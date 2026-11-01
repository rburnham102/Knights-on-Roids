class_name Pickup
extends Area2D
## An item lying on the ground. It hops out of whatever dropped it, bobs in
## place, and emits `collected` when the knight walks over it. It doesn't apply
## the item itself: whoever spawned it (the run manager) listens for the signal
## and decides what picking it up means.

signal collected(item: Item)

const POP_TIME := 0.35        # the hop out of a barrel or a dead enemy
const POP_HEIGHT := 8.0
const POP_SCATTER := 10.0     # how far from the source it can land
const BOB_HEIGHT := 1.5
const BOB_TIME := 0.7         # one bob up (and the same back down)
const LABEL_TIME := 0.8       # the floating name after pickup

@export var item: Item

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label
@onready var sound: AudioStreamPlayer2D = $PickupSound

func _ready() -> void:
	sprite.texture = item.icon
	label.text = item.title
	if item.pickup_sound:
		sound.stream = item.pickup_sound
	body_entered.connect(_on_body_entered)
	_pop()

# Hops to a spot near where it dropped. It can't be picked up mid-hop
# (monitoring starts off in the scene), so you always see what dropped.
func _pop() -> void:
	var landing := position + Vector2(randf_range(-POP_SCATTER, POP_SCATTER), randf_range(-3.0, 5.0))
	create_tween().tween_property(self, "position", landing, POP_TIME)

	var rest_y := sprite.position.y
	var hop := create_tween()
	hop.tween_property(sprite, "position:y", rest_y - POP_HEIGHT, POP_TIME * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(sprite, "position:y", rest_y, POP_TIME * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hop.tween_callback(_land.bind(rest_y))

func _land(rest_y: float) -> void:
	# Turning monitoring on also reports a knight who is already standing here.
	monitoring = true
	var bob := create_tween().set_loops()   # set_loops() with no count = forever
	bob.tween_property(sprite, "position:y", rest_y - BOB_HEIGHT, BOB_TIME).set_trans(Tween.TRANS_SINE)
	bob.tween_property(sprite, "position:y", rest_y, BOB_TIME).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node2D) -> void:
	# The collision mask only sees the player layer; the group check just
	# makes that explicit.
	if not body.is_in_group("player"):
		return
	# We're inside a physics callback, so physics state changes are deferred.
	set_deferred("monitoring", false)
	collected.emit(item)

	sprite.hide()
	label.show()
	sound.play()
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 10.0, LABEL_TIME)
	tween.tween_property(label, "modulate:a", 0.0, LABEL_TIME * 0.5).set_delay(LABEL_TIME * 0.5)
	await tween.finished
	if sound.playing:
		await sound.finished   # don't cut the sound off
	queue_free()
