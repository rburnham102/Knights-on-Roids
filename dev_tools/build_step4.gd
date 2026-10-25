extends SceneTree
# One-off generator for step 4's scenes and resources.
#   godot --headless --path . -s res://build_step4.gd -- 1     (tileset, door, rooms, upgrades, screens)
#   godot --headless --path . -s res://build_step4.gd -- 2     (run.tscn)

const WALL := Vector2i(4, 8)    # the stone ledge tile (collides)
const FLOOR := Vector2i(1, 1)   # plain ground

func _initialize() -> void:
	var phase: String = OS.get_cmdline_user_args()[0]
	if phase == "1":
		make_tileset()
		make_door()
		make_rooms()
		make_upgrades()
		make_screens()
	else:
		make_run_scene()
	quit()

func own_all(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		own_all(child, root)

func save_scene(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	err = ResourceSaver.save(packed, path) if err == OK else err
	print("saved ", path, " -> ", "ok" if err == OK else "ERROR %d" % err)
	root.free()

# ---------------------------------------------------------------- tileset
func make_tileset() -> void:
	var game: Node = load("res://game.tscn").instantiate()
	var tile_map: TileMap = game.get_node("TileMap")
	print("tileset saved: ", ResourceSaver.save(tile_map.tile_set, "res://tileset.tres") == OK)
	game.free()

# ------------------------------------------------------------------- door
func make_door() -> void:
	var door := Node2D.new()
	door.name = "ExitDoor"
	door.set_script(load("res://exit_door.gd"))
	var blocker := StaticBody2D.new()
	blocker.name = "Blocker"
	blocker.collision_layer = 1   # world
	blocker.collision_mask = 0
	var block_shape := CollisionShape2D.new()
	block_shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 32)
	block_shape.shape = rect
	blocker.add_child(block_shape)
	door.add_child(blocker)
	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.position = Vector2(-8, -16)
	visual.size = Vector2(16, 32)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	door.add_child(visual)
	var trigger := Area2D.new()
	trigger.name = "Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 2   # the knight's body
	var trig_shape := CollisionShape2D.new()
	trig_shape.name = "CollisionShape2D"
	var trig_rect := RectangleShape2D.new()
	trig_rect.size = Vector2(28, 40)
	trig_shape.shape = trig_rect
	trigger.add_child(trig_shape)
	door.add_child(trigger)
	own_all(door, door)
	save_scene(door, "res://exit_door.tscn")

# ------------------------------------------------------------------ rooms
func make_rooms() -> void:
	build_room("room_arena", 24, 13, [],
		[Vector2i(10, 3), Vector2i(10, 9), Vector2i(14, 6), Vector2i(17, 3), Vector2i(17, 9), Vector2i(20, 6)])
	build_room("room_pillars", 24, 13,
		[Rect2i(8, 3, 2, 2), Rect2i(8, 8, 2, 2), Rect2i(14, 5, 2, 3)],
		[Vector2i(11, 6), Vector2i(12, 2), Vector2i(12, 10), Vector2i(17, 3), Vector2i(17, 9), Vector2i(20, 6)])
	build_room("room_hall", 32, 11,
		[Rect2i(10, 2, 2, 2), Rect2i(10, 7, 2, 2), Rect2i(19, 4, 2, 3)],
		[Vector2i(14, 5), Vector2i(15, 2), Vector2i(15, 8), Vector2i(23, 2), Vector2i(23, 8), Vector2i(27, 5), Vector2i(28, 3)])

func build_room(file: String, w: int, h: int, blocks: Array, spawns: Array) -> void:
	var room := Node2D.new()
	room.name = "Room"
	room.set_script(load("res://room.gd"))
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = load("res://tileset.tres")
	room.add_child(ground)
	var mid: int = h / 2
	for x in w:
		for y in h:
			var on_border: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			var in_gap: bool = x == w - 1 and (y == mid - 1 or y == mid)   # where the door sits
			ground.set_cell(Vector2i(x, y), 0, WALL if (on_border and not in_gap) else FLOOR)
	for block in blocks:
		for x in range(block.position.x, block.end.x):
			for y in range(block.position.y, block.end.y):
				ground.set_cell(Vector2i(x, y), 0, WALL)
	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = ground.map_to_local(Vector2i(2, mid))
	room.add_child(start)
	var spawn_root := Node2D.new()
	spawn_root.name = "EnemySpawns"
	room.add_child(spawn_root)
	for i in spawns.size():
		var marker := Marker2D.new()
		marker.name = "Spawn%d" % (i + 1)
		marker.position = ground.map_to_local(spawns[i])
		spawn_root.add_child(marker)
	var door: Node2D = load("res://exit_door.tscn").instantiate()
	door.position = ground.map_to_local(Vector2i(w - 1, mid - 1)) + Vector2(0, 8)
	room.add_child(door)
	# Everything gets the room as owner, but not the door's own children
	# (they stay part of the door scene).
	for child in room.get_children():
		child.owner = room
	for child in spawn_root.get_children():
		child.owner = room
	save_scene(room, "res://rooms/%s.tscn" % file)

# --------------------------------------------------------------- upgrades
func make_upgrades() -> void:
	var defs := [
		["power_up", "Brute Strength", "+2 Power\nHit harder, knock enemies back farther, and break poise faster.", 2, 0, 0, 0, ""],
		["dexterity_up", "Quick Feet", "+2 Dexterity\nMove faster, dodge farther, and get a wider parry window.", 0, 2, 0, 0, ""],
		["vitality_up", "Thick Hide", "+2 Vitality\nMore maximum health (and you heal the difference).", 0, 0, 2, 0, ""],
		["field_dressing", "Field Dressing", "Restore 35 health right now.", 0, 0, 0, 35, ""],
		["parry_mend", "Parry & Mend", "Every perfect parry heals you for 5.", 0, 0, 0, 0, "parry_heal"],
		["brutal_riposte", "Brutal Riposte", "Your riposte hits 60% harder.", 0, 0, 0, 0, "riposte_power"],
		["ghost_step", "Ghost Step", "Your dodge stays invulnerable 0.06s longer.", 0, 0, 0, 0, "long_dodge"],
		["light_footed", "Light Footed", "Your dodge cooldown is 0.2s shorter.", 0, 0, 0, 0, "quick_dodge"],
		["iron_guard", "Iron Guard", "Your guard recovers 50% faster.", 0, 0, 0, 0, "iron_guard"],
	]
	for d in defs:
		var upgrade := Upgrade.new()
		upgrade.title = d[1]
		upgrade.description = d[2]
		upgrade.power = d[3]
		upgrade.dexterity = d[4]
		upgrade.vitality = d[5]
		upgrade.heal = d[6]
		upgrade.perk = StringName(d[7])
		print("upgrade ", d[0], ": ", ResourceSaver.save(upgrade, "res://upgrades/%s.tres" % d[0]) == OK)

# ---------------------------------------------------------------- screens
func full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func make_label(label_name: String, size: int, unique := true) -> Label:
	var label := Label.new()
	label.name = label_name
	label.unique_name_in_owner = unique
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label

func make_screens() -> void:
	# --- upgrade screen
	var layer := CanvasLayer.new()
	layer.name = "UpgradeScreen"
	layer.layer = 5
	layer.set_script(load("res://upgrade_screen.gd"))
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.7)
	layer.add_child(dim)
	full_rect(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	layer.add_child(center)
	full_rect(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var header := make_label("Header", 26)
	header.text = "Choose an upgrade"
	box.add_child(header)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	for i in 3:
		var button := Button.new()
		button.name = "Choice%d" % (i + 1)
		button.unique_name_in_owner = true
		button.custom_minimum_size = Vector2(250, 170)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 15)
		row.add_child(button)
	own_all(layer, layer)
	save_scene(layer, "res://upgrade_screen.tscn")
	# --- run over screen
	var over := CanvasLayer.new()
	over.name = "RunOverScreen"
	over.layer = 6
	over.set_script(load("res://run_over_screen.gd"))
	var over_dim := ColorRect.new()
	over_dim.name = "Dim"
	over_dim.color = Color(0, 0, 0, 0.8)
	over.add_child(over_dim)
	full_rect(over_dim)
	var over_center := CenterContainer.new()
	over_center.name = "Center"
	over.add_child(over_center)
	full_rect(over_center)
	var over_box := VBoxContainer.new()
	over_box.name = "Box"
	over_box.add_theme_constant_override("separation", 22)
	over_center.add_child(over_box)
	over_box.add_child(make_label("Title", 44))
	over_box.add_child(make_label("Body", 20))
	var new_run := Button.new()
	new_run.name = "NewRun"
	new_run.unique_name_in_owner = true
	new_run.text = "New run"
	new_run.custom_minimum_size = Vector2(220, 52)
	new_run.add_theme_font_size_override("font_size", 20)
	over_box.add_child(new_run)
	own_all(over, over)
	save_scene(over, "res://run_over_screen.tscn")

# -------------------------------------------------------------- run scene
func make_run_scene() -> void:
	var root := Node2D.new()
	root.name = "Run"
	root.set_script(load("res://game.gd"))
	var room_holder := Node2D.new()
	room_holder.name = "RoomHolder"
	root.add_child(room_holder)
	var actors := Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	root.add_child(actors)
	var knight: CharacterBody2D = load("res://Knight.tscn").instantiate()
	actors.add_child(knight)
	var hud: CanvasLayer = load("res://hud.tscn").instantiate()
	root.add_child(hud)
	var upgrade_screen: CanvasLayer = load("res://upgrade_screen.tscn").instantiate()
	root.add_child(upgrade_screen)
	var end_screen: CanvasLayer = load("res://run_over_screen.tscn").instantiate()
	root.add_child(end_screen)
	var fade_layer := CanvasLayer.new()
	fade_layer.name = "FadeLayer"
	fade_layer.layer = 10
	root.add_child(fade_layer)
	var fade_rect := ColorRect.new()
	fade_rect.name = "Rect"
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)
	full_rect(fade_rect)
	var manager := Node.new()
	manager.name = "RunManager"
	manager.set_script(load("res://run_manager.gd"))
	root.add_child(manager)
	for node in [room_holder, actors, knight, hud, upgrade_screen, end_screen, fade_layer, fade_rect, manager]:
		node.owner = root
	manager.set("knight", knight)
	manager.set("actors", actors)
	manager.set("room_holder", room_holder)
	manager.set("hud", hud)
	manager.set("upgrade_screen", upgrade_screen)
	manager.set("end_screen", end_screen)
	manager.set("fade_rect", fade_rect)
	save_scene(root, "res://run.tscn")
