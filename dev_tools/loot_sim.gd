extends SceneTree
# Loot economy simulation: how much healing and how many stat points drops
# add to a run. Builds real levels (chunks + EnemyDirector) for many seeds and
# assumes the player kills everything and smashes every barrel (the most loot
# a run can give). No combat - for fights, see run_sim.gd.
#   godot --headless --path . -s res://dev_tools/loot_sim.gd -- runs=300 orc=0.08 archer=0.15 armored=0.4 barrel=0.15

const LEVEL := preload("res://rooms/level.tscn")

func _initialize() -> void:
	await process_frame   # the tree isn't running yet: @onready vars would be null
	var runs := 300
	var ov := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			runs = int(arg.get_slice("=", 1))
		elif arg.contains("="):
			ov[arg.get_slice("=", 0)] = float(arg.get_slice("=", 1))
	var mgr: Node = load("res://run.tscn").instantiate()
	var templates: Array[PackedScene] = mgr.get_node("RunManager").CHUNKS
	var heal_after_room: float = mgr.get_node("RunManager").heal_after_room
	mgr.free()

	# Drop chances straight from the scenes, unless overridden.
	var chance := {}
	for entry in EnemyDirector.ENTRIES:
		var e: Node = entry.scene.instantiate()
		var key: String = {"orc": "orc", "skeleton_archer": "archer", "armored_orc": "armored"}[entry.scene.resource_path.get_file().get_basename()]
		chance[entry.scene] = ov.get(key, e.drop_chance)
		e.free()
	var b: Node = load("res://breakable.tscn").instantiate()
	var barrel_chance: float = ov.get("barrel", b.drop_chance)
	b.free()

	var depth_heal := []
	var depth_enemies := []
	var depth_drops := []
	var depth_barrels := []
	for d in RunState.RUN_LENGTH:
		depth_heal.append(0.0); depth_enemies.append(0.0); depth_drops.append(0.0); depth_barrels.append(0.0)
	var tomes_per_run := []
	for r in runs:
		var run := RunState.new(5000 + r)
		var tomes := 0
		for depth in range(1, RunState.RUN_LENGTH + 1):
			var level: Level = LEVEL.instantiate()
			root.add_child(level)
			level.build(templates, run.rng)
			var barrels := level.find_children("*", "StaticBody2D", true, false).filter(func(n): return n is Breakable).size()
			var sources: Array[float] = []
			for points in level.spawn_groups():
				for scene in EnemyDirector.plan(depth, points.size(), run.rng):
					sources.append(chance[scene])
			depth_enemies[depth - 1] += sources.size()
			depth_barrels[depth - 1] += barrels
			for i in barrels:
				sources.append(barrel_chance)
			for c in sources:
				var item := Loot.roll(c, run.loot_rng)
				if item:
					depth_drops[depth - 1] += 1
					depth_heal[depth - 1] += item.heal
					tomes += item.power + item.dexterity + item.vitality
			level.free()
			# the upgrade roll uses run.rng too, like a real run
			run.roll_upgrades([], 3)
		tomes_per_run.append(tomes)

	print("drop chances: orc %.2f archer %.2f armored %.2f barrel %.2f   (%d runs)" % [ov.get("orc", chance.values()[0]), ov.get("archer", chance.values()[1]), ov.get("armored", chance.values()[2]), barrel_chance, runs])
	print("room  enemies  barrels  drops  heal from drops  (room-clear heal: %d)" % roundi(100 * heal_after_room))
	var total_heal := 0.0
	for d in RunState.RUN_LENGTH:
		total_heal += depth_heal[d]
		print("%4d  %7.1f  %7.1f  %5.2f  %15.1f" % [d + 1, depth_enemies[d] / runs, depth_barrels[d] / runs, depth_drops[d] / runs, depth_heal[d] / runs])
	tomes_per_run.sort()
	var avg: float = tomes_per_run.reduce(func(s, n): return s + n) / float(runs)
	var zero := tomes_per_run.count(0)
	print("per run: heal %.0f HP (vs %d from room clears), tomes avg %.2f, none %d%%, 3+ %d%%" % [total_heal / runs, roundi(100 * heal_after_room) * RunState.RUN_LENGTH, avg, 100 * zero / runs, 100 * tomes_per_run.filter(func(t): return t >= 3).size() / runs])
	quit()
