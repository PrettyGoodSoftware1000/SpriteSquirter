extends Node
## Headless smoke test for the game modes. It plays through the main
## systems without a mouse and fails loudly if something is off:
##   godot --headless --path . res://tools/smoke_test.tscn
## It saves a map called "Smoke test" in user://maps/ and deletes it after.

const MAIN := "res://scenes/main.tscn"
const TEST_MAP := "Smoke test"

var _failures: PackedStringArray = []


func _ready() -> void:
	# Live outside the current scene so changing scenes does not free the test.
	var tree := get_tree()
	get_parent().remove_child.call_deferred(self)
	tree.root.add_child.call_deferred(self)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var game := Game
	Engine.time_scale = 8.0
	game.settings.birth_seconds = 5.0

	# 1. The menu.
	await _open(game, "menu", "", 384)
	_check(get_tree().current_scene.get_node("Controller") is MainMenu, "menu controller")

	# 2. A random medium island: found a village, gather, build, be born.
	await _open(game, "play", "", 384)
	var play := get_tree().current_scene.get_node("Controller") as PlayMode
	_check(play != null, "play controller")
	_check(is_equal_approx(Terrain.ISLAND_RADIUS, 174.0), "medium map: 1.5x the old island radius")
	var starts: PackedVector2Array = play._info.starts
	_check(starts.size() >= 2, "random island has start locations (%d)" % starts.size())
	_check(get_tree().get_nodes_in_group("people").is_empty(), "no people before choosing a start")
	var start: Vector3 = Vector3(starts[0].x, game.terrain.get_height(starts[0].x, starts[0].y), starts[0].y)
	play._found(start, 0)
	var village := play.village
	var first_people := village.population()
	_check(first_people > 5, "village site villagers join the player (%d)" % first_people)
	_check(not get_tree().get_nodes_in_group("player_buildings").is_empty(), "village site buildings join the player")
	var before: Dictionary = village.resources.duplicate()
	_check(not get_tree().get_nodes_in_group("rocks").is_empty(), "boulder fields placed (%d boulders)" % get_tree().get_nodes_in_group("rocks").size())
	_check(is_equal_approx(1.0 - DayCycle.NIGHT_START, DayCycle.NIGHT_START * 0.5), "night is half as long as day")
	# A wheat field: sown by the villagers, then it grows by itself.
	var field := CropField.new()
	field.setup(Vector2(8, 8))
	field.position = village.center + Vector3(0, 0, 14)
	game.world_root.add_child(field)
	await _wait(120.0)
	_check(field.stage != CropField.Stage.SOWING or field.progress > 0.3, "villagers sow the field (stage %d, %.2f)" % [field.stage, field.progress])
	var jobs := {}
	for v in village.people():
		jobs[v.job] = jobs.get(v.job, 0) + 1
	print("  jobs %s" % jobs)
	for res in ["lumber", "stone", "food", "magicko"]:
		_check(village.resources[res] > before[res], "%s is gathered (%.1f -> %.1f)" % [res, before[res], village.resources[res]])
	_check(village.population() > first_people or village.population() >= village.housing(), "a child is born")

	var spot := _free_spot(play, village.center)
	_check(spot != Vector3.INF, "found a free building spot")
	if spot != Vector3.INF:
		var site := ConstructionSite.new()
		site.setup("tall_house", 1234, {})
		game.world_root.add_child(site)
		site.global_position = spot
		var built := [false]
		site.completed.connect(func(_b: Destructible) -> void: built[0] = true)
		var adults := village.adults()
		var expected := ConstructionSite.VILLAGER_SECONDS / maxf(adults, 1.0)
		await _wait(minf(expected * 2.5 + 20.0, 240.0))
		_check(built[0], "the villagers finish a building (%d adults, ~%d s expected)" % [adults, int(expected)])

	# Warriors: the player asks for them; a Town guard trains one a minute.
	_check(village.max_count("warrior") == 0, "no warriors without a Town guard")
	var tower := BuildingFactory.create("moon_tower", RandomNumberGenerator.new())
	game.world_root.add_child(tower)
	tower.global_position = village.center + Vector3(10, 0, -10)
	tower.add_to_group("player_buildings")
	village.set_wanted("warrior", 9)
	_check(village.wanted.warrior == PlayerVillage.WARRIORS_PER_GUARD, "a Town guard allows 4 warriors (%d)" % village.wanted.warrior)
	village.set_wanted("warrior", 2)
	await _wait(PlayerVillage.WARRIOR_SECONDS * 0.5)
	_check(village.soldiers() == 0 and village.training_progress("warrior").size() == 1, "one warrior trains at a time, and takes a minute")
	await _wait(PlayerVillage.WARRIOR_SECONDS * 0.5 + 35.0)
	var soldiers := get_tree().get_nodes_in_group("soldiers")
	_check(soldiers.size() == 1, "the first warrior is trained (%d)" % soldiers.size())
	if not soldiers.is_empty():
		var s := soldiers[0] as Villager
		_check(is_equal_approx(s.max_hp, Villager.HEALTH * 4.0) and is_equal_approx(s.damage, Villager.ATTACK_DAMAGE * 2.0), "soldiers have 4x health and 2x damage")
	var eating := village.food_upkeep()
	_check(eating >= village.population() + 2.0, "a warrior eats 3 food a minute (village eats %.0f/min)" % eating)
	village.set_wanted("warrior", 0)
	await _wait(1.0)
	_check(village.soldiers() == 0 and village.training_progress("warrior").is_empty(), "warriors go back to work when no longer wanted")

	# Wizards: Singing rocks train one every 3 minutes; they make magicko.
	var rocks := BuildingFactory.create("singing_rocks", RandomNumberGenerator.new())
	game.world_root.add_child(rocks)
	rocks.global_position = village.center + Vector3(-12, 0, 10)
	rocks.add_to_group("player_buildings")
	village.set_wanted("wizard", 5)
	_check(village.wanted.wizard == PlayerVillage.WIZARDS_PER_ROCKS, "Singing rocks allow 2 wizards")
	village.set_wanted("wizard", 1)
	# Training pauses while the recruit fights or flees, so allow for a raid.
	for k in 30:
		await _wait(15.0)
		if village.wizards() > 0:
			break
	var wizards := get_tree().get_nodes_in_group("wizards")
	_check(wizards.size() == 1, "a wizard is trained (%d)" % wizards.size())
	_check(Villager.FIREBOLT_DAMAGE / Villager.FIREBOLT_SECONDS > Villager.ATTACK_DAMAGE * Villager.SOLDIER_DAMAGE / Villager.ATTACK_SECONDS,
		"firebolts hurt faster than a warrior's sword")

	# Roots hold goblins in place.
	var goblins := get_tree().get_nodes_in_group("goblins")
	_check(not goblins.is_empty(), "goblins live at the cave (%d)" % goblins.size())
	var first := goblins[0] as Villager
	_check(is_equal_approx(first.max_hp, Villager.HEALTH) and is_equal_approx(first.damage, Villager.ATTACK_DAMAGE), "goblins match grown-up villagers")
	var roots := RootPatch.new()
	game.world_root.add_child(roots)
	var person: Villager = village.people()[0]
	person.global_position = first.global_position + Vector3(1, 0, 0)
	roots.cast(first.global_position)
	var held_at := first.global_position
	await _wait(3.0)
	_check(first.snared_until > game.now + 10.0 and first.snared_until < game.now + RootPatch.DURATION and first.global_position.distance_to(held_at) < 0.5,
		"roots hold goblins for 20 seconds")
	_check(person.slowed_until > game.now and person.snared_until <= game.now, "roots only slow your own people")
	roots.queue_free()
	for g in goblins:
		(g as Villager).snared_until = 0.0

	# The midnight raid: goblins march on the village and fight.
	var gap_before := first.global_position.distance_to(village.center)
	play.raids.start_raid()
	_check(get_tree().get_nodes_in_group("raiders").size() == goblins.size(), "every goblin joins the raid")
	await _wait(20.0)
	_check(not is_instance_valid(first) or not first.is_alive() or first.global_position.distance_to(village.center) < gap_before - 10.0,
		"raiders close in on the village")
	# The tortoise deals with goblins that come within reach.
	var bait: Array = []
	for g in get_tree().get_nodes_in_group("raiders"):
		if bait.size() < 4:
			bait.append(g)
	var c := play.creature
	var ahead := Vector3(sin(c.heading), 0, cos(c.heading))
	for k in bait.size():
		(bait[k] as Villager).global_position = c.global_position + ahead * 4.0 + Vector3(k - 1.5, 0, 0)
		(bait[k] as Villager).snared_until = game.now + 60.0
	await _wait(12.0)
	var left := 0
	for g in bait:
		if is_instance_valid(g) and (g as Villager).is_alive():
			left += 1
	_check(left == 0, "the tortoise kills goblins in reach (%d of %d left)" % [left, bait.size()])
	await _wait(60.0)
	play.raids.end_raid()
	_check(get_tree().get_nodes_in_group("raiders").is_empty(), "the raid ends in the morning")
	var rate := play.raids.spawn_rate()
	play.raids.nights += 1
	_check(play.raids.spawn_rate() > rate, "goblins spawn faster every night")
	var before_goblins := get_tree().get_nodes_in_group("goblins").size()
	game.settings.goblin_rate = 12.0
	await _wait(11.0)
	game.settings.goblin_rate = Game.DEFAULT_SETTINGS.goblin_rate
	_check(get_tree().get_nodes_in_group("goblins").size() > before_goblins, "caves keep spawning goblins")

	# Hunger: no births without food, then people starve.
	game.settings.food_rate = 0.0
	village.resources.food = 0.0
	var fed := village.population()
	await _wait(1.0)
	_check(village.next_birth_in() < 0.0, "no births without food")
	await _wait(PlayerVillage.STARVE_AFTER + PlayerVillage.STARVE_EVERY * 0.5)
	_check(village.population() < fed, "people starve with no food (%d -> %d)" % [fed, village.population()])
	game.settings.food_rate = Game.DEFAULT_SETTINGS.food_rate
	village.resources.food = 200.0

	# Water flows into lowered ground next to it; craters away from water are stone.
	var terrain: Terrain = game.terrain
	var shore := _find_shore(terrain)
	_check(shore != Vector3.INF, "found a shore")
	if shore != Vector3.INF:
		terrain.apply_brush(shore, 4.0, Terrain.Brush.LOWER, 3.0, 0.0, 0.9)
		await _wait(1.0)
		_check(terrain.water_depth(shore.x, shore.z) > 0.5, "water flows into lowered ground beside it")
	var dry := _free_spot(play, village.center + Vector3(30, 0, 30))
	if dry != Vector3.INF and terrain.water_depth(dry.x, dry.z) == 0.0:
		Explosion.detonate(dry, Fireball.BLAST_RADIUS)
		await _wait(1.0)
		var k := roundi(dry.z + Terrain.HALF) * Terrain.N + roundi(dry.x + Terrain.HALF)
		_check(terrain.water_depth(dry.x, dry.z) == 0.0 and terrain.rock[k] > 0.5, "a crater away from water is dry stone")

	# Rain puts out fires.
	var fire_at := village.center + Vector3(6, 0, 6)
	game.fire.start_fire(fire_at)
	game.fire.start_fire(fire_at + Vector3(3, 0, 0))
	var cloud := RainCloud.new()
	game.world_root.add_child(cloud)
	cloud.cast(fire_at)
	await _wait(2.0)
	var near := 0
	for f in game.fire._fires:
		if (f.pos as Vector3).distance_to(fire_at) < RainCloud.RADIUS:
			near += 1
	_check(near == 0, "rain puts out the fires (%d left)" % near)
	game.fire.start_fire(fire_at)
	_check(game.fire._fires.filter(func(f: Dictionary) -> bool: return (f.pos as Vector3).distance_to(fire_at) < 2.0).is_empty(), "wet ground does not burn")

	# 3. The editor: a small map with starts, a cave and trees, saved.
	await _open(game, "editor", "", 192)
	var editor := get_tree().current_scene.get_node("Controller") as EditorMode
	_check(editor != null, "editor controller")
	_check(get_tree().get_nodes_in_group("buildings").is_empty(), "new editor map has no buildings")
	var placed := 0
	for p in [Vector2(-30, -20), Vector2(30, 25), Vector2(0, 40)]:
		var pos := Vector3(p.x, game.terrain.get_height(p.x, p.y), p.y)
		if editor._spot_problem(pos) == "":
			editor._place_start(pos)
			placed += 1
	_check(get_tree().get_nodes_in_group("start_markers").size() == placed and placed > 0, "start locations placed (%d)" % placed)
	editor._place_cave(Vector3(45, game.terrain.get_height(45, -45), -45))
	editor._plant_tree(Vector3(-10, 0, 10))
	# Grow the island out over the sky with the land brush.
	var t2: Terrain = game.terrain
	var out := Vector3(0, 0, 0)
	for d in range(60, 96):
		if not t2._land(d, 0):
			out = Vector3(d + 3, 0, 0)
			break
	_check(out != Vector3.ZERO, "found sky beside the island")
	t2.paint_land(out, 5.0, 2.4)
	_check(t2.is_inside(out.x, out.z), "the land brush grows the island")
	var hit_edge := t2.paint_land(Vector3(Terrain.HALF - 1.0, 0, 0), 5.0, 2.4)
	_check(hit_edge, "the land brush stops at the edge of the map")
	var data_now := editor.map_data()
	data_now["version"] = MapData.VERSION
	var bigger := MapData.expand(data_now, 64)
	var probe := Vector2(out.x, out.z)
	var old_n: int = int(data_now.size) + 1
	var new_n: int = int(bigger.size) + 1
	var ok_shift: bool = is_equal_approx((data_now.heights as PackedFloat32Array)[roundi(probe.y + data_now.size * 0.5) * old_n + roundi(probe.x + data_now.size * 0.5)],
		(bigger.heights as PackedFloat32Array)[roundi(probe.y + bigger.size * 0.5) * new_n + roundi(probe.x + bigger.size * 0.5)])
	_check(int(bigger.size) == 192 + 128 and ok_shift, "the map square grows without moving the land")
	editor._map_name = TEST_MAP
	var path := editor._save()
	_check(path != "" and FileAccess.file_exists(path), "map saved (%s)" % path)
	var data := MapData.load_map(path)
	_check(not data.is_empty() and data.size == 192, "map loads back")
	_check((data.starts as PackedVector2Array).size() == placed, "starts saved")
	var listed := MapData.list_maps().filter(func(m: Dictionary) -> bool: return m.path == path)
	_check(listed.size() == 1, "map is listed in the menu")

	# 4. Play the saved map: no buildings, villagers appear at the start.
	await _open(game, "play", path, 192)
	play = get_tree().current_scene.get_node("Controller") as PlayMode
	_check(Terrain.SIZE == 192, "map size restored")
	_check(get_tree().get_nodes_in_group("buildings").is_empty(), "saved map has no buildings")
	_check(get_tree().get_nodes_in_group("start_markers").size() == placed, "start banners shown")
	_check(get_tree().get_nodes_in_group("goblins").size() > 0 == (data.caves.size() > 0), "goblins live in the caves")
	var s0: Vector2 = play._info.starts[0]
	play._found(Vector3(s0.x, game.terrain.get_height(s0.x, s0.y), s0.y), 0)
	_check(play.village.population() == PlayerVillage.START_VILLAGERS, "starting villagers spawned (%d)" % play.village.population())
	await _wait(3.0)
	_check(get_tree().get_nodes_in_group("start_markers").is_empty(), "banners removed after choosing")

	# 5. A large random island builds.
	await _open(game, "play", "", 768)
	_check(Terrain.SIZE == 768 and Terrain.CHUNKS == 24 and is_equal_approx(Terrain.ISLAND_RADIUS, 348.0), "large map: twice the old island radius")

	DirAccess.remove_absolute(path)
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
	else:
		print("SMOKE TEST FAILED:\n  " + "\n  ".join(_failures))
		get_tree().quit(1)


func _open(game: Variant, mode: String, map_path: String, size: int) -> void:
	game.session = {"mode": mode, "map_path": map_path, "size": size}
	game.world_seed = 4242 + size
	game.village = null
	get_tree().change_scene_to_file(MAIN)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("opened %s %s %d" % [mode, map_path, size])


## Waits `seconds` of game time.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, false).timeout


func _free_spot(play: PlayMode, center: Vector3) -> Vector3:
	for ring in range(8, 44, 4):
		for k in 16:
			var a := TAU * k / 16.0
			var p := center + Vector3(cos(a) * ring, 0, sin(a) * ring)
			p.y = Game.terrain.get_height(p.x, p.z)
			play._place_kind = "tall_house"
			if play._placement_problem(p, 4.0) == "":
				return p
	return Vector3.INF


## A dry sample right beside water, on the island.
func _find_shore(terrain: Terrain) -> Vector3:
	for j in range(4, Terrain.SIZE - 4, 3):
		for i in range(4, Terrain.SIZE - 4, 3):
			var k := j * Terrain.N + i
			if terrain.island[k] == 0 or terrain.water[k] != Terrain.NO_WATER or terrain.water[k + 2] == Terrain.NO_WATER:
				continue
			var x := i - Terrain.HALF
			var z := j - Terrain.HALF
			if terrain.is_inside(x, z) and terrain.get_height(x, z) < 2.0:
				return Vector3(x, terrain.get_height(x, z), z)
	return Vector3.INF


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
