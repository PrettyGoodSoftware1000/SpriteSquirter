class_name Art
extends RefCounted
## The shared look of the game: colour palettes, textures and cached
## materials. Everything visual asks this class for its materials, so the
## whole art style can be tuned in one place.
##
## Nature (terrain, grass, trees, rocks, water) takes its colours from the
## current palette, which can be swapped while the game runs with
## set_palette(). Buildings and characters keep their own colours.

const TEX_DIR := "res://assets/textures/"
const SHADER_DIR := "res://shaders/"

## Nature palettes. Add a dictionary here to get a new button in the dev menu.
const PALETTES := [
	{
		# Teal hills, red-brown trees and violet rock, after comic-style alpine art.
		"name": "Alpine",
		"grass_root": Color(0.08, 0.34, 0.30), "grass_tip": Color(0.46, 0.74, 0.36), "grass_dry": Color(0.84, 0.80, 0.34),
		"leaf": Color(0.30, 0.66, 0.44), "leaf_dark": Color(0.08, 0.36, 0.38),
		"pine": Color(0.12, 0.44, 0.42), "pine_dark": Color(0.05, 0.20, 0.32),
		"accent": Color(0.86, 0.30, 0.20), "accent_dark": Color(0.50, 0.12, 0.18),
		"bark": Color(0.48, 0.28, 0.24), "bark_dark": Color(0.25, 0.12, 0.18),
		"rock": Color(0.60, 0.58, 0.72), "rock_dark": Color(0.34, 0.32, 0.54), "moss": Color(0.40, 0.68, 0.34),
		"dirt": Color(0.64, 0.46, 0.34), "dirt_dark": Color(0.42, 0.27, 0.27), "sand": Color(0.88, 0.80, 0.56),
		"water": Color(0.22, 0.80, 0.88), "water_deep": Color(0.08, 0.40, 0.74),
	},
	{
		"name": "Meadow",
		"grass_root": Color(0.10, 0.26, 0.07), "grass_tip": Color(0.44, 0.62, 0.15), "grass_dry": Color(0.66, 0.64, 0.22),
		"leaf": Color(0.40, 0.66, 0.14), "leaf_dark": Color(0.14, 0.38, 0.10),
		"pine": Color(0.16, 0.42, 0.24), "pine_dark": Color(0.06, 0.24, 0.16),
		"accent": Color(0.96, 0.56, 0.10), "accent_dark": Color(0.70, 0.22, 0.06),
		"bark": Color(0.42, 0.33, 0.25), "bark_dark": Color(0.27, 0.20, 0.16),
		"rock": Color(0.52, 0.50, 0.47), "rock_dark": Color(0.36, 0.35, 0.37), "moss": Color(0.24, 0.42, 0.12),
		"dirt": Color(0.46, 0.34, 0.22), "dirt_dark": Color(0.33, 0.24, 0.16), "sand": Color(0.78, 0.68, 0.45),
		"water": Color(0.18, 0.62, 0.66), "water_deep": Color(0.06, 0.30, 0.50),
	},
	{
		"name": "Candy",
		"grass_root": Color(0.62, 0.20, 0.42), "grass_tip": Color(1.0, 0.56, 0.72), "grass_dry": Color(1.0, 0.80, 0.55),
		"leaf": Color(0.30, 0.82, 0.78), "leaf_dark": Color(0.10, 0.48, 0.56),
		"pine": Color(0.62, 0.46, 0.92), "pine_dark": Color(0.34, 0.20, 0.62),
		"accent": Color(1.0, 0.90, 0.32), "accent_dark": Color(0.94, 0.56, 0.12),
		"bark": Color(0.52, 0.30, 0.42), "bark_dark": Color(0.32, 0.16, 0.30),
		"rock": Color(0.72, 0.62, 0.80), "rock_dark": Color(0.48, 0.38, 0.62), "moss": Color(0.98, 0.62, 0.78),
		"dirt": Color(0.70, 0.46, 0.40), "dirt_dark": Color(0.52, 0.30, 0.32), "sand": Color(1.0, 0.86, 0.74),
		"water": Color(0.50, 0.90, 0.86), "water_deep": Color(0.24, 0.50, 0.86),
	},
	{
		"name": "Autumn",
		"grass_root": Color(0.36, 0.22, 0.06), "grass_tip": Color(0.86, 0.60, 0.16), "grass_dry": Color(0.92, 0.78, 0.36),
		"leaf": Color(0.94, 0.46, 0.10), "leaf_dark": Color(0.60, 0.16, 0.06),
		"pine": Color(0.36, 0.42, 0.16), "pine_dark": Color(0.16, 0.24, 0.10),
		"accent": Color(0.98, 0.80, 0.18), "accent_dark": Color(0.78, 0.46, 0.08),
		"bark": Color(0.36, 0.26, 0.20), "bark_dark": Color(0.20, 0.14, 0.12),
		"rock": Color(0.56, 0.48, 0.42), "rock_dark": Color(0.38, 0.32, 0.30), "moss": Color(0.62, 0.50, 0.14),
		"dirt": Color(0.42, 0.28, 0.18), "dirt_dark": Color(0.28, 0.18, 0.12), "sand": Color(0.80, 0.64, 0.42),
		"water": Color(0.20, 0.52, 0.56), "water_deep": Color(0.08, 0.24, 0.38),
	},
	{
		"name": "Alien",
		"grass_root": Color(0.20, 0.08, 0.40), "grass_tip": Color(0.56, 0.34, 0.92), "grass_dry": Color(0.30, 0.86, 0.80),
		"leaf": Color(0.16, 0.88, 0.72), "leaf_dark": Color(0.04, 0.44, 0.52),
		"pine": Color(0.92, 0.30, 0.56), "pine_dark": Color(0.52, 0.10, 0.38),
		"accent": Color(0.98, 0.78, 0.14), "accent_dark": Color(0.90, 0.38, 0.08),
		"bark": Color(0.24, 0.20, 0.42), "bark_dark": Color(0.12, 0.10, 0.26),
		"rock": Color(0.88, 0.50, 0.26), "rock_dark": Color(0.60, 0.26, 0.20), "moss": Color(0.30, 0.86, 0.70),
		"dirt": Color(0.34, 0.20, 0.40), "dirt_dark": Color(0.22, 0.12, 0.30), "sand": Color(0.94, 0.70, 0.50),
		"water": Color(0.86, 0.36, 0.76), "water_deep": Color(0.42, 0.12, 0.56),
	},
	{
		"name": "Frost",
		"grass_root": Color(0.36, 0.52, 0.62), "grass_tip": Color(0.86, 0.94, 0.98), "grass_dry": Color(0.70, 0.82, 0.96),
		"leaf": Color(0.80, 0.92, 0.98), "leaf_dark": Color(0.44, 0.64, 0.82),
		"pine": Color(0.30, 0.56, 0.60), "pine_dark": Color(0.12, 0.32, 0.42),
		"accent": Color(0.74, 0.62, 0.94), "accent_dark": Color(0.42, 0.34, 0.74),
		"bark": Color(0.40, 0.38, 0.44), "bark_dark": Color(0.22, 0.22, 0.30),
		"rock": Color(0.62, 0.68, 0.78), "rock_dark": Color(0.40, 0.46, 0.60), "moss": Color(0.92, 0.96, 1.0),
		"dirt": Color(0.50, 0.50, 0.56), "dirt_dark": Color(0.36, 0.36, 0.44), "sand": Color(0.86, 0.90, 0.96),
		"water": Color(0.56, 0.84, 0.94), "water_deep": Color(0.20, 0.42, 0.72),
	},
	{
		"name": "Ember",
		"grass_root": Color(0.12, 0.10, 0.10), "grass_tip": Color(0.42, 0.36, 0.32), "grass_dry": Color(0.90, 0.40, 0.10),
		"leaf": Color(0.92, 0.26, 0.10), "leaf_dark": Color(0.44, 0.06, 0.06),
		"pine": Color(0.30, 0.26, 0.26), "pine_dark": Color(0.12, 0.10, 0.12),
		"accent": Color(1.0, 0.72, 0.16), "accent_dark": Color(0.90, 0.34, 0.06),
		"bark": Color(0.20, 0.17, 0.17), "bark_dark": Color(0.09, 0.08, 0.09),
		"rock": Color(0.30, 0.27, 0.28), "rock_dark": Color(0.16, 0.14, 0.16), "moss": Color(0.86, 0.34, 0.08),
		"dirt": Color(0.26, 0.20, 0.18), "dirt_dark": Color(0.15, 0.11, 0.11), "sand": Color(0.44, 0.36, 0.32),
		"water": Color(0.98, 0.52, 0.12), "water_deep": Color(0.62, 0.14, 0.06),
	},
]

# --- Fixed colours for buildings and characters ------------------------------
const TIMBER := Color(0.33, 0.22, 0.13)
const TIMBER_DARK := Color(0.21, 0.14, 0.09)
const WOOD := Color(0.56, 0.38, 0.22)
const WOOD_DARK := Color(0.40, 0.26, 0.15)
const CLOTH_COLORS := [
	Color(0.72, 0.16, 0.13), Color(0.18, 0.36, 0.66), Color(0.90, 0.68, 0.15),
	Color(0.25, 0.52, 0.22), Color(0.56, 0.26, 0.60), Color(0.92, 0.46, 0.12),
	Color(0.88, 0.84, 0.74), Color(0.14, 0.50, 0.52),
]
const SKIN_COLORS := [Color(0.94, 0.72, 0.56), Color(0.76, 0.52, 0.38), Color(0.48, 0.32, 0.22), Color(0.88, 0.64, 0.50)]
const GOBLIN_SKIN := [Color(0.42, 0.62, 0.22), Color(0.30, 0.52, 0.26), Color(0.56, 0.66, 0.24)]

## Texture repeats per metre for each surface kind.
const SURFACE_SCALE := {
	"stone": 0.4, "rock": 0.3, "planks": 0.8, "shingles": 0.5, "plaster": 0.33,
	"bark": 0.66, "thatch": 0.6, "dirt": 0.4, "ground": 0.3, "hide": 0.55,
}
## Nature roles: [texture kind, light colour key, dark colour key, options].
const NATURE_ROLES := {
	"leaf": ["hide", "leaf", "leaf_dark", {"ink": 0.45}],
	"pine": ["hide", "pine", "pine_dark", {"ink": 0.45, "scale": 0.8}],
	"accent": ["hide", "accent", "accent_dark", {"ink": 0.45}],
	"bark": ["bark", "bark", "bark_dark", {}],
	"rock": ["rock", "rock", "rock_dark", {"moss": 1.0}],
	"turf": ["ground", "grass_tip", "grass_root", {"ink": 0.3, "scale": 0.5}],
}

static var palette_index := 0

static var _materials := {}
static var _glass: Array[ShaderMaterial] = []
static var _ambient_tinted: Array[ShaderMaterial] = []
static var _terrain_textures: Array = [null, null, null]
static var _terrain_samples := 257.0


static func tex(tex_name: String) -> Texture2D:
	return load(TEX_DIR + tex_name + ".png")


static func shader(shader_name: String) -> Shader:
	return load(SHADER_DIR + shader_name + ".gdshader")


static func palette() -> Dictionary:
	return PALETTES[palette_index]


# --- Cel-shaded surfaces ----------------------------------------------------

## A triplanar cel-shaded material. `kind` picks the texture set (see
## SURFACE_SCALE); colour_a/b tint individual bricks, planks or shingles.
## Options: scale, ink (0..1 line darkness), moss, outline (line width, 0 = none).
static func surface(kind: String, color_a: Color, color_b: Color, opts := {}) -> ShaderMaterial:
	var key := "surface|%s|%s|%s|%s" % [kind, color_a.to_html(), color_b.to_html(), opts]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = shader("surface")
	m.set_shader_parameter("detail_tex", tex(kind + "_detail"))
	m.set_shader_parameter("normal_tex", tex(kind + "_normal"))
	m.set_shader_parameter("color_a", color_a)
	m.set_shader_parameter("color_b", color_b)
	m.set_shader_parameter("moss_color", palette().moss)
	m.set_shader_parameter("tex_scale", opts.get("scale", SURFACE_SCALE[kind]))
	m.set_shader_parameter("ink", opts.get("ink", 0.8))
	m.set_shader_parameter("moss", opts.get("moss", 0.0))
	var width: float = opts.get("outline", 1.0)
	if width > 0.0:
		m.next_pass = outline(width)
	_materials[key] = m
	return m


## The black ink outline drawn around a mesh as a second pass.
static func outline(width := 1.0) -> ShaderMaterial:
	var key := "outline|%.2f" % width
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader("outline")
		m.set_shader_parameter("width", width)
		_materials[key] = m
	return _materials[key]


## A white material of the given texture kind, meant to be coloured per
## shape with MeshBuilder.color. This is how buildings get their colours.
static func paint(kind: String, outline_width := 1.0) -> ShaderMaterial:
	return surface(kind, Color(1, 1, 1), Color(0.86, 0.86, 0.86), {"outline": outline_width})


## Like paint(), but the surface also glows in its own colour (crystals,
## runes, the moon).
static func glow(energy := 1.6) -> ShaderMaterial:
	var key := "glow|%.2f" % energy
	if not _materials.has(key):
		var m := surface("plaster", Color(1, 1, 1), Color(0.9, 0.9, 0.9), {"ink": 0.2, "glow": energy})
		m.set_shader_parameter("glow_color", Color(1, 1, 1))
		m.set_shader_parameter("glow_energy", energy)
		_materials[key] = m
	return _materials[key]


static func timber() -> ShaderMaterial:
	return surface("planks", TIMBER, TIMBER_DARK, {"scale": 1.6, "outline": 0.0})


static func wood() -> ShaderMaterial:
	return surface("planks", WOOD, WOOD_DARK, {"outline": 0.0})


## Cloth and skin for small characters, coloured by vertex colour.
static func cloth() -> ShaderMaterial:
	return surface("plaster", Color(1, 1, 1), Color(0.88, 0.88, 0.88), {"scale": 2.5, "ink": 0.2, "outline": 0.42})


## Window panes. They light up when Art.set_window_glow() is raised at dusk.
static func glass() -> ShaderMaterial:
	if _materials.has("glass"):
		return _materials["glass"]
	var m := surface("plaster", Color(0.10, 0.14, 0.22), Color(0.16, 0.22, 0.30), {"scale": 1.0, "ink": 0.0, "outline": 0.0, "glass": true})
	m.set_shader_parameter("glow_color", Color(1.0, 0.66, 0.24))
	_glass.append(m)
	_materials["glass"] = m
	return m


static func set_window_glow(energy: float) -> void:
	for m in _glass:
		m.set_shader_parameter("glow_energy", energy)


# --- Nature (follows the palette) ---------------------------------------------

## Material for a natural feature: "leaf", "pine", "accent", "bark", "rock"
## or "turf". Its colours change with the palette.
static func nature(role: String) -> ShaderMaterial:
	var key := "nature|" + role
	if not _materials.has(key):
		var info: Array = NATURE_ROLES[role]
		var m := surface(info[0], Color(1, 1, 1), Color(1, 1, 1), info[3].merged({"role": role}))
		_materials[key] = m
		_apply_palette_to(role, m)
	return _materials[key]


static func grass() -> ShaderMaterial:
	if not _materials.has("grass"):
		var m := ShaderMaterial.new()
		m.shader = shader("grass")
		m.set_shader_parameter("noise_tex", tex("noise"))
		_materials["grass"] = m
		_apply_terrain_textures(m)
		_apply_palette_to("grass", m)
	return _materials["grass"]


static func terrain() -> ShaderMaterial:
	if not _materials.has("terrain"):
		var m := ShaderMaterial.new()
		m.shader = shader("terrain")
		m.set_shader_parameter("noise_tex", tex("noise"))
		for layer in ["ground", "dirt", "rock"]:
			m.set_shader_parameter(layer + "_detail", tex(layer + "_detail"))
			m.set_shader_parameter(layer + "_normal", tex(layer + "_normal"))
		_materials["terrain"] = m
		_apply_terrain_textures(m)
		_apply_palette_to("terrain", m)
	return _materials["terrain"]


static func water() -> ShaderMaterial:
	if not _materials.has("water"):
		var m := ShaderMaterial.new()
		m.shader = shader("water")
		m.set_shader_parameter("noise_tex", tex("noise"))
		_materials["water"] = m
		_apply_terrain_textures(m)
		_apply_palette_to("water", m)
	return _materials["water"]


static func waterfall() -> ShaderMaterial:
	if not _materials.has("waterfall"):
		var m := ShaderMaterial.new()
		m.shader = shader("waterfall")
		m.set_shader_parameter("noise_tex", tex("noise"))
		_materials["waterfall"] = m
		_apply_palette_to("waterfall", m)
	return _materials["waterfall"]


## Switches every natural material to another palette, instantly.
static func set_palette(index: int) -> void:
	palette_index = posmod(index, PALETTES.size())
	for key in _materials:
		var k: String = key
		if k.begins_with("nature|"):
			_apply_palette_to(k.trim_prefix("nature|"), _materials[key])
		elif k in ["grass", "terrain", "water", "waterfall"]:
			_apply_palette_to(k, _materials[key])
		elif k.begins_with("surface|"):
			(_materials[key] as ShaderMaterial).set_shader_parameter("moss_color", palette().moss)


static func _apply_palette_to(role: String, m: ShaderMaterial) -> void:
	var p := palette()
	match role:
		"grass":
			m.set_shader_parameter("color_root", p.grass_root)
			m.set_shader_parameter("color_tip", p.grass_tip)
			m.set_shader_parameter("color_dry", p.grass_dry)
		"terrain":
			# The ground under the blades is a blend of the grass root and tip colours.
			var root: Color = p.grass_root
			var tip: Color = p.grass_tip
			var dry: Color = p.grass_dry
			m.set_shader_parameter("grass_a", root.lerp(tip, 0.3))
			m.set_shader_parameter("grass_b", root.lerp(tip, 0.75))
			m.set_shader_parameter("grass_dry", dry.darkened(0.15))
			m.set_shader_parameter("dirt_a", p.dirt)
			m.set_shader_parameter("dirt_b", p.dirt_dark)
			m.set_shader_parameter("rock_a", p.rock)
			m.set_shader_parameter("rock_b", p.rock_dark)
			m.set_shader_parameter("sand_color", p.sand)
		"water", "waterfall":
			m.set_shader_parameter("shallow_color", p.water)
			m.set_shader_parameter("deep_color", p.water_deep)
		_:
			var info: Array = NATURE_ROLES[role]
			m.set_shader_parameter("color_a", p[info[1]])
			m.set_shader_parameter("color_b", p[info[2]])
			m.set_shader_parameter("moss_color", p.moss)


## Called by Terrain whenever it (re)creates its data textures, so the
## terrain, grass and water shaders all read the same world.
static func bind_terrain(height: Texture2D, scorch: Texture2D, mask: Texture2D, samples: int) -> void:
	_terrain_textures = [height, scorch, mask]
	_terrain_samples = samples
	for key in ["terrain", "grass", "water"]:
		if _materials.has(key):
			_apply_terrain_textures(_materials[key])


static func _apply_terrain_textures(m: ShaderMaterial) -> void:
	m.set_shader_parameter("height_tex", _terrain_textures[0])
	m.set_shader_parameter("scorch_tex", _terrain_textures[1])
	m.set_shader_parameter("mask_tex", _terrain_textures[2])
	m.set_shader_parameter("world_n", _terrain_samples)


# --- Particles --------------------------------------------------------------

## kind: "flame", "ember", "smoke", "dust" or "mist".
static func particle(kind: String) -> ShaderMaterial:
	var key := "particle|" + kind
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = shader("particle")
	match kind:
		"flame":
			m.set_shader_parameter("sprite_tex", tex("flame"))
			m.set_shader_parameter("noise_tex", tex("noise"))
			m.set_shader_parameter("flame", 1.0)
			m.set_shader_parameter("glow", 2.4)
		"ember":
			m.set_shader_parameter("sprite_tex", tex("flame"))
			m.set_shader_parameter("color_hot", Color(1.0, 0.8, 0.3))
			m.set_shader_parameter("color_cool", Color(1.0, 0.4, 0.05))
			m.set_shader_parameter("glow", 5.0)
		_:
			m.set_shader_parameter("sprite_tex", tex("smoke"))
			m.set_shader_parameter("use_ramp", 0.0)
			_ambient_tinted.append(m)
	_materials[key] = m
	return m


## Smoke, dust and mist are unlit sprites, so the Atmosphere tells them how
## bright the world currently is.
static func set_particle_ambient(color: Color) -> void:
	for m in _ambient_tinted:
		m.set_shader_parameter("ambient", color)
