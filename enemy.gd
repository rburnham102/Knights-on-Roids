extends CharacterBody2D
# Shared brain for every enemy (orc, armored orc, skeleton archer, ...).
# It lives on entity.tscn; the enemy scenes inherit that scene, so they get this
# script for free and only override sprites and the @export values below
# (including which AttackData files they use). Enemies with special movement,
# like the archer, attach a small script that `extends "res://enemy.gd"`.

signal died

# What the enemy is doing right now. Exactly one at a time.
#   FREE    - chasing / idle; can start an attack
#   WINDUP  - standing still and flashing: the telegraph before an attack
#   ATTACK  - mid-attack
#   STAGGER - stunned (poise broken, parried, or its guard was broken)
#   GUARD   - shield up: soaks up hits from the front
#   DEAD    - out of health
enum State { FREE, WINDUP, ATTACK, STAGGER, GUARD, DEAD }

const ARROW_SCENE := preload("res://aarow.tscn")

@export var max_health: int = 50
@export var speed: float = 60.0
@export var detect_range: float = 250.0
@export var attack_range: float = 20.0   # was 24, but the swing only reaches ~22 px, so it whiffed a standing target
@export var attack_cooldown: float = 0.4
@export var heavy_chance: float = 0.4   # 40% of attacks are heavy
@export var light_attack: AttackData
@export var heavy_attack: AttackData

@export_group("Special attack")
## An occasional big move (the armored orc's shield smash).
@export var special_attack: AttackData
@export var special_cooldown: float = 4.0
@export var special_chance: float = 0.15
## Chance to pick it when the knight is holding a block: punishes turtling.
@export var special_chance_vs_block: float = 0.7

@export_group("Guard")
## Raises its shield when the knight swings at it (needs a "block" animation).
@export var can_guard := false
@export var guard_chance: float = 0.6
@export var guard_duration: float = 0.9
@export var guard_cooldown: float = 1.0       # can't guard again right after
@export var guard_damage_mult: float = 0.2    # share of damage that gets through from the front
@export var guard_poise_mult: float = 0.25

@export_group("Poise")
## Poise soaks up hits: only when it runs out does the enemy stagger.
## 0 means no poise at all (every hit staggers).
@export var max_poise: float = 0.0
@export var poise_regen: float = 8.0         # per second, once it starts
@export var poise_regen_delay: float = 2.0   # seconds after a hit before it starts

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var hurtbox_shape: CollisionShape2D = $HurtBox/CollisionShape2D

const KNOCKBACK_DECAY := 700.0   # how fast the push fades (pixels/sec per second)
const PARRY_STAGGER := 1.5      # seconds the enemy is helpless after being parried
const PARRY_RECOVERY_COOLDOWN := 0.4   # breathing room after it recovers from a parry
const GUARD_BREAK_STAGGER := 1.2       # seconds helpless after its guard is broken
const GUARD_TRIGGER_RANGE := 45.0      # raises the shield if the knight swings this close
const GUARD_MIN_TIME := 0.35           # keeps the shield up at least this long
const GUARD_TINT := Color(1.8, 1.6, 0.7)
# Lining up: enemies stand beside the knight (in front of or behind him) on
# the same horizontal line, this share of attack_range away from him.
const LANE_SPOT_DISTANCE := 0.75
const LANE_ARRIVE := 2.0   # pixels: close enough to the spot to stop walking

var state := State.FREE
# Read-only conveniences so other scripts (and tests) can ask simple questions.
var is_dead: bool:
	get:
		return state == State.DEAD
var is_hurt: bool:
	get:
		return state == State.STAGGER
var is_guarding: bool:
	get:
		return state == State.GUARD
var is_attacking: bool:   # true from the start of the wind-up until the attack ends
	get:
		return state == State.WINDUP or state == State.ATTACK

var health: int
var poise: float
var poise_delay_left := 0.0
var current_attack: AttackData
var cooldown_left := 0.0
var special_cooldown_left := 0.0
var guard_cooldown_left := 0.0
var guard_left := 0.0
var player_was_swinging := false
var windup_left := 0.0
var stagger_hold := 0.0   # extra helpless time after the hurt animation (parry, guard break)
var hit_bodies: Array = []
var player: Node2D
var knockback := Vector2.ZERO
var tint_tween: Tween

func _ready() -> void:
	health = max_health
	poise = max_poise
	player = get_tree().get_first_node_in_group("player")
	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	hitbox.area_entered.connect(_on_hitbox_area_entered)   # hitbox now looks for HurtBox areas
	# Every attack can resize the damage circle, so give each enemy its own
	# copy of the shape (the scene's shape is shared by all enemies).
	hitbox_shape.shape = hitbox_shape.shape.duplicate()
	hitbox_shape.position = Vector2.ZERO   # the Hitbox node's position alone controls the reach
	anim.play("idle")

# ---------------------------------------------------------------- state machine

func change_state(new_state: State) -> void:
	# Re-entering the same state is allowed on purpose (a fresh hit restarts
	# the hurt animation).
	_exit_state(state, new_state)
	state = new_state
	_enter_state(new_state)

func _exit_state(old_state: State, new_state: State) -> void:
	match old_state:
		State.WINDUP:
			_clear_tint()
			if new_state != State.ATTACK:   # the attack was interrupted before it began
				current_attack = null
				cooldown_left = attack_cooldown
		State.ATTACK:
			current_attack = null
			cooldown_left = attack_cooldown
			anim.speed_scale = 1.0
			hitbox_shape.set_deferred("disabled", true)
		State.GUARD:
			guard_cooldown_left = guard_cooldown
			if new_state == State.FREE:
				cooldown_left = 0.0   # counter-attack: the shield drops and it swings straight away

func _enter_state(new_state: State) -> void:
	match new_state:
		State.WINDUP:
			windup_left = current_attack.windup_time
			velocity = Vector2.ZERO
			anim.play("idle")
			# Fade into the warning colour over the whole wind-up.
			_clear_tint()
			tint_tween = create_tween()
			tint_tween.tween_property(anim, "modulate", current_attack.telegraph_color, current_attack.windup_time)
		State.STAGGER:
			stagger_hold = 0.0
			anim.stop()
			anim.play("hurt")
		State.GUARD:
			guard_left = guard_duration
			velocity = Vector2.ZERO
			anim.play("block")   # facing stays locked while the shield is up
		State.DEAD:
			velocity = Vector2.ZERO
			died.emit()
			body_shape.set_deferred("disabled", true)
			hurtbox_shape.set_deferred("disabled", true)   # corpses can't be hit (arrows fly past)
			anim.play("death")

func _clear_tint() -> void:
	if tint_tween:
		tint_tween.kill()
		tint_tween = null
	anim.modulate = Color.WHITE

func _physics_process(delta: float) -> void:
	cooldown_left = max(cooldown_left - delta, 0.0)
	guard_cooldown_left = max(guard_cooldown_left - delta, 0.0)
	special_cooldown_left = max(special_cooldown_left - delta, 0.0)
	update_poise(delta)

	match state:
		State.DEAD, State.STAGGER:
			process_stagger(delta)
		State.WINDUP:
			process_windup(delta)
		State.GUARD:
			process_guard(delta)
		State.ATTACK:
			stand_still()
		State.FREE:
			process_free(delta)

func process_stagger(delta: float) -> void:
	# Stunned or dying: slide with the knockback, then fade it out
	knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity = knockback
	move_and_slide()
	if state == State.STAGGER and stagger_hold > 0.0:
		stagger_hold -= delta
		if stagger_hold <= 0.0 and not anim.is_playing():
			recover()

func process_windup(delta: float) -> void:
	stand_still()
	if is_instance_valid(player):
		anim.flip_h = player.global_position.x < global_position.x   # keep facing the target
	windup_left -= delta
	if windup_left <= 0.0:
		begin_swing()

func process_guard(delta: float) -> void:
	stand_still()
	guard_left -= delta
	var swinging: bool = is_instance_valid(player) and player.get("is_attacking") == true
	var held := guard_duration - guard_left
	if guard_left <= 0.0 or (not swinging and held >= GUARD_MIN_TIME):
		change_state(State.FREE)

func stand_still() -> void:
	velocity = Vector2.ZERO
	move_and_slide()

# Straight-line chasing deadlocks on a pillar corner, so: if we're trying to
# move but barely getting anywhere, sidestep for a moment. (Real pathfinding,
# NavigationAgent2D, can replace this later if rooms get more complicated.)
var stuck_time := 0.0
var detour_left := 0.0
var detour_dir := Vector2.ZERO

func move_toward_target(direction: Vector2, move_speed: float, delta: float) -> void:
	var heading := direction
	if detour_left > 0.0:
		detour_left -= delta
		heading = (direction + detour_dir * 1.5).normalized()
	velocity = heading * move_speed
	move_and_slide()
	if get_real_velocity().length() < move_speed * 0.3:
		stuck_time += delta
		if stuck_time > 0.25 and detour_left <= 0.0:
			detour_dir = direction.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
			detour_left = 0.6
			stuck_time = 0.0
	else:
		stuck_time = 0.0

func process_free(delta: float) -> void:
	if not is_instance_valid(player):
		stand_still()
		return

	# Stop chasing a dead player
	if player.get("is_dead") == true:
		stand_still()
		anim.play("idle")
		return

	var to_player := player.global_position - global_position
	var distance := to_player.length()

	# Face the player (assumes the art faces right)
	anim.flip_h = to_player.x < 0

	# A shielded enemy reacts the moment the knight starts a swing near it.
	var swinging: bool = player.get("is_attacking") == true
	if can_guard and swinging and not player_was_swinging and distance <= GUARD_TRIGGER_RANGE \
			and guard_cooldown_left <= 0.0 and randf() < guard_chance:
		player_was_swinging = true
		change_state(State.GUARD)
		return
	player_was_swinging = swinging

	# Only attack from in front of or behind the knight: within 45 degrees of
	# horizontal on either side. (The knight only faces left/right, so his
	# front cone plus his back cone is exactly "more sideways than vertical".)
	var in_lane := absf(to_player.y) <= absf(to_player.x)

	if distance <= attack_range and in_lane and cooldown_left <= 0.0:
		start_attack()
	elif distance <= detect_range:
		# Walk to a spot beside the knight on whichever side we're already on,
		# instead of straight at him. Keeps lining up during the cooldown too.
		var side := -1.0 if to_player.x > 0.0 else 1.0
		var spot := player.global_position + Vector2(side * attack_range * LANE_SPOT_DISTANCE, 0.0)
		var to_spot := spot - global_position
		if to_spot.length() > LANE_ARRIVE:
			move_toward_target(to_spot.normalized(), speed, delta)
			anim.play("walk")
		else:
			stand_still()
			anim.play("idle")
	else:
		stand_still()
		anim.play("idle")

# ---------------------------------------------------------------------- attacks

func start_attack() -> void:
	hit_bodies.clear()
	var knight_blocking: bool = is_instance_valid(player) and player.get("is_blocking") == true
	if special_attack != null and special_cooldown_left <= 0.0 \
			and randf() < (special_chance_vs_block if knight_blocking else special_chance):
		current_attack = special_attack
		special_cooldown_left = special_cooldown
	else:
		current_attack = heavy_attack if randf() < heavy_chance else light_attack
	if current_attack.windup_time > 0.0:
		change_state(State.WINDUP)
	else:
		begin_swing()

func begin_swing() -> void:
	change_state(State.ATTACK)
	anim.speed_scale = current_attack.anim_speed
	anim.play(current_attack.anim)

func _on_frame_changed() -> void:
	if state != State.ATTACK or current_attack == null:
		return
	if anim.animation != current_attack.anim:
		return
	if anim.frame == current_attack.hit_frame:
		if current_attack.type == AttackData.Type.RANGED:
			fire_projectile()
		else:
			var dir := -1.0 if anim.flip_h else 1.0
			hitbox.position.x = current_attack.hitbox_offset * dir
			(hitbox_shape.shape as CircleShape2D).radius = current_attack.hitbox_radius
			hitbox_shape.set_deferred("disabled", false)
	elif current_attack.type == AttackData.Type.MELEE and current_attack.active_frames > 0 \
			and anim.frame == current_attack.hit_frame + current_attack.active_frames:
		hitbox_shape.set_deferred("disabled", true)   # the damaging part of the attack is over

func fire_projectile() -> void:
	if not is_instance_valid(player):
		return
	var origin := global_position + Vector2(0, -8)
	var dir := (player.global_position + Vector2(0, -7) - origin).normalized()
	var arrow := ARROW_SCENE.instantiate()
	arrow.from_enemy = true
	arrow.direction = dir
	arrow.damage = current_attack.damage
	arrow.speed = current_attack.projectile_speed
	arrow.max_range = current_attack.projectile_range
	arrow.knockback_force = current_attack.knockback
	get_parent().add_child(arrow)
	arrow.global_position = origin + dir * 10.0

func _on_hitbox_area_entered(area: Area2D) -> void:
	if current_attack == null:
		return
	# `area` is a HurtBox. Its owner is the root of the scene it belongs to,
	# i.e. the character that was hit.
	var target: Node2D = area.owner
	if target == self or target in hit_bodies:
		return
	if target.is_in_group("player") and target.has_method("take_damage"):
		hit_bodies.append(target)
		var result: Combat.HitResult = target.take_damage(current_attack.damage, global_position, current_attack.knockback, 0.0, Combat.flags_of(current_attack))
		match result:
			Combat.HitResult.BLOCKED:
				get_blocked()
			Combat.HitResult.PARRIED:
				get_parried()

func get_blocked() -> void:
	# A plain block only stops the damage. The attacker keeps swinging and
	# isn't punished: punishing is what a parry is for.
	anim.self_modulate = GUARD_TINT
	create_tween().tween_property(anim, "self_modulate", Color.WHITE, 0.2)

func get_parried() -> void:
	if state == State.DEAD:
		return
	poise = max_poise   # poise is broken, so the next hits can't be shrugged off
	change_state(State.STAGGER)
	stagger_hold = PARRY_STAGGER
	knockback = Vector2.ZERO   # stay put so the riposte lands
	cooldown_left = PARRY_STAGGER + PARRY_RECOVERY_COOLDOWN
	anim.modulate = Color(1.0, 0.9, 0.4)
	create_tween().tween_property(anim, "modulate", Color.WHITE, PARRY_STAGGER)

# ------------------------------------------------------------- damage and poise

func update_poise(delta: float) -> void:
	if max_poise <= 0.0:
		return
	if poise_delay_left > 0.0:
		poise_delay_left -= delta
	elif poise < max_poise:
		poise = minf(poise + poise_regen * delta, max_poise)

# Is the attacker on the side this enemy is facing? (A raised shield only
# covers the front.)
func is_frontal(from_position: Vector2) -> bool:
	var facing := -1.0 if anim.flip_h else 1.0
	return (from_position.x - global_position.x) * facing >= 0.0

func take_damage(amount: int, from_position: Vector2 = Vector2.ZERO, force: float = 0.0, poise_damage: float = 0.0, flags: int = 0) -> void:
	if state == State.DEAD:
		return

	var guarded := false
	var guard_shattered := false
	if state == State.GUARD and is_frontal(from_position):
		if flags & Combat.FLAG_GUARD_BREAK:
			guard_shattered = true   # a heavy hit breaks the shield: full damage
		else:
			guarded = true
			amount = maxi(1, roundi(amount * guard_damage_mult))
			poise_damage *= guard_poise_mult
			force = 0.0

	health -= amount
	poise_delay_left = poise_regen_delay

	if health <= 0:
		if force > 0.0:
			knockback = (global_position - from_position).normalized() * force
		die()
		return

	if guard_shattered:
		poise = max_poise
		if force > 0.0:
			knockback = (global_position - from_position).normalized() * force
		change_state(State.STAGGER)
		stagger_hold = GUARD_BREAK_STAGGER
		return

	var broke_poise := true
	if max_poise > 0.0:
		poise -= poise_damage
		broke_poise = poise <= 0.0

	if state == State.STAGGER and (max_poise > 0.0 or stagger_hold > 0.0):
		# Already stunned (or held open by a parry): take the damage and the
		# push, but don't restart or shorten the stun.
		if force > 0.0:
			knockback = (global_position - from_position).normalized() * force
		hit_flash()
	elif broke_poise:
		poise = max_poise
		if force > 0.0:
			knockback = (global_position - from_position).normalized() * force
		change_state(State.STAGGER)   # interrupts whatever it was doing
	else:
		hit_flash(GUARD_TINT if guarded else Color(2.0, 2.0, 2.0))   # shrugged it off

func hit_flash(tint := Color(2.0, 2.0, 2.0)) -> void:
	# self_modulate, so it doesn't fight the wind-up tint that uses modulate.
	anim.self_modulate = tint
	create_tween().tween_property(anim, "self_modulate", Color.WHITE, 0.12)

func die() -> void:
	change_state(State.DEAD)

func recover() -> void:
	change_state(State.FREE)
	anim.play("idle")

func _on_animation_finished() -> void:
	match anim.animation:
		"hurt":
			if state == State.STAGGER and stagger_hold <= 0.0:
				recover()
		"death":
			queue_free()
		_:
			if state == State.ATTACK and current_attack != null and anim.animation == current_attack.anim:
				change_state(State.FREE)
