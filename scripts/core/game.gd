extends Node
## Global access point (autoload "Game") for the shared world systems.
##
## Main fills these references in when it builds the world, so any script can
## reach the terrain, effects, fire system or camera without node paths.
## The session (menu, play or map editor) and the gameplay settings live
## here too, so they survive the scene reload that starts a new world.

## Gameplay numbers the dev menu (~) can change while playing.
const DEFAULT_SETTINGS := {
	"day_minutes": 8.0, # length of a full day-night cycle
	"lumber_rate": 6.0, # per worker per minute
	"stone_rate": 4.0, # per worker per minute
	"food_rate": 6.0, # per worker per minute
	"birth_seconds": 30.0, # time between new villagers
	"magicko_rate": 1.0, # per grown-up villager per minute
	"goblin_rate": 1.0, # goblins per starting cave per minute, on day 1
	"goblin_rate_growth": 0.5, # added to goblin_rate every night
	"creature_food": 20.0, # food a full-grown creature eats per minute
	"creature_grow_minutes": 30.0, # time for the creature to reach full size
	"goblin_build_speed": 2.0, # how many times as fast the goblins start and finish buildings
	"sapling_rate": 2.0, # saplings the village plants a minute (balancing.txt saplings_per_minute)
	"villager_detail": 300.0, # metres from the camera within which villagers are drawn in full detail (300: always)
	"construction_rate": 1.0, # how many times as fast the village's buildings go up
	"training_time": 1.0, # training times are multiplied by this
	"influence_start": 45.0, # radius in metres of a new village's influence
	"influence_per_person": 1.0, # metres the influence grows for every villager
}

## The creature the player chose in the main menu: a key of Creature.SPECIES.
var creature_kind := "tortoise"
## Seed for the current world. Kept here so it survives a scene reload.
var world_seed: int = 0
## Lighting mood, kept here so it survives generating a new world.
var mood_index: int = 0
## The nature palette the player picked in the dev menu (see Art.PALETTES).
## A map from the editor can choose its own, which is used while it is played.
var palette_index: int = 0
## Index into Grass.DENSITY_LEVELS (0 = full detail).
var grass_level: int = 0
## Whether the dev menu (~) is open.
var dev_menu := false
## mode: "menu", "play" or "editor". map_path: a saved map, or "" for a
## world made from world_seed. size: map size for a world made from a seed.
## map_data: a map held in memory instead of a file (the editor uses it to
## grow the map square without saving first).
var session := {"mode": "menu", "map_path": "", "size": 384, "map_data": {}}
var settings := DEFAULT_SETTINGS.duplicate()

var world_root: Node3D
var terrain: Terrain
var effects: Effects
var fire: FireSystem
var camera_rig: RtsCamera
var creature: Creature
## The player's village while playing; null in the menu and the editor.
var village: PlayerVillage
## Day and night while playing; null in the menu and the editor.
var day_cycle: DayCycle
## Seconds of game time since the program started. Timed effects (such as
## the roots spell) compare against this.
var now := 0.0


var _paths: PathGrid


func _ready() -> void:
	Balance.load_file()
	settings.sapling_rate = Balance.num("saplings_per_minute")
	Texts.load_file()
	ActionTable.load_file()
	Villager.apply_balance()
	BuildingCatalog.apply_balance()
	world_seed = randi()


func _process(delta: float) -> void:
	now += delta


## The route finder for the current world's terrain (made on first use).
func path_grid() -> PathGrid:
	if _paths == null or not is_instance_valid(_paths.terrain) or _paths.terrain != terrain:
		_paths = PathGrid.new()
		_paths.setup(terrain)
	return _paths


## Leaves the current world and builds a new one. With no map_path the
## world comes from a fresh random seed of the given size.
func start(mode: String, map_path := "", size := 384, new_seed := true, map_data := {}) -> void:
	session = {"mode": mode, "map_path": map_path, "size": size, "map_data": map_data}
	if new_seed:
		world_seed = randi()
	village = null
	day_cycle = null
	get_tree().reload_current_scene()


## The point on the ground under a screen position, or null.
func pick_ground(screen_pos: Vector2) -> Variant:
	if not is_instance_valid(camera_rig) or not is_instance_valid(terrain):
		return null
	var cam := camera_rig.camera
	var hit: Variant = terrain.raycast(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	# Ignore the floor of the void around the island.
	if hit != null and (hit as Vector3).y < -20.0:
		return null
	return hit


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
