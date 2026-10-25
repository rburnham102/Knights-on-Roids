class_name ExitDoor
extends Node2D
## The door at the end of a room. Closed: a solid block. Open: walking into it
## emits `entered`. The visuals are plain rectangles so they're easy to replace.

signal entered

var is_open := false

@onready var blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D
@onready var visual: ColorRect = $Visual
@onready var trigger: Area2D = $Trigger

func _ready() -> void:
	close()

func open() -> void:
	is_open = true
	blocker_shape.set_deferred("disabled", true)
	visual.color = Color(0.95, 0.85, 0.4, 0.55)

func close() -> void:
	is_open = false
	blocker_shape.set_deferred("disabled", false)
	visual.color = Color(0.12, 0.08, 0.08, 1.0)

func _physics_process(_delta: float) -> void:
	if not is_open:
		return
	# Polling (instead of the body_entered signal) also catches a knight who
	# was already standing in the doorway when it opened.
	for body in trigger.get_overlapping_bodies():
		if body.is_in_group("player"):
			is_open = false
			entered.emit()
			return
