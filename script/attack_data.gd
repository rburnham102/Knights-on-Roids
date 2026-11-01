class_name AttackData
extends Resource
## One attack, as data. Save one of these as a .tres file per attack and drop
## it into a slot on the character. A new weapon is a new set of .tres files,
## not new code.

enum Type { MELEE, RANGED }

## Name of the animation (in the character's SpriteFrames) that plays.
@export var anim: StringName
@export var type: Type = Type.MELEE
@export var damage := 10
## Animation frame on which the hit happens (hitbox turns on / arrow fires).
@export var hit_frame := 2
@export var knockback := 120.0
## Camera shake when this attack connects.
@export var shake := 0.0
## Forward lunge speed at the start of the swing (0 = none).
@export var lunge := 0.0
## Enemies only: seconds the attacker stands still and flashes before the
## swing animation starts (the telegraph). 0 = swing immediately.
@export var windup_time := 0.0
## How many animation frames the hitbox stays on after the hit frame.
## 0 = until the animation ends.
@export var active_frames := 0
## How much of the target's poise this attack removes.
@export var poise_damage := 0.0
## Freeze-frame length (seconds) when this attack connects. 0 = none.
@export var hit_stop := 0.0
## Colour the attacker flashes during its wind-up.
@export var telegraph_color := Color(1.0, 0.85, 0.3)
## Can a perfectly timed block catch this? (false for things like the shield smash)
@export var parryable := true
## Shatters the target's guard instead of being absorbed by it.
@export var guard_break := false
## Enemies only: size and placement of the damage area for melee attacks.
## offset = how far in front of the attacker the circle sits (0 = centred on it).
@export var hitbox_radius := 10.0
@export var hitbox_offset := 8.0
## Enemies only: plays the swing animation faster/slower (1.0 = as drawn).
@export var anim_speed := 1.0
## Ranged attacks: how fast the projectile flies (pixels per second).
@export var projectile_speed := 400.0
## Ranged attacks (enemies): how far the projectile flies before vanishing (pixels).
@export var projectile_range := 1200.0
