extends CanvasLayer
## Debug-only screen shown before a run: pick a starting loadout of upgrades,
## a starting room and a seed, then press Start. The RunManager opens it (in
## debug builds, i.e. when you run from the editor) and waits for `started`.

## picks: Upgrade -> how many times to take it. run_seed 0 = random.
signal started(picks: Dictionary, start_room: int, run_seed: int)

const MAX_STACKS := 5

## What you set up last time. A static var belongs to the script, not to any
## one node, so it survives reload_current_scene() (the New Run button) for
## as long as the game is running. The next run opens with the same loadout.
static var last_counts := {}   # upgrade resource_path -> count
static var last_room := 1
static var last_seed := ""

var spin_boxes := {}   # Upgrade -> its SpinBox

@onready var grid: GridContainer = %Grid
@onready var room_box: SpinBox = %StartRoom
@onready var seed_edit: LineEdit = %Seed
@onready var seed_error: Label = %SeedError
@onready var start_button: Button = %Start
@onready var clear_button: Button = %Clear

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep working while the game is paused
	start_button.pressed.connect(_on_start_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	seed_edit.text_submitted.connect(func(_text): _on_start_pressed())   # Enter in the seed box starts too
	seed_error.hide()
	hide()

## Builds one row per upgrade and shows the screen. `one_only` lists upgrades
## that can't stack (the healer).
func open(upgrades: Array, run_length: int, one_only: Array = []) -> void:
	for child in grid.get_children():
		child.queue_free()
	spin_boxes.clear()
	for upgrade: Upgrade in upgrades:
		var label := Label.new()
		label.text = upgrade.title
		label.tooltip_text = upgrade.description
		label.mouse_filter = Control.MOUSE_FILTER_PASS   # Labels ignore the mouse by default, so no tooltip without this
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # names take the spare width, boxes line up on the right
		grid.add_child(label)

		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 1 if upgrade in one_only else MAX_STACKS
		spin.value = last_counts.get(upgrade.resource_path, 0)
		spin.tooltip_text = upgrade.description
		grid.add_child(spin)
		spin_boxes[upgrade] = spin

	room_box.min_value = 1
	room_box.max_value = run_length
	room_box.value = last_room
	seed_edit.text = last_seed
	show()
	get_tree().paused = true
	start_button.grab_focus()

func _on_clear_pressed() -> void:
	for spin: SpinBox in spin_boxes.values():
		spin.value = 0
	room_box.value = 1
	seed_edit.text = ""
	seed_error.hide()

func _on_start_pressed() -> void:
	if not visible:
		return
	# Seeds are 64-bit, too big for a SpinBox to hold exactly, so it's typed text.
	var seed_text := seed_edit.text.strip_edges()
	if seed_text != "" and not seed_text.is_valid_int():
		seed_error.show()
		return
	var run_seed := seed_text.to_int() if seed_text != "" else 0

	var picks := {}
	last_counts.clear()
	for upgrade: Upgrade in spin_boxes:
		var count := int(spin_boxes[upgrade].value)
		if count > 0:
			picks[upgrade] = count
			last_counts[upgrade.resource_path] = count
	last_room = int(room_box.value)
	last_seed = seed_text

	hide()
	get_tree().paused = false
	started.emit(picks, last_room, run_seed)
