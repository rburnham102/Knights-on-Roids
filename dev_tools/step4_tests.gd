extends SceneTree
# Step-4 tests: the run loop (rooms, doors, director, upgrades, victory, death) and perks.
#   godot --headless --fixed-fps 60 --path <project> -s res://step4_tests.gd

const KNIGHT := "res://Knight.tscn"
const ORC := preload("res://orc.tscn")
const ARCHER := preload("res://skeleton_archer.tscn")
const ARMORED := preload("res://armored_orc.tscn")
const FLOOR_TILE := Vector2i(1, 1)
const UPGRADE_FILES := ["power_up", "dexterity_up", "vitality_up", "field_dressing", "parry_mend",
	"brutal_riposte", "ghost_step", "light_footed", "iron_guard"]

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

func wait_until(cond: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()

func new_arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a

func end_arena(a: Node) -> void:
	a.queue_free()
	Engine.time_scale = 1.0
	await frames(3)

func enemies_of(actors: Node) -> Array:
	return actors.get_children().filter(func(c): return "max_poise" in c)

func boot_run(seed_value := 1234) -> Node2D:
	var scene: Node2D = load("res://run.tscn").instantiate()
	scene.get_node("RunManager").start_seed = seed_value
	root.add_child(scene)
	current_scene = scene   # so "New run" (reload_current_scene) works in a test
	await frames(3)
	await wait_until(func(): return not scene.get_node("RunManager").changing_room, 120)
	return scene

func kill_all(scene: Node) -> void:
	for e in enemies_of(scene.get_node("Actors")):
		e.take_damage(9999)

func _initialize() -> void:
	await run()
	Engine.time_scale = 1.0
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame
	await frames(2)

	# ------------------------------------------------------------ run state
	print("[RunState]")
	var rs := RunState.new(42)
	check("a fresh run: stats 10/10/10, depth 0, no perks", rs.stats.power == 10 and rs.stats.dexterity == 10 and rs.stats.vitality == 10 and rs.depth == 0 and rs.perks.is_empty())
	var pool: Array[Upgrade] = []
	for id in UPGRADE_FILES:
		pool.append(load("res://upgrades/%s.tres" % id))
	check("nine upgrades exist, each with a title and description", pool.size() == 9 and pool.all(func(u): return u.title != "" and u.description != ""))
	var rolled := rs.roll_upgrades(pool, 3)
	check("a roll offers 3 different upgrades", rolled.size() == 3 and rolled[0] != rolled[1] and rolled[1] != rolled[2] and rolled[0] != rolled[2])
	var rs2 := RunState.new(42)
	var rolled2 := rs2.roll_upgrades(pool, 3)
	check("the same seed rolls the same upgrades", rolled[0] == rolled2[0] and rolled[1] == rolled2[1] and rolled[2] == rolled2[2])

	var a := new_arena()
	var knight: Node2D = load(KNIGHT).instantiate()
	knight.stats = rs.stats
	knight.perks = rs.perks
	a.add_child(knight)
	await frames(2)
	rs.apply(load("res://upgrades/power_up.tres"), knight)
	check("Brute Strength: +2 Power", rs.stats.power == 12)
	knight.health = 60
	rs.apply(load("res://upgrades/vitality_up.tres"), knight)
	check("Thick Hide: +2 Vitality raises max health 100 -> 110 and heals the difference", knight.max_health() == 110 and knight.health == 70, "hp %d/%d" % [knight.health, knight.max_health()])
	rs.apply(load("res://upgrades/field_dressing.tres"), knight)
	check("Field Dressing heals 35", knight.health == 105)
	rs.apply(load("res://upgrades/parry_mend.tres"), knight)
	rs.apply(load("res://upgrades/parry_mend.tres"), knight)
	check("perks stack (taken twice = 2)", rs.perks.get(&"parry_heal", 0) == 2 and knight.perk(&"parry_heal") == 2)
	check("upgrades taken are recorded", rs.upgrades_taken.size() == 5)
	await end_arena(a)

	# ------------------------------------------------------------- director
	print("[Enemy director]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var only_orcs := true
	var counts1 := 0
	var counts10 := 0
	var saw_archer_d2 := false
	var armored_early := false
	var saw_armored_d4 := false
	var budget_ok := true
	var slots_ok := true
	for i in 60:
		var p1 := EnemyDirector.plan(1, 6, rng)
		counts1 += p1.size()
		for s in p1:
			if s != ORC:
				only_orcs = false
		var p2 := EnemyDirector.plan(2, 6, rng)
		if p2.has(ARCHER):
			saw_archer_d2 = true
		var p3 := EnemyDirector.plan(3, 6, rng)
		if p3.has(ARMORED):
			armored_early = true
		var p4 := EnemyDirector.plan(4, 6, rng)
		if p4.has(ARMORED):
			saw_armored_d4 = true
		var p10 := EnemyDirector.plan(10, 6, rng)
		counts10 += p10.size()
		if p10.size() > 6:
			slots_ok = false
		var spent := 0.0
		for s in p10:
			spent += 1.0 if s == ORC else (1.5 if s == ARCHER else 3.0)
		if spent > EnemyDirector.budget_for(10) + 0.001:
			budget_ok = false
	check("room 1 only ever has orcs", only_orcs)
	check("archers can appear from room 2", saw_archer_d2)
	check("no armored orc before room 4, but they appear from room 4", not armored_early and saw_armored_d4)
	check("later rooms are fuller than the first", counts10 > counts1 * 1.5, "%d vs %d enemies over 60 rolls" % [counts10, counts1])
	check("never more enemies than spawn points, never over budget", slots_ok and budget_ok)
	check("there is always at least one enemy", EnemyDirector.plan(1, 6, rng).size() >= 1 and EnemyDirector.plan(1, 0, rng).size() >= 1)

	# ---------------------------------------------------------------- rooms
	print("[Rooms]")
	var expected := {"room_arena": Rect2(0, 0, 384, 208), "room_pillars": Rect2(0, 0, 384, 208), "room_hall": Rect2(0, 0, 512, 176)}
	for name in expected:
		a = new_arena()
		var room: Room = load("res://rooms/%s.tscn" % name).instantiate()
		a.add_child(room)
		await frames(2)
		check("%s: bounds %s" % [name, str(expected[name].size)], room.bounds() == expected[name], str(room.bounds()))
		var spawns := room.spawn_positions()
		var good := spawns.size() >= 6
		for pos in spawns:
			if room.ground.get_cell_atlas_coords(room.ground.local_to_map(pos)) != FLOOR_TILE:
				good = false
		check("%s: %d enemy spawns, all on open floor" % [name, spawns.size()], good)
		check("%s: knight starts on open floor, west of every spawn" % name,
			room.ground.get_cell_atlas_coords(room.ground.local_to_map(room.player_start.position)) == FLOOR_TILE
			and spawns.all(func(p): return p.x > room.player_start.position.x + 48.0))
		var right_edge: float = room.bounds().end.x
		check("%s: the door sits in the east wall, in its gap" % name,
			abs(room.exit_door.position.x - (right_edge - 8.0)) < 1.0 and room.exit_door.position.y > 0.0)
		await end_arena(a)

	# ----------------------------------------------------------------- door
	print("[Exit door]")
	a = new_arena()
	var door: ExitDoor = load("res://exit_door.tscn").instantiate()
	door.position = Vector2(100, 0)
	a.add_child(door)
	var kn: Node2D = load(KNIGHT).instantiate()
	kn.position = Vector2(60, 0)
	a.add_child(kn)
	await frames(3)
	var entered := [0]
	door.entered.connect(func(): entered[0] += 1)
	Input.action_press("move_right")
	await frames(70)
	check("a closed door is solid", kn.position.x < 92.0 and entered[0] == 0, "knight at x=%.1f" % kn.position.x)
	door.open()
	await frames(30)
	Input.action_release("move_right")
	check("walking into an open door fires `entered` once", entered[0] == 1, "fired %d" % entered[0])
	await end_arena(a)

	a = new_arena()
	door = load("res://exit_door.tscn").instantiate()
	door.position = Vector2(100, 0)
	a.add_child(door)
	kn = load(KNIGHT).instantiate()
	kn.position = Vector2(96, 0)   # already standing in the doorway
	a.add_child(kn)
	await frames(3)
	entered = [0]
	door.entered.connect(func(): entered[0] += 1)
	door.open()
	await frames(5)
	check("opening a door while already standing in it still counts", entered[0] == 1)
	await end_arena(a)

	# ------------------------------------------------------------- run flow
	print("[Run flow]")
	var scene := await boot_run(1234)
	var mgr: Node = scene.get_node("RunManager")
	var hud: Node = scene.get_node("HUD")
	var actors: Node = scene.get_node("Actors")
	var kn_run: Node2D = actors.get_node("Knight")
	var up_screen: Node = scene.get_node("UpgradeScreen")
	var end_screen: Node = scene.get_node("RunOverScreen")
	check("a run starts in room 1, shown on the HUD", mgr.run.depth == 1 and hud.room_label.text == "Room 1 / 10", hud.room_label.text)
	check("the room's door starts closed", mgr.room != null and not mgr.room.exit_door.is_open)
	var room_enemies := enemies_of(actors)
	check("room 1 has orcs only, counted by the manager", room_enemies.size() >= 1 and room_enemies.size() == mgr.enemies_left and room_enemies.all(func(e): return e.scene_file_path == ORC.resource_path))
	check("the knight starts at the room's start marker", kn_run.global_position.distance_to(mgr.room.player_start.global_position) < 1.0)
	var b: Rect2 = mgr.room.bounds()
	check("camera limits match the room", kn_run.camera.limit_left == int(b.position.x) and kn_run.camera.limit_right == int(b.end.x) and kn_run.camera.limit_bottom == int(b.end.y))
	check("enemies fade in: idle at first", room_enemies.all(func(e): return e.process_mode == Node.PROCESS_MODE_DISABLED and e.modulate.a < 0.6))
	await frames(40)
	check("...and wake up after half a second", room_enemies.all(func(e): return e.process_mode != Node.PROCESS_MODE_DISABLED and e.modulate.a > 0.99))
	kn_run.health = 50
	kill_all(scene)
	await wait_until(func(): return mgr.awaiting_upgrade, 200)
	check("clearing the room offers an upgrade and pauses the game", mgr.awaiting_upgrade and up_screen.visible and paused)
	check("the knight was healed by the room-clear share of max health", kn_run.health == 50 + roundi(kn_run.max_health() * mgr.heal_after_room), "hp %d" % kn_run.health)
	check("three different choices are shown", up_screen.offered.size() == 3 and up_screen.offered[0] != up_screen.offered[1])
	check("the door is still closed while choosing", not mgr.room.exit_door.is_open)
	var pick: Upgrade = up_screen.offered[0]
	up_screen.choose(0)
	check("choosing unpauses, applies the upgrade, and opens the door", not paused and mgr.run.upgrades_taken == [pick] and mgr.room.exit_door.is_open)
	var old_room: Node = mgr.room
	var hp_before: int = kn_run.health
	kn_run.global_position = mgr.room.exit_door.global_position + Vector2(-6, 0)
	await wait_until(func(): return mgr.run.depth == 2 and not mgr.changing_room, 300)
	check("walking through the open door starts room 2", mgr.run.depth == 2 and hud.room_label.text == "Room 2 / 10")
	check("the old room is gone, the new one is in", not is_instance_valid(old_room) and room_holder_count(scene) == 1)
	check("the same knight carried over, health and stats intact", actors.get_node("Knight") == kn_run and kn_run.health >= hp_before and kn_run.stats == mgr.run.stats)
	check("the knight is at the new room's start", kn_run.global_position.distance_to(mgr.room.player_start.global_position) < 1.0)
	var d2 := enemies_of(actors)
	check("room 2 enemies respect the director (no armored orcs yet)", d2.size() >= 1 and d2.all(func(e): return e.scene_file_path != ARMORED.resource_path))

	# ... all the way through room 10
	for depth in range(2, 11):
		kill_all(scene)
		if depth < 10:
			await wait_until(func(): return mgr.awaiting_upgrade, 200)
			up_screen.choose(0)
			kn_run.global_position = mgr.room.exit_door.global_position + Vector2(-6, 0)
			await wait_until(func(): return mgr.run.depth == depth + 1 and not mgr.changing_room, 300)
		else:
			await wait_until(func(): return mgr.finished, 200)
	check("clearing room 10 completes the run", mgr.finished and mgr.run.rooms_cleared == 10 and end_screen.visible)
	check("...with the victory title and a summary", end_screen.title_label.text == "RUN COMPLETE" and end_screen.body_label.text.contains("Rooms cleared: 10 / 10"), end_screen.body_label.text.replace("\n", " | "))
	check("...and no upgrade is offered after the last room", not mgr.awaiting_upgrade and mgr.run.upgrades_taken.size() == 9)
	scene.queue_free()
	paused = false
	await frames(3)

	# ---------------------------------------------------------------- death
	print("[Death and a new run]")
	scene = await boot_run(99)
	mgr = scene.get_node("RunManager")
	kn_run = scene.get_node("Actors/Knight")
	end_screen = scene.get_node("RunOverScreen")
	kn_run.take_damage(9999)
	await wait_until(func(): return mgr.finished, 400)
	check("dying ends the run with the death screen", end_screen.visible and end_screen.title_label.text == "YOU DIED" and paused)
	check("...and the level did NOT just reload on its own", current_scene == scene and is_instance_valid(scene))
	end_screen.new_run_requested.emit()
	await frames(4)
	var fresh: Node = current_scene
	check("'New run' starts a brand new run", fresh != scene and fresh.get_node("RunManager").run.depth >= 1 and fresh.get_node("RunManager").run.rooms_cleared == 0 and not paused)
	fresh.queue_free()
	await frames(3)

	# --------------------------------------------------------------- perks

	print("[Enemies get around obstacles]")
	a = new_arena()
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(100, 0)
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(32, 32)   # centred on the line between orc and knight
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	a.add_child(wall)
	knight = load(KNIGHT).instantiate()
	knight.position = Vector2(40, 0)
	a.add_child(knight)
	var chaser: Node2D = ORC.instantiate()
	chaser.position = Vector2(160, 0)
	chaser.heavy_chance = 0.0
	a.add_child(chaser)
	await frames(2)
	var got_through := await wait_until(func(): return chaser.global_position.distance_to(knight.global_position) < 26.0, 480)
	check("an orc walks around a pillar that blocks its straight path", got_through, "ended %.0f px away" % chaser.global_position.distance_to(knight.global_position))
	await end_arena(a)

	a = new_arena()
	wall = StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(100, 0)
	wall_shape = CollisionShape2D.new()
	wall_rect = RectangleShape2D.new()
	wall_rect.size = Vector2(32, 32)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	a.add_child(wall)
	knight = load(KNIGHT).instantiate()
	knight.position = Vector2(40, 0)
	a.add_child(knight)
	var shooter: Node2D = ARCHER.instantiate()
	shooter.position = Vector2(200, 0)
	a.add_child(shooter)
	await frames(2)
	var first_shot_had_clear_line := [false]
	var shot_taken := await wait_until(func():
		if a.get_children().any(func(c): return "from_enemy" in c):
			first_shot_had_clear_line[0] = shooter.has_line_of_sight()
			return true
		return false, 900)
	check("an archer behind a pillar walks around it, and only then shoots", shot_taken and first_shot_had_clear_line[0])
	await end_arena(a)

	print("[Perks and knight helpers]")
	a = new_arena()
	knight = load(KNIGHT).instantiate()
	knight.perks = {&"parry_heal": 2}
	a.add_child(knight)
	await frames(2)
	knight.health = 50
	Input.action_press("block")
	await frames(3)
	var res: Combat.HitResult = knight.take_damage(8, Vector2(-30, 0), 0.0)
	Input.action_release("block")
	check("Parry & Mend (x2): a perfect parry heals 10", res == Combat.HitResult.PARRIED and knight.health == 60, "hp %d" % knight.health)
	await end_arena(a)

	a = new_arena()
	knight = load(KNIGHT).instantiate()
	knight.perks = {&"riposte_power": 1}
	a.add_child(knight)
	await frames(2)
	Input.action_press("block")
	await frames(3)
	knight.take_damage(8, Vector2(30, 0), 0.0)
	Input.action_release("block")
	var riposte_damage: int = knight.attack_damage()
	await frames(80)
	knight.start_attack(knight.light_combo[1], true)
	var normal_damage: int = knight.attack_damage()
	check("Brutal Riposte: the riposte hits 60% harder (12 -> 19)...", riposte_damage == 19, str(riposte_damage))
	check("...but a normal second swing is unchanged (12)", normal_damage == 12, str(normal_damage))
	await end_arena(a)

	var invuln := {}
	for stacks in [0, 1]:
		a = new_arena()
		knight = load(KNIGHT).instantiate()
		knight.perks = {&"long_dodge": stacks}
		a.add_child(knight)
		await frames(2)
		Input.action_press("dodge")
		await frames(2)
		Input.action_release("dodge")
		while knight.dodge_time < 0.2:
			await physics_frame
		invuln[stacks] = knight.is_invulnerable
		await end_arena(a)
	check("Ghost Step: still invulnerable at 0.2s with the perk (0.24s), not without (0.18s)", invuln[1] and not invuln[0])

	var cool := {}
	for stacks in [0, 1, 5]:
		a = new_arena()
		knight = load(KNIGHT).instantiate()
		knight.perks = {&"quick_dodge": stacks}
		a.add_child(knight)
		await frames(2)
		Input.action_press("dodge")
		await frames(2)
		Input.action_release("dodge")
		cool[stacks] = knight.dodge_cooldown_left
		await end_arena(a)
	check("Light Footed: dodge cooldown 0.7 -> 0.5, never below 0.3", cool[0] > 0.65 and cool[1] > 0.45 and cool[1] < 0.52 and cool[5] > 0.25 and cool[5] < 0.33, str(cool))

	var regen := {}
	for stacks in [0, 1]:
		a = new_arena()
		knight = load(KNIGHT).instantiate()
		knight.perks = {&"iron_guard": stacks}
		a.add_child(knight)
		await frames(2)
		knight.guard = 20.0
		knight.guard_regen_delay_left = 0.0
		await frames(60)
		regen[stacks] = knight.guard - 20.0
		await end_arena(a)
	check("Iron Guard: guard regenerates 50% faster (12/s -> 18/s)", abs(regen[0] - 12.0) < 1.5 and abs(regen[1] - 18.0) < 2.0, str(regen))

	a = new_arena()
	knight = load(KNIGHT).instantiate()
	a.add_child(knight)
	await frames(2)
	var heals := []
	knight.health_changed.connect(func(c, m): heals.append(c))
	knight.health = 90
	knight.heal(50)
	check("heal() never goes past max health and announces it", knight.health == 100 and heals == [100])
	knight.heal(0)
	check("healing 0 does nothing", heals.size() == 1)
	await tap_dodge()
	await frames(3)
	check("(setup) knight is mid-dodge", knight.state == knight.State.DODGE)
	knight.reset_for_new_room()
	check("reset_for_new_room leaves the dodge cleanly (solid again, still)", knight.state == knight.State.FREE and knight.collision_layer == 2 and knight.collision_mask == 7 and knight.velocity == Vector2.ZERO)
	knight.take_damage(9999)
	await frames(2)
	knight.heal(10)
	check("a dead knight can't be healed", knight.health <= 0)
	await end_arena(a)

	a = new_arena()
	knight = load(KNIGHT).instantiate()
	a.add_child(knight)
	await frames(2)
	var died_count := [0]
	knight.died.connect(func(): died_count[0] += 1)
	knight.take_damage(9999)
	await frames(200)
	check("with a listener, death emits `died` once instead of reloading", died_count[0] == 1 and is_instance_valid(knight))
	await end_arena(a)

func room_holder_count(scene: Node) -> int:
	return scene.get_node("RoomHolder").get_child_count()

func tap_dodge() -> void:
	Input.action_press("dodge")
	await frames(2)
	Input.action_release("dodge")
