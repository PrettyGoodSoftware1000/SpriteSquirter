class_name Terrain
extends Node3D
## Editable heightmap terrain.
##
## Heights live in one flat array of (SIZE + 1)^2 samples spaced 1 m apart and
## centred on the origin, so the world spans x/z in [-HALF, HALF]. The visible
## mesh is split into chunks, and editing only rebuilds the chunks it touches.

signal changed(center: Vector3, radius: float)

enum Brush { RAISE, LOWER, FLATTEN, SMOOTH }

const SIZE := 256
const HALF := 128.0
const N := SIZE + 1
const CHUNK := 32
const CHUNKS := 8 # SIZE / CHUNK
const WATER_LEVEL := 0.0
const MIN_HEIGHT := -10.0
const MAX_HEIGHT := 60.0

const COLOR_SAND := Color(0.80, 0.70, 0.46)
const COLOR_GRASS := Color(0.36, 0.62, 0.20)
const COLOR_GRASS_DARK := Color(0.21, 0.45, 0.15)
const COLOR_MEADOW := Color(0.62, 0.68, 0.28)
const COLOR_ROCK := Color(0.42, 0.38, 0.36)
const COLOR_SNOW := Color(0.95, 0.96, 1.0)
const COLOR_SCORCH := Color(0.07, 0.06, 0.05)

var heights := PackedFloat32Array()
## 0..1 burn darkness per sample, painted by fire and explosions.
var scorch := PackedFloat32Array()
## Flat areas picked for villages: {"pos": Vector2, "radius": float, "height": float}.
var village_sites: Array[Dictionary] = []

var _chunks: Array[MeshInstance3D] = []
var _dirty := {}
var _collision_dirty := false
var _collision_timer := 0.0
var _shape := HeightMapShape3D.new()
var _material := StandardMaterial3D.new()
var _color_noise := FastNoiseLite.new()


func _ready() -> void:
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.95
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			add_child(mi)
			_chunks.append(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	if not _dirty.is_empty():
		_rebuild_dirty_chunks()
	if _collision_dirty:
		_collision_timer -= delta
		if _collision_timer <= 0.0:
			_collision_timer = 0.2
			_collision_dirty = false
			_shape.map_data = heights


# --- Generation -------------------------------------------------------------

func generate(world_seed: int) -> void:
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

	_color_noise.seed = world_seed + 99
	_color_noise.frequency = 0.05

	heights.resize(N * N)
	scorch.resize(N * N)
	scorch.fill(0.0)
	for j in N:
		for i in N:
			heights[j * N + i] = _natural_height(i - HALF, j - HALF, base, mask)

	_pick_village_sites(rng)
	_flatten_village_sites()

	_shape.map_width = N
	_shape.map_depth = N
	_shape.map_data = heights
	for idx in _chunks.size():
		_dirty[idx] = true
	_rebuild_dirty_chunks()


func _natural_height(x: float, z: float, base: FastNoiseLite, mask: FastNoiseLite) -> float:
	var n := base.get_noise_2d(x, z)
	# The mask decides where the land is hilly and where it stays flat.
	var hilliness := smoothstep(0.45, 0.72, (mask.get_noise_2d(x, z) + 1.0) * 0.5)
	var plains := 1.8 + n * 4.0
	var hills := 5.0 + pow((n + 1.0) * 0.5, 1.5) * 36.0
	var h := lerpf(plains, hills, hilliness)
	# Sink the map edges into the sea so the world reads as an island.
	var edge := maxf(absf(x), absf(z)) / HALF
	return lerpf(h, -4.0, smoothstep(0.78, 0.98, edge))


func _pick_village_sites(rng: RandomNumberGenerator) -> void:
	village_sites.clear()
	var wanted := rng.randi_range(4, 5)
	# Try strict rules first, then relax them if the map is very hilly.
	for max_relief in [5.0, 9.0, 16.0, 1000.0]:
		var attempts := 0
		while village_sites.size() < wanted and attempts < 400:
			attempts += 1
			var p := Vector2(rng.randf_range(-82.0, 82.0), rng.randf_range(-82.0, 82.0))
			var too_close := false
			for s in village_sites:
				if p.distance_to(s.pos) < 58.0:
					too_close = true
					break
			if too_close:
				continue
			var r := rng.randf_range(15.0, 21.0)
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


# --- Queries ----------------------------------------------------------------

## Height of the surface at world x/z, matching the rendered triangles.
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


func is_inside(x: float, z: float) -> bool:
	return absf(x) < HALF - 1.0 and absf(z) < HALF - 1.0


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
func raycast(origin: Vector3, dir: Vector3, max_dist := 2000.0) -> Variant:
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
	var i0 := clampi(floori(center.x + HALF - radius), 0, SIZE)
	var i1 := clampi(ceili(center.x + HALF + radius), 0, SIZE)
	var j0 := clampi(floori(center.z + HALF - radius), 0, SIZE)
	var j1 := clampi(ceili(center.z + HALF + radius), 0, SIZE)
	var source := PackedFloat32Array()
	if mode == Brush.SMOOTH:
		source = heights.duplicate()
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := Vector2(i - HALF - center.x, j - HALF - center.z).length()
			if d > radius:
				continue
			var w := 1.0 - smoothstep(radius * hardness, radius, d)
			var k := j * N + i
			var h := heights[k]
			match mode:
				Brush.RAISE:
					h += amount * w
				Brush.LOWER:
					h -= amount * w
				Brush.FLATTEN:
					h = lerpf(h, target_height, clampf(amount * w, 0.0, 1.0))
				Brush.SMOOTH:
					var avg := (_sample(source, i - 1, j) + _sample(source, i + 1, j)
						+ _sample(source, i, j - 1) + _sample(source, i, j + 1) + h) / 5.0
					h = lerpf(h, avg, clampf(amount * w, 0.0, 1.0))
			heights[k] = clampf(h, MIN_HEIGHT, MAX_HEIGHT)
	_mark_dirty(i0, j0, i1, j1)
	_collision_dirty = true
	changed.emit(center, radius)


## Darkens the ground (burn marks). Purely visual.
func add_scorch(center: Vector3, radius: float, amount: float) -> void:
	var i0 := clampi(floori(center.x + HALF - radius), 0, SIZE)
	var i1 := clampi(ceili(center.x + HALF + radius), 0, SIZE)
	var j0 := clampi(floori(center.z + HALF - radius), 0, SIZE)
	var j1 := clampi(ceili(center.z + HALF + radius), 0, SIZE)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := Vector2(i - HALF - center.x, j - HALF - center.z).length()
			if d > radius:
				continue
			var k := j * N + i
			var w := 1.0 - smoothstep(radius * 0.3, radius, d)
			scorch[k] = minf(1.0, scorch[k] + amount * w)
	_mark_dirty(i0, j0, i1, j1)


func _sample(source: PackedFloat32Array, i: int, j: int) -> float:
	return source[clampi(j, 0, SIZE) * N + clampi(i, 0, SIZE)]


func _mark_dirty(i0: int, j0: int, i1: int, j1: int) -> void:
	# Normals use neighbouring samples, so widen the range by a couple of cells.
	var cx0 := clampi(floori((i0 - 2) / float(CHUNK)), 0, CHUNKS - 1)
	var cx1 := clampi(floori((i1 + 2) / float(CHUNK)), 0, CHUNKS - 1)
	var cz0 := clampi(floori((j0 - 2) / float(CHUNK)), 0, CHUNKS - 1)
	var cz1 := clampi(floori((j1 + 2) / float(CHUNK)), 0, CHUNKS - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			_dirty[cz * CHUNKS + cx] = true


# --- Mesh building ----------------------------------------------------------

func _rebuild_dirty_chunks() -> void:
	for key in _dirty.keys():
		var idx: int = key
		_build_chunk(idx % CHUNKS, floori(idx / float(CHUNKS)))
	_dirty.clear()


func _build_chunk(cx: int, cz: int) -> void:
	var n := CHUNK + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var k := 0
	for lj in n:
		for li in n:
			var i := cx * CHUNK + li
			var j := cz * CHUNK + lj
			var h := heights[j * N + i]
			var nrm := _grid_normal(i, j)
			verts[k] = Vector3(i - HALF, h, j - HALF)
			normals[k] = nrm
			colors[k] = _grid_color(i, j, h, nrm)
			k += 1

	var indices := PackedInt32Array()
	indices.resize(CHUNK * CHUNK * 6)
	var w := 0
	for lj in CHUNK:
		for li in CHUNK:
			var a := lj * n + li
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Godot treats clockwise triangles (seen from above) as front faces.
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = c
			indices[w + 3] = b
			indices[w + 4] = d
			indices[w + 5] = c
			w += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	_chunks[cz * CHUNKS + cx].mesh = mesh


func _grid_height(i: int, j: int) -> float:
	return heights[clampi(j, 0, SIZE) * N + clampi(i, 0, SIZE)]


func _grid_normal(i: int, j: int) -> Vector3:
	var hl := _grid_height(i - 1, j)
	var hr := _grid_height(i + 1, j)
	var hd := _grid_height(i, j - 1)
	var hu := _grid_height(i, j + 1)
	return Vector3(hl - hr, 2.0, hd - hu).normalized()


func _grid_color(i: int, j: int, h: float, nrm: Vector3) -> Color:
	var x := i - HALF
	var z := j - HALF
	var variation := (_color_noise.get_noise_2d(x, z) + 1.0) * 0.5
	var c := COLOR_GRASS.lerp(COLOR_GRASS_DARK, variation)
	for s in village_sites:
		var r: float = s.radius
		var d := Vector2(x, z).distance_to(s.pos)
		if d < r + 4.0:
			c = c.lerp(COLOR_MEADOW, (1.0 - smoothstep(r - 6.0, r + 4.0, d)) * 0.6)
	c = COLOR_SAND.lerp(c, smoothstep(0.3, 1.3, h))
	var slope := 1.0 - nrm.y
	c = c.lerp(COLOR_ROCK, smoothstep(0.16, 0.36, slope))
	c = c.lerp(COLOR_SNOW, smoothstep(24.0, 29.0, h) * (1.0 - smoothstep(0.3, 0.5, slope)))
	return c.lerp(COLOR_SCORCH, scorch[j * N + i])
