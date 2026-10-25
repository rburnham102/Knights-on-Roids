class_name Upgrade
extends Resource
## One upgrade the knight can pick between rooms. Make a new one by creating a
## new .tres file of this type in res://upgrades/ and adding it to the pool in
## run_manager.gd.

@export var title := ""
@export_multiline var description := ""
## Stat points added to the run.
@export var power := 0
@export var dexterity := 0
@export var vitality := 0
## Health restored right away.
@export var heal := 0
## A perk id the knight's code looks for (taking it twice stacks). Empty = none.
@export var perk: StringName = &""
