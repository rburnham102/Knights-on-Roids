extends SceneTree
# Step-2 tests: telegraph, active window, poise, parry + riposte, anti-mash,
# dodge, hit-stop, reach.
#   godot --headless --fixed-fps 60 --path <project> -s res://step2_tests.gd

const KNIGHT := "res://Knight.tscn"
const ORC := "res://orc.tscn"
const ARMORED := "res://armored_orc.tscn"

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
	var orc: Node2D

	# --------------------------------------------------------- reach (the fix)
	print("[Knight swing reach, including point blank]")
	var reach := {}
	for dx in [8, 12, 20, 30, 38, 48]:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		orc = spawn(a, ORC, Vector2(dx, 0))
		orc.player = null
		await frames(2)
		orc.health = 500
		orc.position.x = dx
		knight.start_attack(knight.light_combo[0], false)   # no lunge
		await frames(60)
		reach[dx] = orc.health < 500
		await end_arena(a)
	check("a light swing hits an enemy at 8, 12, 20, 30 and 38 px",
		reach[8] and reach[12] and reach[20] and reach[30] and reach[38], str(reach))
	check("...but not one 48 px away", not reach[48])

	# --------------------------------------------------------------- telegraph
	print("[Telegraph: the enemy winds up before it swings]")
	for heavy in [false, true]:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		orc = spawn(a, ORC, Vector2(20, 0), func(o): o.heavy_chance = 1.0 if heavy else 0.0)
		await frames(1)
		var windup_frames := 0
		var tinted := false
		var hp_during_windup: int = knight.health
		for i in 120:
			await physics_frame
			if orc.state == orc.State.WINDUP:
				windup_frames += 1
				if orc.anim.modulate != Color.WHITE:
					tinted = true
				hp_during_windup = knight.health
			if orc.state == orc.State.ATTACK:
				break
		var want := (0.40 if heavy else 0.22) * 60.0
		var label := "heavy" if heavy else "light"
		check("%s: wind-up lasts ~%.2fs" % [label, want / 60.0], abs(windup_frames - want) <= 3, "%d frames" % windup_frames)
		check("%s: the sprite flashes the warning colour" % label, tinted)
		check("%s: no damage dealt during the wind-up" % label, hp_during_windup == 100)
		await frames(3)
		check("%s: tint is cleared once the swing starts" % label, orc.state == orc.State.ATTACK and orc.anim.modulate == Color.WHITE)
		await end_arena(a)

	# --------------------------------------------------------- active window
	print("[Enemy hitbox is only live for a short window]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	orc = spawn(a, ORC, Vector2(60, 0), func(o): o.heavy_chance = 0.0)   # far away: it just walks up
	await frames(2)
	orc.player = knight
	var on_frames := 0
	var seen_on := false
	for i in 200:
		await physics_frame
		if orc.state == orc.State.ATTACK and not orc.hitbox_shape.disabled:
			on_frames += 1
			seen_on = true
		if seen_on and orc.state != orc.State.ATTACK:
			break
	check("light swing hitbox is on for ~2 animation frames (0.25s), not the whole swing",
		on_frames >= 11 and on_frames <= 18, "%d physics frames" % on_frames)
	await end_arena(a)

	# -------------------------------------------------------------------- poise
	print("[Poise]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	orc = spawn(a, ORC, Vector2(24, 0))
	orc.player = null
	await frames(2)
	check("orc starts with full poise (50)", orc.poise == 50.0 and orc.max_poise == 50.0)
	orc.take_damage(10, Vector2.ZERO, 100.0, 10.0)
	check("a chip hit damages but doesn't stagger", orc.health == 40 and orc.state == orc.State.FREE and orc.poise == 40.0)
	check("...and applies no knockback", orc.knockback == Vector2.ZERO)
	orc.take_damage(10, Vector2(-30, 0), 100.0, orc.poise)   # exactly enough poise damage to break it
	check("poise running out staggers it", orc.state == orc.State.STAGGER, "poise %.0f" % orc.poise)
	check("...and refills the poise bar", orc.poise == 50.0)
	check("...with knockback away from the attacker", orc.knockback.x > 0.0)
	var hurt_frame_before: int = orc.anim.frame
	await frames(10)
	orc.take_damage(1, Vector2(-30, 0), 0.0, 10.0)
	check("hits while staggered don't restart the stun", orc.anim.frame >= hurt_frame_before and orc.anim.frame > 0)
	await end_arena(a)

	a = new_arena()
	orc = spawn(a, ORC, Vector2(24, 0))
	orc.player = null
	await frames(2)
	orc.take_damage(10, Vector2.ZERO, 0.0, 10.0)
	await frames(60 * 2 + 5)   # 2s delay
	var poise_after_delay: float = orc.poise
	await frames(60)           # +1s of regen at 8/s
	check("poise doesn't regen for 2s after a hit, then recovers ~8/s",
		poise_after_delay < 41.5 and orc.poise > 46.0 and orc.poise < 49.5, "%.1f then %.1f" % [poise_after_delay, orc.poise])
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	orc = spawn(a, ORC, Vector2(24, 0), func(o): o.heavy_chance = 0.0)
	await frames(2)
	orc.player = knight
	while orc.state != orc.State.WINDUP:
		await physics_frame
	orc.take_damage(5, Vector2(-30, 0), 0.0, 10.0)   # chip: poise 50 -> 40
	check("a chip hit doesn't cancel the wind-up", orc.state == orc.State.WINDUP)
	orc.take_damage(5, Vector2(-30, 0), 0.0, orc.poise)   # break
	check("breaking poise cancels the wind-up", orc.state == orc.State.STAGGER and orc.current_attack == null)
	check("...and the enemy is put on cooldown", orc.cooldown_left > 0.3)
	await end_arena(a)

	a = new_arena()
	armored = spawn(a, ARMORED, Vector2(24, 0))
	await frames(2)
	check("armored orc has 130 poise (much tougher than the orc)", armored.max_poise == 130.0)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.power = 20)
	await frames(2)
	knight.start_attack(knight.heavy_attack, false)
	check("power 20: heavy poise damage 30 -> 45", is_equal_approx(knight.attack_poise_damage(), 45.0), str(knight.attack_poise_damage()))
	await end_arena(a)

	# --------------------------------------------------------- parry / block
	print("[Parry vs plain block, decided by block timing]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	check("riposte slot is attack_light2", knight.riposte_attack != null and knight.riposte_attack.anim == &"attack_light2")
	Input.action_press("block")
	await frames(3)
	var hp: int = knight.health
	var gd: float = knight.guard
	var res: Combat.HitResult = knight.take_damage(20, Vector2(-30, 0), 250.0, 0.0)
	Input.action_release("block")
	check("block raised just before impact -> PARRIED", res == Combat.HitResult.PARRIED)
	check("parry costs no health and no guard", knight.health == hp and knight.guard == gd)
	check("parry starts no guard-regen delay", knight.guard_regen_delay_left == 0.0)
	check("parry doesn't push the knight", knight.knockback == Vector2.ZERO)
	check("knight riposte: ATTACK state swinging attack_light2", knight.state == knight.State.ATTACK and knight.current_attack == knight.riposte_attack)
	check("riposte turns the knight toward the attacker (left)", knight.last_direction == "left" and knight.pivot.scale.x == -1.0)
	check("riposte primes the chain: next light press is the heavy finisher", knight.combo_index == 2)
	check("hit-stop engaged on the parry", Engine.time_scale < 1.0, str(Engine.time_scale))
	await frames(20)
	check("hit-stop ends again by itself", is_equal_approx(Engine.time_scale, 1.0), str(Engine.time_scale))
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("block")
	await frames(20)
	res = knight.take_damage(8, Vector2(30, 0), 100.0, 0.0)
	Input.action_release("block")
	check("block held too long -> plain BLOCKED", res == Combat.HitResult.BLOCKED)
	check("plain block costs guard (8) and no health", is_equal_approx(knight.guard, 52.0) and knight.health == 100)
	check("plain block stays in BLOCK, no riposte", knight.state == knight.State.BLOCK)
	await end_arena(a)

	var results := {}
	for dex in [10, 20]:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.dexterity = dex)
		await frames(2)
		Input.action_press("block")
		await frames(3)
		knight.block_time = 0.20   # raised 0.2s before impact
		results[dex] = knight.take_damage(8, Vector2(30, 0), 0.0, 0.0)
		Input.action_release("block")
		await end_arena(a)
	check("0.2s early is too early at dexterity 10 but a parry at dexterity 20 (0.15s -> 0.225s window)",
		results[10] == Combat.HitResult.BLOCKED and results[20] == Combat.HitResult.PARRIED)

	print("[Anti-mash: block can't be re-raised instantly]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("block")
	await frames(10)
	Input.action_release("block")
	await frames(2)
	Input.action_press("block")
	await frames(3)
	check("pressing block again right after lowering it does nothing yet", knight.state != knight.State.BLOCK)
	await frames(20)
	check("...but after the 0.3s delay it goes up", knight.state == knight.State.BLOCK)
	Input.action_release("block")
	await end_arena(a)

	print("[Parry with a real orc: counter, stagger, chain]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	orc = spawn(a, ORC, Vector2(22, 0), func(o): o.heavy_chance = 0.0)
	await frames(2)
	orc.health = 200
	var raised := false
	for i in 200:
		await physics_frame
		# raise the block one animation frame before the light swing lands
		if not raised and orc.state == orc.State.ATTACK and orc.anim.frame == orc.current_attack.hit_frame - 1:
			Input.action_press("block")
			raised = true
		if raised and knight.state == knight.State.ATTACK:
			break
	Input.action_release("block")
	check("the knight parried the orc's swing", knight.state == knight.State.ATTACK and knight.health == 100 and knight.guard == 60.0,
		"state %d hp %d guard %.0f" % [knight.state, knight.health, knight.guard])
	check("the orc is staggered and held open", orc.state == orc.State.STAGGER and orc.stagger_hold > 1.0, "hold %.2f" % orc.stagger_hold)
	var hp_before: int = orc.health
	await frames(40)   # riposte lands
	check("the riposte landed (attack_light2 = 12 damage)", orc.health == hp_before - 12, "%d -> %d" % [hp_before, orc.health])
	check("the orc is still helpless after being hit", orc.state == orc.State.STAGGER)
	await frames(2)
	await tap("attack_light")   # finisher in the combo window
	await frames(70)
	check("pressing light after the riposte lands the heavy (25) too", orc.health == hp_before - 12 - 25, "%d -> %d" % [hp_before, orc.health])
	await frames(60)
	check("the orc recovers ~1.5s after the parry", orc.state != orc.State.STAGGER)
	await end_arena(a)

	print("[Plain block leaves the attacker standing]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	orc = spawn(a, ORC, Vector2(22, 0), func(o): o.heavy_chance = 0.0)
	Input.action_press("block")
	await frames(2)
	var was_staggered := false
	for i in 90:
		await physics_frame
		if orc.state == orc.State.STAGGER:
			was_staggered = true
	Input.action_release("block")
	check("blocked swing: orc never staggers, knight guard 60 -> 50", not was_staggered and is_equal_approx(knight.guard, 50.0), "guard %.0f" % knight.guard)
	await end_arena(a)

	# -------------------------------------------------------------------- dodge
	print("[Dodge]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("move_right")
	await frames(2)
	await tap("dodge")
	check("dodge key -> DODGE state", knight.state == knight.State.DODGE)
	check("no 'dodge' animation yet -> falls back to a fast walk", knight.anim.animation == &"walk" and is_equal_approx(knight.anim.speed_scale, 2.0))
	check("sprite fades while invulnerable", knight.anim.modulate.a < 0.6)
	check("slips through enemies (off the player layer, sees only walls)", knight.collision_layer == 0 and knight.collision_mask == 1)
	var x0: float = knight.position.x
	await frames(35)
	Input.action_release("move_right")
	check("state returns to FREE and speed/colour/mask are restored",
		knight.state == knight.State.FREE and knight.anim.speed_scale == 1.0 and knight.anim.modulate.a == 1.0 and knight.collision_mask == 7 and knight.collision_layer == 2)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	Input.action_press("move_right")
	await frames(2)
	var start_x: float = knight.position.x
	await tap("dodge")
	await frames(20)   # dodge (15 frames) + a little walking
	var travelled: float = knight.position.x - start_x
	Input.action_release("move_right")
	# 60 px dash + ~2 frames of walking before and a few after the dash
	check("a dash covers ~60 px (plus a bit of walking)", travelled > 58.0 and travelled < 75.0, "%.1f px" % travelled)
	await end_arena(a)

	var dd := {}
	for dex in [10, 20]:
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO, func(k): k.stats = Stats.new(); k.stats.dexterity = dex)
		await frames(2)
		Input.action_press("move_right")
		await tap("dodge")
		await frames(14)
		dd[dex] = knight.position.x
		Input.action_release("move_right")
		await end_arena(a)
	check("dexterity 20 dashes ~1.5x as far as dexterity 10", dd[20] / dd[10] > 1.35 and dd[20] / dd[10] < 1.6, "%.1f vs %.1f px" % [dd[20], dd[10]])

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	await tap("dodge")
	await frames(3)
	hp = knight.health
	var early: Combat.HitResult = knight.take_damage(10, Vector2(30, 0), 100.0, 0.0)
	check("hit during the invulnerable frames -> DODGED, no damage", early == Combat.HitResult.DODGED and knight.health == hp)
	check("...and no stagger", knight.state == knight.State.DODGE)
	await frames(10)   # now ~0.2s in: past the 0.18s of i-frames
	var late: Combat.HitResult = knight.take_damage(10, Vector2(30, 0), 0.0, 0.0)
	check("hit after the invulnerable frames -> damage lands", late == Combat.HitResult.HIT and knight.health == hp - 10)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	await tap("dodge")
	await frames(20)
	await tap("dodge")
	check("dodge cooldown: a second dodge 0.4s later is refused", knight.state != knight.State.DODGE)
	await frames(30)
	await tap("dodge")
	check("...and works after 0.7s", knight.state == knight.State.DODGE)
	await end_arena(a)

	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	await tap("attack_light")
	await tap("dodge")
	check("can't dodge out of an attack (v1)", knight.state == knight.State.ATTACK)
	await frames(80)
	Input.action_press("block")
	await frames(20)
	await tap("dodge")
	check("can dodge out of a block", knight.state == knight.State.DODGE)
	Input.action_release("block")
	await end_arena(a)

	print("[Dodge through an enemy]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	orc = spawn(a, ORC, Vector2(25, 0))
	orc.player = null
	await frames(2)
	Input.action_press("move_right")
	await tap("dodge")
	await frames(20)
	Input.action_release("move_right")
	check("knight ends up on the far side of the orc", knight.position.x > orc.position.x + 4.0, "knight %.1f orc %.1f" % [knight.position.x, orc.position.x])
	check("...without shoving the orc along (it moved < 8 px)", abs(orc.position.x - 25.0) < 8.0, "orc at %.1f" % orc.position.x)
	await end_arena(a)

	print("[Dodge animation hook]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	await frames(2)
	var sf: SpriteFrames = knight.anim.sprite_frames
	sf.add_animation(&"dodge")
	sf.set_animation_speed(&"dodge", 8.0)
	sf.set_animation_loop(&"dodge", false)
	for i in 8:
		sf.add_frame(&"dodge", sf.get_frame_texture(&"idle", 0))
	await tap("dodge")
	check("a 'dodge' animation is used when it exists", knight.anim.animation == &"dodge")
	check("...and its speed is fitted to the dash (8 frames @ 8fps = 1s -> x4 for 0.25s)", is_equal_approx(knight.anim.speed_scale, 4.0), str(knight.anim.speed_scale))
	sf.remove_animation(&"dodge")
	await end_arena(a)

	# ------------------------------------------------------------------ hit-stop
	print("[Hit-stop on a heavy hit]")
	a = new_arena()
	knight = spawn(a, KNIGHT, Vector2.ZERO)
	orc = spawn(a, ORC, Vector2(24, 0))
	orc.player = null
	await frames(2)
	orc.health = 500
	knight.start_attack(knight.heavy_attack, false)
	var froze := false
	for i in 120:
		await physics_frame
		if Engine.time_scale < 1.0:
			froze = true
	check("heavy hit freezes the game briefly, then restores it", froze and is_equal_approx(Engine.time_scale, 1.0))
	await end_arena(a)

var armored: Node2D
