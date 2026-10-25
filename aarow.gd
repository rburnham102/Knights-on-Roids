extends Area2D

var damage := 10
var speed := 400.0
var travel_distance := 0.0
var direction := Vector2.RIGHT
var knockback_force := 0.0

const RANGE := 1200.0

func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	position += step
	travel_distance += step.length()   # was never incrementing before
	if travel_distance > RANGE:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position - direction * 8.0, knockback_force)
	queue_free()
