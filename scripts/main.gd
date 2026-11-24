extends Node3D
## Entry point. Builds the world for the current session (see Game.session)
## and hands it to the matching controller:
##   "menu"    MainMenu: a random island behind the title menu
##   "play"    PlayMode: the game, on a random island or a saved map
##   "editor"  EditorMode: the map editor
##
## A world comes from a saved map file when session.map_path is set, and
## otherwise from Game.world_seed at the size in session.size.

var terrain: Terrain
var atmosphere: Atmosphere
var camera_rig: RtsCamera


func _ready() -> void:
	var mode: String = Game.session.mode
	var map := {}
	if not Game.session.get("map_data", {}).is_empty():
		map = Game.session.map_data
	elif Game.session.map_path != "":
		map = MapData.load_map(Game.session.map_path)
		if map.is_empty():
			push_warning("Falling back to a random island")
	Terrain.configure(int(map.size) if not map.is_empty() else int(Game.session.size))
	# A map from the editor brings its own nature palette.
	Art.set_palette(int(map.get("palette", Game.palette_index)) if not map.is_empty() else Game.palette_index)
	Grass.density = Grass.DENSITY_LEVELS[Game.grass_level]
	Game.world_root = self

	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	# The map editor is always at noon (the first mood, "Meadow day").
	atmosphere.set_mood(0 if Game.session.get("mode", "") == "editor" else Game.mood_index, 0.0)

	var effects := Effects.new()
	effects.name = "Effects"
	add_child(effects)
	Game.effects = effects

	var fire := FireSystem.new()
	fire.name = "Fires"
	add_child(fire)
	Game.fire = fire

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	Game.terrain = terrain

	# What the controller needs to know about the world it was given.
	var info := {"name": "Random island", "starts": PackedVector2Array(), "caves": [], "from_map": false}
	if not map.is_empty():
		terrain.load_map(map)
		WorldPopulator.populate_from_map(self, terrain, map, mode == "play")
		info = {"name": map.name, "starts": map.starts, "caves": map.caves, "paths": map.get("paths", []), "from_map": true, "path": Game.session.map_path,
			"unsaved": not Game.session.get("map_data", {}).is_empty()}
	elif mode == "editor":
		terrain.generate(Game.world_seed, false)
		WorldPopulator.populate_nature(self, terrain, Game.world_seed)
		info.name = ""
	else:
		terrain.generate(Game.world_seed, true)
		info.merge(WorldPopulator.populate(self, terrain, Game.world_seed), true)

	camera_rig = RtsCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.bounds = Terrain.HALF
	camera_rig.zoom_max = 230.0 * maxf(Terrain.SCALE, 1.0)
	add_child(camera_rig)
	Game.camera_rig = camera_rig
	camera_rig.focus_on(Vector3.ZERO, true)
	terrain.changed.connect(_on_terrain_changed)

	var controller: Node
	match mode:
		"play":
			var play := PlayMode.new()
			play.setup(info, atmosphere)
			controller = play
		"editor":
			var editor := EditorMode.new()
			editor.setup(info)
			controller = editor
		_:
			controller = MainMenu.new()
			camera_rig.auto_orbit = 0.04
			camera_rig.set_zoom(150.0 * Terrain.SCALE, true)
	controller.name = "Controller"
	add_child(controller)


func _on_terrain_changed(center: Vector3, radius: float) -> void:
	# Keep buildings, trees and rocks sitting on the ground after it is reshaped.
	for node in get_tree().get_nodes_in_group("grounded"):
		var d := node as Node3D
		var flat := Vector2(d.global_position.x - center.x, d.global_position.z - center.z).length()
		if flat < radius + 6.0:
			d.global_position.y = terrain.get_height(d.global_position.x, d.global_position.z)
