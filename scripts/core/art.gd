class_name Art
extends RefCounted
## The shared look of the game: colour palette, textures and cached
## materials. Everything visual asks this class for its materials, so the
## whole art style can be tuned in one place.

const TEX_DIR := "res://assets/textures/"
const SHADER_DIR := "res://shaders/"

# --- Palette (albedo colours, before lighting) ------------------------------
const GRASS_ROOT := Color(0.10, 0.24, 0.06)
const GRASS_TIP := Color(0.44, 0.60, 0.15)
const GRASS_DRY := Color(0.62, 0.62, 0.22)
const LEAF_DARK := Color(0.09, 0.26, 0.07)
const LEAF_LIGHT := Color(0.42, 0.66, 0.13)
const PINE_DARK := Color(0.05, 0.19, 0.11)
const PINE_LIGHT := Color(0.20, 0.44, 0.20)
const AUTUMN_DARK := Color(0.50, 0.16, 0.04)
const AUTUMN_LIGHT := Color(0.98, 0.60, 0.10)
const BARK := Color(0.36, 0.30, 0.25)
const BARK_DARK := Color(0.22, 0.18, 0.16)
const TIMBER := Color(0.33, 0.22, 0.13)
const TIMBER_DARK := Color(0.21, 0.14, 0.09)
const WOOD := Color(0.52, 0.37, 0.22)
const WOOD_DARK := Color(0.38, 0.26, 0.15)
const ROCK := Color(0.47, 0.44, 0.40)
const ROCK_DARK := Color(0.32, 0.31, 0.32)
const MOSS := Color(0.20, 0.34, 0.10)

const STONE_COLORS := [
	[Color(0.52, 0.49, 0.44), Color(0.37, 0.36, 0.36)],
	[Color(0.62, 0.53, 0.40), Color(0.44, 0.38, 0.31)],
	[Color(0.46, 0.47, 0.50), Color(0.32, 0.33, 0.38)],
]
const PLASTER_COLORS := [
	Color(0.86, 0.80, 0.66), Color(0.84, 0.68, 0.40), Color(0.80, 0.58, 0.52),
	Color(0.62, 0.71, 0.55), Color(0.58, 0.70, 0.76), Color(0.90, 0.88, 0.82),
	Color(0.74, 0.60, 0.74),
]
const ROOF_COLORS := [
	Color(0.26, 0.35, 0.47), Color(0.62, 0.28, 0.16), Color(0.28, 0.42, 0.20),
	Color(0.43, 0.23, 0.42), Color(0.72, 0.50, 0.17), Color(0.13, 0.43, 0.43),
	Color(0.55, 0.13, 0.13),
]
const THATCH_COLORS := [Color(0.74, 0.62, 0.33), Color(0.55, 0.44, 0.22)]
const CAP_COLORS := [
	Color(0.72, 0.12, 0.09), Color(0.46, 0.22, 0.58), Color(0.88, 0.46, 0.09),
	Color(0.10, 0.50, 0.52), Color(0.56, 0.33, 0.16),
]
const GOURD_COLORS := [
	Color(0.88, 0.45, 0.08), Color(0.80, 0.62, 0.16), Color(0.50, 0.60, 0.22),
	Color(0.70, 0.20, 0.10), Color(0.86, 0.74, 0.52),
]
const CLOTH_COLORS := [
	Color(0.62, 0.16, 0.13), Color(0.18, 0.32, 0.55), Color(0.78, 0.60, 0.15),
	Color(0.25, 0.45, 0.20), Color(0.48, 0.24, 0.50), Color(0.80, 0.42, 0.12),
	Color(0.80, 0.77, 0.68), Color(0.16, 0.42, 0.44),
]
const SKIN_COLORS := [Color(0.90, 0.70, 0.55), Color(0.72, 0.50, 0.36), Color(0.45, 0.30, 0.20), Color(0.84, 0.62, 0.48)]

## Texture repeats per metre and roughness for each surface kind.
const SURFACE_DEFAULTS := {
	"stone": [0.4, 0.9], "rock": [0.3, 0.92], "planks": [0.8, 0.75], "shingles": [0.5, 0.8],
	"plaster": [0.33, 0.9], "bark": [0.66, 0.9], "thatch": [0.6, 0.95], "dirt": [0.4, 0.95],
	"ground": [0.3, 0.95], "hide": [1.0, 0.6],
}

static var _materials := {}
static var _glass: Array[ShaderMaterial] = []
static var _ambient_tinted: Array[ShaderMaterial] = []
static var _terrain_textures: Array = [null, null, null]


static func tex(tex_name: String) -> Texture2D:
	return load(TEX_DIR + tex_name + ".png")


static func shader(shader_name: String) -> Shader:
	return load(SHADER_DIR + shader_name + ".gdshader")


# --- Textured surfaces ------------------------------------------------------

## A triplanar surface material. `kind` picks the texture set (see
## SURFACE_DEFAULTS); colour_a/b tint individual bricks, planks or shingles.
## Options: scale, roughness, normal, moss.
static func surface(kind: String, color_a: Color, color_b: Color, opts := {}) -> ShaderMaterial:
	var key := "surface|%s|%s|%s|%s" % [kind, color_a.to_html(), color_b.to_html(), opts]
	if _materials.has(key):
		return _materials[key]
	var defaults: Array = SURFACE_DEFAULTS[kind]
	var m := ShaderMaterial.new()
	m.shader = shader("surface")
	m.set_shader_parameter("detail_tex", tex(kind + "_detail"))
	m.set_shader_parameter("normal_tex", tex(kind + "_normal"))
	m.set_shader_parameter("color_a", color_a)
	m.set_shader_parameter("color_b", color_b)
	m.set_shader_parameter("moss_color", MOSS)
	m.set_shader_parameter("tex_scale", opts.get("scale", defaults[0]))
	m.set_shader_parameter("roughness", opts.get("roughness", defaults[1]))
	m.set_shader_parameter("normal_strength", opts.get("normal", 1.0))
	m.set_shader_parameter("moss", opts.get("moss", 0.0))
	_materials[key] = m
	return m


static func stone(index: int, moss := 0.35) -> ShaderMaterial:
	var pair: Array = STONE_COLORS[index % STONE_COLORS.size()]
	return surface("stone", pair[0], pair[1], {"moss": moss})


static func plaster(color: Color) -> ShaderMaterial:
	return surface("plaster", color, color.darkened(0.16).lerp(Color(0.45, 0.38, 0.3), 0.15))


static func timber() -> ShaderMaterial:
	return surface("planks", TIMBER, TIMBER_DARK, {"scale": 1.6})


static func wood() -> ShaderMaterial:
	return surface("planks", WOOD, WOOD_DARK)


static func roof(color: Color) -> ShaderMaterial:
	var other := Color.from_hsv(fposmod(color.h + 0.04, 1.0), color.s * 0.85, color.v * 0.65)
	return surface("shingles", color, other, {"moss": 0.15})


static func thatch() -> ShaderMaterial:
	return surface("thatch", THATCH_COLORS[0], THATCH_COLORS[1])


static func bark() -> ShaderMaterial:
	return surface("bark", BARK, BARK_DARK, {"moss": 0.2})


static func rock() -> ShaderMaterial:
	return surface("rock", ROCK, ROCK_DARK, {"moss": 0.6})


## Plain cloth / skin: the plaster texture at a fine scale, coloured per
## object with the `tint` instance parameter.
static func cloth() -> ShaderMaterial:
	return surface("plaster", Color(1, 1, 1), Color(0.8, 0.8, 0.8), {"scale": 2.5, "normal": 0.5, "roughness": 0.95})


## Window panes. They light up when Art.set_window_glow() is raised at dusk.
static func glass() -> ShaderMaterial:
	var key := "glass"
	if _materials.has(key):
		return _materials[key]
	var m := surface("plaster", Color(0.10, 0.14, 0.20), Color(0.16, 0.20, 0.26), {"scale": 1.0, "roughness": 0.25, "normal": 0.3, "glass": true})
	m.set_shader_parameter("glow_color", Color(1.0, 0.62, 0.22))
	_glass.append(m)
	_materials[key] = m
	return m


static func set_window_glow(energy: float) -> void:
	for m in _glass:
		m.set_shader_parameter("glow_energy", energy)


# --- Vegetation -------------------------------------------------------------

static func foliage(dark: Color, light: Color) -> ShaderMaterial:
	var key := "foliage|%s|%s" % [dark.to_html(), light.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = shader("foliage")
	m.set_shader_parameter("leaf_tex", tex("leaves"))
	m.set_shader_parameter("color_dark", dark)
	m.set_shader_parameter("color_light", light)
	_materials[key] = m
	return m


static func grass() -> ShaderMaterial:
	if _materials.has("grass"):
		return _materials["grass"]
	var m := ShaderMaterial.new()
	m.shader = shader("grass")
	m.set_shader_parameter("noise_tex", tex("noise"))
	m.set_shader_parameter("color_root", GRASS_ROOT)
	m.set_shader_parameter("color_tip", GRASS_TIP)
	m.set_shader_parameter("color_dry", GRASS_DRY)
	_materials["grass"] = m
	_apply_terrain_textures(m)
	return m


# --- Terrain and water ------------------------------------------------------

static func terrain() -> ShaderMaterial:
	if _materials.has("terrain"):
		return _materials["terrain"]
	var m := ShaderMaterial.new()
	m.shader = shader("terrain")
	m.set_shader_parameter("noise_tex", tex("noise"))
	for layer in ["ground", "dirt", "rock"]:
		m.set_shader_parameter(layer + "_detail", tex(layer + "_detail"))
		m.set_shader_parameter(layer + "_normal", tex(layer + "_normal"))
	# The ground under the blades is a blend of the grass root and tip colours.
	m.set_shader_parameter("grass_a", GRASS_ROOT.lerp(GRASS_TIP, 0.25))
	m.set_shader_parameter("grass_b", GRASS_ROOT.lerp(GRASS_TIP, 0.7))
	m.set_shader_parameter("grass_dry", GRASS_DRY.darkened(0.2))
	m.set_shader_parameter("rock_a", ROCK)
	m.set_shader_parameter("rock_b", ROCK_DARK)
	_materials["terrain"] = m
	_apply_terrain_textures(m)
	return m


static func water() -> ShaderMaterial:
	if _materials.has("water"):
		return _materials["water"]
	var m := ShaderMaterial.new()
	m.shader = shader("water")
	m.set_shader_parameter("noise_tex", tex("noise"))
	_materials["water"] = m
	_apply_terrain_textures(m)
	return m


## Called by Terrain whenever it (re)creates its data textures, so the
## terrain, grass and water shaders all read the same world.
static func bind_terrain(height: Texture2D, scorch: Texture2D, mask: Texture2D) -> void:
	_terrain_textures = [height, scorch, mask]
	for key in ["terrain", "grass", "water"]:
		if _materials.has(key):
			_apply_terrain_textures(_materials[key])


static func _apply_terrain_textures(m: ShaderMaterial) -> void:
	m.set_shader_parameter("height_tex", _terrain_textures[0])
	m.set_shader_parameter("scorch_tex", _terrain_textures[1])
	m.set_shader_parameter("mask_tex", _terrain_textures[2])


# --- Particles --------------------------------------------------------------

## kind: "flame", "ember", "smoke" or "dust".
static func particle(kind: String) -> ShaderMaterial:
	var key := "particle|" + kind
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = shader("particle")
	match kind:
		"flame":
			m.set_shader_parameter("sprite_tex", tex("flame"))
			m.set_shader_parameter("color_hot", Color(1.0, 0.86, 0.32))
			m.set_shader_parameter("color_cool", Color(1.0, 0.27, 0.03))
			m.set_shader_parameter("glow", 2.6)
		"ember":
			m.set_shader_parameter("sprite_tex", tex("flame"))
			m.set_shader_parameter("color_hot", Color(1.0, 0.8, 0.3))
			m.set_shader_parameter("color_cool", Color(1.0, 0.4, 0.05))
			m.set_shader_parameter("glow", 5.0)
		"smoke":
			m.set_shader_parameter("sprite_tex", tex("smoke"))
			m.set_shader_parameter("use_ramp", 0.0)
			_ambient_tinted.append(m)
		"dust":
			m.set_shader_parameter("sprite_tex", tex("smoke"))
			m.set_shader_parameter("use_ramp", 0.0)
			_ambient_tinted.append(m)
	_materials[key] = m
	return m


## Smoke and dust are unlit sprites, so the Atmosphere tells them how bright
## the world currently is.
static func set_particle_ambient(color: Color) -> void:
	for m in _ambient_tinted:
		m.set_shader_parameter("ambient", color)
