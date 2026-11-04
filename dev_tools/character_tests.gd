extends SceneTree
# Character tests: the select screen, the three new characters (speed, combos,
# multi-hit swings, blocking without block art) and their class upgrades.
#   godot --headless --fixed-fps 60 --path <project> -s res://dev_tools/character_tests.gd

const KNIGHT := "res://Knight.tscn"
const TEMPLAR := "res://KnightTemplar.tscn"
const SWORDSMAN := "res://Swordsman.tscn"
const WIZARD := "res://Wizard.tscn"
const ORC := "res://orc.tscn"
# Each scene's class file, for its starting stats (what a real run uses).
const CLASS_OF := {
	KNIGHT: "res://characters/knight.tres",
	TEMPLAR: "res://characters/knight_templar.tres",
	SWORDSMAN: "res://characters/swordsman.tres",
	WIZARD: "res://characters/wizard.tres",
}

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
	for action in ["move_right", "block", "attack_light"]:
		Input.action_release(action)
	a.queue_free()
	Engine.time_scale = 1.0
	await frames(3)

func spawn(arena: Node, path: String, pos: Vector2, setup := Callable()) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.position = pos
	if setup.is_valid():
		setup.call(n)
	arena.add_child(n)
	return n

# Spawns a character with its class's starting stats, like a run does.
func spawn_as(arena: Node, path: String, pos: Vector2) -> Node2D:
	return spawn(arena, path, pos, func(n):
		n.stats = (load(CLASS_OF[path]) as CharacterClass).starting_stats.duplicate())

# A passive orc with lots of health: a damage dummy.
func dummy(arena: Node, pos: Vector2) -> Node2D:
	var orc := spawn(arena, ORC, pos)
	orc.player = null
	return orc

func _initialize() -> void:
	await run()
	Engine.time_scale = 1.0
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame
	await frames(2)
	var a: Node2D
	var p: Node2D
	var orc: Node2D

	# ---------------------------------------------------------- scenes
	print("[Every new character is an inherited scene of Knight.tscn]")
	for path in [TEMPLAR, SWORDSMAN, WIZARD]:
		var state: SceneState = (load(path) as PackedScene).get_state()
		var base: PackedScene = state.get_node_instance(0)
		check(path.get_file() + " inherits Knight.tscn", base != null and base.resource_path == KNIGHT)

	# ---------------------------------------------------------- starting stats
	print("[Starting stats]")
	var max_hp := {}
	for path in [KNIGHT, TEMPLAR, SWORDSMAN, WIZARD]:
		a = new_arena()
		p = spawn_as(a, path, Vector2.ZERO)
		await frames(1)
		max_hp[path.get_file()] = p.max_health()
		await end_arena(a)
	check("health: Knight 100, Templar 120, Swordsman 90, Wizard 80",
		max_hp == {"Knight.tscn": 100, "KnightTemplar.tscn": 120, "Swordsman.tscn": 90, "Wizard.tscn": 80}, str(max_hp))
	var templar_stats: Stats = (load(CLASS_OF[TEMPLAR]) as CharacterClass).starting_stats
	var sword_stats: Stats = (load(CLASS_OF[SWORDSMAN]) as CharacterClass).starting_stats
	check("Templar has lower Dexterity, Swordsman higher", templar_stats.dexterity < 10 and sword_stats.dexterity > 10)
	var trial_run := RunState.new(1)
	trial_run.set_character(load(CLASS_OF[TEMPLAR]))
	trial_run.stats.vitality += 4
	check("a run upgrades its own copy, never the class file", templar_stats.vitality == 14 and trial_run.stats.vitality == 18)

	# ---------------------------------------------------------- speed
	print("[Walking speed: Templar < Knight = Wizard < Swordsman]")
	var walked := {}
	for path in [KNIGHT, TEMPLAR, SWORDSMAN, WIZARD]:
		a = new_arena()
		p = spawn_as(a, path, Vector2.ZERO)
		await frames(2)
		Input.action_press("move_right")
		await frames(60)
		Input.action_release("move_right")
		walked[path.get_file()] = roundi(p.position.x)
		await end_arena(a)
	check("Knight walks 100 px in a second", absi(walked["Knight.tscn"] - 100) <= 3, str(walked))
	check("Templar is slower (85 x Dex 8 = 80)", absi(walked["KnightTemplar.tscn"] - 80) <= 3)
	check("Swordsman is faster (120 x Dex 13 = 131)", absi(walked["Swordsman.tscn"] - 131) <= 3)
	check("Wizard matches the Knight", absi(walked["Wizard.tscn"] - walked["Knight.tscn"]) <= 1)

	# ---------------------------------------------------------- combos
	print("[Combo order]")
	var orders := {
		TEMPLAR: ["attack1", "attack3", "attack2", "attack1"],
		SWORDSMAN: ["attack1", "attack2", "attack3", "attack1"],
		WIZARD: ["attack1", "attack1", "attack1", "attack1"],
	}
	for path in orders:
		a = new_arena()
		p = spawn(a, path, Vector2.ZERO)
		await frames(2)
		var seen: Array[String] = []
		var last_attack: AttackData = null
		var was_free := true
		for i in 600:
			if i % 5 == 0:
				Input.action_press("attack_light")
			elif i % 5 == 2:
				Input.action_release("attack_light")
			await physics_frame
			# A new swing = an attack that wasn't running last frame.
			var now: AttackData = p.current_attack
			if now != null and (now != last_attack or was_free):
				seen.append(String(p.anim.animation))
			was_free = now == null
			last_attack = now
			if seen.size() >= 4:
				break
		check(path.get_file() + " combo: " + " > ".join(orders[path]), seen == orders[path], str(seen))
		await end_arena(a)

	print("[Heavy and bow buttons]")
	a = new_arena()
	p = spawn(a, TEMPLAR, Vector2.ZERO)
	await frames(2)
	await tap("attack_heavy")
	check("Templar heavy = attack3", p.anim.animation == &"attack3")
	await frames(90)
	await tap("attack_bow")
	await frames(2)
	check("Templar has no bow: the bow button does nothing", p.state == p.State.FREE)
	await end_arena(a)

	# ---------------------------------------------------------- multi-hit
	print("[Multi-hit swings]")
	a = new_arena()
	p = spawn(a, TEMPLAR, Vector2.ZERO)
	orc = dummy(a, Vector2(18, 0))
	await frames(2)
	orc.health = 500
	orc.position = Vector2(18, 0)
	var t3: AttackData = load("res://attacks/templar/templar_attack3.tres")
	p.start_attack(t3)
	p.lunge_velocity = Vector2.ZERO
	await frames(90)
	check("Templar attack3 hits twice (2 x 10)", orc.health == 480, "took %d" % (500 - orc.health))
	await end_arena(a)

	a = new_arena()
	p = spawn(a, SWORDSMAN, Vector2.ZERO)
	orc = dummy(a, Vector2(18, 0))
	await frames(2)
	orc.health = 500
	orc.position = Vector2(18, 0)
	var s2: AttackData = load("res://attacks/swordsman/swordsman_attack2.tres")
	p.start_attack(s2)
	p.lunge_velocity = Vector2.ZERO
	await frames(90)
	check("Swordsman attack2 hits three times (3 x 6)", orc.health == 482, "took %d" % (500 - orc.health))
	await end_arena(a)

	# ---------------------------------------------------------- block, no art
	print("[Blocking without a block animation]")
	a = new_arena()
	p = spawn(a, SWORDSMAN, Vector2.ZERO)
	await frames(2)
	Input.action_press("block")
	await frames(3)
	check("Swordsman can block", p.state == p.State.BLOCK)
	check("...holding the idle pose, tinted", p.anim.animation == &"idle" and not p.anim.is_playing() and p.anim.self_modulate != Color.WHITE)
	await frames(30)   # past the parry window
	var result = p.take_damage(10, Vector2(20, 0), 100.0)
	check("...and a hit is blocked", result == Combat.HitResult.BLOCKED and p.health == p.max_health())
	Input.action_release("block")
	await frames(3)
	check("letting go clears the tint", p.state == p.State.FREE and p.anim.self_modulate == Color.WHITE)
	await end_arena(a)

	a = new_arena()
	p = spawn(a, TEMPLAR, Vector2.ZERO)
	await frames(2)
	Input.action_press("block")
	await frames(3)
	check("Templar blocks with his real block animation", p.anim.animation == &"block" and p.anim.self_modulate == Color.WHITE)
	await end_arena(a)

	# ---------------------------------------------------------- shield walk
	print("[Shield Walk: move while blocking]")
	var expected := [0, 28, 44, 60]   # 80 px/s for 60 frames x 0, 35, 55, 75 %
	for stacks in 4:
		a = new_arena()
		p = spawn_as(a, TEMPLAR, Vector2.ZERO)
		p.perks = {&"shield_walk": stacks} if stacks > 0 else {}
		await frames(2)
		Input.action_press("block")
		await frames(2)
		Input.action_press("move_right")
		await frames(60)
		var moved := roundi(p.position.x)
		var walk_anim: StringName = p.anim.animation
		Input.action_release("move_right")
		await frames(2)
		check("%d stack(s): moves %d px while blocking" % [stacks, expected[stacks]],
			absi(moved - expected[stacks]) <= 2 and p.state == p.State.BLOCK, "moved %d" % moved)
		if stacks > 0:
			check("...with the shield-up walk, then the held block when stopped",
				walk_anim == &"block_walk" and p.anim.animation == &"block" and p.anim.frame == 3)
		await end_arena(a)

	# ---------------------------------------------------------- other perks
	print("[Class perks]")
	a = new_arena()
	p = spawn(a, TEMPLAR, Vector2.ZERO)
	await frames(2)
	p.perks = {&"bulwark": 1}
	check("Bulwark: +25% max guard", is_equal_approx(p.max_guard(), 75.0))
	await frames(400)
	check("...and the guard regenerates up to it", is_equal_approx(p.guard, 75.0), str(p.guard))
	await end_arena(a)

	a = new_arena()
	p = spawn(a, SWORDSMAN, Vector2.ZERO)
	await frames(2)
	var base_window: float = p.parry_window()
	p.perks = {&"flurry": 2, &"duelist": 1}
	p.start_combo_attack()
	check("Flurry x2: combo swings play 24% faster", is_equal_approx(p.anim.speed_scale, 1.24))
	await frames(120)
	check("...and the speed resets after the swing", is_equal_approx(p.anim.speed_scale, 1.0))
	check("Duelist: parry window 40% wider", is_equal_approx(p.parry_window(), base_window * 1.4))
	await end_arena(a)

	# ---------------------------------------------------------- wizard
	print("[Wizard spells]")
	a = new_arena()
	p = spawn(a, WIZARD, Vector2.ZERO)
	orc = dummy(a, Vector2(40, 0))
	await frames(2)
	orc.health = 500
	orc.position = Vector2(40, 0)
	p.start_combo_attack()
	await frames(60)
	check("frost burst hits an enemy 40 px away", orc.health == 486, "took %d" % (500 - orc.health))
	await end_arena(a)

	# Farthest distance (in steps of 4 px) at which the burst still lands.
	var frost_reach := {}
	for stacks in [0, 2]:
		frost_reach[stacks] = 0
		for dx in range(40, 100, 4):
			a = new_arena()
			p = spawn(a, WIZARD, Vector2.ZERO)
			p.perks = {&"wide_frost": stacks}
			orc = dummy(a, Vector2(dx, 0))
			await frames(2)
			orc.health = 500
			orc.position = Vector2(dx, 0)
			p.start_combo_attack()
			await frames(60)
			var hit: bool = orc.health < 500
			await end_arena(a)
			if not hit:
				break
			frost_reach[stacks] = dx
	check("frost burst reaches well past a sword swing (38 px)", frost_reach[0] >= 50, str(frost_reach))
	check("Wide Frost x2 reaches at least 8 px farther", frost_reach[2] >= frost_reach[0] + 8)

	for stacks in [0, 1]:
		a = new_arena()
		p = spawn(a, WIZARD, Vector2.ZERO)
		p.perks = {&"searing_bolt": stacks}
		orc = dummy(a, Vector2(150, 0))
		await frames(2)
		orc.health = 500
		orc.position = Vector2(150, 0)
		p.ranged_attack = null
		p.aim_direction = Vector2.RIGHT
		p.start_attack(p.heavy_attack)
		p.aim_direction = Vector2.RIGHT   # the mouse isn't anywhere useful in a test
		var fireball_seen := false   # a bool: the fireball frees itself when it hits
		for i in 120:
			await physics_frame
			for c in a.get_children():
				if c.scene_file_path == "res://fireball.tscn":
					fireball_seen = true
			if orc.health < 500:
				break
		await frames(20)
		if stacks == 0:
			check("heavy button throws a fireball", fireball_seen)
			check("...that hits for 18", orc.health == 482, "took %d" % (500 - orc.health))
		else:
			check("Searing Bolt: fireball hits for 25 (18 x 1.4)", orc.health == 475, "took %d" % (500 - orc.health))
		await end_arena(a)

	# ---------------------------------------------------------- pools
	print("[Upgrade pools]")
	var shared: Array = load("res://script/run_manager.gd").UPGRADES
	var siege: Upgrade = load("res://upgrades/charged_shot.tres")
	var templar_class: CharacterClass = load("res://characters/knight_templar.tres")
	var knight_class: CharacterClass = load("res://characters/knight.tres")
	var templar_pool := templar_class.upgrade_pool(shared)
	check("the Knight is offered Siege Shot", siege in knight_class.upgrade_pool(shared))
	check("the Templar is not", not siege in templar_pool)
	check("the Templar gets Shield Walk and Bulwark",
		load("res://upgrades/shield_walk.tres") in templar_pool and load("res://upgrades/bulwark.tres") in templar_pool)
	check("everyone shares the 10 common upgrades", templar_pool.size() == shared.size() + 2, str(templar_pool.size()))

	# ---------------------------------------------------------- select screen
	print("[Character select in run.tscn]")
	var scene: Node = load("res://run.tscn").instantiate()
	scene.get_node("RunManager").dev_screen_enabled = false
	root.add_child(scene)
	current_scene = scene
	await frames(3)
	var select: CanvasLayer = scene.get_node("CharacterSelect")
	var mgr: Node = scene.get_node("RunManager")
	check("the run opens on the character select, 4 choices", select.visible and select.buttons.size() == 4)
	check("no player and no room yet", mgr.knight == null and mgr.room == null)
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	Input.parse_input_event(key)
	await frames(30)
	check("pressing 2 picks the Knight Templar", mgr.knight != null and mgr.knight.name == "KnightTemplar" and mgr.run.character == templar_class)
	check("the room is built and the select screen gone", mgr.room != null and not select.visible)
	check("the HUD follows the Templar, with his 120 health", scene.get_node("HUD").health_label.text == "120 / 120")
	check("the pool is the Templar's", mgr.pool.size() == templar_pool.size() and not siege in mgr.pool)
	var shield_walk: Upgrade = load("res://upgrades/shield_walk.tres")
	for i in 3:
		mgr.run.apply(shield_walk, mgr.knight)
		mgr._remove_if_maxed(shield_walk)
		if i < 2:
			check("Shield Walk still offered after %d pick(s)" % (i + 1), shield_walk in mgr.pool)
	check("...and gone once it's maxed (3)", not shield_walk in mgr.pool and mgr.knight.perk(&"shield_walk") == 3)
	check("the select screen remembers the pick", select.last_index == 1)
	scene.queue_free()
	await frames(3)
