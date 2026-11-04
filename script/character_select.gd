extends CanvasLayer
## Shown when a run starts: pick who to play. The RunManager opens it with
## its list of CharacterClass resources and waits for `chosen`.
## One button per class is built in code, so adding a character never needs
## an edit to this scene.

signal chosen(character: CharacterClass)

## The last pick. A static var belongs to the script, not to the node, so it
## survives reload_current_scene() (the New Run button): the next run opens
## with the same character selected, and Enter starts it again.
static var last_index := 0

var classes: Array[CharacterClass] = []
var buttons: Array[Button] = []

@onready var row: HBoxContainer = %Row

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep working while the game is paused
	hide()

func open(character_classes: Array[CharacterClass]) -> void:
	classes = character_classes
	for child in row.get_children():
		child.queue_free()
	buttons.clear()
	for i in classes.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(210, 300)   # tall enough for 5 lines of description
		button.add_child(_card(classes[i], i + 1))
		button.pressed.connect(choose.bind(i))
		row.add_child(button)
		buttons.append(button)
	show()
	buttons[clampi(last_index, 0, buttons.size() - 1)].grab_focus()

# What's drawn on a button: portrait on top, name and description underneath.
# A Button can't lay out children itself, so a VBoxContainer fills it. Every
# child ignores the mouse, so clicks and hovers still reach the button.
func _card(character: CharacterClass, number: int) -> Control:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)

	var portrait := TextureRect.new()
	portrait.texture = character.portrait
	portrait.custom_minimum_size = Vector2(112, 112)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)

	var title := Label.new()
	title.text = "%d.  %s" % [number, character.display_name]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var text := Label.new()
	text.text = character.description
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)
	return box

func choose(index: int) -> void:
	if not visible or index >= classes.size():
		return
	last_index = index
	hide()
	chosen.emit(classes[index])

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# 1, 2, 3... pick by number, like the upgrade screen.
	var index: int = event.keycode - KEY_1
	if index >= 0 and index < classes.size():
		choose(index)
