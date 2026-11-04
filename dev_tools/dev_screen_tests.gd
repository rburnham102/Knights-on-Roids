extends SceneTree
# Tests for the dev start screen in run.tscn.
#   godot --headless --fixed-fps 60 --path <project> -s res://dev_tools/dev_screen_tests.gd

const RUN := "res://run.tscn"
const POWER := "res://upgrades/power_up.tres"
const VITALITY := "res://upgrades/vitality_up.tres"
const SIEGE := "res://upgrades/charged_shot.tres"
const HEALER := "res://upgrades/healer.tres"

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
		await process_frame

# Boots run.tscn the way the game does: as the current scene.
func boot(setup := Callable()) -> Node:
	var scene: Node = load(RUN).instantiate()
	scene.get_node("RunManager").character_select_enabled = false   # plays the first class, the Knight
	if setup.is_valid():
		setup.call(scene.get_node("RunManager"))
	root.add_child(scene)
	current_scene = scene
	await frames(3)
	return scene

# A fresh run (New Run) opens the character select: pick the Knight.
func pick_knight(scene: Node) -> void:
	scene.get_node("CharacterSelect").choose(0)
	await frames(2)

func shutdown(scene: Node) -> void:
	paused = false
	scene.queue_free()
	current_scene = null
	await frames(3)

func spin_for(screen: Node, path: String) -> SpinBox:
	for upgrade: Upgrade in screen.spin_boxes:
		if upgrade.resource_path == path:
			return screen.spin_boxes[upgrade]
	return null

func _initialize() -> void:
	await run()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame

	print("[Shows at boot]")
	var scene := await boot()
	var mgr: Node = scene.get_node("RunManager")
	var screen: Node = scene.get_node("DevScreen")
	check("dev screen is visible and the game is paused", screen.visible and paused)
	check("it's above the black fade (layer 20 > 10)", screen.layer > scene.get_node("FadeLayer").layer)
	await frames(30)
	check("the run waits: no room built yet", mgr.room == null and mgr.run.depth == 0)
	check("one row per upgrade in the pool", screen.spin_boxes.size() == mgr.pool.size(),
		"%d rows, %d upgrades" % [screen.spin_boxes.size(), mgr.pool.size()])
	check("healer capped at 1, others at 5",
		spin_for(screen, HEALER).max_value == 1 and spin_for(screen, POWER).max_value == 5)
	check("start room goes 1 to RUN_LENGTH", screen.room_box.min_value == 1 and screen.room_box.max_value == RunState.RUN_LENGTH)

	print("[A bad seed is refused]")
	screen.seed_edit.text = "abc"
	screen.start_button.pressed.emit()
	await frames(2)
	check("still open, still paused, error shown", screen.visible and paused and screen.seed_error.visible)

	print("[Start with a loadout]")
	spin_for(screen, POWER).value = 2
	spin_for(screen, VITALITY).value = 1
	spin_for(screen, SIEGE).value = 2
	spin_for(screen, HEALER).value = 1
	screen.room_box.value = 5
	screen.seed_edit.text = "12345"
	screen.start_button.pressed.emit()
	await frames(30)
	var knight: Node = mgr.knight
	check("screen hidden and game running", not screen.visible and not paused)
	check("starts in room 5", mgr.run.depth == 5 and mgr.room != null, "depth %d" % mgr.run.depth)
	check("HUD shows room 5", scene.get_node("HUD").room_label.text.contains("5"), scene.get_node("HUD").room_label.text)
	check("the typed seed is used", mgr.run.run_seed == 12345, str(mgr.run.run_seed))
	check("Brute Strength x2 -> power 14", knight.stats.power == 14, str(knight.stats.power))
	check("Thick Hide x1 -> vitality 12, at full 110 health",
		knight.stats.vitality == 12 and knight.health == knight.max_health() and knight.max_health() == 110,
		"vit %d hp %d/%d" % [knight.stats.vitality, knight.health, knight.max_health()])
	check("Siege Shot x2 -> perk stacks 2 (2.5 s charge)", knight.perk(&"charged_shot") == 2 and is_equal_approx(knight.full_charge_time(), 2.5))
	check("the healer was hired and is in the level", is_instance_valid(mgr.healer) and mgr.healer.is_inside_tree())
	check("...and taken out of the upgrade pool", not mgr.HEALER_UPGRADE in mgr.pool)
	check("the end screen will list all 6 picks", mgr.run.upgrades_taken.size() == 6, str(mgr.run.upgrades_taken.size()))

	print("[New Run reopens it with the same loadout]")
	mgr._on_new_run_requested()   # what the end screen's New Run button does
	await frames(5)
	scene = current_scene
	mgr = scene.get_node("RunManager")
	screen = scene.get_node("DevScreen")
	# A fresh run asks for a character first; the dev screen comes after.
	var select: CanvasLayer = scene.get_node("CharacterSelect")
	check("fresh run opens the character select first", select.visible and not screen.visible)
	await pick_knight(scene)   # the Knight, so the Siege Shot row exists
	check("fresh run, dev screen open again", screen.visible and paused and mgr.room == null)
	check("remembers the counts", spin_for(screen, POWER).value == 2 and spin_for(screen, SIEGE).value == 2 and spin_for(screen, HEALER).value == 1)
	check("remembers room and seed", screen.room_box.value == 5 and screen.seed_edit.text == "12345")

	print("[Start again from the remembered loadout]")
	screen.start_button.pressed.emit()
	await frames(30)
	check("seed 12345 again", mgr.run.run_seed == 12345)

	print("[Clear = a plain run]")
	mgr._on_new_run_requested()
	await frames(5)
	scene = current_scene
	mgr = scene.get_node("RunManager")
	screen = scene.get_node("DevScreen")
	await pick_knight(scene)
	screen.clear_button.pressed.emit()
	check("Clear zeroes every count, room 1, blank seed",
		screen.spin_boxes.values().all(func(s): return s.value == 0) and screen.room_box.value == 1 and screen.seed_edit.text == "")
	screen.start_button.pressed.emit()
	await frames(30)
	knight = mgr.knight
	check("room 1, no perks, base stats, no healer",
		mgr.run.depth == 1 and knight.perks.is_empty() and knight.stats.power == 10 and mgr.healer == null)
	check("blank seed = a random seed", mgr.run.run_seed != 0 and mgr.run.run_seed != 12345)
	await shutdown(scene)

	print("[Toggle off]")
	scene = await boot(func(m): m.dev_screen_enabled = false)
	mgr = scene.get_node("RunManager")
	await frames(30)
	check("dev_screen_enabled = false: no screen, the run starts", not scene.get_node("DevScreen").visible and not paused and mgr.run.depth == 1 and mgr.room != null)
	await shutdown(scene)

	print("[Inspector start_seed still works when the seed box is blank]")
	scene = await boot(func(m): m.start_seed = 999)
	mgr = scene.get_node("RunManager")
	screen = scene.get_node("DevScreen")
	await pick_knight(scene)
	screen.clear_button.pressed.emit()
	screen.start_button.pressed.emit()
	await frames(30)
	check("start_seed 999 used", mgr.run.run_seed == 999, str(mgr.run.run_seed))
	await shutdown(scene)
