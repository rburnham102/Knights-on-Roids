extends Node
## Runs one whole run: builds each level (a village street made of random
## chunks), fills it with enemies, locks the door
## until they're dead, offers an upgrade, and handles death and victory.
## The knight, HUD and screens live in run.tscn and are assigned below.

const LEVEL := preload("res://rooms/level.tscn")
const CHUNKS: Array[PackedScene] = [
	preload("res://rooms/chunks/chunk_template.tscn"),
	preload("res://rooms/chunks/chunk_template2.tscn"),
	preload("res://rooms/chunks/chunk_template3.tscn"),
]
const UPGRADES := [
	preload("res://upgrades/power_up.tres"),
	preload("res://upgrades/dexterity_up.tres"),
	preload("res://upgrades/vitality_up.tres"),
	preload("res://upgrades/field_dressing.tres"),
	preload("res://upgrades/parry_mend.tres"),
	preload("res://upgrades/brutal_riposte.tres"),
	preload("res://upgrades/ghost_step.tres"),
	preload("res://upgrades/light_footed.tres"),
	preload("res://upgrades/iron_guard.tres"),
]
const SPAWN_IN_TIME := 0.5     # enemies fade in and stay idle this long
const FADE_TIME := 0.25

@export var start_seed := 0    # 0 = a random run
@export var heal_after_room := 0.25   # share of max health restored when a room is cleared
@export var knight: CharacterBody2D
@export var actors: Node2D
@export var room_holder: Node2D
@export var hud: CanvasLayer
@export var upgrade_screen: CanvasLayer
@export var end_screen: CanvasLayer
@export var fade_rect: ColorRect

var run: RunState
var room: Level   # the current level (still called "room" so the dev tools keep working)
var pool: Array[Upgrade] = []
var enemies_left := 0
var awaiting_upgrade := false
var finished := false
var changing_room := false

func _ready() -> void:
	run = RunState.new(start_seed)
	for upgrade in UPGRADES:
		pool.append(upgrade)
	# The knight plays with the run's stats and perks, so upgrades apply to him.
	knight.stats = run.stats
	knight.perks = run.perks
	knight.died.connect(_on_knight_died)
	upgrade_screen.chosen.connect(_on_upgrade_chosen)
	end_screen.new_run_requested.connect(_on_new_run_requested)
	fade_rect.color.a = 1.0
	_begin.call_deferred()

func _begin() -> void:
	changing_room = true
	await _enter_room()

# ------------------------------------------------------------------ rooms

func _enter_room() -> void:
	run.depth += 1
	hud.set_room(run.depth, RunState.RUN_LENGTH)
	_clear_level()
	await get_tree().process_frame   # lets the old room finish being freed
	_build_room()
	await _fade_to(0.0)
	changing_room = false

func _clear_level() -> void:
	if room:
		room.queue_free()
		room = null
	for child in actors.get_children():
		if child != knight:
			child.queue_free()   # enemies, arrows, effects left over
	Engine.time_scale = 1.0

func _build_room() -> void:
	room = LEVEL.instantiate()
	room_holder.add_child(room)
	room.build(CHUNKS, run.rng)

	knight.global_position = room.player_start.global_position
	knight.reset_for_new_room()
	var area := room.bounds()
	knight.camera.limit_left = floori(area.position.x)
	knight.camera.limit_top = floori(area.position.y)
	knight.camera.limit_right = ceili(area.end.x)
	knight.camera.limit_bottom = ceili(area.end.y)

	room.exit_door.close()
	room.exit_door.entered.connect(_on_exit_entered)
	_spawn_enemies()

# Every chunk gets its own enemy budget, so enemies are spread along the street.
func _spawn_enemies() -> void:
	enemies_left = 0
	for points: Array[Vector2] in room.spawn_groups():
		if points.is_empty():
			continue
		var scenes := EnemyDirector.plan(run.depth, points.size(), run.rng)
		# Shuffle the spawn points with the run's generator so a seed replays the same.
		for i in range(points.size() - 1, 0, -1):
			var j: int = run.rng.randi() % (i + 1)
			var swap := points[i]
			points[i] = points[j]
			points[j] = swap
		enemies_left += scenes.size()
		for i in scenes.size():
			var enemy: Node2D = scenes[i].instantiate()
			enemy.position = points[i]
			actors.add_child(enemy)
			enemy.died.connect(_on_enemy_died)
			_spawn_in(enemy)

# Enemies fade in and do nothing for a moment, so a room never opens with a hit.
func _spawn_in(enemy: Node2D) -> void:
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(enemy, "modulate:a", 1.0, SPAWN_IN_TIME)
	tween.tween_callback(func():
		if is_instance_valid(enemy):
			enemy.process_mode = Node.PROCESS_MODE_INHERIT)

func _on_enemy_died() -> void:
	if finished:
		return
	enemies_left -= 1
	if enemies_left <= 0:
		_room_cleared()

func _room_cleared() -> void:
	run.rooms_cleared += 1
	knight.heal(roundi(knight.max_health() * heal_after_room))
	if run.depth >= RunState.RUN_LENGTH:
		_finish(true)
		return
	await get_tree().create_timer(0.6).timeout   # a beat to enjoy the kill
	if finished or knight.is_dead:
		return
	awaiting_upgrade = true
	upgrade_screen.show_choices(run.roll_upgrades(pool, 3))

func _on_upgrade_chosen(upgrade: Upgrade) -> void:
	awaiting_upgrade = false
	run.apply(upgrade, knight)
	room.exit_door.open()

func _on_exit_entered() -> void:
	if changing_room or finished:
		return
	changing_room = true
	await _fade_to(1.0)
	await _enter_room()

# ------------------------------------------------------------- end of a run

func _on_knight_died() -> void:
	_finish(false)

func _finish(won: bool) -> void:
	finished = true
	end_screen.show_result(won, run)

func _on_new_run_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()   # run.tscn holds all run state, so this is a fresh run

func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", alpha, FADE_TIME)
	await tween.finished
