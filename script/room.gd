class_name Room
extends Node2D
## One hand-made room. To make a new one, duplicate a room scene and repaint the
## tilemap; just keep these nodes:
##   Ground        - a TileMapLayer (its tiles define the room's size)
##   PlayerStart   - a Marker2D: where the knight appears
##   EnemySpawns   - Marker2D children, one per possible enemy
##   ExitDoor      - the door scene, in a gap in the far wall

@onready var ground: TileMapLayer = $Ground
@onready var player_start: Marker2D = $PlayerStart
@onready var enemy_spawns: Node2D = $EnemySpawns
@onready var exit_door: ExitDoor = $ExitDoor

func spawn_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for marker in enemy_spawns.get_children():
		out.append(marker.global_position)
	return out

## The room's area in world pixels (used for the camera limits).
func bounds() -> Rect2:
	var cells := ground.get_used_rect()
	var tile := Vector2(ground.tile_set.tile_size)
	var top_left := ground.to_global(ground.map_to_local(cells.position)) - tile / 2.0
	return Rect2(top_left, Vector2(cells.size) * tile)
