extends SceneTree
# Headless combat test. Run with:
#   godot --headless --fixed-fps 60 --path <project> -s res://combat_test.gd

const KNIGHT := "res://Knight.tscn"
const ENEMIES := {"orc": "res://orc.tscn", "armored_orc": "res://armored_orc.tscn"}
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

func new_arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a

func spawn(arena: Node, path: String, pos: Vector2) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.position = pos
	arena.add_child(n)
	return n

func settle() -> void:
	await frames(2)

func end_arena(a: Node) -> void:
	a.queue_free()
	await frames(3)

func _initialize() -> void:
	await run()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func run() -> void:
	await process_frame
	await frames(2)
	for key in ENEMIES:
		var path: String = ENEMIES[key]

		print("[%s] knight light attack -> enemy" % key)
		var a := new_arena()
		var knight := spawn(a, KNIGHT, Vector2.ZERO)
		var e := spawn(a, path, Vector2(24, 0))
		e.player = null   # freeze enemy AI
		await settle()
		var start_hp: int = e.health
		knight.start_attack(knight.light_combo[0], false)
		await frames(60)
		check("enemy took exactly one hit of 10", e.health == start_hp - 10, "hp %d -> %d" % [start_hp, e.health])
		await end_arena(a)

		print("[%s] enemy light attack -> knight" % key)
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		e = spawn(a, path, Vector2(20, 0))
		e.heavy_chance = 0.0
		e.special_chance = 0.0
		e.special_chance_vs_block = 0.0
		await frames(90)
		var dmg: int = e.light_attack.damage
		check("knight took exactly one hit (%d)" % dmg, knight.health == 100 - dmg, "knight hp %d" % knight.health)
		await end_arena(a)

		print("[%s] enemy attack vs blocking knight" % key)
		a = new_arena()
		knight = spawn(a, KNIGHT, Vector2.ZERO)
		e = spawn(a, path, Vector2(20, 0))
		e.heavy_chance = 0.0
		e.special_chance = 0.0
		e.special_chance_vs_block = 0.0
		Input.action_press("block")
		var staggered := false
		for i in 80:
			await physics_frame
			if e.state == e.State.STAGGER:
				staggered = true
		Input.action_release("block")
		check("knight took no health damage", knight.health == 100, "knight hp %d" % knight.health)
		check("guard absorbed the hit", is_equal_approx(knight.guard, knight.MAX_GUARD - e.light_attack.damage), "guard %.1f" % knight.guard)
		check("plain block does NOT stagger the attacker any more", not staggered)
		await end_arena(a)

		print("[%s] arrow -> enemy" % key)
		a = new_arena()
		e = spawn(a, path, Vector2(0, 0))
		e.player = null
		start_hp = e.health
		var arrow: Node2D = load(ARROW).instantiate()
		arrow.direction = Vector2.RIGHT
		arrow.damage = 15
		arrow.position = Vector2(-60, -6)
		a.add_child(arrow)
		await frames(60)
		check("enemy took arrow damage (15)", e.health == start_hp - 15, "hp %d -> %d" % [start_hp, e.health])
		check("arrow was consumed", not is_instance_valid(arrow))
		await end_arena(a)

		print("[%s] arrow passes through a dying enemy" % key)
		a = new_arena()
		e = spawn(a, path, Vector2(0, 0))
		e.player = null
		e.die()
		await frames(3)
		arrow = load(ARROW).instantiate()
		arrow.direction = Vector2.RIGHT
		arrow.position = Vector2(-30, -6)
		a.add_child(arrow)
		await frames(15)
		check("arrow still flying past the corpse", is_instance_valid(arrow) and arrow.position.x > 10.0)
		await end_arena(a)

	print("[stats]")
	var o: Node = load(ENEMIES["orc"]).instantiate()
	var ao: Node = load(ENEMIES["armored_orc"]).instantiate()
	print("  orc max_health=%d speed=%.0f | armored max_health=%d speed=%.0f" % [o.max_health, o.speed, ao.max_health, ao.speed])
	o.free()
	ao.free()
