extends SceneTree
# Balance simulation: bots with different skill levels fight scenarios.
#   godot --headless --fixed-fps 60 --path <project> -s res://sim.gd -- trials=12
# Bots only use what a player has: the Input actions, and what's visible on
# screen (enemy state, how long until a swing lands, ...).

const SCENARIOS := {
	"1 orc": [["res://orc.tscn", Vector2(70, 0)]],
	"2 orcs": [["res://orc.tscn", Vector2(70, -6)], ["res://orc.tscn", Vector2(-70, 6)]],
	"armored": [["res://armored_orc.tscn", Vector2(70, 0)]],
	"orc+armored": [["res://orc.tscn", Vector2(70, 0)], ["res://armored_orc.tscn", Vector2(-80, 6)]],
	"archer": [["res://skeleton_archer.tscn", Vector2(150, 0)]],
	"orc+archer": [["res://orc.tscn", Vector2(70, 0)], ["res://skeleton_archer.tscn", Vector2(-160, -10)]],
	"armored+archer": [["res://armored_orc.tscn", Vector2(70, 0)], ["res://skeleton_archer.tscn", Vector2(-160, -10)]],
}
# kind, parry/dodge timing jitter (seconds, std dev)
const BOTS := [
	["masher", 0.0],
	["turtle", 0.0],
	["parry", 0.04],
	["parry", 0.08],
	["dodge", 0.04],
	["dodge", 0.08],
]
const MAX_FRAMES := 75 * 60
const REACTION := 0.15   # a bot only notices a wind-up this long after it starts

var knight: Node2D
var enemies: Array = []
var kind := ""
var jitter := 0.0
var now := 0.0
var frame := 0
var rng := RandomNumberGenerator.new()
var down := {}        # action -> currently pressed by us
var tap_left := {}    # action -> frames left to hold a tap
var plan := {}        # enemy instance id -> {at: float, done: bool}
var block_until := 0.0
var ov := {}                 # tuning overrides from the command line (key=value)
var knight_poise_base := {}  # original poise_damage of the knight's attacks

func _initialize() -> void:
	var trials := 12
	for arg in OS.get_cmdline_user_args():
		var k: String = arg.get_slice("=", 0)
		var v: float = float(arg.get_slice("=", 1))
		if k == "trials":
			trials = int(v)
		else:
			ov[k] = v
	if not ov.is_empty():
		print("overrides: ", ov)
	await run(trials)
	quit()

func run(trials: int) -> void:
	await process_frame
	print("%-12s %-12s %6s %8s %8s %8s" % ["bot", "scenario", "wins", "avg hp", "avg sec", "parries"])
	for b in BOTS:
		for sc in SCENARIOS:
			var wins := 0
			var hp_sum := 0.0
			var t_sum := 0.0
			var parries := 0
			for i in trials:
				var r: Dictionary = await fight(b[0], b[1], sc, i + 1)
				wins += 1 if r.won else 0
				hp_sum += r.hp
				t_sum += r.seconds
				parries += r.parries
			var label: String = b[0] if b[1] == 0.0 else "%s %dms" % [b[0], int(b[1] * 1000)]
			print("%-12s %-12s %3d/%-2d %8.0f %8.1f %8.1f" % [label, sc, wins, trials, hp_sum / trials, t_sum / trials, float(parries) / trials])

# ---------------------------------------------------------------- one fight

func fight(bot_kind: String, bot_jitter: float, scenario: String, trial_seed: int) -> Dictionary:
	kind = bot_kind
	jitter = bot_jitter
	seed(trial_seed)
	rng.seed = trial_seed
	plan.clear()
	down.clear()
	tap_left.clear()
	block_until = 0.0
	var arena := Node2D.new()
	root.add_child(arena)
	knight = load("res://Knight.tscn").instantiate()
	apply_knight_overrides()
	arena.add_child(knight)
	enemies.clear()
	for e in SCENARIOS[scenario]:
		var n: Node2D = load(e[0]).instantiate()
		apply_overrides(n, e[0])
		n.position = e[1]
		arena.add_child(n)
		enemies.append(n)
	await physics_frame
	await physics_frame
	var parries := 0
	var last_state: int = knight.state
	var won := false
	frame = 0
	while frame < MAX_FRAMES:
		now = frame / 60.0
		think()
		apply_inputs()
		await physics_frame
		frame += 1
		# count parries: knight went BLOCK -> ATTACK without taking damage
		if knight.state == knight.State.ATTACK and last_state == knight.State.BLOCK:
			parries += 1
		last_state = knight.state
		if knight.state == knight.State.DEAD:
			break
		if living().is_empty():
			won = true
			break
	var hp := maxi(knight.health, 0) if won or knight.state != knight.State.DEAD else 0
	for a in down.keys():
		Input.action_release(a)
	arena.queue_free()
	Engine.time_scale = 1.0
	await physics_frame
	await physics_frame
	return {"won": won, "hp": hp, "seconds": frame / 60.0, "parries": parries}

func living() -> Array:
	return enemies.filter(func(e): return is_instance_valid(e) and e.state != e.State.DEAD)

func nearest() -> Node2D:
	var best: Node2D = null
	for e in living():
		if best == null or e.global_position.distance_to(knight.global_position) < best.global_position.distance_to(knight.global_position):
			best = e
	return best

# ------------------------------------------------------------------- inputs

func press(action: String, on := true) -> void:
	down[action] = on

func tap(action: String, frames_held := 2) -> void:
	tap_left[action] = frames_held

func apply_inputs() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "block", "attack_light", "attack_heavy", "dodge"]:
		var want: bool = down.get(a, false) or tap_left.get(a, 0) > 0
		if tap_left.get(a, 0) > 0:
			tap_left[a] -= 1
		if want and not Input.is_action_pressed(a):
			Input.action_press(a)
		elif not want and Input.is_action_pressed(a):
			Input.action_release(a)
	for a in ["move_left", "move_right", "move_up", "move_down", "block"]:
		down[a] = false

func steer(dir: Vector2) -> void:
	if dir.x > 0.3: press("move_right")
	elif dir.x < -0.3: press("move_left")
	if dir.y > 0.3: press("move_down")
	elif dir.y < -0.3: press("move_up")

# --------------------------------------------------------------------- brains

func think() -> void:
	match kind:
		"masher":
			attack_nearest(7)
		"turtle":
			press("block")
		"parry", "dodge":
			skilled()

# Walk up to the nearest enemy, face it, and tap an attack every `cadence` frames.
# `adaptive` bots switch to the heavy attack (it breaks a raised shield) when
# the target has its guard up.
func attack_nearest(cadence: int, adaptive := false) -> void:
	var t := nearest()
	if t == null:
		return
	var d := t.global_position - knight.global_position
	var facing_axis_x: bool = abs(d.x) >= abs(d.y)
	var want_dir: String = ("right" if d.x > 0 else "left") if facing_axis_x else ("down" if d.y > 0 else "up")
	var in_reach: bool = abs(d.y) <= 8.0 and abs(d.x) <= 30.0 if facing_axis_x else abs(d.x) <= 8.0 and abs(d.y) <= 30.0
	if knight.state == knight.State.FREE and not in_reach:
		steer(d)   # close the gap
		return
	if knight.state == knight.State.FREE and knight.last_direction != want_dir:
		steer(d.normalized() * 1.0)   # one frame of steering turns the knight toward it
		return
	if frame % cadence == 0:
		tap("attack_heavy" if adaptive and t.get("is_guarding") == true else "attack_light")

func attack_speed(e: Node2D) -> float:
	return e.anim.sprite_frames.get_animation_speed(e.current_attack.anim) * e.current_attack.anim_speed

# Seconds until this enemy's melee swing connects, or -1 if it isn't a threat.
func time_to_impact(e: Node2D) -> float:
	if e.current_attack == null or e.current_attack.type != AttackData.Type.MELEE:
		return -1.0
	if e.state == e.State.WINDUP:
		return e.windup_left + e.current_attack.hit_frame / attack_speed(e)
	if e.state == e.State.ATTACK and e.anim.frame < e.current_attack.hit_frame:
		return (e.current_attack.hit_frame - e.anim.frame - 0.5) / attack_speed(e)
	return -1.0

func enemy_arrows() -> Array:
	return knight.get_parent().get_children().filter(func(c): return c is Area2D and "from_enemy" in c and c.from_enemy)

func skilled() -> void:
	var soonest := 99.0
	# 1) melee swings the bot can see coming
	for e in living():
		if e.global_position.distance_to(knight.global_position) > 48.0:
			continue
		var t := time_to_impact(e)
		if t < 0.0:
			continue
		soonest = minf(soonest, t)
		var id: int = e.get_instance_id()
		if plan.has(id):
			continue
		# Does the player notice yet? (reaction time after the wind-up starts)
		if e.state == e.State.WINDUP and (e.current_attack.windup_time - e.windup_left) < REACTION:
			continue
		# A player learns which attacks can't be parried and dodges those.
		var dodge: bool = kind == "dodge" or not e.current_attack.parryable
		var lead: float = (knight.DODGE_IFRAMES * 0.5) if dodge else (knight.parry_window() * 0.5)
		plan[id] = {"at": now + t - lead + rng.randfn(0.0, jitter), "done": false, "target": e, "dodge": dodge, "perp": false}
	# 2) arrows flying at the knight
	for ar in enemy_arrows():
		var id: int = ar.get_instance_id()
		if plan.has(id):
			continue
		var to_k: Vector2 = knight.global_position - ar.global_position
		var dist := to_k.length()
		if dist > 140.0 or ar.direction.dot(to_k.normalized()) < 0.95:
			continue   # not heading for us
		var t: float = dist / ar.speed
		soonest = minf(soonest, t)
		var dodge: bool = kind == "dodge"
		var lead: float = (knight.DODGE_IFRAMES * 0.5) if dodge else (knight.parry_window() * 0.5)
		plan[id] = {"at": now + t - lead + rng.randfn(0.0, jitter), "done": false, "target": ar, "dodge": dodge, "perp": true}

	# execute any plan whose time has come
	for id in plan.keys():
		var p: Dictionary = plan[id]
		var tgt = p.target   # untyped on purpose: it may have been freed
		if not is_instance_valid(tgt):
			plan.erase(id)
			continue
		if p.done:
			if "state" in tgt and tgt.state in [tgt.State.FREE, tgt.State.STAGGER, tgt.State.DEAD, tgt.State.GUARD]:
				plan.erase(id)   # that swing is over; allow planning the next one
			continue
		if now >= p.at and knight.state in [knight.State.FREE, knight.State.BLOCK]:
			p.done = true
			if p.dodge:
				var away: Vector2 = knight.global_position - tgt.global_position
				if p.perp:
					away = Vector2(-tgt.direction.y, tgt.direction.x)   # sidestep the arrow
					if rng.randf() < 0.5:
						away = -away
				steer(away)
				tap("dodge")
			else:
				block_until = now + 0.5
	if now < block_until:
		press("block")
		return
	# Only start a swing when nothing is about to land.
	if soonest < 0.65:
		return
	attack_nearest(7, true)

func apply_overrides(n: Node2D, scene_path: String) -> void:
	var p := "o_"
	if scene_path.contains("armored"):
		p = "a_"
	elif scene_path.contains("archer"):
		p = "r_"
	if ov.has(p + "poise"): n.max_poise = ov[p + "poise"]
	if ov.has(p + "cd"): n.attack_cooldown = ov[p + "cd"]
	if ov.has(p + "hp"): n.max_health = int(ov[p + "hp"])
	if ov.has(p + "speed"): n.speed = ov[p + "speed"]
	if ov.has(p + "heavy"): n.heavy_chance = ov[p + "heavy"]
	if ov.has(p + "ldmg"): n.light_attack.damage = int(ov[p + "ldmg"])
	if ov.has(p + "hdmg"): n.heavy_attack.damage = int(ov[p + "hdmg"])
	if ov.has(p + "lwind"): n.light_attack.windup_time = ov[p + "lwind"]
	if ov.has(p + "hwind"): n.heavy_attack.windup_time = ov[p + "hwind"]
	if ov.has(p + "pspeed"): n.light_attack.projectile_speed = ov[p + "pspeed"]
	if ov.has(p + "spec"): n.special_chance = ov[p + "spec"]
	if ov.has(p + "specb"): n.special_chance_vs_block = ov[p + "specb"]
	if ov.has(p + "speccd"): n.special_cooldown = ov[p + "speccd"]
	if ov.has(p + "guard"): n.guard_chance = ov[p + "guard"]
	if ov.has(p + "smash") and n.special_attack != null: n.special_attack.damage = int(ov[p + "smash"])

func apply_knight_overrides() -> void:
	if ov.has("dex") or ov.has("pow") or ov.has("vit"):
		knight.stats = Stats.new()
		knight.stats.dexterity = int(ov.get("dex", 10))
		knight.stats.power = int(ov.get("pow", 10))
		knight.stats.vitality = int(ov.get("vit", 10))
	var atk: Array = [knight.light_combo[0], knight.light_combo[1], knight.heavy_attack]
	if knight_poise_base.is_empty():
		for a in atk:
			knight_poise_base[a] = a.poise_damage
	if ov.has("kp"):
		for a in atk:
			a.poise_damage = knight_poise_base[a] * ov["kp"]
