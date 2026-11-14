class_name GoblinRaids
extends Node
## Grows the goblin camps and sends the goblins against the player's village.
##
## Every cave that was there when the game began spawns goblins all the
## time, at Game.settings.goblin_rate per minute, and the rate goes up by
## goblin_rate_growth every night. Halfway through each night every goblin
## leaves its cave and marches on the village; in the morning the survivors
## go home. Once a raid has GOBLINS_PER_OGRE goblins an ogre joins it, and
## another for every GOBLINS_PER_OGRE more. Call setup() with the DayCycle.

signal raid_started(goblins: int, ogres: int)
signal raid_ended

const GOBLINS_PER_OGRE := 15

var raiding := false
## Nights since the game began (counted at nightfall).
var nights := 0

var _caves: Array[Node3D] = []
var _spawned := {}


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
		g.start_raid(village.center + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 10.0))
		if g.raiding and g.ogre:
			ogres += 1
		elif g.raiding:
			count += 1
	raiding = count + ogres > 0
	if raiding:
		raid_started.emit(count, ogres)


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
	if raiding:
		raiding = false
		raid_ended.emit()
