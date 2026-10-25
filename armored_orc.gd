extends CharacterBody2D

signal died

@export var max_health: int = 50
@export var speed: float = 60.0
@export var detect_range: float = 250.0
@export var attack_range: float = 24.0
@export var attack_cooldown: float = 1.2
@export var heavy_chance: float = 0.3   # 30% of attacks are heavy

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D

const ATTACKS := {
	"light": {"anim": "attack_light", "damage": 8,  "hit_frame": 2, "knockback": 120.0},
	"heavy": {"anim": "attack_heavy", "damage": 20, "hit_frame": 4, "knockback": 250.0},
}

const HITBOX_DISTANCE := 8.0
const KNOCKBACK_DECAY := 700.0   # how fast the push fades (pixels/sec per second)
const BLOCKED_RECOIL := 180.0   # push away from the knight when blocked
const BLOCKED_COOLDOWN := 1.8   # extra time before it can swing again


var health: int
var is_dead := false
var is_hurt := false
var is_attacking := false
var current_attack: Dictionary = {}
var cooldown_left := 0.0
var hit_bodies: Array = []
var player: Node2D
var knockback := Vector2.ZERO

func _ready() -> void:
	health = max_health
	player = get_tree().get_first_node_in_group("player")
	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	# The shape is offset +9 in the scene, which makes left/right swings uneven.
	# Zero it so the Hitbox node's position alone controls the reach.
	hitbox_shape.position = Vector2.ZERO
	anim.play("idle")

func _physics_process(delta: float) -> void:
	cooldown_left = max(cooldown_left - delta, 0.0)

	# Staggered or dying: slide with the knockback, then fade it out
	if is_dead or is_hurt:
		knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		velocity = knockback
		move_and_slide()
		return

	if is_attacking or not is_instance_valid(player):
		velocity = Vector2.ZERO
		move_and_slide()
		return


	# Stop chasing a dead player
	if player.get("is_dead") == true:
		velocity = Vector2.ZERO
		move_and_slide()
		anim.play("idle")
		return

	var to_player := player.global_position - global_position
	var distance := to_player.length()

	# Face the player (assumes the art faces right)
	anim.flip_h = to_player.x < 0

	if distance <= attack_range and cooldown_left <= 0.0:
		start_attack()
	elif distance <= detect_range and distance > attack_range:
		velocity = to_player.normalized() * speed   # <-- was missing
		move_and_slide()
		anim.play("walk")
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		anim.play("idle")

func start_attack() -> void:
	is_attacking = true
	hit_bodies.clear()
	current_attack = ATTACKS["heavy"] if randf() < heavy_chance else ATTACKS["light"]
	anim.play(current_attack["anim"])

func get_blocked(from_position: Vector2) -> void:
	if is_dead:
		return
	end_attack()   # cancels the swing and disables the hitbox
	cooldown_left = BLOCKED_COOLDOWN
	knockback = (global_position - from_position).normalized() * BLOCKED_RECOIL
	is_hurt = true   # reuses the stagger state, so the knockback slide already works
	anim.stop()
	anim.play("hurt")

	# Yellow flash so a block reads differently from taking damage
	anim.modulate = Color(1.0, 0.9, 0.4)
	create_tween().tween_property(anim, "modulate", Color.WHITE, 0.25)




func _on_frame_changed() -> void:
	if not is_attacking:
		return
	if anim.animation == current_attack["anim"] and anim.frame == current_attack["hit_frame"]:
		var dir := -1.0 if anim.flip_h else 1.0
		hitbox.position.x = HITBOX_DISTANCE * dir
		hitbox_shape.set_deferred("disabled", false)

func _on_hitbox_body_entered(body: Node2D) -> void:
	if current_attack.is_empty():
		return
	if body == self or body in hit_bodies:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		hit_bodies.append(body)
		var blocked: bool = body.take_damage(current_attack["damage"], global_position, current_attack["knockback"])
		if blocked:
			get_blocked(body.global_position)

func end_attack() -> void:
	is_attacking = false
	current_attack = {}
	cooldown_left = attack_cooldown
	hitbox_shape.set_deferred("disabled", true)

func take_damage(amount: int, from_position: Vector2 = Vector2.ZERO, force: float = 0.0) -> void:
	if is_dead:
		return
	health -= amount

	if force > 0.0:
		knockback = (global_position - from_position).normalized() * force

	if health <= 0:
		die()
	else:
		play_hurt()

func play_hurt() -> void:
	if is_attacking:
		end_attack()   # getting hit interrupts the swing
	is_hurt = true
	anim.stop()
	anim.play("hurt")

func die() -> void:
	is_dead = true
	is_hurt = false
	if is_attacking:
		end_attack()
	velocity = Vector2.ZERO
	died.emit()
	body_shape.set_deferred("disabled", true)
	anim.play("death")

func _on_animation_finished() -> void:
	match anim.animation:
		"attack_light", "attack_heavy":
			if is_attacking:
				end_attack()
		"hurt":
			is_hurt = false
			anim.play("idle")
		"death":
			queue_free()
