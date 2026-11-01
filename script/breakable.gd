class_name Breakable
extends StaticBody2D
## A prop the knight can smash: barrels, crates, pots...
## It has a HurtBox on the enemy_hurtbox layer and a take_damage() method,
## which is all the knight's sword and arrows look for, so it takes hits
## exactly like an enemy without the knight's code knowing about it.
##
## It's in the "breakables" group (see the Node dock > Groups), which is how
## the run manager finds every breakable in a freshly built level.
## To make a crate: Scene > New Inherited Scene from breakable.tscn, then swap
## the Sprite2D texture and the Broken Texture below.

signal broken(breakable: Breakable)

## Hits it takes before it breaks.
@export var hits_to_break := 1
## Chance (0 to 1) that breaking it drops an item.
@export_range(0.0, 1.0) var drop_chance := 0.1
## What's left on the ground afterwards.
@export var broken_texture: Texture2D

var hits_left := 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hurtbox_shape: CollisionShape2D = $HurtBox/CollisionShape2D
@onready var hit_sound: AudioStreamPlayer2D = $HitSound

func _ready() -> void:
	hits_left = hits_to_break

# Same signature as the enemies' take_damage(), so callers can't tell the
# difference. A barrel only cares that it was hit, not how hard.
func take_damage(_amount: int, _from_position := Vector2.ZERO, _force := 0.0, _poise_damage := 0.0, _flags := 0) -> Combat.HitResult:
	if hits_left <= 0:
		return Combat.HitResult.HIT
	hits_left -= 1
	hit_sound.play()
	_flash()
	if hits_left <= 0:
		_break()
	return Combat.HitResult.HIT

func _break() -> void:
	sprite.texture = broken_texture
	# Deferred: we're inside the physics callback of whatever hit us.
	body_shape.set_deferred("disabled", true)
	hurtbox_shape.set_deferred("disabled", true)
	broken.emit(self)

# A quick white flash and squash, so every hit feels like it landed.
func _flash() -> void:
	sprite.self_modulate = Color(2.0, 2.0, 2.0)
	sprite.scale = Vector2(0.6, 0.4)
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.12)
	tween.tween_property(sprite, "scale", Vector2(0.5, 0.5), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
