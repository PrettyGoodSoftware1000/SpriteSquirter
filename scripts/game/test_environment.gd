class_name TestEnvironment
extends Node3D
## A place to look at a new model inside Godot, as its maker meant it to
## look: the model's own materials (colour, normal and metal/roughness
## maps), no cel shading or outline, under studio lights and a soft sky.
## The camera is the game's (WASD / arrows pan, Q / E turn, wheel zoom,
## middle drag to turn and tilt). Esc goes back to the menu.
##
## "Walk" sets it walking round a wide circle with its walk clip
## (tools/newer_balrog_walk.py). It is heavy: like an elephant it takes a
## few seconds to get going and to come to a stop, and its body leans
## into the change of speed.

const MODEL := "res://assets/test/NewerBalrog.glb"
## The model is 1.7 m tall; this shows it about as big as the game's
## full-grown balrog (11 m).
const MODEL_SCALE := 6.5
## The walk clip (the skeleton and its "Walk" action), and how fast its
## hooves carry the model at its own size: the clip plays as fast as the
## model really walks, so the hooves do not slide.
const WALK_CLIP := "res://assets/test/NewerBalrog_walk.glb"
const WALK_CLIP_SPEED := 0.341
## Its walking speed (about the game balrog's 2.3 m/s) and the circle it
## walks round.
const WALK_SPEED := WALK_CLIP_SPEED * MODEL_SCALE
const WALK_RADIUS := 30.0
## Mass: how quickly its speed follows what it wants (per second; lower is
## heavier). The speed eases in and out, so it never jerks into motion.
const MASS_RESPONSE := 1.3
## The bone the upper body leans from, as it speeds up or slows down.
const LEAN_BONE := "Bone_003"

var _model: Node3D
var _skel: Skeleton3D
var _bones: MeshInstance3D
var _key: DirectionalLight3D
var _env: Environment
var _info: Label
var _speed_label: Label
var _walk: Animation
## [track, bone, track type] for each track of the walk clip.
var _tracks: Array[Array] = []
## Walking round the circle, or on the spot (the clip plays, it stays put).
var _walking := false
var _in_place := false
var _follow := true
## The lighting sliders and their starting values, for "Reset lighting".
var _light_sliders: Array[HSlider] = []
var _light_defaults: Array[float] = []
var _speed := 0.0
var _accel := 0.0
var _heading := 0.0
## How far through the walk clip it is (0..1), and how much of it shows.
var _phase := 0.0
var _walk_w := 0.0


func _ready() -> void:
	_build_lighting()
	_build_floor()
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	_skel = skels[0] as Skeleton3D if not skels.is_empty() else null
	_load_walk()
	_build_bone_lines()
	_build_camera()
	_build_ui()


func _load_walk() -> void:
	if _skel == null or not ResourceLoader.exists(WALK_CLIP):
		return
	var clip := (load(WALK_CLIP) as PackedScene).instantiate()
	var players := clip.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_walk = (players[0] as AnimationPlayer).get_animation("Walk")
	clip.free()
	if _walk == null:
		return
	for track in _walk.get_track_count():
		var bone := _skel.find_bone(String(_walk.track_get_path(track).get_concatenated_subnames()))
		if bone >= 0:
			_tracks.append([track, bone, _walk.track_get_type(track)])


func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	_env = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.5, 0.62)
	sky_mat.sky_horizon_color = Color(0.72, 0.74, 0.78)
	sky_mat.ground_horizon_color = Color(0.5, 0.5, 0.52)
	sky_mat.ground_bottom_color = Color(0.22, 0.22, 0.24)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	# The sky lights it from every side and shows in its shiny parts.
	# (Not too much of it, or it flattens the model's shading: washed out.)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.5
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	# A little more contrast and colour; the sliders change these.
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.12
	_env.adjustment_saturation = 1.15
	_env.ssao_enabled = true
	_env.ssao_radius = 1.5
	_env.ssao_intensity = 1.6
	world.environment = _env
	add_child(world)
	# Studio lights: a key light with shadows, a soft fill from the other
	# side, and a rim light from behind to pick out the outline.
	_key = DirectionalLight3D.new()
	_key.name = "KeyLight"
	_key.light_energy = 2.6
	_key.shadow_enabled = true
	_key.directional_shadow_max_distance = 120.0
	_key.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	add_child(_key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.4
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.rotation_degrees = Vector3(-20.0, -60.0, 0.0)
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_energy = 1.1
	rim.rotation_degrees = Vector3(-25.0, 180.0, 0.0)
	add_child(rim)


func _build_floor() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(4000, 4000)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.32, 0.34)
	mat.roughness = 0.9
	floor_mesh.material = mat
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = floor_mesh
	add_child(floor_node)


## The skeleton as lines from each bone to its parent, drawn over the model.
func _build_bone_lines() -> void:
	_bones = MeshInstance3D.new()
	_bones.name = "BoneLines"
	_bones.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	mat.render_priority = 10
	_bones.material_override = mat
	_bones.visible = false
	add_child(_bones)


func _draw_bones() -> void:
	var im := _bones.mesh as ImmediateMesh
	im.clear_surfaces()
	if _skel == null or _skel.get_bone_count() == 0:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var to_world := _skel.global_transform
	for i in _skel.get_bone_count():
		var parent := _skel.get_bone_parent(i)
		var at := to_world * _skel.get_bone_global_pose(i).origin
		if parent >= 0:
			im.surface_set_color(Color(1.0, 0.75, 0.2))
			im.surface_add_vertex(to_world * _skel.get_bone_global_pose(parent).origin)
			im.surface_set_color(Color(1.0, 0.3, 0.1))
			im.surface_add_vertex(at)
		# A small cross at every joint.
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			im.surface_set_color(Color(0.4, 0.9, 1.0))
			im.surface_add_vertex(at - axis * 0.12)
			im.surface_add_vertex(at + axis * 0.12)
	im.surface_end()


func _build_camera() -> void:
	var rig := RtsCamera.new()
	rig.name = "CameraRig"
	rig.zoom_min = 3.0
	rig.zoom_max = 120.0
	rig.bounds = 140.0
	rig.focus_lift = 5.5
	add_child(rig)
	Game.camera_rig = rig
	rig.yaw = 0.5
	rig.pitch = deg_to_rad(18.0)
	rig.set_zoom(26.0, true)
	rig.focus_on(Vector3.ZERO, true)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.theme = UiTheme.get_theme()
	panel.position = Vector2(16, 16)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Test environment"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_info = Label.new()
	_info.text = _model_info()
	_info.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_info)
	var bones := _button("Show skeleton")
	bones.toggle_mode = true
	bones.toggled.connect(func(on: bool) -> void: _bones.visible = on)
	box.add_child(bones)
	box.add_child(_heading_label("Walk"))
	var walk_row := HBoxContainer.new()
	walk_row.add_theme_constant_override("separation", 6)
	box.add_child(walk_row)
	var in_place := _button("Play walk in place")
	var around := _button("Walk around")
	for b: Button in [in_place, around]:
		b.toggle_mode = true
		b.disabled = _walk == null
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		walk_row.add_child(b)
	# One or the other: switching between them keeps its momentum.
	in_place.toggled.connect(func(on: bool) -> void:
		_in_place = on
		if on:
			around.set_pressed_no_signal(false)
		_walking = on)
	around.toggled.connect(func(on: bool) -> void:
		_in_place = false
		if on:
			in_place.set_pressed_no_signal(false)
		_walking = on)
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 6)
	box.add_child(cam_row)
	var follow := _button("Camera follows")
	follow.toggle_mode = true
	follow.button_pressed = true
	follow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	follow.toggled.connect(func(on: bool) -> void: _follow = on)
	cam_row.add_child(follow)
	var home := _button("Back to start")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.pressed.connect(func() -> void:
		_heading = 0.0
		_model.position = Vector3.ZERO
		_model.rotation.y = 0.0)
	cam_row.add_child(home)
	_speed_label = Label.new()
	_speed_label.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_speed_label)

	box.add_child(_heading_label("Lighting"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	box.add_child(grid)
	_slider(grid, "Brightness", 0.3, 2.5, _env.tonemap_exposure, func(v: float) -> void: _env.tonemap_exposure = v)
	_slider(grid, "Contrast", 0.5, 2.0, _env.adjustment_contrast, func(v: float) -> void: _env.adjustment_contrast = v)
	_slider(grid, "Colour", 0.0, 2.0, _env.adjustment_saturation, func(v: float) -> void: _env.adjustment_saturation = v)
	_slider(grid, "Sky light", 0.0, 2.0, _env.ambient_light_energy, func(v: float) -> void: _env.ambient_light_energy = v)
	_slider(grid, "Key light", 0.0, 6.0, _key.light_energy, func(v: float) -> void: _key.light_energy = v)
	_slider(grid, "Key direction", -180.0, 180.0, _key.rotation_degrees.y, func(v: float) -> void: _key.rotation_degrees.y = v)
	_slider(grid, "Key height", 5.0, 85.0, -_key.rotation_degrees.x, func(v: float) -> void: _key.rotation_degrees.x = -v)
	_slider(grid, "Shadows (SSAO)", 0.0, 4.0, _env.ssao_intensity, func(v: float) -> void: _env.ssao_intensity = v)
	var reset := _button("Reset lighting")
	reset.pressed.connect(func() -> void:
		for i in _light_sliders.size():
			_light_sliders[i].value = _light_defaults[i])
	box.add_child(reset)
	var help := Label.new()
	help.text = "WASD pan   Q / E turn   wheel zoom   middle drag tilt"
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.65)
	box.add_child(help)
	var back := _button("Back to menu")
	back.pressed.connect(_back)
	box.add_child(back)


func _model_info() -> String:
	var tris := 0
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	var clips := (players[0] as AnimationPlayer).get_animation_list().size() if not players.is_empty() else 0
	var walk := "\nWalk: %.1f s a cycle (%s)" % [_walk.length, WALK_CLIP.get_file()] if _walk != null else "\nNo walk clip"
	return "%s\n%d triangles, %d bones, %d animations%s" % [MODEL.get_file(), tris,
		_skel.get_bone_count() if _skel != null else 0, clips, walk]


func _process(delta: float) -> void:
	_update_walk(delta)
	if _bones.visible:
		_draw_bones()


## Speed with mass: a critically damped spring, so speeding up and slowing
## down both start gently, build, and ease off (seconds, not a moment).
func _update_walk(delta: float) -> void:
	if _walk == null:
		return
	var want := WALK_SPEED if _walking else 0.0
	_accel += ((want - _speed) * MASS_RESPONSE * MASS_RESPONSE - 2.0 * MASS_RESPONSE * _accel) * delta
	_speed = maxf(0.0, _speed + _accel * delta)
	if not _walking and _speed < 0.02:
		_speed = 0.0
		_accel = 0.0
	# Round the circle (or on the spot: the clip plays, the body stays).
	if not _in_place:
		_heading += _speed / WALK_RADIUS * delta
		_model.rotation.y = _heading
		_model.position += Vector3(sin(_heading), 0.0, cos(_heading)) * _speed * delta
	# The clip runs as fast as it walks; mixed with the standing pose while
	# it gets going or comes to a stop.
	_phase = fposmod(_phase + delta * _speed / WALK_SPEED / _walk.length, 1.0)
	_walk_w = lerpf(_walk_w, clampf(_speed / (0.35 * WALK_SPEED), 0.0, 1.0), 1.0 - exp(-4.0 * delta))
	_skel.reset_bone_poses()
	if _walk_w > 0.001:
		var time := _phase * _walk.length
		for entry in _tracks:
			var track: int = entry[0]
			var bone: int = entry[1]
			match entry[2]:
				Animation.TYPE_ROTATION_3D:
					var rest := _skel.get_bone_rest(bone).basis.get_rotation_quaternion()
					_skel.set_bone_pose_rotation(bone, rest.slerp(_walk.rotation_track_interpolate(track, time), _walk_w))
				Animation.TYPE_POSITION_3D:
					var at := _skel.get_bone_rest(bone).origin
					_skel.set_bone_pose_position(bone, at.lerp(_walk.position_track_interpolate(track, time), _walk_w))
	# The upper body leans into speeding up and back when slowing down.
	var lean := clampf(_accel * 0.09, -0.1, 0.1)
	var spine := _skel.find_bone(LEAN_BONE)
	if spine >= 0 and absf(lean) > 0.0001:
		var pose := _skel.get_bone_global_pose(spine)
		pose.basis = Basis(Vector3.RIGHT, lean) * pose.basis
		_skel.set_bone_global_pose(spine, pose)
	if _follow and _speed > 0.0:
		var rig := Game.camera_rig
		rig.focus.x = _model.position.x
		rig.focus.z = _model.position.z
	_speed_label.text = "Speed %.1f m/s" % _speed


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE:
		_back()


func _back() -> void:
	Game.start("menu", "", Terrain.SIZE)


## A row of `grid` (3 columns): a name, a slider that calls `apply`, and
## the value.
func _slider(grid: GridContainer, text: String, lo: float, hi: float, value: float, apply: Callable) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 200.0
	s.custom_minimum_size.x = 200
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value = value
	grid.add_child(s)
	var shown := Label.new()
	shown.custom_minimum_size.x = 44
	shown.modulate = Color(1, 1, 1, 0.7)
	shown.text = "%.2f" % value if hi <= 10.0 else "%d" % roundi(value)
	grid.add_child(shown)
	s.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		shown.text = "%.2f" % v if hi <= 10.0 else "%d" % roundi(v))
	_light_sliders.append(s)
	_light_defaults.append(value)


func _heading_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(1.0, 0.9, 0.6)
	return label


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	return b
