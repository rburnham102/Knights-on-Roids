extends CanvasLayer
## Pauses the game and offers a choice of upgrades.

signal chosen(upgrade: Upgrade)

var offered: Array[Upgrade] = []
var buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep working while the game is paused
	for node in [%Choice1, %Choice2, %Choice3]:
		buttons.append(node)
	for i in buttons.size():
		buttons[i].pressed.connect(choose.bind(i))
	hide()

func show_choices(choices: Array[Upgrade]) -> void:
	offered = choices
	for i in buttons.size():
		buttons[i].visible = i < choices.size()
		if i < choices.size():
			buttons[i].text = "%d.  %s\n\n%s" % [i + 1, choices[i].title, choices[i].description]
	show()
	get_tree().paused = true
	buttons[0].grab_focus()

func choose(index: int) -> void:
	if not visible or index >= offered.size():
		return
	var upgrade := offered[index]
	hide()
	get_tree().paused = false
	chosen.emit(upgrade)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: choose(0)
		KEY_2: choose(1)
		KEY_3: choose(2)
