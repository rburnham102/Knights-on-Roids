class_name Level
extends Node2D
## A village street built from random chunk templates laid side by side.
## Chunk templates live in res://rooms/chunks/. Each one is 25 tiles wide
## (400 px) and follows the same layout so any two fit together:
##   rows -4..2   house fronts (roofs may stick up past the camera)
##   rows 3..8    the street you fight on (the top wall sits at row 3)
##   row 9        shoreline tiles (they have wall collision)
##   rows 10..11  water
## Each template needs an "EnemySpawn" node with Marker2D children.

const CHUNK_WIDTH := 400.0
const VIEW_TOP := -64.0      # highest point the camera may show (row -4)
const VIEW_BOTTOM := 192.0   # bottom of the water (end of row 11)

@export var chunk_count := 4   # 4 chunks = 100 tiles

@onready var chunks: Node2D = $Chunks
@onready var player_start: Marker2D = $PlayerStart
@onready var exit_door: ExitDoor = $ExitDoor
@onready var right_wall: CollisionShape2D = $Walls/Right

## Lay out `chunk_count` random templates and move the far wall and door
## to the end of the street.
func build(templates: Array[PackedScene], rng: RandomNumberGenerator) -> void:
	var last_index := -1
	for i in chunk_count:
		var index: int = rng.randi() % templates.size()
		if index == last_index and templates.size() > 1:
			index = (index + 1) % templates.size()   # never the same chunk twice in a row
		last_index = index
		var chunk: Node2D = templates[index].instantiate()
		chunk.position.x = i * CHUNK_WIDTH
		chunks.add_child(chunk)
	var length := chunk_count * CHUNK_WIDTH
	right_wall.position.x = length + 8.0
	exit_door.position.x = length - 8.0

## Spawn points grouped by chunk, so each chunk gets its own enemy budget.
func spawn_groups() -> Array[Array]:
	var groups: Array[Array] = []
	for chunk in chunks.get_children():
		var points: Array[Vector2] = []
		for marker in chunk.get_node("EnemySpawn").get_children():
			points.append(marker.global_position)
		groups.append(points)
	return groups

## The level's area in world pixels (used for the camera limits).
func bounds() -> Rect2:
	return Rect2(0.0, VIEW_TOP, chunk_count * CHUNK_WIDTH, VIEW_BOTTOM - VIEW_TOP)
