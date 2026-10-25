class_name EnemyDirector
extends RefCounted
## Decides which enemies fill a room. Each room gets a budget that grows with
## depth; every enemy costs some of it and only appears from a minimum depth.

const ENTRIES := [
	{"scene": preload("res://orc.tscn"), "cost": 1.0, "min_depth": 1},
	{"scene": preload("res://skeleton_archer.tscn"), "cost": 1.5, "min_depth": 2},
	{"scene": preload("res://armored_orc.tscn"), "cost": 3.0, "min_depth": 4},
]
# Tuning knobs (static vars so the run simulation can try other values).
static var base_budget := 1.2
static var budget_per_depth := 0.45

static func budget_for(depth: int) -> float:
	return base_budget + budget_per_depth * depth

## The enemies to spawn in a room at `depth` with room for `slots` of them.
static func plan(depth: int, slots: int, rng: RandomNumberGenerator) -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	var budget := budget_for(depth)
	while result.size() < slots:
		var options := ENTRIES.filter(func(e): return e.min_depth <= depth and e.cost <= budget)
		if options.is_empty():
			break
		var pick: Dictionary = options[rng.randi() % options.size()]
		result.append(pick.scene)
		budget -= pick.cost
	if result.is_empty():
		result.append(ENTRIES[0].scene)   # never an empty room
	return result
