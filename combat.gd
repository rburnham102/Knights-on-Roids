class_name Combat
extends RefCounted
## Small shared helpers for combat. Everything here is static, so there is
## nothing to instance and no autoload to register: call Combat.hit_stop(0.07).

## What happened to an attack that reached a defender. Returned by the
## knight's take_damage() so the attacker can react.
enum HitResult {
	HIT,      # the damage landed (or the target was already dead)
	BLOCKED,  # absorbed by the guard
	PARRIED,  # perfectly timed block: attacker is open
	DODGED,   # the target was invulnerable (mid-dodge)
}

# Extra properties of an incoming attack, passed to take_damage() as a bit mask.
const FLAG_PROJECTILE := 1     # an arrow: a parry deflects it, and there's nobody to riposte
const FLAG_UNPARRYABLE := 2    # a parry-timed block is just a block
const FLAG_GUARD_BREAK := 4    # shatters a raised guard

static var _freeze_id := 0

static func flags_of(attack: AttackData) -> int:
	var f := 0
	if not attack.parryable:
		f |= FLAG_UNPARRYABLE
	if attack.guard_break:
		f |= FLAG_GUARD_BREAK
	return f

## Freezes the game for a moment ("hit-stop"). Heavy hits feel heavier when
## everything pauses for a few frames.
static func hit_stop(duration: float, time_scale := 0.05) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	_freeze_id += 1
	var my_id := _freeze_id
	Engine.time_scale = time_scale
	# create_timer(time, process_always, process_in_physics, ignore_time_scale):
	# the last 'true' makes the timer run in real time, so it isn't slowed by
	# the very time_scale we just lowered.
	await tree.create_timer(duration, true, false, true).timeout
	# If another freeze started meanwhile, let that one do the restoring.
	if my_id == _freeze_id:
		Engine.time_scale = 1.0
