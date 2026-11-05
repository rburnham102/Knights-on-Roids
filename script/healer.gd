class_name Healer
extends CharacterBody2D
## A priestess hired as an upgrade. She follows behind the knight, heals him
## every so often, and when enemies get on top of her she knocks them away with
## a burst of holy fire. She's fragile: when she dies, the perk is gone (and
## her card goes back into the upgrade pool).
##
## The run manager creates her, tells her who the knight is, and listens for
## `died`. She doesn't know anything about rooms or upgrades.

signal died

# What she's doing right now. Exactly one at a time (same idea as the knight).
#   FOLLOW - walking behind the knight (or idling when she's there)
#   HEAL   - casting her heal on the knight
#   ATTACK - casting the defensive burst
#   HURT   - flinching from a hit
#   DEAD   - out of health
enum State { FOLLOW, HEAL, ATTACK, HURT, DEAD }

const HOLY_BURST := preload("res://effects/holy_burst.tscn")
const HEAL_EFFECT := preload("res://effects/heal_effect.tscn")

@export var max_health := 40
@export var speed := 90.0                 # a little slower than the knight (100)

@export_group("Heal")
@export var heal_amount := 20
@export var heal_cooldown := 30.0         # seconds between heals
@export var heal_range := 90.0            # how close the knight must be
@export var heal_frame := 4               # frame of "heal" where the magic lands

@export_group("Holy burst")
@export var burst_damage := 3             # barely a scratch...
@export var burst_poise_damage := 999.0   # ...but it always staggers, which is what pushes
@export var burst_force := 260.0          # knockback speed (the knight's heavy is ~150)
@export var burst_radius := 30.0
@export var burst_cooldown := 3.0
@export var burst_frame := 4              # frame of "attack" where the fire appears
@export var threat_range := 24.0          # an enemy winding up this close sets her off

@export_group("Following")
@export var follow_offset := Vector2(18, -3)   # behind the knight, a little above
@export var follow_slack := 6.0                # close enough: stop walking

var knight: Node2D                 # set by the run manager before she's added
var health := 0
var state := State.FOLLOW
var heal_cooldown_left := 0.0
var burst_cooldown_left := 0.0
var side := -1.0                   # -1 = left of the knight, 1 = right
var cast_done := false             # this cast already landed

# Enemies check these on whoever they're chasing (the knight has them too).
var is_dead: bool:
	get: return state == State.DEAD
var is_attacking := false
var is_blocking := false

@onready var anim: AnimatedSprite2D = $Pivot/AnimatedSprite2D
@onready var pivot: Node2D = $Pivot
@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	add_to_group("allies")   # enemy swings hurt anything in this group
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	anim.play("idle")

func _physics_process(delta: float) -> void:
	heal_cooldown_left = maxf(heal_cooldown_left - delta, 0.0)
	burst_cooldown_left = maxf(burst_cooldown_left - delta, 0.0)

	if state == State.DEAD or not is_instance_valid(knight):
		velocity = Vector2.ZERO
		return

	if state == State.FOLLOW:
		# Defending herself comes first, then healing, then walking.
		if burst_cooldown_left <= 0.0 and _enemy_threatening():
			change_state(State.ATTACK)
		elif heal_cooldown_left <= 0.0 and _knight_needs_heal():
			change_state(State.HEAL)
		else:
			_follow()
			move_and_slide()
			return
	velocity = Vector2.ZERO   # casting or flinching: stand still

# ----------------------------------------------------------------- decisions

func _follow() -> void:
	# Stay on the side the knight's back is facing. Only switch when he turns
	# left or right, so moving up/down doesn't make her swap sides.
	var facing: float = knight.pivot.scale.x
	side = -facing
	var spot := knight.global_position + Vector2(follow_offset.x * side, follow_offset.y)
	var to_spot := spot - global_position
	if to_spot.length() > follow_slack:
		velocity = to_spot.normalized() * speed
		face(to_spot.x)
		anim.play("walk")
	else:
		velocity = Vector2.ZERO
		face(knight.global_position.x - global_position.x)
		anim.play("idle")

func _knight_needs_heal() -> bool:
	if knight.is_dead:
		return false
	# Wait until the whole heal is useful, so it's never wasted topping him up.
	var missing: int = knight.max_health() - knight.health
	return missing >= heal_amount and global_position.distance_to(knight.global_position) <= heal_range

# An enemy close by that is winding up or swinging at her.
func _enemy_threatening() -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.player != self or enemy.is_dead:
			continue
		if enemy.global_position.distance_to(global_position) > threat_range:
			continue
		if enemy.state == enemy.State.WINDUP or enemy.state == enemy.State.ATTACK:
			return true
	return false

# ------------------------------------------------------------- state machine

func change_state(new_state: State) -> void:
	state = new_state
	cast_done = false
	match new_state:
		State.FOLLOW:
			anim.play("idle")
		State.HEAL:
			face(knight.global_position.x - global_position.x)
			anim.play("heal")
		State.ATTACK:
			var nearest := _nearest_enemy()
			if nearest:
				face(nearest.global_position.x - global_position.x)
			anim.play("attack")
		State.HURT:
			anim.play("hurt")
		State.DEAD:
			anim.play("death")
			health_bar.hide()
			$CollisionShape2D.set_deferred("disabled", true)
			$Pivot/HurtBox/CollisionShape2D.set_deferred("disabled", true)
			died.emit()

func _on_frame_changed() -> void:
	if cast_done:
		return
	if state == State.HEAL and anim.frame == heal_frame:
		cast_done = true
		_cast_heal()
	elif state == State.ATTACK and anim.frame == burst_frame:
		cast_done = true
		_cast_burst()

func _on_animation_finished() -> void:
	match state:
		State.HEAL, State.ATTACK:
			change_state(State.FOLLOW)
		State.HURT:
			# Hit back if the burst is ready and there's someone to push away.
			var nearest := _nearest_enemy()
			var close := nearest != null and nearest.global_position.distance_to(global_position) <= burst_radius
			change_state(State.ATTACK if burst_cooldown_left <= 0.0 and close else State.FOLLOW)
		State.DEAD:
			var fade := create_tween()
			fade.tween_property(self, "modulate:a", 0.0, 0.6)
			fade.tween_callback(queue_free)

# ----------------------------------------------------------------- abilities

func _cast_heal() -> void:
	heal_cooldown_left = heal_cooldown
	if not is_instance_valid(knight) or knight.is_dead:
		return
	knight.heal(heal_amount)
	var fx: Node2D = HEAL_EFFECT.instantiate()
	knight.add_child(fx)   # rides along with the knight while it plays

func _cast_burst() -> void:
	burst_cooldown_left = burst_cooldown
	var burst: HolyBurst = HOLY_BURST.instantiate()
	burst.damage = burst_damage
	burst.poise_damage = burst_poise_damage
	burst.force = burst_force
	burst.radius = burst_radius
	get_parent().add_child(burst)   # into Actors, so it doesn't move with her
	# 1 px above her feet, so y-sorting draws the fire behind her, not over her.
	burst.global_position = global_position + Vector2(0, -1)

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_dead:
			continue
		if best == null or enemy.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = enemy
	return best

# ------------------------------------------------------------ health & hits

# Same signature as the knight's, so enemy swings and arrows don't care who
# they hit. She can't block or dodge.
func take_damage(amount: int, _from_position := Vector2.ZERO, _force := 0.0, _poise_damage := 0.0, _flags := 0) -> Combat.HitResult:
	if state == State.DEAD:
		return Combat.HitResult.HIT
	health = maxi(health - amount, 0)
	health_bar.value = health
	_flash()
	if health <= 0:
		change_state(State.DEAD)
	elif state != State.ATTACK:   # don't interrupt the burst she's casting
		change_state(State.HURT)
	return Combat.HitResult.HIT

func heal(amount: int) -> void:
	if state == State.DEAD or amount <= 0:
		return
	health = mini(health + amount, max_health)
	health_bar.value = health

func face(dir_x: float) -> void:
	if dir_x != 0.0:
		pivot.scale.x = -1.0 if dir_x < 0.0 else 1.0

func _flash() -> void:
	anim.self_modulate = Color(2.0, 2.0, 2.0)
	create_tween().tween_property(anim, "self_modulate", Color.WHITE, 0.12)

# Called by the run manager when the knight walks into a new room.
func place_beside_knight() -> void:
	global_position = knight.global_position + Vector2(follow_offset.x * side, follow_offset.y)
	velocity = Vector2.ZERO
	if state != State.DEAD:
		change_state(State.FOLLOW)
