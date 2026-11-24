class_name SaveGame
extends RefCounted
## Saving and loading a game in progress (the pause menu's Save game and
## Load game, and the main menu's Load game).
##
## A save is a plain text file. Its first lines start with # and say what
## it is; the rest is JSON, which a person can read (and, with care, edit):
##   version, game_version, creature_kind, settings (the dev menu's sliders)
##   world      the island: its terrain (long base64 lines: heights, paint,
##              water), trees, boulders, goblin caves and painted paths
##   village    resources, research and spells (known, under way, the
##              spell bar), what the player asked for, births, the boosts
##   day, raids the clock, and the goblins' nights and building
##   buildings  every building: kind, look, place, turn, health, and whose
##   bridges, sites, fields, people, others, goblins, creature, balrogs
## Positions are [x, y, z]. Loading builds the island again from the save
## and puts everything back. Saplings, skeletons, the dead, fires and
## things in flight are not saved.

const VERSION := 1
const DIR_NAME := "saves"
const EXT := ".txt"


## Where saves go by default: a "saves" folder beside the game.
static func default_dir() -> String:
	var base := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	return base.path_join(DIR_NAME)


## Writes the game `play` is playing to `path`. Returns "" or what went wrong.
static func save(play: PlayMode, path: String) -> String:
	if not play.village.founded:
		return "Choose where your village begins before saving."
	var data := collect(play)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write %s (%s)." % [path, error_string(FileAccess.get_open_error())]
	file.store_line("# SpriteSquirter saved game, version %s, saved %s" % [
		ProjectSettings.get_setting("application/config/version", "?"), Time.get_datetime_string_from_system(false, true)])
	file.store_line("# %s, %d villagers. Load it from the main menu or the pause menu (Load game)." % [play.day_cycle.clock_text(), play.village.population()])
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return ""


## Reads a save. Empty if the file is missing, damaged or not a save.
static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var lines: PackedStringArray = []
	while not file.eof_reached():
		var line := file.get_line()
		if not line.begins_with("#"):
			lines.append(line)
	file.close()
	var parsed: Variant = JSON.parse_string("\n".join(lines))
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	for key in ["version", "world", "village", "creature_kind"]:
		if not data.has(key):
			return {}
	if int(data.version) > VERSION:
		return {}
	return data


## Starts the saved game at `path`. Returns "" or what went wrong.
static func load_game(path: String) -> String:
	var data := read(path)
	if data.is_empty():
		return "%s is not a saved game this version can read." % path.get_file()
	var world := _world_from(data.world)
	if world.is_empty():
		return "The island in %s is damaged." % path.get_file()
	Game.creature_kind = str(data.creature_kind)
	var settings: Dictionary = data.get("settings", {})
	for key: String in settings:
		if Game.DEFAULT_SETTINGS.has(key):
			Game.settings[key] = float(settings[key])
	Game.world_seed = int(world.seed)
	Game.start("play", "", int(world.size), false, world)
	Game.session["save"] = data
	return ""


# --- Writing ----------------------------------------------------------------------

static func collect(play: PlayMode) -> Dictionary:
	var tree := play.get_tree()
	var v := play.village
	var caves: Array[Node3D] = []
	for node in tree.get_nodes_in_group("caves"):
		caves.append(node as Node3D)
	var data := {
		"version": VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"creature_kind": Game.creature_kind,
		"settings": Game.settings.duplicate(),
		"world": _world(play, caves),
		"village": {
			"center": _vec(v.center), "resources": v.resources.duplicate(), "wanted": v.wanted.duplicate(),
			"researched": v.researched.keys(), "research_jobs": v.research_jobs.duplicate(true),
			"spells_known": v.spells_known.keys(), "spell_slots": Array(v.spell_slots), "spell_jobs": v.spell_jobs.duplicate(true),
			"birth_progress": v.birth_progress, "hungry_for": v.hungry_for, "stored": v._stored.duplicate(),
			"fey_left": maxf(0.0, v.fey_until - Game.now), "blood_left": maxf(0.0, v.blood_until - Game.now),
			"stuck_reports": v._stuck_reports,
		},
		"cooldowns": play._cooldowns.duplicate(),
		"day": {"time": play.day_cycle.time, "day": play.day_cycle.day},
		"raids": {"nights": play.raids.nights, "build_timer": play.raids._build_timer, "balrog_timer": play.raids._balrog_timer,
			"kinds_left": Array(play.raids._kinds_left)},
		"buildings": [], "bridges": [], "sites": [], "fields": [], "people": [], "others": [], "goblins": [], "balrogs": [],
	}
	# Buildings (and, for bridges, which two they join).
	var index := {}
	for node in tree.get_nodes_in_group("buildings"):
		var b := node as Destructible
		if b == null or b.destroyed or b is RopeBridge or b.is_ghost:
			continue
		var side := "player" if b.is_in_group("player_buildings") else ("goblin" if b.is_in_group("goblin_buildings") else "none")
		var entry := {"kind": b.get_meta("kind", ""), "pos": _vec(b.global_position), "rot": b.rotation.y, "hp": b.hp, "side": side}
		if b.has_meta("look_state"):
			entry["look"] = str(b.get_meta("look_state"))
		if b.has_meta("cave"):
			entry["cave"] = caves.find(b.get_meta("cave"))
		index[b] = (data.buildings as Array).size()
		(data.buildings as Array).append(entry)
	for node in tree.get_nodes_in_group("bridges"):
		var bridge := node as RopeBridge
		if bridge.usable() and index.has(bridge.a) and index.has(bridge.b):
			(data.bridges as Array).append({"a": index[bridge.a], "b": index[bridge.b], "length": bridge.length, "ya": bridge.ya, "yb": bridge.yb,
				"pos": _vec(bridge.global_position), "rot": bridge.rotation.y})
	for node in tree.get_nodes_in_group("construction_sites") + tree.get_nodes_in_group("goblin_sites"):
		var site := node as ConstructionSite
		if site == null:
			continue
		var entry := {"kind": site.kind, "look": site.look_seed, "cost": site.cost.duplicate(), "goblin": site.goblin, "progress": site.progress,
			"pos": _vec(site.global_position), "rot": site.rotation.y}
		if site.kind == "bridge":
			if site.ends.size() < 2 or not index.has(site.ends[0]) or not index.has(site.ends[1]):
				continue
			entry["spec"] = site.spec.duplicate()
			entry["ends"] = [index[site.ends[0]], index[site.ends[1]]]
		if site.has_meta("cave"):
			entry["cave"] = caves.find(site.get_meta("cave"))
		(data.sites as Array).append(entry)
	for node in tree.get_nodes_in_group("fields"):
		var field := node as CropField
		(data.fields as Array).append({"pos": _vec(field.global_position), "rot": field.rotation.y, "size": [field.size.x, field.size.y],
			"stage": int(field.stage), "progress": field.progress, "sprouted": field.sprouted})
	# People: the village's, the other villages', and the goblins.
	for node in tree.get_nodes_in_group("villagers"):
		var p := node as Villager
		if p == null or not p.is_alive() or p.skeleton:
			continue
		var entry := {"pos": _vec(p.global_position), "hp": p.hp, "home": _vec(p.home), "home_radius": p.home_radius}
		if p.goblin:
			entry["ogre"] = p.ogre
			entry["archer"] = p.archer
			(data.goblins as Array).append(entry)
		elif p.owned:
			entry["child"] = p.child
			entry["age"] = p._age
			entry["fey"] = p.fey
			entry["pin"] = p.pin
			entry["role"] = _role(p)
			(data.people as Array).append(entry)
		else:
			entry["child"] = p.child
			(data.others as Array).append(entry)
	var c := play.creature
	if is_instance_valid(c):
		data["creature"] = {"pos": _vec(c.global_position), "yaw": c.rotation.y, "age": c.age, "growth_paid": c.growth_paid,
			"hp": c.hp, "dead": c.knocked_out, "levels": c.levels.duplicate(), "used": c.used.duplicate(),
			"stamina": c.stamina, "magicko": c.magicko,
			"knowledge": c.mind.knowledge.duplicate(true), "behavior": c.mind.behavior.duplicate(true), "seeds_thrown": c.mind.seeds_thrown}
	for node in tree.get_nodes_in_group("balrogs"):
		var b := node as Balrog
		if b != null and not b.knocked_out:
			(data.balrogs as Array).append({"pos": _vec(b.global_position), "age": b.age, "hp": b.hp})
	return data


static func _role(p: Villager) -> String:
	if p.necromancer:
		return "necromancer"
	if p.wizard:
		return "wizard"
	if p.fey_archer:
		return "fey_archer"
	if p.archer:
		return "archer"
	if p.soldier:
		return "warrior"
	return ""


## The island, as MapData has it (the terrain's layers as base64 text).
static func _world(play: PlayMode, caves: Array[Node3D]) -> Dictionary:
	var t := Game.terrain
	var map := t.export_map()
	var out := {"seed": map.seed, "size": map.size, "palette": Art.palette_index, "rivers": []}
	for key in ["heights", "bare", "water", "sand", "rock"]:
		out[key] = Marshalls.raw_to_base64((map[key] as PackedFloat32Array).to_byte_array())
	out["island"] = Marshalls.raw_to_base64(map.island as PackedByteArray)
	for river: PackedVector2Array in map.rivers:
		var points := []
		for p in river:
			points.append([p.x, p.y])
		(out.rivers as Array).append(points)
	var trees := []
	for node in play.get_tree().get_nodes_in_group("trees"):
		var tr := node as Destructible
		if tr == null or tr.destroyed or not tr.has_meta("seed"):
			continue
		trees.append([tr.global_position.x, tr.global_position.z, tr.rotation.y, int(tr.get_meta("seed"))])
	out["trees"] = trees
	var rocks := []
	for node in play.get_tree().get_nodes_in_group("rocks"):
		var r := node as Node3D
		rocks.append([r.global_position.x, r.global_position.z, int(r.get_meta("seed", 0)), r.scale.x, float(r.get_meta("stone", -1.0))])
	out["rocks"] = rocks
	var cave_list := []
	for cave in caves:
		cave_list.append({"pos": [cave.global_position.x, cave.global_position.z], "facing": float(cave.get_meta("facing", 0.0))})
	out["caves"] = cave_list
	var paths := []
	for path: PackedVector2Array in play.raids.paths:
		var points := []
		for p in path:
			points.append([p.x, p.y])
		paths.append(points)
	out["paths"] = paths
	return out


# --- Reading ----------------------------------------------------------------------

## The saved island as a MapData map, for Main to build.
static func _world_from(w: Dictionary) -> Dictionary:
	var size := int(w.get("size", 0))
	if not Terrain.valid_size(size):
		return {}
	var n := (size + 1) * (size + 1)
	var map := {"name": "Saved game", "seed": int(w.get("seed", 0)), "size": size, "palette": int(w.get("palette", 0)),
		"starts": PackedVector2Array(), "rivers": [], "trees": [], "rocks": [], "caves": [], "paths": []}
	for key in ["heights", "bare", "water", "sand", "rock"]:
		var layer := Marshalls.base64_to_raw(str(w.get(key, ""))).to_float32_array()
		if layer.size() != n:
			return {}
		map[key] = layer
	var island := Marshalls.base64_to_raw(str(w.get("island", "")))
	if island.size() != n:
		return {}
	map["island"] = island
	for river: Array in w.get("rivers", []):
		var points := PackedVector2Array()
		for p: Array in river:
			points.append(Vector2(p[0], p[1]))
		(map.rivers as Array).append(points)
	for t: Array in w.get("trees", []):
		(map.trees as Array).append([float(t[0]), float(t[1]), float(t[2]), int(t[3])])
	for r: Array in w.get("rocks", []):
		(map.rocks as Array).append([float(r[0]), float(r[1]), int(r[2]), float(r[3])])
	for c: Dictionary in w.get("caves", []):
		(map.caves as Array).append({"pos": Vector2(c.pos[0], c.pos[1]), "facing": float(c.facing)})
	for path: Array in w.get("paths", []):
		var points := PackedVector2Array()
		for p: Array in path:
			points.append(Vector2(p[0], p[1]))
		(map.paths as Array).append(points)
	return map


## Puts the saved game back once its island is built (PlayMode calls it
## instead of asking where the village begins).
static func restore(play: PlayMode, d: Dictionary) -> void:
	var tree := play.get_tree()
	var root := Game.world_root
	var terrain := Game.terrain
	var v := play.village
	var caves: Array[Node3D] = []
	for node in tree.get_nodes_in_group("caves"):
		caves.append(node as Node3D)
	# (The caves come back in their saved order.)
	var saved_caves: Array = d.world.get("caves", [])
	var cave_of := func(k: int) -> Node3D:
		if k < 0 or k >= saved_caves.size():
			return null
		var at := Vector2(saved_caves[k].pos[0], saved_caves[k].pos[1])
		var best: Node3D = null
		for cave in caves:
			if best == null or Vector2(cave.global_position.x, cave.global_position.z).distance_to(at) < Vector2(best.global_position.x, best.global_position.z).distance_to(at):
				best = cave
		return best
	# What is left in each boulder.
	var rock_list: Array = d.world.get("rocks", [])
	for node in tree.get_nodes_in_group("rocks"):
		var r := node as Node3D
		for saved: Array in rock_list:
			if saved.size() > 4 and float(saved[4]) >= 0.0 and absf(float(saved[0]) - r.global_position.x) < 0.01 and absf(float(saved[1]) - r.global_position.z) < 0.01:
				r.set_meta("stone", float(saved[4]))
				break

	# The village.
	var vd: Dictionary = d.village
	v.founded = true
	v.center = _v3(vd.center)
	for res: String in vd.get("resources", {}):
		v.resources[res] = float(vd.resources[res])
	for role: String in vd.get("wanted", {}):
		if v.wanted.has(role):
			v.wanted[role] = int(vd.wanted[role])
	for id: String in vd.get("researched", []):
		v.researched[id] = true
	v.barrows = v.has_research("wheelbarrows")
	for place: String in vd.get("research_jobs", {}):
		if v.research_jobs.has(place):
			v.research_jobs[place] = (vd.research_jobs[place] as Array).duplicate(true)
	v._bar()
	var slots: Array = vd.get("spell_slots", [])
	for k in mini(slots.size(), v.spell_slots.size()):
		v.spell_slots[k] = str(slots[k])
	for id: String in vd.get("spells_known", []):
		v.spells_known[id] = true
	v.spell_jobs = (vd.get("spell_jobs", []) as Array).duplicate(true)
	v.birth_progress = float(vd.get("birth_progress", 0.0))
	v.hungry_for = float(vd.get("hungry_for", 0.0))
	v._stored = (vd.get("stored", {}) as Dictionary).duplicate()
	v.fey_until = Game.now + float(vd.get("fey_left", 0.0))
	v.blood_until = Game.now + float(vd.get("blood_left", 0.0))
	v._stuck_reports = int(vd.get("stuck_reports", 0))
	var cooldowns: Array = d.get("cooldowns", [])
	for k in mini(cooldowns.size(), play._cooldowns.size()):
		play._cooldowns[k] = float(cooldowns[k])

	# The clock and the goblins.
	play.day_cycle.time = float(d.day.time)
	play.day_cycle.day = int(d.day.day)
	play.day_cycle.process_mode = Node.PROCESS_MODE_INHERIT
	var rd: Dictionary = d.get("raids", {})
	play.raids.nights = int(rd.get("nights", 0))
	play.raids._build_timer = float(rd.get("build_timer", 0.0))
	play.raids._balrog_timer = float(rd.get("balrog_timer", 3.0))
	play.raids._kinds_left.assign(rd.get("kinds_left", []))

	# Buildings, then the bridges between them and what is being built.
	var made: Array[Destructible] = []
	for b: Dictionary in d.get("buildings", []):
		var rng := RandomNumberGenerator.new()
		if b.has("look"):
			rng.state = int(str(b.look))
		var node := BuildingFactory.create(str(b.kind), rng)
		root.add_child(node)
		node.global_position = _v3(b.pos)
		node.rotation.y = float(b.rot)
		node.hp = minf(float(b.hp), node.max_hp)
		match str(b.side):
			"player":
				node.add_to_group("player_buildings")
			"goblin":
				node.add_to_group("goblin_buildings")
		if b.has("cave"):
			var cave: Node3D = cave_of.call(int(b.cave))
			if cave != null:
				node.set_meta("cave", cave)
		made.append(node)
	for br: Dictionary in d.get("bridges", []):
		var bridge := BuildingFactory.create_bridge(float(br.length), float(br.ya), float(br.yb))
		bridge.a = made[int(br.a)]
		bridge.b = made[int(br.b)]
		root.add_child(bridge)
		bridge.global_position = _v3(br.pos)
		bridge.rotation.y = float(br.rot)
		bridge.add_to_group("player_buildings")
	for s: Dictionary in d.get("sites", []):
		var site := ConstructionSite.new()
		var cost := {}
		for res: String in s.get("cost", {}):
			cost[res] = float(s.cost[res])
		if str(s.kind) == "bridge":
			site.spec = {"length": float(s.spec.length), "ya": float(s.spec.ya), "yb": float(s.spec.yb)}
			site.ends = [made[int(s.ends[0])], made[int(s.ends[1])]]
		site.setup(str(s.kind), int(s.look), cost, bool(s.goblin))
		if s.has("cave"):
			var cave: Node3D = cave_of.call(int(s.cave))
			if cave != null:
				site.set_meta("cave", cave)
				site.completed.connect(func(built: Destructible) -> void:
					built.set_meta("cave", cave)
					play.raids._on_built(built))
		root.add_child(site)
		site.global_position = _v3(s.pos)
		site.rotation.y = float(s.rot)
		site.progress = float(s.progress)
		site._update_visual()
	for f: Dictionary in d.get("fields", []):
		var field := CropField.new()
		field.setup(Vector2(f.size[0], f.size[1]))
		field.position = _v3(f.pos)
		field.rotation.y = float(f.rot)
		root.add_child(field)
		field.stage = int(f.stage) as CropField.Stage
		field.progress = float(f.progress)
		field.sprouted = float(f.get("sprouted", 0.0))
		field._refresh()

	# The village's people.
	for p: Dictionary in d.get("people", []):
		var at := _v3(p.pos)
		var person := WorldPopulator.spawn_villager(root, terrain, at, 0.01, false, true, bool(p.child), bool(p.fey))
		person.global_position = Vector3(at.x, terrain.get_height(at.x, at.z), at.z)
		person.home = v.center
		person.home_radius = PlayerVillage.HOME_RADIUS
		if bool(p.child):
			person._age = float(p.get("age", 0.0))
			person._grow(0.0)
		person.pin = str(p.get("pin", ""))
		var role := str(p.get("role", ""))
		var post := _nearest_with_role(tree, at, "necro" if role == "necromancer" else ("wizard" if role == "wizard" else "guard"))
		var post_at := post.global_position if post != null else v.center
		match role:
			"warrior":
				person.guard = post
				person.become_soldier(post_at)
				if v.has_research("swords"):
					person.sharpen()
			"archer":
				person.guard = post
				person.become_archer(post_at)
			"fey_archer":
				person.guard = post
				person.become_fey_archer(post_at)
			"wizard":
				person.become_wizard(post_at)
			"necromancer":
				person.become_wizard(post_at)
				person.become_necromancer(post_at)
		person.hp = minf(float(p.hp), person.max_hp)
	for p: Dictionary in d.get("others", []):
		var at := _v3(p.pos)
		var other := WorldPopulator.spawn_villager(root, terrain, _v3(p.home), float(p.home_radius), false, false, bool(p.child))
		other.global_position = Vector3(at.x, terrain.get_height(at.x, at.z), at.z)
	# The goblins, and each war hut's ogres.
	var ogres: Array[Villager] = []
	for g: Dictionary in d.get("goblins", []):
		var at := _v3(g.pos)
		var goblin: Villager
		if bool(g.ogre):
			goblin = Villager.new()
			goblin.goblin = true
			goblin.ogre = true
			goblin.home = _v3(g.home)
			goblin.home_radius = float(g.home_radius)
			root.add_child(goblin)
			ogres.append(goblin)
		else:
			goblin = WorldPopulator.spawn_villager(root, terrain, _v3(g.home), float(g.home_radius), true)
			if bool(g.get("archer", false)):
				goblin.become_goblin_archer()
		goblin.global_position = Vector3(at.x, terrain.get_height(at.x, at.z), at.z)
		goblin.hp = minf(float(g.hp), goblin.max_hp)
	for hut in play.raids.standing(GoblinRaids.OGRE_HOME):
		var living: Array = []
		for ogre in ogres:
			if ogre.home.distance_to(hut.global_position) < 12.0:
				living.append(ogre)
		hut.set_meta("ogres", living)

	# The creature and the balrogs.
	var cd: Dictionary = d.get("creature", {})
	if not cd.is_empty():
		var beast := play._make_creature(_v3(cd.pos), float(cd.yaw))
		beast.age = float(cd.age)
		beast.growth_paid = int(cd.growth_paid)
		beast._grow(0.0)
		for stat: String in cd.get("levels", {}):
			beast.levels[stat] = int(cd.levels[stat])
		for stat: String in cd.get("used", {}):
			beast.used[stat] = float(cd.used[stat])
		beast._grow(0.0)
		beast.hp = clampf(float(cd.hp), 1.0, beast.max_hp)
		beast.stamina = float(cd.get("stamina", beast.stamina))
		beast.magicko = float(cd.get("magicko", beast.magicko))
		for key: String in cd.get("knowledge", {}):
			beast.mind.knowledge[key] = cd.knowledge[key]
		for key: String in cd.get("behavior", {}):
			beast.mind.behavior[key] = cd.behavior[key]
		beast.mind.seeds_thrown = int(cd.get("seeds_thrown", 0))
	for bd: Dictionary in d.get("balrogs", []):
		var balrog := play.raids.hatch_balrog(true)
		if balrog == null:
			break
		balrog.age = float(bd.age)
		balrog._grow(0.0)
		var at := _v3(bd.pos)
		balrog.global_position = Vector3(at.x, terrain.get_height(at.x, at.z), at.z)
		balrog.hp = clampf(float(bd.hp), 1.0, balrog.max_hp)
	play.hud.set_spell_slots(v.spell_slots)
	Game.camera_rig.focus_on(v.center)
	Game.camera_rig.set_zoom(75.0)


static func _nearest_with_role(tree: SceneTree, at: Vector3, role: String) -> Destructible:
	var best: Destructible = null
	for node in tree.get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if b != null and not b.destroyed and BuildingCatalog.role(b.get_meta("kind", "")) == role:
			if best == null or b.global_position.distance_to(at) < best.global_position.distance_to(at):
				best = b
	return best


static func _vec(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


static func _v3(a: Variant) -> Vector3:
	var list: Array = a
	return Vector3(float(list[0]), float(list[1]), float(list[2]))
