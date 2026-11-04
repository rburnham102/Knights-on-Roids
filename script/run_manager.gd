extends Node
## Runs one whole run: builds each level (a village street made of random
## chunks), fills it with enemies, locks the door
## until they're dead, offers an upgrade, and handles death and victory.
## It also spawns the loot that enemies and barrels drop, and applies it.
## The HUD and screens live in run.tscn and are assigned below. The player is
## spawned at the start of the run from the CharacterClass picked on the
## character select screen.

const LEVEL := preload("res://rooms/level.tscn")
const PICKUP := preload("res://pickup.tscn")
const HEALER := preload("res://healer.tscn")
const HEALER_UPGRADE := preload("res://upgrades/healer.tres")
const CHUNKS: Array[PackedScene] = [
	preload("res://rooms/chunks/chunk_template.tscn"),
	preload("res://rooms/chunks/chunk_template2.tscn"),
	preload("res://rooms/chunks/chunk_template3.tscn"),
	preload("res://rooms/chunks/chunk_template4.tscn"),
	preload("res://rooms/chunks/chunk_template5.tscn"),
	preload("res://rooms/chunks/chunk_template6.tscn"),
]
## The upgrades every character can be offered. Class-only upgrades (and ones
## a class can't take) are set on each CharacterClass in res://characters/.
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
	HEALER_UPGRADE,
]
const SPAWN_IN_TIME := 0.5     # enemies fade in and stay idle this long
const FADE_TIME := 0.25
## Share of enemies that go after the healer instead of the knight.
const PEEL_CHANCE := 0.2

@export var start_seed := 0    # 0 = a random run
@export var heal_after_room := 0.25   # share of max health restored when a room is cleared
## The playable characters, in the order the select screen shows them.
## The first one is used when the select screen is turned off.
@export var classes: Array[CharacterClass] = []
@export var character_select: CanvasLayer
## Show the character select screen before the run. Tests turn it off.
@export var character_select_enabled := true
@export var actors: Node2D
@export var room_holder: Node2D
@export var hud: CanvasLayer
@export var upgrade_screen: CanvasLayer
@export var end_screen: CanvasLayer
@export var fade_rect: ColorRect
@export var dev_screen: CanvasLayer
## Show the dev loadout screen before the run. It only ever appears in debug
## builds (running from the editor), never in an exported release game.
@export var dev_screen_enabled := true

var knight: CharacterBody2D   # the player character, spawned in _spawn_player()
var run: RunState
var room: Level   # the current level (still called "room" so the dev tools keep working)
var pool: Array[Upgrade] = []
var enemies_left := 0
var awaiting_upgrade := false
var finished := false
var changing_room := false
var healer: Healer   # null until hired (and again after she dies)

func _ready() -> void:
	_new_run_state(start_seed)
	upgrade_screen.chosen.connect(_on_upgrade_chosen)
	end_screen.new_run_requested.connect(_on_new_run_requested)
	fade_rect.color.a = 1.0
	if character_select and character_select_enabled and classes.size() > 1:
		character_select.chosen.connect(_on_character_chosen)
		character_select.open(classes)
	else:
		_on_character_chosen(classes[0])

# Spawns the chosen character, then shows the dev screen (debug builds) or starts.
func _on_character_chosen(character: CharacterClass) -> void:
	_spawn_player(character)
	if dev_screen and dev_screen_enabled and OS.is_debug_build():
		dev_screen.started.connect(_on_dev_start)
		dev_screen.open(pool, RunState.RUN_LENGTH, [HEALER_UPGRADE])
	else:
		_begin.call_deferred()   # build the first room once everything is ready

func _spawn_player(character: CharacterClass) -> void:
	run.set_character(character)
	pool = character.upgrade_pool(UPGRADES)
	knight = character.scene.instantiate()
	# Before add_child(): the player's _ready() works out its health from these.
	# The player uses the run's stats and perks, so upgrades apply to them.
	knight.stats = run.stats
	knight.perks = run.perks
	actors.add_child(knight)
	knight.died.connect(_on_knight_died)
	hud.bind_to(knight)

func _new_run_state(run_seed: int) -> void:
	var character := run.character if run else null
	run = RunState.new(run_seed)
	run.set_character(character)
	# The player uses the run's stats and perks, so upgrades apply to them.
	if knight:
		knight.stats = run.stats
		knight.perks = run.perks

# The dev screen's Start button: set up the run the way it asked, then begin.
func _on_dev_start(picks: Dictionary, start_room: int, run_seed: int) -> void:
	if run_seed != 0:
		_new_run_state(run_seed)   # a typed seed beats the Inspector's start_seed
	run.depth = start_room - 1     # _enter_room() adds one as it builds the room
	for upgrade: Upgrade in picks:
		for i in picks[upgrade]:
			# The same call as picking it between rooms, so stats, perks,
			# healing and the end screen's upgrade list all just work.
			run.apply(upgrade, knight)
		_remove_if_maxed(upgrade)
		if upgrade == HEALER_UPGRADE:
			_hire_healer()
	_begin()

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
		if child != knight and child != healer:
			child.queue_free()   # enemies, arrows, effects left over
	Engine.time_scale = 1.0

func _build_room() -> void:
	room = LEVEL.instantiate()
	room_holder.add_child(room)
	room.build(CHUNKS, run.rng)

	knight.global_position = room.player_start.global_position
	knight.reset_for_new_room()
	if healer:
		healer.place_beside_knight()
	var area := room.bounds()
	knight.camera.limit_left = floori(area.position.x)
	knight.camera.limit_top = floori(area.position.y)
	knight.camera.limit_right = ceili(area.end.x)
	knight.camera.limit_bottom = ceili(area.end.y)

	room.exit_door.close()
	room.exit_door.entered.connect(_on_exit_entered)
	# The chunk templates place the barrels; the group finds them all.
	for breakable: Breakable in get_tree().get_nodes_in_group("breakables"):
		breakable.broken.connect(_on_breakable_broken)
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
			enemy.died.connect(_on_enemy_died.bind(enemy))   # bind() adds the enemy as an argument
			# A few enemies go after the healer. loot_rng, not rng: this
			# depends on your upgrades, so it mustn't change the next rooms.
			if healer and run.loot_rng.randf() < PEEL_CHANCE:
				enemy.player = healer
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

func _on_enemy_died(enemy: Node2D) -> void:
	if finished:
		return
	_drop_loot(enemy.drop_chance, enemy.global_position)
	enemies_left -= 1
	if enemies_left <= 0:
		_room_cleared()

func _room_cleared() -> void:
	run.rooms_cleared += 1
	knight.heal(roundi(knight.max_health() * heal_after_room))
	if healer:
		healer.heal(roundi(healer.max_health * heal_after_room))
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
	_remove_if_maxed(upgrade)
	if upgrade == HEALER_UPGRADE:
		_hire_healer()
	room.exit_door.open()

func _on_exit_entered() -> void:
	if changing_room or finished:
		return
	changing_room = true
	await _fade_to(1.0)
	await _enter_room()

# An upgrade with a max_stacks limit stops being offered once it's reached.
func _remove_if_maxed(upgrade: Upgrade) -> void:
	if upgrade.max_stacks > 0 and run.upgrades_taken.count(upgrade) >= upgrade.max_stacks:
		pool.erase(upgrade)

# ----------------------------------------------------------------- healer

func _hire_healer() -> void:
	pool.erase(HEALER_UPGRADE)   # only one at a time
	healer = HEALER.instantiate()
	healer.knight = knight
	healer.died.connect(_on_healer_died)
	actors.add_child(healer)
	healer.place_beside_knight()
	healer.modulate.a = 0.0
	create_tween().tween_property(healer, "modulate:a", 1.0, SPAWN_IN_TIME)

func _on_healer_died() -> void:
	# Enemies that were after her turn back to the knight.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.player == healer:
			enemy.player = knight
	healer = null                # she plays her death animation, then frees herself
	run.perks.erase(&"healer")
	pool.append(HEALER_UPGRADE)  # she can be hired again later

# ------------------------------------------------------------------- loot

func _on_breakable_broken(breakable: Breakable) -> void:
	_drop_loot(breakable.drop_chance, breakable.global_position)

func _drop_loot(chance: float, at: Vector2) -> void:
	var item := Loot.roll(chance, run.loot_rng)
	if item == null:
		return
	var pickup: Pickup = PICKUP.instantiate()
	pickup.item = item
	pickup.position = actors.to_local(at)
	pickup.collected.connect(_on_item_collected)
	# Deferred: drops happen inside a physics callback (the hit that killed
	# something), and Godot doesn't allow adding Area2Ds in the middle of one.
	actors.add_child.call_deferred(pickup)

func _on_item_collected(item: Item) -> void:
	run.apply_item(item, knight)

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
