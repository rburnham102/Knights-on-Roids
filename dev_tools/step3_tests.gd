extends SceneTree
# Step-3 tests: dodge steering, armored-orc guard, shield smash, skeleton archer.
#   godot --headless --fixed-fps 60 --path <project> -s res://step3_tests.gd

const KNIGHT := "res://Knight.tscn"
const ORC := "res://orc.tscn"
const ARMORED := "res://armored_orc.tscn"
const ARCHER := "res://skeleton_archer.tscn"
const ARROW := "res://aarow.tscn"

var passed := 0
var failed := 0

func check(label: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print(("  PASS  " if ok else "  FAIL  "), label, "  ", detail)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)

func new_arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a

func end_arena(a: Node) -> void:
	a.queue_free()
	Engine.time_scale = 1.0
	await frames(3)

func spawn(arena: Node, path: String, pos: Vector2, setup := Callable()) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.position = pos
	if setup.is_valid():
		setup.call(n)
	arena.add_child(n)
	return n

func arrows(arena: Node) -> Array:
	return arena.get_children().filter(func(c): return c is Area2D and "from_enemy" in c)

# A passive armored orc: no AI, only the behaviours a test switches on.
func calm(o: Node2D) -> void:
	o.guard_chance = 0.0
	o.special_chance = 0.0
	o.special_chance_vs_block = 0.0
	o.heavy_chance = 0.0

func _initialize() -> void:
	await run()
	Engine.time_scale = 1.0
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame
	await frames(2)
	var a: Node2D
	var knight: Node2D
	var o: Node2D

	# ================================================================ dodge steering
	print("[Dodge follows where you steer]")
	var dirs := {
		"right": ["move_right"], "left": ["move_left"], "up": ["move_up"], "down": ["move_down"],
		"up-right": ["move_up", "move_right"], "up-left": ["move_up", "move_left"],
		"down-right": ["move_down", "move_right"], "down-left": ["move_down", "move_left"]}
	var vec := {"move_right": Vector2.RIGHT, "move_left": Vector2.LEFT, "move_up": Vector2.UP, "move_down": Vector2.DOWN}
	var all_ok := true
	for dname in dirs:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		await frames(2)
		var want := Vector2.ZERO
		for act in dirs[dname]:
			Input.action_press(act)
			want += vec[act]
		await tap("dodge")
		var p0: Vector2 = knight.position
		await frames(10)
		var moved: Vector2 = knight.position - p0
		if moved.normalized().dot(want.normalized()) < 0.98:
			all_ok = false
		for act in dirs[dname]:
			Input.action_release(act)
		await end_arena(a)
	check("dodge goes the way you're steering in all 8 directions", all_ok)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("move_up")
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_up")
	Input.action_release("move_right")
	await frames(4)   # 0.07s after letting go
	var p1: Vector2 = knight.position
	await tap("dodge")
	await frames(10)
	var d1: Vector2 = knight.position - p1
	check("letting go just before Shift: dashes the diagonal you were going", d1.x > 20.0 and d1.y < -20.0, str(d1))
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("move_up")
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_up")
	Input.action_release("move_right")
	await frames(20)   # standing still for 0.33s
	p1 = knight.position
	await tap("dodge")
	await frames(10)
	d1 = knight.position - p1
	check("standing still: dashes the way you're facing (a straight, cardinal dash)", (abs(d1.x) < 3.0 or abs(d1.y) < 3.0) and d1.length() > 40.0, str(d1))
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("dodge")
	await physics_frame
	Input.action_press("move_left")   # direction arrives 1 frame AFTER Shift
	await frames(1)
	Input.action_release("dodge")
	p1 = knight.position
	await frames(12)
	Input.action_release("move_left")
	d1 = knight.position - p1
	check("direction pressed a frame after Shift still steers the dash", d1.x < -30.0, str(d1))
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	await tap("dodge")   # faces right, standing still
	await frames(5)
	Input.action_press("move_left")   # far too late to steer it
	p1 = knight.position
	await frames(8)
	Input.action_release("move_left")
	check("...but not once the dash is well under way", knight.position.x > p1.x - 1.0 or knight.dodge_velocity.x > 0.0, str(knight.position - p1))
	await end_arena(a)

	# ===================================================================== guard
	print("[Armored orc guard]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARMORED, Vector2(28, 0), func(x): x.guard_chance = 1.0; x.special_chance = 0.0; x.heavy_chance = 0.0)
	await frames(3)
	check("armored orc can guard, plain orc can't", o.can_guard and not load(ORC).instantiate().can_guard)
	knight.start_attack(knight.light_combo[0], false)
	await frames(3)
	check("raises its shield when the knight swings at it", o.state == o.State.GUARD)
	var hp0: int = o.health
	var poise0: float = o.poise
	o.take_damage(10, knight.global_position, 100.0, 10.0, 0)
	check("frontal hit: 10 damage -> 2", o.health == hp0 - 2, "%d -> %d" % [hp0, o.health])
	check("...poise damage cut to a quarter", is_equal_approx(o.poise, poise0 - 2.5), "%.1f" % o.poise)
	check("...no knockback and no stagger", o.knockback == Vector2.ZERO and o.state == o.State.GUARD)
	hp0 = o.health
	o.take_damage(10, o.global_position + Vector2(30, 0), 0.0, 0.0, 0)
	check("hit from BEHIND ignores the shield (full 10)", o.health == hp0 - 10, "%d -> %d" % [hp0, o.health])
	hp0 = o.health
	o.take_damage(25, knight.global_position, 250.0, 30.0, Combat.FLAG_GUARD_BREAK)
	check("a guard-breaking heavy hit does full damage", o.health == hp0 - 25, "%d -> %d" % [hp0, o.health])
	check("...and leaves the orc staggered for 1.2s", o.state == o.State.STAGGER and is_equal_approx(o.stagger_hold, 1.2))
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARMORED, Vector2(28, 0), func(x): x.guard_chance = 1.0; x.special_chance = 0.0; x.heavy_chance = 0.0)
	await frames(3)
	var flip0: bool = o.anim.flip_h
	knight.start_attack(knight.light_combo[0], false)
	await frames(3)
	knight.position = Vector2(60, 0)   # knight hops to the orc's other side
	await frames(5)
	check("facing is locked while the shield is up", o.state == o.State.GUARD and o.anim.flip_h == flip0)
	await frames(70)
	check("the shield comes down on its own", o.state != o.State.GUARD)
	check("...and it can't re-raise immediately (1s cooldown)", o.guard_cooldown_left > 0.0)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARMORED, Vector2(28, 0), func(x): x.guard_chance = 1.0; x.special_chance = 0.0; x.heavy_chance = 0.0)
	await frames(3)
	knight.start_attack(knight.heavy_attack, false)
	var broke := false
	for i in 60:
		await physics_frame
		if o.state == o.State.STAGGER and o.stagger_hold > 1.0:
			broke = true
	check("the knight's real heavy attack breaks a raised guard", broke)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ORC, Vector2(26, 0), func(x): x.heavy_chance = 0.0)
	await frames(3)
	var guarded := false
	knight.start_attack(knight.light_combo[0], false)
	for i in 30:
		await physics_frame
		if o.state == o.State.GUARD:
			guarded = true
	check("a plain orc never raises a shield", not guarded)
	await end_arena(a)

	# ================================================================== shield smash
	print("[Shield smash]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARMORED, Vector2(18, 0), func(x): x.special_chance = 1.0; x.guard_chance = 0.0; x.heavy_chance = 0.0)
	await frames(1)
	var windup := 0
	var tinted := false
	var saw_speed := false
	var radius := 0.0
	var offset := -1.0
	var hit_hp := 100
	for i in 200:
		await physics_frame
		if o.state == o.State.WINDUP:
			windup += 1
			if o.anim.modulate != Color.WHITE:
				tinted = true
		if o.state == o.State.ATTACK:
			if is_equal_approx(o.anim.speed_scale, 1.6):
				saw_speed = true
			if not o.hitbox_shape.disabled:
				radius = (o.hitbox_shape.shape as CircleShape2D).radius
				offset = o.hitbox.position.x
		if knight.health < 100 and hit_hp == 100:
			hit_hp = knight.health
		if o.state == o.State.FREE and radius > 0.0:
			break
	check("starts with the special: it was chosen", o.special_cooldown_left > 0.0)
	check("telegraph: ~0.35s purple wind-up", abs(windup - 21) <= 3 and tinted, "%d frames" % windup)
	check("the slow animation is sped up (x1.6) during the smash", saw_speed)
	check("...and restored afterwards", o.anim.speed_scale == 1.0)
	check("smash hitbox is a big circle centred on the orc (r26, offset 0)", is_equal_approx(radius, 26.0) and is_equal_approx(offset, 0.0), "r=%s off=%s" % [radius, offset])
	check("it hit the knight for its full damage", hit_hp == 100 - o.special_attack.damage, "hp %d" % hit_hp)
	await frames(5)
	check("the smash starts a 3s special cooldown (still running afterwards)", o.special_cooldown_left > 0.5 and o.special_cooldown_left < 3.0, "%.1fs left" % o.special_cooldown_left)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARMORED, Vector2(18, 0), func(x): x.special_chance = 0.0; x.special_chance_vs_block = 1.0; x.guard_chance = 0.0; x.heavy_chance = 0.0)
	await frames(2)
	Input.action_press("block")
	var result_seen := false
	for i in 220:
		await physics_frame
		if knight.guard_broken:
			result_seen = true
			break
	Input.action_release("block")
	check("turtling gets punished: the smash breaks a held guard", result_seen and knight.guard == 0.0)
	check("...and half the damage still lands", knight.health == 100 - ceili(o.special_attack.damage * 0.5), "hp %d" % knight.health)
	check("...leaving the knight HURT", knight.state == knight.State.HURT)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("block")
	await frames(3)
	var r1: Combat.HitResult = knight.take_damage(10, Vector2(30, 0), 0.0, 0.0, Combat.FLAG_UNPARRYABLE)
	check("an unparryable hit can't be parried, even on a perfectly timed block", r1 == Combat.HitResult.BLOCKED and is_equal_approx(knight.guard, 50.0), "guard %.0f" % knight.guard)
	Input.action_release("block")
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	await tap("dodge")
	await frames(3)
	var r2: Combat.HitResult = knight.take_damage(18, Vector2(30, 0), 0.0, 0.0, Combat.FLAG_UNPARRYABLE | Combat.FLAG_GUARD_BREAK)
	check("dodging it works (i-frames)", r2 == Combat.HitResult.DODGED and knight.health == 100)
	await end_arena(a)

	# ===================================================================== archer
	print("[Skeleton archer]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARCHER, Vector2(50, 0))
	await frames(2)
	check("archer: 30 HP, low poise (15), arrow shot", o.max_health == 30 and o.max_poise == 15.0 and o.light_attack.type == AttackData.Type.RANGED)
	var far := 0.0
	for i in 150:
		await physics_frame
		far = maxf(far, o.global_position.distance_to(knight.global_position))
	check("backs away when the knight is too close", far > 85.0, "reached %.0f px" % far)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARCHER, Vector2(130, 0))
	await frames(1)
	var start_frame := -1
	var shot_frame := -1
	var shot: Node2D = null
	for i in 150:
		await physics_frame
		if start_frame < 0 and o.state == o.State.WINDUP:
			start_frame = i
		var ar := arrows(a)
		if shot_frame < 0 and not ar.is_empty():
			shot_frame = i
			shot = ar[0]
			break
	check("archer telegraphs, then fires ~0.85s later", start_frame >= 0 and shot != null and abs((shot_frame - start_frame) - 51) <= 8, "%d frames" % (shot_frame - start_frame))
	if shot != null:
		check("arrow: enemy-owned, 10 damage, speed 240, flies at the knight",
			shot.from_enemy and shot.damage == 10 and is_equal_approx(shot.speed, 240.0) and shot.direction.x < -0.9, "dir %s" % str(shot.direction))
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARCHER, Vector2(130, 0))
	await frames(2)
	for i in 400:
		await physics_frame
		if knight.health < 100:
			break
	check("an unblocked arrow hits for 10", knight.health == 90, "hp %d" % knight.health)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARCHER, Vector2(130, 0))
	await frames(2)
	Input.action_press("block")   # held far too long to parry
	for i in 400:
		await physics_frame
		if knight.guard < 60.0:
			break
	Input.action_release("block")
	check("a held block just absorbs the arrow (guard -10, no health lost)", is_equal_approx(knight.guard, 50.0) and knight.health == 100, "guard %.0f" % knight.guard)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARCHER, Vector2(130, 0))
	await frames(2)
	var raised := false
	var deflected: Node2D = null
	for i in 500:
		await physics_frame
		for ar in arrows(a):
			if not raised and ar.from_enemy and ar.global_position.distance_to(knight.global_position) < 26.0:
				Input.action_press("block")   # ~0.1s before it arrives
				raised = true
			if raised and not ar.from_enemy:
				deflected = ar
		if deflected != null:
			break
	Input.action_release("block")
	check("a perfectly timed block deflects the arrow", deflected != null and deflected.direction.x > 0.9 and not deflected.from_enemy)
	check("...no damage, no guard lost, and no pointless riposte", knight.health == 100 and knight.guard == 60.0 and knight.state == knight.State.BLOCK)
	var archer_hp: int = o.health
	for i in 120:
		await physics_frame
		if o.health < archer_hp:
			break
	check("...and the deflected arrow hurts the archer (30 -> 20)", o.health == 20, "archer hp %d" % o.health)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARCHER, Vector2(130, 0))
	await frames(2)
	var dodged := false
	var passed_through := false
	for i in 500:
		await physics_frame
		for ar in arrows(a):
			if not dodged and ar.from_enemy and ar.global_position.distance_to(knight.global_position) < 34.0:
				await tap("dodge")   # no direction: dashes the way it faces
				dodged = true
			if dodged and ar.from_enemy and ar.global_position.x < knight.global_position.x - 20.0:
				passed_through = true
		if passed_through:
			break
	check("dodging an arrow: no damage and the arrow sails on", dodged and knight.health == 100)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARCHER, Vector2(300, 300))
	await frames(2)
	o.player = null
	o.take_damage(2, Vector2.ZERO, 0.0, 10.0)
	check("archer: a chip hit doesn't stagger it", o.state != o.State.STAGGER)
	o.take_damage(2, Vector2.ZERO, 0.0, 10.0)
	check("...a second one does (low poise)", o.state == o.State.STAGGER)
	await end_arena(a)


	print("[Block needs a fresh press after a hit or a dodge]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("block")
	await frames(20)
	knight.take_damage(18, Vector2(30, 0), 0.0, 0.0, Combat.FLAG_GUARD_BREAK | Combat.FLAG_UNPARRYABLE)
	await frames(60)
	knight.guard = 60.0
	knight.guard_broken = false
	await frames(10)
	check("key held through a hit: the guard does NOT come back up by itself", knight.state != knight.State.BLOCK, "state %d" % knight.state)
	Input.action_release("block")
	await frames(20)
	Input.action_press("block")
	await frames(3)
	check("...after letting go and pressing again, it does", knight.state == knight.State.BLOCK)
	Input.action_release("block")
	await frames(20)
	Input.action_press("block")
	await frames(20)
	await tap("dodge")
	await frames(30)
	check("key held through a dodge: no automatic re-block either", knight.state != knight.State.BLOCK)
	Input.action_release("block")
	await end_arena(a)

	print("[Armored orc counter-attacks when its shield drops]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	o = spawn(a, ARMORED, Vector2(24, 0), func(x): x.guard_chance = 1.0; x.special_chance = 0.0; x.heavy_chance = 0.0)
	await frames(3)
	knight.start_attack(knight.light_combo[0], false)
	var guard_ended := -1
	var swung := -1
	for i in 150:
		await physics_frame
		if guard_ended < 0 and o.state != o.State.GUARD and o.state != o.State.FREE:
			guard_ended = i
		if o.state == o.State.GUARD:
			continue
		if o.state == o.State.WINDUP or o.state == o.State.ATTACK:
			swung = i
			break
	check("when the shield drops, it starts an attack right away", swung >= 0 and swung < 90, "attack began on frame %d" % swung)
	await end_arena(a)

	print("[Flags]")
	var smash: AttackData = load("res://attacks/enemy/armored_smash.tres")
	var heavy: AttackData = load("res://attacks/attack_heavy.tres")
	var light: AttackData = load("res://attacks/attack_light.tres")
	check("smash: unparryable + guard-break", Combat.flags_of(smash) == (Combat.FLAG_UNPARRYABLE | Combat.FLAG_GUARD_BREAK))
	check("knight's heavy: guard-break only", Combat.flags_of(heavy) == Combat.FLAG_GUARD_BREAK)
	check("knight's light: no flags", Combat.flags_of(light) == 0)
