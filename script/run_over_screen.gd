extends CanvasLayer
## Shown when a run ends, by death or by clearing the last room.

signal new_run_requested

@onready var title_label: Label = %Title
@onready var body_label: Label = %Body
@onready var new_run_button: Button = %NewRun

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	new_run_button.pressed.connect(func(): new_run_requested.emit())
	hide()

func show_result(won: bool, run: RunState) -> void:
	title_label.text = "RUN COMPLETE" if won else "YOU DIED"
	var names: PackedStringArray = []
	for upgrade in run.upgrades_taken:
		names.append(upgrade.title)
	body_label.text = "Rooms cleared: %d / %d\nUpgrades: %s\nSeed: %d" % [
		run.rooms_cleared, RunState.RUN_LENGTH,
		", ".join(names) if not names.is_empty() else "none", run.run_seed]
	show()
	get_tree().paused = true
	new_run_button.grab_focus()
