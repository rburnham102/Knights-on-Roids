extends SceneTree
# Step-5 tests: playtest fixes. Archer arrows have a range, combo swings follow
# the held direction (orcs above/below), and the riposte -> heavy follow-up is
# easier to land.
#   godot --headless --fixed-fps 60 --path <project> -s res://step5_tests.gd

const KNIGHT := "res://Knight.tscn"
const ORC := "res://orc.tscn"
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

# An orc that just stands there and soaks hits.
func dummy_orc(a: Node, pos: Vector2) -> Node2D:
	var o := spawn(a, ORC, pos)
	o.player = null
	await frames(2)
	o.health = 500
	o.max_poise = 1000.0
	o.poise = 1000.0
	return o

func _initialize() -> void:
	await run()
	Engine.time_scale = 1.0
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame
	await frames(2)

	# ------------------------------------------------------------ arrow range
	print("[Arrow range]")
	var shot: AttackData = load("res://attacks/enemy/archer_shot.tres")
	check("archer_shot range is 220 px", is_equal_approx(shot.projectile_range, 220.0), str(shot.projectile_range))
	check("default range stays 1200 (knight's bow unchanged)", is_equal_approx(AttackData.new().projectile_range, 1200.0))

	var a := new_arena()
	var arrow: Area2D = load(ARROW).instantiate()
	arrow.from_enemy = true
	arrow.direction = Vector2.RIGHT
	arrow.speed = 240.0
	arrow.max_range = 220.0
	a.add_child(arrow)
	var last_x := 0.0
	var faded := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(arrow):
			break
		last_x = arrow.position.x
		if arrow.modulate.a < 0.99 and arrow.modulate.a > 0.0:
			faded = true
	check("an archer arrow is gone after ~220 px", not is_instance_valid(arrow) and last_x > 200.0 and last_x <= 220.0, "last seen at x=%.0f" % last_x)
	check("...and fades out on the way, instead of popping", faded)
	await end_arena(a)

	a = new_arena()
	arrow = load(ARROW).instantiate()
	arrow.from_enemy = true
	arrow.direction = Vector2.RIGHT
	arrow.max_range = 220.0
	a.add_child(arrow)
	await frames(1)
	check("the fade keeps the enemy arrow's red tint", is_equal_approx(arrow.modulate.g, 0.6) and is_equal_approx(arrow.modulate.b, 0.5))
	await end_arena(a)

	a = new_arena()
	var knight := spawn(a, KNIGHT, Vector2(-300, 300))
	var archer := spawn(a, "res://skeleton_archer.tscn", Vector2.ZERO)
	await frames(2)
	archer.current_attack = shot
	archer.player = spawn(a, KNIGHT, Vector2(150, 0))   # something to aim at
	archer.fire_projectile()
	var fired: Node = a.get_children().filter(func(c): return "from_enemy" in c)[0]
	check("the archer hands its range to the arrow", is_equal_approx(fired.max_range, 220.0), str(fired.max_range))
	await end_arena(a)

	# ------------------------------------------------- swings follow the input
	print("[Swings go the way you're pressing]")
	for setup in [["up", Vector2(0, -14)], ["down", Vector2(0, 14)]]:
		var key: String = "move_" + setup[0]
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		var orc := await dummy_orc(a, setup[1])
		knight.last_direction = "right"
		var dirs: Array = []
		var last_anim := &""
		for f in 150:
			if f % 22 == 0 and f < 66:
				Input.action_press("attack_light")
			if f % 22 == 2:
				Input.action_release("attack_light")
			if f >= 22:
				Input.action_press(key)   # turn toward the orc after the first swing
			await physics_frame
			if knight.current_attack != null and knight.current_attack.anim != last_anim:
				last_anim = knight.current_attack.anim
				dirs.append(knight.last_direction)
		check("orc %s: mid-combo, holding %s turns swings 2 and 3 toward it" % [setup[0], setup[0]], dirs == ["right", setup[0], setup[0]], str(dirs))
		check("...and both land (12 + 25 = 37)", 500 - orc.health == 37, "dealt %d" % (500 - orc.health))
		await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	knight.last_direction = "up"
	knight.start_combo_attack()
	check("no key held: a swing keeps the last facing", knight.last_direction == "up")
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("move_down")
	knight.start_riposte(Vector2(30, 0))
	check("a riposte still aims at the attacker, even with another key held", knight.last_direction == "right", knight.last_direction)
	await end_arena(a)

	# ----------------------------------------------------- riposte follow-up
	print("[Riposte -> heavy finisher]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	knight.start_riposte(Vector2(30, 0))
	knight.anim.pause()   # hold it on frame 0 (headless frame timing is too coarse to hit it otherwise)
	Input.action_press("attack_light")   # pressed on the riposte's very first frame
	await frames(2)
	Input.action_release("attack_light")
	check("light pressed before the riposte's hit frame is kept", knight.combo_queued and knight.anim.frame < knight.current_attack.hit_frame, "frame %d" % knight.anim.frame)
	knight.anim.play()
	var got_heavy := false
	for i in 90:
		await physics_frame
		if knight.current_attack != null and knight.current_attack.anim == &"attack_heavy":
			got_heavy = true
			break
	check("...and the heavy finisher follows the riposte", got_heavy)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	await tap_light()
	await frames(4)
	knight.start_attack(knight.light_combo[0], true)   # a normal (non-riposte) swing
	knight.anim.pause()
	Input.action_press("attack_light")
	await frames(2)
	Input.action_release("attack_light")
	check("a normal swing still ignores presses before its hit frame (no mash-chaining)", not knight.combo_queued and knight.anim.frame < knight.current_attack.hit_frame)
	knight.anim.play()
	await end_arena(a)

	var windows := {}
	for riposte in [false, true]:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		await frames(2)
		if riposte:
			knight.start_riposte(Vector2(30, 0))
		else:
			knight.combo_index = 2
			knight.start_attack(knight.light_combo[1], true)
		for i in 120:
			await physics_frame
			if knight.state == knight.State.FREE:
				break
		windows[riposte] = knight.combo_window
		await end_arena(a)
	check("follow-up window after a riposte is 0.5s", is_equal_approx(windows[true], 0.5), "%.3f" % windows[true])
	check("normal combo window is unchanged at 0.35s", is_equal_approx(windows[false], 0.35), "%.3f" % windows[false])

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	knight.start_riposte(Vector2(30, 0))
	for i in 120:
		await physics_frame
		if knight.state == knight.State.FREE:
			break
	await frames(27)   # 0.45s after the riposte ended: too late before, fine now
	await tap_light()
	check("a press 0.45s after the riposte ends still gets the heavy", knight.current_attack != null and knight.current_attack.anim == &"attack_heavy")
	await end_arena(a)

func tap_light() -> void:
	Input.action_press("attack_light")
	await frames(2)
	Input.action_release("attack_light")
