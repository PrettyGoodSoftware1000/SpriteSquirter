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
	# The test's checks were made with villagers making 30 magicko a minute
	# (now 0.5: the village soon runs dry, and the creature makes blood
	# sacrifices of the villagers the other checks need).
	game.settings.magicko_rate = 30.0
	# The test's timings were made with a 24-minute day and night.
	game.settings.day_minutes = 16.0
	game.settings.night_minutes = 8.0
	# Goblins spawn and build as they used to, for the raid checks.
	game.settings.goblin_rate = 2.0
	game.settings.goblin_build_speed = 4.0
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
	# No saplings until their own checks (so the trees stay as they were).
	game.settings.sapling_rate = 0.0
	# No balrog until its own checks at the end, and the tortoise keeps
	# out of its shell until then too.
	Balance.values["balrogs"] = 0.0
	Balance.values["shell_damage_share"] = 1.0

	# 1. The menu.
	# The spell bar's memory goes to a file of its own while testing.
	SpellLayout.path = "user://spell_bar_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SpellLayout.path))
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
	play.creature.growth_paid = 10  # (its growth is paid for, so it grows)
	var village := play.village
	var first_people := village.population()
	_check(first_people == roundi(Balance.num("start_villagers")), "the village starts with 20 villagers (%d)" % first_people)
	_check(not get_tree().get_nodes_in_group("player_buildings").is_empty(), "village site buildings join the player")
	var free_store := false
	# (Whichever model Names.txt gives the Storehouse's job.)
	var store_kind := BuildingCatalog.kind_for_role("store", "store")
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.get_meta("kind", "") == store_kind and (b as Node3D).global_position.distance_to(village.center) < 45.0:
			free_store = true
	_check(free_store, "a free Storehouse stands at the start location")
	_check(BuildingCatalog.housing(store_kind) == roundi(Balance.num("storehouse_housing")), "a Storehouse houses storehouse_housing (%d)" % BuildingCatalog.housing(store_kind))
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
	_check(village.built_shrines() == 0, "the village site's Singing Stones make no animus: 1 a minute to begin with (%d there)" % village.shrines().size())
	play._set_mode(PlayMode.Mode.COMMAND)
	_check(play.hud._hint.text == "", "no hint text while nothing is in hand")
	_check(village.influence() > Game.settings.influence_start and village.in_territory(village.center + Vector3(village.influence() - 1.0, 0, 0))
		and not village.in_territory(village.center + Vector3(village.influence() + 1.0, 0, 0)), "the village's influence grows with its people (%.0f m)" % village.influence())
	_check(Balance.values.size() >= Balance.DEFAULTS.size() and FileAccess.file_exists(Balance.PATH), "balancing.txt is read")
	_check(str(ProjectSettings.get_setting("application/config/version", "")) != "", "the game has a version number")
	play.pause_menu.open()
	_check(get_tree().paused, "Esc's pause menu stops the game")
	play.pause_menu.close()
	_check(not get_tree().paused, "and lets it go again")
	var before: Dictionary = village.resources.duplicate()
	_check(not get_tree().get_nodes_in_group("rocks").is_empty(), "boulder fields placed (%d boulders)" % get_tree().get_nodes_in_group("rocks").size())
	_check(is_equal_approx(DayCycle.NIGHT_START, 0.75) and DayCycle.MIDNIGHT == DayCycle.NIGHT_START, "night starts at midnight")
	_check(is_equal_approx(Game.DEFAULT_SETTINGS.day_minutes, 10.0) and is_equal_approx(Game.DEFAULT_SETTINGS.night_minutes, 8.0)
		and play.hud._setting_sliders.has("day_minutes") and play.hud._setting_sliders.has("night_minutes"),
		"days are 10 minutes and nights 8 by default, each with a slider")
	# A wheat field: sown by a farmer (only farmers sow), then it grows by itself.
	var field := CropField.new()
	field.setup(Vector2(8, 8))
	field.position = village.center + Vector3(0, 0, 14)
	game.world_root.add_child(field)
	village.change_quota("food", 1)
	_check(village.quota.food == 1, "a worker can be set to farm")
	# (Checked after a minute: in two the field can be reaped and under the plough again.)
	await _wait(60.0)
	_check(field.stage != CropField.Stage.SOWING or field.progress > 0.3, "the farmer sows the field (stage %d, %.2f)" % [field.stage, field.progress])
	play._cursor_hit = field.global_position
	play._hover_field()
	_check(field._label != null and field._label.visible and field._label.text.contains("% to harvest") or field.stage == CropField.Stage.RIPE,
		"the mouse over a field shows how far it is to harvest (%s)" % (field._label.text if field._label else "none"))
	_check(Game.DEFAULT_SETTINGS.has("crop_growth_rate"), "a slider sets how fast crops grow")
	# (Ripe at once: it takes crop_grow_seconds by itself.)
	if field.stage == CropField.Stage.GROWING:
		field.progress = 0.999
	await _wait(60.0)
	var jobs := {}
	for v in village.people():
		jobs[v.job] = jobs.get(v.job, 0) + 1
	print("  jobs %s" % jobs)
	_check(not jobs.has("food"), "food is gathered only from crop fields (no foraging)")
	_check(village.resources.lumber >= 0.0 and is_equal_approx(Balance.num("start_lumber"), Balance.values.get("start_lumber", 100.0)), "the village starts with balancing.txt's resources")
	for res in ["lumber", "stone", "magicko"]:
		_check(village.resources[res] > before[res], "%s is gathered (%.1f -> %.1f)" % [res, before[res], village.resources[res]])
	# (Food is eaten as fast as it comes in while a child is born every 5
	# seconds, so count what was carried to the store.)
	_check(village._stored.get("food", 0.0) > 20.0, "food is gathered (%.1f carried in)" % village._stored.get("food", 0.0))
	_check(village.population() > first_people or village.population() >= village.housing(), "a child is born")

	# The day stops while building, armies and hunger are tested, so that
	# midnight's raid does not come in the middle of them.
	play.day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	# (Enough to pay for a Home, whatever balancing.txt makes it cost.)
	for res in ["lumber", "stone", "food"]:
		village.give(res, 300.0, false)
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
		# Spells are researched at the Wizardry tower first. (Bless and
		# Condemn, which came with the creature's growth, are set aside.)
		for growth_spell: String in ["bless", "condemn"]:
			village.spells_known.erase(growth_spell)
			var slot_g := village.spell_slots.find(growth_spell)
			if slot_g >= 0:
				village.spell_slots[slot_g] = ""
		play.hud.set_spell_slots(village.spell_slots)
		play._spell_key(gnomes)
		_check(play._armed < 0 and not village.knows_spell("gnomes") and not village.knows_spell("fireball") and village.spell_at(0) == ""
			and play.hud._spell_slot_of[gnomes] == -1, "every spell must be researched before it is on the spell bar or cast")
		# (The village site's own Wizardry towers, if it has any, are set aside.)
		var site_towers: Array[Node] = []
		for node in get_tree().get_nodes_in_group("player_buildings"):
			if BuildingCatalog.role(node.get_meta("kind", "")) == "wizard":
				site_towers.append(node)
				node.remove_from_group("player_buildings")
		_check(village.start_spell_research("gnomes") != "", "spells are researched at a Wizardry tower")
		var tower_kind := BuildingCatalog.kind_for_role("wizard", "moon_tower")
		var shrine := BuildingFactory.create(tower_kind, RandomNumberGenerator.new())
		game.world_root.add_child(shrine)
		shrine.set_meta("kind", tower_kind)
		shrine.global_position = village.center + Vector3(14, 0, 10)
		shrine.add_to_group("player_buildings")
		play._cursor_hit = shrine.global_position
		play._on_left_click()
		_check(play.hud.is_spell_research_open() and not play.hud._tower_research_rows.is_empty(),
			"clicking a Wizardry tower opens its spell research, with Overcast in it")
		play.hud.show_spell_research(false)
		village.give("animus", 10.0)
		var animus_then := village.amount("animus")
		_check(village.start_spell_research("gnomes") == "" and village.amount("animus") == animus_then - 1,
			"the first spell costs 1 animus to research")
		_check(village.start_spell_research("rain") != "", "one spell at a time for one Wizardry tower")
		village.spell_job("gnomes").t = SpellBook.research_seconds("gnomes") - 0.5
		await _wait(1.0)
		_check(village.knows_spell("gnomes") and not village.knows_spell("rain") and village.spell_at(0) == "gnomes"
			and play.hud._spell_slot_of[gnomes] == 0, "the Wizardry tower teaches the spell, and it appears on the spell bar")
		animus_then = village.amount("animus")
		_check(village.start_spell_research("rain") == "" and village.amount("animus") == animus_then - 2, "the next spell costs 2 animus")
		var shrine_2 := BuildingFactory.create(tower_kind, RandomNumberGenerator.new())
		game.world_root.add_child(shrine_2)
		shrine_2.set_meta("kind", tower_kind)
		shrine_2.global_position = village.center + Vector3(-16, 0, 12)
		shrine_2.add_to_group("player_buildings")
		_check(village.start_spell_research("roots") == "" and village.spell_jobs.size() == 2 and village.start_spell_research("lightning") != "",
			"two Wizardry towers research two spells at once (and no more)")
		await _wait(1.0)
		_check(village.spell_job("rain").t > 0.5 and village.spell_job("roots").t > 0.5, "both at the same time")
		village.spell_jobs.clear()
		shrine_2.queue_free()
		for node in site_towers:
			node.add_to_group("player_buildings")
		village.learn_all_spells()
		play.hud.set_spell_slots(village.spell_slots)
		_check(village.knows_spell("rain") and village.knows_spell("charm") and village.spell_at(0) == "gnomes" and village.spell_at(1) != "",
			"the dev menu can teach every spell (after the ones already known)")
		# A spell can be dragged to any place on the bar, rows 2 and 3 too.
		var fire_k := SpellBook.index_of("fireball")
		SpellLayout.set_rows(2)
		play.hud._show_spell_rows()
		var bar_lines := play.hud._spell_lines
		_check(bar_lines[1].visible and not bar_lines[2].visible and bar_lines[1].get_index() < bar_lines[0].get_index()
			and play.hud._remove_row_button.visible, "the Ctrl row opens above the first, and a - button closes it")
		play.hud.spell_moved.emit(fire_k, 12)
		_check(village.spell_at(12) == "fireball" and play._key_of(fire_k) == "Ctrl+3" and play.hud._spell_slot_of[fire_k] == 12
			and play.hud._spell_lines[1].visible and play.hud._spell_keys[fire_k].text == "3", "a spell dragged to the second row is cast with Ctrl and its number")
		play.hud.spell_moved.emit(fire_k, 0)
		_check(village.spell_at(0) == "fireball" and village.spell_at(12) == "gnomes", "dragging a spell onto another swaps them")
		_check(SpellLayout.slot_of("fireball") == 0 and SpellLayout.slot_of("gnomes") == 12, "where the spells are is remembered for the next game")
		play.hud._remove_row_button.pressed.emit()
		_check(not bar_lines[1].visible and SpellLayout.row_count() == 1 and not play.hud._remove_row_button.visible, "the - button closes the extra rows")
		_check(PlayMode._bar_column(KEY_0) == 9 and PlayMode._bar_column(KEY_KP_3) == 2 and PlayMode._bar_column(KEY_A) == -1,
			"the number keys and the numpad pick the spell bar's places")
		_check(play.hud._spell_buttons[fire_k].tooltip_text == "", "the spell bar has no tooltips")
		shrine.queue_free()
		play._cursor_hit = spot
		magicko_before = village.amount("magicko")
		play._spell_key(gnomes)
		play._cursor_hit = spot
		play._click_spell()
		var crew_g := get_tree().get_nodes_in_group("gnomes")
		_check(crew_g.size() == 5 and magicko_before - village.amount("magicko") == SpellBook.cost("gnomes"), "Gnomish Subcontractors: 5 gnomes for spell_cost_gnomes")
		play._cooldowns[gnomes] = 0.0
		var magicko_again := village.amount("magicko")
		play._spell_key(gnomes)
		play._cursor_hit = spot
		play._click_spell()
		_check(get_tree().get_nodes_in_group("gnomes").size() == 5 and village.amount("magicko") == magicko_again
			and play.hud._prompt.text == Texts.line("gnomes_dont_stack"), "Gnomish Subcontractors don't stack on one building (and say so)")
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
		_check((play.hud._jobs.warrior.count as Label).text == "0/0" and not (play.hud._jobs.warrior.row as Control).visible,
			"Warriors are not shown without a Town guard (%s)" % (play.hud._jobs.warrior.count as Label).text)
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
	_check(is_equal_approx(village.train_seconds("warrior"), Balance.num("warrior_training_seconds")), "a warrior trains in warrior_training_seconds")
	Game.settings.training_time = 2.0
	_check(is_equal_approx(village.train_seconds("warrior"), 2.0 * Balance.num("warrior_training_seconds")), "the training time slider stretches it")
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
	# (The village site may have come with towers of its own.)
	var wizards_allowed := village.max_count("wizard")
	var rocks := BuildingFactory.create("moon_tower", RandomNumberGenerator.new())
	game.world_root.add_child(rocks)
	rocks.set_meta("kind", "moon_tower")
	rocks.global_position = village.center + Vector3(-12, 0, 10)
	rocks.add_to_group("player_buildings")
	_check(village.max_count("wizard") == wizards_allowed + PlayerVillage.WIZARDS_PER_ROCKS, "a Wizardry tower allows 2 wizards (%d)" % village.max_count("wizard"))
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
	# (Round the grey rock slopes, which can be a long way.)
	var closed_in := false
	for k in 12:
		await _wait(5.0)
		closed_in = not is_instance_valid(first) or not first.is_alive() or first.global_position.distance_to(village.center) < gap_before - 10.0
		if closed_in:
			break
	_check(closed_in, "raiders close in on the village")
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
	var left := 0
	for k in 12:
		await _wait(2.0)
		left = 0
		for g in bait:
			if is_instance_valid(g) and (g as Villager).is_alive():
				left += 1
		if left == 0:
			break
	_check(left == 0, "the tortoise kills goblins in reach (%d of %d left)" % [left, bait.size()])
	await _wait(60.0)
	play.raids.end_raid()
	_check(get_tree().get_nodes_in_group("raiders").is_empty(), "the raid ends in the morning")
	var rate := play.raids.spawn_rate()
	play.raids.nights += 1
	_check(is_equal_approx(play.raids.spawn_rate(), rate), "the nights alone do not make the goblins spawn faster (only their buildings do)")
	var before_goblins := get_tree().get_nodes_in_group("goblins").size()
	game.settings.goblin_rate = 12.0
	# (The creature holds still, so it eats none of them meanwhile.)
	play.creature.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(11.0)
	play.creature.process_mode = Node.PROCESS_MODE_INHERIT
	game.settings.goblin_rate = 2.0
	_check(get_tree().get_nodes_in_group("goblins").size() > before_goblins, "caves keep spawning goblins")
	# Goblin population bounce back: with fewer than 5 left, the caves
	# spawn 5 a minute until there are 6 again.
	game.settings.goblin_rate = 0.0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if not g.ogre:
			g.remove_from_group("goblins")
			g.queue_free()
	play.creature.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(1.0)
	_check(play.raids.bouncing, "with fewer than %d goblins the goblin population bounces back" % roundi(Balance.num("goblin_bounce_below")))
	for k in 12:
		await _wait(10.0)
		if not play.raids.bouncing:
			break
	_check(play.raids.goblin_count() >= roundi(Balance.num("goblin_bounce_until")) and not play.raids.bouncing,
		"5 a minute until there are %d again (%d)" % [roundi(Balance.num("goblin_bounce_until")), play.raids.goblin_count()])
	play.creature.process_mode = Node.PROCESS_MODE_INHERIT
	game.settings.goblin_rate = 2.0

	# Hunger: no births without food, then people starve. The wheat is held
	# growing so no harvest comes in.
	for node in get_tree().get_nodes_in_group("fields"):
		var f := node as CropField
		f.stage = CropField.Stage.GROWING
		f.progress = 0.0
		f.process_mode = Node.PROCESS_MODE_DISABLED
	game.settings.food_rate = 0.0
	village.resources.food = 0.0
	# (A warning may have floated up already, earlier in the test.)
	village._food_warned_at = -INF
	for node in get_tree().get_nodes_in_group("food_warnings"):
		node.remove_from_group("food_warnings")
	# Food already on its way to the store would reset the hunger clock.
	for v in village.people():
		if v.carry_kind == "food":
			v.carry = 0.0
	var fed := village.population()
	await _wait(1.0)
	_check(village.next_birth_in() < 0.0, "no births without food")
	_check(get_tree().get_nodes_in_group("food_warnings").size() == 1 and not play.hud._warning.text.contains("food"),
		"\"Out of food\" floats up over the Storehouse, not in the village panel")
	await _wait(5.5)
	_check(get_tree().get_nodes_in_group("food_warnings").size() == 0, "and not again within %d seconds" % Balance.num("food_warning_seconds"))
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
	# watchtowers: none of either until those are built. (The goblins build
	# fast, so take away anything they have put up already.)
	play.raids.end_raid()
	for group in ["goblin_buildings", "goblin_sites", "ogres", "bats"]:
		for node in get_tree().get_nodes_in_group(group):
			node.remove_from_group(group)
			node.queue_free()
	play.raids._build_timer = 0.0
	await _wait(0.2)
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
	var blood_end := village.blood_until
	await _wait(1.0)
	village.sacrifice(village.people()[0].global_position)
	_check(village.blood_until < blood_end + PlayerVillage.BLOOD_SECONDS * 0.5, "a second sacrifice does not stack")
	_check(is_equal_approx(village.blood_boost(), Balance.num("blood_sacrifice_boost")), "it speeds magicko up blood_sacrifice_boost times")
	var blood_k := SpellBook.index_of("blood")
	var had_overcast := village.has_research("overcast")
	village.researched["overcast"] = true
	play._cooldowns[blood_k] = 5.0
	_check(not play.spell_ready(blood_k) and not play.overcast_open(blood_k) and play.spell_state(blood_k) == 1,
		"Blood Sacrifice cannot be overcast (no lightning round its cost)")
	play._cooldowns[blood_k] = 0.0
	if not had_overcast:
		village.researched.erase("overcast")
	village.researched["blood_x3"] = true
	_check(is_equal_approx(village.blood_boost(), Balance.num("blood_sacrifice_upgraded_boost")) and Research.find("blood_x3").place == "necro"
		and (Research.find("blood_x3").cost as Dictionary).get("animus", 0) == 10,
		"the Necromancer tower's upgrade (10 animus) makes it blood_sacrifice_upgraded_boost times")
	village.researched.erase("blood_x3")
	play.hud.set_resources(village, "")
	_check((play.hud._rate_labels.bones as Label).text == "" and not play.hud._warning.visible, "bones show only their total, and the village panel has no red warning")
	# A Windmill adds windmill_food_rate to the food rate (one is enough).
	var plain_rate := village.food_rate()
	var mills: Array[Destructible] = []
	for n in 2:
		var mill := BuildingFactory.create("windmill", RandomNumberGenerator.new())
		game.world_root.add_child(mill)
		mill.set_meta("kind", "windmill")
		mill.global_position = village.center + Vector3(60 + n * 10, 0, 60)
		mill.add_to_group("player_buildings")
		mills.append(mill)
	_check(is_equal_approx(village.food_rate(), plain_rate + Balance.num("windmill_food_rate")) or plain_rate > game.settings.food_rate,
		"a Windmill adds windmill_food_rate to the food rate per worker, and a second adds nothing (%.1f -> %.1f)" % [plain_rate, village.food_rate()])
	for mill in mills:
		mill.free()
	await _wait(1.0)

	# Rain makes wheat grow faster.
	field.stage = CropField.Stage.GROWING
	field.progress = 0.0
	var wet := RainCloud.new()
	game.world_root.add_child(wet)
	wet.cast(field.global_position)
	await _wait(10.0)
	_check(field.stage != CropField.Stage.GROWING or field.progress > 10.0 / Balance.num("crop_grow_seconds") * 1.8, "rain speeds up the wheat (%.2f)" % field.progress)

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
	_check(is_equal_approx(Creature.SPECIES.squirrel.speed, Creature.SPECIES.tortoise.speed * 1.3), "the squirrel is 30% faster")
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
	_check(village.amount("animus") == 2, "the village gets 1 animus a minute, and a Shrine 1 more (%.2f)" % village.resources.animus)
	play.resurrect()
	_check(beast.knocked_out, "no resurrection without 5 animus")
	village.give("animus", 10.0)
	play.resurrect()
	_check(not beast.knocked_out and is_equal_approx(beast.hp, beast.max_hp) and village.amount("animus") == 7
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
	_check(not village.barrows, "a Blacksmith alone brings no wheelbarrows: they are researched")
	for res in ["lumber", "stone", "food"]:
		village.give(res, 600.0)
	_check(village.max_count("archer") == 0, "no archers before bows")
	_check(village.start_research("bows") == "", "bows can be researched")
	_check(village.start_research("axes_1") != "", "one research at a time")
	village.research_job("bows").t = Research.find("bows").seconds - 2.0
	await _wait(4.0)
	_check(village.has_research("bows") and village.max_count("archer") >= PlayerVillage.ARCHERS_PER_GUARD,
		"bows allow 2 archers per Town guard (%d allowed)" % village.max_count("archer"))
	_check(is_equal_approx(Research.find("swords").seconds, 300.0), "sharper swords take 5 minutes")
	_check(village.start_research("picks_2") != "" or not village.researching("smith").is_empty(), "a tool's second tier waits for its first")
	play.hud.show_research_menu(true, "smith")
	var tier_rows: Dictionary = play.hud._research_rows
	_check(tier_rows.pitchforks_1.row.visible and not tier_rows.pitchforks_2.row.visible and not tier_rows.pitchforks_3.row.visible,
		"the Blacksmith's menu hides a tool's next tier until the one before is researched")
	for id: String in ["swords", "wheelbarrows", "pitchforks_1", "picks_1", "axes_1"]:
		for res in ["lumber", "stone", "food"]:
			village.give(res, 300.0)
		village.start_research(id)
		if not village.research_job(id).is_empty():
			village.research_job(id).t = Research.find(id).seconds - 0.5
		await _wait(1.5)
	play.hud.update_research(village)
	_check(tier_rows.pitchforks_2.row.visible and not tier_rows.pitchforks_3.row.visible, "and shows it once that one is done")
	_check(not tier_rows.pitchforks_1.row.visible and not tier_rows.swords.row.visible, "researched upgrades leave the menu")
	_check(Research.describe(Research.find("picks_2")).contains("% of base stone gathering speed") and Research.describe(Research.find("picks_2")).contains(
		Research._pct(100.0 + 2.0 * Balance.num("tool_tier_bonus") * 100.0) + "%"), "each tool tier says what it adds to the base speed (%s)" % Research.describe(Research.find("picks_2")))
	play.hud.update_spell_research(village)
	var known_row: Dictionary = play.hud._spell_research_rows.get("gnomes", {})
	_check(not known_row.is_empty() and not (known_row.row as Control).visible, "known spells leave the Shrine's menu")
	play.hud.show_research_menu(false)
	_check(village.barrows and is_equal_approx(village.tool_bonus("stone"), 1.0 + Balance.num("tool_tier_bonus")), "wheelbarrows, and a tool's first tier")
	for id: String in ["pitchforks_2", "pitchforks_3", "picks_2", "picks_3", "axes_2", "axes_3"]:
		for res in ["lumber", "stone", "food"]:
			village.give(res, 300.0)
		village.start_research(id)
		if not village.research_job(id).is_empty():
			village.research_job(id).t = Research.find(id).seconds - 0.5
		await _wait(1.5)
	_check(village.has_research("swords") and absf(village.tool_bonus("food") - 1.5) < 0.01
		and absf(village.tool_bonus("stone") - 1.5) < 0.01 and absf(village.tool_bonus("lumber") - 1.5) < 0.01,
		"swords researched, and all three tool tiers: 50%% faster (%.3f)" % village.tool_bonus("food"))
	# Two Blacksmiths research two things at once.
	var smithy_2 := BuildingFactory.create("blacksmith", RandomNumberGenerator.new())
	game.world_root.add_child(smithy_2)
	smithy_2.global_position = village.center + Vector3(-22, 0, -14)
	smithy_2.add_to_group("player_buildings")
	village.researched.erase("swords")
	village.researched.erase("bows")
	for res in ["lumber", "stone", "food"]:
		village.give(res, 600.0)
	_check(village.start_research("swords") == "" and village.start_research("bows") == "" and village.researching("smith").size() == 2,
		"two Blacksmiths research two things at once")
	village.researching("smith").clear()
	village.researched["swords"] = true
	village.researched["bows"] = true
	smithy_2.queue_free()
	# Overcast is researched at a Wizardry tower (see the spells' checks).
	_check(Research.find("overcast").place == "wizard" and Research.find("overcast").cost.get("animus", 0) == 10, "Overcast is researched at the Wizardry tower for 10 animus")
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
	_check(BuildingCatalog.find("store").name == "Stacked houses" and BuildingCatalog.role(store_kind) == "store"
		and BuildingCatalog.find("moon_tower").gameplay == "Wizardry tower" and BuildingCatalog.find("tall_house").gameplay == "Town guard"
		and BuildingCatalog.find("singing_rocks").gameplay == "Shrine" and BuildingCatalog.find("windmill").gameplay == "Granary"
		and BuildingCatalog.find("necro_tower").name == "Skull tower"
		and FileAccess.file_exists(BuildingCatalog.NAMES_PATH), "Names.txt pairs asset names with gameplay names")
	_check(BuildingCatalog.title("moon_tower") != "" and BuildingCatalog.title("field") == "Wheat field" and BuildingCatalog.title("goblin_tent") != BuildingCatalog.MISSING_NAME,
		"in-game names come from Names.txt (%s)" % BuildingCatalog.title("treehouse"))
	play.hud.show_build_menu(true)
	await _wait(0.3)
	_check(play.hud._build_previews.size() == BuildingCatalog.BUILDINGS.size() - 2, "the build menu shows a picture of each building (%d)" % play.hud._build_previews.size())
	Game.dev_menu = true
	play.hud.set_dev_visible(true)
	_check((play.hud._build_buttons[store_kind] as Button).tooltip_text.contains(BuildingCatalog.find(store_kind).name), "with the dev menu open, the build menu tells the model's name")
	Game.dev_menu = false
	play.hud.set_dev_visible(false)
	_check((play.hud._build_buttons[store_kind] as Button).tooltip_text == "", "and not otherwise")
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
	_check(BuildingCatalog.housing("treehouse") == roundi(Balance.num("home_housing")) and homes[0].has_meta("deck_h"), "Homes are treehouses with a deck")
	for kind: String in ["lookout_treehouse", "twin_treehouse", "great_treehouse"]:
		var tree_home := BuildingFactory.create(kind, RandomNumberGenerator.new())
		_check(tree_home.has_meta("deck_h") and BuildingCatalog.role(kind) == "home", "%s is a treehouse Home" % kind)
		tree_home.free()
	_check(Balance.num("bridge_max_length") > 9.5, "a rope bridge reaches bridge_max_length (%d m)" % roundi(Balance.num("bridge_max_length")))
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
	_check(bones_gained >= roundi(Balance.num("bones_min")) and bones_gained <= roundi(Balance.num("bones_max")) and corpse.is_in_group("corpses"),
		"a dead goblin leaves bones_min to bones_max bones (%d)" % bones_gained)
	var necro_tower := BuildingFactory.create("necro_tower", RandomNumberGenerator.new())
	game.world_root.add_child(necro_tower)
	necro_tower.global_position = village.center + Vector3(-10, 0, 20)
	necro_tower.add_to_group("player_buildings")
	_check(village.max_count("necromancer") == roundi(Balance.num("necromancers_per_tower")) and is_equal_approx(village.train_seconds("necromancer"), Balance.num("necromancer_training_seconds")),
		"a Necromancer tower trains necromancers_per_tower necromancers")
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
	_check(necros.is_empty() or (not (necros[0] as Node).is_in_group("wizards") and village.wanted.wizard <= village.wizards() + village.training_progress("wizard").size()),
		"a necromancer is an upgraded wizard: it counts as a necromancer, not a wizard (%d wizards wanted)" % village.wanted.wizard)
	_check(BuildingCatalog.role_name("shrine") == BuildingCatalog.title("singing_rocks") and not play.hud._resurrect.text.contains("Shrine"),
		"the game shows in-game names, never the gameplay effect")
	if necros.size() == 1:
		var necro := necros[0] as Villager
		_check(is_equal_approx(necro.power(), Villager.FIREBOLT_DAMAGE * 0.5) and is_equal_approx(necro.max_hp, Balance.num("necromancer_health")),
			"a necromancer's (purple) firebolt does half a wizard's harm, and its health is from balancing.txt")
	_check(SpellBook.cost("fireball") == roundi(Balance.num("spell_cost_fireball")) and Balance.DEFAULTS.has("spell_cost_rain"),
		"what spells cost is in balancing.txt")
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
		# (Goblins dying about the place leave bones too, so the count can go up.)
		_check(skeletons.size() >= 1 and necro._minions.size() >= 1 and necro._minions.size() <= roundi(Balance.num("necromancer_skeletons")),
			"the necromancer raises a skeleton from the dead (%d)" % skeletons.size())
		if not skeletons.is_empty():
			var bony := skeletons[0] as Villager
			_check(is_equal_approx(bony.max_hp, Balance.num("goblin_health") * 0.5) and is_equal_approx(bony.damage, Balance.num("goblin_damage") * 0.5),
				"a skeleton has half the health and damage of who it was")
			_check(not bony.is_in_group("people") and bony._expires > game.now + Balance.num("skeleton_seconds") - 80.0
				and bony._expires <= game.now + Balance.num("skeleton_seconds"), "it lasts skeleton_seconds and is not a villager")
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
	# (A few tries: each picks spots at random, and the caves may be crowded.)
	var goblin_site: ConstructionSite = null
	for k in 8:
		goblin_site = play.raids.start_building()
		if goblin_site != null:
			break
	_check(goblin_site != null and goblin_site.goblin and goblin_site.is_in_group("goblin_sites"), "the goblins mark out a building near their cave")
	_check(play.raids.start_building() == null, "and start no other until it is finished")
	if goblin_site:
		var site_cave := goblin_site.get_meta("cave") as Node3D
		var goblin_built := get_tree().get_nodes_in_group("goblin_buildings").size()
		var rate_before := play.raids.cave_rate(site_cave)
		# (They build fast: it may be finished already.)
		for k in 60:
			await _wait(1.0)
			if not is_instance_valid(goblin_site) or goblin_site.progress > 0.0:
				break
		_check(not is_instance_valid(goblin_site) or goblin_site.progress > 0.0, "goblins work on it")
		if is_instance_valid(goblin_site):
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
	_check(is_equal_approx(1000.0 - struck[0].hp, Balance.num("lightning_damage")) and is_equal_approx(1000.0 - struck[1].hp, Balance.num("lightning_damage") * Balance.num("lightning_wet_bonus")),
		"a wet goblin takes lightning_wet_bonus times as much from lightning (%.0f and %.0f)" % [1000.0 - struck[0].hp, 1000.0 - struck[1].hp])
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

	# A giant bat carries a villager off to the cave during a raid. (With
	# nobody to shoot it down: archers and wizards always go for a bat.)
	village.set_wanted("wizard", 0)
	village.set_wanted("archer", 0)
	village.set_wanted("necromancer", 0)
	for node in get_tree().get_nodes_in_group("skeletons"):
		node.queue_free()
	await _wait(1.0)
	# (No births meanwhile, so the count shows the one taken.)
	var births_were: float = game.settings.birth_seconds
	game.settings.birth_seconds = 1.0e9
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
		_check(taken[0] and village.population() == before_bat - 1, "it snatches a villager and takes it into the cave (%d -> %d, shot down %s)" % [
			before_bat, village.population(), is_instance_valid(bat) and not bat.is_alive()])
	game.settings.birth_seconds = births_were
	var doomed := play.raids.launch_bat()
	if doomed:
		doomed.take_hit(Balance.num("bat_health") + 1.0, null)
		_check(not doomed.is_alive() and not doomed.is_in_group("bats"), "a bat with no health left falls out of the sky")
	play.raids.raiding = false

	# Saplings: a planted one is not a tree to chop until it has grown.
	var sprout_at := village.center + Vector3(30, 0, -26)
	sprout_at.y = game.terrain.get_height(sprout_at.x, sprout_at.z)
	var sprout := Sapling.plant(sprout_at)
	await _wait(0.2)
	_check(sprout.is_in_group("saplings") and not sprout.is_in_group("trees") and sprout.scale.x < 0.3, "a sapling starts small, and is not chopped")
	(sprout.get_node("Sapling") as Sapling)._age = 1.0e9
	await _wait(1.2)
	_check(sprout.is_in_group("trees") and not sprout.is_in_group("saplings") and sprout.scale.x > 0.8, "a sapling grows into a tree")
	var saplings_before := get_tree().get_nodes_in_group("saplings").size()
	game.settings.sapling_rate = 60.0
	var knelt := false
	var most_kneeling := 0.0
	for k in 70:
		await _wait(1.0)
		for v in village.people():
			knelt = knelt or v.job == "plant"
		for v in village._planting:
			most_kneeling = maxf(most_kneeling, village._planting[v])
		if get_tree().get_nodes_in_group("saplings").size() > saplings_before:
			break
	game.settings.sapling_rate = 0.0
	_check(knelt and get_tree().get_nodes_in_group("saplings").size() > saplings_before, "villagers kneel and plant saplings (knelt %s for up to %.0f s, %d saplings, %d sites)" % [
		knelt, most_kneeling, get_tree().get_nodes_in_group("saplings").size(), get_tree().get_nodes_in_group("construction_sites").size()])
	for node in get_tree().get_nodes_in_group("saplings"):
		node.queue_free()

	# A battle is only enemies inside the village's influence.
	var marcher := WorldPopulator.spawn_villager(game.world_root, game.terrain, village.center + Vector3(village.influence() + 25.0, 0, 0), 1.0, true)
	await _wait(0.1)
	marcher.raiding = true
	var calm := not beast.mind._battle_raging() or get_tree().get_nodes_in_group("goblins").any(
		func(g: Node) -> bool: return g != marcher and village.in_territory((g as Node3D).global_position))
	marcher.global_position = village.center + Vector3(5, 0, 5)
	_check(calm and beast.mind._battle_raging(), "goblins marching outside the influence are no battle; inside it they are")
	marcher.queue_free()
	# Only Builders and unassigned Workers build.
	village._assign_jobs()
	_check(village.people().all(func(v: Villager) -> bool: return v.job != "build" or v.pin == "" or v.pin == "build"),
		"lumberjacks, miners and farmers never build")

	# Charm Offensive: half the goblins caught in it fight their own kind.
	var charm_at := village.center + Vector3(-40, 0, 30)
	charm_at.y = game.terrain.get_height(charm_at.x, charm_at.z)
	var pair: Array[Villager] = []
	for k in 2:
		pair.append(WorldPopulator.spawn_villager(game.world_root, game.terrain, charm_at, 2.0, true))
	await _wait(0.2)
	Balance.values["charm_share"] = 1.0
	pair[0].global_position = charm_at
	pair[1].global_position = charm_at + Vector3(30, 0, 0)
	var charm := CharmOffensive.new()
	game.world_root.add_child(charm)
	var charmed_count := charm.cast(charm_at)
	Balance.values["charm_share"] = Balance.DEFAULTS["charm_share"]
	_check(charmed_count == 1 and pair[0].charmed() and not pair[1].charmed() and pair[0]._pink_eyes.size() == 2,
		"Charm Offensive charms the goblins in it, and their eyes turn pink")
	_check(pair[0]._nearest_goblin(100.0) == pair[1] and pair[1]._nearest_goblin(100.0) != pair[0], "a charmed goblin goes for its own kind")
	pair[0].charmed_until = 0.0
	await _wait(0.6)
	_check(not pair[0].charmed() and pair[0]._pink_eyes.is_empty(), "the charm wears off")
	for g in pair:
		g.queue_free()

	# A giant bat falls to a single arrow, and drops its villager.
	var downed := GiantBat.new()
	downed.cave = Node3D.new()
	game.world_root.add_child(downed.cave)
	game.world_root.add_child(downed)
	downed.global_position = village.center + Vector3(0, 12, 0)
	downed.take_hit(1.0, village.people()[0])
	_check(not downed.is_alive(), "one arrow or firebolt brings a giant bat down")
	downed.cave.queue_free()

	# The magic tree: magicko from it, rising as it grows, seeds and pixies.
	var magic := MagicTree.new()
	game.world_root.add_child(magic)
	magic.global_position = village.center + Vector3(-30, 0, -30)
	var tiny_rate := magic.magicko_rate()
	magic._age = 1.0e9
	await _wait(0.2)
	_check(is_equal_approx(tiny_rate, 10.0) and is_equal_approx(magic.magicko_rate(), 100.0), "a magic tree gives 10 magicko a minute tiny, 100 full grown")
	var magicko_now := village.amount("magicko")
	await _wait(6.0)
	_check(village.amount("magicko") >= magicko_now + 9, "and the village gets it (%d more in 6 seconds)" % (village.amount("magicko") - magicko_now))
	magic._pixie_due = 0.0
	magic._drop_seed()
	await _wait(3.0)
	var pixies := 0
	for child in magic.get_children():
		if child is Pixie:
			pixies += 1
	_check(pixies == 1, "pixies fly about the magic tree")
	_check(not get_tree().get_nodes_in_group("saplings").is_empty(), "the magic tree drops seeds that become saplings")
	_check(not magic.is_in_group("trees"), "nobody can chop the magic tree")
	magic.queue_free()
	for node in get_tree().get_nodes_in_group("saplings"):
		node.queue_free()

	# Punches take turns between the fists.
	beast._start_strike()
	var first_fist := beast._punch_hand
	beast._action = Creature.Action.NONE
	beast._start_strike()
	_check(beast._punch_hand != first_fist, "the creature punches with one fist and then the other")
	beast._action = Creature.Action.NONE
	beast._arm_one = [null, null]

	# Growing as the owner has it: with growth_animus_step at 0 it grows by
	# itself, and Bless and Condemn come with its first two tenths.
	var age_kept := beast.age
	var animus_kept := village.amount("animus")
	var step_kept := Balance.num("growth_animus_step")
	if step_kept <= 0.0:
		beast.growth_paid = 0
		beast.age = 0.0
		village.resources.animus = 0.0
		for growth_spell: String in ["bless", "condemn"]:
			village.spells_known.erase(growth_spell)
		await _wait(1.0)
		_check(beast.age > 0.0 and beast.growth_paid >= 1 and village.knows_spell("bless") and not beast.can_grow(),
			"with growth_animus_step 0 the creature grows by itself, for no animus, and Bless comes")
	# Growing for animus, when growth_animus_step is above 0: 1 step for the
	# first tenth, 2 for the second...
	Balance.values["growth_animus_step"] = 1.0
	beast.growth_paid = 0
	beast.age = 0.0
	village.resources.animus = 0.0
	# (Bless and Condemn come with growing: take them away to see them come.)
	for growth_spell: String in ["bless", "condemn"]:
		village.spells_known.erase(growth_spell)
		var slot_k := village.spell_slots.find(growth_spell)
		if slot_k >= 0:
			village.spell_slots[slot_k] = ""
	_check(village.start_spell_research("bless") != "", "Bless cannot be researched")
	await _wait(1.0)
	_check(beast.age == 0.0 and beast.growth_paid == 0 and not beast.can_grow(), "with no animus, the creature does not grow")
	village.give("animus", 1.0)
	await _wait(0.5)
	_check(beast.can_grow() and beast.growth_paid == 0 and beast.age == 0.0, "with the animus, it can grow on, but waits to be told")
	play.hud.update_creature(beast)
	_check(play.hud._portrait_sparkles.amount > 0.0 and play.hud._portrait.tooltip_text.contains("1 animus"), "its portrait sparkles, and says what growing costs")
	play.hud.grow_requested.emit()
	await _wait(2.0)
	_check(beast.growth_paid == 1 and village.amount("animus") == 0 and beast.age > 0.0
		and beast.age <= 0.1 * game.settings.creature_grow_minutes * 60.0 + 0.01, "clicking the portrait pays 1 animus for the first tenth of its growth, and no further")
	_check(village.knows_spell("bless") and not village.knows_spell("condemn"), "the first growth unlocks Bless")
	play.hud.update_creature(beast)
	_check(is_equal_approx(play.hud._growth_bar.paid, 0.1) and play.hud._growth_bar.grown <= 0.11, "the growth bar shows what it has grown and what is paid for")
	village.give("animus", 2.0)
	_check(beast.pay_for_growth() and beast.growth_paid == 2 and village.amount("animus") == 0, "the second tenth costs 2")
	_check(village.knows_spell("condemn"), "the next growth unlocks Condemn")
	play.hud.update_creature(beast)
	_check(play.hud._portrait_sparkles.amount == 0.0, "no sparkle when it cannot grow on")
	beast.growth_paid = 10
	beast.age = age_kept
	village.resources.animus = float(animus_kept)
	Balance.values["growth_animus_step"] = step_kept
	await _wait(0.3)

	# Out of its shell, a harmless blast knocks the goblins near it away,
	# and it has a burst of speed.
	var shoved := WorldPopulator.spawn_villager(game.world_root, game.terrain, beast.global_position + Vector3(6, 0, 0), 0.5, true)
	await _wait(0.05)
	shoved.global_position = beast.global_position + Vector3(6, 0, 0)  # (clear of its feet)
	var shoved_hp := shoved.hp
	beast._burst_out()
	_check(shoved.is_alive() and shoved.hp >= shoved_hp - 0.01 and shoved._stagger_until > game.now and shoved._shove.length() > 1.0,
		"the blast out of its shell knocks nearby goblins away, unhurt")
	# Coming out of its shell sets it off.
	beast._burst_until = 0.0
	beast.hiding = true
	beast._hid_at = game.now - 100.0
	beast._last_hit_at = game.now - 100.0
	for k in 20:
		await _wait(0.05)
		if not beast.hiding:
			break
	_check(beast._burst_until > game.now, "and it has a burst of speed")

	# Kinky Fey Stuff: a pixie comes for a villager at work, off they go into
	# a building, and then the fey are about.
	var lover := village.fey_target(village.center)
	if lover == null:
		lover = village.fey_target(village.people()[0].global_position)
	_check(lover != null, "Kinky Fey Stuff finds a villager at work")
	if lover != null:
		# (Near the middle of the village, so the walk to a building is short.)
		lover.global_position = village.center + Vector3(3, 0, 3)
		Balance.values["fey_tryst_seconds"] = 3.0
		var tryst := FeyTryst.new()
		game.world_root.add_child(tryst)
		tryst.begin(lover)
		for k in 30:
			await _wait(0.5)
			if lover.job == "tryst":
				break
		_check(lover.job == "tryst" and lover._pink_eyes.size() == 2, "a pixie flies to the villager, whose eyes glow green, and they go off together")
		for k in 120:
			await _wait(0.5)
			if village.fey_until > game.now:
				break
		_check(village.fey_until > game.now and not lover.visible, "as soon as they go into the building, the fey are about (births come faster)")
		for k in 60:
			await _wait(0.5)
			if lover.visible:
				break
		_check(lover.visible and lover._pink_eyes.is_empty(), "the villager comes back out, eyes no longer glowing")
		Balance.values["fey_tryst_seconds"] = Balance.DEFAULTS["fey_tryst_seconds"]
	# Children born meanwhile are winged girls, who grow up flying.
	village.fey_until = game.now + 60.0
	var kid := village._spawn_child()
	_check(kid.fey and kid._wings.size() == 4 and kid._look.get("female", false), "a child born while the fey are about is a girl with four wings")
	kid._age = 1.0e9
	await _wait(2.0)
	_check(kid.is_adult() and kid._hover > 0.3 and village.fey_adults() >= 1, "and grows up flying (%.1f m up)" % kid._hover)
	var kid_was := [kid.state, kid._working, kid.job]
	kid.state = Villager.State.JOB
	kid._working = true
	kid.job = "lumber"
	for k in 5:
		kid._update_fey(1.0)
	var gathering_at := kid._hover
	kid.job = "build"
	for k in 5:
		kid._update_fey(1.0)
	_check(gathering_at < 0.05 and kid._hover > 1.5, "fey fly unless they are gathering (%.1f m gathering, %.1f m building)" % [gathering_at, kid._hover])
	kid.state = kid_was[0]
	kid._working = kid_was[1]
	kid.job = kid_was[2]
	kid._moving = true
	for k in 10:
		kid._animate(0.2)
	_check(kid._body.rotation.x > 0.4, "a flying fey leans forwards as she flies along (%.2f)" % kid._body.rotation.x)
	village.fey_until = 0.0
	# Fey Archers: as many as there are winged villagers, once archers can be trained.
	_check(village.max_count("fey_archer") == village.fey_adults(), "Fey Archers: as many as there are winged villagers (%d)" % village.max_count("fey_archer"))
	Balance.values["fey_archer_training_seconds"] = 2.0
	# (Free of whatever it was carrying, so it goes straight to training.)
	kid.carry = 0.0
	kid.clear_job()
	village.set_wanted("fey_archer", 1)
	for k in 60:
		await _wait(1.0)
		if village.count("fey_archer") >= 1:
			break
	var fey_archers := get_tree().get_nodes_in_group("fey_archers")
	_check(fey_archers.size() == 1 and (fey_archers[0] as Villager).fey_archer and not (fey_archers[0] as Node).is_in_group("archers"),
		"a winged villager trains as a Fey Archer (%d; wanted %d, training %s, guards %d, kid job '%s' pin '%s' state %d works %s, free %d)" % [
			fey_archers.size(), village.wanted.fey_archer, village.training_progress("fey_archer"), village._training_buildings("fey_archer").size(),
			kid.job, kid.pin, kid.state, kid.can_work(), village.free_workers()])
	Balance.values["fey_archer_training_seconds"] = Balance.DEFAULTS["fey_archer_training_seconds"]
	village.set_wanted("fey_archer", 0)
	if is_instance_valid(shoved):
		shoved.queue_free()

	# Lumberjacks go as far as it takes for wood.
	var far_tree := WorldPopulator.spawn_tree(game.world_root, game.terrain, village.center.x + PlayerVillage.WORK_REACH + 30.0, village.center.z, 0.0, 7)
	await _wait(0.1)
	_check(village._nearest_free(far_tree.global_position, "trees", {}) == far_tree, "there is no limit to how far lumberjacks go for wood")
	far_tree.queue_free()
	_check(is_equal_approx(Game.DEFAULT_SETTINGS.goblin_build_speed, 1.0) and is_equal_approx(Game.DEFAULT_SETTINGS.goblin_rate, 0.0)
		and not Game.DEFAULT_SETTINGS.has("goblin_rate_growth"), "the owner's sliders are the defaults: Goblin Spawn Rate 0, goblin build speed 1")
	_check(is_equal_approx(Game.DEFAULT_SETTINGS.day_minutes, 10.0) and play.day_cycle.clock_text().contains(":"), "a day is 10 minutes by default (%s)" % play.day_cycle.clock_text())
	_check(DayCycle.twelve_hour(16.0) == "4:00 pm" and DayCycle.twelve_hour(0.5) == "12:30 am" and DayCycle.twelve_hour(12.25) == "12:15 pm"
		and DayCycle.twelve_hour(9.0) == "9:00 am" and (play.day_cycle.clock_text().ends_with(" am") or play.day_cycle.clock_text().ends_with(" pm")),
		"the clock is a 12-hour one, with no daytime or nighttime (%s)" % play.day_cycle.clock_text())
	# Night begins at midnight; the hours go by at the night's own pace.
	var clock := DayCycle.new()
	add_child(clock)
	clock.process_mode = Node.PROCESS_MODE_DISABLED
	clock.time = 0.0
	var fell := [false]
	clock.nightfall.connect(func() -> void: fell[0] = true)
	clock.advance(DayCycle.day_seconds() - 1.0)
	_check(not fell[0] and not clock.is_night(), "the daylight lasts day_minutes")
	clock.advance(2.0)
	_check(fell[0] and clock.is_night() and clock.hour() < 1.0, "and then night falls, at midnight (%s)" % DayCycle.twelve_hour(clock.hour()))
	clock.advance(DayCycle.night_seconds() * 0.5)
	_check(clock.is_night() and absf(clock.hour() - 3.0) < 0.2, "the night's hours pass at the night's pace (%s halfway)" % DayCycle.twelve_hour(clock.hour()))
	clock.advance(DayCycle.night_seconds() * 0.5 + 1.0)
	_check(not clock.is_night() and clock.day == 2 and clock.hour() < 6.1, "and morning comes at 6 am after night_minutes")
	clock.free()

	# Magic rain: a field being sown sprouts at once; ripe wheat sprouts
	# seedlings where it has been reaped.
	var wet_field := CropField.new()
	wet_field.setup(Vector2(6, 6))
	wet_field.position = village.center + Vector3(-70, 0, -70)
	wet_field.process_mode = Node.PROCESS_MODE_DISABLED
	game.world_root.add_child(wet_field)
	wet_field.water(5.0)
	_check(wet_field.stage == CropField.Stage.GROWING and wet_field.progress == 0.0, "rain on a field being sown sprouts it all at once, sown or not")
	wet_field.stage = CropField.Stage.RIPE
	wet_field.progress = 0.4
	wet_field.water(5.0)
	_check(is_equal_approx(wet_field.sprouted, 0.4) and wet_field._sprouts.multimesh.visible_instance_count > 0,
		"rain on ripe wheat sprouts seedlings in the reaped ground")
	wet_field.add_work(1.0e6)
	_check(wet_field.stage == CropField.Stage.SOWING and is_equal_approx(wet_field.progress, 0.4), "and they count as sown when the reaping is done")
	_check(is_equal_approx(Balance.num("rain_crop_growth"), Balance.values.get("rain_crop_growth", 3.5)) and Balance.num("rain_crop_growth") > 1.0,
		"wet wheat grows rain_crop_growth times as fast (%.2f)" % Balance.num("rain_crop_growth"))
	# Only farmers sow; anyone may reap, and farmers reap first.
	var helper: Villager = null
	for v in village.people():
		if v.can_work() and v.pin == "" and v.job != "train":
			helper = v
			break
	if helper != null:
		var saved_fields: Array[Node] = []
		for node in get_tree().get_nodes_in_group("fields"):
			if node != wet_field:
				saved_fields.append(node)
				node.remove_from_group("fields")
		_check(not village._give_job(helper, "food", {}), "an unassigned worker does not sow")
		wet_field.stage = CropField.Stage.RIPE
		wet_field.progress = 0.0
		_check(village._give_job(helper, "food", {}) and helper.job_target == wet_field, "but reaps ripe wheat")
		helper.clear_job()
		for node in saved_fields:
			node.add_to_group("fields")
	wet_field.queue_free()
	# Unassigned workers go after whatever the village has least of.
	var kept_res: Dictionary = village.resources.duplicate()
	village.resources.lumber = 250.0
	village.resources.food = 250.0
	village.resources.stone = 0.0
	var idle_worker: Villager = null
	for v in village.people():
		if v.can_work() and v.pin == "" and v.job != "train" and v.job != "build" and v.job != "tryst" and v.job != "plant":
			idle_worker = v
			break
	if idle_worker != null:
		idle_worker.clear_job()
		village._assign_jobs()
		_check(idle_worker.job == "stone" or get_tree().get_nodes_in_group("rocks").is_empty(), "an unassigned worker goes after the resource the village has least of (%s)" % idle_worker.job)
	village.resources = kept_res

	# Goblin archers.
	var bowman := WorldPopulator.spawn_villager(game.world_root, game.terrain, village.center + Vector3(80, 0, 80), 1.0, true)
	await _wait(0.1)
	bowman.become_goblin_archer()
	_check(bowman.archer and bowman.is_in_group("goblin_archers") and is_equal_approx(bowman.max_hp, Balance.num("goblin_archer_health"))
		and is_equal_approx(bowman.shot_range(), Balance.num("goblin_archer_range")) and Balance.num("goblin_archer_chance") > 0.0,
		"a goblin archer has goblin_archer_health and shoots goblin_archer_range metres")
	bowman.queue_free()
	var some_cave: Node3D = null
	for node in get_tree().get_nodes_in_group("caves"):
		some_cave = node as Node3D
		break
	if some_cave != null:
		var tip := play.raids.cave_tip(some_cave)
		_check(tip.contains("Spawns") and tip.contains("Goblin archers") and tip.contains("Ogres"), "pointing at a goblin cave shows its spawn rate and every enemy")
	_check(GoblinRaids.building_tip("goblin_war_hut").contains("ogre") and GoblinRaids.building_tip("goblin_watchtower").contains("bat")
		and GoblinRaids.building_tip("goblin_tent").contains("goblins"), "goblin buildings say what they do")
	_check(SpellCursors.grey_image("fireball").get_pixel(16, 16).s < 0.01 or SpellCursors.grey_image("fireball").get_pixel(16, 16).a == 0.0,
		"outside the influence the spell pointer is grey")
	# Advance time: five minutes at once.
	var day_was := play.day_cycle.time + play.day_cycle.day
	var born_before := village.population()
	village.resources.food = 200.0
	var magicko_rate_now := village.last_minute("magicko")
	var magicko_before: float = village.resources.magicko
	var expected_magicko := village.magicko_per_minute() * PlayMode.ADVANCE_SECONDS / 60.0
	play.advance_time(PlayMode.ADVANCE_SECONDS)
	_check(play.day_cycle.time + play.day_cycle.day > day_was and (village.population() > born_before or village.population() >= village.housing())
		and village.amount("food") >= 1, "the dev menu's Advance time moves the clock on, and the births come")
	_check(absf(village.resources.magicko - magicko_before - expected_magicko) < 1.0 and village.last_minute("magicko") <= magicko_rate_now + 1,
		"Advance time gives the magicko of the minutes skipped, and does not count it as income (%.1f given, %.1f expected; rate %d -> %d)" % [
		village.resources.magicko - magicko_before, expected_magicko, magicko_rate_now, village.last_minute("magicko")])
	# Nobody walks through a building unless they are going into it.
	var walled: Destructible = null
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if b != null and not b.destroyed and PathGrid.wall_radius(b) > 1.5:
			walled = b
			break
	if walled == null:
		_check(false, "a building to walk round")
	else:
		var wall_mid := walled.global_position
		var wall_r := PathGrid.wall_radius(walled)
		var wall_grid := game.path_grid()
		var walk_from := Vector3.ZERO
		var walk_to := Vector3.ZERO
		for k in 16:
			var a := TAU * k / 16.0
			var side := Vector3(cos(a), 0.0, sin(a)) * (wall_r + 3.0)
			var side_a := wall_mid + side
			var side_b := wall_mid - side
			if wall_grid.building_at(side_a) == null and wall_grid.building_at(side_b) == null and game.terrain.water_depth(side_a.x, side_a.z) < 0.1 and game.terrain.water_depth(side_b.x, side_b.z) < 0.1 \
					and not game.terrain.is_steep(side_a.x, side_a.z) and not game.terrain.is_steep(side_b.x, side_b.z):
				walk_from = side_a
				walk_to = side_b
				break
		var walker := WorldPopulator.spawn_villager(game.world_root, game.terrain, walk_from, 1.0)
		walker.global_position = Vector3(walk_from.x, game.terrain.get_height(walk_from.x, walk_from.z), walk_from.z)
		var closest := INF
		var arrived := false
		for k in 3000:
			arrived = walker._move_towards(walk_to, 3.0, 1.0 / 30.0)
			closest = minf(closest, Vector2(walker.global_position.x - wall_mid.x, walker.global_position.z - wall_mid.z).length())
			if arrived:
				break
		_check(arrived and walker._flat_to(walk_to) < 1.0 and closest > wall_r * 0.9,
			"a villager walks round a building, not through it (%.1f m from its middle at closest, its walls %.1f m)" % [closest, wall_r])
		var went_in := false
		for k in 600:
			if walker._move_towards(wall_mid, 3.0, 1.0 / 30.0):
				went_in = true
				break
		_check(went_in and walker._flat_to(wall_mid) < 1.0, "but walks in when the building is where it is going")
		walker.queue_free()
	play.raids.end_raid()
	play.day_cycle.nightfall.emit()
	_check(play.raids.raiding, "the goblins raid at nightfall")
	play.raids.end_raid()
	# Darker nights, as the dev menu's slider says.
	var sky := play._atmosphere
	sky._night = 1.0
	game.settings.night_darkness = 50.0
	sky._apply(sky._current)
	_check(is_equal_approx(sky._env.tonemap_exposure, 0.5), "the night darkness slider darkens the night")
	game.settings.night_darkness = 0.0
	sky._night = 0.0
	sky._apply(sky._current)
	_check(play.hud._portrait != null and play.hud._creature_bars.health[0].mouse_filter == Control.MOUSE_FILTER_STOP, "the creature has a portrait, and its bars can be clicked")
	play.hud.creature_focus_requested.emit()
	_check(Hud.SPELL_SIZE == 36, "the spell bar is half the size")

	# Bless and Condemn: the key takes the spell in hand and says what the
	# creature last did; the key again (or a click) casts it. Each thing it
	# does is judged once.
	var bless := SpellBook.index_of("bless")
	village.learn_all_spells()
	beast.mind.did("explore")
	play._spell_key(bless)
	_check(play._armed == bless and play._judge_prompt and play.hud._prompt.text.contains("exploring"), "pressing Bless shows the creature's last action")
	var keen: float = beast.mind.behavior.explore
	village.give("magicko", 50.0)
	play._spell_key(bless)
	_check(beast.mind.behavior.explore > keen and play._armed == -1 and not play._judge_prompt, "pressing it again casts it, without a click")
	beast.mind._judged_at.clear()
	play._cooldowns[bless] = 0.0  # (past Bless's cooldown)
	beast.mind.did("eat", {"enemy": "goblin", "battle": true})
	var eat_action := beast.mind.judge_target()
	var keen_eat: float = beast.mind.behavior.get(eat_action, 0.0)
	play._spell_key(bless)
	play._click_spell()
	_check(beast.mind.behavior[eat_action] > keen_eat and play._armed == -1, "a click casts it too")
	_check(not play._judge_prompt, "and the text goes")
	keen_eat = beast.mind.behavior[eat_action]
	play._spell_key(bless)
	play._click_spell()
	_check(is_equal_approx(beast.mind.behavior[eat_action], keen_eat), "the same action cannot be blessed twice")
	# What floats up is the owner's sentence from Actions.csv.
	_check(beast.mind.action_sentence("eat", {"enemy": "goblin", "battle": true}).begins_with("The creature ate a goblin"),
		"the creature's action is told in the sentence from Actions.csv (%s)" % beast.mind.action_sentence("eat", {"enemy": "goblin", "battle": true}))
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
	_check(Balance.num("lightning_jumps") >= 1.0, "chain lightning jumps lightning_jumps times (%d)" % roundi(Balance.num("lightning_jumps")))
	_check(SpellBook.SPELLS[SpellBook.index_of("condemn")].name == "Condemn" and SpellBook.index_of("curse") == -1, "Curse is now called Condemn")
	# Cooldowns: no casting again until it has cooled down, unless with
	# Overcast, once, for twice the magicko.
	var fire_k := SpellBook.index_of("fireball")
	var fire_cost := play.spell_cost(fire_k)
	play._cooldowns[fire_k] = SpellBook.cooldown("fireball")
	village.researched.erase("overcast")
	_check(not play.spell_ready(fire_k), "a spell cannot be cast while it cools down")
	play._update_ui()
	_check(play.spell_cost(fire_k) == fire_cost and play.spell_state(fire_k) == 1 and play.hud._spell_fills[fire_k].left > 0.9
		and play.hud._spell_costs[fire_k].get_theme_color("font_color") == Hud.COST_COOLING,
		"cooling down, without Overcast: the same cost in red, and the icon fills from the bottom")
	village.researched["overcast"] = true
	play._cooldowns[fire_k] = SpellBook.cooldown("fireball") - 1.0
	_check(play.spell_ready(fire_k) and play.spell_cost(fire_k) == fire_cost * 2, "with Overcast it can, for twice the magicko (%d)" % play.spell_cost(fire_k))
	play._update_ui()
	_check(play.spell_state(fire_k) == 2 and play.hud._spell_costs[fire_k].get_theme_color("font_color") == Hud.COST_OVERCAST
		and play.hud._spell_sparkles[fire_k].active, "the cost shows blue, with red lightning round it, while Overcast can cast it")
	village.give("magicko", 1000.0, false)
	play._pay_for(fire_k)
	_check(not play.spell_ready(fire_k), "but only once in each cooldown")
	play._update_ui()
	_check(play.spell_state(fire_k) == 1 and not play.hud._spell_sparkles[fire_k].active and play.hud._spell_sparkles[fire_k]._burst >= 0.0,
		"overcast, it turns red and the lightning bursts outwards and goes")
	play._cooldowns[fire_k] = 0.0
	play._overcast_used[fire_k] = false

	# The creature learns by watching, and is blessed and cursed.
	var mind := beast.mind
	for id: String in CreatureMind.SPELLS + CreatureMind.HARVESTS:
		Balance.values["knowledge_" + id] = Balance.DEFAULTS["knowledge_" + id]
		mind.knowledge[id] = 0.0
	mind.watch_spell("rain")
	_check(is_equal_approx(mind.knowledge.rain, Balance.num("knowledge_per_watch")) and not mind.learned("rain"), "watching a spell adds knowledge")
	var casts := 1
	while not mind.learned("rain") and casts < 50:
		mind.watch_spell("rain")
		casts += 1
	_check(mind.learned("rain") and casts == ceili(Balance.num("knowledge_rain") / Balance.num("knowledge_per_watch")), "enough casts teach the creature rain (%d)" % casts)
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
	# (In the air: a flyer casts on the wing too.)
	beast.flying = true
	var cast_flying := mind._try_spells()
	beast.flying = false
	_check(cast_flying and mind.last_action == "rain" and mind.last_facts.get("target", "") == "crops" and is_equal_approx(beast.magicko, beast.max_magicko - Balance.num("creature_cost_rain")),
		"it casts rain on the crops, even while flying, and that costs it magicko (%d left)" % roundi(beast.magicko))
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
	_check(is_equal_approx(Balance.parse_number("150%"), 1.5) and is_equal_approx(Balance.parse_number("80%"), 0.8)
		and is_equal_approx(Balance.DEFAULTS.raven_spellcaster_personality, 1.5) and Balance.num("raven_spellcaster_personality") > 0.0,
		"personalities are read as percentages (raven spellcaster %d%%)" % roundi(Balance.num("raven_spellcaster_personality") * 100.0))
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
	for node in get_tree().get_nodes_in_group("goblins"):
		node.remove_from_group("goblins")
		node.queue_free()
	beast._action = Creature.Action.NONE
	beast.drop_load()
	# (Back by the village, on open ground, wherever its last errand left it.)
	var by_village := village.center + Vector3(12, 0, 12)
	beast.global_position = Vector3(by_village.x, game.terrain.get_height(by_village.x, by_village.z), by_village.z)
	beast.has_target = false
	await _wait(0.5)
	beast.stamina = beast.max_stamina * 0.5
	var walk_to := beast.global_position
	for k in 72:
		var a := TAU * k / 24.0
		var p: Vector3 = beast.global_position + Vector3(cos(a), 0, sin(a)) * [25.0, 16.0, 10.0][int(k / 24.0)]
		# (Not over a grey rock slope, where it would have to stop.)
		var clear := true
		for s in 13:
			var q := beast.global_position.lerp(p, s / 12.0)
			clear = clear and not game.terrain.is_steep(q.x, q.z)
		if clear and game.terrain.is_inside(p.x, p.z) and game.terrain.is_dry(p.x, p.z):
			walk_to = p
			break
	beast.move_to(walk_to)
	# (Measured only while it is walking: standing, it gets its breath back.)
	var stamina_then := beast.stamina
	var top_speed := 0.0
	var drained := false
	var last_stamina := beast.stamina
	var was_walking := false
	for k in 40:
		await _wait(0.1)
		top_speed = maxf(top_speed, beast.speed)
		var walking := beast.speed > 0.6
		if walking and was_walking and beast.stamina < last_stamina:
			drained = true
			break
		was_walking = walking
		last_stamina = beast.stamina
	_check(drained, "the tortoise's stamina drains slowly as it walks (%.1f -> %.1f, speed %.1f, snared %s, alert %s, hiding %s, action %d, target %s %.1f m)" % [
		stamina_then, beast.stamina, top_speed, game.now < beast.snared_until, beast._alert, beast.hiding, beast._action, beast.has_target, beast._flat(walk_to, beast.global_position)])
	# Attack move (right-click): it goes after an enemy near its way, and
	# once it is fighting it does not finish the walk.
	beast.has_target = false
	beast.global_position = Vector3(by_village.x, game.terrain.get_height(by_village.x, by_village.z), by_village.z)
	var goal := beast.global_position
	var side_spot := beast.global_position
	for k in 48:
		var a := TAU * k / 48.0
		var dir := Vector3(cos(a), 0, sin(a))
		var g := beast.global_position + dir * 40.0
		var sp := beast.global_position + dir * 14.0 + Vector3(-dir.z, 0, dir.x) * 12.0
		var ok := game.terrain.is_inside(g.x, g.z) and game.terrain.is_dry(g.x, g.z) and game.terrain.is_dry(sp.x, sp.z)
		for st in 11:
			var q := beast.global_position.lerp(g, st / 10.0)
			ok = ok and not game.terrain.is_steep(q.x, q.z) and game.terrain.is_dry(q.x, q.z)
		if ok:
			goal = g
			side_spot = sp
			break
	var lurker := WorldPopulator.spawn_villager(game.world_root, game.terrain, side_spot, 0.5, true)
	lurker.global_position = Vector3(side_spot.x, game.terrain.get_height(side_spot.x, side_spot.z), side_spot.z)
	lurker.process_mode = Node.PROCESS_MODE_DISABLED
	play._command_attack_move(goal)
	_check(beast.attack_moving, "a right-click sends the creature on an attack move")
	var engaged := false
	for k in 60:
		await _wait(0.5)
		if not beast.attack_moving and (not is_instance_valid(lurker) or not lurker.is_alive() or beast.is_fighting()):
			engaged = true
			break
	_check(engaged and beast._flat(goal, beast.global_position) > 8.0,
		"on an attack move it goes after an enemy on the way and stays to fight (%.0f m short of where it was sent)" % beast._flat(goal, beast.global_position))
	if is_instance_valid(lurker):
		lurker.queue_free()

	# Magicko: 1 every 2 minutes from a villager, wizard_magicko from a wizard.
	var settings_were: Dictionary = Game.settings.duplicate()
	Game.settings.magicko_rate = Game.DEFAULT_SETTINGS.magicko_rate
	var maker_rate := village.magicko_per_minute()
	var makers := village.adults() - village.wizards()
	_check(is_equal_approx(Game.DEFAULT_SETTINGS.magicko_rate, 0.5) and (village.blood_active() or village.fey_adults() > 0
		or is_equal_approx(maker_rate, makers * 0.5 + village.wizards() * Balance.num("wizard_magicko"))),
		"a villager makes 1 magicko every 2 minutes, a wizard wizard_magicko a minute (%.1f a minute from %d villagers)" % [maker_rate, makers])
	Game.settings = settings_were
	# Defending the village: goblins marching near a Storehouse.
	_check(beast.mind.personality("defensive") > Balance.num("raven_defensive_personality"), "the tortoise is the most defensive of the town")
	beast.has_target = false
	beast.attack_moving = false
	var store_at := village.center
	for node in get_tree().get_nodes_in_group("player_buildings"):
		if BuildingCatalog.role(node.get_meta("kind", "")) == "store":
			store_at = (node as Node3D).global_position
			break
	var raider_near_at := store_at + Vector3(30, 0, 30)
	var raider_near := WorldPopulator.spawn_villager(game.world_root, game.terrain, raider_near_at, 0.5, true)
	raider_near.process_mode = Node.PROCESS_MODE_DISABLED
	raider_near.raiding = true
	_check(beast.mind.marching_on_stores() == raider_near, "goblins marching within 200 m of a Storehouse are seen")
	Balance.values["defensive_weight"] = 1000.0
	beast.mind._defend_timer = 0.0
	# (Not in a fight just now: the last check's goblin is gone.)
	beast._alert = false
	beast._cancel_action()
	beast.fleeing_until = 0.0
	_check(beast.mind._consider_defending() and beast.attack_moving, "the creature sets off to attack them")
	Balance.values["defensive_weight"] = Balance.DEFAULTS["defensive_weight"]
	beast.attack_moving = false
	beast.has_target = false
	raider_near.queue_free()
	# Creature buffs, researched at the Shrines.
	# (The dev menu's "every spell" earlier taught them all: start again.)
	village.buffs_known.clear()
	village.buff_jobs.clear()
	_check(village.buff_research_cost().get("animus", 0) == roundi(Balance.num("buff_research_first")), "the first buff costs 5 animus to research")
	village.give("animus", 100.0)
	_check(village.start_buff_research("growth") == "" and village.buff_research_cost().get("animus", 0) == roundi(Balance.num("buff_research_first") + Balance.num("buff_research_step")),
		"and the next costs 5 more")
	village.buff_job("growth").t = Balance.num("buff_research_seconds") - 0.5
	await _wait(1.5)
	_check(village.knows_buff("growth"), "a buff is researched in 8 minutes")
	play.hud.update_buffs(village, beast, play)
	_check(play.hud._buff_slots.growth.button.visible and play.hud._buff_slots.size() == BuffBook.BUFFS.size(), "it appears on the buff bar over the health bar")
	var age_before := beast.age
	beast.age = 0.0
	beast.growth_paid = 10
	# (A hungry creature does not grow.)
	village.resources.food = 200.0
	_check(play.cast_buff("growth") == "" and beast.buff_on("growth"), "Creature Growth is cast")
	_check(play.cast_buff("growth") != "", "but not while it is on")
	await _wait(2.0)
	_check(beast.age > 2.0 * 1.5, "the creature grows twice as fast (%.1f s of growth in 2 s)" % beast.age)
	beast._buffs["growth"] = game.now
	await _wait(0.2)
	_check(play.cast_buff("growth") != "" and play.buff_cooling("growth") > 0.0, "a minute's cooldown after it wears off")
	beast.age = age_before
	village.buffs_known["aura"] = true
	var singed := WorldPopulator.spawn_villager(game.world_root, game.terrain, beast.global_position + Vector3(5, 0, 0), 0.5, true)
	singed.process_mode = Node.PROCESS_MODE_DISABLED
	var singed_hp := singed.hp
	_check(play.cast_buff("aura") == "" and beast.buff_on("aura"), "Flaming Aura is cast for 1 animus")
	# (Kept beside the creature, wherever it walks, for three seconds: two
	# ticks at the least, however the second falls.)
	for k in 10:
		singed.global_position = beast.global_position + Vector3(4, 0, 0)
		await _wait(0.3)
	_check(singed.hp <= singed_hp - Balance.num("aura_damage") * 1.5, "enemies close by take fire damage every second (%d lost)" % roundi(singed_hp - singed.hp))
	beast._buffs.clear()
	singed.queue_free()
	# Over a building: what it is researching.
	village.give("lumber", 300.0)
	village.give("stone", 300.0)
	village.researched.erase("pitchforks_3")
	village.start_research("pitchforks_3")
	_check(village.status_of(smithy).contains("Researching Pitchforks III"), "the mouse over the Blacksmith shows what it researches (%s)" % village.status_of(smithy).replace("\n", " / "))
	village.researching("smith").clear()
	village.researched["pitchforks_3"] = true
	# Farmers with nothing to sow or reap work the growing fields.
	var tilled := get_tree().get_nodes_in_group("fields")[0] as CropField
	tilled.process_mode = Node.PROCESS_MODE_INHERIT
	for node in get_tree().get_nodes_in_group("fields"):
		(node as CropField).stage = CropField.Stage.GROWING
	var farmer: Villager = null
	for v in village.people():
		if v.can_work() and v.pin == "":
			farmer = v
			break
	if farmer != null:
		farmer.pin = "food"
		farmer.clear_job()
		village._assign_jobs()
		_check(farmer.job == "tend", "a farmer with nothing to reap works a growing field (%s)" % farmer.job)
		farmer.pin = ""
		farmer.clear_job()
	tilled.stage = CropField.Stage.GROWING
	tilled.progress = 0.1
	var growing_from := tilled.progress
	tilled.tend(1.0)
	tilled._process(1.0)
	var tended_step := tilled.progress - growing_from
	growing_from = tilled.progress
	tilled._process(1.0)
	_check(tended_step > (tilled.progress - growing_from) * 1.1, "and that makes it grow faster")
	game.settings.goblin_rate = 2.0
	Balance.values["goblin_bounce_below"] = Balance.DEFAULTS["goblin_bounce_below"]
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
	# (creature_friendly_fire of the harm: with a high share it can kill.)
	_check(not bystander.is_alive() or bystander.hp < bystander.max_hp, "the creature's fireball harms villagers a little (%.0f of %.0f left)" % [bystander.hp, bystander.max_hp])
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
	# (No goblins about to fight, so it is not kept from its task.)

	game.settings.goblin_rate = 0.0
	Balance.values["goblin_bounce_below"] = 0.0
	for node in get_tree().get_nodes_in_group("goblins"):
		node.remove_from_group("goblins")
		node.queue_free()
	var fetched := false
	for k in 60:
		await _wait(5.0)
		if mind.last_action.begins_with("lumber"):
			fetched = true
			break
	for other: String in ["food", "stone"] + CreatureMind.SPELLS:
		Balance.values["knowledge_" + other] = Balance.DEFAULTS["knowledge_" + other]
	Balance.values["wander_weight"] = Balance.DEFAULTS["wander_weight"]
	_check(fetched, "the creature fetches a tree for the storehouse (task %s, last action %s, knocked out %s, speed %.1f, %.0f m from the village, target %s %.0f m, action %d)" % [
		mind._task, mind.last_action, beast.knocked_out, beast.speed, beast.global_position.distance_to(village.center), beast.has_target, beast._flat(beast.target, beast.global_position), beast._action])
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

	# Trees: walkers step round their trunks, and a target nobody could
	# reach is left alone for a while.
	var trunk_tree := WorldPopulator.spawn_tree(game.world_root, game.terrain, village.center.x + 40.0, village.center.z - 40.0, 0.0, 11)
	await _wait(0.1)
	_check(game.path_grid().trunk_at(trunk_tree.global_position + Vector3(0.2, 0, 0), 0.3) == trunk_tree, "the path finder knows where the tree trunks are")
	trunk_tree.set_meta("blocked_until", game.now + 60.0)
	_check(village._nearest_free(trunk_tree.global_position, "trees", {}) != trunk_tree, "a tree nobody could get to is left alone for a while")
	trunk_tree.queue_free()

	# Archer posts: an archer climbs a treehouse, shoots twice as far from
	# up there, cannot be reached by goblin blades, and falls with it.
	var perch_spot := _free_spot(play, village.center + Vector3(-30, 0, 30))
	var perch := BuildingFactory.create("treehouse", RandomNumberGenerator.new())
	game.world_root.add_child(perch)
	perch.global_position = perch_spot
	perch.add_to_group("player_buildings")
	var bowman_v: Villager = null
	for v in village.people():
		if v.can_work() and v.job != "train" and not v.fey:
			bowman_v = v
			break
	if bowman_v != null:
		# (The village is not asked for archers, so it is kept from standing this one down.)
		village._army_timer = 1.0e9
		bowman_v.global_position = RopeBridge.ladder_foot(perch) + Vector3(2, 0, 0)
		bowman_v.become_archer(perch_spot)
		for k in 60:
			await _wait(0.5)
			if bowman_v.on_post():
				break
		_check(bowman_v.on_post() and bowman_v.global_position.y > perch.global_position.y + 2.0,
			"an archer climbs a treehouse to stand on it (%s)" % Villager.State.keys()[bowman_v.state])
		_check(is_equal_approx(bowman_v.shot_range(), Villager.ARCHER_RANGE * Balance.num("archer_post_range")), "up there it shoots archer_post_range as far")
		var blade := WorldPopulator.spawn_villager(game.world_root, game.terrain, perch_spot, 1.0, true)
		await _wait(0.1)
		var hp_then := bowman_v.hp
		bowman_v.take_hit(10.0, blade)
		_check(bowman_v.hp == hp_then and blade._nearest_villager(50.0) != bowman_v, "goblins with blades cannot reach it")
		blade.queue_free()
		perch.shatter(perch.global_position, 1.0)
		await _wait(0.5)
		_check(not bowman_v.is_alive(), "and it falls with its post")
		village._army_timer = 0.0

	# Save the game, load it again, and everything is back.
	var save_path := "user://smoke_save.txt"
	_check(SaveGame.save(play, save_path) == "" and not SaveGame.read(save_path).is_empty(), "the game saves to a readable text file")
	var had := {"buildings": get_tree().get_nodes_in_group("player_buildings").size(), "people": village.population(),
		"goblins": get_tree().get_nodes_in_group("goblins").size(), "fields": get_tree().get_nodes_in_group("fields").size(),
		"lumber": village.amount("lumber"), "research": village.researched.size(), "spells": village.spells_known.size(),
		"day": play.day_cycle.day, "kind": game.creature_kind}
	_check(SaveGame.load_game(save_path) == "", "and loads")
	for k in 4:
		await get_tree().process_frame
	play = get_tree().current_scene.get_node("Controller") as PlayMode
	village = play.village
	await _wait(0.5)
	var has := {"buildings": get_tree().get_nodes_in_group("player_buildings").size(), "people": village.population(),
		"goblins": get_tree().get_nodes_in_group("goblins").size(), "fields": get_tree().get_nodes_in_group("fields").size(),
		"lumber": village.amount("lumber"), "research": village.researched.size(), "spells": village.spells_known.size(),
		"day": play.day_cycle.day, "kind": game.creature_kind}
	_check(village.founded and is_instance_valid(play.creature) and has.buildings == had.buildings and absi(has.people - had.people) <= 2
		and has.fields == had.fields and absi(has.lumber - had.lumber) <= 2 and has.research == had.research and has.spells == had.spells
		and has.day == had.day and has.kind == had.kind and absi(has.goblins - had.goblins) <= 2,
		"a loaded game has its buildings, people, fields, resources, research, spells, day and creature back (%s -> %s)" % [had, has])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	# 3. The editor: a small map with starts, a cave and trees, saved.
	await _open(game, "editor", "", 192)
	_check(get_tree().current_scene.get_node("Atmosphere").mood_index == 0, "the map editor is always at noon")
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
	# (A hill short of the grey rock slopes, so its top can be walked to.)
	et.apply_brush(hill, 12.0, Terrain.Brush.RAISE, 4.0)
	var floor_h := et.get_height(hill.x + 13.0, hill.z)
	var climber := WorldPopulator.spawn_villager(game.world_root, et, Vector3(hill.x - 7.0, 0, hill.z), 0.01)
	climber.global_position = Vector3(hill.x - 7.0, et.get_height(hill.x - 7.0, hill.z), hill.z)
	_check(climber._slope_speed(Vector3.RIGHT) < 0.6 and is_equal_approx(climber._slope_speed(Vector3.LEFT), 1.0),
		"walking up a steep slope is slow (%.2f of full speed)" % climber._slope_speed(Vector3.RIGHT))
	et.apply_brush(Vector3(hill.x + 6.0, floor_h, hill.z), 5.0, Terrain.Brush.CUT, 1.0, floor_h)
	_check(et.get_height(hill.x, hill.z) - et.get_height(hill.x + 2.0, hill.z) > 3.0, "the cut brush slices a hill into a sheer cliff")
	climber.global_position = Vector3(hill.x + 1.5, floor_h, hill.z)
	_check(climber._is_cliff(Vector3.LEFT), "a cliff cannot be climbed")
	climber.global_position = Vector3(hill.x + 0.5, et.get_height(hill.x + 0.5, hill.z), hill.z)
	_check(climber._is_cliff(Vector3.RIGHT), "nor walked down")
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
	play.creature.growth_paid = 10  # (its growth is paid for, so it grows)
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
	play.creature.growth_paid = 10  # (its growth is paid for, so it grows)
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
	# Forest seeding: a magic acorn within half the influence of the centre,
	# then a 15, 30 and 60 minute wait; Bless and Condemn count 30 for it.
	var smind := squirrel.mind
	var seed_at: Variant = smind.seed_spot()
	var sv := play.village
	_check(seed_at != null and Vector2((seed_at as Vector3).x - sv.center.x, (seed_at as Vector3).z - sv.center.z).length() <= sv.influence() * 0.5,
		"the squirrel finds a spot for a magic tree within half the influence")
	if seed_at != null:
		squirrel.toss_acorn(seed_at)
		await _wait(3.0)
		var grew := false
		for node in get_tree().get_nodes_in_group("magic_trees"):
			grew = grew or (node as Node3D).global_position.distance_to(seed_at) < 1.0
		_check(grew, "the squirrel tosses a magic acorn, and a magic tree grows where it lands")
	var waits: Array[int] = []
	smind.seeds_thrown = 0  # (it may have seeded on its own already)
	for k in 3:
		smind.seeded()
		waits.append(roundi((smind.seed_ready_at - Game.now) / 60.0))
	_check(waits == [15, 30, 60], "forest seeding waits 15, then 30, then 60 minutes (%s)" % str(waits))
	smind.did("seed", {"battle": false})
	var seed_before: float = smind.behavior.get(smind.judge_target(), 0.0)
	var seed_action := smind.judge_target()
	smind.judge(1)
	_check(seed_action != "" and is_equal_approx(smind.behavior[seed_action], seed_before + 30.0), "Bless counts 30 for forest seeding (%s)" % seed_action)

	# 6. The raven, which flies, and the goblins' balrog.
	game.creature_kind = "raven"
	game.settings.creature_grow_minutes = 0.02
	await _open(game, "play", "", 384)
	play = get_tree().current_scene.get_node("Controller") as PlayMode
	play.day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	var r0: Vector2 = play._info.starts[0]
	play._found(Vector3(r0.x, game.terrain.get_height(r0.x, r0.y), r0.y), 0)
	play.creature.growth_paid = 10  # (its growth is paid for, so it grows)
	await _wait(3.0)
	var raven := play.creature
	raven.mind.process_mode = Node.PROCESS_MODE_DISABLED
	_check(raven.kind == "raven" and raven.size > 0.99 and is_equal_approx(raven.max_hp, Balance.num("raven_health")), "the raven is the player's creature (size %.2f, %d paid, %.0f hp)" % [
		raven.size, raven.growth_paid, raven.max_hp])
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
	# With a load in its arms it walks, however far.
	var far_off := raven.global_position + Vector3(Balance.num("raven_fly_distance") * 3.0, 0, 0)
	var would_fly := raven._should_hurry(far_off, true)
	var load := Node3D.new()
	game.world_root.add_child(load)
	raven.carry(load)
	_check(would_fly and not raven._should_hurry(far_off, true), "the raven walks home with a load instead of flying")
	raven.drop_load()
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
	# It swats giant bats: in the air with its wings, on the ground with a blow.
	play.raids.raiding = true
	var swatted := play.raids.launch_bat()
	if swatted:
		swatted.set_process(false)
		raven.flying = true
		swatted.global_position = raven.global_position + Vector3(2.0, 1.0, 0.0)
		raven._action_cooldown = 0.0
		raven._air_combat()
		raven.flying = false
		_check(not swatted.is_alive(), "the raven knocks a giant bat out of the air")
		if is_instance_valid(swatted):
			swatted.queue_free()
	var low_bat := play.raids.launch_bat()
	if low_bat:
		low_bat.set_process(false)
		low_bat.global_position = raven.global_position + Vector3(2.0, 1.5, 0.0)
		_check(raven._bat_in_reach() == low_bat, "a bat low enough is in reach of a giant on the ground")
		low_bat.queue_free()
	play.raids.raiding = false
	# On an attack move it comes down to fight what it passes on the way.
	var raven_goal := raven.global_position
	var raven_foe_at := raven.global_position
	for k in 48:
		var a := TAU * k / 48.0
		var dir := Vector3(cos(a), 0, sin(a))
		var g := raven.global_position + dir * 90.0
		var fp := raven.global_position + dir * 45.0 + Vector3(-dir.z, 0, dir.x) * 15.0
		if game.terrain.is_inside(g.x, g.z) and game.terrain.is_dry(g.x, g.z) and game.terrain.is_inside(fp.x, fp.z) and game.terrain.is_dry(fp.x, fp.z) \
				and not game.terrain.is_steep(fp.x, fp.z):
			raven_goal = g
			raven_foe_at = fp
			break
	var waylaid := WorldPopulator.spawn_villager(game.world_root, game.terrain, raven_foe_at, 0.5, true)
	waylaid.global_position = Vector3(raven_foe_at.x, game.terrain.get_height(raven_foe_at.x, raven_foe_at.z), raven_foe_at.z)
	waylaid.process_mode = Node.PROCESS_MODE_DISABLED
	raven.mind.process_mode = Node.PROCESS_MODE_DISABLED
	raven.attack_move(raven_goal)
	var came_down := false
	for k in 60:
		await _wait(0.5)
		if not raven.flying and (not is_instance_valid(waylaid) or not waylaid.is_alive() or raven.is_fighting()) and raven._flat(raven_goal, raven.global_position) > 20.0:
			came_down = true
			break
	_check(came_down, "on an attack move the raven lands to fight what it passes (%.0f m short of where it was sent)" % raven._flat(raven_goal, raven.global_position))
	if is_instance_valid(waylaid):
		waylaid.queue_free()
	# (Its mind stays off, as for the checks before: the balrog's come next.)
	raven.has_target = false
	raven.attack_moving = false

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
		# (The raven lands first: the balrog never aims at it in the air.)
		raven.has_target = false
		raven.flying = false
		raven._alt = 0.0
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
