class_name NeutralVillage
extends PlayerVillage
## A village of its own on one of the start locations the player did not
## pick (the player chooses how many before the game starts: at most one
## fewer than there are start locations). It begins as the player's does,
## with a free Storehouse and Balance "start_villagers" people, and then it
## lives just as the player's village does (PlayerVillage): its people
## gather, carry what they gather to its Storehouse, eat, have children,
## put up buildings and train warriors, all for their own village. They
## fight off goblins, and the goblins raid them too.
##
## What it builds comes from a build order: one of the files
## Neutral_Build_Order_1.txt, _2.txt and so on in the NeutralVillages
## folder, picked at random for each village (see BuildOrder). It builds
## the buildings there in order, one at a time, as it can afford them, and
## after the last one it builds at random, up to the most of each the file
## allows. Its people: Balance "neutral_keep_workers" workers always (they
## build, and gather what the village has least of), as many warriors,
## archers, wizards and necromancers as its buildings can train, and a
## third of everyone else on each of lumber, stone and food.
##
## Its people do not worship the creature to begin with. They are won over
## (become worshipers, who make the player magicko like the player's own
## people): one for every Balance "convert_minutes" the creature spends in
## their village, and "convert_on_help_min" to "convert_on_help_max" at
## once when it helps them (creature_helped(): it casts rain, or a spell at
## the goblins there, or gathers near them). No more than "worshipers_most"
## of them can be won over that way. Once "takeover_share" of them worship
## it, the village is the player's: its buildings, people, what it has
## stored and the ground round it (taken_over). The same happens at once
## when everyone left in it worships the creature, and when everyone in it
## is dead but its buildings still stand. If the goblins kill everyone and
## knock everything down, a goblin cave opens where it stood (wiped_out).

## The player has taken the village over: `peaceful` if its people were
## won over, false if they were all dead and only the buildings were left.
signal taken_over(village: NeutralVillage, peaceful: bool)
## The goblins have wiped the village out; `cave` has opened in its place.
signal wiped_out(village: NeutralVillage, cave: Node3D)
## `count` more of its people worship the creature.
signal converted(village: NeutralVillage, count: int)

## The most neutral villages a game can have.
const MOST := 7
## Seconds it waits for the next building in its order before it gives up
## on it and goes on to the one after (it may never afford some).
const PATIENCE := 300.0

static var _made := 0

## Shown to the player ("Neutral village 1").
var title := ""
var order: BuildOrder
## How far through the build order it is.
var _next := 0
var _build_timer := 0.0
## Seconds it has waited for the step it is on.
var _waited := 0.0
var _staff_timer := 0.0
var _fate_timer := 0.0
## Seconds the creature has spent in the village towards the next convert.
var _seen := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	neutral = true
	_made += 1
	people_group = "neutral_people_%d" % _made
	buildings_group = "neutral_buildings_%d" % _made
	_rng.randomize()


func _ready() -> void:
	super._ready()
	add_to_group("neutral_villages")
	# (Archers need bows; a neutral village has them from the start.)
	researched["bows"] = true
	if order == null:
		order = BuildOrder.pick(_rng)


## Everyone born there does not worship the creature.
func spawn_person(at: Vector3, radius: float, child := false, fey := false) -> Villager:
	return WorldPopulator.spawn_villager(Game.world_root, Game.terrain, at, radius, false, false, child, fey, self)


func join(v: Villager) -> void:
	v.owned = false
	v.village = self
	v.worshiper = false
	v.add_to_group(people_group)


func _process(delta: float) -> void:
	super._process(delta)
	if not founded or is_queued_for_deletion():
		return
	_watch_creature(delta)
	if is_queued_for_deletion():
		return
	_staff_timer -= delta
	if _staff_timer <= 0.0:
		_staff_timer = 2.0
		_staff()
	_build_timer -= delta
	if _build_timer <= 0.0:
		_build_timer = maxf(Balance.num("neutral_build_seconds"), 0.5)
		_waited += _build_timer
		_build_next()
	_fate_timer -= delta
	if _fate_timer <= 0.0:
		_fate_timer = 1.0
		_check_fate()


# --- Its people -------------------------------------------------------------------

## Keeps "neutral_keep_workers" workers, trains as big an army as its
## buildings allow from the rest, and splits everyone left over between
## lumber, stone and food.
func _staff() -> void:
	var keep := maxi(0, roundi(Balance.num("neutral_keep_workers")))
	var grown := 0
	for v in people():
		if v.is_adult() and v.is_alive():
			grown += 1
	# The necromancers were wizards: they are part of the army already.
	var spare := maxi(0, grown - keep - count("necromancer"))
	for role: String in ["warrior", "archer", "wizard"]:
		wanted[role] = mini(max_count(role), spare)
		spare -= wanted[role]
	wanted.necromancer = mini(max_count("necromancer"), count("wizard") + count("necromancer"))
	wanted.fey_archer = 0
	var workers: Array[Villager] = []
	for v in people():
		if v.can_work() and v.job != "train":
			workers.append(v)
	var promised := 0
	for role: String in ["warrior", "archer", "wizard"]:
		promised += maxi(0, wanted[role] - count(role) - training_progress(role).size())
	var share := maxi(0, workers.size() - keep - promised)
	var want := {"food": share / 3, "lumber": share / 3, "stone": share / 3}
	if share % 3 >= 1:
		want.food += 1
	if share % 3 >= 2:
		want.lumber += 1
	var have := {"food": 0, "lumber": 0, "stone": 0}
	for v in workers:
		if have.has(v.pin):
			have[v.pin] += 1
	# Too many on a job: back to the unassigned workers.
	for kind: String in have:
		for v in workers:
			if have[kind] <= want[kind]:
				break
			if v.pin == kind:
				v.pin = ""
				have[kind] -= 1
	# Too few: from the unassigned (not the ones building, if it can help it).
	for kind: String in want:
		for pass_k in 2:
			for v in workers:
				if have[kind] >= want[kind]:
					break
				if v.pin != "" or (pass_k == 0 and v.job == "build"):
					continue
				v.pin = kind
				if v.job != kind and not (kind == "food" and v.job == "farm"):
					v.clear_job()
				have[kind] += 1


# --- Building -----------------------------------------------------------------------

## One thing at a time: the next in its build order (or, after the last, one
## at random that it has fewer of than the most), once it can afford it.
func _build_next() -> void:
	if not construction_sites().is_empty():
		return
	var kind := ""
	while _next < order.steps.size():
		var step: String = order.steps[_next]
		if built(step) < order.most(step):
			kind = step
			break
		_next += 1
	if kind != "" and _waited > PATIENCE:
		# (Waited too long for it: on to the next.)
		_next += 1
		_waited = 0.0
		return
	if kind == "":
		var open: Array[String] = []
		for k: String in order.limits:
			if built(k) < order.most(k) and can_afford(_cost_of(k)):
				open.append(k)
		if open.is_empty():
			return
		kind = open[_rng.randi() % open.size()]
	var ok := _lay_out_field() if kind == "field" else _put_up(kind)
	if ok and _next < order.steps.size() and order.steps[_next] == kind:
		_next += 1
		_waited = 0.0


func _cost_of(kind: String) -> Dictionary:
	if kind == "field":
		var side := maxf(Balance.num("neutral_field_size"), CropField.MIN_SIDE)
		return CropField.cost_for(Vector2(side, side))
	return BuildingCatalog.find(kind).get("cost", {})


## How many of `kind` the village has, standing or going up ("field": its
## wheat fields).
func built(kind: String) -> int:
	if kind == "field":
		return fields().size()
	var n := 0
	for node in get_tree().get_nodes_in_group(buildings_group):
		if node.get_meta("kind", "") == kind and not (node as Destructible).destroyed:
			n += 1
	for site in construction_sites():
		if (site as ConstructionSite).kind == kind:
			n += 1
	return n


## Marks out a building site for `kind` (paid for at once), somewhere free
## in the village. False if it cannot afford it or finds no room.
func _put_up(kind: String) -> bool:
	var info := BuildingCatalog.find(kind)
	if info.is_empty() or not can_afford(info.cost):
		return false
	var look := _rng.randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = look
	var sample := BuildingFactory.create(kind, rng)
	var footprint := sample.footprint
	sample.free()
	var spot: Variant = _free_spot(footprint)
	if spot == null:
		return false
	var p: Vector3 = spot
	spend(info.cost)
	var terrain := Game.terrain
	var h := maxf(terrain.average_height(p, footprint), Terrain.WATER_LEVEL + 0.5)
	terrain.apply_brush(Vector3(p.x, h, p.z), footprint + 3.0, Terrain.Brush.FLATTEN, 1.0, h, footprint / (footprint + 3.0))
	_clear_trees(p, footprint + 1.5)
	var site := ConstructionSite.new()
	site.setup(kind, look, info.cost)
	site.set_meta("village", self)
	Game.world_root.add_child(site)
	site.global_position = Vector3(p.x, h, p.z)
	# Doors face the middle of the village.
	site.rotation.y = atan2(center.x - p.x, center.z - p.z)
	return true


## Lays out a square wheat field (Balance "neutral_field_size" a side).
func _lay_out_field() -> bool:
	var side := maxf(Balance.num("neutral_field_size"), CropField.MIN_SIDE)
	var field_size := Vector2(side, side)
	var cost := CropField.cost_for(field_size)
	if not can_afford(cost):
		return false
	var reach := influence() * 0.85
	for attempt in 60:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(side * 0.8 + 6.0, maxf(reach, side + 8.0))
		var c := center + Vector3(cos(a), 0.0, sin(a)) * r
		var yaw := atan2(center.x - c.x, center.z - c.z)
		if not _field_fits(c, field_size, yaw):
			continue
		spend(cost)
		for node in get_tree().get_nodes_in_group("trees") + get_tree().get_nodes_in_group("saplings"):
			var t := node as Destructible
			if CropField.in_rect(t.global_position, c, field_size, yaw, 1.0):
				t.fell()
		var field := CropField.new()
		field.setup(field_size)
		field.set_meta("village", self)
		field.position = Vector3(c.x, Game.terrain.get_height(c.x, c.z), c.z)
		field.rotation.y = yaw
		Game.world_root.add_child(field)
		return true
	return false


func _field_fits(c: Vector3, field_size: Vector2, yaw: float) -> bool:
	var terrain := Game.terrain
	var points := CropField.rect_corners(c, field_size, yaw)
	points.append(c)
	for k in 4:
		points.append(points[k].lerp(points[(k + 1) % 4], 0.5))
	for p in points:
		if not terrain.is_dry(p.x, p.z) or not _mine_to_use(p):
			return false
	for group in ["buildings", "construction_sites", "goblin_sites", "caves"]:
		for node in get_tree().get_nodes_in_group(group):
			var b := node as Node3D
			var reach: float = 12.0 if group == "caves" else float(b.get("footprint"))
			if CropField.in_rect(b.global_position, c, field_size, yaw, reach + 1.0):
				return false
	for node in get_tree().get_nodes_in_group("fields"):
		var other := node as CropField
		for p in points:
			if other.contains(p, 1.0):
				return false
		if CropField.in_rect(other.global_position, c, field_size, yaw, 1.0):
			return false
	return true


## Somewhere free in the village for a building `footprint` metres across,
## or null.
func _free_spot(footprint: float) -> Variant:
	var terrain := Game.terrain
	var reach := influence() * 0.8
	for attempt in 80:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(6.0 + footprint, maxf(reach, footprint + 10.0))
		var p := center + Vector3(cos(a), 0.0, sin(a)) * r
		if not terrain.is_dry(p.x, p.z) or terrain.get_normal(p.x, p.z).y < 0.85 or not _mine_to_use(p):
			continue
		var clear := true
		for group in ["buildings", "construction_sites", "goblin_sites"]:
			for node in get_tree().get_nodes_in_group(group):
				var b := node as Node3D
				if b.get("kind") == "bridge":
					continue
				var other: float = b.get("footprint")
				if Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < other + footprint + 1.5:
					clear = false
					break
			if not clear:
				break
		if not clear:
			continue
		for node in get_tree().get_nodes_in_group("caves"):
			var cave := node as Node3D
			if Vector2(cave.global_position.x - p.x, cave.global_position.z - p.z).length() < 14.0 + footprint:
				clear = false
		for node in get_tree().get_nodes_in_group("fields"):
			if (node as CropField).contains(p, footprint + 1.0):
				clear = false
		if clear:
			return p
	return null


## True where the village may build: inside its own influence, and not on
## the player's ground or another neutral village's.
func _mine_to_use(p: Vector3) -> bool:
	if Vector2(p.x - center.x, p.z - center.z).length() > influence():
		return false
	var player := Game.village
	if is_instance_valid(player) and player.founded and player.in_territory(p):
		return false
	for node in get_tree().get_nodes_in_group("neutral_villages"):
		var other := node as NeutralVillage
		if other != self and other.founded and other.in_territory(p):
			return false
	return true


func _clear_trees(p: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group("trees") + get_tree().get_nodes_in_group("saplings"):
		var t := node as Destructible
		if Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length() < radius:
			t.fell()


# --- Worshipers --------------------------------------------------------------------

## How many of its people worship the creature.
func worshipers() -> int:
	var n := 0
	for v in people():
		if v.worshiper:
			n += 1
	return n


## The grown-up worshipers that make the player magicko (wizards make
## theirs for their own village).
func grown_worshipers() -> int:
	var n := 0
	for v in people():
		if v.worshiper and v.is_adult() and not v.wizard:
			n += 1
	return n


## 0..1: the share of its people who worship the creature.
func worship_share() -> float:
	var pop := population()
	return float(worshipers()) / pop if pop > 0 else 0.0


## The creature in the village: one more worshiper every "convert_minutes".
func _watch_creature(delta: float) -> void:
	var c := Game.creature
	if not is_instance_valid(c) or c.knocked_out or not in_territory(c.global_position):
		return
	_seen += delta
	var every := maxf(Balance.num("convert_minutes"), 0.01) * 60.0
	if _seen >= every:
		_seen -= every
		convert_people(1)


## The creature helped, at `at`: every neutral village that saw it (within
## Balance "neutral_help_reach" of its influence; with `inside`, only the
## village it was in) wins over "convert_on_help_min" to "convert_on_help_max"
## more worshipers at once.
static func creature_helped(at: Vector3, inside := false) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group("neutral_villages"):
		var v := node as NeutralVillage
		if not v.founded or v.is_queued_for_deletion():
			continue
		var d := Vector2(at.x - v.center.x, at.z - v.center.z).length()
		if d < v.influence() + (0.0 if inside else Balance.num("neutral_help_reach")):
			var lo := roundi(Balance.num("convert_on_help_min"))
			v.convert_people(v._rng.randi_range(mini(lo, roundi(Balance.num("convert_on_help_max"))), maxi(lo, roundi(Balance.num("convert_on_help_max")))))


## Up to `n` more of its people worship the creature (no more than
## "worshipers_most" of them in all). Returns how many did.
func convert_people(n: int) -> int:
	var most := floori(Balance.num("worshipers_most") * population() + 0.0001)
	var left: Array[Villager] = []
	for v in people():
		if not v.worshiper:
			left.append(v)
	var done := 0
	var now := worshipers()
	while done < n and now < most and not left.is_empty():
		var v: Villager = left.pop_at(_rng.randi() % left.size())
		v.worshiper = true
		Game.effects.spawn_dust(v.global_position, 0.5)
		done += 1
		now += 1
	if done > 0:
		var creature_name := Game.creature.species_name().to_lower() if is_instance_valid(Game.creature) else "creature"
		_float_over_storehouse(Texts.line("villagers_converted" if done > 1 else "villager_converted",
			{"count": done, "creature": creature_name, "village": title}), Color(1.0, 0.88, 0.45))
		converted.emit(self, done)
		_check_fate()
	return done


## What the box by the pointer says over its Storehouse.
func worship_tip() -> String:
	return "%s\nWorshipers: %d of %d (%d%%)\nIt becomes yours at %d%%" % [title, worshipers(), population(),
		roundi(worship_share() * 100.0), roundi(Balance.num("takeover_share") * 100.0)]


# --- Its fate ----------------------------------------------------------------------

func _check_fate() -> void:
	if not founded or is_queued_for_deletion():
		return
	var pop := population()
	if pop == 0:
		var standing := false
		for node in get_tree().get_nodes_in_group(buildings_group):
			if not (node as Destructible).destroyed:
				standing = true
				break
		if standing:
			take_over(false)
		else:
			_fall_to_goblins()
	elif worshipers() >= pop or worship_share() >= Balance.num("takeover_share") - 0.0001:
		take_over(true)


## Everything the village has becomes the player's.
func take_over(peaceful: bool) -> void:
	var player := Game.village
	if not is_instance_valid(player) or is_queued_for_deletion():
		return
	founded = false
	for node in get_tree().get_nodes_in_group(buildings_group):
		node.remove_from_group(buildings_group)
		node.remove_from_group("neutral_buildings")
		node.remove_meta("village")
		node.add_to_group("player_buildings")
	for node in construction_sites() + fields():
		(node as Node).remove_meta("village")
	# Its army stays an army (the player's asks for that many more).
	for role: String in ARMY:
		player.wanted[role] += count(role)
	for b in _training.keys():
		var entry: Dictionary = _training[b]
		if is_instance_valid(entry.v):
			(entry.v as Villager).clear_job()
	_training.clear()
	for v in people():
		v.remove_from_group(people_group)
		v.village = null
		v.owned = true
		v.worshiper = true
		v.add_to_group("people")
	for node in get_tree().get_nodes_in_group("skeletons"):
		var s := node as Villager
		if s.village == self:
			s.village = null
			s.owned = true
	for res: String in STORED:
		if resources.get(res, 0.0) > 0.0:
			player.give(res, resources[res], false)
	player.taken_centres.append(center)
	taken_over.emit(self, peaceful)
	queue_free()


## Nobody left and nothing standing: a goblin cave opens where it was.
func _fall_to_goblins() -> void:
	founded = false
	for node in construction_sites() + fields():
		(node as Node).queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.randi()
	var cave := WorldPopulator.place_cave(Game.world_root, Game.terrain, Vector2(center.x, center.z), rng.randf() * TAU, rng, false, false)
	wiped_out.emit(self, cave)
	queue_free()
