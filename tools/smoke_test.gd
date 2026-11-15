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
	# The creature grows up in a few seconds and eats nothing, so the older
	# checks see the full-grown creature and the food they expect.
	game.settings.creature_grow_minutes = 0.1
	game.settings.creature_food = 0.0
	# The creature learns nothing until its own checks, so it does not start
	# fetching food or casting spells in the middle of the others.
	for id: String in CreatureMind.SPELLS + CreatureMind.HARVESTS:
		Balance.values["knowledge_" + id] = 1.0e9

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
	var free_store := false
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.get_meta("kind", "") == "store" and (b as Node3D).global_position.distance_to(village.center) < 45.0:
			free_store = true
	_check(free_store, "a free Storehouse stands at the start location")
	_check(Balance.values.size() == Balance.DEFAULTS.size() and FileAccess.file_exists(Balance.PATH), "balancing.txt is read")
	_check(str(ProjectSettings.get_setting("application/config/version", "")) != "", "the game has a version number")
	play.pause_menu.open()
	_check(get_tree().paused, "Esc's pause menu stops the game")
	play.pause_menu.close()
	_check(not get_tree().paused, "and lets it go again")
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
	# The day stops while armies and hunger are tested, so no raid gets in
	# the way (recruits stop training to fight).
	play.day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	@warning_ignore("integer_division")
	var guards_before := village.max_count("warrior") / PlayerVillage.WARRIORS_PER_GUARD
	var tower := BuildingFactory.create("moon_tower", RandomNumberGenerator.new())
	game.world_root.add_child(tower)
	tower.global_position = village.center + Vector3(10, 0, -10)
	tower.add_to_group("player_buildings")
	village.set_wanted("warrior", 99)
	_check(village.wanted.warrior == (guards_before + 1) * PlayerVillage.WARRIORS_PER_GUARD,
		"each Town guard allows 4 warriors (%d guards, %d allowed)" % [guards_before + 1, village.wanted.warrior])
	village.set_wanted("warrior", 1)
	await _wait(PlayerVillage.WARRIOR_SECONDS * 0.5)
	_check(village.soldiers() == 0 and village.training_progress("warrior").size() == 1, "a warrior takes a minute to train")
	await _wait(PlayerVillage.WARRIOR_SECONDS * 0.5 + 35.0)
	var soldiers := get_tree().get_nodes_in_group("soldiers")
	_check(soldiers.size() == 1, "the first warrior is trained (%d)" % soldiers.size())
	if not soldiers.is_empty():
		var s := soldiers[0] as Villager
		_check(is_equal_approx(s.max_hp, Balance.num("warrior_health")) and is_equal_approx(s.damage, Balance.num("warrior_damage")), "soldiers have 4x health and 2x damage")
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
	_check(is_equal_approx(first.max_hp, Balance.num("goblin_health")) and is_equal_approx(first.damage, Balance.num("goblin_damage")), "goblins match grown-up villagers")
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
	# Caves spawn all the time, so count the goblins (and any ogres) now.
	_check(get_tree().get_nodes_in_group("raiders").size() == get_tree().get_nodes_in_group("goblins").size(), "every goblin joins the raid")
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

	# Hunger: no births without food, then people starve. The wheat is held
	# growing so no harvest comes in.
	for node in get_tree().get_nodes_in_group("fields"):
		var f := node as CropField
		f.stage = CropField.Stage.GROWING
		f.progress = 0.0
		f.process_mode = Node.PROCESS_MODE_DISABLED
	game.settings.food_rate = 0.0
	village.resources.food = 0.0
	# Food already on its way to the store would reset the hunger clock.
	for v in village.people():
		if v.carry_kind == "food":
			v.carry = 0.0
	var fed := village.population()
	await _wait(1.0)
	_check(village.next_birth_in() < 0.0, "no births without food")
	for k in 12:
		await _wait(15.0)
		village.resources.food = minf(village.resources.food, 0.0)
		if village.population() < fed:
			break
	_check(village.population() < fed, "people starve with no food (%d -> %d)" % [fed, village.population()])
	game.settings.food_rate = Game.DEFAULT_SETTINGS.food_rate
	village.resources.food = 200.0
	for node in get_tree().get_nodes_in_group("fields"):
		node.process_mode = Node.PROCESS_MODE_INHERIT
	play.day_cycle.process_mode = Node.PROCESS_MODE_INHERIT

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

	# One ogre joins the raid for every 15 goblins.
	var cave := get_tree().get_nodes_in_group("caves")[0] as Node3D
	while get_tree().get_nodes_in_group("goblins").size() < GoblinRaids.GOBLINS_PER_OGRE:
		play.raids.spawn_at(cave)
	play.raids.start_raid()
	var ogres := get_tree().get_nodes_in_group("ogres")
	@warning_ignore("integer_division")
	var expected_ogres := (get_tree().get_nodes_in_group("goblins").size() - ogres.size()) / GoblinRaids.GOBLINS_PER_OGRE
	_check(ogres.size() == expected_ogres and ogres.size() >= 1, "an ogre joins the raid for every 15 goblins (%d)" % ogres.size())
	if not ogres.is_empty():
		var ogre := ogres[0] as Villager
		_check(is_equal_approx(ogre.max_hp, Balance.num("ogre_health")) and is_equal_approx(ogre.damage, Balance.num("ogre_damage")),
			"the ogre has 10x health and 3x damage")
	await _wait(15.0)
	play.raids.end_raid()

	# Blood Sacrifice: a villager dies, magicko comes in twice as fast.
	var people_before := village.population()
	_check(village.sacrifice(village.people()[0].global_position), "blood sacrifice finds a villager")
	_check(village.population() == people_before - 1 and village.blood_active(), "the sacrifice kills one villager and starts the boost")
	await _wait(2.0)

	# Rain makes wheat grow faster.
	field.stage = CropField.Stage.GROWING
	field.progress = 0.0
	var wet := RainCloud.new()
	game.world_root.add_child(wet)
	wet.cast(field.global_position)
	await _wait(10.0)
	_check(field.stage != CropField.Stage.GROWING or field.progress > 10.0 / CropField.GROW_SECONDS * 1.8, "rain speeds up the wheat (%.2f)" % field.progress)

	# The creature: full grown by now; it eats, and can be knocked out.
	var beast := play.creature
	_check(beast.kind == "tortoise" and is_equal_approx(beast.size, 1.0), "the tortoise is full grown after its growing time")
	game.settings.creature_food = 20.0
	_check(is_equal_approx(village.creature_upkeep(), 20.0), "a full-grown creature eats 20 food a minute")
	game.settings.creature_food = 0.0
	_check(is_equal_approx(Creature.SPECIES.tiger.speed, Creature.SPECIES.tortoise.speed * 1.3)
		and is_equal_approx(Balance.num("tortoise_health"), Balance.num("tiger_health") * 2.0), "the tiger is 30% faster, the tortoise has twice the health")
	beast.take_hit(beast.max_hp * 2.0, null)
	_check(beast.knocked_out, "the creature is knocked out at no health")

	# Blacksmith: wheelbarrows, research, archers.
	play.day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	play.raids.end_raid()
	_check(not village.barrows, "no wheelbarrows without a Blacksmith")
	_check(village.start_research("bows") != "", "research needs a Blacksmith")
	var smithy := BuildingFactory.create("blacksmith", RandomNumberGenerator.new())
	game.world_root.add_child(smithy)
	smithy.global_position = village.center + Vector3(-12, 0, -8)
	smithy.add_to_group("player_buildings")
	await _wait(1.5)
	_check(village.barrows, "a Blacksmith brings wheelbarrows")
	for res in ["lumber", "stone", "food"]:
		village.give(res, 600.0)
	_check(village.max_count("archer") == 0, "no archers before bows")
	_check(village.start_research("bows") == "", "bows can be researched")
	_check(village.start_research("axes") != "", "one research at a time")
	village.research.t = Research.find("bows").seconds - 2.0
	await _wait(4.0)
	_check(village.has_research("bows") and village.max_count("archer") >= PlayerVillage.ARCHERS_PER_GUARD,
		"bows allow 2 archers per Town guard (%d allowed)" % village.max_count("archer"))
	_check(is_equal_approx(Research.find("swords").seconds, 300.0), "sharper swords take 5 minutes")
	for id: String in ["swords", "pitchforks", "picks", "axes"]:
		village.start_research(id)
		village.research.t = Research.find(id).seconds - 0.5
		await _wait(1.5)
	_check(village.has_research("swords") and is_equal_approx(village.tool_bonus("food"), 2.0)
		and is_equal_approx(village.tool_bonus("stone"), 2.0) and is_equal_approx(village.tool_bonus("lumber"), 2.0), "swords and tools researched")
	village.set_wanted("archer", 1)
	await _wait(PlayerVillage.ARCHER_SECONDS + 45.0)
	_check(village.archers() == 1, "an archer is trained (%d)" % village.archers())
	village.set_wanted("warrior", 1)
	await _wait(PlayerVillage.WARRIOR_SECONDS + 45.0)
	var sharp := get_tree().get_nodes_in_group("soldiers")
	_check(not sharp.is_empty() and is_equal_approx((sharp[0] as Villager).damage, Balance.num("warrior_damage") * Balance.num("sharper_swords_bonus")),
		"warriors hit harder with sharper swords")
	# The player sets one more miner: it switches at once.
	var miners_before: int = village.gatherers.stone
	village.change_quota("stone", 1)
	_check(village.gatherers.stone == miners_before + 1 and village.quota.stone == miners_before + 1,
		"one more miner is set to work at once (%d -> %d)" % [miners_before, village.gatherers.stone])
	village.change_quota("stone", -1)

	# The creature learns by watching, and is blessed and cursed.
	var mind := beast.mind
	for id: String in CreatureMind.SPELLS + CreatureMind.HARVESTS:
		Balance.values["knowledge_" + id] = Balance.DEFAULTS["knowledge_" + id]
		mind.knowledge[id] = 0.0
	mind.watch_spell("rain")
	_check(is_equal_approx(mind.knowledge.rain, Balance.num("knowledge_per_watch")) and not mind.learned("rain"), "watching a spell adds knowledge")
	for k in 3:
		mind.watch_spell("rain")
	_check(mind.learned("rain"), "four casts teach the creature rain")
	var lumber_known: float = mind.knowledge.lumber
	village.store("lumber", Balance.num("stored_per_lesson"))
	_check(is_equal_approx(mind.knowledge.lumber, lumber_known + Balance.num("knowledge_per_lesson")), "storing 100 lumber teaches it a little about lumber")
	mind.did("eat")
	mind.judge(1)
	_check(is_equal_approx(mind.behavior.eat, Balance.num("behavior_start") + Balance.num("bless_points")), "bless makes it keener on what it just did")
	mind.judge(-1)
	_check(is_equal_approx(mind.behavior.eat, Balance.num("behavior_start")), "curse makes it less keen")
	# Rain when the village burns.
	game.fire.start_fire(village.center + Vector3(5, 0, -5))
	var rain_at: Variant = mind._spell_target("rain")
	_check(rain_at != null, "the creature sees a fire to rain on")
	if rain_at != null:
		mind._cast("rain", rain_at)
		_check(mind.last_action == "rain", "the creature casts rain")
	# Its fireball only singes the player's own people.
	var bystander := village.people()[0]
	bystander.hp = bystander.max_hp
	Explosion.detonate(bystander.global_position, Fireball.BLAST_RADIUS, Balance.num("creature_friendly_fire"))
	_check(bystander.is_alive() and bystander.hp < bystander.max_hp, "the creature's fireball does a tenth of the harm to villagers (%.0f of %.0f left)" % [bystander.hp, bystander.max_hp])
	# Fetching a tree once it knows how.
	await _wait(maxf(0.0, Balance.num("creature_knockout_seconds") - 150.0) + 2.0)
	mind.knowledge.lumber = Balance.num("knowledge_lumber")
	mind.behavior.explore = 0.0
	mind._idle_timer = 0.0
	mind._away = false
	mind.home = beast.global_position
	var fetched := false
	for k in 30:
		await _wait(5.0)
		if mind.last_action == "lumber":
			fetched = true
			break
	_check(fetched, "the creature fetches a tree for the storehouse")
	play.day_cycle.process_mode = Node.PROCESS_MODE_INHERIT

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

	# 5. A large random island builds. This time with the tiger, growing
	# at the normal rate: it starts at 15% of its size.
	game.creature_kind = "tiger"
	game.settings.creature_grow_minutes = 30.0
	await _open(game, "play", "", 768)
	_check(Terrain.SIZE == 768 and Terrain.CHUNKS == 24 and is_equal_approx(Terrain.ISLAND_RADIUS, 348.0), "large map: twice the old island radius")
	play = get_tree().current_scene.get_node("Controller") as PlayMode
	var t0: Vector2 = play._info.starts[0]
	play._found(Vector3(t0.x, game.terrain.get_height(t0.x, t0.y), t0.y), 0)
	var tiger := play.creature
	_check(tiger.kind == "tiger" and tiger.size < 0.16 and is_equal_approx(tiger.scale.x, tiger.size), "the tiger starts at 15%% of its size (%.2f)" % tiger.size)
	tiger.move_to(tiger.global_position + Vector3(6, 0, 6))
	await _wait(60.0)
	_check(tiger.size > 0.17 and tiger.size < 0.2, "the tiger grows towards full size over 30 minutes (%.3f after 1 minute)" % tiger.size)
	game.creature_kind = "tortoise"

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
