extends AnimatedSprite2D
## A visual effect that plays its animation once and then removes itself.
## Spawn it, add it to the scene, and forget about it.

func _ready() -> void:
	animation_finished.connect(queue_free)
	play()
