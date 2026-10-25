extends CharacterBody2D

const SPEED = 100.0
const MAX_HEALTH := 100
const ARROW_SCENE := preload("res://aarow.tscn")
const KNOCKBACK_DECAY := 700.0
const MAX_GUARD := 60.0
const GUARD_REGEN := 12.0              # guard recovered per second
const GUARD_REGEN_DELAY := 1.5         # seconds after a blocked hit before regen starts
const GUARD_BREAK_DELAY := 2.5         # longer delay when the guard breaks
const GUARD_RECOVER_AT := 20.0         # after a break, block is unusable until guard reaches this
const BLOCK_KNOCKBACK_PER_DAMAGE := 8.0
const LUNGE_DECAY := 500.0   # how fast the lunge slows down (pixels/sec per second)


@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var camera: Camera2D = $Camera2D

const BLOCK_EFFECT := preload("res://block_effect.tscn")

const ATTACKS := {
	"attack_light":  {"anim": "attack_light",  "damage": 10, "type": "melee",  "hit_frame": 2, "knockback": 120.0, "shake": 0.0, "lunge": 0.0},
	"attack_light2": {"anim": "attack_light2", "damage": 12, "type": "melee",  "hit_frame": 2, "knockback": 150.0, "shake": 1.0, "lunge": 140.0},
	"attack_heavy":  {"anim": "attack_heavy",  "damage": 25, "type": "melee",  "hit_frame": 4, "knockback": 250.0, "shake": 3.0, "lunge": 140.0},
	"attack_bow":    {"anim": "attack_bow",    "damage": 15, "type": "ranged", "hit_frame": 5, "knockback": 100.0, "shake": 0.0, "lunge": 0.0},
}

const LIGHT_COMBO := ["attack_light", "attack_light2", "attack_heavy"]
const COMBO_WINDOW := 0.35   # seconds after a swing ends to still continue the chain

const DIRECTIONS := {
	"up": Vector2.UP,
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}
const HITBOX_DISTANCE := 20.0

var health: int = MAX_HEALTH
var is_dead := false
var is_hurt := false
var is_attacking := false
var current_attack: Dictionary = {}
var last_direction := "right"
var hit_bodies: Array = []
var aim_direction := Vector2.RIGHT
var knockback := Vector2.ZERO
var shake_strength := 0.0
var shake_decay := 0.0
var combo_index := 0
var combo_window := 0.0
var combo_queued := false
var attack_from_combo := false
var guard := MAX_GUARD
var guard_regen_delay_left := 0.0
var guard_broken := false
var is_blocking := false
var guard_bar: ProgressBar
var guard_fill: StyleBoxFlat

var lunge_velocity := Vector2.ZERO

func _ready() -> void:
	add_to_group("player")   # <-- lets the orc find the knight
	setup_guard_bar()

func _physics_process(delta: float) -> void:
	# Screen shake
	if shake_strength > 0.0:
		shake_strength = max(shake_strength - shake_decay * delta, 0.0)
		camera.offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
	else:
		camera.offset = Vector2.ZERO
	
	update_guard(delta)
	update_guard_bar()
	if is_dead or is_hurt:
		knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		velocity = knockback
		move_and_slide()
		return

		# Hold to block. Can't start while attacking or guard-broken.
	var want_block := Input.is_action_pressed("block") and not is_attacking and not guard_broken
	if want_block and not is_blocking:
		start_block()
	elif not want_block and is_blocking:
		stop_block()

	if is_blocking:
		knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		velocity = knockback
		move_and_slide()
		return   # no attacking or walking while blocking
	
	# Combo window counts down only while not attacking
	if not is_attacking:
		combo_window = max(combo_window - delta, 0.0)
		if combo_window == 0.0:
			combo_index = 0

	# Light button drives the combo
	if Input.is_action_just_pressed("attack_light"):
		if not is_attacking:
			start_combo_attack()
		elif anim.frame >= current_attack["hit_frame"]:
			combo_queued = true   # buffered: only accepted after the hit frame

	# Other attacks (heavy on its own, bow)
	if not is_attacking:
		for action in ATTACKS:
			if action in ["attack_light", "attack_light2"]:
				continue
			if Input.is_action_just_pressed(action):
				start_attack(ATTACKS[action])
				break

	if is_attacking:
		lunge_velocity = lunge_velocity.move_toward(Vector2.ZERO, LUNGE_DECAY * delta)
		velocity = lunge_velocity
		move_and_slide()
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity = direction * SPEED + knockback
	move_and_slide()
	update_animation(direction)

func start_combo_attack() -> void:
	if combo_window <= 0.0:
		combo_index = 0   # window expired, restart the chain
	var key: String = LIGHT_COMBO[combo_index]
	combo_index = (combo_index + 1) % LIGHT_COMBO.size()   # wraps to 0 after the finisher
	combo_window = 0.0
	start_attack(ATTACKS[key], true)

func start_attack(attack: Dictionary, from_combo := false) -> void:
	is_attacking = true
	attack_from_combo = from_combo
	current_attack = attack
	hit_bodies.clear()

	if attack["type"] == "ranged":
		aim_direction = (get_global_mouse_position() - global_position).normalized()
		anim.flip_h = aim_direction.x < 0

	anim.play(attack["anim"])
	var lunge: float = attack.get("lunge", 0.0)
	if lunge > 0.0:
		lunge_velocity = DIRECTIONS[last_direction] * lunge
	else:
		lunge_velocity = Vector2.ZERO



func finish_attack() -> void:
	var continue_combo := attack_from_combo and combo_index != 0
	is_attacking = false
	current_attack = {}
	attack_from_combo = false
	disable_hitbox()
	lunge_velocity = Vector2.ZERO
	if continue_combo:
		combo_window = COMBO_WINDOW
		if combo_queued:
			combo_queued = false
			start_combo_attack()   # chains straight into the next swing
			return
	else:
		combo_index = 0
	combo_queued = false

func fire_arrow() -> void:
	var arrow = ARROW_SCENE.instantiate()
	arrow.direction = aim_direction
	arrow.damage = current_attack["damage"]
	arrow.knockback_force = current_attack["knockback"]
	# Add to the level, NOT to the knight, so it doesn't move with him
	get_parent().add_child(arrow)
	arrow.global_position = %ShootingPoint.global_position

func update_guard(delta: float) -> void:
	if guard_regen_delay_left > 0.0:
		guard_regen_delay_left -= delta
		return
	if is_blocking or guard >= MAX_GUARD:
		return   # no regen while holding block
	guard = minf(guard + GUARD_REGEN * delta, MAX_GUARD)
	if guard_broken and guard >= GUARD_RECOVER_AT:
		guard_broken = false

func start_block() -> void:
	is_blocking = true
	# Blocking breaks any combo in progress
	combo_index = 0
	combo_window = 0.0
	combo_queued = false
	anim.play("block")

func block_flash(from_position: Vector2, heavy: bool) -> void:
	# Keep the sprite tint if you like it
	anim.modulate = Color(1.792, 2.139, 2.85, 1.0)
	create_tween().tween_property(anim, "modulate", Color.WHITE, 0.2)

	var dir := (from_position - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	var fx := BLOCK_EFFECT.instantiate()
	get_parent().add_child(fx)   # in the level, so it doesn't move with the knight
	fx.global_position = global_position + dir * 10.0 + Vector2(0, -7)
	#fx.rotation = dir.angle()                 # orient toward the attacker
	#fx.scale = Vector2(1.5, 1.5) if heavy else Vector2.ONE


func stop_block() -> void:
	is_blocking = false

func setup_guard_bar() -> void:
	guard_bar = ProgressBar.new()
	guard_bar.max_value = MAX_GUARD
	guard_bar.value = MAX_GUARD
	guard_bar.show_percentage = false
	guard_bar.custom_minimum_size = Vector2(20, 3)
	guard_bar.size = Vector2(20, 3)
	guard_bar.position = Vector2(-11, -28)   # centered above the head
	guard_bar.z_index = 10
	guard_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guard_bar.visible = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	guard_fill = StyleBoxFlat.new()
	guard_fill.bg_color = Color(0.3, 0.7, 1.0)
	guard_bar.add_theme_stylebox_override("background", bg)
	guard_bar.add_theme_stylebox_override("fill", guard_fill)
	add_child(guard_bar)

func update_guard_bar() -> void:
	guard_bar.value = guard
	guard_bar.visible = guard < MAX_GUARD and not is_dead
	# Red while broken, blue otherwise
	guard_fill.bg_color = Color(0.9, 0.25, 0.2) if guard_broken else Color(0.3, 0.7, 1.0)

func enable_hitbox() -> void:
	hitbox.position = DIRECTIONS[last_direction] * HITBOX_DISTANCE
	hitbox_shape.set_deferred("disabled", false)

func disable_hitbox() -> void:
	hitbox_shape.set_deferred("disabled", true)

func _on_hitbox_body_entered(body: Node2D) -> void:
	if current_attack.is_empty():
		return
	if body == self or body in hit_bodies:
		return
	hit_bodies.append(body)
	if body.has_method("take_damage"):
		body.take_damage(current_attack["damage"], global_position, current_attack["knockback"])
		if current_attack["shake"] > 0.0:
			shake(current_attack["shake"])
			


func take_damage(amount: int, from_position: Vector2 = Vector2.ZERO, force: float = 0.0) -> bool:
	if is_dead:
		return false

	if is_blocking:
		var absorbed := mini(amount, int(guard))
		var leftover := amount - absorbed
		guard -= absorbed
		guard_regen_delay_left = GUARD_REGEN_DELAY

		if from_position != Vector2.ZERO:
			knockback = (global_position - from_position).normalized() * float(amount) * BLOCK_KNOCKBACK_PER_DAMAGE
		shake(1.5)
		block_flash(from_position, amount >= 15)
		
		print("Blocked ", absorbed, " | guard: ", guard)

		if leftover <= 0:
			return true   # fully blocked, the attacker will recoil

		# Guard break: the rest of the damage goes through
		guard = 0.0
		guard_broken = true
		guard_regen_delay_left = GUARD_BREAK_DELAY
		is_blocking = false
		amount = leftover
		force = 0.0

	health -= amount
	print("Knight health: ", health)
	shake(2.0 if amount < 15 else 4.0)

	if force > 0.0:
		knockback = (global_position - from_position).normalized() * force

	if is_attacking:
		is_attacking = false
		current_attack = {}
		disable_hitbox()
	combo_index = 0
	combo_window = 0.0
	combo_queued = false
	attack_from_combo = false
	lunge_velocity = Vector2.ZERO

	if health <= 0:
		die()
	else:
		is_hurt = true
		anim.stop()
		anim.play("hurt")
	return false


func die() -> void:
	is_dead = true
	is_hurt = false
	velocity = Vector2.ZERO
	anim.play("death")
	is_blocking = false
	
func _on_animated_finished() -> void:
	match anim.animation:
		"hurt":
			is_hurt = false
		"death":
			# Placeholder: restart the level after a moment.
			# Don't queue_free() the knight, the Camera2D is his child.
			await get_tree().create_timer(1.5).timeout
			get_tree().reload_current_scene()
		_:
			if is_attacking and anim.animation == current_attack.get("anim", ""):
				finish_attack()


func update_animation(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		anim.play("idle")
		return
	print(scale)
	if abs(direction.x) > abs(direction.y):
		last_direction = "right" if direction.x > 0 else "left"
	else:
		last_direction = "down" if direction.y > 0 else "up"

	# Only change facing when moving horizontally, so up/down keeps the last side
	if direction.x < 0:
		#anim.flip_h = direction.x < 0
		scale.x = -1
	elif direction.x > 0:
		scale.x = 1

	anim.play("walk")

func _on_frame_changed() -> void:
	if not is_attacking:
		return
	if anim.animation != current_attack["anim"]:
		return
	if anim.frame != current_attack["hit_frame"]:
		return

	match current_attack["type"]:
		"melee":
			enable_hitbox()
		"ranged":
			fire_arrow()


func shake(strength: float, duration: float = 0.2) -> void:
	# Don't let a weak shake cancel a stronger one already running
	if strength < shake_strength:
		return
	shake_strength = strength
	shake_decay = strength / duration
