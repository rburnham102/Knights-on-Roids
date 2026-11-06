class_name HolyBurst
extends Area2D
## The healer's defensive spell: a burst of holy fire around her that barely
## hurts but throws every enemy in reach away from her.
##
## It's an Area2D on the enemy_hurtbox layer mask, so it finds enemies exactly
## the way the knight's sword does: by their HurtBox, whose owner has
## take_damage(). The healer sets the numbers before adding it to the scene.

var damage := 3
var poise_damage := 999.0
var force := 260.0
var radius := 30.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	($CollisionShape2D.shape as CircleShape2D).radius = radius
	sprite.animation_finished.connect(queue_free)
	sprite.play()
	$Sound.play()
	# A new Area2D only knows what it overlaps after the physics server has
	# stepped once, so wait for that before asking.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := []
	for area in get_overlapping_areas():
		var target: Node = area.owner
		if target in hit or not target.has_method("take_damage"):
			continue
		hit.append(target)
		# Pushed straight away from the centre of the burst.
		target.take_damage(damage, global_position, force, poise_damage)
