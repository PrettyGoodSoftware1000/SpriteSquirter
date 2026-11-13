extends Node
## Global access point (autoload "Game") for the shared world systems.
##
## Main fills these references in when it builds the world, so any script can
## reach the terrain, effects, fire system or camera without node paths.

## Seed for the current world. Kept here so it survives a scene reload.
var world_seed: int = 0
## Lighting mood, kept here so it survives generating a new world.
var mood_index: int = 0
## Index into Grass.DENSITY_LEVELS (0 = full detail).
var grass_level: int = 0
## Whether the dev menu (~) is open.
var dev_menu := false

var world_root: Node3D
var terrain: Terrain
var effects: Effects
var fire: FireSystem
var camera_rig: RtsCamera
var creature: Creature


func _ready() -> void:
	world_seed = randi()


## Shakes the camera. The shake fades with distance from `at`.
func shake(amount: float, at: Vector3) -> void:
	if is_instance_valid(camera_rig):
		camera_rig.add_shake(amount, at)


## Tells every villager within `radius` of `pos` to run away from it.
func alarm(pos: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v and v.global_position.distance_to(pos) < radius:
			v.flee(pos)
