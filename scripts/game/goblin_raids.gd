class_name GoblinRaids
extends Node
## Grows the goblin camps and sends the goblins against the player's village.
##
## Every cave that was there when the game began spawns goblins all the
## time, at Game.settings.goblin_rate per minute, and the rate goes up by
## goblin_rate_growth every night. Halfway through each night every goblin
## leaves its cave and marches on the village; in the morning the survivors
## go home. Once a raid has GOBLINS_PER_OGRE goblins an ogre joins it, and
## another for every GOBLINS_PER_OGRE more, and Balance "bats_per_raid"
## giant bats fly out to carry villagers off. Call setup() with the DayCycle.
##
## The goblins have a giant of their own, the Balrog (Balance "balrogs" of
## them). It hatches at a cave soon after the village is founded, guards the
## cave while it grows, and marches with the raids once it is full grown.
## When one dies the next hatches "balrog_respawn_minutes" later.
##
## The goblins build, too. Every Balance "goblin_build_minutes" they mark
## out one of BuildingFactory.GOBLIN_KINDS near one of their caves, and up
## to BUILDERS goblins put it up, going back to the cave now and then for
## what they build with (the goblins' resources are not counted). They stop
## at "goblin_buildings_max" buildings.

signal raid_started(goblins: int, ogres: int)
signal raid_ended
## A giant bat has snatched one of the player's villagers.
signal bat_took
signal balrog_came
signal balrog_grown
signal balrog_died

const GOBLINS_PER_OGRE := 15
const BUILDERS := 3
## How near a painted path's ends must be to the goblin's cave and to the village.
const PATH_SNAP := 45.0

var raiding := false
## Nights since the game began (counted at nightfall).
var nights := 0

## Paths painted in the map editor, each from a cave to a start location.
var paths: Array = []

var _caves: Array[Node3D] = []
var _spawned := {}
var _build_timer := 0.0
var _site_timer := 0.0
## Seconds until the next balrog hatches (if there is room for one).
var _balrog_timer := 3.0
## Balrogs that set out with the raid that is on.
var marching := 0


func setup(day_cycle: DayCycle) -> void:
	day_cycle.nightfall.connect(func() -> void: nights += 1)
	day_cycle.midnight.connect(start_raid)
	day_cycle.morning.connect(end_raid)
	for node in get_tree().get_nodes_in_group("caves"):
		_caves.append(node as Node3D)


## Goblins each starting cave spawns per minute tonight.
func spawn_rate() -> float:
	return maxf(0.0, Game.settings.goblin_rate + nights * Game.settings.goblin_rate_growth)


func _process(delta: float) -> void:
	var village := Game.village
	if village == null or not village.founded:
		return
	var rate := spawn_rate() / 60.0 * delta
	for cave in _caves:
		if not is_instance_valid(cave):
			continue
		var due: float = _spawned.get(cave, 0.0) + rate
		while due >= 1.0:
			due -= 1.0
			spawn_at(cave)
		_spawned[cave] = due
	if get_tree().get_nodes_in_group("balrogs").size() < roundi(Balance.num("balrogs")):
		_balrog_timer -= delta
		if _balrog_timer <= 0.0:
			_balrog_timer = Balance.num("balrog_respawn_minutes") * 60.0
			hatch_balrog()
	_build_timer += delta
	if _build_timer >= Balance.num("goblin_build_minutes") * 60.0:
		_build_timer = 0.0
		start_building()
	_site_timer -= delta
	if _site_timer <= 0.0:
		_site_timer = 1.0
		_manage_builders()


## A new balrog, as small as a newborn creature, at one of the caves.
func hatch_balrog() -> Balrog:
	var caves: Array[Node3D] = []
	for cave in _caves:
		if is_instance_valid(cave):
			caves.append(cave)
	if caves.is_empty():
		return null
	var balrog := Balrog.new()
	balrog.name = "Balrog"
	Game.world_root.add_child(balrog)
	balrog.settle(caves[randi() % caves.size()])
	balrog.grew_up.connect(func() -> void: balrog_grown.emit())
	balrog.died.connect(func() -> void:
		_balrog_timer = Balance.num("balrog_respawn_minutes") * 60.0
		balrog_died.emit())
	balrog_came.emit()
	return balrog


# --- Building ---------------------------------------------------------------------

## Marks out a new goblin building near a cave. Returns its site, or null
## if the goblins have enough or there is no room.
func start_building() -> ConstructionSite:
	var tree := get_tree()
	var have := tree.get_nodes_in_group("goblin_buildings").size() + tree.get_nodes_in_group("goblin_sites").size()
	var caves: Array[Node3D] = []
	for cave in _caves:
		if is_instance_valid(cave):
			caves.append(cave)
	if caves.is_empty() or have >= roundi(Balance.num("goblin_buildings_max")):
		return null
	var kind: String = BuildingFactory.GOBLIN_KINDS[randi() % BuildingFactory.GOBLIN_KINDS.size()]
	var footprint := 3.4
	var terrain := Game.terrain
	for attempt in 40:
		var cave := caves[randi() % caves.size()]
		var a: float = cave.get_meta("facing", 0.0) + randf_range(-2.0, 2.0)
		var p := cave.global_position + Vector3(sin(a), 0.0, cos(a)) * randf_range(17.0, 26.0 + attempt)
		if not _site_ok(p, footprint):
			continue
		var h := terrain.average_height(p, footprint)
		terrain.apply_brush(Vector3(p.x, h, p.z), footprint + 3.0, Terrain.Brush.FLATTEN, 1.0, h, footprint / (footprint + 3.0))
		for node in tree.get_nodes_in_group("trees"):
			var t := node as Destructible
			if Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length() < footprint + 1.5:
				t.fell()
		var site := ConstructionSite.new()
		site.setup(kind, randi(), {"resources": Balance.num(kind + "_resources")}, true)
		site.set_meta("cave", cave)
		Game.world_root.add_child(site)
		site.global_position = Vector3(p.x, h, p.z)
		# The door looks back towards the cave, more or less.
		site.rotation.y = a + PI + randf_range(-0.6, 0.6)
		return site
	return null


func _site_ok(p: Vector3, footprint: float) -> bool:
	var terrain := Game.terrain
	if not terrain.is_inside(p.x, p.z) or not terrain.is_dry(p.x, p.z) or terrain.get_normal(p.x, p.z).y < 0.9:
		return false
	# Well clear of the player's village (and of the creature that guards it).
	var village := Game.village
	if is_instance_valid(village) and village.founded and (village.in_territory(p) or village.center.distance_to(p) < 62.0):
		return false
	for group in ["buildings", "construction_sites", "goblin_sites"]:
		for node in get_tree().get_nodes_in_group(group):
			var b := node as Node3D
			var other: float = b.get("footprint")
			if Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < other + footprint + 2.0:
				return false
	for node in get_tree().get_nodes_in_group("caves"):
		var c := node as Node3D
		if Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < 15.0 + footprint:
			return false
	for node in get_tree().get_nodes_in_group("fields"):
		if (node as CropField).contains(p, footprint):
			return false
	return true


## Keeps up to BUILDERS goblins on each site, and sends each back to the
## cave for another load every so often.
func _manage_builders() -> void:
	var goblins := get_tree().get_nodes_in_group("goblins")
	for node in get_tree().get_nodes_in_group("goblin_sites"):
		var site := node as ConstructionSite
		var cave := site.get_meta("cave") as Node3D
		var crew: Array[Villager] = []
		for g_node in goblins:
			var g := g_node as Villager
			if g.job == "build" and g.job_target == site:
				crew.append(g)
		while crew.size() < BUILDERS:
			var best: Villager = null
			var best_d := 70.0
			for g_node in goblins:
				var g := g_node as Villager
				if g.job != "" or g.raiding or g.ogre or not g.is_alive() or g.state == Villager.State.HELD:
					continue
				var d := g.global_position.distance_to(site.global_position)
				if d < best_d:
					best_d = d
					best = g
			if best == null:
				break
			best.assign_job("build", site.work_spot(crew.size(), BUILDERS), site)
			best.set_meta("fetch_at", Game.now + randf_range(10.0, 25.0))
			best.set_meta("fetching", false)
			crew.append(best)
		if not is_instance_valid(cave):
			continue
		var facing: float = cave.get_meta("facing", 0.0)
		for k in crew.size():
			var g := crew[k]
			if g.raiding or not g.is_working():
				continue
			if g.get_meta("fetching", false):
				# At the cave: shoulder a load and carry it back.
				g.carry_pack("stone" if randf() < 0.4 else "lumber")
				g.assign_job("build", site.work_spot(k, BUILDERS), site)
				g.set_meta("fetching", false)
				g.set_meta("fetch_at", Game.now + randf_range(18.0, 30.0))
			else:
				g.carry_pack("")
				if Game.now > g.get_meta("fetch_at", 0.0):
					var a := facing + randf_range(-0.5, 0.5)
					g.assign_job("build", cave.global_position + Vector3(sin(a), 0.0, cos(a)) * randf_range(3.0, 5.0), site)
					g.set_meta("fetching", true)


## One new goblin crawls out of the cave and joins its camp.
func spawn_at(cave: Node3D) -> Villager:
	var facing: float = cave.get_meta("facing", 0.0)
	var front := Vector3(sin(facing), 0.0, cos(facing))
	var g := WorldPopulator.spawn_villager(Game.world_root, Game.terrain, cave.global_position + front * 10.0, 9.0, true)
	var mouth := cave.global_position + front * randf_range(2.0, 4.0)
	g.global_position = Vector3(mouth.x, Game.terrain.get_height(mouth.x, mouth.z), mouth.z)
	return g


func start_raid() -> void:
	var village := Game.village
	if village == null or not village.founded:
		return
	_muster_ogres()
	var count := 0
	var ogres := 0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		var a := randf() * TAU
		g.start_raid(village.center + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 10.0), _route_for(g.home))
		if g.raiding and g.ogre:
			ogres += 1
		elif g.raiding:
			count += 1
	# A full-grown balrog comes too.
	marching = 0
	for node in get_tree().get_nodes_in_group("balrogs"):
		var balrog := node as Balrog
		if balrog.grown() >= 1.0:
			balrog.start_raid(village.center, _route_for(balrog.global_position))
			marching += 1
	raiding = count + ogres + marching > 0
	if raiding:
		raid_started.emit(count, ogres)
		for k in roundi(Balance.num("bats_per_raid")):
			get_tree().create_timer(6.0 + 9.0 * k + randf() * 4.0, false).timeout.connect(launch_bat)


## A giant bat flies out of one of the caves to carry off a villager.
func launch_bat() -> GiantBat:
	var caves: Array[Node3D] = []
	for cave in _caves:
		if is_instance_valid(cave):
			caves.append(cave)
	if caves.is_empty() or not raiding:
		return null
	var bat := GiantBat.new()
	bat.cave = caves[randi() % caves.size()]
	Game.world_root.add_child(bat)
	bat.global_position = bat.cave.global_position + Vector3.UP * 7.0
	bat.took.connect(func(_victim: Villager) -> void: bat_took.emit())
	return bat


## The way a goblin (or the balrog) whose camp is at `from` takes to the
## village: one of the map's painted paths that runs from near there to
## near the village, picked at random and shifted a little to one side so
## the goblins do not walk in single file. Empty if the map has none (the
## goblin then finds its own way).
func _route_for(from: Vector3) -> PackedVector3Array:
	var village := Game.village
	var fits: Array[PackedVector2Array] = []
	for path: PackedVector2Array in paths:
		if path.size() < 2:
			continue
		var first := path[0]
		var last := path[path.size() - 1]
		if Vector2(from.x, from.z).distance_to(first) < PATH_SNAP and Vector2(village.center.x, village.center.z).distance_to(last) < PATH_SNAP:
			fits.append(path)
	var out := PackedVector3Array()
	if fits.is_empty():
		return out
	var path := fits[randi() % fits.size()]
	var a := randf() * TAU
	var aside := Vector2(cos(a), sin(a)) * randf_range(0.0, 4.0)
	for k in range(1, path.size()):
		var p := path[k] + aside
		out.append(Vector3(p.x, 0.0, p.y))
	return out


## One ogre for every GOBLINS_PER_OGRE goblins in the raid. New ones come
## out of the caves in turn.
func _muster_ogres() -> void:
	var caves := get_tree().get_nodes_in_group("caves")
	if caves.is_empty():
		return
	var have := get_tree().get_nodes_in_group("ogres").size()
	@warning_ignore("integer_division")
	var wanted := (get_tree().get_nodes_in_group("goblins").size() - have) / GOBLINS_PER_OGRE
	for k in range(have, wanted):
		var cave := caves[k % caves.size()] as Node3D
		var facing: float = cave.get_meta("facing", 0.0)
		var front := Vector3(sin(facing), 0.0, cos(facing))
		var ogre := Villager.new()
		ogre.goblin = true
		ogre.ogre = true
		ogre.home = cave.global_position + front * 10.0
		ogre.home_radius = 9.0
		Game.world_root.add_child(ogre)
		var mouth := cave.global_position + front * 5.0
		ogre.global_position = Vector3(mouth.x, Game.terrain.get_height(mouth.x, mouth.z), mouth.z)
		ogre.rotation.y = facing


func end_raid() -> void:
	for node in get_tree().get_nodes_in_group("raiders"):
		(node as Villager).end_raid()
	for node in get_tree().get_nodes_in_group("bats"):
		(node as GiantBat).go_home()
	for node in get_tree().get_nodes_in_group("balrogs"):
		(node as Balrog).end_raid()
	if raiding:
		raiding = false
		raid_ended.emit()
