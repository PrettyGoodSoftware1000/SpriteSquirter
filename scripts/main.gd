extends Node3D
## Entry point. Builds the world, then turns mouse and keyboard input into
## actions: moving the creature, casting fireballs, sculpting terrain and
## placing buildings.

enum Mode { COMMAND, FIREBALL, RAISE, LOWER, FLATTEN, SMOOTH, BUILD }

const BRUSH_MIN := 3.0
const BRUSH_MAX := 30.0
const SCULPT_RATE := 8.0
const FIREBALL_COOLDOWN := 0.25

var mode: Mode = Mode.COMMAND
var brush_radius := 8.0

var terrain: Terrain
var atmosphere: Atmosphere
var creature: Creature
var camera_rig: RtsCamera
var hud: Hud

var _rng := RandomNumberGenerator.new()
var _cursor_hit: Variant = null
var _painting := false
var _flatten_height := 0.0
var _fireball_cooldown := 0.0
var _stats_timer := 0.0

var _brush_ring: MeshInstance3D
var _ring_mesh := ImmediateMesh.new()
var _ring_material := StandardMaterial3D.new()

var _ghost: Destructible
var _ghost_seed := 0
var _ghost_rotation := 0.0
var _ghost_valid := false
var _ghost_material := StandardMaterial3D.new()


func _ready() -> void:
	_rng.seed = Game.world_seed
	Grass.density = Grass.DENSITY_LEVELS[Game.grass_level]
	Game.world_root = self
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.set_mood(Game.mood_index, 0.0)

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(Game.world_seed)
	Game.terrain = terrain

	var effects := Effects.new()
	effects.name = "Effects"
	add_child(effects)
	Game.effects = effects

	var fire := FireSystem.new()
	fire.name = "Fires"
	add_child(fire)
	Game.fire = fire

	_add_water()
	WorldPopulator.populate(self, terrain, Game.world_seed)

	creature = Creature.new()
	creature.name = "Creature"
	add_child(creature)
	creature.place(_creature_start(), _rng.randf() * TAU)
	Game.creature = creature

	camera_rig = RtsCamera.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.focus_on(creature.global_position, true)
	Game.camera_rig = camera_rig

	hud = Hud.new()
	add_child(hud)
	hud.mode_selected.connect(func(m: int) -> void: _set_mode(m as Mode))
	hud.regenerate_requested.connect(_regenerate)
	hud.set_brush(brush_radius)
	hud.set_mood(atmosphere.mood_name())
	hud.set_grass(Grass.DENSITY_NAMES[Game.grass_level])

	_setup_brush_ring()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_seed = _rng.randi()
	terrain.changed.connect(_on_terrain_changed)
	_set_mode(Mode.COMMAND)


func _process(delta: float) -> void:
	_fireball_cooldown = maxf(0.0, _fireball_cooldown - delta)
	_cursor_hit = _pick_ground(get_viewport().get_mouse_position())
	_painting = _painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _painting and _cursor_hit != null:
		_sculpt(_cursor_hit, delta)
	_update_brush_ring()
	_update_ghost()
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		_update_stats()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var number: int = key.physical_keycode - KEY_1
		if number >= 0 and number < Mode.size():
			_set_mode(number as Mode)
			return
		match key.physical_keycode:
			KEY_ESCAPE:
				_set_mode(Mode.COMMAND)
			KEY_F:
				_cast_fireball()
			KEY_SPACE:
				camera_rig.focus_on(creature.global_position)
			KEY_R:
				_reroll_ghost()
			KEY_BRACKETLEFT:
				brush_radius = clampf(brush_radius - 1.5, BRUSH_MIN, BRUSH_MAX)
				hud.set_brush(brush_radius)
			KEY_BRACKETRIGHT:
				brush_radius = clampf(brush_radius + 1.5, BRUSH_MIN, BRUSH_MAX)
				hud.set_brush(brush_radius)
			KEY_G:
				_cycle_grass()
			KEY_L:
				atmosphere.next_mood()
				Game.mood_index = atmosphere.mood_index
				hud.set_mood(atmosphere.mood_name())
			KEY_N:
				_regenerate()
		return

	var button := event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif button.button_index == MOUSE_BUTTON_RIGHT and _cursor_hit != null:
			_command_move(_cursor_hit)


# --- Actions ------------------------------------------------------------------

func _set_mode(m: Mode) -> void:
	mode = m
	_painting = false
	hud.set_mode(m)
	if m == Mode.BUILD:
		if _ghost == null:
			_make_ghost()
	elif _ghost != null:
		_ghost.queue_free()
		_ghost = null


func _on_left_click() -> void:
	if _cursor_hit == null:
		return
	var hit: Vector3 = _cursor_hit
	match mode:
		Mode.COMMAND:
			_command_move(hit)
		Mode.FIREBALL:
			_cast_fireball()
		Mode.RAISE, Mode.LOWER, Mode.FLATTEN, Mode.SMOOTH:
			_painting = true
			_flatten_height = hit.y
		Mode.BUILD:
			_place_building()


func _command_move(pos: Vector3) -> void:
	creature.move_to(pos)
	Game.effects.spawn_marker(pos)


func _cast_fireball() -> void:
	if _cursor_hit == null or _fireball_cooldown > 0.0:
		return
	_fireball_cooldown = FIREBALL_COOLDOWN
	creature.cast_fireball(_cursor_hit)


func _sculpt(pos: Vector3, delta: float) -> void:
	match mode:
		Mode.RAISE:
			terrain.apply_brush(pos, brush_radius, Terrain.Brush.RAISE, SCULPT_RATE * delta)
		Mode.LOWER:
			terrain.apply_brush(pos, brush_radius, Terrain.Brush.LOWER, SCULPT_RATE * delta)
		Mode.FLATTEN:
			terrain.apply_brush(pos, brush_radius, Terrain.Brush.FLATTEN, 6.0 * delta, _flatten_height)
		Mode.SMOOTH:
			terrain.apply_brush(pos, brush_radius, Terrain.Brush.SMOOTH, 6.0 * delta)


func _cycle_grass() -> void:
	Game.grass_level = (Game.grass_level + 1) % Grass.DENSITY_LEVELS.size()
	Grass.density = Grass.DENSITY_LEVELS[Game.grass_level]
	terrain.grass.rebuild()
	hud.set_grass(Grass.DENSITY_NAMES[Game.grass_level])


func _regenerate() -> void:
	Game.world_seed = randi()
	get_tree().reload_current_scene()


# --- Building placement -------------------------------------------------------

func _make_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = _ghost_seed
	_ghost = BuildingFactory.create_building(rng)
	_ghost.is_ghost = true
	add_child(_ghost)
	BuildingFactory.make_ghost(_ghost, _ghost_material)
	_ghost.rotation.y = _ghost_rotation


func _reroll_ghost() -> void:
	_ghost_seed = _rng.randi()
	_ghost_rotation = _rng.randf() * TAU
	if mode == Mode.BUILD:
		_make_ghost()


func _update_ghost() -> void:
	if _ghost == null:
		return
	if _cursor_hit == null:
		_ghost.visible = false
		return
	var p: Vector3 = _cursor_hit
	_ghost.visible = true
	_ghost.global_position = p
	_ghost_valid = _can_place(p, _ghost.footprint)
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.5, 0.45) if _ghost_valid else Color(1.0, 0.3, 0.3, 0.45)


func _can_place(p: Vector3, footprint: float) -> bool:
	if absf(p.x) > 118.0 or absf(p.z) > 118.0:
		return false
	if terrain.get_height(p.x, p.z) < Terrain.WATER_LEVEL + 0.4:
		return false
	for node in get_tree().get_nodes_in_group("buildings"):
		var b := node as Destructible
		var gap := Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length()
		if gap < b.footprint + footprint + 1.0:
			return false
	return true


func _place_building() -> void:
	if _cursor_hit == null or not _ghost_valid:
		return
	var p: Vector3 = _cursor_hit
	var footprint := _ghost.footprint
	var h := maxf(terrain.average_height(p, footprint), Terrain.WATER_LEVEL + 0.5)
	# Level a pad for the building, blending out into the surrounding ground.
	terrain.apply_brush(Vector3(p.x, h, p.z), footprint + 3.0, Terrain.Brush.FLATTEN, 1.0, h, footprint / (footprint + 3.0))
	for node in get_tree().get_nodes_in_group("trees"):
		var t := node as Destructible
		if Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length() < footprint + 1.5:
			t.remove_from_group("destructibles")
			t.remove_from_group("grounded")
			t.remove_from_group("trees")
			t.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = _ghost_seed
	var b := BuildingFactory.create_building(rng)
	add_child(b)
	b.global_position = Vector3(p.x, h, p.z)
	b.rotation.y = _ghost_rotation
	terrain.add_bare(b.global_position, footprint + 1.5, 0.9)
	Game.effects.spawn_dust(b.global_position, clampf(footprint * 0.6, 0.8, 2.5))
	# Every new house brings a couple of new villagers.
	for k in 2:
		WorldPopulator.spawn_villager(self, terrain, b.global_position, 12.0)
	_reroll_ghost()


# --- Helpers ------------------------------------------------------------------

func _pick_ground(screen_pos: Vector2) -> Variant:
	var cam := camera_rig.camera
	return terrain.raycast(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


func _on_terrain_changed(center: Vector3, radius: float) -> void:
	# Keep buildings, trees and rocks sitting on the ground after it is reshaped.
	for node in get_tree().get_nodes_in_group("grounded"):
		var d := node as Node3D
		var flat := Vector2(d.global_position.x - center.x, d.global_position.z - center.z).length()
		if flat < radius + 6.0:
			d.global_position.y = terrain.get_height(d.global_position.x, d.global_position.z)


func _creature_start() -> Vector3:
	if terrain.village_sites.is_empty():
		return Vector3.ZERO
	var site: Dictionary = terrain.village_sites[0]
	var c: Vector2 = site.pos
	var r: float = site.radius
	# Just outside the first village, on the side facing the map centre.
	var dir := (-c).normalized() if c.length() > 1.0 else Vector2.RIGHT
	var p := c + dir * (r + 10.0)
	return Vector3(p.x, 0.0, p.y)


func _update_stats() -> void:
	var tree := get_tree()
	hud.set_stats("Villagers %d   Buildings %d   Trees %d   Fires %d   FPS %d" % [
		tree.get_nodes_in_group("villagers").size(),
		tree.get_nodes_in_group("buildings").size(),
		tree.get_nodes_in_group("trees").size(),
		Game.fire.count(),
		Engine.get_frames_per_second()])


func _setup_brush_ring() -> void:
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = Color(1.0, 0.9, 0.3)
	_ring_material.no_depth_test = true
	_brush_ring = MeshInstance3D.new()
	_brush_ring.mesh = _ring_mesh
	_brush_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_brush_ring)


func _update_brush_ring() -> void:
	var sculpting := mode in [Mode.RAISE, Mode.LOWER, Mode.FLATTEN, Mode.SMOOTH]
	_brush_ring.visible = sculpting and _cursor_hit != null
	if not _brush_ring.visible:
		return
	var c: Vector3 = _cursor_hit
	_ring_mesh.clear_surfaces()
	for r in [brush_radius, brush_radius * 0.4]:
		_ring_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _ring_material)
		for k in 49:
			var a := TAU * k / 48.0
			var x: float = c.x + cos(a) * r
			var z: float = c.z + sin(a) * r
			_ring_mesh.surface_add_vertex(Vector3(x, terrain.get_height(x, z) + 0.25, z))
		_ring_mesh.surface_end()


func _add_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	plane.material = Art.water()
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.position.y = Terrain.WATER_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	var bed_plane := PlaneMesh.new()
	bed_plane.size = Vector2(1400, 1400)
	bed_plane.material = Art.surface("dirt", Color(0.50, 0.44, 0.32), Color(0.38, 0.34, 0.26), {"scale": 0.1})
	var bed := MeshInstance3D.new()
	bed.name = "Seabed"
	bed.mesh = bed_plane
	bed.position.y = -4.5
	add_child(bed)
