extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal guard_changed(current: float, maximum: float)
signal died   # a run manager listens to this; without one the level just reloads

# What the knight is doing right now. Exactly one at a time.
#   FREE   - idle/walking; can start an attack or a block
#   ATTACK - mid-swing
#   BLOCK  - holding the guard up
#   HURT   - stunned after taking damage
#   DODGE  - dashing; invulnerable for the first part of it
#   DEAD   - out of health
enum State { FREE, ATTACK, BLOCK, HURT, DODGE, DEAD }

const SPEED = 100.0
const BASE_HEALTH := 100               # max health at vitality 10 (see Stats)
const ARROW_SCENE := preload("res://aarow.tscn")
const KNOCKBACK_DECAY := 700.0
# Block is deliberately NOT scaled by stats: these are fixed values.
const MAX_GUARD := 60.0
const GUARD_REGEN := 12.0              # guard recovered per second
const GUARD_REGEN_DELAY := 1.5         # seconds after a blocked hit before regen starts
const GUARD_BREAK_DELAY := 2.5         # longer delay when the guard breaks
const GUARD_RECOVER_AT := 20.0         # after a break, block is unusable until guard reaches this
const BLOCK_KNOCKBACK_PER_DAMAGE := 8.0
const LUNGE_DECAY := 500.0   # how fast the lunge slows down (pixels/sec per second)
const COMBO_WINDOW := 0.35   # seconds after a swing ends to still continue the chain
# After a riposte, the heavy finisher gets a more generous window: the riposte
# swings by itself, so the player has to react to it ending.
const RIPOSTE_FOLLOWUP_WINDOW := 0.5
const BLOCK_EFFECT := preload("res://block_effect.tscn")

# Parry: a block raised this shortly before impact is a perfect block.
# (Dexterity widens it, see Stats.parry_window_mult.)
const PARRY_WINDOW := 0.15
const PARRY_HIT_STOP := 0.1
# After lowering the guard it can't go straight back up, so tapping block
# over and over doesn't farm parries.
const BLOCK_RERAISE_DELAY := 0.3

# Dodge
const DODGE_ANIM := &"dodge"          # add an animation with this name to the Knight's SpriteFrames
const DODGE_DURATION := 0.25          # seconds the whole dash lasts
const DODGE_IFRAMES := 0.18           # first part of the dash you can't be hit
const DODGE_DISTANCE := 30.0          # pixels (Dexterity scales it). Was 60.
const DODGE_COOLDOWN := 0.7           # seconds from the start of one dodge to the next
const DODGE_DIRECTION_GRACE := 0.12   # let go of the keys this recently? dash the way you were going
const DODGE_STEER_WINDOW := 0.05      # a direction pressed this soon after Shift still steers the dash
const GUARD_BREAK_DAMAGE_THROUGH := 0.5   # share of a guard-breaking hit that still lands

const DIRECTIONS := {
	"up": Vector2.UP,
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}
const HITBOX_DISTANCE := 18.0   # was 20: 18 also reaches an enemy at body contact (8 px)

# Set these in the Inspector (see Knight.tscn).
@export var stats: Stats
@export var light_combo: Array[AttackData]   # swings in order; the light button walks this chain
@export var heavy_attack: AttackData
@export var ranged_attack: AttackData
@export var riposte_attack: AttackData      # swung automatically after a parry

@onready var pivot: Node2D = $Pivot
@onready var anim: AnimatedSprite2D = $Pivot/AnimatedSprite2D
@onready var hitbox: Area2D = $Pivot/Hitbox
@onready var hitbox_shape: CollisionShape2D = $Pivot/Hitbox/CollisionShape2D
@onready var camera: Camera2D = $Camera2D

var state := State.FREE
# Read-only convenience so other scripts (the enemies) can ask "is he dead?"
var is_dead: bool:
	get:
		return state == State.DEAD

var health: int
var current_attack: AttackData   # only set while state == ATTACK
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
var guard_broken := false   # a condition that outlasts any one state, so it isn't a State
var guard_bar: ProgressBar
var guard_fill: StyleBoxFlat

var lunge_velocity := Vector2.ZERO
var block_time := 0.0                 # seconds since the guard went up
var block_raise_cooldown_left := 0.0
var perks := {}              # perk id -> stack count, filled in by the run manager
var is_riposte := false      # the current swing is a riposte (perks can boost it)
var block_needs_repress := false   # after a hit or a dodge, a block key still held down doesn't re-raise the guard
var dodge_time := 0.0
var dodge_cooldown_left := 0.0
var dodge_velocity := Vector2.ZERO
var dodge_direction_pending := false   # dash started with no direction yet; a late key can still steer it
var last_move_input := Vector2.ZERO
var since_move := 10.0                  # seconds since a movement key was last held
var normal_collision_layer := 0
var normal_collision_mask := 0
# True while a dodge's invulnerable frames are running.
var is_invulnerable: bool:
	get:
		return state == State.DODGE and dodge_time < DODGE_IFRAMES + 0.06 * perk(&"long_dodge")
# Read-only conveniences so enemies can read what the knight is doing.
var is_attacking: bool:
	get:
		return state == State.ATTACK
var is_blocking: bool:
	get:
		return state == State.BLOCK

func _ready() -> void:
	add_to_group("player")   # <-- lets the orc find the knight
	if stats == null:
		stats = Stats.new()   # safety net: all-10 stats = the base numbers
	health = max_health()
	normal_collision_layer = collision_layer
	normal_collision_mask = collision_mask
	setup_guard_bar()

func max_health() -> int:
	return roundi(BASE_HEALTH * stats.health_mult())

func perk(id: StringName) -> int:
	return int(perks.get(id, 0))

func heal(amount: int) -> void:
	if state == State.DEAD or amount <= 0:
		return
	health = mini(health + amount, max_health())
	health_changed.emit(health, max_health())

# Called by the run manager when the knight is placed in a new room.
func reset_for_new_room() -> void:
	velocity = Vector2.ZERO
	knockback = Vector2.ZERO
	lunge_velocity = Vector2.ZERO
	if state != State.DEAD and state != State.FREE:
		change_state(State.FREE)
	last_direction = "right"
	face(1.0)

# ---------------------------------------------------------------- state machine

func change_state(new_state: State) -> void:
	# Re-entering the same state is allowed on purpose: a second hit while
	# hurt restarts the hurt animation.
	_exit_state(state)
	state = new_state
	_enter_state(new_state)

func _exit_state(old_state: State) -> void:
	match old_state:
		State.BLOCK:
			block_raise_cooldown_left = BLOCK_RERAISE_DELAY
		State.DODGE:
			collision_layer = normal_collision_layer   # solid to enemies again
			collision_mask = normal_collision_mask
			anim.speed_scale = 1.0
			anim.modulate.a = 1.0
		State.ATTACK:
			# One place that cleans up an attack, however it ended
			# (finished, or interrupted by damage).
			current_attack = null
			is_riposte = false
			attack_from_combo = false
			lunge_velocity = Vector2.ZERO
			disable_hitbox()

func _enter_state(new_state: State) -> void:
	match new_state:
		State.BLOCK:
			reset_combo()   # blocking breaks any combo in progress
			block_time = 0.0
			anim.play("block")
		State.DODGE:
			block_needs_repress = true
			start_dodge_motion()
		State.HURT:
			block_needs_repress = true
			reset_combo()
			anim.stop()
			anim.play("hurt")
		State.DEAD:
			reset_combo()
			velocity = Vector2.ZERO
			anim.play("death")

func reset_combo() -> void:
	combo_index = 0
	combo_window = 0.0
	combo_queued = false
	attack_from_combo = false

func _physics_process(delta: float) -> void:
	update_shake(delta)
	update_guard(delta)
	update_guard_bar()
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move_input != Vector2.ZERO:
		last_move_input = move_input
		since_move = 0.0
	else:
		since_move += delta
	dodge_cooldown_left = maxf(dodge_cooldown_left - delta, 0.0)
	block_raise_cooldown_left = maxf(block_raise_cooldown_left - delta, 0.0)

	match state:
		State.DEAD, State.HURT:
			slide_with_knockback(delta)
		State.DODGE:
			process_dodge(delta)
		State.BLOCK:
			process_block(delta)
		State.ATTACK:
			process_attack(delta)
		State.FREE:
			process_free(delta)

func process_free(delta: float) -> void:
	if dodge_pressed():
		change_state(State.DODGE)
		process_dodge(delta)
		return

	# Hold to block. Can't start while guard-broken, right after lowering it, or
	# if the key has been held since a hit/dodge (let go and press again).
	if not Input.is_action_pressed("block"):
		block_needs_repress = false
	if Input.is_action_pressed("block") and not guard_broken and block_raise_cooldown_left <= 0.0 and not block_needs_repress:
		change_state(State.BLOCK)
		slide_with_knockback(delta)
		return

	# Combo window counts down only while free
	combo_window = max(combo_window - delta, 0.0)
	if combo_window == 0.0:
		combo_index = 0

	if Input.is_action_just_pressed("attack_light"):
		start_combo_attack()
	elif Input.is_action_just_pressed("attack_heavy"):
		start_attack(heavy_attack)
	elif Input.is_action_just_pressed("attack_bow"):
		start_attack(ranged_attack)

	if state == State.ATTACK:   # an attack just started this frame
		apply_lunge(delta)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity = direction * SPEED * stats.speed_mult() + knockback
	move_and_slide()
	update_animation(direction)

func process_block(delta: float) -> void:
	if dodge_pressed():
		change_state(State.DODGE)
		process_dodge(delta)
		return
	if not Input.is_action_pressed("block"):
		change_state(State.FREE)
		process_free(delta)   # let go this frame = free to act this frame
		return
	block_time += delta
	slide_with_knockback(delta)   # no attacking or walking while blocking

# ---------------------------------------------------------------------- dodge

func dodge_pressed() -> bool:
	return dodge_cooldown_left <= 0.0 and Input.is_action_just_pressed("dodge")

# Called when the DODGE state is entered: pick a direction and start the dash.
func start_dodge_motion() -> void:
	reset_combo()
	dodge_time = 0.0
	dodge_cooldown_left = maxf(DODGE_COOLDOWN - 0.2 * perk(&"quick_dodge"), 0.3)
	# Dash the way you're steering. If you let go a split second ago, use the
	# direction you were going; only if you've been standing still do you dash
	# the way you face (and even then a direction pressed in the next few
	# frames still steers it).
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	dodge_direction_pending = false
	if dir == Vector2.ZERO and since_move <= DODGE_DIRECTION_GRACE:
		dir = last_move_input
	if dir == Vector2.ZERO:
		# No direction: hop backwards, still facing the same way.
		set_dodge_direction(-DIRECTIONS[last_direction], false)
		dodge_direction_pending = true
	else:
		set_dodge_direction(dir)
	# Slip through enemies but not walls. Both lines are needed: the mask stops
	# US seeing them, the layer stops THEM seeing us (otherwise they'd get
	# shoved along by the dash).
	collision_layer = 0
	collision_mask = 1   # layer 1 = world

	# Use the "dodge" animation if it exists, stretched or squeezed so it
	# lasts exactly as long as the dash. Otherwise fall back to a fast walk.
	var frames := anim.sprite_frames
	if frames.has_animation(DODGE_ANIM):
		var play_time := frames.get_frame_count(DODGE_ANIM) / frames.get_animation_speed(DODGE_ANIM)
		anim.speed_scale = play_time / DODGE_DURATION
		anim.play(DODGE_ANIM)
	else:
		anim.speed_scale = 2.0
		anim.play("walk")

func set_dodge_direction(dir: Vector2, turn := true) -> void:
	if turn:
		set_facing(dir)
	dodge_velocity = dir.normalized() * DODGE_DISTANCE * stats.dodge_distance_mult() / DODGE_DURATION

func process_dodge(delta: float) -> void:
	dodge_time += delta
	if dodge_direction_pending and dodge_time <= DODGE_STEER_WINDOW:
		var steer := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if steer != Vector2.ZERO:
			set_dodge_direction(steer)
			dodge_direction_pending = false
	anim.modulate.a = 0.4 if is_invulnerable else 1.0   # ghostly while you can't be hit
	velocity = dodge_velocity
	move_and_slide()
	if dodge_time >= DODGE_DURATION:
		change_state(State.FREE)

func process_attack(delta: float) -> void:
	# Light button during a swing buffers the next combo hit, but only after
	# the hit frame (so mashing doesn't chain by itself). A riposte is the
	# exception: it starts on its own, so a press any time during it counts.
	if Input.is_action_just_pressed("attack_light") and (is_riposte or anim.frame >= current_attack.hit_frame):
		combo_queued = true
	apply_lunge(delta)

func slide_with_knockback(delta: float) -> void:
	knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity = knockback
	move_and_slide()

func apply_lunge(delta: float) -> void:
	lunge_velocity = lunge_velocity.move_toward(Vector2.ZERO, LUNGE_DECAY * delta)
	velocity = lunge_velocity
	move_and_slide()

func update_shake(delta: float) -> void:
	if shake_strength > 0.0:
		shake_strength = max(shake_strength - shake_decay * delta, 0.0)
		camera.offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
	else:
		camera.offset = Vector2.ZERO

# ---------------------------------------------------------------------- attacks

func start_combo_attack() -> void:
	if combo_window <= 0.0:
		combo_index = 0   # window expired, restart the chain
	var attack := light_combo[combo_index]
	combo_index = (combo_index + 1) % light_combo.size()   # wraps to 0 after the finisher
	combo_window = 0.0
	start_attack(attack, true)

func start_attack(attack: AttackData, from_combo := false) -> void:
	change_state(State.ATTACK)
	attack_from_combo = from_combo
	current_attack = attack
	hit_bodies.clear()

	if attack.type == AttackData.Type.RANGED:
		aim_direction = (get_global_mouse_position() - global_position).normalized()
		face(aim_direction.x)
	elif not is_riposte:
		# Swing the way the player is pressing right now. Without this, a combo
		# keeps the direction of its first swing, because last_direction is
		# otherwise only updated while walking. (A riposte aims at the attacker.)
		var held := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if held != Vector2.ZERO:
			set_facing(held)

	anim.play(attack.anim)
	if attack.lunge > 0.0:
		lunge_velocity = DIRECTIONS[last_direction] * attack.lunge * stats.lunge_mult()
	else:
		lunge_velocity = Vector2.ZERO

func finish_attack() -> void:
	var continue_combo := attack_from_combo and combo_index != 0
	var was_riposte := is_riposte   # read it now: the exit hook below clears it
	change_state(State.FREE)   # the ATTACK exit hook clears the attack
	if continue_combo:
		var window := RIPOSTE_FOLLOWUP_WINDOW if was_riposte else COMBO_WINDOW
		combo_window = window * stats.combo_window_mult()
		if combo_queued:
			combo_queued = false
			start_combo_attack()   # chains straight into the next swing
			return
	else:
		combo_index = 0
	combo_queued = false

# Damage and knockback of the current attack after Power is applied.
func attack_damage() -> int:
	var mult := stats.damage_mult()
	if is_riposte:
		mult *= 1.0 + 0.6 * perk(&"riposte_power")
	return roundi(current_attack.damage * mult)

func attack_knockback() -> float:
	return current_attack.knockback * stats.knockback_mult()

func attack_poise_damage() -> float:
	return current_attack.poise_damage * stats.poise_damage_mult()

func parry_window() -> float:
	return PARRY_WINDOW * stats.parry_window_mult()

# Called on a perfect block: turn to face the attacker and counter-attack.
func start_riposte(attacker_position: Vector2) -> void:
	set_facing(attacker_position - global_position)
	# Pretend we're on the last link before the finisher, so pressing light
	# right after the riposte continues the chain into the heavy.
	combo_index = light_combo.size() - 1
	is_riposte = true
	start_attack(riposte_attack, true)

func fire_arrow() -> void:
	var arrow = ARROW_SCENE.instantiate()
	arrow.direction = aim_direction
	arrow.damage = attack_damage()
	arrow.knockback_force = attack_knockback()
	arrow.poise_damage = attack_poise_damage()
	# Add to the level, NOT to the knight, so it doesn't move with him
	get_parent().add_child(arrow)
	arrow.global_position = %ShootingPoint.global_position

func enable_hitbox() -> void:
	var d: Vector2 = DIRECTIONS[last_direction]
	hitbox.position = Vector2(absf(d.x), d.y) * HITBOX_DISTANCE
	hitbox_shape.set_deferred("disabled", false)

func disable_hitbox() -> void:
	hitbox_shape.set_deferred("disabled", true)

func _on_hitbox_area_entered(area: Area2D) -> void:
	if current_attack == null:
		return
	# `area` is an enemy HurtBox. Its owner is the root of the scene it
	# belongs to, i.e. the enemy that was hit.
	var body: Node = area.owner
	if body == self or body in hit_bodies:
		return
	hit_bodies.append(body)
	if body.has_method("take_damage"):
		body.take_damage(attack_damage(), global_position, attack_knockback(), attack_poise_damage(), Combat.flags_of(current_attack))
		if current_attack.shake > 0.0:
			shake(current_attack.shake)
		if current_attack.hit_stop > 0.0:
			Combat.hit_stop(current_attack.hit_stop)

func _on_frame_changed() -> void:
	if state != State.ATTACK or current_attack == null:
		return
	if anim.animation != current_attack.anim:
		return
	if anim.frame != current_attack.hit_frame:
		return

	match current_attack.type:
		AttackData.Type.MELEE:
			enable_hitbox()
		AttackData.Type.RANGED:
			fire_arrow()

# ------------------------------------------------------------------ guard / HP

func update_guard(delta: float) -> void:
	if guard_regen_delay_left > 0.0:
		guard_regen_delay_left -= delta
		return
	if state == State.BLOCK or guard >= MAX_GUARD:
		return   # no regen while holding block
	set_guard(minf(guard + GUARD_REGEN * (1.0 + 0.5 * perk(&"iron_guard")) * delta, MAX_GUARD))
	if guard_broken and guard >= GUARD_RECOVER_AT:
		guard_broken = false

func set_guard(value: float) -> void:
	guard = value
	guard_changed.emit(guard, MAX_GUARD)

func block_flash(from_position: Vector2, heavy: bool, parry := false) -> void:
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
	fx.scale = Vector2(1.5, 1.5) if heavy else Vector2.ONE
	if parry:
		fx.scale = Vector2(1.8, 1.8)
		fx.modulate = Color(1.0, 0.85, 0.3)   # gold, so a parry looks different from a block

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

func take_damage(amount: int, from_position: Vector2 = Vector2.ZERO, force: float = 0.0, _poise_damage: float = 0.0, flags: int = 0) -> Combat.HitResult:
	if state == State.DEAD:
		return Combat.HitResult.HIT   # nothing to do to a dead knight

	# Invulnerability is a check here instead of switching the HurtBox off:
	# re-enabling a hurtbox that still overlaps a swing would register a hit.
	if is_invulnerable:
		return Combat.HitResult.DODGED

	if state == State.BLOCK and (flags & Combat.FLAG_GUARD_BREAK):
		# Shield smash and friends: the guard shatters and part of the hit gets through.
		block_flash(from_position, true)
		shake(4.0)
		set_guard(0.0)
		guard_broken = true
		guard_regen_delay_left = GUARD_BREAK_DELAY
		amount = ceili(amount * GUARD_BREAK_DAMAGE_THROUGH)
		change_state(State.HURT)   # leaves BLOCK, so the plain-block code below is skipped
	elif state == State.BLOCK and block_time <= parry_window() and not (flags & Combat.FLAG_UNPARRYABLE):
		# Perfect block: no guard lost, no push, and we hit back.
		shake(2.5)
		block_flash(from_position, true, true)
		Combat.hit_stop(PARRY_HIT_STOP)
		heal(5 * perk(&"parry_heal"))
		if not (flags & Combat.FLAG_PROJECTILE):
			start_riposte(from_position)   # nobody to counter-attack when it's an arrow
		return Combat.HitResult.PARRIED

	if state == State.BLOCK:
		var absorbed := mini(amount, int(guard))
		var leftover := amount - absorbed
		set_guard(guard - absorbed)
		guard_regen_delay_left = GUARD_REGEN_DELAY

		if from_position != Vector2.ZERO:
			knockback = (global_position - from_position).normalized() * float(amount) * BLOCK_KNOCKBACK_PER_DAMAGE
		shake(1.5)
		block_flash(from_position, amount >= 15)

		print("Blocked ", absorbed, " | guard: ", guard)

		if leftover <= 0:
			return Combat.HitResult.BLOCKED   # fully blocked, the attacker will recoil

		# Guard break: the rest of the damage goes through
		set_guard(0.0)
		guard_broken = true
		guard_regen_delay_left = GUARD_BREAK_DELAY
		amount = leftover
		force = 0.0

	health -= amount
	health_changed.emit(maxi(health, 0), max_health())
	print("Knight health: ", health)
	shake(2.0 if amount < 15 else 4.0)

	if force > 0.0:
		knockback = (global_position - from_position).normalized() * force

	# Changing state runs the exit hook of whatever we were doing (an attack
	# in progress is cancelled) and the enter hook of the new state.
	if health <= 0:
		die()
	else:
		change_state(State.HURT)
	return Combat.HitResult.HIT

func die() -> void:
	change_state(State.DEAD)

# -------------------------------------------------------------------- animation

# Turn toward a direction: picks the main axis for last_direction (which way
# swings and lunges go) and flips the sprite. Only horizontal input flips the
# sprite, so moving straight up/down keeps the side you were facing.
func set_facing(dir: Vector2) -> void:
	if dir.x != 0.0:
		last_direction = "right" if dir.x > 0 else "left"
	face(dir.x)

func face(dir_x: float) -> void:
	if dir_x != 0.0:
		pivot.scale.x = -1.0 if dir_x < 0.0 else 1.0

func _on_animated_finished() -> void:
	match anim.animation:
		"hurt":
			if state == State.HURT:
				change_state(State.FREE)
		"death":
			# Placeholder: restart the level after a moment.
			# Don't queue_free() the knight, the Camera2D is his child.
			await get_tree().create_timer(1.5).timeout
			if died.get_connections().is_empty():
				get_tree().reload_current_scene()   # sandbox level: just restart
			else:
				died.emit()   # a run manager is listening: it decides what happens
		_:
			if state == State.ATTACK and anim.animation == current_attack.anim:
				finish_attack()

func update_animation(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		anim.play("idle")
		return
	set_facing(direction)
	anim.play("walk")

func shake(strength: float, duration: float = 0.2) -> void:
	# Don't let a weak shake cancel a stronger one already running
	if strength < shake_strength:
		return
	shake_strength = strength
	shake_decay = strength / duration
