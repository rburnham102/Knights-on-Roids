extends Area2D
## An arrow. The knight's arrows hurt enemies; an enemy's arrows (from_enemy)
## hurt the knight, and a perfectly timed block sends them back.

var damage := 10
var speed := 400.0
var travel_distance := 0.0
var direction := Vector2.RIGHT
var knockback_force := 0.0
var poise_damage := 0.0
var from_enemy := false   # set by the shooter before it is added to the scene
## How far the arrow flies before it's gone. The shooter can change it before
## adding the arrow to the scene (the archer's shots are short-ranged).
var max_range := 1200.0

const FADE_DISTANCE := 40.0   # fades out over its last few pixels instead of popping

func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)   # walls (world layer)
	area_entered.connect(_on_area_entered)   # HurtBoxes
	apply_team(false)

# Collision layers: 1 = world, 8 = player hurtbox, 16 = enemy hurtbox.
func apply_team(deferred: bool) -> void:
	var mask := 1 + (8 if from_enemy else 16)
	if deferred:
		set_deferred("collision_mask", mask)   # we may be inside a physics callback
	else:
		collision_layer = 0
		collision_mask = mask
	modulate = Color(1.0, 0.6, 0.5) if from_enemy else Color.WHITE   # enemy arrows look reddish

func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	position += step
	travel_distance += step.length()
	if travel_distance >= max_range:
		queue_free()
		return
	# Only touch the alpha, so the reddish enemy tint from apply_team() stays.
	modulate.a = clampf((max_range - travel_distance) / FADE_DISTANCE, 0.0, 1.0)

func _on_body_entered(_body: Node2D) -> void:
	# The mask only includes the world layer for bodies, so this is a wall.
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	# `area` is a HurtBox; its owner is the character it belongs to.
	var target: Node = area.owner
	if not target.has_method("take_damage"):
		return
	if not from_enemy:
		target.take_damage(damage, global_position - direction * 8.0, knockback_force, poise_damage)
		queue_free()
		return
	var result: Combat.HitResult = target.take_damage(damage, global_position - direction * 8.0, knockback_force, 0.0, Combat.FLAG_PROJECTILE)
	match result:
		Combat.HitResult.PARRIED:
			reflect()
		Combat.HitResult.DODGED:
			pass   # sails right through a dodging knight
		_:
			queue_free()

# A parried arrow flies back the way it came and now hurts enemies.
func reflect() -> void:
	from_enemy = false
	direction = -direction
	rotation = direction.angle()
	travel_distance = 0.0
	apply_team(true)
