extends SceneTree
# Damage numbers: behaviour checks plus screenshots.
#   xvfb-run godot --path <project> --fixed-fps 60 --rendering-driver opengl3 -s res://dev_tools/damage_number_tests.gd -- out=/tmp/dmg
# (With --headless the checks still run; the screenshots are skipped.)

var out_dir := ""
var arena: Node2D
var knight: Node2D
var orc: Node2D
var passed := 0
var failed := 0

func check(what: String, ok: bool, got: Variant = "") -> void:
	if ok:
		passed += 1
		print("  PASS  ", what)
	else:
		failed += 1
		print("  FAIL  ", what, "  ", got)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func shot(file: String) -> void:
	if out_dir == "":
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(file + ".png"))
	print("  saved ", file)

func numbers() -> Array:
	return arena.find_children("*", "DamageNumber", true, false).filter(func(n): return not n.fading)

func all_numbers() -> Array:
	return arena.find_children("*", "DamageNumber", true, false)

func setup(enemy_scene := "res://orc.tscn", gap := 16.0) -> void:
	if arena:
		arena.queue_free()
		await frames(2)
	arena = Node2D.new()
	root.add_child(arena)
	var chunk: Node2D = load("res://rooms/chunks/chunk_template.tscn").instantiate()
	arena.add_child(chunk)
	var spot: Vector2 = chunk.get_node("EnemySpawn/Marker2D").global_position
	knight = load("res://Knight.tscn").instantiate()
	knight.position = spot
	arena.add_child(knight)
	orc = load(enemy_scene).instantiate()
	orc.position = spot + Vector2(gap, 0)
	arena.add_child(orc)
	orc.player = null
	orc.set_physics_process(false)   # stands still and never swings back
	knight.camera.make_current()   # screenshots at the real in-game zoom
	await frames(3)
	orc.health = 999

# One "tap" of the light attack button.
func tap(action := "attack_light") -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame

func mash_until_hits(n: int, max_frames := 300) -> void:
	var start: int = 999 - orc.health
	var hp_seen: int = orc.health
	var count := 0
	for f in max_frames:
		if f % 4 == 0:
			await tap()
		else:
			await physics_frame
		if orc.health != hp_seen:
			hp_seen = orc.health
			count += 1
			if count >= n:
				return

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
			DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(640, 360)
	await process_frame

	print("-- single hit")
	await setup()
	await mash_until_hits(1)
	var n := numbers()
	check("one light hit makes one number", n.size() == 1, n.size())
	if n.size() == 1:
		check("...showing the damage (10)", n[0].label.text == "10", n[0].label.text)
		check("...in the enemy style", n[0].style == DamageNumber.Style.ENEMY)
		await frames(15)   # let the flash settle
		check("...and it's white", n[0].label.modulate.is_equal_approx(DamageNumber.COLOR_HIT), n[0].label.modulate)
		await shot("1_single_hit")
	await frames(60 * 2)
	check("it fades out and frees itself after the window", all_numbers().size() == 0, all_numbers().size())

	print("-- combo adds up")
	await setup()
	await mash_until_hits(2)
	n = numbers()
	check("second combo hit adds to the same number", n.size() == 1, n.size())
	if n.size() == 1:
		check("...10 + 12 = 22", n[0].label.text == "22", n[0].label.text)
		await process_frame
		check("...it flashes on the hit (starts white)", n[0].label.modulate.b > 0.8, n[0].label.modulate)
		await shot("2a_combo_flash")
		await frames(15)
		check("...then settles to yellow", n[0].label.modulate.is_equal_approx(DamageNumber.COLOR_COMBO), n[0].label.modulate)
		await shot("2b_combo_yellow")
	await mash_until_hits(1)
	n = numbers()
	check("the heavy finisher still lands on the same number", n.size() == 1, n.size())
	if n.size() == 1:
		check("...10 + 12 + 25 = 47", n[0].label.text == "47", n[0].label.text)
		await frames(3)
		await shot("2c_combo_finisher")

	print("-- a pause starts a fresh number")
	await frames(60 * 2)
	await mash_until_hits(1)
	n = numbers()
	check("hit after a pause: a new number", n.size() == 1 and n[0].label.text == "10", n.map(func(x): return x.label.text))

	print("-- guarded hit")
	await setup("res://armored_orc.tscn", 16.0)
	orc.anim.flip_h = true   # face the knight (he's on the left)
	orc.change_state(orc.State.GUARD)
	orc.guard_left = 99.0
	var hp_before: int = orc.health
	orc.take_damage(10, knight.global_position)
	n = numbers()
	var expected: int = hp_before - orc.health
	check("guarded hit shows what got through (%d)" % expected, n.size() == 1 and n[0].label.text == str(expected), n.map(func(x): return x.label.text))
	await frames(15)
	if n.size() == 1:
		check("...in grey", n[0].label.modulate.is_equal_approx(DamageNumber.COLOR_GUARDED), n[0].label.modulate)
		await shot("3_guarded")

	print("-- killing blow")
	await setup()
	orc.set_physics_process(true)   # the death animation needs it to finish
	orc.health = 5
	orc.take_damage(12, knight.global_position)
	check("the killing blow shows the full hit (12)", numbers().size() == 1 and numbers()[0].label.text == "12")
	await frames(10)
	await shot("4_kill")
	for i in 120:
		await physics_frame
	check("the orc is gone...", not is_instance_valid(orc))
	# The number itself fades on its own timer; it must not have been freed with the orc
	# before then (it lives in the level, not on the orc).

	print("-- kill frees enemy before number fades")
	await setup()
	orc.set_physics_process(true)
	orc.health = 5
	orc.take_damage(12, knight.global_position)
	var num: Node = numbers()[0]
	orc.queue_free()
	await frames(2)
	check("number survives its enemy being freed", is_instance_valid(num))

	print("-- arrow")
	await setup("res://orc.tscn", 60.0)
	var screen := root.get_canvas_transform() * orc.global_position
	root.warp_mouse(screen)   # the bow aims at the mouse
	await frames(2)
	knight.start_attack(knight.ranged_attack)
	for i in 120:
		await physics_frame
		if orc.health != 999:
			break
	n = numbers()
	check("an arrow hit shows a number", n.size() == 1 and n[0].label.text == str(999 - orc.health), n.map(func(x): return x.label.text))

	print("-- knight takes damage")
	await setup()
	knight.take_damage(8, orc.global_position, 0.0)
	n = numbers()
	check("knight hurt: one number (8)", n.size() == 1 and n[0].label.text == "8", n.map(func(x): return x.label.text))
	if n.size() == 1:
		check("...in the ally style", n[0].style == DamageNumber.Style.ALLY)
		await frames(15)
		check("...red", n[0].label.modulate.is_equal_approx(DamageNumber.COLOR_TAKEN), n[0].label.modulate)
		await shot("5_knight_hurt")
	await frames(20)
	knight.change_state(knight.State.FREE)
	knight.take_damage(12, orc.global_position, 0.0)
	n = numbers()
	check("hits close together add up on him too (8 + 12 = 20)", n.size() == 1 and n[0].label.text == "20", n.map(func(x): return x.label.text))
	await frames(15)
	if n.size() == 1:
		check("...and stay red (not yellow)", n[0].label.modulate.is_equal_approx(DamageNumber.COLOR_TAKEN), n[0].label.modulate)

	print("-- fully blocked hit")
	await setup()
	await frames(60 * 2)
	knight.change_state(knight.State.BLOCK)
	knight.block_time = 1.0   # well past the parry window: a plain block
	var hp_k: int = knight.health
	var r: int = knight.take_damage(5, orc.global_position, 0.0)
	check("a fully blocked hit (%s) shows no number" % Combat.HitResult.keys()[r], r == Combat.HitResult.BLOCKED and numbers().size() == 0 and knight.health == hp_k, numbers().size())

	print("-- healer takes damage")
	await setup()
	var healer: Node2D = load("res://healer.tscn").instantiate()
	healer.knight = knight
	healer.position = knight.position + Vector2(-18, -3)
	arena.add_child(healer)
	await frames(3)
	healer.take_damage(6)
	n = numbers().filter(func(x): return x.target == healer)
	check("healer hurt: a red number (6)", n.size() == 1 and n[0].label.text == "6" and n[0].style == DamageNumber.Style.ALLY, n.size())
	await frames(15)
	await shot("6_healer_hurt")

	print("\n%d passed, %d failed" % [passed, failed])
	quit()
