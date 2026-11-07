class_name DamageNumber
extends Node2D
## A number that pops up over whoever was just hit.
##
## Hits that land close together on the same target add up into ONE number
## (a combo), which pops and flashes with every new hit. When the hits stop,
## the number floats up, fades out and frees itself.
##
## Whoever takes damage calls one line, keeping the returned number so the
## next hit can add to it:
##     damage_number = DamageNumber.add_hit(damage_number, self, amount)

const SCENE := preload("res://damage_number.tscn")

## Who the number is for. Enemies are hit BY the player (white, then yellow
## in a combo); allies are the player's side TAKING damage (red).
enum Style { ENEMY, ALLY }

const COLOR_HIT := Color(1.0, 1.0, 1.0)          # a single hit on an enemy
const COLOR_COMBO := Color(1.0, 0.85, 0.2)       # two or more hits adding up
const COLOR_GUARDED := Color(0.65, 0.65, 0.65)   # soaked up by a shield
const COLOR_TAKEN := Color(1.0, 0.25, 0.2)       # the knight or healer was hurt
const COLOR_FLASH := Color(1.0, 1.0, 1.0)        # every hit starts here, then fades to its colour

## Seconds after a hit during which the next hit still adds to this number.
## A bit longer than the slowest gap in a combo chain (the wind-up into the
## heavy finisher is ~0.85 s), so a whole chain stays one number.
const COMBO_WINDOW := 1.0
const HEAD_OFFSET := Vector2(0, -18)   # where the number sits, relative to the target's feet
const POP_SCALE := 1.6                 # how big each hit makes it before it settles
const POP_TIME := 0.15
const FLASH_TIME := 0.2
const FLOAT_DISTANCE := 10.0           # pixels it rises while fading out
const FADE_TIME := 0.45

@onready var label: Label = $Label

var style := Style.ENEMY
var total := 0
var hits := 0
var any_unguarded := false
var target: Node2D
var open_left := 0.0      # seconds until it stops accepting hits
var fading := false
var pop_tween: Tween

## The one function other scripts call. Adds `amount` to `current` if it is
## still open, otherwise starts a new number above `who`. Returns the number
## that now shows the hit, so the caller can keep it for next time.
## `current` is deliberately untyped: once a number has faded it frees itself,
## and Godot refuses to pass a freed object into a typed parameter.
static func add_hit(current, who: Node2D, amount: int, guarded := false, number_style := Style.ENEMY) -> DamageNumber:
	if not is_instance_valid(current) or current.fading:
		current = SCENE.instantiate()
		current.style = number_style
		current.target = who
		# A sibling of the target, not its child: the number must survive the
		# enemy being freed, and shouldn't be shoved around by its knockback.
		who.get_parent().add_child(current)
	current.add(amount, guarded)
	return current

func add(amount: int, guarded: bool) -> void:
	total += amount
	hits += 1
	any_unguarded = any_unguarded or not guarded
	open_left = COMBO_WINDOW
	label.text = str(total)
	_follow_target()

	# Pop: jump big, settle back. Restarted on every hit.
	if pop_tween:
		pop_tween.kill()
	scale = Vector2.ONE * POP_SCALE
	pop_tween = create_tween().set_parallel()
	pop_tween.tween_property(self, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Flash: start white, fade to this number's colour.
	label.modulate = COLOR_FLASH
	pop_tween.tween_property(label, "modulate", _color(), FLASH_TIME)

func _color() -> Color:
	if style == Style.ALLY:
		return COLOR_TAKEN
	if hits >= 2:
		return COLOR_COMBO
	return COLOR_HIT if any_unguarded else COLOR_GUARDED

func _process(delta: float) -> void:
	if fading:
		return
	_follow_target()
	open_left -= delta
	if open_left <= 0.0:
		_fade_out()

# Stay over the target's head while the combo is going (it gets knocked back).
func _follow_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position + HEAD_OFFSET

func _fade_out() -> void:
	fading = true
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y - FLOAT_DISTANCE, FADE_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
