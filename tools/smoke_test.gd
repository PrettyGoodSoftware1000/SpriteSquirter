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
	await _open(game, "menu", "", 256)
	_check(get_tree().current_scene.get_node("Controller") is MainMenu, "menu controller")

	# 2. A random medium island: found a village, gather, build, be born.
	await _open(game, "play", "", 256)
	var play := get_tree().current_scene.get_node("Controller") as PlayMode
	_check(play != null, "play controller")
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
	await _wait(25.0)
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
	await _open(game, "play", "", 384)
	_check(Terrain.SIZE == 384 and Terrain.CHUNKS == 12, "large map size")

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


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
