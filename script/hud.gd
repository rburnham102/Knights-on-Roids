extends CanvasLayer
## Screen-fixed heads-up display: health bar, guard bar and the game version.
## It finds the knight through the "player" group and listens to his signals,
## so the knight never needs to know the HUD exists.

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var guard_bar: ProgressBar = %GuardBar
@onready var version_label: Label = %VersionLabel
@onready var room_label: Label = %RoomLabel

func _ready() -> void:
	# Deferred so it works wherever the HUD sits in the tree: the knight adds
	# himself to the "player" group in his own _ready.
	_bind_to_player.call_deferred()

# Called by the run manager when a new room starts.
func set_room(number: int, total: int) -> void:
	room_label.text = "Room %d / %d" % [number, total]

# Called by game.gd, which owns the version string.
func set_version(text: String) -> void:
	version_label.text = text

func _bind_to_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.health_changed.connect(_on_health_changed)
	player.guard_changed.connect(_on_guard_changed)
	# Signals only report *changes*, so read the starting values once.
	_on_health_changed(player.health, player.max_health())
	_on_guard_changed(player.guard, player.MAX_GUARD)

func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [current, maximum]

func _on_guard_changed(current: float, maximum: float) -> void:
	guard_bar.max_value = maximum
	guard_bar.value = current
