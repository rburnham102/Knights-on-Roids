extends SceneTree
# Step-1 tests: state machine, combo chain, Stats effects, AttackData values, HUD.
#   godot --headless --fixed-fps 60 --path <project> -s res://step1_tests.gd

const KNIGHT := "res://Knight.tscn"
const ORC := "res://orc.tscn"
const HUD := "res://hud.tscn"

var passed := 0
var failed := 0

func check(label: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print(("  PASS  " if ok else "  FAIL  "), label, "  ", detail)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)

func new_arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a

func end_arena(a: Node) -> void:
	a.queue_free()
	await frames(3)

func spawn(arena: Node, path: String, pos: Vector2, setup := Callable()) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.position = pos
	if setup.is_valid():
		setup.call(n)   # runs before _ready, like setting an Inspector value
	arena.add_child(n)
	return n

func _initialize() -> void:
	await run()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame
	await frames(2)

	# ------------------------------------------------------------ Stats math
	print("[Stats math]")
	var s := Stats.new()
	check("all-10 stats give multiplier 1.0 everywhere",
		is_equal_approx(s.damage_mult(), 1.0) and is_equal_approx(s.knockback_mult(), 1.0)
		and is_equal_approx(s.speed_mult(), 1.0) and is_equal_approx(s.lunge_mult(), 1.0)
		and is_equal_approx(s.combo_window_mult(), 1.0) and is_equal_approx(s.health_mult(), 1.0))
	s.power = 20
	s.dexterity = 20
	s.vitality = 20
	check("power 20 -> damage x1.5, knockback x1.5", is_equal_approx(s.damage_mult(), 1.5) and is_equal_approx(s.knockback_mult(), 1.5))
	check("dexterity 20 -> speed x1.3, lunge x1.5, combo window x1.4",
		is_equal_approx(s.speed_mult(), 1.3) and is_equal_approx(s.lunge_mult(), 1.5) and is_equal_approx(s.combo_window_mult(), 1.4))
	check("vitality 20 -> health x1.5", is_equal_approx(s.health_mult(), 1.5))
	s.power = 1
	check("stat 1 stays positive (power 1 -> damage x0.55)", is_equal_approx(s.damage_mult(), 0.55))

	# --------------------------------------------------- AttackData values
	print("[AttackData files match the old dictionary]")
	var a := new_arena()
	var knight := spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	var want := [
		["attack_light", 10, 2, 120.0, 0.0, 0.0, 0],
		["attack_light2", 12, 2, 150.0, 1.0, 140.0, 0],
		["attack_heavy", 25, 4, 250.0, 3.0, 140.0, 0],
	]
	check("light_combo has 3 swings", knight.light_combo.size() == 3)
	for i in 3:
		var d: AttackData = knight.light_combo[i]
		var w: Array = want[i]
		check("combo[%d] %s" % [i, w[0]],
			d.anim == w[0] and d.damage == w[1] and d.hit_frame == w[2] and is_equal_approx(d.knockback, w[3])
			and is_equal_approx(d.shake, w[4]) and is_equal_approx(d.lunge, w[5]) and d.type == w[6])
	var hv: AttackData = knight.heavy_attack
	check("heavy slot holds attack_heavy", hv.anim == &"attack_heavy" and hv.damage == 25)
	var bow: AttackData = knight.ranged_attack
	check("ranged slot holds attack_bow (ranged, dmg 15, frame 5)",
		bow.anim == &"attack_bow" and bow.type == AttackData.Type.RANGED and bow.damage == 15 and bow.hit_frame == 5 and is_equal_approx(bow.knockback, 100.0))
	await end_arena(a)

	# ---------------------------------------------------------- state machine
	print("[State machine]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	check("starts FREE", knight.state == knight.State.FREE)
	check("starts with 100 health, 60 guard", knight.health == 100 and is_equal_approx(knight.guard, 60.0))
	await tap("attack_light")
	check("light tap -> ATTACK with the first combo swing", knight.state == knight.State.ATTACK and knight.current_attack == knight.light_combo[0])
	await frames(70)
	check("swing finished -> FREE, attack cleared", knight.state == knight.State.FREE and knight.current_attack == null)
	check("hitbox is off after the swing", knight.hitbox_shape.disabled)
	Input.action_press("block")
	await frames(3)
	check("hold block -> BLOCK (block anim)", knight.state == knight.State.BLOCK and knight.anim.animation == &"block")
	Input.action_release("block")
	await frames(3)
	check("release block -> FREE", knight.state == knight.State.FREE)
	await end_arena(a)

	print("[Damage interrupts an attack]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	await tap("attack_light")
	while knight.anim.frame < 3:   # wait until past the hit frame (frame 2): hitbox is live
		await physics_frame
	await physics_frame
	check("hitbox live mid-swing", not knight.hitbox_shape.disabled)
	knight.take_damage(5, Vector2(30, 0), 100.0)
	await frames(2)
	check("hit mid-swing -> HURT, attack cancelled", knight.state == knight.State.HURT and knight.current_attack == null)
	check("hitbox switched off by the exit hook", knight.hitbox_shape.disabled)
	check("combo state reset", knight.combo_index == 0 and knight.combo_queued == false)
	await frames(10)
	knight.take_damage(5, Vector2(30, 0), 0.0)
	check("second hit while hurt restarts the hurt anim", knight.state == knight.State.HURT and knight.anim.frame == 0)
	await frames(70)
	check("hurt ends -> FREE", knight.state == knight.State.FREE)
	check("health 100 -> 90 after two 5-damage hits", knight.health == 90, "hp %d" % knight.health)
	await end_arena(a)

	print("[Guard break]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("block")
	await frames(20)   # held well past the parry window, so this is a plain block
	knight.guard = 5.0
	var blocked: Combat.HitResult = knight.take_damage(20, Vector2(30, 0), 100.0)
	Input.action_release("block")
	check("guard break lets damage through (returns false)", blocked == Combat.HitResult.HIT)
	check("leftover 15 damage taken", knight.health == 85, "hp %d" % knight.health)
	check("guard 0, broken, knight HURT", knight.guard == 0.0 and knight.guard_broken and knight.state == knight.State.HURT)
	await end_arena(a)

	print("[Death]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	var got: Array = []
	knight.health_changed.connect(func(c, m): got.append([c, m]))
	knight.take_damage(1000, Vector2(18, 0), 0.0)
	await frames(2)
	var orc := spawn(a, ORC, Vector2(18, 0))   # arrives after the knight is already dead
	orc.heavy_chance = 0.0
	check("lethal hit -> DEAD, is_dead true", knight.state == knight.State.DEAD and knight.is_dead)
	check("health_changed signal sent (0 / 100)", got.size() == 1 and got[0] == [0, 100], str(got))
	var hp_before: int = knight.health
	await frames(2)
	check("dead knight ignores further damage", knight.take_damage(10) == Combat.HitResult.HIT and knight.health == hp_before)
	await frames(100)
	check("orc never attacks a dead knight", not orc.is_attacking and knight.state == knight.State.DEAD)
	await end_arena(a)

	# ----------------------------------------------------------- combo chain
	print("[Combo chain via input]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	var dummy := spawn(a, ORC, Vector2(26, 0))
	dummy.player = null
	await frames(2)
	dummy.health = 500
	var seen: Array = []
	await tap("attack_light")
	for i in 150:
		if i == 12:
			await tap("attack_light")   # buffered during swing 1 (past its hit frame)
		if i == 50:
			await tap("attack_light")   # buffered during swing 2
		await physics_frame
		if knight.current_attack != null and (seen.is_empty() or seen[-1] != knight.current_attack.anim):
			seen.append(knight.current_attack.anim)
	check("swings chain light -> light2 -> heavy", seen == [&"attack_light", &"attack_light2", &"attack_heavy"], str(seen))
	check("all three swings landed (10+12+25 = 47)", dummy.health == 500 - 47, "dummy hp %d" % dummy.health)
	check("chain wrapped back to start", knight.combo_index == 0)
	await end_arena(a)

	# ------------------------------------------------- stats in the game
	print("[Stats take effect]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.power = 20)
	dummy = spawn(a, ORC, Vector2(24, 0))
	dummy.player = null
	await frames(2)
	dummy.health = 500
	knight.start_attack(knight.light_combo[0], false)
	check("power 20: knockback 180", is_equal_approx(knight.attack_knockback(), 180.0), str(knight.attack_knockback()))
	await frames(60)
	check("power 20: light hit does 15 damage", dummy.health == 485, "dummy hp %d" % dummy.health)
	await end_arena(a)

	var dist := {}
	for dex in [10, 20]:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.dexterity = dex)
		await frames(2)
		Input.action_press("move_right")
		await frames(30)
		Input.action_release("move_right")
		dist[dex] = knight.position.x
		await end_arena(a)
	check("dexterity 20 walks 1.3x as far as dexterity 10", is_equal_approx(dist[20] / dist[10], 1.3), "%.1f vs %.1f px" % [dist[20], dist[10]])

	var lunge := {}
	var window := {}
	for dex in [10, 20]:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.dexterity = dex)
		await frames(2)
		knight.start_attack(knight.light_combo[1], true)   # light2 has a 140 lunge
		lunge[dex] = knight.lunge_velocity.length()
		knight.combo_index = 2   # pretend we're mid-chain so finishing opens the combo window
		for i in 200:
			await physics_frame
			if knight.state == knight.State.FREE:
				break
		window[dex] = knight.combo_window   # read the moment the swing ends
		await end_arena(a)
	check("dexterity 20: lunge speed 210 (vs 140)", is_equal_approx(lunge[10], 140.0) and is_equal_approx(lunge[20], 210.0), "%s / %s" % [lunge[10], lunge[20]])
	check("dexterity 20: combo window 0.49s vs 0.35s", window[20] > 0.45 and window[10] < 0.36 and window[10] > 0.30, "%.2f vs %.2f s" % [window[20], window[10]])

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.vitality = 20)
	await frames(2)
	check("vitality 20: 150 max health, starts full", knight.max_health() == 150 and knight.health == 150)
	await end_arena(a)

	# ------------------------------------------------------------------- HUD
	print("[HUD]")
	for hud_first in [false, true]:
		var label := "HUD added %s the knight" % ("BEFORE" if hud_first else "AFTER")
		a = new_arena()
		var hud: CanvasLayer
		if hud_first:
			hud = load(HUD).instantiate()
			a.add_child(hud)
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		if not hud_first:
			hud = load(HUD).instantiate()
			a.add_child(hud)
		hud.set_version("V9.9.9")
		await frames(3)
		check(label + ": starts at 100 / 100 and guard 60", hud.health_bar.value == 100 and hud.health_label.text == "100 / 100" and hud.guard_bar.value == 60)
		check(label + ": shows the version string", hud.version_label.text == "V9.9.9")
		knight.take_damage(8, Vector2(30, 0), 0.0)
		check(label + ": health bar follows damage (92 / 100)", hud.health_bar.value == 92 and hud.health_label.text == "92 / 100")
		await frames(70)
		Input.action_press("block")
		await frames(20)
		knight.take_damage(8, Vector2(30, 0), 0.0)
		Input.action_release("block")
		check(label + ": guard bar follows a blocked hit (52)", is_equal_approx(hud.guard_bar.value, 52.0), str(hud.guard_bar.value))
		await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.vitality = 20)
	var hud2: CanvasLayer = load(HUD).instantiate()
	a.add_child(hud2)
	await frames(3)
	check("HUD shows 150 / 150 for vitality 20", hud2.health_label.text == "150 / 150" and hud2.health_bar.max_value == 150)
	await end_arena(a)
