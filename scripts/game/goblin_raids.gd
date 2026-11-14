class_name GoblinRaids
extends Node
## Sends the goblins against the player's village.
##
## Halfway through each night every goblin leaves its cave and marches on
## the village; in the morning the survivors go home. At nightfall each
## cave is topped back up, and the camps grow by CAMP_GROWTH goblins a
## night (from CAMP_SIZE up to CAMP_MAX). Once a raid has GOBLINS_PER_OGRE
## goblins an ogre joins it, and another for every GOBLINS_PER_OGRE more.
## Call setup() with the DayCycle.

signal raid_started(goblins: int, ogres: int)
signal raid_ended

## Goblins living at each cave on the first night.
const CAMP_SIZE := 11
const CAMP_GROWTH := 2
const CAMP_MAX := 21
const GOBLINS_PER_OGRE := 15

var raiding := false
## Nights so far (counted at nightfall).
var night := 0


func setup(day_cycle: DayCycle) -> void:
	day_cycle.nightfall.connect(refill_caves)
	day_cycle.midnight.connect(start_raid)
	day_cycle.morning.connect(end_raid)


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


## How many goblins each cave holds tonight.
func camp_size() -> int:
	return mini(CAMP_SIZE + CAMP_GROWTH * maxi(night - 1, 0), CAMP_MAX)


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


## New goblins crawl out of each cave to replace the ones that died.
func refill_caves() -> void:
	night += 1
	var goblins := get_tree().get_nodes_in_group("goblins")
	for node in get_tree().get_nodes_in_group("caves"):
		var cave := node as Node3D
		var facing: float = cave.get_meta("facing", 0.0)
		var front := Vector3(sin(facing), 0.0, cos(facing))
		var camp := cave.global_position + front * 10.0
		var living := 0
		for g in goblins:
			var home: Vector3 = (g as Villager).home
			if not (g as Villager).ogre and Vector2(home.x - camp.x, home.z - camp.z).length() < 8.0:
				living += 1
		for k in camp_size() - living:
			var g := WorldPopulator.spawn_villager(Game.world_root, Game.terrain, camp, 9.0, true)
			var mouth := cave.global_position + front * randf_range(2.0, 4.0)
			g.global_position = Vector3(mouth.x, Game.terrain.get_height(mouth.x, mouth.z), mouth.z)
