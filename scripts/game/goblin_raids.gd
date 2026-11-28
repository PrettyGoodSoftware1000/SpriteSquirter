class_name GoblinRaids
extends Node
## Grows the goblin camps and sends the goblins against the player's village.
##
## Every cave that was there when the game began spawns goblins all the
## time, at Game.settings.goblin_rate per minute (it does not rise by the
## night). Every finished goblin building adds
## Balance "goblin_rate_per_building" more at its cave. At nightfall every
## goblin leaves its cave and marches on the village; in the morning the
## survivors go home. Call setup() with the DayCycle.
##
## Ogres and giant bats come from what the goblins have built. Every war
## hut (OGRE_HOME) keeps Balance "ogres_per_war_hut" ogres: they appear when
## it is finished, and any that have died are replaced at the next
## nightfall. Every watchtower (BAT_HOME) sends "bats_per_watchtower" giant
## bats with each raid to carry villagers off, from night "bats_from_night"
## on. No hut, no ogres; no tower, no bats.
##
## The goblins have a giant of their own, the Balrog (Balance "balrogs" of
## them). It hatches at a cave soon after the village is founded, guards the
## cave while it grows, and marches with the raids once it is full grown.
## When one dies the next hatches "balrog_respawn_minutes" later.
##
## The goblins build, too. Every Balance "goblin_build_minutes" (divided by
## the dev menu's goblin build speed, which also hurries the builders) they
## mark out one of BuildingFactory.GOBLIN_KINDS near one of their caves (one
## at a time: not until the last one is finished), and up to BUILDERS
## goblins put it up, going back to the cave now and then for what they
## build with (the goblins' resources are not counted). Builders stay at
## home when the others raid, and keep at it until the building is
## finished. They stop at "goblin_buildings_max" buildings. They build one
## of each kind, in a random order, before starting on the kinds again.
## When there is no room where they first look they look further from the
## cave, and if there is still none they try again a little later.
##
## A goblin that crawls out of a cave is a Goblin Archer one time in four
## (Balance "goblin_archer_chance"): it shoots from afar, at the flying
## creature and at archers on their posts too.
##
## Neutral villages (NeutralVillage) make the goblins stronger: every one
## there was when the game began adds Balance "neutral_goblin_spawn"
## goblins a minute at every starting cave, and "neutral_goblin_build_speed"
## percent to how fast the goblins build (neutral_start). The raids go for
## them too: each goblin marches on the player's village or on one of the
## neutral villages, picked at random. A neutral village the goblins wipe
## out (nobody left, nothing standing) becomes a goblin cave (add_cave()).

signal raid_started(goblins: int, ogres: int)
## Goblins have set out for the neutral villages (and none for the player's).
signal neutral_raid_started(goblins: int)
signal raid_ended
## A giant bat has snatched one of the player's villagers.
signal bat_took
signal balrog_came
signal balrog_grown
signal balrog_died
## A cave was brought down (see hurt_cave()).
signal cave_fell

## The goblin buildings that ogres and giant bats come from.
const OGRE_HOME := "goblin_war_hut"
const BAT_HOME := "goblin_watchtower"
const BUILDERS := 3
## How soon the goblins look again for somewhere to build, when they found nowhere.
const RETRY_SECONDS := 10.0
## How near a painted path's ends must be to the goblin's cave and to the village.
const PATH_SNAP := 45.0

var raiding := false
## Nights since the game began (counted at nightfall).
var nights := 0
## How many neutral villages there were when the game began.
static var neutral_start := 0

## Paths painted in the map editor, each from a cave to a start location.
var paths: Array = []

var _caves: Array[Node3D] = []
var _spawned := {}
## Goblin population bounce back: true from when the goblins fall below
## Balance "goblin_bounce_below" until they are back to
## "goblin_bounce_until"; meanwhile they spawn at least
## "goblin_bounce_rate" a minute in all.
var bouncing := false
var _bounce_due := 0.0
var _build_timer := 0.0
var _site_timer := 0.0
## Seconds until the next balrog hatches (if there is room for one).
var _balrog_timer := 3.0
## The kinds of building the goblins have yet to put up in this round.
var _kinds_left: Array[String] = []
## Balrogs that set out with the raid that is on.
var marching := 0


func setup(day_cycle: DayCycle) -> void:
	day_cycle.nightfall.connect(func() -> void:
		nights += 1
		start_raid())
	day_cycle.morning.connect(end_raid)
	for node in get_tree().get_nodes_in_group("caves"):
		_caves.append(node as Node3D)


## Goblins each starting cave spawns per minute before its buildings add
## more (there is no growth by the night: only the buildings add), with
## Balance "neutral_goblin_spawn" more for every neutral village there was
## at the start.
func spawn_rate() -> float:
	return maxf(0.0, Game.settings.goblin_rate + neutral_start * Balance.num("neutral_goblin_spawn"))


## How many times as fast the goblins build: the dev menu's goblin build
## speed, and Balance "neutral_goblin_build_speed" percent more for every
## neutral village there was at the start.
static func build_speed() -> float:
	return Game.settings.goblin_build_speed * (1.0 + neutral_start * Balance.num("neutral_goblin_build_speed"))


## The goblins' raids at work in this game (for hurt_cave()).
static var current: GoblinRaids


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## A cave's health: Balance "goblin_cave_health" to begin with.
static func cave_hp(cave: Node3D) -> float:
	return float(cave.get_meta("hp", Balance.num("goblin_cave_health")))


## True while `cave` stands.
static func cave_standing(cave: Variant) -> bool:
	return is_instance_valid(cave) and (cave as Node3D).is_in_group("caves") and cave_hp(cave) > 0.0


## The Flag Bearer's fighters hack at a cave: at no health it caves in
## (it spawns no more goblins) and is gone.
static func hurt_cave(cave: Node3D, amount: float) -> void:
	if not cave_standing(cave):
		return
	var left := cave_hp(cave) - amount
	cave.set_meta("hp", left)
	if left > 0.0:
		if randf() < 0.15:
			Game.effects.spawn_dust(cave.global_position + Vector3(randf_range(-5.0, 5.0), 3.0, randf_range(-3.0, 3.0)), 2.0)
		return
	cave.remove_from_group("caves")
	for k in 6:
		Game.effects.spawn_dust(cave.global_position + Vector3(randf_range(-7.0, 7.0), randf_range(0.0, 6.0), randf_range(-6.0, 4.0)), 6.0)
	Game.shake(1.2, cave.global_position)
	if current != null:
		current._caves.erase(cave)
		current.cave_fell.emit()
	cave.queue_free()


## A new cave (where a neutral village was wiped out): it spawns goblins
## like the caves that were there from the start.
func add_cave(cave: Node3D) -> void:
	if not _caves.has(cave):
		_caves.append(cave)


## Goblins `cave` spawns per minute: spawn_rate(), and more for each
## finished goblin building that belongs to it.
func cave_rate(cave: Node3D) -> float:
	var built := 0
	for node in get_tree().get_nodes_in_group("goblin_buildings"):
		if node.get_meta("cave", null) == cave:
			built += 1
	return spawn_rate() + built * Balance.num("goblin_rate_per_building")


func _process(delta: float) -> void:
	var village := Game.village
	if village == null or not village.founded:
		return
	for cave in _caves:
		if not is_instance_valid(cave):
			continue
		var due: float = _spawned.get(cave, 0.0) + cave_rate(cave) / 60.0 * delta
		while due >= 1.0:
			due -= 1.0
			spawn_at(cave)
		_spawned[cave] = due
	_bounce_back(delta)
	if get_tree().get_nodes_in_group("balrogs").size() < roundi(Balance.num("balrogs")):
		_balrog_timer -= delta
		if _balrog_timer <= 0.0:
			_balrog_timer = Balance.num("balrog_respawn_minutes") * 60.0
			hatch_balrog()
	_build_timer += delta
	var every := Balance.num("goblin_build_minutes") * 60.0 / maxf(build_speed(), 0.01)
	if _build_timer >= every:
		_build_timer = 0.0
		if start_building() == null and _wants_to_build():
			# Nowhere to put it: look again in a few seconds.
			_build_timer = maxf(0.0, every - RETRY_SECONDS)
	_site_timer -= delta
	if _site_timer <= 0.0:
		_site_timer = 1.0
		_manage_builders()


## The dev menu's Advance time: `seconds` go by at once for the caves (the
## goblins they would have spawned crawl out), the goblins' building and
## the next balrog.
func advance(seconds: float) -> void:
	for cave in _caves:
		if not is_instance_valid(cave):
			continue
		var due: float = _spawned.get(cave, 0.0) + cave_rate(cave) / 60.0 * seconds
		var made := 0
		while due >= 1.0 and made < 500:
			due -= 1.0
			made += 1
			spawn_at(cave)
		_spawned[cave] = minf(due, 1.0)
	_balrog_timer -= seconds
	_build_timer += seconds


## How many goblins there are (alive, not charmed; ogres not counted).
func goblin_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g != null and g.is_alive() and not g.ogre and not g.charmed():
			count += 1
	return count


## Goblin population bounce back: when fewer than "goblin_bounce_below"
## goblins are left, the caves spawn at least "goblin_bounce_rate" a
## minute in all until there are "goblin_bounce_until" again.
func _bounce_back(delta: float) -> void:
	var count := goblin_count()
	if count < roundi(Balance.num("goblin_bounce_below")):
		bouncing = true
	elif count >= roundi(Balance.num("goblin_bounce_until")):
		bouncing = false
	if not bouncing:
		_bounce_due = 0.0
		return
	var caves: Array[Node3D] = []
	var usual := 0.0
	for cave in _caves:
		if is_instance_valid(cave):
			caves.append(cave)
			usual += cave_rate(cave)
	if caves.is_empty():
		return
	# Only what the caves do not spawn already.
	_bounce_due += maxf(0.0, Balance.num("goblin_bounce_rate") - usual) / 60.0 * delta
	while _bounce_due >= 1.0:
		_bounce_due -= 1.0
		spawn_at(caves[randi() % caves.size()])


## A new balrog, as small as a newborn creature, at one of the caves.
## `quiet`: nothing is announced (a saved game's balrog coming back).
func hatch_balrog(quiet := false) -> Balrog:
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
	if not quiet:
		balrog_came.emit()
	return balrog


# --- Building ---------------------------------------------------------------------

## True while the goblins could start another building (none under way,
## fewer than they stop at, and a cave to build by).
func _wants_to_build() -> bool:
	var tree := get_tree()
	if not tree.get_nodes_in_group("goblin_sites").is_empty():
		return false
	if tree.get_nodes_in_group("goblin_buildings").size() >= roundi(Balance.num("goblin_buildings_max")):
		return false
	for cave in _caves:
		if is_instance_valid(cave):
			return true
	return false


## Marks out a new goblin building near a cave (`kind`, or one picked at
## random). Returns its site, or null if the goblins have enough, are
## still busy on the last one, or there is no room. It tries spots further
## and further from the caves until one fits.
func start_building(kind := "") -> ConstructionSite:
	var tree := get_tree()
	if not tree.get_nodes_in_group("goblin_sites").is_empty():
		return null
	var have := tree.get_nodes_in_group("goblin_buildings").size()
	var caves: Array[Node3D] = []
	for cave in _caves:
		if is_instance_valid(cave):
			caves.append(cave)
	if caves.is_empty() or have >= roundi(Balance.num("goblin_buildings_max")):
		return null
	if kind == "":
		# Each kind once, in a random order, before any comes round again.
		if _kinds_left.is_empty():
			_kinds_left.assign(BuildingFactory.GOBLIN_KINDS)
			_kinds_left.shuffle()
		kind = _kinds_left.back()
	var footprint := 3.4
	var terrain := Game.terrain
	for attempt in 160:
		var cave := caves[randi() % caves.size()]
		# (Before the cave at first, then all round it, further and further out.)
		var a: float = cave.get_meta("facing", 0.0) + randf_range(-2.0, 2.0) * minf(1.0 + attempt / 40.0, PI / 2.0)
		var out := 17.0 + attempt * 0.6
		var p := cave.global_position + Vector3(sin(a), 0.0, cos(a)) * randf_range(out, out + 9.0)
		if not _site_ok(p, footprint):
			continue
		# The goblins must be able to walk to it from their cave (round the
		# grey rock slopes).
		var way := Game.path_grid().find(cave.global_position, p, true)
		if way.is_empty() or Vector2(way[way.size() - 1].x - p.x, way[way.size() - 1].z - p.z).length() > 4.0:
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
		# The finished building belongs to the cave, and makes it spawn more.
		site.completed.connect(func(b: Destructible) -> void:
			b.set_meta("cave", cave)
			_on_built(b))
		Game.world_root.add_child(site)
		site.global_position = Vector3(p.x, h, p.z)
		# The door looks back towards the cave, more or less.
		site.rotation.y = a + PI + randf_range(-0.6, 0.6)
		_kinds_left.erase(kind)
		return site
	return null


## A goblin building is finished. A war hut's ogres move in at once.
func _on_built(building: Node3D) -> void:
	if building.get_meta("kind", "") == OGRE_HOME:
		_fill_hut(building)


## The goblins' finished buildings of one kind that still stand.
func standing(kind: String) -> Array[Destructible]:
	var out: Array[Destructible] = []
	for node in get_tree().get_nodes_in_group("goblin_buildings"):
		var b := node as Destructible
		if b != null and not b.destroyed and b.get_meta("kind", "") == kind:
			out.append(b)
	return out


## Brings a war hut's ogres up to strength.
func _fill_hut(hut: Node3D) -> void:
	var living: Array = []
	for node: Variant in hut.get_meta("ogres", []):
		if is_instance_valid(node) and (node as Villager).is_alive():
			living.append(node)
	while living.size() < roundi(Balance.num("ogres_per_war_hut")):
		var a := hut.rotation.y + PI * 0.5 + randf_range(-0.6, 0.6)
		var front := Vector3(sin(a), 0.0, cos(a))
		var ogre := Villager.new()
		ogre.goblin = true
		ogre.ogre = true
		ogre.home = hut.global_position + front * 8.0
		ogre.home_radius = 6.0
		Game.world_root.add_child(ogre)
		var door := hut.global_position + front * 5.0
		ogre.global_position = Vector3(door.x, Game.terrain.get_height(door.x, door.z), door.z)
		ogre.rotation.y = a
		living.append(ogre)
	hut.set_meta("ogres", living)


func _site_ok(p: Vector3, footprint: float) -> bool:
	var terrain := Game.terrain
	if not terrain.is_inside(p.x, p.z) or not terrain.is_dry(p.x, p.z) or terrain.get_normal(p.x, p.z).y < 0.9:
		return false
	# Well clear of the player's village (and of the creature that guards it),
	# and of the neutral villages.
	var village := Game.village
	if is_instance_valid(village) and village.founded and (village.in_territory(p) or village.center.distance_to(p) < 62.0):
		return false
	for node in get_tree().get_nodes_in_group("neutral_villages"):
		if (node as NeutralVillage).in_territory(p):
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
			best.set_meta("fetch_at", Game.now + randf_range(30.0, 50.0))
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
				g.set_meta("fetch_at", Game.now + randf_range(40.0, 60.0))
			else:
				g.carry_pack("")
				if Game.now > g.get_meta("fetch_at", 0.0):
					var a := facing + randf_range(-0.5, 0.5)
					g.assign_job("build", cave.global_position + Vector3(sin(a), 0.0, cos(a)) * randf_range(3.0, 5.0), site)
					g.set_meta("fetching", true)


## One new goblin crawls out of the cave and joins its camp: a Goblin
## Archer one time in four (Balance "goblin_archer_chance").
func spawn_at(cave: Node3D) -> Villager:
	var facing: float = cave.get_meta("facing", 0.0)
	var front := Vector3(sin(facing), 0.0, cos(facing))
	var g := WorldPopulator.spawn_villager(Game.world_root, Game.terrain, cave.global_position + front * 10.0, 9.0, true)
	var mouth := cave.global_position + front * randf_range(2.0, 4.0)
	g.global_position = Vector3(mouth.x, Game.terrain.get_height(mouth.x, mouth.z), mouth.z)
	if randf() < Balance.num("goblin_archer_chance"):
		g.become_goblin_archer()
	return g


# --- What the mouse shows ------------------------------------------------------

## What pointing at `cave` shows: how fast it spawns (with its buildings)
## and how many of each enemy there are.
func cave_tip(cave: Node3D) -> String:
	var built := 0
	for node in get_tree().get_nodes_in_group("goblin_buildings"):
		if node.get_meta("cave", null) == cave and not (node as Destructible).destroyed:
			built += 1
	var lines: PackedStringArray = ["Gooblin cave", "Spawns %s gooblins a minute" % _num(cave_rate(cave) if _caves.has(cave) else 0.0)]
	if built > 0:
		lines.append("(%s of them from its %d buildings)" % [_num(built * Balance.num("goblin_rate_per_building")), built])
	var goblins := 0
	var archers := 0
	var ogres := 0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g == null or not g.is_alive() or g.charmed():
			continue
		if g.ogre:
			ogres += 1
		elif g.archer:
			archers += 1
		else:
			goblins += 1
	var bats := 0
	for tower in standing(BAT_HOME):
		bats += roundi(Balance.num("bats_per_watchtower"))
	lines.append("Gooblins %d   Gooblin archers %d   Ogres %d" % [goblins, archers, ogres])
	lines.append("Giant bats %d a raid   Balrogs %d" % [bats, get_tree().get_nodes_in_group("balrogs").size()])
	return "\n".join(lines)


## What pointing at one of the goblins' buildings shows: what it does.
static func building_tip(kind: String) -> String:
	var more := "Makes %s more gooblins spawn a minute" % _num(Balance.num("goblin_rate_per_building"))
	match kind:
		OGRE_HOME:
			var n := roundi(Balance.num("ogres_per_war_hut"))
			return "Adds %d ogre%s\n%s" % [n, "" if n == 1 else "s", more]
		BAT_HOME:
			var n := roundi(Balance.num("bats_per_watchtower"))
			return "Sends %d giant bat%s each raid\n%s" % [n, "" if n == 1 else "s", more]
		"goblin_hut":
			return "Gooblins live here"
	return more


static func _num(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func start_raid() -> void:
	var village := Game.village
	if village == null or not village.founded:
		return
	for hut in standing(OGRE_HOME):
		_fill_hut(hut)
	var count := 0
	var ogres := 0
	var to_neutral := 0
	# Each goblin goes for the player's village or a neutral one, at random.
	var targets: Array[PlayerVillage] = [village]
	for node in get_tree().get_nodes_in_group("neutral_villages"):
		if (node as NeutralVillage).founded:
			targets.append(node as PlayerVillage)
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		# Builders stay behind to finish what they are building.
		if g.job == "build" and is_instance_valid(g.job_target):
			continue
		var a := randf() * TAU
		var goal := targets[randi() % targets.size()]
		var near := goal.center + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 10.0)
		g.start_raid(near, _route_for(g.home) if goal == village else PackedVector3Array())
		if not g.raiding:
			continue
		if goal != village:
			to_neutral += 1
		elif g.ogre:
			ogres += 1
		else:
			count += 1
	# A full-grown balrog comes too.
	marching = 0
	for node in get_tree().get_nodes_in_group("balrogs"):
		var balrog := node as Balrog
		if balrog.grown() >= 1.0:
			balrog.start_raid(village.center, _route_for(balrog.global_position))
			marching += 1
	raiding = count + ogres + marching + to_neutral > 0
	if raiding and count + ogres + marching == 0:
		neutral_raid_started.emit(to_neutral)
	elif raiding:
		raid_started.emit(count, ogres)
		if nights < roundi(Balance.num("bats_from_night")):
			return
		var k := 0
		for tower in standing(BAT_HOME):
			for n in roundi(Balance.num("bats_per_watchtower")):
				get_tree().create_timer(6.0 + 9.0 * k + randf() * 4.0, false).timeout.connect(launch_bat.bind(tower))
				k += 1


## A giant bat flies off `from` (a watchtower, or else one of the caves) to
## carry a villager off to a cave.
func launch_bat(from: Node3D = null) -> GiantBat:
	var caves: Array[Node3D] = []
	for cave in _caves:
		if is_instance_valid(cave):
			caves.append(cave)
	if caves.is_empty() or not raiding:
		return null
	var bat := GiantBat.new()
	bat.cave = caves[randi() % caves.size()]
	Game.world_root.add_child(bat)
	bat.global_position = (from.global_position + Vector3.UP * 12.0) if is_instance_valid(from) else (bat.cave.global_position + Vector3.UP * 7.0)
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
