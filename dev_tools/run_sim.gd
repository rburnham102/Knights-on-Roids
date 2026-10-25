extends SceneTree
# Run simulation: bots play whole runs (rooms, upgrades, doors) of run.tscn.
#   godot --headless --fixed-fps 60 --path . -s res://run_sim.gd -- runs=8
# The bot logic below is the same as sim.gd's (it only uses inputs and what is
# visible on screen); the new part is walking the run loop.

const BOTS := [
	["masher", 0.0],
	["turtle", 0.0],
	["parry", 0.04],
	["parry", 0.08],
	["dodge", 0.04],
	["dodge", 0.08],
]
const MAX_FRAMES := 12 * 60 * 60     # a run longer than 12 minutes counts as stuck
const ROOM_TIMEOUT := 120 * 60       # ...and so does a room that takes over 2 minutes
const REACTION := 0.15

var knight: Node2D
var mgr: Node
var actors: Node2D
var kind := ""
var jitter := 0.0
var now := 0.0
var frame := 0
var rng := RandomNumberGenerator.new()
var down := {}
var tap_left := {}
var plan := {}
var block_until := 0.0
var trace := false
var ov := {}
var stuck_frames := 0
var detour_frames := 0
var detour_dir := Vector2.ZERO
var last_steer := Vector2.RIGHT
var stuck_ref_pos := Vector2.ZERO
var stuck_ref_frame := 0

func _initialize() -> void:
	var runs := 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			runs = int(arg.get_slice("=", 1))
		elif arg == "trace":
			trace = true
		elif arg.contains("="):
			ov[arg.get_slice("=", 0)] = float(arg.get_slice("=", 1))
	if ov.has("base"): EnemyDirector.base_budget = ov["base"]
	if ov.has("per"): EnemyDirector.budget_per_depth = ov["per"]
	if not ov.is_empty():
		print("overrides: ", ov)
	await run(runs)
	quit()

func run(runs: int) -> void:
	await process_frame
	print("%-12s %5s %9s %-26s %7s %7s" % ["bot", "won", "avg rooms", "rooms cleared when it ended", "avg hp", "avg min"])
	for b in BOTS:
		var won := 0
		var cleared_sum := 0
		var hp_sum := 0
		var frames_sum := 0
		var hist := {}
		for i in runs:
			var r: Dictionary = await play_run(b[0], b[1], 1000 + i)
			won += 1 if r.won else 0
			cleared_sum += r.cleared
			hp_sum += r.hp
			frames_sum += r.frames
			hist[r.cleared] = int(hist.get(r.cleared, 0)) + 1
		var label: String = b[0] if b[1] == 0.0 else "%s %dms" % [b[0], int(b[1] * 1000)]
		var keys := hist.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for k in keys:
			parts.append("%d:%d" % [k, hist[k]])
		print("%-12s %2d/%-2d %9.1f %-26s %7.0f %7.1f" % [label, won, runs, float(cleared_sum) / runs, " ".join(parts), float(hp_sum) / runs, float(frames_sum) / runs / 3600.0])

func living() -> Array:
	return actors.get_children().filter(func(c): return "max_poise" in c and c.state != c.State.DEAD)

func nearest() -> Node2D:
	var best: Node2D = null
	for e in living():
		if best == null or e.global_position.distance_to(knight.global_position) < best.global_position.distance_to(knight.global_position):
			best = e
	return best

func pick_upgrade(offered: Array) -> int:
	var best := 0
	var best_score := -1.0
	for i in offered.size():
		var u = offered[i]
		var score := rng.randf() * 0.5
		if u.power + u.dexterity + u.vitality > 0:
			score += 3.0
		elif u.heal > 0:
			score += 2.0 + (2.0 if knight.health < knight.max_health() * 0.5 else 0.0)
		else:
			score += 2.5   # perks
		if score > best_score:
			best_score = score
			best = i
	return best

# ------------------------------------------------------------------ one run

func play_run(bot_kind: String, bot_jitter: float, run_seed: int) -> Dictionary:
	kind = bot_kind
	jitter = bot_jitter
	seed(run_seed)
	rng.seed = run_seed
	plan.clear()
	down.clear()
	tap_left.clear()
	block_until = 0.0
	var scene: Node2D = load("res://run.tscn").instantiate()
	scene.get_node("RunManager").start_seed = run_seed
	if ov.has("heal"): scene.get_node("RunManager").heal_after_room = ov["heal"]
	root.add_child(scene)
	current_scene = scene
	mgr = scene.get_node("RunManager")
	actors = scene.get_node("Actors")
	knight = actors.get_node("Knight")
	var up_screen: Node = scene.get_node("UpgradeScreen")
	await physics_frame
	await physics_frame
	frame = 0
	var last_depth := 0
	var room_start := 0
	while frame < MAX_FRAMES:
		now = frame / 60.0
		if mgr.finished:
			break
		if mgr.run.depth != last_depth:
			last_depth = mgr.run.depth
			plan.clear()
			block_until = 0.0
			room_start = frame
		if frame - room_start > ROOM_TIMEOUT:
			var info := []
			for e in actors.get_children():
				if "max_poise" in e:
					info.append("%s@(%.0f,%.0f) st%d cd%.1f" % [e.scene_file_path.get_file().get_basename(), e.global_position.x, e.global_position.y, e.state, e.cooldown_left])
			print("TIMEOUT %s room d%d K(%.0f,%.0f) st%d hp%d plan=%d | %s" % [kind, mgr.run.depth, knight.global_position.x, knight.global_position.y, knight.state, knight.health, plan.size(), " ".join(info)])
			break
		if trace and frame % 90 == 0 and frame > 0:
			var info := []
			for e in actors.get_children():
				if "max_poise" in e:
					info.append("%s@(%.0f,%.0f) st%d pm=%d player=%s vel=(%.0f,%.0f) a=%.2f" % [e.name.substr(0, 6), e.global_position.x, e.global_position.y, e.state, e.process_mode, str(is_instance_valid(e.player)), e.velocity.x, e.velocity.y, e.modulate.a])
			print("f%d d%d Kpm=%d Kvel=(%.0f,%.0f) down=%s K(%.0f,%.0f) st%d hp%d chg=%s up=%s door=%s left=%d | %s" % [frame, mgr.run.depth, knight.process_mode, knight.velocity.x, knight.velocity.y, str(down), knight.global_position.x, knight.global_position.y, knight.state, knight.health, mgr.changing_room, mgr.awaiting_upgrade, mgr.room.exit_door.is_open if mgr.room else "-", mgr.enemies_left, " ".join(info)])
		if trace and frame - room_start > ROOM_TIMEOUT - 200 and frame % 15 == 0:
			print("STUCK? f%d K(%.1f,%.1f) vel(%.0f,%.0f) st%d stuck=%d detour=%d dir=(%.1f,%.1f) steer=(%.0f,%.0f) door=(%.0f,%.0f)" % [frame, knight.global_position.x, knight.global_position.y, knight.velocity.x, knight.velocity.y, knight.state, stuck_frames, detour_frames, detour_dir.x, detour_dir.y, last_steer.x, last_steer.y, mgr.room.exit_door.global_position.x, mgr.room.exit_door.global_position.y])
		if mgr.awaiting_upgrade:
			up_screen.choose(pick_upgrade(up_screen.offered))
		elif mgr.changing_room or mgr.room == null:
			pass
		elif mgr.room.exit_door.is_open:
			steer(mgr.room.exit_door.global_position - knight.global_position)
		else:
			think()
		var wants_move: bool = down.get("move_left", false) or down.get("move_right", false) or down.get("move_up", false) or down.get("move_down", false)
		apply_inputs()
		await physics_frame
		frame += 1
		# like a player would: if pushing for half a second and getting nowhere, step around it
		if detour_frames > 0:
			detour_frames -= 1
		if wants_move and knight.state == knight.State.FREE:
			if frame - stuck_ref_frame >= 30:
				if knight.global_position.distance_to(stuck_ref_pos) < 10.0 and detour_frames == 0:
					detour_frames = 45
					detour_dir = last_steer.normalized().orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
				stuck_ref_frame = frame
				stuck_ref_pos = knight.global_position
		else:
			stuck_ref_frame = frame
			stuck_ref_pos = knight.global_position
	var won: bool = mgr.finished and mgr.run.rooms_cleared >= RunState.RUN_LENGTH and not knight.is_dead
	var result := {"won": won, "cleared": mgr.run.rooms_cleared, "hp": maxi(knight.health, 0), "frames": frame}
	for a in ["move_left", "move_right", "move_up", "move_down", "block", "attack_light", "attack_heavy", "dodge"]:
		Input.action_release(a)
	paused = false
	Engine.time_scale = 1.0
	scene.queue_free()
	await physics_frame
	await physics_frame
	return result

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
	last_steer = dir
	if detour_frames > 0:
		dir = dir.normalized() + detour_dir * 1.5   # sidestep whatever we're stuck on
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

