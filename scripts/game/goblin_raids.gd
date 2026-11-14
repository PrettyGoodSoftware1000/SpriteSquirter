class_name GoblinRaids
extends Node
## Grows the goblin camps and sends the goblins against the player's village.
##
## Every cave that was there when the game began spawns goblins all the
## time, at Game.settings.goblin_rate per minute, and the rate goes up by
## goblin_rate_growth every night. Halfway through each night every goblin
## leaves its cave and marches on the village; in the morning the survivors
## go home. Call setup() with the DayCycle.

signal raid_started(count: int)
signal raid_ended

var raiding := false
## Nights since the game began.
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
	var count := 0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		var a := randf() * TAU
		g.start_raid(village.center + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 10.0))
		if g.raiding:
			count += 1
	raiding = count > 0
	if raiding:
		raid_started.emit(count)


func end_raid() -> void:
	for node in get_tree().get_nodes_in_group("raiders"):
		(node as Villager).end_raid()
	if raiding:
		raiding = false
		raid_ended.emit()
