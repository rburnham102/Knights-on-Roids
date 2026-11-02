extends SceneTree
# Screenshots of the new effects next to the knight, for judging scale.
#   xvfb-run godot --path <project> --fixed-fps 60 -s res://dev_tools/render_fx.gd -- out=/tmp/renders

var out_dir := "/tmp"
var knight: Node2D
var arena: Node2D

func shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

# The real mouse can be moved under xvfb; aim it at a world point.
func aim_at(world: Vector2) -> void:
	var screen := root.get_canvas_transform() * world
	root.warp_mouse(screen)
	Input.warp_mouse(screen)

func setup() -> void:
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
	knight.perks = {&"charged_shot": 1}
	arena.add_child(knight)
	var orc: Node2D = load("res://orc.tscn").instantiate()
	orc.position = spot + Vector2(70, 0)
	arena.add_child(orc)
	orc.player = null
	orc.set_physics_process(false)
	await frames(3)
	orc.health = 999

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	root.size = Vector2i(640, 360)
	await process_frame
	await setup()

	# Heavy attack: grab a few frames of the ground splash.
	knight.start_attack(knight.heavy_attack)
	while knight.anim.frame < 4:
		await physics_frame
	await shot("heavy_1")
	await frames(6)
	await shot("heavy_2")
	await frames(8)
	await shot("heavy_3")

	# Charging bow.
	await setup()
	await frames(5)
	aim_at(knight.global_position + Vector2(70, -7))
	Input.action_press("attack_bow")
	while not knight.is_charging:
		await physics_frame
	await shot("charge_0")
	await frames(120)
	await shot("charge_50")
	await frames(125)
	await shot("charge_100")
	Input.action_release("attack_bow")
	await frames(2)
	await shot("release_1")
	await frames(3)
	await shot("release_2")
	await frames(4)
	await shot("hit_1")
	await frames(6)
	await shot("hit_2")
	quit()
