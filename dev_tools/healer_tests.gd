extends SceneTree
# Healer tests: following, healing and its cooldown, the defensive burst,
# getting hurt and dying, and the perk in a real run (hire, peel, re-offer).
#   godot --headless --fixed-fps 60 --path <project> -s res://dev_tools/healer_tests.gd

const KNIGHT := "res://Knight.tscn"
const HEALER := "res://healer.tscn"
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

func seconds(s: float) -> void:
	await frames(roundi(s * 60.0))

func new_arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a

func end_arena(a: Node) -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "attack_light", "block"]:
		Input.action_release(action)
	a.queue_free()
	Engine.time_scale = 1.0
	await frames(3)

func spawn(arena: Node, path: String, pos: Vector2) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.position = pos
	arena.add_child(n)
	return n

func party(a: Node, at := Vector2(200, 100)) -> Array:
	var k := spawn(a, KNIGHT, at)
	var h: Healer = load(HEALER).instantiate()
	h.knight = k
	h.position = at + Vector2(-18, -3)
	a.add_child(h)
	return [k, h]

func _initialize() -> void:
	await frames(2)
	print("--- following")
	await test_follow()
	print("--- healing")
	await test_heal()
	print("--- holy burst")
	await test_burst()
	await test_burst_armored()
	print("--- hurt and death")
	await test_hurt_by_orc()
	await test_death()
	print("--- in a run")
	await test_run()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func test_follow() -> void:
	var a := new_arena()
	var p := await party(a)
	var k: Node2D = p[0]
	var h: Healer = p[1]
	await frames(3)
	Input.action_press("move_right")
	await seconds(1.5)
	Input.action_release("move_right")
	await seconds(1.0)
	var behind := h.global_position.x < k.global_position.x
	check("follows the knight", h.global_position.distance_to(k.global_position) < 30.0, "dist %.1f" % h.global_position.distance_to(k.global_position))
	check("...walking behind him (he faces right, she's on his left)", behind)
	Input.action_press("move_left")
	await seconds(1.0)
	Input.action_release("move_left")
	await seconds(1.0)
	check("switches sides when he turns around", h.global_position.x > k.global_position.x)
	await end_arena(a)

func test_heal() -> void:
	var a := new_arena()
	var p := await party(a)
	var k: Node2D = p[0]
	var h: Healer = p[1]
	await frames(3)
	k.health = 90
	await seconds(2.0)
	check("doesn't waste a heal when he's missing < 20", k.health == 90 and h.heal_cooldown_left == 0.0)
	k.health = 60
	var fx := []
	k.child_entered_tree.connect(func(n): fx.append(n.name))
	await seconds(2.0)
	check("heals 20 when he's hurt", k.health == 80, "health %d" % k.health)
	check("...and starts the 30 s cooldown", h.heal_cooldown_left > 27.0, "%.1f" % h.heal_cooldown_left)
	check("...with the heal effect on the knight", fx.any(func(n): return String(n).begins_with("HealEffect")), str(fx))
	check("...which cleans itself up", not k.get_children().any(func(c): return c.name.begins_with("HealEffect")))
	k.health = 40
	await seconds(25.0)
	check("no second heal inside 30 s", k.health == 40, "health %d" % k.health)
	await seconds(6.0)
	check("heals again once it recharges", k.health == 60, "health %d" % k.health)
	await end_arena(a)

func orc_on(a: Node, path: String, pos: Vector2, target: Node2D) -> Node2D:
	var o := spawn(a, path, pos)
	await frames(1)
	o.player = target
	return o

func test_burst() -> void:
	var a := new_arena()
	var p := await party(a)
	var h: Healer = p[1]
	var o := await orc_on(a, ORC, h.global_position + Vector2(14, 0), h)
	o.health = 200
	await frames(2)
	var start := o.global_position.distance_to(h.global_position)
	var hp_before: int = o.health
	var furthest := 0.0
	for i in 120:
		await physics_frame
		furthest = maxf(furthest, o.global_position.distance_to(h.global_position))
		if h.burst_cooldown_left > 0.0 and i > 40:
			break
	check("an orc swinging at her sets off the burst", h.burst_cooldown_left > 0.0)
	check("burst does little damage", hp_before - o.health <= 5, "%d dmg" % (hp_before - o.health))
	check("...but throws the orc well away", furthest - start > 25.0, "pushed %.0f px" % (furthest - start))
	await end_arena(a)

func test_burst_armored() -> void:
	var a := new_arena()
	var p := await party(a)
	var h: Healer = p[1]
	var o := await orc_on(a, ARMORED, h.global_position + Vector2(14, 0), h)
	await frames(2)
	var start := o.global_position.distance_to(h.global_position)
	h.change_state(Healer.State.ATTACK)
	var furthest := 0.0
	for i in 60:
		await physics_frame
		furthest = maxf(furthest, o.global_position.distance_to(h.global_position))
	check("even an armored orc gets pushed (poise can't hold it)", furthest - start > 20.0, "pushed %.0f px" % (furthest - start))
	check("burst is on cooldown afterwards", h.burst_cooldown_left > 1.5)
	await end_arena(a)

func test_hurt_by_orc() -> void:
	var a := new_arena()
	var p := await party(a)
	var h: Healer = p[1]
	h.burst_cooldown_left = 999.0   # can't defend: let the orc land a hit
	var o := await orc_on(a, ORC, h.global_position + Vector2(16, 0), h)
	for i in 300:
		await physics_frame
		if h.health < h.max_health:
			break
	check("an orc swing hurts her (allies group)", h.health < h.max_health, "health %d" % h.health)
	check("health bar shows it", h.health_bar.value == h.health)
	await end_arena(a)

func test_death() -> void:
	var a := new_arena()
	var p := await party(a)
	var h: Healer = p[1]
	var got := []
	h.died.connect(func(): got.append(1))
	await frames(2)
	h.take_damage(100)
	check("dies at 0 health and says so once", h.is_dead and got.size() == 1)
	check("health bar hidden when dead", not h.health_bar.visible)
	h.take_damage(5)
	check("no second death", got.size() == 1)
	await seconds(2.0)
	check("fades out and frees herself", not is_instance_valid(h))
	await end_arena(a)

func test_run() -> void:
	var scene: Node2D = load("res://run.tscn").instantiate()
	scene.get_node("RunManager").start_seed = 4242
	scene.get_node("RunManager").dev_screen_enabled = false   # no dev screen: start right away
	scene.get_node("RunManager").character_select_enabled = false   # plays the first class, the Knight
	root.add_child(scene)
	current_scene = scene
	var mgr: Node = scene.get_node("RunManager")
	var k: Node2D = scene.get_node("Actors/Knight")
	await frames(40)
	check("healer card is in the upgrade pool", mgr.HEALER_UPGRADE in mgr.pool)
	mgr._on_upgrade_chosen(mgr.HEALER_UPGRADE)
	await frames(5)
	check("picking it hires her", mgr.healer != null and is_instance_valid(mgr.healer))
	check("...and takes the card out of the pool", not mgr.HEALER_UPGRADE in mgr.pool)
	var h: Healer = mgr.healer

	# Walk through a few rooms counting who the enemies are after.
	var peeled := 0
	var total := 0
	for room in 4:
		mgr._on_exit_entered()
		await frames(90)
		check("room %d: she came along and stands by the knight" % mgr.run.depth, is_instance_valid(h) and h.global_position.distance_to(k.global_position) < 30.0)
		for e in get_nodes_in_group("enemies"):
			total += 1
			if e.player == h:
				peeled += 1
	print("        %d of %d enemies went after her (%.0f%%)" % [peeled, total, 100.0 * peeled / maxi(total, 1)])
	check("some enemies peel off to her, most stay on the knight", peeled > 0 and peeled < total * 0.4)

	h.take_damage(999)
	await frames(2)
	var still_on_her := get_nodes_in_group("enemies").filter(func(e): return e.player == h).size()
	check("when she dies, enemies turn back to the knight", still_on_her == 0)
	check("the perk is gone", not mgr.run.perks.has(&"healer") and mgr.healer == null)
	check("she can be offered again", mgr.HEALER_UPGRADE in mgr.pool)
	scene.queue_free()
	await frames(3)
