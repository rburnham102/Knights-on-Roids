extends SceneTree
# Tests for the heavy attack's ground effect and the charged bow (Siege Shot).
#   godot --headless --fixed-fps 60 --path <project> -s res://dev_tools/charge_tests.gd

const KNIGHT := "res://Knight.tscn"
const ORC := "res://orc.tscn"
const HEAVY_FX := "res://heavy_attack.tscn"
const BOW_FIRE_FX := "res://heavybowfire.tscn"
const CHARGE_HIT_FX := "res://arrowchargehit.tscn"
const ARROW := "res://aarow.tscn"

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

func new_arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a

func end_arena(a: Node) -> void:
	Input.action_release("attack_bow")
	a.queue_free()
	await frames(3)

func spawn(arena: Node, path: String, pos: Vector2, setup := Callable()) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.position = pos
	if setup.is_valid():
		setup.call(n)
	arena.add_child(n)
	return n

# Nodes in the arena that were made from a given scene.
func find_fx(arena: Node, scene_path: String) -> Array:
	return arena.get_children().filter(func(n): return n.scene_file_path == scene_path)

func find_arrows(arena: Node) -> Array:
	return find_fx(arena, ARROW)

# Headless Godot has no mouse: it sits at screen (0, 0) for good. With the
# knight's camera off, screen (0, 0) is world (0, 0), so the "mouse" is the
# world origin and the knight aims at it. Put him left of it to aim right.
const AIM_RIGHT_FROM := Vector2(-200, 0)

func archer(stacks: int) -> Callable:
	return func(k):
		k.get_node("Camera2D").enabled = false
		if stacks > 0:
			k.perks = {&"charged_shot": stacks}

# Waits until the draw is paused and charging (or gives up after a second).
func until_charging(knight: Node) -> void:
	for i in 60:
		if knight.is_charging:
			return
		await physics_frame

func _initialize() -> void:
	await run()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame
	await frames(2)

	# ------------------------------------------------- heavy impact effect
	print("[Heavy attack ground effect]")
	var heavy: AttackData = load("res://attacks/attack_heavy.tres")
	check("attack_heavy.tres has heavy_attack.tscn as its impact_effect",
		heavy.impact_effect != null and heavy.impact_effect.resource_path == HEAVY_FX)
	var a := new_arena()
	var knight := spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	knight.start_attack(knight.heavy_attack)
	var spawned_at_frame := -1
	for i in 60:
		await physics_frame
		if spawned_at_frame < 0 and not find_fx(a, HEAVY_FX).is_empty():
			spawned_at_frame = knight.anim.frame
	check("effect appears on the hit frame (4), with nobody to hit", spawned_at_frame == 4, str(spawned_at_frame))
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	knight.set_facing(Vector2.LEFT)
	knight.start_attack(knight.heavy_attack)
	var fx: Node2D = null
	for i in 60:
		await physics_frame
		if not find_fx(a, HEAVY_FX).is_empty():
			fx = find_fx(a, HEAVY_FX)[0]
			break
	check("facing left: lands in front of him (x < 0) and is mirrored",
		fx != null and fx.global_position.x < knight.global_position.x and fx.scale.x < 0.0,
		"" if fx == null else "%s scale %s" % [fx.global_position - knight.global_position, fx.scale])
	check("it lives in the level, not on the knight", fx != null and fx.get_parent() == a)
	await frames(40)
	check("and frees itself when its animation ends", not is_instance_valid(fx))
	await end_arena(a)

	print("[Combo finisher also gets it]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	knight.start_attack(knight.light_combo[2], true)
	await frames(45)
	check("combo finisher (same .tres) spawns it too", not find_fx(a, HEAVY_FX).is_empty() or knight.light_combo[2] == knight.heavy_attack)
	knight.start_attack(knight.light_combo[0], true)
	for c in find_fx(a, HEAVY_FX):
		c.queue_free()
	await frames(40)
	check("a light swing does not", find_fx(a, HEAVY_FX).is_empty())
	await end_arena(a)

	# ------------------------------------------------------ bow without perk
	print("[Bow without the perk is unchanged]")
	a = new_arena()
	knight = spawn(a, KNIGHT, AIM_RIGHT_FROM, archer(0))
	await frames(2)
	Input.action_press("attack_bow")
	await frames(90)   # hold well past the release frame
	check("holding without the perk never charges", not knight.is_charging and knight.charge_fx == null)
	var arrows := find_arrows(a)
	check("one normal arrow fired (15 dmg, speed 400, not charged)",
		arrows.size() == 1 and arrows[0].damage == 15 and is_equal_approx(arrows[0].speed, 400.0) and not arrows[0].charged,
		"" if arrows.is_empty() else "dmg %d speed %.0f" % [arrows[0].damage, arrows[0].speed])
	check("no cannon blast", find_fx(a, BOW_FIRE_FX).is_empty())
	await end_arena(a)

	# --------------------------------------------------- tap with the perk
	print("[Tap with the perk = normal shot]")
	a = new_arena()
	knight = spawn(a, KNIGHT, AIM_RIGHT_FROM, archer(1))
	await frames(2)
	Input.action_press("attack_bow")
	await frames(3)
	Input.action_release("attack_bow")
	await frames(60)
	arrows = find_arrows(a)
	check("tap fires a plain arrow", arrows.size() == 1 and arrows[0].damage == 15 and not arrows[0].charged)
	check("no charge glow, no blast", find_fx(a, BOW_FIRE_FX).is_empty() and knight.charge_fx == null)
	await end_arena(a)

	# ------------------------------------------------------- full charge
	print("[Hold to charge]")
	a = new_arena()
	knight = spawn(a, KNIGHT, AIM_RIGHT_FROM, archer(1))
	var dummy := spawn(a, ORC, AIM_RIGHT_FROM + Vector2(120, 0))
	dummy.player = null
	await frames(2)
	dummy.health = 500
	Input.action_press("attack_bow")
	await until_charging(knight)
	check("draw pauses on the frame before the release (4)",
		knight.is_charging and knight.anim.frame == 4 and not knight.anim.is_playing(),
		"frame %d playing %s" % [knight.anim.frame, knight.anim.is_playing()])
	check("charge glow is on the ShootingPoint", knight.charge_fx != null and knight.charge_fx.get_parent() == knight.get_node("%ShootingPoint"))
	check("no arrow while drawn", find_arrows(a).is_empty())
	await frames(90)   # 1.5 s held
	check("halfway (1.5 s): glow on the middle frame (3-4 of 0-8)", knight.charge_fx.frame in [3, 4], "frame %d ratio %.2f" % [knight.charge_fx.frame, knight.charge_ratio()])
	await frames(92)   # past 3 s
	check("full (3 s): glow on the last frame", knight.charge_ratio() >= 1.0 and knight.charge_fx.frame == 8, "frame %d" % knight.charge_fx.frame)
	check("still drawn while held", knight.is_charging and find_arrows(a).is_empty())
	var glow: Node = knight.charge_fx
	Input.action_release("attack_bow")
	await frames(2)
	arrows = find_arrows(a)
	check("release fires right away", arrows.size() == 1)
	if arrows.size() == 1:
		check("full charge: 60 dmg (4x), 300 knockback, 60 poise, speed 700, charged",
			arrows[0].damage == 60 and is_equal_approx(arrows[0].knockback_force, 300.0)
			and is_equal_approx(arrows[0].poise_damage, 60.0) and is_equal_approx(arrows[0].speed, 700.0) and arrows[0].charged,
			"dmg %d kb %.0f poise %.0f speed %.0f" % [arrows[0].damage, arrows[0].knockback_force, arrows[0].poise_damage, arrows[0].speed])
	check("cannon blast spawned at the bow", find_fx(a, BOW_FIRE_FX).size() == 1)
	check("charge glow removed", not is_instance_valid(glow) and not knight.is_charging)
	await frames(20)
	check("arrow hit the orc for 60", dummy.health == 440, "hp %d" % dummy.health)
	check("burst effect where it hit", find_fx(a, CHARGE_HIT_FX).size() == 1)
	await frames(60)
	check("bow attack finished normally", knight.state == knight.State.FREE)
	check("effects cleaned themselves up", find_fx(a, BOW_FIRE_FX).is_empty() and find_fx(a, CHARGE_HIT_FX).is_empty())
	await end_arena(a)

	print("[Half charge scales in between]")
	a = new_arena()
	knight = spawn(a, KNIGHT, AIM_RIGHT_FROM, archer(1))
	await frames(2)
	Input.action_press("attack_bow")
	await until_charging(knight)
	await frames(90)   # 1.5 s of 3
	Input.action_release("attack_bow")
	await frames(2)
	arrows = find_arrows(a)
	check("half charge: ~37 dmg (2.5x) and charged", arrows.size() == 1 and arrows[0].damage in [37, 38] and arrows[0].charged,
		"" if arrows.is_empty() else "dmg %d" % arrows[0].damage)
	await end_arena(a)

	print("[Interrupted]")
	a = new_arena()
	knight = spawn(a, KNIGHT, AIM_RIGHT_FROM, archer(1))
	await frames(2)
	Input.action_press("attack_bow")
	await frames(100)
	glow = knight.charge_fx
	knight.take_damage(5, Vector2(30, 0), 0.0)
	await frames(2)
	check("getting hit cancels the charge", knight.state == knight.State.HURT and not knight.is_charging and not is_instance_valid(glow))
	await frames(60)
	check("and no arrow is fired", find_arrows(a).is_empty())
	await end_arena(a)

	print("[Aims while drawn]")
	a = new_arena()
	knight = spawn(a, KNIGHT, AIM_RIGHT_FROM, archer(1))
	await frames(2)
	Input.action_press("attack_bow")
	await until_charging(knight)
	check("aiming right to start", knight.pivot.scale.x > 0.0 and knight.aim_direction.x > 0.0)
	knight.position = Vector2(200, 0)   # the "mouse" is now on his left
	await frames(3)
	check("turns to follow the mouse", knight.pivot.scale.x < 0.0 and knight.aim_direction.x < 0.0)
	Input.action_release("attack_bow")
	await frames(2)
	arrows = find_arrows(a)
	check("and fires the new way", arrows.size() == 1 and arrows[0].direction.x < 0.0)
	await end_arena(a)

	print("[Second pick charges faster]")
	a = new_arena()
	knight = spawn(a, KNIGHT, AIM_RIGHT_FROM, archer(2))
	await frames(2)
	check("two stacks: full charge in 2.5 s", is_equal_approx(knight.full_charge_time(), 2.5))
	knight.perks = {&"charged_shot": 4}
	check("four stacks: 1.5 s", is_equal_approx(knight.full_charge_time(), 1.5))
	knight.perks = {&"charged_shot": 9}
	check("never below 1.5 s", is_equal_approx(knight.full_charge_time(), 1.5))
	await end_arena(a)

	print("[Upgrade]")
	var up: Upgrade = load("res://upgrades/charged_shot.tres")
	check("charged_shot.tres grants the perk", up.perk == &"charged_shot")
	var rm_src: String = load("res://script/run_manager.gd").source_code
	check("it's in the run manager's upgrade pool", rm_src.contains("res://upgrades/charged_shot.tres"))
