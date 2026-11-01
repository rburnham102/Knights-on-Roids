class_name Loot
extends RefCounted
## Decides WHAT drops. Each source (an enemy, a barrel) decides HOW OFTEN with
## its own drop_chance, so a sturdy enemy or a crate can be more generous.
##
## Weights are relative: an item with weight 60 drops 3 times as often as one
## with weight 20. They don't need to add up to anything.

const TABLE := [
	{"item": preload("res://items/small_health_potion.tres"), "weight": 60.0},
	{"item": preload("res://items/large_health_potion.tres"), "weight": 20.0},
	{"item": preload("res://items/tome_of_power.tres"), "weight": 3.0},
	{"item": preload("res://items/tome_of_dexterity.tres"), "weight": 3.0},
	{"item": preload("res://items/tome_of_vitality.tres"), "weight": 3.0},
]

## Rolls one drop. Returns null most of the time (when nothing drops).
static func roll(chance: float, rng: RandomNumberGenerator) -> Item:
	if rng.randf() >= chance:
		return null
	var weights := PackedFloat32Array()
	for entry in TABLE:
		weights.append(entry.weight)
	# rand_weighted() is built into RandomNumberGenerator: it returns an index,
	# picked in proportion to the weights.
	return TABLE[rng.rand_weighted(weights)].item
