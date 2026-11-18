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
	# The creature always notices, and never learns extra, so the
	# knowledge checks are exact (its personality's part is checked below).
	Balance.values["notice_chance"] = 100.0
	Balance.values["bonus_knowledge_chance"] = 0.0
	# Untrained creatures now run from a fight now and then; the tests want them to stay.
	Balance.values["flee_chance"] = 0.0
	# No balrog until its own checks at the end, and the tortoise keeps
	# out of its shell until then too.
	Balance.values["balrogs"] = 0.0
	Balance.values["shell_damage_share"] = 1.0

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
	_check(first_people == roundi(Balance.num("start_villagers")), "the village starts with 20 villagers (%d)" % first_people)
	_check(not get_tree().get_nodes_in_group("player_buildings").is_empty(), "village site buildings join the player")
	var free_store := false
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.get_meta("kind", "") == "store" and (b as Node3D).global_position.distance_to(village.center) < 45.0:
			free_store = true
	_check(free_store, "a free Storehouse stands at the start location")
	_check(BuildingCatalog.housing("store") == 25, "a Storehouse houses 25")
	# What the village can store, and what came in over the last minute.
	var lumber_cap := village.capacity("lumber")
	village.give("lumber", 5000.0)
	var stores := 0
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if BuildingCatalog.role(b.get_meta("kind", "")) == "store":
			stores += 1
	_check(is_equal_approx(lumber_cap, Balance.num("storehouse_holds") * stores) and village.amount("lumber") == roundi(lumber_cap),
		"each Storehouse holds 300 of each (%d lumber, %d Storehouses)" % [village.amount("lumber"), stores])
	village.resources.lumber = 80.0
	_check(village.capacity("magicko") == INF and village.capacity("animus") == INF, "magicko and animus have no limit")
	_check(village.influence() > Game.settings.influence_start and village.in_territory(village.center + Vector3(village.influence() - 1.0, 0, 0))
		and not village.in_territory(village.center + Vector3(village.influence() + 1.0, 0, 0)), "the village's influence grows with its people (%.0f m)" % village.influence())
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
	# (Checked after a minute: in two the field can be reaped and under the plough again.)
	await _wait(60.0)
	_check(field.stage != CropField.Stage.SOWING or field.progress > 0.3, "villagers sow the field (stage %d, %.2f)" % [field.stage, field.progress])
	await _wait(60.0)
	var jobs := {}
	for v in village.people():
		jobs[v.job] = jobs.get(v.job, 0) + 1
	print("  jobs %s" % jobs)
	for res in ["lumber", "stone", "magicko"]:
		_check(village.resources[res] > before[res], "%s is gathered (%.1f -> %.1f)" % [res, before[res], village.resources[res]])
	# (Food is eaten as fast as it comes in while a child is born every 5
	# seconds, so count what was carried to the store.)
	_check(village._stored.get("food", 0.0) > 20.0, "food is gathered (%.1f carried in)" % village._stored.get("food", 0.0))
	_check(village.population() > first_people or village.population() >= village.housing(), "a child is born")

	# The day stops while building, armies and hunger are tested, so that
	# midnight's raid does not come in the middle of them.
	play.day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	var spot := _free_spot(play, village.center)
	_check(spot != Vector3.INF, "found a free building spot")
	if spot != Vector3.INF:
		var site := ConstructionSite.new()
		var home_cost: Dictionary = BuildingCatalog.find("treehouse").cost
		site.setup("treehouse", 1234, home_cost)
		_check(home_cost.lumber == roundi(Balance.num("cost_home_lumber")) and home_cost.stone == roundi(Balance.num("cost_home_stone")),
			"building costs come from balancing.txt")
		_check(is_equal_approx(site.work_needed, (home_cost.lumber + home_cost.stone) * Balance.num("build_work_per_resource")),
			"building time is in proportion to the cost (%d villager-seconds for a Home)" % int(site.work_needed))
		game.world_root.add_child(site)
		site.global_position = spot
		var built := [false]
		site.completed.connect(func(_b: Destructible) -> void: built[0] = true)
		var adults := village.adults()
		# Five villagers at most build one building.
		var expected := site.work_needed / clampf(adults, 1.0, Balance.num("builders_per_building"))
		await _wait(8.0)
		var crew := 0
		for v in village.people():
			if v.job == "build":
				crew += 1
		_check(crew == mini(adults, 5), "no more than 5 villagers build one building (%d)" % crew)
		for k in 48:
			if built[0]:
				break
			await _wait(5.0)
		_check(built[0], "the villagers finish a building (%d adults, ~%d s expected)" % [adults, int(expected)])
		# Gnomish Subcontractors: five gnomes come running and build it.
		# (No villagers work on it, so only the gnomes do.)
		Balance.values["builders_per_building"] = 0.0
		var gnome_site := ConstructionSite.new()
		gnome_site.setup("treehouse", 99, home_cost)
		game.world_root.add_child(gnome_site)
		gnome_site.global_position = spot
		var gnomes := SpellBook.index_of("gnomes")
		village.give("magicko", 100.0)
		var magicko_before := village.amount("magicko")
		# Spells are researched at the Shrine first.
		play._spell_key(gnomes)
		_check(play._armed < 0 and not village.knows_spell("gnomes") and village.knows_spell("fireball") and village.knows_spell("bless"),
			"a spell must be researched before it is cast (Fireball, Bless and Condemn need none)")
		_check(village.shrines().is_empty() and village.start_spell_research("gnomes") != "", "spells are researched at a Shrine")
		var shrine := BuildingFactory.create("singing_rocks", RandomNumberGenerator.new())
		game.world_root.add_child(shrine)
		shrine.global_position = village.center + Vector3(14, 0, 10)
		shrine.add_to_group("player_buildings")
		play._cursor_hit = shrine.global_position
		play._on_left_click()
		_check(play.hud.is_spell_research_open(), "clicking a Shrine opens its spell research")
		play.hud.show_spell_research(false)
		village.give("animus", 10.0)
		var animus_before := village.amount("animus")
		_check(village.start_spell_research("gnomes") == "" and village.amount("animus") == animus_before - roundi(Balance.num("spell_research_gnomes_animus")),
			"researching a spell costs animus")
		_check(village.start_spell_research("rain") != "", "one spell at a time")
		village.spell_research.t = SpellBook.research_seconds("gnomes") - 0.5
		await _wait(1.0)
		_check(village.knows_spell("gnomes") and not village.knows_spell("rain"), "the Shrine teaches the spell")
		village.learn_all_spells()
		_check(village.knows_spell("rain") and village.knows_spell("lightning"), "the dev menu can teach every spell")
		shrine.queue_free()
		play._cursor_hit = spot
		magicko_before = village.amount("magicko")
		play._spell_key(gnomes)
		play._cursor_hit = spot
		play._click_spell()
		var crew_g := get_tree().get_nodes_in_group("gnomes")
		_check(crew_g.size() == 5 and magicko_before - village.amount("magicko") == 20, "Gnomish Subcontractors: 5 gnomes for 20 magicko")
		var far := 0.0
		for g in crew_g:
			far = maxf(far, (g as Node3D).global_position.distance_to(spot))
		_check(far > 40.0, "they appear about 50 m from the building (%.0f m)" % far)
		await _wait(8.0)
		var near := 0
		for g in get_tree().get_nodes_in_group("gnomes"):
			if (g as Node3D).global_position.distance_to(spot) < gnome_site.footprint + 3.0:
				near += 1
		_check(near == 5 and gnome_site.progress > 0.0, "they run to it and build (%d there, %.0f%% built)" % [near, gnome_site.progress * 100.0])
		gnome_site.add_work(gnome_site.work_needed)
		await _wait(0.5)
		_check(get_tree().get_nodes_in_group("gnomes").is_empty(), "and vanish when it is finished")
		Balance.values["builders_per_building"] = Balance.DEFAULTS["builders_per_building"]
		# The dev menu's ruler measures between two clicks.
		play._set_mode(PlayMode.Mode.RULER)
		play._ruler_click(village.center)
		play._ruler_click(village.center + Vector3(30, 0, 40))
		_check(play._ruler.visible and play._ruler._label.text.begins_with("50.0 m"), "the ruler measures a distance (%s)" % play._ruler._label.text)
		play._set_mode(PlayMode.Mode.COMMAND)

	# Warriors: the player asks for them; a Town guard trains one a minute.
	# (The day was stopped above, so no raid gets in the way: recruits stop
	# training to fight.)
	play.raids.end_raid()
	@warning_ignore("integer_division")
	var guards_before := village.max_count("warrior") / PlayerVillage.WARRIORS_PER_GUARD
	# Paying for something leaves the rate beside a resource alone.
	var stone_rate := village.last_minute("stone")
	village.spend({"stone": 10})
	_check(village.last_minute("stone") == stone_rate, "paying for something does not change a resource's rate (%d)" % stone_rate)
	village.give("stone", 10.0)
	if guards_before == 0:
		play.hud.set_resources(village, "")
		_check((play.hud._jobs.warrior.count as Label).text == "0/0", "Warriors 0/0 without a Town guard (%s)" % (play.hud._jobs.warrior.count as Label).text)
	var tower := BuildingFactory.create("tall_house", RandomNumberGenerator.new())
	game.world_root.add_child(tower)
	tower.set_meta("kind", "tall_house")
	tower.global_position = village.center + Vector3(10, 0, -10)
	tower.add_to_group("player_buildings")
	_check(village.max_count("warrior") == (guards_before + 1) * PlayerVillage.WARRIORS_PER_GUARD,
		"each Town guard allows 4 warriors (%d guards, %d allowed)" % [guards_before + 1, village.max_count("warrior")])
	var free_before := village.free_workers()
	village.set_wanted("warrior", 99)
	_check(village.wanted.warrior == mini(village.max_count("warrior"), free_before),
		"no more warriors are wanted than there are free workers (%d wanted, %d free)" % [village.wanted.warrior, free_before])
	village.set_wanted("warrior", 0)
	play.hud.set_resources(village, "")
	_check((play.hud._jobs.warrior.count as Label).text == "%d/%d" % [village.count("warrior"), village.max_count("warrior")],
		"a Town guard makes it 0/4 at once (%s)" % (play.hud._jobs.warrior.count as Label).text)
	village.set_wanted("warrior", 1)
	play.hud.set_resources(village, "")
	_check((play.hud._jobs.warrior.count as Label).text == "%d/%d" % [maxi(1, village.count("warrior")), village.max_count("warrior")],
		"asking for a warrior counts it at once, before it is trained (%s)" % (play.hud._jobs.warrior.count as Label).text)
	_check(is_equal_approx(village.train_seconds("warrior"), 15.0), "a warrior trains in a quarter of a minute")
	Game.settings.training_time = 2.0
	_check(is_equal_approx(village.train_seconds("warrior"), 30.0), "the training time slider stretches it")
	Game.settings.training_time = 1.0
	await _wait(village.train_seconds("warrior") * 0.5)
	_check(village.soldiers() == 0 and village.training_progress("warrior").size() == 1, "a warrior is still training halfway")
	await _wait(village.train_seconds("warrior") * 0.5 + 35.0)
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

	# Wizards: a Wizardry tower (the Moon tower) trains them; they make magicko.
	var rocks := BuildingFactory.create("moon_tower", RandomNumberGenerator.new())
	game.world_root.add_child(rocks)
	rocks.set_meta("kind", "moon_tower")
	rocks.global_position = village.center + Vector3(-12, 0, 10)
	rocks.add_to_group("player_buildings")
	_check(village.max_count("wizard") == PlayerVillage.WIZARDS_PER_ROCKS, "a Wizardry tower allows 2 wizards")
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
	# (Goblins that are putting up a building stay at home, so any building
	# they have begun by now is cleared away first.)
	for old in get_tree().get_nodes_in_group("goblin_sites"):
		old.remove_from_group("goblin_sites")
		old.queue_free()
	for g in get_tree().get_nodes_in_group("goblins"):
		if (g as Villager).job == "build":
			(g as Villager).clear_job()
	play.raids._build_timer = 0.0
	var gap_before := first.global_position.distance_to(village.center)
	play.raids.start_raid()
	# Caves spawn all the time, so count the goblins (and any ogres) now.
	# (All but the ones putting up a building, who stay to finish it.)
	var builders := 0
	for g in get_tree().get_nodes_in_group("goblins"):
		if (g as Villager).job == "build":
			builders += 1
	_check(get_tree().get_nodes_in_group("raiders").size() == get_tree().get_nodes_in_group("goblins").size() - builders, "every goblin joins the raid (%d builders stay)" % builders)
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
	# It will not stomp beside a villager or a building, so stand it
	# somewhere clear first (where it wandered to is down to chance).
	if not c._stomp_is_safe(c.global_position + ahead * 4.0):
		for k in 48:
			var a := TAU * k / 16.0
			var p := village.center + Vector3(cos(a), 0, sin(a)) * (25.0 + 10.0 * floorf(k / 16.0))
			if not game.terrain.is_inside(p.x, p.z) or not game.terrain.is_dry(p.x, p.z):
				continue
			p.y = game.terrain.get_height(p.x, p.z)
			if c._stomp_is_safe(p + ahead * 4.0) and c._stomp_is_safe(p):
				c.global_position = p
				c.has_target = false
				break
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
	# (The creature holds still, so it eats none of them meanwhile.)
	play.creature.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(11.0)
	play.creature.process_mode = Node.PROCESS_MODE_INHERIT
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
		# (The fires it starts are put out, so they do not creep into the village.)
		_put_out_fires()
		var k := roundi(dry.z + Terrain.HALF) * Terrain.N + roundi(dry.x + Terrain.HALF)
		_check(terrain.water_depth(dry.x, dry.z) == 0.0 and terrain.rock[k] > 0.5, "a crater away from water is dry stone")

	# Ogres come from the goblins' war huts, and giant bats from their
	# watchtowers: none of either until those are built.
	play.raids.start_raid()
	await _wait(14.0)
	_check(get_tree().get_nodes_in_group("ogres").is_empty() and get_tree().get_nodes_in_group("bats").is_empty(), "no ogres or bats without the goblin buildings for them")
	play.raids.end_raid()
	# (One building at a time, so each is finished before the next is begun.
	# Bats do not come before the third night.)
	play.raids.nights = maxi(play.raids.nights, roundi(Balance.num("bats_from_night")))
	var marked := 0
	for wanted: String in [GoblinRaids.OGRE_HOME, GoblinRaids.BAT_HOME]:
		for old in get_tree().get_nodes_in_group("goblin_sites"):
			old.remove_from_group("goblin_sites")
			old.queue_free()
		var new_site: ConstructionSite = null
		for attempt in 6:
			if new_site == null:
				new_site = play.raids.start_building(wanted)
		if new_site != null:
			marked += 1
			new_site.add_work(1.0e9)
		await _wait(0.3)
	_check(marked == 2, "the goblins mark out a war hut and a watchtower")
	await _wait(0.5)
	var ogres := get_tree().get_nodes_in_group("ogres")
	_check(ogres.size() == 1 and play.raids.standing(GoblinRaids.OGRE_HOME).size() == 1, "a finished war hut adds an ogre (%d)" % ogres.size())
	play.raids.start_raid()
	await _wait(14.0)
	_check(get_tree().get_nodes_in_group("ogres").size() == 1 and get_tree().get_nodes_in_group("bats").size() == 1, "the raid has the hut's ogre and the watchtower's bat (%d, %d)"
		% [get_tree().get_nodes_in_group("ogres").size(), get_tree().get_nodes_in_group("bats").size()])
	for node in get_tree().get_nodes_in_group("bats"):
		node.queue_free()
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
	var grown_age := beast.age
	beast.age = 0.0
	beast._grow(0.0)
	_check(is_equal_approx(village.creature_upkeep(), 20.0 * Creature.START_SIZE * 0.5), "a creature under half grown eats half as much")
	beast.age = grown_age
	beast._grow(0.0)
	game.settings.creature_food = 0.0
	_check(is_equal_approx(Creature.SPECIES.squirrel.speed, Creature.SPECIES.tortoise.speed * 1.3)
		and is_equal_approx(Balance.num("tortoise_health"), Balance.num("squirrel_health") * 2.0), "the squirrel is 30% faster, the tortoise has twice the health")
	# The tortoise's shell: a fifth of the harm, and something to bless or curse.
	Balance.values["shell_damage_share"] = Balance.DEFAULTS["shell_damage_share"]
	beast.hp = beast.max_hp
	beast.used["health"] = 0.0  # (so these hits do not happen to level its health up)
	beast.mind.behavior["shell"] = 100.0
	beast.mind.behavior["shell_health_full"] = 100.0
	beast._shell_think_at = 0.0
	beast.take_hit(10.0, null)
	_check(beast.hiding and beast.mind.last_action == "shell" and beast.mind.judge_target() == "shell_health_full",
		"the tortoise hides in its shell when it is hit, judged by how hurt it was (%s)" % beast.mind.judge_target())
	beast.mind.behavior["shell"] = 0.0
	var before_blow := beast.hp
	beast.take_hit(100.0, null)
	_check(is_equal_approx(before_blow - beast.hp, 100.0 * Balance.num("shell_damage_share")), "in its shell it takes a fifth of the damage (%.0f)" % (before_blow - beast.hp))
	beast.hp = beast.max_hp * 0.2
	_check(beast.shell_action() == "shell_near_death", "hiding when near death is a different thing to bless")
	await _wait(Balance.num("shell_calm_seconds") + 1.0)
	_check(not beast.hiding, "the tortoise comes out when nothing has hit it for a while")
	Balance.values["shell_damage_share"] = 1.0
	var size_before := beast.size
	beast.take_hit(beast.max_hp * 2.0, null)
	_check(beast.knocked_out, "the creature dies at no health")
	_check(is_equal_approx(beast.size, size_before * 0.75), "and shrinks by a quarter (%.2f -> %.2f)" % [size_before, beast.size])
	await _wait(50.0)
	_check(beast.knocked_out and play.hud._resurrect.visible, "it stays dead, and the Resurrect button shows")
	# Animus comes from a Shrine (the Singing rocks), and brings it back there.
	village.resources.animus = 0.0
	play.resurrect()
	_check(beast.knocked_out, "no Shrine, no resurrection")
	var shrine := BuildingFactory.create("singing_rocks", RandomNumberGenerator.new())
	game.world_root.add_child(shrine)
	shrine.set_meta("kind", "singing_rocks")
	shrine.global_position = village.center + Vector3(-14, 0, -12)
	shrine.add_to_group("player_buildings")
	await _wait(60.0)
	_check(village.amount("animus") == 1, "a Shrine makes 1 animus a minute (%.2f)" % village.resources.animus)
	play.resurrect()
	_check(beast.knocked_out, "no resurrection without 5 animus")
	village.give("animus", 10.0)
	play.resurrect()
	_check(not beast.knocked_out and is_equal_approx(beast.hp, beast.max_hp) and village.amount("animus") == 6
		and beast.global_position.distance_to(shrine.global_position) < 20.0, "5 animus brings it back to life at the Shrine")
	# A Granary stores more food.
	var food_cap := village.capacity("food")
	var granary := BuildingFactory.create("windmill", RandomNumberGenerator.new())
	game.world_root.add_child(granary)
	granary.set_meta("kind", "windmill")
	granary.global_position = village.center + Vector3(16, 0, 14)
	granary.add_to_group("player_buildings")
	_check(is_equal_approx(village.capacity("food"), food_cap + Balance.num("granary_holds")), "a Granary holds 300 more food")
	_check(village.drop_point(granary.global_position + Vector3(6, 0, 0), "food").distance_to(granary.global_position) < granary.footprint + 1.0,
		"and food can be carried to it")
	granary.queue_free()

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
	await _wait(village.train_seconds("archer") + 45.0)
	_check(village.archers() == 1, "an archer is trained (%d; wanted %s, allowed %d, training %s, raiders %d, workers %d)" % [village.archers(),
		village.wanted, village.max_count("archer"), village.training_progress("archer"), get_tree().get_nodes_in_group("raiders").size(), village.workers()])
	village.set_wanted("warrior", 1)
	await _wait(village.train_seconds("warrior") + 45.0)
	var sharp := get_tree().get_nodes_in_group("soldiers")
	_check(not sharp.is_empty() and is_equal_approx((sharp[0] as Villager).damage, Balance.num("warrior_damage") * Balance.num("sharper_swords_bonus")),
		"warriors hit harder with sharper swords")
	# The player sets one more miner: it switches at once.
	var spare_before := village.unassigned()
	village.change_quota("stone", 1)
	_check(village.quota.stone == 1 and village.unassigned() == spare_before - 1,
		"setting a miner takes one of the unassigned workers (%d -> %d)" % [spare_before, village.unassigned()])
	village.change_quota("stone", -1)
	_check(village.quota.stone == 0 and village.unassigned() == spare_before, "and taking the miner off gives the worker back")
	# Builders are first onto a site, and two sites get a crew each.
	village.change_quota("build", 1)
	var the_builder: Villager = null
	for v in village.people():
		if v.pin == "build":
			the_builder = v
	_check(the_builder != null and village.quota.build == 1 and the_builder.job == "", "a builder waits for something to build")
	var two_sites: Array[ConstructionSite] = []
	for k in 2:
		var spot2 := _free_spot(play, village.center + Vector3(20.0 - 40.0 * k, 0, -20))
		var site2 := ConstructionSite.new()
		site2.setup("mushroom_house", 77 + k, {"lumber": 5000})
		game.world_root.add_child(site2)
		site2.global_position = spot2
		two_sites.append(site2)
	village._assign_jobs()
	var crews := [0, 0]
	for v in village.people():
		if v.job == "build":
			crews[two_sites.find(v.job_target)] += 1
	_check(crews[0] == 5 and crews[1] == 5 and the_builder.job == "build", "two buildings get five builders each (%d and %d)" % crews)
	for site2 in two_sites:
		site2.queue_free()
	village.change_quota("build", -1)
	await _wait(1.0)
	_check(BuildingCatalog.find("store").name == "Stacked houses" and BuildingCatalog.role("store") == "store"
		and BuildingCatalog.find("moon_tower").gameplay == "Wizardry tower" and BuildingCatalog.find("tall_house").gameplay == "Town guard"
		and BuildingCatalog.find("singing_rocks").gameplay == "Shrine" and BuildingCatalog.find("windmill").gameplay == "Granary"
		and BuildingCatalog.find("necro_tower").name == "Skull tower"
		and FileAccess.file_exists(BuildingCatalog.NAMES_PATH), "Names.txt pairs asset names with gameplay names")
	_check(BuildingCatalog.title("moon_tower") == "Wizardry tower" and BuildingCatalog.title("treehouse") == BuildingCatalog.MISSING_NAME
		and BuildingCatalog.title("field") == "Wheat field", "in-game names come from Names.txt; a building without one says Name missing")
	play.hud.show_build_menu(true)
	await _wait(0.3)
	_check(play.hud._build_previews.size() == BuildingCatalog.BUILDINGS.size() - 2, "the build menu shows a picture of each building (%d)" % play.hud._build_previews.size())
	Game.dev_menu = true
	play.hud.set_dev_visible(true)
	_check((play.hud._build_buttons["store"] as Button).tooltip_text.contains("Stacked houses"), "with the dev menu open, the build menu tells the model's name")
	Game.dev_menu = false
	play.hud.set_dev_visible(false)
	_check((play.hud._build_buttons["store"] as Button).tooltip_text == "", "and not otherwise")
	play.hud.show_build_menu(false)
	var all_near := true
	for v in get_tree().get_nodes_in_group("villagers"):
		all_near = all_near and (v as Villager)._near
	_check(all_near, "every villager and goblin is drawn in full detail, however far away")

	# Treehouse Homes, and a rope bridge between two of them.
	var homes: Array[Destructible] = []
	for k in 2:
		var home := BuildingFactory.create("treehouse", RandomNumberGenerator.new())
		game.world_root.add_child(home)
		var hp := village.center + Vector3(14.0 + 18.0 * k, 0, 14)
		home.global_position = Vector3(hp.x, terrain.get_height(hp.x, hp.z), hp.z)
		home.rotation.y = 1.0 + k
		home.add_to_group("player_buildings")
		homes.append(home)
	_check(BuildingCatalog.housing("treehouse") == 6 and homes[0].has_meta("deck_h"), "Homes are treehouses with a deck")
	for kind: String in ["lookout_treehouse", "twin_treehouse", "great_treehouse"]:
		var tree_home := BuildingFactory.create(kind, RandomNumberGenerator.new())
		_check(tree_home.has_meta("deck_h") and BuildingCatalog.role(kind) == "home", "%s is a treehouse Home" % kind)
		tree_home.free()
	_check(is_equal_approx(Balance.num("bridge_max_length"), 35.0), "a rope bridge reaches 35 m (20 villagers long)")
	village.give("lumber", 100.0)
	play._start_placing("bridge")
	_check(play._bridge_ghosts != null and play._bridge_ghosts.get_child_count() > 0, "the treehouses a bridge can join are lit up")
	play._bridge_click(homes[0])
	var lumber_before := village.amount("lumber")
	play._bridge_click(homes[1])
	var bridge_site: ConstructionSite = null
	for node in get_tree().get_nodes_in_group("construction_sites"):
		if (node as ConstructionSite).kind == "bridge":
			bridge_site = node
	_check(bridge_site != null and village.amount("lumber") < lumber_before, "the player marks out a rope bridge between two Homes")
	if bridge_site:
		_check(is_equal_approx(bridge_site.work_needed, (lumber_before - village.amount("lumber")) * Balance.num("build_work_per_resource")),
			"a bridge's building time follows its length")
		bridge_site.add_work(bridge_site.work_needed)
		await _wait(0.5)
		var bridges := get_tree().get_nodes_in_group("bridges")
		_check(bridges.size() == 1 and (bridges[0] as RopeBridge).usable(), "the bridge is built")
		var walker: Villager = null
		for v in village.people():
			if v.can_work():
				walker = v
		var far_foot := RopeBridge.ladder_foot(homes[1])
		walker.global_position = RopeBridge.ladder_foot(homes[0]) + Vector3(1, 0, 1)
		walker._cross_cool = 0.0
		walker.state = Villager.State.IDLE
		var went := walker._try_bridge(far_foot)
		var highest := 0.0
		for k in 60:
			await _wait(1.0)
			if not is_instance_valid(walker) or walker.state != Villager.State.CROSS:
				break
			highest = maxf(highest, walker.global_position.y - terrain.get_height(walker.global_position.x, walker.global_position.z))
		_check(went and highest > 3.0 and is_instance_valid(walker) and walker.global_position.distance_to(far_foot) < 12.0,
			"a villager climbs up, walks over the bridge and comes down the other side (%.1f m up)" % highest)
		_check(play._bridge_problem(homes[0], homes[1]) != "", "two Homes take only one bridge")

	# Bones, necromancers and skeletons.
	var bones_before := village.amount("bones")
	var corpse := WorldPopulator.spawn_villager(game.world_root, terrain, village.center + Vector3(-6, 0, 14), 1.0, true)
	corpse.take_hit(999.0, null)
	var bones_gained := village.amount("bones") - bones_before
	_check(bones_gained >= 2 and bones_gained <= 4 and corpse.is_in_group("corpses"), "a dead goblin leaves 2-4 bones (%d)" % bones_gained)
	var necro_tower := BuildingFactory.create("necro_tower", RandomNumberGenerator.new())
	game.world_root.add_child(necro_tower)
	necro_tower.global_position = village.center + Vector3(-10, 0, 20)
	necro_tower.add_to_group("player_buildings")
	_check(village.max_count("necromancer") == 2 and is_equal_approx(village.train_seconds("necromancer"), 75.0),
		"a Necromancer tower trains 2 necromancers, 75 seconds each")
	Balance.values["necromancer_training_seconds"] = 15.0
	village.set_wanted("wizard", 1)
	if village.wizards() == 0:
		for v in village.people():
			if v.can_work():
				v.become_wizard(necro_tower.global_position)
				break
	village.set_wanted("necromancer", 1)
	await _wait(60.0)
	var necros := get_tree().get_nodes_in_group("necromancers")
	_check(necros.size() == 1, "a wizard becomes a necromancer (%d)" % necros.size())
	Balance.values["necromancer_training_seconds"] = Balance.DEFAULTS["necromancer_training_seconds"]
	if not necros.is_empty():
		var necro := necros[0] as Villager
		var body := WorldPopulator.spawn_villager(game.world_root, terrain, necro.global_position + Vector3(4, 0, 3), 1.0, true)
		await _wait(0.2)
		body.take_hit(999.0, null)
		village.give("bones", 10.0)
		bones_before = village.amount("bones")
		await _wait(12.0)
		var skeletons := get_tree().get_nodes_in_group("skeletons")
		_check(skeletons.size() == 1 and village.amount("bones") <= bones_before - roundi(Balance.num("raise_bones")) + 4,
			"the necromancer raises a skeleton from the dead (%d)" % skeletons.size())
		if not skeletons.is_empty():
			var bony := skeletons[0] as Villager
			_check(is_equal_approx(bony.max_hp, Balance.num("goblin_health") * 0.5) and is_equal_approx(bony.damage, Balance.num("goblin_damage") * 0.5),
				"a skeleton has half the health and damage of who it was")
			_check(not bony.is_in_group("people") and bony._expires > game.now + 100.0 and bony._expires <= game.now + 180.0, "it lasts 3 minutes and is not a villager")
			bony._expires = game.now + 0.5
			await _wait(1.5)
			_check(not is_instance_valid(bony) or not bony.is_alive(), "and then it crumbles")
	village.set_wanted("necromancer", 0)
	village.set_wanted("wizard", 0)

	# The goblins build.
	_check(is_equal_approx(Balance.num("goblin_build_minutes"), 5.0), "the goblins start a building every 5 minutes")
	for old in get_tree().get_nodes_in_group("goblin_sites"):
		old.remove_from_group("goblin_sites")
		old.queue_free()
	var goblin_site := play.raids.start_building()
	_check(goblin_site != null and goblin_site.goblin and goblin_site.is_in_group("goblin_sites"), "the goblins mark out a building near their cave")
	_check(play.raids.start_building() == null, "and start no other until it is finished")
	if goblin_site:
		var site_cave := goblin_site.get_meta("cave") as Node3D
		await _wait(40.0)
		_check(goblin_site.progress > 0.0, "goblins work on it (%.0f%%)" % (goblin_site.progress * 100.0))
		var rate_before := play.raids.cave_rate(site_cave)
		var goblin_built := get_tree().get_nodes_in_group("goblin_buildings").size()
		goblin_site.add_work(goblin_site.work_needed)
		await _wait(0.5)
		_check(get_tree().get_nodes_in_group("goblin_buildings").size() == goblin_built + 1 and get_tree().get_nodes_in_group("player_buildings").filter(
			func(n: Node) -> bool: return n.is_in_group("goblin_buildings")).is_empty(), "and it becomes a goblin building")
		_check(is_equal_approx(play.raids.cave_rate(site_cave), rate_before + Balance.num("goblin_rate_per_building")),
			"each goblin building makes its cave spawn more goblins")
	for kind: String in BuildingFactory.GOBLIN_KINDS:
		var shack := BuildingFactory.create(kind, RandomNumberGenerator.new())
		_check(shack.height > 2.0 and BuildingCatalog.find(kind).name != "", "%s builds" % kind)
		shack.free()

	# Chain lightning jumps from one to the next, and the wet take double.
	var storm_at := village.center + Vector3(60, 0, 60)
	var struck: Array[Villager] = []
	for k in 3:
		var g := WorldPopulator.spawn_villager(game.world_root, terrain, storm_at + Vector3(k * 4.0, 0, 0), 0.1, true)
		g.max_hp = 1000.0
		g.hp = 1000.0
		struck.append(g)
	struck[1].soak()
	await _wait(0.2)
	var hits := ChainLightning.cast(struck[0].global_position)
	_check(hits >= 3, "chain lightning jumps through the goblins near it (%d hit)" % hits)
	_check(is_equal_approx(1000.0 - struck[0].hp, Balance.num("lightning_damage")) and is_equal_approx(1000.0 - struck[1].hp, Balance.num("lightning_damage") * 2.0),
		"a wet goblin takes double from lightning (%.0f and %.0f)" % [1000.0 - struck[0].hp, 1000.0 - struck[1].hp])
	for g in struck:
		g.queue_free()
	_check(SpellBook.index_of("lightning") >= 0 and CreatureMind.SPELLS.has("lightning"), "chain lightning is a spell the creature can learn")

	# Everyone grown up turns out when a goblin comes close to the village.
	# (The creature is held back, so it does not eat the goblin first.)
	play.creature.snared_until = game.now + 6.0
	play.creature.mind.process_mode = Node.PROCESS_MODE_DISABLED
	var prowler := WorldPopulator.spawn_villager(game.world_root, terrain, village.center + Vector3(3, 0, 18), 0.1, true)
	prowler.max_hp = 5000.0
	prowler.hp = 5000.0
	if play.creature.global_position.distance_to(prowler.global_position) < 20.0:
		play.creature.place(play.creature.global_position + (play.creature.global_position - prowler.global_position).normalized() * 25.0, play.creature.heading)
	await _wait(4.0)
	var defenders := 0
	for v in village.people():
		if v.state == Villager.State.FIGHT and v._foe == prowler:
			defenders += 1
	_check(not prowler.raiding or defenders > 0, "a goblin near the village counts as an enemy")
	_check(defenders >= 3, "villagers of all kinds turn out to fight it (%d)" % defenders)
	prowler.queue_free()
	play.creature.mind.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(0.5)

	# A giant bat carries a villager off to the cave during a raid.
	var before_bat := village.population()
	play.raids.raiding = true
	var bat := play.raids.launch_bat()
	_check(bat != null and bat.is_in_group("bats"), "a giant bat flies out of a cave during a raid")
	if bat:
		bat.global_position = village.center + Vector3(0, 30, 0)
		var taken := [false]
		bat.took.connect(func(_v: Villager) -> void: taken[0] = true)
		for k in 40:
			await _wait(2.0)
			if not is_instance_valid(bat):
				break
		_check(taken[0] and village.population() == before_bat - 1, "it snatches a villager and takes it into the cave (%d -> %d)" % [before_bat, village.population()])
	var doomed := play.raids.launch_bat()
	if doomed:
		doomed.take_hit(Balance.num("bat_health") + 1.0, null)
		_check(not doomed.is_alive() and not doomed.is_in_group("bats"), "a bat with no health left falls out of the sky")
	play.raids.raiding = false

	# Bless and Curse: the key takes the spell in hand and says what the
	# creature last did; a click casts it; the key again puts it away. Each
	# thing it does is judged once.
	var bless := SpellBook.index_of("bless")
	beast.mind.did("explore")
	play._spell_key(bless)
	_check(play._armed == bless and play._judge_prompt and play.hud._prompt.text.contains("exploring"), "pressing Bless shows the creature's last action")
	play._spell_key(bless)
	_check(play._armed == -1 and not play._judge_prompt, "pressing it again puts it away")
	var keen: float = beast.mind.behavior.explore
	village.give("magicko", 50.0)
	play._spell_key(bless)
	play._click_spell()
	_check(beast.mind.behavior.explore > keen and play._armed == -1, "a click casts it")
	_check(not play._judge_prompt, "and the text goes")
	keen = beast.mind.behavior.explore
	play._spell_key(bless)
	play._click_spell()
	_check(is_equal_approx(beast.mind.behavior.explore, keen), "the same action cannot be blessed twice")
	_check(not CreatureMind.all_actions().has("run") and not CreatureMind.all_actions().has("fly"), "running and flying are not blessed or cursed")
	# Other spells: in hand, then cast with a click inside the influence.
	var fireball := SpellBook.index_of("fireball")
	play._spell_key(fireball)
	_check(play._armed == fireball and SpellCursors.image("fireball").get_size() == Vector2i(SpellCursors.SIZE, SpellCursors.SIZE), "a spell in hand turns the pointer into its sign")
	var magicko_then := village.amount("magicko")
	play._cursor_hit = village.center + Vector3(village.influence() + 30.0, 0, 0)
	play._click_spell()
	_check(village.amount("magicko") == magicko_then, "spells cannot be cast outside the village's influence")
	play._disarm()
	_check(is_equal_approx(Balance.num("lightning_jumps"), 12.0), "chain lightning jumps twice as many times")
	_check(SpellBook.SPELLS[SpellBook.index_of("condemn")].name == "Condemn" and SpellBook.index_of("curse") == -1, "Curse is now called Condemn")
	# The soft cooldown: a spell cast recently costs more.
	var fire_k := SpellBook.index_of("fireball")
	var fire_cost := play.spell_cost(fire_k)
	(play._recent[fire_k] as Array).append(game.now)
	(play._recent[fire_k] as Array).append(game.now)
	_check(play.spell_cost(fire_k) == fire_cost * 2, "a spell cast twice in the last 10 seconds costs twice as much (%d)" % play.spell_cost(fire_k))
	(play._recent[fire_k] as Array).clear()

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
	_check(is_equal_approx(mind.behavior.eat, Balance.num("affinity_start") + 10.0), "Bless adds 10 affinity for what it just did")
	mind.did("eat")
	mind.judge(-1)
	_check(is_equal_approx(mind.behavior.eat, Balance.num("affinity_start") + 10.0), "the same action cannot be judged again within a minute")
	mind._judged_at.eat = game.now - 61.0
	mind.judge(-1)
	_check(is_equal_approx(mind.behavior.eat, Balance.num("affinity_start")), "a minute later, Condemn takes 10 away")
	mind.behavior.eat = 30.0
	_check(is_equal_approx(mind.cooldown("eat"), 180.0), "at 30 affinity the wait is 3 minutes")
	mind.behavior.eat = -60.0
	_check(is_equal_approx(mind.cooldown("eat"), 360.0), "at -60 it is 6 minutes")
	mind.behavior.eat = 85.0
	_check(is_equal_approx(mind.cooldown("eat"), 720.0), "at 80 or more it is 12 minutes")
	mind.behavior.eat = 0.0
	# With an action cooling down, the next one down its column whose
	# condition held is judged instead.
	mind._judged_at.clear()
	var short := {"lowest": true, "stock": 0, "battle": true}
	mind.did("lumber", short)
	_check(mind.judge_target() == "lumber_none", "the most specific action whose condition held is judged first (%s)" % mind.judge_target())
	mind.judge(1)
	_check(mind.judge_target() == "lumber_lowest", "then, while it waits, the next one down whose condition held (%s)" % mind.judge_target())
	mind.judge(1)
	_check(mind.judge_target() == "lumber_battle" and is_equal_approx(mind.behavior.lumber_lowest, 10.0), "skipping the ones that did not hold (%s)" % mind.judge_target())
	mind.judge(1)
	_check(mind.judge_target() == "lumber", "and the general one comes last")
	_check(mind.describe("lumber_none") == "When we were totally out of wood, the creature gathered some.", "the sentence comes from Actions.csv, without the brackets")
	mind.did("throw", {"enemy": "ogre"})
	_check(mind.describe("throw") == "The creature threw an ogre.", "[a or an] [enemy name] is filled in (%s)" % mind.describe("throw"))
	_check(ActionTable.unknown.is_empty(), "every condition in Actions.csv is understood (%s)" % ", ".join(ActionTable.unknown))
	_check(mind.score("lumber", short) > mind.score("lumber", {"highest": true, "stock": 100}) and mind.weight("lumber", short) > mind.weight("lumber", {}),
		"what it is blessed for makes it likelier to do it")
	_check(mind.applicable("flee", {"health": 0.2}) == ["flee_health_under_25", "flee_health_under_50", "flee"]
		and mind.applicable("flee", {"health": 1.0}) == ["flee_health_full", "flee_health_over_80", "flee"], "health conditions read their numbers from the brackets")
	var picks := {"a": 0, "b": 0}
	for k in 400:
		picks[CreatureMind.pick({"a": exp(1.0), "b": 1.0})] += 1
	_check(picks.a > picks.b and picks.b > 0, "choices are made at random, weighted by affinity (%d to %d)" % [picks.a, picks.b])
	for key: String in ["lumber", "lumber_lowest", "lumber_none", "lumber_battle"]:
		mind.behavior[key] = 0.0
	mind._judged_at.clear()
	_check(mind.behavior.has("food_none") and mind.behavior.has("food_plenty") and mind.behavior.has("lumber_battle") and mind.behavior.has("flee_health_under_25"),
		"fetching and running away depend on what was going on")
	# Rain when the village burns.
	game.fire.start_fire(village.center + Vector3(5, 0, -5))
	var rain_at: Variant = null
	for option: Dictionary in mind._spell_options("rain"):
		if option.facts.get("target", "") == "fire":
			rain_at = option.pos
	_check(rain_at != null, "the creature sees a fire to rain on")
	if rain_at != null:
		mind._cast("rain", rain_at, {"target": "fire"})
		_check(mind.last_action == "rain" and mind.judge_target() == "rain_fire", "the creature casts rain on it")
	# Rain on growing wheat is its own thing to do, and spells cost it magicko.
	var crop := get_tree().get_nodes_in_group("fields")[0] as CropField
	crop.stage = CropField.Stage.GROWING
	crop.progress = 0.0
	crop._wet = 0.0
	game.fire._wet.clear()
	var crop_seen := false
	for option: Dictionary in mind._spell_options("rain"):
		crop_seen = crop_seen or option.facts.get("target", "") == "crops"
	_check(crop_seen, "the creature sees growing wheat to rain on")
	Balance.values["spell_hold_weight"] = 0.0
	mind.behavior["rain_fire"] = -100.0
	mind.behavior["rain_crops"] = 100.0
	mind._ready_at.clear()
	beast.magicko = 0.0
	_check(not mind._try_spells(), "the creature cannot cast without magicko")
	beast.magicko = beast.max_magicko
	_check(mind._try_spells() and mind.last_action == "rain" and mind.last_facts.get("target", "") == "crops" and is_equal_approx(beast.magicko, beast.max_magicko - Balance.num("creature_cost_rain")),
		"it casts rain on the crops, and that costs it magicko (%d left)" % roundi(beast.magicko))
	mind.behavior["rain_fire"] = Balance.num("affinity_start")
	mind.behavior["rain_crops"] = Balance.num("affinity_start")
	Balance.values["spell_hold_weight"] = Balance.DEFAULTS["spell_hold_weight"]
	# Mischief: a fireball at a villager is possible, but rare until blessed.
	var fire_options := {}
	# (Stood by the village, so there are villagers and buildings in reach.)
	var stand := village.people()[0].global_position + Vector3(12, 0, 0)
	beast.place(stand, beast.heading)
	for option: Dictionary in mind._spell_options("fireball"):
		fire_options[option.facts.target] = option.base
	_check(is_equal_approx(fire_options.get("villager", -1.0), Balance.num("mischief_weight") * mind.personality("mischief")),
		"fireball at a villager or one of our buildings is a rare choice, as rare as the tortoise's mischief weight (%s)" % str(fire_options))
	village.resources.magicko = 500.0
	var blood_bases := []
	for option: Dictionary in mind._spell_options("blood"):
		blood_bases.append(option.base)
	_check(blood_bases.is_empty() or is_equal_approx(blood_bases[0], 1.0 if village.population() >= village.housing() else Balance.num("mischief_weight") * mind.personality("mischief")),
		"a sacrifice with plenty of magicko is mischief unless housing is full (%s)" % str(blood_bases))
	# Personality traits: written as percentages, 100% average.
	_check(is_equal_approx(Balance.parse_number("150%"), 1.5) and is_equal_approx(Balance.num("raven_spellcaster_personality"), 1.5)
		and is_equal_approx(Balance.num("tortoise_observant_personality"), 1.5) and is_equal_approx(Balance.num("tortoise_knowledgeSeeker_personality"), 1.5)
		and is_equal_approx(Balance.num("raven_knowledgeSeeker_personality"), 1.5) and is_equal_approx(Balance.num("squirrel_flee_personality"), 1.5),
		"personalities are read as percentages (raven spellcaster, tortoise observant and knowledge seeker, raven knowledge seeker, squirrel flee)")
	_check(not Balance.DEFAULTS.has("flee_chance_near_death") and Balance.DEFAULTS.has("flee_chance"), "how hurt it is no longer sets a base chance to run")
	# Observant: with no chance to notice, it learns nothing; knowledge
	# seeker: with every chance of extra, it learns twice as much.
	var stone_known: float = mind.knowledge.stone
	var stone_needed := Balance.num("knowledge_stone")
	Balance.values["knowledge_stone"] = 1.0e9
	mind.knowledge.stone = 0.0
	var learn_then: float = 0.0
	Balance.values["notice_chance"] = 0.0
	mind._on_lesson("stone")
	_check(is_equal_approx(mind.knowledge.stone, learn_then), "a creature that does not notice learns nothing")
	Balance.values["notice_chance"] = 100.0
	Balance.values["bonus_knowledge_chance"] = 100.0
	mind._on_lesson("stone")
	_check(is_equal_approx(mind.knowledge.stone, learn_then + 2.0 * Balance.num("knowledge_per_lesson")), "a knowledge seeker sometimes learns extra (%.0f)" % (mind.knowledge.stone - learn_then))
	Balance.values["bonus_knowledge_chance"] = 0.0
	mind.knowledge.stone = stone_known
	Balance.values["knowledge_stone"] = stone_needed
	# The dev menu's sliders go to a text file and back.
	var slider_path := "user://sliders_test.txt"
	var day_then: float = game.settings.day_minutes
	_check(SliderFile.save(slider_path, game.settings) == "" and FileAccess.get_file_as_string(slider_path).contains("Day length = "),
		"the sliders save as a readable text file")
	game.settings.day_minutes = 3.0
	play.load_sliders(slider_path)
	_check(is_equal_approx(game.settings.day_minutes, day_then), "and load back from it (day length %.1f)" % game.settings.day_minutes)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slider_path))
	# Using a stat levels it up: 100 used for the first level, 200 more for the next.
	var start_level: int = beast.levels.magicko
	beast.used.magicko = 0.0
	beast._use("magicko", Balance.num("level_points") * (start_level + 1))
	_check(beast.levels.magicko == start_level + 1 and is_equal_approx(beast.level_cost("magicko"), minf(Balance.num("level_points") * (start_level + 2), 1000.0)),
		"using magicko levels it up, and the next level costs 100 more (level %d)" % (beast.levels.magicko + 1))
	var health_level: int = beast.levels.health
	beast.take_hit(Balance.num("level_points") * (health_level + 1) + 1.0, null)
	_check(beast.levels.health == health_level + 1, "losing health levels up health too")
	beast.hp = beast.max_hp
	beast.levels.stamina = 0
	beast.used.stamina = 0.0
	_check(is_equal_approx(beast.level_cost("stamina"), 100.0), "the first level costs 100")
	beast.levels.stamina = 20
	_check(is_equal_approx(beast.level_cost("stamina"), 1000.0), "and a level never costs more than 1,000")
	beast.levels.stamina = 0
	# The tortoise tires as it walks (its mind kept from sending it elsewhere).
	beast.mind.process_mode = Node.PROCESS_MODE_DISABLED
	beast.drop_load()
	beast.stamina = beast.max_stamina * 0.5
	var walk_to := beast.global_position
	for k in 24:
		var a := TAU * k / 24.0
		var p := beast.global_position + Vector3(cos(a), 0, sin(a)) * 25.0
		if game.terrain.is_inside(p.x, p.z) and game.terrain.is_dry(p.x, p.z):
			walk_to = p
			break
	beast.move_to(walk_to)
	# (Measured once it is under way: standing to turn, it gets its breath back.)
	for k in 8:
		if beast.speed > 0.6:
			break
		await _wait(0.25)
	var stamina_then := beast.stamina
	var top_speed := 0.0
	for k in 4:
		await _wait(0.5)
		top_speed = maxf(top_speed, beast.speed)
	_check(beast.stamina < stamina_then, "the tortoise's stamina drains slowly as it walks (%.1f -> %.1f, speed %.1f, snared %s, alert %s, hiding %s)" % [
		stamina_then, beast.stamina, top_speed, game.now < beast.snared_until, beast._alert, beast.hiding])
	beast.has_target = false
	beast.mind.process_mode = Node.PROCESS_MODE_INHERIT
	# Exploring is a long trip.
	var home_then := beast.mind.home
	_check(beast.mind._explore() and beast.target.distance_to(home_then) >= Balance.num("explore_least") - 0.1 and beast.mind.last_action == "explore",
		"exploring is a long trip from where it was sent (%.0f m)" % beast.target.distance_to(home_then))
	beast.has_target = false
	beast.mind._away = false
	_check(play.hud._creature_bars.size() == 3, "the creature's health, stamina and magicko bars are on the HUD")
	# Its fireball only singes the player's own people.
	var bystander := village.people()[0]
	bystander.hp = bystander.max_hp
	Explosion.detonate(bystander.global_position, Fireball.BLAST_RADIUS, Balance.num("creature_friendly_fire"))
	_put_out_fires()
	_check(bystander.is_alive() and bystander.hp < bystander.max_hp, "the creature's fireball does a tenth of the harm to villagers (%.0f of %.0f left)" % [bystander.hp, bystander.max_hp])
	# Fetching a tree once it knows how.
	await _wait(2.0)
	mind.knowledge.lumber = Balance.num("knowledge_lumber")
	# (Only lumber: it may have picked up enough about food or stone by now,
	# and a spell cast in between would hide the fetching.)
	for other: String in ["food", "stone"] + CreatureMind.SPELLS:
		Balance.values["knowledge_" + other] = 1.0e9
	mind.behavior.explore = -100.0
	# (Nothing else to choose between: a short wander is as likely as
	# fetching, and would only slow the check down.)
	Balance.values["wander_weight"] = 0.0
	mind._idle_timer = 0.0
	mind._away = false
	# (Standing still, so it is at home when it next thinks.)
	beast.has_target = false
	mind.home = beast.global_position
	# (The villagers may have felled every tree near the village by now:
	# plant one for it.)
	if mind._harvest_target("lumber") == null:
		var tree_rng := RandomNumberGenerator.new()
		var sapling := FloraFactory.create_tree(tree_rng)
		while sapling.footprint < 1.2:
			sapling.free()
			sapling = FloraFactory.create_tree(tree_rng)
		game.world_root.add_child(sapling)
		var spot_for := beast.global_position.lerp(village.center, 0.5) + Vector3(6, 0, 6)
		sapling.global_position = Vector3(spot_for.x, game.terrain.get_height(spot_for.x, spot_for.z), spot_for.z)
	var fetched := false
	for k in 30:
		await _wait(5.0)
		if mind.last_action.begins_with("lumber"):
			fetched = true
			break
	for other: String in ["food", "stone"] + CreatureMind.SPELLS:
		Balance.values["knowledge_" + other] = Balance.DEFAULTS["knowledge_" + other]
	Balance.values["wander_weight"] = Balance.DEFAULTS["wander_weight"]
	_check(fetched, "the creature fetches a tree for the storehouse (task %s, last action %s, knocked out %s, speed %.1f, %.0f m from the village)" % [
		mind._task, mind.last_action, beast.knocked_out, beast.speed, beast.global_position.distance_to(village.center)])
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
	# The cut brush leaves a sheer cliff, which nobody climbs and routes go round.
	var et: Terrain = game.terrain
	var hill := Vector3(-25, 0, -45)
	et.apply_brush(hill, 10.0, Terrain.Brush.RAISE, 8.0)
	var floor_h := et.get_height(hill.x + 13.0, hill.z)
	var climber := WorldPopulator.spawn_villager(game.world_root, et, Vector3(hill.x - 7.0, 0, hill.z), 0.01)
	climber.global_position = Vector3(hill.x - 7.0, et.get_height(hill.x - 7.0, hill.z), hill.z)
	_check(climber._slope_speed(Vector3.RIGHT) < 0.6 and is_equal_approx(climber._slope_speed(Vector3.LEFT), 1.0),
		"walking up a steep slope is slow (%.2f of full speed)" % climber._slope_speed(Vector3.RIGHT))
	et.apply_brush(Vector3(hill.x + 6.0, floor_h, hill.z), 5.0, Terrain.Brush.CUT, 1.0, floor_h)
	_check(et.get_height(hill.x, hill.z) - et.get_height(hill.x + 2.0, hill.z) > 3.0, "the cut brush slices a hill into a sheer cliff")
	climber.global_position = Vector3(hill.x + 1.5, floor_h, hill.z)
	_check(climber._is_cliff(Vector3.LEFT), "a cliff cannot be climbed")
	var grid := game.path_grid()
	var below := Vector3(hill.x + 4.0, 0, hill.z)
	var above := Vector3(hill.x - 4.0, 0, hill.z)
	var way := grid.find(below, above)
	var walked := 0.0
	var last_point := below
	for point in way:
		walked += Vector2(point.x - last_point.x, point.z - last_point.z).length()
		last_point = point
	_check(not grid.clear_line(below, above) and walked > 7.0, "the way up goes round the cliff (%.0f m for 8 m)" % walked)
	climber.queue_free()
	_check(EditorMode.TOOL_NAMES.has("Expand island") and EditorMode.TOOL_NAMES.has("Cut cliff") and EditorMode.TOOL_NAMES.has("Goblin path"),
		"the editor has expand-island, cut and goblin-path brushes")
	# Goblin paths, drawn from the cave to each start.
	for marker in get_tree().get_nodes_in_group("start_markers"):
		var m3 := marker as Node3D
		editor._stroke = PackedVector2Array([Vector2(45, -45), Vector2(30, -20), Vector2(m3.global_position.x, m3.global_position.z)])
		editor._drawing = true
		editor._finish_path()
	_check(editor._paths.size() == placed and (editor.map_data().paths as Array).size() == placed, "goblin paths join the cave to the start locations (%d)" % editor._paths.size())
	editor._stroke = PackedVector2Array([Vector2(-60, 60), Vector2(-50, 50)])
	editor._drawing = true
	editor._finish_path()
	_check(editor._paths.size() == placed, "a path that joins nothing is not kept")
	# Ctrl+Z undoes the last change.
	var probe_h := et.get_height(12.0, 12.0)
	editor._begin_undo()
	et.apply_brush(Vector3(12, 0, 12), 5.0, Terrain.Brush.RAISE, 4.0)
	_check(et.get_height(12.0, 12.0) > probe_h + 1.0, "the raise brush raises the ground")
	editor.undo()
	_check(is_equal_approx(et.get_height(12.0, 12.0), probe_h) and get_tree().get_nodes_in_group("start_markers").size() == placed
		and editor._paths.size() == placed, "undo puts the ground back and keeps the rest")
	# The map keeps the palette chosen for it.
	editor._set_palette(2)
	_check(int(editor.map_data().palette) == 2, "the map remembers its palette")
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
	_check(Art.palette_index == 2, "the map is played in its own palette")
	_check(get_tree().get_nodes_in_group("buildings").is_empty(), "saved map has no buildings")
	_check(get_tree().get_nodes_in_group("start_markers").size() == placed, "start banners shown")
	_check(get_tree().get_nodes_in_group("goblins").size() > 0 == (data.caves.size() > 0), "goblins live in the caves")
	var s0: Vector2 = play._info.starts[0]
	play._found(Vector3(s0.x, game.terrain.get_height(s0.x, s0.y), s0.y), 0)
	_check(play.village.population() == roundi(Balance.num("start_villagers")), "starting villagers spawned (%d)" % play.village.population())
	var raider := get_tree().get_nodes_in_group("goblins")[0] as Villager
	var route := play.raids._route_for(raider.home)
	_check(play.raids.paths.size() == placed and route.size() >= 2, "goblins take the map's painted path to the village (%d points)" % route.size())
	await _wait(3.0)
	_check(get_tree().get_nodes_in_group("start_markers").is_empty(), "banners removed after choosing")

	# 5. A large random island builds. This time with the squirrel, growing
	# at the normal rate: it starts at 15% of its size.
	game.creature_kind = "squirrel"
	game.settings.creature_grow_minutes = 30.0
	await _open(game, "play", "", 768)
	_check(Terrain.SIZE == 768 and Terrain.CHUNKS == 24 and is_equal_approx(Terrain.ISLAND_RADIUS, 348.0), "large map: twice the old island radius")
	play = get_tree().current_scene.get_node("Controller") as PlayMode
	_check(Art.palette_index == game.palette_index, "a random island goes back to the player's palette")
	var t0: Vector2 = play._info.starts[0]
	play._found(Vector3(t0.x, game.terrain.get_height(t0.x, t0.y), t0.y), 0)
	var squirrel := play.creature
	_check(squirrel.kind == "squirrel" and squirrel.size < 0.16 and is_equal_approx(squirrel.scale.x, squirrel.size), "the squirrel starts at 15%% of its size (%.2f)" % squirrel.size)
	squirrel.move_to(squirrel.global_position + Vector3(6, 0, 6))
	await _wait(60.0)
	_check(squirrel.size > 0.17 and squirrel.size < 0.2, "the squirrel grows towards full size over 30 minutes (%.3f after 1 minute)" % squirrel.size)
	# A long way is run, on all fours, and that uses stamina.
	squirrel.mind.process_mode = Node.PROCESS_MODE_DISABLED
	squirrel.drop_load()
	squirrel.stamina = squirrel.max_stamina
	squirrel._tired = false
	squirrel.running = false
	squirrel.has_target = false
	var run_to := squirrel.global_position
	for k in 24:
		var a := TAU * k / 24.0
		var p := squirrel.global_position + Vector3(cos(a), 0, sin(a)) * 45.0
		if game.terrain.is_inside(p.x, p.z) and game.terrain.is_dry(p.x, p.z):
			run_to = p
			break
	squirrel.move_to(run_to)
	await _wait(3.0)
	var walk_speed := squirrel._top_speed()
	_check(squirrel.running and squirrel.speed > walk_speed * 1.2,
		"the squirrel runs a long journey, half as fast again (%.1f against %.1f)" % [squirrel.speed, walk_speed])
	_check(squirrel.stamina < squirrel.max_stamina, "running uses stamina (%.0f left)" % squirrel.stamina)
	squirrel.stamina = 0.2
	await _wait(1.0)
	_check(not squirrel.running and squirrel.has_target, "out of stamina, it drops back to a walk")
	squirrel.has_target = false

	# 6. The raven, which flies, and the goblins' balrog.
	game.creature_kind = "raven"
	game.settings.creature_grow_minutes = 0.02
	await _open(game, "play", "", 384)
	play = get_tree().current_scene.get_node("Controller") as PlayMode
	play.day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	var r0: Vector2 = play._info.starts[0]
	play._found(Vector3(r0.x, game.terrain.get_height(r0.x, r0.y), r0.y), 0)
	await _wait(3.0)
	var raven := play.creature
	raven.mind.process_mode = Node.PROCESS_MODE_DISABLED
	_check(raven.kind == "raven" and raven.size > 0.99 and is_equal_approx(raven.max_hp, Balance.num("raven_health")), "the raven is the player's creature")
	# A short walk on the flat is walked.
	var hop_to := raven.global_position
	for k in 24:
		var a := TAU * k / 24.0
		var p := raven.global_position + Vector3(cos(a), 0, sin(a)) * 12.0
		if game.terrain.is_dry(p.x, p.z) and absf(game.terrain.get_height(p.x, p.z) - raven.global_position.y) < 0.5:
			hop_to = p
			break
	raven.move_to(hop_to)
	await _wait(1.0)
	_check(hop_to != raven.global_position and not raven.flying, "the raven walks a short way on the flat")
	await _wait(8.0)
	# A long way is flown.
	var flight_to := raven.global_position
	for k in 24:
		var a := TAU * k / 24.0
		var p := raven.global_position + Vector3(cos(a), 0, sin(a)) * 70.0
		if game.terrain.is_inside(p.x, p.z) and game.terrain.is_dry(p.x, p.z):
			flight_to = p
			break
	raven.move_to(flight_to)
	await _wait(4.0)
	var up := raven.global_position.y - game.terrain.get_height(raven.global_position.x, raven.global_position.z)
	_check(raven.flying and raven.is_flying() and up > 5.0, "the raven flies a journey longer than raven_fly_distance (%.1f m up)" % up)
	for k in 30:
		if not raven.flying and not raven.has_target:
			break
		await _wait(1.0)
	_check(raven.stamina < raven.max_stamina, "flying uses stamina (%.0f left)" % raven.stamina)
	up = raven.global_position.y - game.terrain.get_height(raven.global_position.x, raven.global_position.z)
	_check(not raven.flying and up < 0.5 and Vector2(raven.global_position.x - flight_to.x, raven.global_position.z - flight_to.z).length() < 3.0, "the raven lands where it was sent")
	# When it runs from a battle, it flies.
	var scare := play.raids.spawn_at(get_tree().get_nodes_in_group("caves")[0] as Node3D)
	scare.set_process(false)
	scare.global_position = raven.global_position + Vector3(3, 0, 0)
	_check(raven.run_from_battle(), "the raven finds somewhere to run from a battle to")
	await _wait(2.0)
	_check(raven.is_fleeing() and raven.flying and not raven.knocked_out, "a raven that runs from battle takes to the air")
	scare.queue_free()
	for k in 30:
		if not raven.flying:
			break
		await _wait(1.0)
	raven.stamina = raven.max_stamina

	# The balrog hatches small, guards its cave and grows.
	game.settings.creature_grow_minutes = 30.0
	Balance.values["balrogs"] = 1.0
	play.raids._balrog_timer = 0.0
	await _wait(0.5)
	var fiends := get_tree().get_nodes_in_group("balrogs")
	_check(fiends.size() == 1, "a balrog hatches at a goblin cave")
	if fiends.size() == 1:
		var balrog := fiends[0] as Balrog
		var bones_then := play.village.amount("bones")
		_check(balrog.size < 0.16 and balrog.hostile and absf(balrog.max_hp - Balance.num("balrog_health") * 0.3) < 5.0, "the balrog starts at 15%% of its size (%.2f)" % balrog.size)
		_check(balrog._top_speed() < 2.6 and balrog._top_speed() > 2.0, "the balrog is a little slower than a marching goblin")
		play.raids.start_raid()
		_check(not balrog.raiding, "a growing balrog stays at its cave during a raid")
		play.raids.end_raid()
		balrog._fire_ready_at = 0.0
		raven.place(balrog.global_position + Vector3(0, 0, 26), 0.0)
		balrog._try_fireball()
		_check(_fireballs() == 0, "a small balrog cannot cast fireball")
		balrog.age = 30.0 * 60.0 * 0.5
		await _wait(0.2)
		raven.place(balrog.global_position + Vector3(0, 0, 26), 0.0)
		balrog._alert = true
		balrog._try_fireball()
		_check(balrog.size > 0.5 and _fireballs() == 1, "at half size the balrog casts fireball (size %.2f)" % balrog.size)
		raven.place(Vector3(r0.x, 0, r0.y), 0.0)
		balrog.auto_move(balrog.global_position + Vector3(0, 0, 60))
		_check(not balrog.flying, "the balrog cannot fly")
		balrog.age = 30.0 * 60.0
		await _wait(0.3)
		_check(balrog.grown() >= 1.0, "the balrog grows to full size like the creature")
		play.raids.start_raid()
		_check(balrog.raiding and balrog.is_threat() and play.raids.marching == 1, "a full-grown balrog marches with the raid")
		play.raids.end_raid()
		_check(not balrog.raiding, "the balrog goes home in the morning")
		# The two giants go for each other with their fists.
		# (The raven is put back to full size: the slower growing set above shrank it.)
		raven.age = 30.0 * 60.0
		await _wait(0.3)
		raven.hp = raven.max_hp
		raven.fleeing_until = 0.0
		raven.place(balrog.global_position + Vector3(0, 0, 7), PI)
		for k in 20:
			if balrog.hp < balrog.max_hp and raven.hp < raven.max_hp:
				break
			await _wait(1.0)
		_check(balrog.hp < balrog.max_hp and raven.hp < raven.max_hp, "the creature and the balrog fight each other (%d and %d health lost)" % [roundi(raven.max_hp - raven.hp), roundi(balrog.max_hp - balrog.hp)])
		balrog.take_hit(1.0e6, null)
		_check(balrog.knocked_out and get_tree().get_nodes_in_group("balrogs").is_empty() and play.village.amount("bones") > bones_then, "a balrog at no health is dead, and leaves bones")
	Balance.values["balrogs"] = 0.0
	game.creature_kind = "tortoise"

	DirAccess.remove_absolute(path)
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
	else:
		print("SMOKE TEST FAILED:\n  " + "\n  ".join(_failures))
		get_tree().quit(1)


func _fireballs() -> int:
	var n := 0
	for node in Game.world_root.get_children():
		if node is Fireball:
			n += 1
	return n


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
			play._place_kind = "treehouse"
			if play._placement_problem(p, 4.0) == "":
				return p
	return Vector3.INF


func _put_out_fires() -> void:
	Game.fire.extinguish_in(Vector3.ZERO, 2000.0)
	for node in get_tree().get_nodes_in_group("destructibles"):
		(node as Destructible).extinguish()


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
