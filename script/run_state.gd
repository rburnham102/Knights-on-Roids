class_name RunState
extends RefCounted
## Everything that belongs to ONE run: the knight's stats and perks, how deep he
## is, and the random number generator that decides rooms, enemies and upgrades.
## It lives inside run.tscn, so reloading the scene starts a fresh run.

const RUN_LENGTH := 10   # clear this many rooms to complete a run

var character: CharacterClass   # who is playing this run (see set_character)
var stats: Stats = Stats.new()
var perks := {}          # perk id -> how many times it was taken
var depth := 0           # the room the knight is in (1 = first room)
var rooms_cleared := 0
var upgrades_taken: Array[Upgrade] = []
var items_found: Array[Item] = []
var rng := RandomNumberGenerator.new()
## Loot gets its own generator. Drops depend on how you play (which barrels you
## smash, how many enemies you kill), so if they used `rng` every drop would
## shift the rooms and enemies that come after. Separate, a seed always gives
## the same rooms, however you play them.
var loot_rng := RandomNumberGenerator.new()
var run_seed := 0

func _init(start_seed := 0) -> void:
	if start_seed == 0:
		rng.randomize()
	else:
		rng.seed = start_seed
	run_seed = rng.seed
	loot_rng.seed = run_seed + 1

## Sets who is playing and starts the stats from that character's.
func set_character(new_character: CharacterClass) -> void:
	character = new_character
	if character and character.starting_stats:
		# duplicate(): upgrades change the run's copy, never the class's .tres.
		stats = character.starting_stats.duplicate()

## Picks `count` different upgrades from the pool.
func roll_upgrades(pool: Array[Upgrade], count := 3) -> Array[Upgrade]:
	var bag: Array[Upgrade] = pool.duplicate()
	var picked: Array[Upgrade] = []
	while picked.size() < count and not bag.is_empty():
		picked.append(bag.pop_at(rng.randi() % bag.size()))
	return picked

## Applies an upgrade picked between rooms.
func apply(upgrade: Upgrade, knight: Node) -> void:
	_grant(upgrade, knight)
	upgrades_taken.append(upgrade)

## Applies an item picked up off the ground.
func apply_item(item: Item, knight: Node) -> void:
	_grant(item, knight)
	items_found.append(item)

# What upgrades and items have in common: stats, perks and healing.
func _grant(upgrade: Upgrade, knight: Node) -> void:
	var old_max: int = knight.max_health()
	stats.power += upgrade.power
	stats.dexterity += upgrade.dexterity
	stats.vitality += upgrade.vitality
	if upgrade.perk != &"":
		perks[upgrade.perk] = int(perks.get(upgrade.perk, 0)) + 1
	# More max health also fills the new health, so Vitality is never a trap.
	knight.heal(knight.max_health() - old_max + upgrade.heal)
