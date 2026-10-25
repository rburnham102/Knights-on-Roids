class_name RunState
extends RefCounted
## Everything that belongs to ONE run: the knight's stats and perks, how deep he
## is, and the random number generator that decides rooms, enemies and upgrades.
## It lives inside run.tscn, so reloading the scene starts a fresh run.

const RUN_LENGTH := 10   # clear this many rooms to complete a run

var stats: Stats = Stats.new()
var perks := {}          # perk id -> how many times it was taken
var depth := 0           # the room the knight is in (1 = first room)
var rooms_cleared := 0
var upgrades_taken: Array[Upgrade] = []
var rng := RandomNumberGenerator.new()
var run_seed := 0

func _init(start_seed := 0) -> void:
	if start_seed == 0:
		rng.randomize()
	else:
		rng.seed = start_seed
	run_seed = rng.seed

## Picks `count` different upgrades from the pool.
func roll_upgrades(pool: Array[Upgrade], count := 3) -> Array[Upgrade]:
	var bag: Array[Upgrade] = pool.duplicate()
	var picked: Array[Upgrade] = []
	while picked.size() < count and not bag.is_empty():
		picked.append(bag.pop_at(rng.randi() % bag.size()))
	return picked

## Applies an upgrade to this run (and heals the knight for anything it grants).
func apply(upgrade: Upgrade, knight: Node) -> void:
	var old_max: int = knight.max_health()
	stats.power += upgrade.power
	stats.dexterity += upgrade.dexterity
	stats.vitality += upgrade.vitality
	if upgrade.perk != &"":
		perks[upgrade.perk] = int(perks.get(upgrade.perk, 0)) + 1
	upgrades_taken.append(upgrade)
	# More max health also fills the new health, so Vitality is never a trap.
	knight.heal(knight.max_health() - old_max + upgrade.heal)
