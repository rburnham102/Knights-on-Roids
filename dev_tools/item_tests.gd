extends SceneTree
# Item tests: barrels break from real sword swings and arrows, enemies and
# barrels drop loot, pickups apply to the run, and loot never changes a seed's rooms.
#   godot --headless --fixed-fps 60 --path <project> -s res://dev_tools/item_tests.gd

const KNIGHT := "res://Knight.tscn"
const BARREL := "res://breakable.tscn"
const PICKUP := "res://pickup.tscn"
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
	for action in ["move_up", "move_down", "move_left", "move_right", "attack_light", "block"]:
		Input.action_release(action)
	a.queue_free()
	Engine.time_scale = 1.0
	await frames(3)

func spawn(arena: Node, path: String, pos: Vector2) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.position = pos
	arena.add_child(n)
	return n

func _initialize() -> void:
	await frames(2)
	print("--- barrels")
	await test_sword_breaks_barrel()
	await test_arrows()
	await test_barrel_is_solid()
	print("--- pickups")
	await test_pickup()
	await test_tome_of_vitality()
	print("--- loot")
	test_loot_roll()
	test_enemy_drop_chances()
	test_loot_keeps_seed()
	print("--- full run")
	await test_run()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func test_sword_breaks_barrel() -> void:
	var a := new_arena()
	var k := spawn(a, KNIGHT, Vector2(100, 100))
	var b: Breakable = spawn(a, BARREL, Vector2(114, 100))
	var got := []
	b.broken.connect(func(x): got.append(x))
	await frames(3)
	Input.action_press("attack_light")
	await frames(2)
	Input.action_release("attack_light")
	await frames(40)
	check("a light swing breaks a barrel", b.hits_left == 0 and got.size() == 1, "hits_left=%d signals=%d" % [b.hits_left, got.size()])
	check("broken barrel stops blocking and taking hits", b.body_shape.disabled and b.hurtbox_shape.disabled)
	check("broken barrel shows the broken sprite", b.sprite.texture == b.broken_texture)
	check("broken signal fires once even with a 3-hit combo", got.size() == 1)
	await end_arena(a)

func test_arrows() -> void:
	var a := new_arena()
	var b: Breakable = spawn(a, BARREL, Vector2(200, 100))
	var arrow: Node2D = load(ARROW).instantiate()
	arrow.direction = Vector2.RIGHT
	arrow.position = Vector2(150, 93)
	a.add_child(arrow)
	await frames(20)
	check("the knight's arrow breaks a barrel", b.hits_left == 0)
	check("...and is used up", not is_instance_valid(arrow) or arrow.is_queued_for_deletion())

	var b2: Breakable = spawn(a, BARREL, Vector2(200, 160))
	await frames(2)
	var enemy_arrow: Node2D = load(ARROW).instantiate()
	enemy_arrow.direction = Vector2.RIGHT
	enemy_arrow.from_enemy = true
	enemy_arrow.position = Vector2(150, 157)
	a.add_child(enemy_arrow)
	await frames(20)
	check("an enemy arrow does NOT break a barrel", b2.hits_left == 1)
	check("...it's stopped by it (barrels are cover)", not is_instance_valid(enemy_arrow))
	await end_arena(a)

func test_barrel_is_solid() -> void:
	var a := new_arena()
	var k := spawn(a, KNIGHT, Vector2(100, 100))
	spawn(a, BARREL, Vector2(130, 100))
	await frames(3)
	Input.action_press("move_right")
	await frames(60)
	Input.action_release("move_right")
	check("the knight can't walk through a barrel", k.global_position.x < 125.0, "x=%.1f" % k.global_position.x)
	await end_arena(a)

func make_pickup(a: Node, item_path: String, pos: Vector2, run: RunState, k: Node) -> Pickup:
	var p: Pickup = load(PICKUP).instantiate()
	p.item = load(item_path)
	p.position = pos
	p.collected.connect(func(item): run.apply_item(item, k))
	a.add_child(p)
	return p

func test_pickup() -> void:
	var a := new_arena()
	var k := spawn(a, KNIGHT, Vector2(100, 100))
	var run := RunState.new(5)
	k.stats = run.stats
	await frames(2)
	k.health = 50
	# Dropped right on the knight: must still wait for the hop to finish.
	var p := make_pickup(a, "res://items/small_health_potion.tres", Vector2(100, 100), run, k)
	await frames(6)
	check("can't be grabbed mid-hop", k.health == 50)
	# Walk onto wherever it landed.
	await frames(20)
	for i in 60:
		if not is_instance_valid(p) or p.sprite.visible == false:
			break
		k.global_position = k.global_position.move_toward(p.global_position, 2.0)
		await physics_frame
	check("a small potion heals 15", k.health == 65, "health=%d" % k.health)
	check("it's recorded as an item, not an upgrade", run.items_found.size() == 1 and run.upgrades_taken.is_empty())
	check("only collected once", run.items_found.size() == 1)
	# --fixed-fps runs game time faster than real time, but audio plays in real
	# time, and the pickup waits for its sound. So wait in real time here.
	var until := Time.get_ticks_msec() + 2000
	while is_instance_valid(p) and Time.get_ticks_msec() < until:
		await physics_frame
	check("the pickup frees itself afterwards", not is_instance_valid(p))
	await end_arena(a)

func test_tome_of_vitality() -> void:
	var a := new_arena()
	var k := spawn(a, KNIGHT, Vector2(100, 100))
	var run := RunState.new(5)
	k.stats = run.stats
	await frames(2)
	var before_max: int = k.max_health()
	k.health = before_max
	run.apply_item(load("res://items/tome_of_vitality.tres"), k)
	check("tome of vitality: +1 vitality", run.stats.vitality == 11)
	check("...more max health, and the new health is filled", k.max_health() > before_max and k.health == k.max_health(), "%d -> %d" % [before_max, k.max_health()])
	await end_arena(a)

func test_loot_roll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var none := 0
	for i in 1000:
		if Loot.roll(0.0, rng) == null:
			none += 1
	check("drop chance 0 never drops", none == 1000)
	var counts := {}
	for i in 20000:
		var item := Loot.roll(1.0, rng)
		counts[item.title] = int(counts.get(item.title, 0)) + 1
	check("drop chance 1 always drops", counts.values().reduce(func(s, n): return s + n) == 20000)
	var small: int = counts.get("Small Health Potion", 0)
	check("weights are respected (small potion ~67%)", absf(small / 20000.0 - 60.0 / 89.0) < 0.02, str(counts))

func test_enemy_drop_chances() -> void:
	var parts := []
	for path in ["res://orc.tscn", "res://skeleton_archer.tscn", "res://armored_orc.tscn"]:
		var e: Node = load(path).instantiate()
		parts.append("%s %.2f" % [path.get_file().get_basename(), e.drop_chance])
		check("%s has a drop chance" % path.get_file(), e.drop_chance > 0.0)
		e.free()
	print("        ", ", ".join(parts))

func test_loot_keeps_seed() -> void:
	var a := RunState.new(1234)
	var b := RunState.new(1234)
	for i in 50:
		Loot.roll(0.5, a.loot_rng)   # one run smashes 50 barrels...
	check("loot rolls don't change a seed's rooms", a.rng.randi() == b.rng.randi())

func test_run() -> void:
	var scene: Node2D = load("res://run.tscn").instantiate()
	scene.get_node("RunManager").start_seed = 777
	scene.get_node("RunManager").dev_screen_enabled = false   # no dev screen: start right away
	scene.get_node("RunManager").character_select_enabled = false   # plays the first class, the Knight
	root.add_child(scene)
	current_scene = scene
	var mgr: Node = scene.get_node("RunManager")
	var actors: Node2D = scene.get_node("Actors")
	var k: Node2D = actors.get_node("Knight")
	await frames(40)
	var barrels: Array = get_nodes_in_group("breakables")
	check("barrels are placed in the level", barrels.size() >= 4, "%d barrels" % barrels.size())
	check("every barrel is connected to the run manager", barrels.all(func(b): return b.broken.get_connections().size() == 1))

	# Kill an enemy that is sure to drop something.
	var enemy: Node2D = actors.get_children().filter(func(c): return "max_poise" in c)[0]
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	enemy.drop_chance = 1.0
	var left_before: int = mgr.enemies_left
	enemy.take_damage(9999, enemy.global_position + Vector2.LEFT, 0.0, 9999.0)
	await frames(3)
	var pickups := actors.get_children().filter(func(c): return c is Pickup)
	check("a dying enemy drops a pickup into Actors", pickups.size() == 1)
	check("enemy count still goes down", mgr.enemies_left == left_before - 1)
	if pickups.size() == 1:
		var p: Pickup = pickups[0]
		await frames(30)
		k.health = 20
		var hp_before: int = k.health
		k.global_position = p.global_position
		await frames(5)
		check("walking onto it applies the item to the run", mgr.run.items_found.size() == 1 and k.health > hp_before, "%s, hp %d -> %d" % [p.item.title, hp_before, k.health])

	# Break a barrel that is sure to drop something.
	var b: Breakable = barrels[0]
	b.drop_chance = 1.0
	b.take_damage(10)
	await frames(3)
	check("a broken barrel drops a pickup", actors.get_children().filter(func(c): return c is Pickup and c.item != null and not c.sprite.visible == false).size() >= 1)

	# Next room: old barrels go away, new ones are connected exactly once.
	mgr._room_cleared()
	await frames(5)
	mgr.room.exit_door.open()
	mgr._on_exit_entered()
	await frames(60)
	var new_barrels: Array = get_nodes_in_group("breakables")
	check("room 2 has its own barrels, each connected once", new_barrels.size() >= 4 and new_barrels.all(func(nb): return nb.broken.get_connections().size() == 1), "%d" % new_barrels.size())
	check("leftover pickups are cleared between rooms", actors.get_children().filter(func(c): return c is Pickup).is_empty())
	scene.queue_free()
	await frames(3)
