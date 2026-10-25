class_name Stats
extends Resource
## The three core character stats.
##
## Every stat is a plain number with a baseline of 10. Each helper below turns
## a stat into a MULTIPLIER on one of the character's base values, so a
## character whose stats are all 10 behaves exactly like the base constants
## in their script (every multiplier is 1.0).
##
## All balance numbers for stats live in this one file.

const BASELINE := 10

# Multiplier change per stat point above/below the baseline.
const DAMAGE_PER_POWER := 0.05
const KNOCKBACK_PER_POWER := 0.05
const SPEED_PER_DEXTERITY := 0.03
const LUNGE_PER_DEXTERITY := 0.05
const COMBO_WINDOW_PER_DEXTERITY := 0.04
const HEALTH_PER_VITALITY := 0.05
const POISE_DAMAGE_PER_POWER := 0.05
const PARRY_WINDOW_PER_DEXTERITY := 0.05
const DODGE_DISTANCE_PER_DEXTERITY := 0.05

## How hard you hit the world: damage, knockback and poise damage.
@export_range(1, 99) var power := 10
## How well you react to the world: movement speed, lunge and dodge distance,
## combo timing and the size of the parry window.
@export_range(1, 99) var dexterity := 10
## How much punishment you can take: max health.
@export_range(1, 99) var vitality := 10

func damage_mult() -> float:
	return _mult(power, DAMAGE_PER_POWER)

func knockback_mult() -> float:
	return _mult(power, KNOCKBACK_PER_POWER)

func speed_mult() -> float:
	return _mult(dexterity, SPEED_PER_DEXTERITY)

func lunge_mult() -> float:
	return _mult(dexterity, LUNGE_PER_DEXTERITY)

func combo_window_mult() -> float:
	return _mult(dexterity, COMBO_WINDOW_PER_DEXTERITY)

func poise_damage_mult() -> float:
	return _mult(power, POISE_DAMAGE_PER_POWER)

func parry_window_mult() -> float:
	return _mult(dexterity, PARRY_WINDOW_PER_DEXTERITY)

func dodge_distance_mult() -> float:
	return _mult(dexterity, DODGE_DISTANCE_PER_DEXTERITY)

func health_mult() -> float:
	return _mult(vitality, HEALTH_PER_VITALITY)

func _mult(stat: int, per_point: float) -> float:
	# Never drop below 10% so a very low stat can't flip a value negative.
	return maxf(1.0 + (stat - BASELINE) * per_point, 0.1)
