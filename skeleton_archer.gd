extends "res://enemy.gd"
# Ranged enemy. Everything that makes an enemy an enemy (states, poise, the
# wind-up tint, being parried, firing arrows) is inherited from enemy.gd. The only
# thing the archer changes is how it MOVES while free: it keeps its distance
# and shoots, instead of walking up to melee range.

@export var min_range: float = 90.0        # closer than this and it backs away
@export var max_range: float = 170.0       # farther than this and it walks closer
@export var retreat_speed: float = 80.0

var strafe_sign := 1.0   # which way to circle when a pillar blocks the shot

# Is there open air between the archer and the knight? Only the world layer
# (walls, pillars, the door) blocks the ray, so other enemies don't.
func has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0, -8), player.global_position + Vector2(0, -7), 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func process_free(delta: float) -> void:
	if not is_instance_valid(player):
		stand_still()
		return
	if player.get("is_dead") == true:
		stand_still()
		anim.play("idle")
		return

	var to_player := player.global_position - global_position
	var distance := to_player.length()
	anim.flip_h = to_player.x < 0   # (assumes the art faces right)

	if distance <= max_range and not has_line_of_sight():
		# A pillar is in the way: find a clear shot instead of shooting the stone.
		# Far away that means walking around it; already close, it means strafing.
		var heading := to_player.normalized()
		if distance < min_range:
			heading = heading.orthogonal() * strafe_sign
		move_toward_target(heading, speed, delta)
		anim.play("walk")
	elif distance < min_range:
		move_toward_target(-to_player.normalized(), retreat_speed, delta)
		anim.play("walk")
		# Cornered against a wall, or the knight is right on top of it: shoot anyway.
		if cooldown_left <= 0.0 and (get_slide_collision_count() > 0 or distance < 40.0):
			start_attack()
	elif distance <= max_range:
		if cooldown_left <= 0.0:
			start_attack()
		else:
			stand_still()
			anim.play("idle")
	elif distance <= detect_range:
		move_toward_target(to_player.normalized(), speed, delta)
		anim.play("walk")
	else:
		stand_still()
		anim.play("idle")
