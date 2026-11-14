class_name Terrain
extends Node3D
## Editable heightmap terrain, shaped as an island floating in the sky.
##
## Heights live in one flat array of (SIZE + 1)^2 samples spaced 1 m apart and
## centred on the origin, so the world spans x/z in [-HALF, HALF]. The visible
## mesh is split into chunks, and editing only rebuilds the chunks it touches.
##
## `island` marks which samples are land. Everything else is the void: its
## height is VOID_HEIGHT and it is not drawn. Where the land ends, a rock
## skirt hangs down from the edge, and the rocky underside hangs below that.
## The land can be grown with paint_land() (map editor).
##
## Water is a layer of its own: `water` holds the surface height of every
## sample that is under water (NO_WATER where it is dry), so lakes can sit
## at any height. After the ground is reshaped, water flows into connected
## ground lower than its surface (settle), and wherever water reaches the
## edge of the island it pours over as a waterfall.
##
## Painted layers: `bare` (worn dirt), `scorch` (burn marks), `sand` and
## `rock` (stone ground, e.g. inside craters). They and the water depth are
## kept in textures that the terrain, grass and water shaders read (see
## Art.bind_terrain).
##
## The map size is chosen per world: call Terrain.configure() before the
## terrain (and anything that reads its size) is added to the tree. A world
## comes either from a seed (generate) or from a saved map (load_map).

signal changed(center: Vector3, radius: float)

enum Brush { RAISE, LOWER, FLATTEN, SMOOTH }

## Map sizes the player can choose, in metres (multiples of CHUNK).
const SIZES := [192, 384, 768]
const SIZE_NAMES := ["Small", "Medium", "Large"]
const DEFAULT_SIZE := 384
## Limits for maps grown in the editor.
const MIN_SIZE := 128
const MAX_SIZE := 1024
## Land must stay this many samples away from the edge of the map square.
const EDGE_MARGIN := 3
const CHUNK := 32
const WATER_LEVEL := 0.0
const MIN_HEIGHT := -10.0
const MAX_HEIGHT := 60.0
const VOID_HEIGHT := -60.0
const NO_WATER := -1000.0
## How far the rock skirt hangs below the edge of the land.
const SKIRT_DEPTH := 10.0
## Generated beaches fade out at this height.
const BEACH_HEIGHT := 1.1
## Water deeper than this counts as water for walking and building.
const WET_DEPTH := 0.05

# Per-world size values, set by configure(). Upper case because the rest of
# the game treats them as constants once the world exists.
static var SIZE := 384
static var HALF := 192.0
static var N := 385
static var CHUNKS := 12
## Radius of a freshly generated island.
static var ISLAND_RADIUS := 174.0
## SIZE relative to the original 256 m map, for scaling placement rules.
static var SCALE := 1.5

var world_seed := 0
var heights := PackedFloat32Array()
## 0..1 burn darkness per sample, painted by fire and explosions.
var scorch := PackedFloat32Array()
## 0..1 bare ground per sample (village squares, roads, under buildings).
var bare := PackedFloat32Array()
## 0..1 sand per sample (beaches, the editor's sand brush).
var sand := PackedFloat32Array()
## 0..1 stone ground per sample (craters).
var rock := PackedFloat32Array()
## Water surface height per sample, or NO_WATER.
var water := PackedFloat32Array()
## 1 for land, 0 for the void.
var island := PackedByteArray()
## Flat areas picked for villages: {"pos": Vector2, "radius": float, "height": float}.
var village_sites: Array[Dictionary] = []
## Centre lines of the rivers, from the spring out to the island's edge.
var rivers: Array[PackedVector2Array] = []

var grass: Grass

var _chunks: Array[MeshInstance3D] = []
var _water_chunks: Array[MeshInstance3D] = []
var _dirty := {}
var _water_dirty := {}
var _collision_dirty := false
var _collision_timer := 0.0
var _shape := HeightMapShape3D.new()
var _height_tex: ImageTexture
var _scorch_tex: ImageTexture
var _bare_tex: ImageTexture
var _ground_tex: ImageTexture
## sand, rock, water depth, unused: one RGBA float pixel per sample.
var _ground_px := PackedFloat32Array()
var _height_tex_dirty := false
var _scorch_tex_dirty := false
var _bare_tex_dirty := false
var _ground_tex_dirty := false
var _settle_rect := Rect2i()
var _settle_pending := false
var _settle_timer := 0.0
var _shape_dirty := false
var _falls_dirty := false
var _extras_timer := 0.0
var _edge_noise := FastNoiseLite.new()
var _underside: MeshInstance3D
var _falls: Node3D


func _ready() -> void:
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			add_child(mi)
			_chunks.append(mi)
			var wi := MeshInstance3D.new()
			wi.name = "Water_%d_%d" % [cx, cz]
			wi.material_override = Art.water()
			wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wi)
			_water_chunks.append(wi)
	grass = Grass.new()
	add_child(grass)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	if _settle_pending:
		_settle_timer -= delta
		if _settle_timer <= 0.0:
			_settle_pending = false
			_settle(_settle_rect)
	if not _dirty.is_empty():
		_rebuild_dirty_chunks()
	if not _water_dirty.is_empty():
		for key in _water_dirty.keys():
			var idx: int = key
			_build_water_chunk(idx % CHUNKS, floori(idx / float(CHUNKS)))
		_water_dirty.clear()
	if _collision_dirty:
		_collision_timer -= delta
		if _collision_timer <= 0.0:
			_collision_timer = 0.2
			_collision_dirty = false
			_shape.map_data = heights
	if _height_tex_dirty:
		_height_tex_dirty = false
		_height_tex.update(_to_image(heights))
	if _scorch_tex_dirty:
		_scorch_tex_dirty = false
		_scorch_tex.update(_to_image(scorch))
	if _bare_tex_dirty:
		_bare_tex_dirty = false
		_bare_tex.update(_to_image(bare))
	if _ground_tex_dirty:
		_ground_tex_dirty = false
		_ground_tex.update(_ground_image())
	if _shape_dirty or _falls_dirty:
		_extras_timer -= delta
		if _extras_timer <= 0.0:
			if _shape_dirty:
				_shape_dirty = false
				_build_underside()
			if _falls_dirty:
				_falls_dirty = false
				_build_falls()


# --- Generation -------------------------------------------------------------

## Sets the size of the next world. Must run before the terrain is added.
static func configure(size: int) -> void:
	if not valid_size(size):
		size = DEFAULT_SIZE
	SIZE = size
	HALF = size * 0.5
	N = size + 1
	CHUNKS = floori(size / float(CHUNK))
	SCALE = size / 256.0
	ISLAND_RADIUS = 116.0 * SCALE


static func valid_size(size: int) -> bool:
	return size % CHUNK == 0 and size >= MIN_SIZE and size <= MAX_SIZE


## Builds a world from a seed. Without villages (the map editor) no village
## sites are picked, so the land is left as nature made it.
func generate(seed_value: int, with_villages := true) -> void:
	world_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var base := FastNoiseLite.new()
	base.seed = world_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.012
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = 5

	var mask := FastNoiseLite.new()
	mask.seed = world_seed + 17
	mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mask.frequency = 0.007
	mask.fractal_octaves = 2

	_edge_noise.seed = world_seed + 3
	_edge_noise.frequency = 0.55

	heights.resize(N * N)
	scorch.resize(N * N)
	scorch.fill(0.0)
	bare.resize(N * N)
	bare.fill(0.0)
	for j in N:
		for i in N:
			heights[j * N + i] = _natural_height(i - HALF, j - HALF, base, mask)

	_carve_rivers(rng)
	village_sites.clear()
	if with_villages:
		_pick_village_sites(rng)
		_flatten_village_sites()
		_paint_village_ground(world_seed)
	_cut_out_island()
	_init_layers()
	_finish()


## Restores a world saved by export_map() (see MapData). Version 1 maps
## had no land, water or paint layers, so those are rebuilt from heights.
func load_map(data: Dictionary) -> void:
	world_seed = data.get("seed", 0)
	_edge_noise.seed = world_seed + 3
	_edge_noise.frequency = 0.55
	heights = (data.heights as PackedFloat32Array).duplicate()
	bare = (data.bare as PackedFloat32Array).duplicate()
	scorch.resize(N * N)
	scorch.fill(0.0)
	rivers.clear()
	for path in data.rivers:
		rivers.append(path)
	village_sites.clear()
	if data.has("island"):
		island = (data.island as PackedByteArray).duplicate()
		water = (data.water as PackedFloat32Array).duplicate()
		sand = (data.sand as PackedFloat32Array).duplicate()
		rock = (data.rock as PackedFloat32Array).duplicate()
	else:
		island.resize(N * N)
		for k in N * N:
			island[k] = 1 if heights[k] > VOID_HEIGHT + 1.0 else 0
		_init_layers()
	_finish()


## The parts of the terrain a map file needs to rebuild it.
func export_map() -> Dictionary:
	return {"seed": world_seed, "size": SIZE, "heights": heights.duplicate(), "bare": bare.duplicate(),
		"rivers": rivers.duplicate(), "island": island.duplicate(), "water": water.duplicate(),
		"sand": sand.duplicate(), "rock": rock.duplicate()}


## Water in every hollow below sea level, and beaches on low ground.
func _init_layers() -> void:
	water.resize(N * N)
	sand.resize(N * N)
	rock.resize(N * N)
	rock.fill(0.0)
	for k in N * N:
		var h := heights[k]
		if island[k] == 1:
			water[k] = WATER_LEVEL if h < WATER_LEVEL - 0.02 else NO_WATER
			sand[k] = 1.0 - smoothstep(0.35, BEACH_HEIGHT, h)
		else:
			water[k] = NO_WATER
			sand[k] = 0.0


func _finish() -> void:
	_ground_px.resize(N * N * 4)
	_refresh_ground(0, 0, SIZE, SIZE)
	_height_tex = ImageTexture.create_from_image(_to_image(heights))
	_scorch_tex = ImageTexture.create_from_image(_to_image(scorch))
	_bare_tex = ImageTexture.create_from_image(_to_image(bare))
	_ground_tex = ImageTexture.create_from_image(_ground_image())
	_ground_tex_dirty = false
	Art.bind_terrain(_height_tex, _scorch_tex, _bare_tex, _ground_tex, N)

	_shape.map_width = N
	_shape.map_depth = N
	_shape.map_data = heights
	for idx in _chunks.size():
		_dirty[idx] = true
	_rebuild_dirty_chunks()
	for idx in _chunks.size():
		_build_water_chunk(idx % CHUNKS, floori(idx / float(CHUNKS)))
	_water_dirty.clear()
	_build_underside()
	_build_falls()


## Distance from the centre to a generated island's edge in the given direction.
func edge_radius(angle: float) -> float:
	return ISLAND_RADIUS * (0.86 + 0.14 * _edge_noise.get_noise_2d(cos(angle), sin(angle)))


func _carve_rivers(rng: RandomNumberGenerator) -> void:
	rivers.clear()
	var spring := Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-18.0, 18.0))
	var first := rng.randf() * TAU
	for angle in [first, first + PI + rng.randf_range(-0.7, 0.7)]:
		var dir := Vector2(cos(angle), sin(angle))
		var side := Vector2(-dir.y, dir.x)
		var length := edge_radius(angle) + 6.0 - spring.dot(dir)
		var phase := rng.randf() * TAU
		var path := PackedVector2Array()
		var steps := roundi(90 * maxf(SCALE, 1.0))
		for k in steps:
			var t := k / float(steps - 1)
			path.append(spring + dir * length * t + side * sin(t * 7.5 + phase) * 13.0 * sin(t * PI))
		rivers.append(path)
		for p in path:
			_stamp_river(p, 2.6, 8.5)
	# A pond where the rivers rise.
	_stamp_river(spring, 7.0, 14.0)


func _stamp_river(p: Vector2, bed: float, bank: float) -> void:
	var i0 := clampi(floori(p.x + HALF - bank), 0, SIZE)
	var i1 := clampi(ceili(p.x + HALF + bank), 0, SIZE)
	var j0 := clampi(floori(p.y + HALF - bank), 0, SIZE)
	var j1 := clampi(ceili(p.y + HALF + bank), 0, SIZE)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := Vector2(i - HALF, j - HALF).distance_to(p)
			if d < bank:
				var k := j * N + i
				heights[k] = minf(heights[k], lerpf(-1.5, maxf(heights[k], 1.2), smoothstep(bed, bank, d)))


func _river_distance(p: Vector2) -> float:
	var best := 1000.0
	for path in rivers:
		for q in path:
			best = minf(best, p.distance_to(q))
	return best


## Drops everything outside the generated island's outline into the void.
func _cut_out_island() -> void:
	island.resize(N * N)
	var limit := HALF - EDGE_MARGIN
	for j in N:
		for i in N:
			var p := Vector2(i - HALF, j - HALF)
			var inside := p.length() < edge_radius(p.angle()) and absf(p.x) < limit and absf(p.y) < limit
			island[j * N + i] = 1 if inside else 0
			if not inside:
				heights[j * N + i] = VOID_HEIGHT


func _natural_height(x: float, z: float, base: FastNoiseLite, mask: FastNoiseLite) -> float:
	var n := base.get_noise_2d(x, z)
	# The mask decides where the land is hilly and where it stays flat.
	var hilliness := smoothstep(0.45, 0.72, (mask.get_noise_2d(x, z) + 1.0) * 0.5)
	var plains := 1.8 + n * 4.0
	var hills := 5.0 + pow((n + 1.0) * 0.5, 1.5) * 36.0
	var h := lerpf(plains, hills, hilliness)
	# Level the land out towards the rim so the edge of the island is walkable.
	var edge := Vector2(x, z).length() / ISLAND_RADIUS
	return lerpf(h, 2.4 + n * 1.5, smoothstep(0.62, 0.95, edge))


func _pick_village_sites(rng: RandomNumberGenerator) -> void:
	village_sites.clear()
	var wanted := clampi(roundi(rng.randi_range(4, 5) * SCALE), 2, 8)
	var reach := 74.0 * SCALE
	# Try strict rules first, then relax them if the map is very hilly.
	for max_relief in [5.0, 9.0, 16.0, 1000.0]:
		var attempts := 0
		while village_sites.size() < wanted and attempts < 400:
			attempts += 1
			var p := Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
			var too_close := p.length() > reach - 2.0
			var r := rng.randf_range(15.0, 21.0)
			if _river_distance(p) < r + 5.0:
				continue
			for s in village_sites:
				if p.distance_to(s.pos) < 58.0 * minf(SCALE, 1.0):
					too_close = true
					break
			if too_close:
				continue
			var h := get_height(p.x, p.y)
			if h < 1.0 or h > 14.0 or _relief(p, r) > max_relief:
				continue
			village_sites.append({"pos": p, "radius": r, "height": h})
		if village_sites.size() >= wanted:
			break


func _relief(center: Vector2, radius: float) -> float:
	var lo := get_height(center.x, center.y)
	var hi := lo
	for k in 12:
		var a := TAU * k / 12.0
		var h := get_height(center.x + cos(a) * radius, center.y + sin(a) * radius)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo


func _flatten_village_sites() -> void:
	for s in village_sites:
		var c: Vector2 = s.pos
		var r: float = s.radius
		var target: float = s.height
		var reach := r + 14.0
		var i0 := clampi(floori(c.x + HALF - reach), 0, SIZE)
		var i1 := clampi(ceili(c.x + HALF + reach), 0, SIZE)
		var j0 := clampi(floori(c.y + HALF - reach), 0, SIZE)
		var j1 := clampi(ceili(c.y + HALF + reach), 0, SIZE)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var d := Vector2(i - HALF, j - HALF).distance_to(c)
				if d >= reach:
					continue
				var t := 1.0 - smoothstep(r, reach, d)
				var k := j * N + i
				heights[k] = lerpf(heights[k], target, t)


## Marks worn dirt in the village squares and along roads between villages.
## Only the samples near a village or road are visited, so big maps stay fast.
func _paint_village_ground(seed_value: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + 5
	noise.frequency = 0.09
	for s in village_sites:
		var c: Vector2 = s.pos
		var r: float = s.radius
		_paint_area(c - Vector2(r, r), c + Vector2(r, r), func(p: Vector2, wobble: float) -> float:
			var d := p.distance_to(c)
			return (1.0 - smoothstep(r * 0.25, r * 0.8, d)) * (0.55 + 0.5 * wobble) if d < r else 0.0, noise)
	# Each village gets a road to the nearest village placed before it.
	for k in range(1, village_sites.size()):
		var from: Vector2 = village_sites[k].pos
		var best: Vector2 = village_sites[0].pos
		for m in k:
			var other: Vector2 = village_sites[m].pos
			if from.distance_to(other) < from.distance_to(best):
				best = other
		var lo := Vector2(minf(from.x, best.x), minf(from.y, best.y)) - Vector2(4, 4)
		var hi := Vector2(maxf(from.x, best.x), maxf(from.y, best.y)) + Vector2(4, 4)
		_paint_area(lo, hi, func(p: Vector2, wobble: float) -> float:
			var d := _segment_distance(p, from, best) + wobble * 2.5
			return (1.0 - smoothstep(0.8, 2.6, d)) * 0.75 if d < 3.0 else 0.0, noise)


func _paint_area(lo: Vector2, hi: Vector2, value: Callable, noise: FastNoiseLite) -> void:
	var i0 := clampi(floori(lo.x + HALF), 0, SIZE)
	var i1 := clampi(ceili(hi.x + HALF), 0, SIZE)
	var j0 := clampi(floori(lo.y + HALF), 0, SIZE)
	var j1 := clampi(ceili(hi.y + HALF), 0, SIZE)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(i - HALF, j - HALF)
			var v: float = value.call(p, noise.get_noise_2d(p.x, p.y))
			var k := j * N + i
			bare[k] = clampf(maxf(bare[k], v), 0.0, 1.0)


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _to_image(data: PackedFloat32Array) -> Image:
	return Image.create_from_data(N, N, false, Image.FORMAT_RF, data.to_byte_array())


func _ground_image() -> Image:
	return Image.create_from_data(N, N, false, Image.FORMAT_RGBAF, _ground_px.to_byte_array())


## Copies sand, rock and water depth into the ground texture data.
func _refresh_ground(i0: int, j0: int, i1: int, j1: int) -> void:
	i0 = clampi(i0, 0, SIZE)
	i1 = clampi(i1, 0, SIZE)
	j0 = clampi(j0, 0, SIZE)
	j1 = clampi(j1, 0, SIZE)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * N + i
			var w := water[k]
			_ground_px[k * 4] = sand[k]
			_ground_px[k * 4 + 1] = rock[k]
			_ground_px[k * 4 + 2] = maxf(w - heights[k], 0.0) if w != NO_WATER else 0.0
	_ground_tex_dirty = true


# --- Queries ----------------------------------------------------------------

## Height of the ground at world x/z, matching the rendered triangles.
func get_height(x: float, z: float) -> float:
	var fx := clampf(x + HALF, 0.0, SIZE - 0.001)
	var fz := clampf(z + HALF, 0.0, SIZE - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * N + i]
	var h10 := heights[j * N + i + 1]
	var h01 := heights[(j + 1) * N + i]
	var h11 := heights[(j + 1) * N + i + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func get_normal(x: float, z: float) -> Vector3:
	var hl := get_height(x - 1.0, z)
	var hr := get_height(x + 1.0, z)
	var hd := get_height(x, z - 1.0)
	var hu := get_height(x, z + 1.0)
	return Vector3(hl - hr, 2.0, hd - hu).normalized()


## True if the point is on the island, at least 2 m from the edge.
func is_inside(x: float, z: float) -> bool:
	return _land(x, z) and _land(x + 2.0, z) and _land(x - 2.0, z) and _land(x, z + 2.0) and _land(x, z - 2.0)


func _land(x: float, z: float) -> bool:
	var i := roundi(x + HALF)
	var j := roundi(z + HALF)
	if i < 0 or j < 0 or i > SIZE or j > SIZE:
		return false
	return island[j * N + i] == 1


## The water surface height at x/z, or NO_WATER.
func water_level_at(x: float, z: float) -> float:
	var i := clampi(roundi(x + HALF), 0, SIZE)
	var j := clampi(roundi(z + HALF), 0, SIZE)
	return water[j * N + i]


## How deep the water is at x/z (0 on dry land).
func water_depth(x: float, z: float) -> float:
	var level := water_level_at(x, z)
	if level == NO_WATER:
		return 0.0
	return maxf(level - get_height(x, z), 0.0)


## True on the island where it is not under water.
func is_dry(x: float, z: float) -> bool:
	return is_inside(x, z) and water_depth(x, z) < WET_DEPTH


## The top of the ground or of the water, whichever is higher.
func surface_height(x: float, z: float) -> float:
	return maxf(get_height(x, z), water_level_at(x, z))


func average_height(center: Vector3, radius: float) -> float:
	var total := get_height(center.x, center.z)
	var count := 1
	for k in 16:
		var a := TAU * k / 16.0
		for r in [radius * 0.5, radius]:
			total += get_height(center.x + cos(a) * r, center.z + sin(a) * r)
			count += 1
	return total / count


## Marches a ray against the heightmap. Returns the hit point or null.
func raycast(origin: Vector3, dir: Vector3, max_dist := 4000.0) -> Variant:
	var t := 0.0
	var prev_t := 0.0
	while t < max_dist:
		var p := origin + dir * t
		var step := 2.0
		if absf(p.x) <= HALF and absf(p.z) <= HALF:
			var gap := p.y - get_height(p.x, p.z)
			if gap <= 0.0:
				var a := prev_t
				var b := t
				for k in 14:
					var m := (a + b) * 0.5
					var q := origin + dir * m
					if q.y <= get_height(q.x, q.z):
						b = m
					else:
						a = m
				return origin + dir * b
			step = clampf(gap * 0.4, 0.25, 6.0)
		prev_t = t
		t += step
	return null


# --- Editing ----------------------------------------------------------------

## Changes the terrain around `center`. `hardness` is the fraction of the
## radius that gets the full effect before it fades out.
func apply_brush(center: Vector3, radius: float, mode: Brush, amount: float, target_height := 0.0, hardness := 0.4) -> void:
	var r := _rect(center, radius)
	var source := PackedFloat32Array()
	if mode == Brush.SMOOTH:
		source = heights.duplicate()
	var touched_edge := false
	for j in range(r.position.y, r.end.y + 1):
		for i in range(r.position.x, r.end.x + 1):
			var d := Vector2(i - HALF - center.x, j - HALF - center.z).length()
			var k := j * N + i
			if d > radius or island[k] == 0:
				continue
			if not touched_edge and _on_edge(i, j):
				touched_edge = true
			var w := 1.0 - smoothstep(radius * hardness, radius, d)
			var h := heights[k]
			match mode:
				Brush.RAISE:
					h += amount * w
				Brush.LOWER:
					h -= amount * w
				Brush.FLATTEN:
					h = lerpf(h, target_height, clampf(amount * w, 0.0, 1.0))
				Brush.SMOOTH:
					var avg := (_land_sample(source, i - 1, j, h) + _land_sample(source, i + 1, j, h)
						+ _land_sample(source, i, j - 1, h) + _land_sample(source, i, j + 1, h) + h) / 5.0
					h = lerpf(h, avg, clampf(amount * w, 0.0, 1.0))
			heights[k] = clampf(h, MIN_HEIGHT, MAX_HEIGHT)
	if touched_edge:
		# The underside hangs from the edge, so it follows the new edge heights.
		_shape_dirty = true
		_extras_timer = 0.4
	_heights_changed(r, center, radius)


func _on_edge(i: int, j: int) -> bool:
	return not (_in(i + 1, j) and _in(i - 1, j) and _in(i, j + 1) and _in(i, j - 1))


## One frame of a sculpt tool held down at `pos` (dev menu and map editor).
func sculpt(mode: Brush, pos: Vector3, radius: float, delta: float, flatten_height: float) -> void:
	match mode:
		Brush.RAISE, Brush.LOWER:
			apply_brush(pos, radius, mode, 8.0 * delta)
		Brush.FLATTEN:
			apply_brush(pos, radius, mode, 6.0 * delta, flatten_height)
		Brush.SMOOTH:
			apply_brush(pos, radius, mode, 6.0 * delta)


## Darkens the ground (burn marks) and burns the grass away.
func add_scorch(center: Vector3, radius: float, amount: float) -> void:
	_paint(scorch, center, radius, amount)
	_scorch_tex_dirty = true


## Wears the grass away to bare dirt (around buildings, on paths).
func add_bare(center: Vector3, radius: float, amount: float) -> void:
	_paint(bare, center, radius, amount)
	_bare_tex_dirty = true


## Turns the ground to bare stone (craters).
func add_rock(center: Vector3, radius: float, amount: float) -> void:
	_paint(rock, center, radius, amount)
	var r := _rect(center, radius)
	_refresh_ground(r.position.x, r.position.y, r.end.x, r.end.y)


## Editor brush: sand. Also clears painted stone.
func paint_sand(center: Vector3, radius: float, amount: float) -> void:
	_paint(sand, center, radius, amount)
	_paint(rock, center, radius, -amount)
	var r := _rect(center, radius)
	_refresh_ground(r.position.x, r.position.y, r.end.x, r.end.y)


## Editor brush: grass. Clears sand, stone, dirt and burn marks, and fills
## in water so the ground there becomes a grassy bank.
func paint_grass(center: Vector3, radius: float, amount: float) -> void:
	for data in [sand, rock, bare, scorch]:
		_paint(data, center, radius, -amount)
	_bare_tex_dirty = true
	_scorch_tex_dirty = true
	var r := _rect(center, radius)
	var filled := false
	for j in range(r.position.y, r.end.y + 1):
		for i in range(r.position.x, r.end.x + 1):
			var k := j * N + i
			if water[k] == NO_WATER or Vector2(i - HALF - center.x, j - HALF - center.z).length() > radius * 0.8:
				continue
			heights[k] = maxf(heights[k], water[k] + 0.15)
			water[k] = NO_WATER
			filled = true
	if filled:
		_mark_water_dirty(r)
		_falls_dirty = true
		_heights_changed(r, center, radius)
	_refresh_ground(r.position.x, r.position.y, r.end.x, r.end.y)


## Editor brush: water with its surface at `level`. The ground inside the
## brush is flattened into a shallow basin, and a bank just above the
## surface is raised round it where the land is lower, so the water stays
## put: a flat pond, even up on a hill, with slopes down from its bank.
func paint_water(center: Vector3, radius: float, level: float) -> void:
	var bank := radius + 2.5
	var r := _rect(center, bank)
	for j in range(r.position.y, r.end.y + 1):
		for i in range(r.position.x, r.end.x + 1):
			var k := j * N + i
			if island[k] == 0:
				continue
			var d := Vector2(i - HALF - center.x, j - HALF - center.z).length()
			if d < radius:
				heights[k] = level - 0.6
				water[k] = maxf(water[k], level)
			elif d < bank and water[k] == NO_WATER:
				heights[k] = maxf(heights[k], level + 0.15)
	_mark_water_dirty(r)
	_heights_changed(r, center, bank)


## Editor brush: grows the island. New land is raised to `height`.
## Returns true if the brush reached the edge of the map square (the land
## stops EDGE_MARGIN samples short of it).
func paint_land(center: Vector3, radius: float, height: float) -> bool:
	var r := _rect(center, radius)
	var hit_edge := false
	var grew := false
	for j in range(r.position.y, r.end.y + 1):
		for i in range(r.position.x, r.end.x + 1):
			if Vector2(i - HALF - center.x, j - HALF - center.z).length() > radius:
				continue
			if i < EDGE_MARGIN or j < EDGE_MARGIN or i > SIZE - EDGE_MARGIN or j > SIZE - EDGE_MARGIN:
				hit_edge = true
				continue
			var k := j * N + i
			if island[k] == 1:
				continue
			island[k] = 1
			heights[k] = height
			water[k] = NO_WATER
			sand[k] = 0.0
			rock[k] = 0.0
			grew = true
	if grew:
		_shape_dirty = true
		_falls_dirty = true
		_extras_timer = 0.4
		_heights_changed(r, center, radius)
	return hit_edge


func _rect(center: Vector3, radius: float) -> Rect2i:
	var i0 := clampi(floori(center.x + HALF - radius), 0, SIZE)
	var i1 := clampi(ceili(center.x + HALF + radius), 0, SIZE)
	var j0 := clampi(floori(center.z + HALF - radius), 0, SIZE)
	var j1 := clampi(ceili(center.z + HALF + radius), 0, SIZE)
	return Rect2i(i0, j0, i1 - i0, j1 - j0)


## Everything that follows a change of ground height inside `r`.
func _heights_changed(r: Rect2i, center: Vector3, radius: float) -> void:
	_mark_dirty(r.position.x, r.position.y, r.end.x, r.end.y)
	_collision_dirty = true
	_height_tex_dirty = true
	_refresh_ground(r.position.x, r.position.y, r.end.x, r.end.y)
	_queue_settle(r)
	changed.emit(center, radius)


func _paint(data: PackedFloat32Array, center: Vector3, radius: float, amount: float) -> void:
	var r := _rect(center, radius)
	for j in range(r.position.y, r.end.y + 1):
		for i in range(r.position.x, r.end.x + 1):
			var d := Vector2(i - HALF - center.x, j - HALF - center.z).length()
			if d > radius:
				continue
			var k := j * N + i
			var w := 1.0 - smoothstep(radius * 0.3, radius, d)
			data[k] = clampf(data[k] + amount * w, 0.0, 1.0)


## A neighbour's height for smoothing; the void counts as level ground.
func _land_sample(source: PackedFloat32Array, i: int, j: int, fallback: float) -> float:
	var k := clampi(j, 0, SIZE) * N + clampi(i, 0, SIZE)
	return source[k] if island[k] == 1 else fallback


func _mark_dirty(i0: int, j0: int, i1: int, j1: int) -> void:
	# Normals and skirts use neighbouring samples, so widen the range a little.
	var cx0 := clampi(floori((i0 - 2) / float(CHUNK)), 0, CHUNKS - 1)
	var cx1 := clampi(floori((i1 + 2) / float(CHUNK)), 0, CHUNKS - 1)
	var cz0 := clampi(floori((j0 - 2) / float(CHUNK)), 0, CHUNKS - 1)
	var cz1 := clampi(floori((j1 + 2) / float(CHUNK)), 0, CHUNKS - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			_dirty[cz * CHUNKS + cx] = true


func _mark_water_dirty(r: Rect2i) -> void:
	var cx0 := clampi(floori((r.position.x - 1) / float(CHUNK)), 0, CHUNKS - 1)
	var cx1 := clampi(floori((r.end.x + 1) / float(CHUNK)), 0, CHUNKS - 1)
	var cz0 := clampi(floori((r.position.y - 1) / float(CHUNK)), 0, CHUNKS - 1)
	var cz1 := clampi(floori((r.end.y + 1) / float(CHUNK)), 0, CHUNKS - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			_water_dirty[cz * CHUNKS + cx] = true


# --- Water flow -----------------------------------------------------------------

func _queue_settle(r: Rect2i) -> void:
	_settle_rect = _settle_rect.merge(r) if _settle_pending else r
	if not _settle_pending:
		_settle_pending = true
		_settle_timer = 0.12


## Lets the water find its level after the ground changed inside `r`:
## ground raised above the surface dries out, and water spreads into every
## connected sample whose ground is below its surface. Water that reaches
## the edge of the island pours off it as a waterfall.
func _settle(r: Rect2i) -> void:
	r = r.grow(1).intersection(Rect2i(0, 0, SIZE, SIZE))
	var changed_rect := Rect2i()
	var any := false
	var queue := PackedInt32Array()
	for j in range(r.position.y, r.end.y + 1):
		for i in range(r.position.x, r.end.x + 1):
			var k := j * N + i
			if water[k] == NO_WATER:
				continue
			if heights[k] >= water[k] - 0.02 or island[k] == 0:
				water[k] = NO_WATER
				changed_rect = changed_rect.merge(Rect2i(i, j, 0, 0)) if any else Rect2i(i, j, 0, 0)
				any = true
			else:
				queue.append(k)
	var head := 0
	var limit := 400000
	while head < queue.size() and head < limit:
		var k := queue[head]
		head += 1
		var level := water[k]
		var i := k % N
		var j := k / N
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + step.x
			var nj := j + step.y
			if ni < 0 or nj < 0 or ni > SIZE or nj > SIZE:
				continue
			var nk := nj * N + ni
			if island[nk] == 0 or heights[nk] >= level - 0.02:
				continue
			if water[nk] != NO_WATER and water[nk] >= level - 0.02:
				continue
			water[nk] = level
			queue.append(nk)
			changed_rect = changed_rect.merge(Rect2i(ni, nj, 0, 0)) if any else Rect2i(ni, nj, 0, 0)
			any = true
	if any:
		_mark_water_dirty(changed_rect)
		_refresh_ground(changed_rect.position.x, changed_rect.position.y, changed_rect.end.x, changed_rect.end.y)
		_falls_dirty = true
		if not _shape_dirty:
			_extras_timer = 0.3


# --- Mesh building ----------------------------------------------------------

func _rebuild_dirty_chunks() -> void:
	for key in _dirty.keys():
		var idx: int = key
		_build_chunk(idx % CHUNKS, floori(idx / float(CHUNKS)))
	_dirty.clear()


func _in(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i <= SIZE and j <= SIZE and island[j * N + i] == 1


## The two triangles of the grid square whose corner is sample (i, j):
## A = (i, j) (i+1, j) (i, j+1) and B = (i+1, j) (i+1, j+1) (i, j+1). Only
## triangles with all three corners on land are drawn.
func _tri_a(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < SIZE and j < SIZE and _in(i, j) and _in(i + 1, j) and _in(i, j + 1)


func _tri_b(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < SIZE and j < SIZE and _in(i + 1, j) and _in(i + 1, j + 1) and _in(i, j + 1)


func _vertex(i: int, j: int) -> Vector3:
	return Vector3(i - HALF, heights[j * N + i], j - HALF)


func _build_chunk(cx: int, cz: int) -> void:
	var n := CHUNK + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	normals.resize(n * n)
	var k := 0
	for lj in n:
		for li in n:
			var i := cx * CHUNK + li
			var j := cz * CHUNK + lj
			verts[k] = _vertex(i, j)
			normals[k] = _grid_normal(i, j)
			k += 1

	var indices := PackedInt32Array()
	for lj in CHUNK:
		for li in CHUNK:
			var i := cx * CHUNK + li
			var j := cz * CHUNK + lj
			var a := lj * n + li
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Godot treats clockwise triangles (seen from above) as front faces.
			var has_a := _tri_a(i, j)
			var has_b := _tri_b(i, j)
			if has_a:
				indices.append_array(PackedInt32Array([a, b, c]))
			if has_b:
				indices.append_array(PackedInt32Array([b, d, c]))
			# A rock skirt hangs from every drawn edge with no triangle on its
			# other side. Each square owns its top, left and diagonal edges.
			var up := _tri_b(i, j - 1)
			var left := _tri_b(i - 1, j)
			if has_a != up:
				_add_skirt(verts, normals, indices, _vertex(i, j), _vertex(i + 1, j), _vertex(i, j + 1) if has_a else _vertex(i + 1, j - 1))
			if has_a != left:
				_add_skirt(verts, normals, indices, _vertex(i, j), _vertex(i, j + 1), _vertex(i + 1, j) if has_a else _vertex(i - 1, j + 1))
			if has_a != has_b:
				_add_skirt(verts, normals, indices, _vertex(i + 1, j), _vertex(i, j + 1), _vertex(i, j) if has_a else _vertex(i + 1, j + 1))

	var mi := _chunks[cz * CHUNKS + cx]
	if indices.is_empty():
		mi.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Art.terrain())
	mi.mesh = mesh


## A wall of rock hanging SKIRT_DEPTH below the edge p0-p1, facing away
## from `inside` (a point on the land side).
func _add_skirt(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		p0: Vector3, p1: Vector3, inside: Vector3) -> void:
	var edge := p1 - p0
	var out := Vector3(edge.z, 0.0, -edge.x).normalized()
	if out.dot(inside - p0) > 0.0:
		out = -out
	var b0 := p0 - Vector3.UP * SKIRT_DEPTH
	var b1 := p1 - Vector3.UP * SKIRT_DEPTH
	var base := verts.size()
	verts.append_array(PackedVector3Array([p0, p1, b0, b1]))
	normals.append_array(PackedVector3Array([out, out, out, out]))
	if (p1 - p0).cross(b0 - p0).dot(out) < 0.0:
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	else:
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))


## Flat water surfaces over every square that touches water.
func _build_water_chunk(cx: int, cz: int) -> void:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for lj in CHUNK:
		for li in CHUNK:
			var i := cx * CHUNK + li
			var j := cz * CHUNK + lj
			var k00 := j * N + i
			var levels := [water[k00], water[k00 + 1], water[k00 + N], water[k00 + N + 1]]
			var top: float = maxf(maxf(levels[0], levels[1]), maxf(levels[2], levels[3]))
			if top == NO_WATER:
				continue
			var base := verts.size()
			for c in 4:
				var level: float = levels[c]
				verts.append(Vector3(i + (c % 2) - HALF, level if level != NO_WATER else top, j + c / 2 - HALF))
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var wi := _water_chunks[cz * CHUNKS + cx]
	if verts.is_empty():
		wi.mesh = null
		return
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	wi.mesh = mesh


func _grid_height(i: int, j: int, fallback: float) -> float:
	var k := clampi(j, 0, SIZE) * N + clampi(i, 0, SIZE)
	return heights[k] if island[k] == 1 else fallback


## Normals ignore the void, so the land stays lit like land right to its edge.
func _grid_normal(i: int, j: int) -> Vector3:
	var h := heights[j * N + i]
	var hl := _grid_height(i - 1, j, h)
	var hr := _grid_height(i + 1, j, h)
	var hd := _grid_height(i, j - 1, h)
	var hu := _grid_height(i, j + 1, h)
	return Vector3(hl - hr, 2.0, hd - hu).normalized()


# --- Underside and waterfalls ---------------------------------------------------

## The rocky underside, hanging below the outline of the land.
func _build_underside() -> void:
	if _underside != null:
		_underside.queue_free()
		_underside = null
	const BINS := 180
	var reach := PackedFloat32Array()
	var rim := PackedFloat32Array()
	reach.resize(BINS)
	rim.resize(BINS)
	reach.fill(0.0)
	rim.fill(2.4)
	# Only the edge of the land matters: find how far it reaches in each
	# direction, and the lowest ground along it there.
	var edge_cells := PackedInt32Array()
	for j in range(1, SIZE):
		for i in range(1, SIZE):
			var k := j * N + i
			if island[k] == 1 and (island[k + 1] == 0 or island[k - 1] == 0 or island[k + N] == 0 or island[k - N] == 0):
				edge_cells.append(k)
	var bins := PackedInt32Array()
	var dist := PackedFloat32Array()
	bins.resize(edge_cells.size())
	dist.resize(edge_cells.size())
	for e in edge_cells.size():
		var k := edge_cells[e]
		var p := Vector2(k % N - HALF, k / N - HALF)
		bins[e] = posmod(floori((p.angle() + PI) / TAU * BINS), BINS)
		dist[e] = p.length()
		reach[bins[e]] = maxf(reach[bins[e]], dist[e])
	rim.fill(1000.0)
	for e in edge_cells.size():
		if dist[e] > reach[bins[e]] - 4.0:
			rim[bins[e]] = minf(rim[bins[e]], heights[edge_cells[e]])
	for b in BINS:
		if rim[b] > 999.0:
			rim[b] = 2.4
	# Each direction reaches at least as far as its neighbours, so thin
	# peninsulas still get rock under them.
	var widest := reach.duplicate()
	for b in BINS:
		widest[b] = maxf(reach[b], maxf(reach[(b + 1) % BINS], reach[(b + BINS - 1) % BINS]))
	if widest[0] <= 0.0 and Array(widest).max() <= 0.0:
		return
	var lump := FastNoiseLite.new()
	lump.seed = _edge_noise.seed + 1
	lump.frequency = 0.9
	var deep := sqrt(maxf(SCALE, 0.5))
	var under := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var f := fposmod((a + PI) / TAU * BINS, float(BINS))
		var b0 := floori(f) % BINS
		var b1 := (b0 + 1) % BINS
		var t := f - floori(f)
		var r := lerpf(widest[b0], widest[b1], t) - 1.0
		var top := minf(lerpf(rim[b0], rim[b1], t), 3.0) - 5.0
		var bulge := 1.0 + 0.22 * lump.get_noise_3d(cos(a) * 2.0, sin(a) * 2.0, v * 3.0) * sin(v * PI)
		var depth := (62.0 + 26.0 * lump.get_noise_2d(cos(a) * 1.3 + 7.0, sin(a) * 1.3)) * deep
		var shrink := pow(1.0 - v, 0.75)
		return Vector3(cos(a) * r * shrink * bulge, top - depth * pow(v, 1.25), sin(a) * r * shrink * bulge)
	var mb := MeshBuilder.new()
	mb.add_grid(BINS, 12, under)
	_underside = MeshInstance3D.new()
	_underside.name = "Underside"
	_underside.mesh = mb.commit()
	_underside.material_override = Art.nature("cliff")
	add_child(_underside)


## A waterfall wherever water reaches the edge of the land.
func _build_falls() -> void:
	if _falls != null:
		_falls.queue_free()
	_falls = Node3D.new()
	_falls.name = "Waterfalls"
	add_child(_falls)
	# Water samples on the edge of the land, and which way is out.
	var edge := {}
	for j in range(1, SIZE):
		for i in range(1, SIZE):
			var k := j * N + i
			if water[k] == NO_WATER or island[k] == 0:
				continue
			var out := Vector2.ZERO
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if island[(j + step.y) * N + i + step.x] == 0:
					out += Vector2(step)
			if out != Vector2.ZERO:
				edge[k] = out
	# Neighbouring edge samples pour together as one fall.
	var groups: Array = []
	var seen := {}
	for start: int in edge:
		if seen.has(start):
			continue
		var group: Array[int] = [start]
		seen[start] = true
		var head := 0
		while head < group.size():
			var k: int = group[head]
			head += 1
			for dj in range(-2, 3):
				for di in range(-2, 3):
					var nk := k + dj * N + di
					if edge.has(nk) and not seen.has(nk):
						seen[nk] = true
						group.append(nk)
		groups.append(group)
	groups.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	for g: Array in groups.slice(0, 16):
		var centre := Vector2.ZERO
		var out := Vector2.ZERO
		var level := 0.0
		for k: int in g:
			centre += Vector2(k % N - HALF, k / N - HALF)
			out += edge[k]
			level += water[k]
		centre /= g.size()
		level /= g.size()
		out = out.normalized() if out.length_squared() > 0.001 else centre.normalized()
		var side := Vector2(-out.y, out.x)
		var spread := 0.0
		for k: int in g:
			spread = maxf(spread, absf((Vector2(k % N - HALF, k / N - HALF) - centre).dot(side)))
		var width := clampf(spread * 2.0 + 2.5, 3.0, 40.0)
		var across := Vector3(side.x, 0.0, side.y)
		var sheet := func(u: float, v: float) -> Vector3:
			var push := 5.0 * (1.0 - exp(-5.0 * v))
			return across * (u - 0.5) * width + Vector3(out.x, 0.0, out.y) * push + Vector3(0.0, 0.05 - 80.0 * v * v, 0.0)
		var fall := MeshBuilder.new()
		fall.add_grid(maxi(6, ceili(width / 1.5)), 24, sheet)
		var fall_mesh := MeshInstance3D.new()
		fall_mesh.name = "Waterfall"
		fall_mesh.mesh = fall.commit()
		fall_mesh.material_override = Art.waterfall()
		var lip := centre + out * 0.8
		fall_mesh.position = Vector3(lip.x, level, lip.y)
		fall_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_falls.add_child(fall_mesh)
		if is_instance_valid(Game.effects):
			var mist := Game.effects.make_mist(clampf(width * 0.4, 2.0, 8.0))
			_falls.add_child(mist)
			mist.position = fall_mesh.position + Vector3(out.x, 0.0, out.y) * 4.0 + Vector3(0, -3.0, 0)
