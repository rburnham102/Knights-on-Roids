class_name CharacterClass
extends Resource
## One playable character, as data: what the select screen shows, which scene
## to spawn, and which upgrades this character can be offered.
## Make a new character by making a new .tres of this type in res://characters/
## and adding it to the RunManager's `classes` list in run.tscn.

@export var display_name := ""
@export_multiline var description := ""
## Shown on the select screen. An AtlasTexture of one idle frame works well.
@export var portrait: Texture2D
## The player scene to spawn (an inherited scene of Knight.tscn).
@export var scene: PackedScene
## Power, Dexterity and Vitality at the start of a run (10 = the base numbers).
## Each run gets its own copy, so upgrades never change this file.
@export var starting_stats: Stats
## Upgrades only this character can be offered, on top of the shared ones.
@export var extra_upgrades: Array[Upgrade] = []
## Shared upgrades this character never sees.
@export var excluded_upgrades: Array[Upgrade] = []

## The upgrades this character can be offered: shared, minus excluded, plus extras.
func upgrade_pool(shared: Array) -> Array[Upgrade]:
	var pool: Array[Upgrade] = []
	for upgrade: Upgrade in shared:
		if not upgrade in excluded_upgrades:
			pool.append(upgrade)
	pool.append_array(extra_upgrades)
	return pool
