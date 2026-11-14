class_name GoblinRaids
extends Node
## Sends the goblins against the player's village.
##
## Halfway through each night every goblin leaves its cave and marches on
## the village; in the morning the survivors go home. At nightfall each
## cave is topped back up to CAMP_SIZE goblins, so there is a raid every
## night. Call setup() with the DayCycle.

signal raid_started(count: int)
signal raid_ended

## Goblins living at each cave.
const CAMP_SIZE := 11

var raiding := false


func setup(day_cycle: DayCycle) -> void:
	day_cycle.nightfall.connect(refill_caves)
	day_cycle.midnight.connect(start_raid)
	day_cycle.morning.connect(end_raid)


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


## New goblins crawl out of each cave to replace the ones that died.
func refill_caves() -> void:
	var goblins := get_tree().get_nodes_in_group("goblins")
	for node in get_tree().get_nodes_in_group("caves"):
		var cave := node as Node3D
		var facing: float = cave.get_meta("facing", 0.0)
		var front := Vector3(sin(facing), 0.0, cos(facing))
		var camp := cave.global_position + front * 10.0
		var living := 0
		for g in goblins:
			var home: Vector3 = (g as Villager).home
			if Vector2(home.x - camp.x, home.z - camp.z).length() < 8.0:
				living += 1
		for k in CAMP_SIZE - living:
			var g := WorldPopulator.spawn_villager(Game.world_root, Game.terrain, camp, 9.0, true)
			var mouth := cave.global_position + front * randf_range(2.0, 4.0)
			g.global_position = Vector3(mouth.x, Game.terrain.get_height(mouth.x, mouth.z), mouth.z)
