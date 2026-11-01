class_name Item
extends Upgrade
## Something the knight finds lying on the ground (a potion, a tome...).
## An Item IS an Upgrade - same stat points, heal and perk - so RunState
## applies it with exactly the same code. It only adds what an Upgrade on a
## menu doesn't need: a picture to show on the ground and a sound to play.
##
## Make a new one by creating a new .tres file of this type in res://items/
## and adding it to the table in loot.gd.

## The 16x16 icon shown on the ground. Use an AtlasTexture to cut one icon
## out of a sprite sheet in res://Asset/Pickups/.
@export var icon: Texture2D
## Played when the knight picks it up. Empty = the pickup scene's default.
@export var pickup_sound: AudioStream
