class_name Atmosphere
extends Node3D
## Sky, sun, fog and colour grading. The sun always sits low enough (never
## overhead) for the cel shading to show the shape of things. A "mood" is one complete lighting
## setup; switching moods blends every value smoothly, which shifts the
## whole world's colours away from the base palette (green meadow by day,
## orange haze at golden hour, blue mist at dawn, firelight at night).

signal mood_changed(mood_name: String)

const MOODS := [
	{
		"name": "Meadow day",
		"sun_elevation": 33.0, "sun_azimuth": -38.0,
		"sun_color": Color(1.0, 0.93, 0.76), "sun_energy": 1.8,
		"ambient_color": Color(0.46, 0.52, 0.86), "ambient_energy": 0.72,
		"sky_top": Color(0.20, 0.46, 0.88), "sky_horizon": Color(0.66, 0.84, 0.96), "sky_ground": Color(0.42, 0.62, 0.90),
		"cloud_color": Color(1.0, 0.99, 0.96), "cloud_shade": Color(0.70, 0.78, 0.92), "cloud_cover": 0.36, "sun_glow": 1.0,
		"fog_color": Color(0.66, 0.82, 0.94), "fog_density": 0.0003,
		"mist_density": 0.0012, "mist_color": Color(0.88, 0.95, 0.86),
		"saturation": 1.12, "window_glow": 0.0, "particle_light": Color(1, 1, 1),
	},
	{
		"name": "Golden hour",
		"sun_elevation": 13.0, "sun_azimuth": -62.0,
		"sun_color": Color(1.0, 0.58, 0.28), "sun_energy": 1.9,
		"ambient_color": Color(0.56, 0.38, 0.62), "ambient_energy": 0.5,
		"sky_top": Color(0.36, 0.42, 0.70), "sky_horizon": Color(1.0, 0.72, 0.48), "sky_ground": Color(0.80, 0.55, 0.36),
		"cloud_color": Color(1.0, 0.76, 0.55), "cloud_shade": Color(0.62, 0.45, 0.52), "cloud_cover": 0.5, "sun_glow": 1.6,
		"fog_color": Color(0.96, 0.66, 0.42), "fog_density": 0.0017,
		"mist_density": 0.013, "mist_color": Color(1.0, 0.80, 0.58),
		"saturation": 1.18, "window_glow": 0.8, "particle_light": Color(1.0, 0.8, 0.65),
	},
	{
		"name": "Misty dawn",
		"sun_elevation": 24.0, "sun_azimuth": 118.0,
		"sun_color": Color(0.82, 0.92, 1.0), "sun_energy": 1.35,
		"ambient_color": Color(0.34, 0.50, 0.74), "ambient_energy": 0.58,
		"sky_top": Color(0.32, 0.52, 0.74), "sky_horizon": Color(0.70, 0.84, 0.90), "sky_ground": Color(0.55, 0.70, 0.78),
		"cloud_color": Color(0.92, 0.97, 1.0), "cloud_shade": Color(0.50, 0.62, 0.74), "cloud_cover": 0.6, "sun_glow": 1.3,
		"fog_color": Color(0.55, 0.72, 0.80), "fog_density": 0.004,
		"mist_density": 0.034, "mist_color": Color(0.80, 0.92, 1.0),
		"saturation": 1.05, "window_glow": 0.4, "particle_light": Color(0.75, 0.88, 1.0),
	},
	{
		"name": "Night",
		"sun_elevation": 30.0, "sun_azimuth": 150.0,
		"sun_color": Color(0.45, 0.58, 1.0), "sun_energy": 0.6,
		"ambient_color": Color(0.15, 0.22, 0.50), "ambient_energy": 0.95,
		"sky_top": Color(0.012, 0.02, 0.07), "sky_horizon": Color(0.10, 0.14, 0.30), "sky_ground": Color(0.07, 0.10, 0.22),
		"cloud_color": Color(0.16, 0.20, 0.34), "cloud_shade": Color(0.04, 0.05, 0.10), "cloud_cover": 0.4, "sun_glow": 0.5,
		"fog_color": Color(0.05, 0.08, 0.17), "fog_density": 0.0016,
		"mist_density": 0.008, "mist_color": Color(0.22, 0.28, 0.5),
		"saturation": 1.1, "window_glow": 3.0, "particle_light": Color(0.10, 0.12, 0.19),
	},
]

var mood_index := 0

var _env := Environment.new()
var _sky_material := ShaderMaterial.new()
var _sun := DirectionalLight3D.new()
var _current := {}
var _from := {}
var _blend := 1.0
var _blend_time := 1.0


func _ready() -> void:
	_sky_material.shader = Art.shader("sky")
	_sky_material.set_shader_parameter("noise_tex", Art.tex("noise"))
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_white = 6.0
	_env.glow_enabled = true
	# Only things that really glow (fire, crystals, windows) should bloom.
	_env.glow_intensity = 0.45
	_env.glow_bloom = 0.0
	_env.glow_hdr_threshold = 1.4
	_env.ssao_enabled = true
	_env.ssao_radius = 2.0
	_env.ssao_intensity = 1.0
	_env.fog_enabled = true
	_env.fog_sun_scatter = 0.25
	_env.fog_aerial_perspective = 0.25
	_env.fog_sky_affect = 0.0
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 330.0
	_sun.directional_shadow_blend_splits = true
	_sun.light_angular_distance = 0.15
	_sun.shadow_bias = 0.06
	_sun.shadow_normal_bias = 1.6
	add_child(_sun)

	_current = MOODS[0].duplicate()
	_apply(_current)


func mood_name() -> String:
	return MOODS[mood_index].name


func next_mood(duration := 4.0) -> void:
	set_mood((mood_index + 1) % MOODS.size(), duration)


func set_mood(index: int, duration := 4.0) -> void:
	mood_index = index
	_from = _current.duplicate()
	_blend = 0.0
	_blend_time = maxf(duration, 0.01)
	if duration <= 0.0:
		_blend = 1.0
		_current = MOODS[index].duplicate()
		_apply(_current)
	mood_changed.emit(mood_name())


func _process(delta: float) -> void:
	if _blend >= 1.0:
		return
	_blend = minf(1.0, _blend + delta / _blend_time)
	var t := smoothstep(0.0, 1.0, _blend)
	var target: Dictionary = MOODS[mood_index]
	for key in target:
		if key == "name":
			continue
		if key == "sun_azimuth":
			_current[key] = rad_to_deg(lerp_angle(deg_to_rad(_from[key]), deg_to_rad(target[key]), t))
		else:
			_current[key] = lerp(_from[key], target[key], t)
	_apply(_current)


func _apply(m: Dictionary) -> void:
	_sun.rotation_degrees = Vector3(-m.sun_elevation, m.sun_azimuth, 0.0)
	_sun.light_color = m.sun_color
	_sun.light_energy = m.sun_energy
	_env.ambient_light_color = m.ambient_color
	_env.ambient_light_energy = m.ambient_energy
	_env.fog_light_color = m.fog_color
	# Flat distance haze only: volumetric fog smears the clean cel-shaded shapes.
	_env.fog_density = m.fog_density + m.mist_density * 0.2
	_env.adjustment_saturation = m.saturation
	_sky_material.set_shader_parameter("top_color", m.sky_top)
	_sky_material.set_shader_parameter("horizon_color", m.sky_horizon)
	_sky_material.set_shader_parameter("ground_color", m.sky_ground)
	_sky_material.set_shader_parameter("sun_color", m.sun_color)
	_sky_material.set_shader_parameter("cloud_color", m.cloud_color)
	_sky_material.set_shader_parameter("cloud_shade", m.cloud_shade)
	_sky_material.set_shader_parameter("cloud_cover", m.cloud_cover)
	_sky_material.set_shader_parameter("sun_glow", m.sun_glow)
	Art.set_window_glow(m.window_glow)
	Art.set_particle_ambient(m.particle_light)
