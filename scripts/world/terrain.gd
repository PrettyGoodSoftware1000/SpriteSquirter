class_name Terrain
extends Node3D
## Editable heightmap terrain, shaped as an island floating in the sky.
##
## Samples outside the island's wobbly outline are dropped to VOID_HEIGHT
## and not drawn; a rocky underside hangs below the rim. Rivers are carved
## below WATER_LEVEL and pour over the edge as waterfalls.
##
## Heights live in one flat array of (SIZE + 1)^2 samples spaced 1 m apart and
## centred on the origin, so the world spans x/z in [-HALF, HALF]. The visible
## mesh is split into chunks, and editing only rebuilds the chunks it touches.
##
## Heights, scorch marks and the bare-ground mask are also kept in textures
## that the terrain, grass and water shaders read (see Art.bind_terrain).

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
const VOID_HEIGHT := -60.0
const ISLAND_RADIUS := 116.0

var heights := PackedFloat32Array()
## 0..1 burn darkness per sample, painted by fire and explosions.
var scorch := PackedFloat32Array()
## 0..1 bare ground per sample (village squares, roads, under buildings).
var bare := PackedFloat32Array()
## Flat areas picked for villages: {"pos": Vector2, "radius": float, "height": float}.
var village_sites: Array[Dictionary] = []
## Centre lines of the rivers, from the spring out to the island's edge.
var rivers: Array[PackedVector2Array] = []

var grass: Grass

var _chunks: Array[MeshInstance3D] = []
var _dirty := {}
var _collision_dirty := false
var _collision_timer := 0.0
var _shape := HeightMapShape3D.new()
var _height_tex: ImageTexture
var _scorch_tex: ImageTexture
var _bare_tex: ImageTexture
var _height_tex_dirty := false
var _scorch_tex_dirty := false
var _bare_tex_dirty := false
var _edge_noise := FastNoiseLite.new()
var _island := PackedByteArray()
var _extras: Node3D


func _ready() -> void:
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			add_child(mi)
			_chunks.append(mi)
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
	if not _dirty.is_empty():
		_rebuild_dirty_chunks()
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
	_pick_village_sites(rng)
	_flatten_village_sites()
	_paint_village_ground(world_seed)
	_cut_out_island()

	_height_tex = ImageTexture.create_from_image(_to_image(heights))
	_scorch_tex = ImageTexture.create_from_image(_to_image(scorch))
	_bare_tex = ImageTexture.create_from_image(_to_image(bare))
	Art.bind_terrain(_height_tex, _scorch_tex, _bare_tex)

	_shape.map_width = N
	_shape.map_depth = N
	_shape.map_data = heights
	for idx in _chunks.size():
		_dirty[idx] = true
	_rebuild_dirty_chunks()
	_build_extras()


## Distance from the centre to the island's edge in the given direction.
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
		for k in 90:
			var t := k / 89.0
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


## Drops everything outside the island's outline into the void.
func _cut_out_island() -> void:
	_island.resize(N * N)
	for j in N:
		for i in N:
			var p := Vector2(i - HALF, j - HALF)
			var inside := p.length() < edge_radius(p.angle())
			_island[j * N + i] = 1 if inside else 0
			if not inside:
				heights[j * N + i] = VOID_HEIGHT


## Builds the rocky underside of the island, the waterfalls and the water.
func _build_extras() -> void:
	if _extras != null:
		_extras.queue_free()
	_extras = Node3D.new()
	_extras.name = "IslandExtras"
	add_child(_extras)

	var lump := FastNoiseLite.new()
	lump.seed = _edge_noise.seed + 1
	lump.frequency = 0.9
	var under := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var r := edge_radius(a)
		var rim_y := get_height(cos(a) * (r - 3.0), sin(a) * (r - 3.0))
		var bulge := 1.0 + 0.22 * lump.get_noise_3d(cos(a) * 2.0, sin(a) * 2.0, v * 3.0) * sin(v * PI)
		var depth := 62.0 + 26.0 * lump.get_noise_2d(cos(a) * 1.3 + 7.0, sin(a) * 1.3)
		var shrink := pow(1.0 - v, 0.75)
		return Vector3(cos(a) * (r + 1.6) * shrink * bulge, minf(rim_y, 3.0) - 1.5 - depth * pow(v, 1.25), sin(a) * (r + 1.6) * shrink * bulge)
	var mb := MeshBuilder.new()
	mb.add_grid(96, 12, under)
	var underside := MeshInstance3D.new()
	underside.name = "Underside"
	underside.mesh = mb.commit()
	underside.material_override = Art.nature("rock")
	_extras.add_child(underside)

	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.material_override = Art.water()
	water.position.y = WATER_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_extras.add_child(water)

	for path in rivers:
		var mouth := path[path.size() - 1]
		var angle := mouth.angle()
		var out := Vector2(cos(angle), sin(angle))
		var rim := out * (edge_radius(angle) - 0.5)
		var across := Vector3(-out.y, 0.0, out.x)
		var sheet := func(u: float, v: float) -> Vector3:
			var push := 5.0 * (1.0 - exp(-5.0 * v))
			return across * (u - 0.5) * 8.5 + Vector3(out.x, 0.0, out.y) * push + Vector3(0.0, 0.05 - 80.0 * v * v, 0.0)
		var fall := MeshBuilder.new()
		fall.add_grid(6, 24, sheet)
		var fall_mesh := MeshInstance3D.new()
		fall_mesh.name = "Waterfall"
		fall_mesh.mesh = fall.commit()
		fall_mesh.material_override = Art.waterfall()
		fall_mesh.position = Vector3(rim.x, WATER_LEVEL, rim.y)
		fall_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_extras.add_child(fall_mesh)
		if is_instance_valid(Game.effects):
			var mist := Game.effects.make_mist(4.0)
			_extras.add_child(mist)
			mist.position = fall_mesh.position + Vector3(out.x, 0.0, out.y) * 4.0 + Vector3(0, -3.0, 0)


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
	var wanted := rng.randi_range(4, 5)
	# Try strict rules first, then relax them if the map is very hilly.
	for max_relief in [5.0, 9.0, 16.0, 1000.0]:
		var attempts := 0
		while village_sites.size() < wanted and attempts < 400:
			attempts += 1
			var p := Vector2(rng.randf_range(-74.0, 74.0), rng.randf_range(-74.0, 74.0))
			var too_close := p.length() > 72.0
			var r := rng.randf_range(15.0, 21.0)
			if _river_distance(p) < r + 5.0:
				continue
			for s in village_sites:
				if p.distance_to(s.pos) < 58.0:
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
func _paint_village_ground(world_seed: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed + 5
	noise.frequency = 0.09
	# Each village gets a road to the nearest village placed before it.
	var roads: Array[PackedVector2Array] = []
	for k in range(1, village_sites.size()):
		var from: Vector2 = village_sites[k].pos
		var best: Vector2 = village_sites[0].pos
		for m in k:
			var other: Vector2 = village_sites[m].pos
			if from.distance_to(other) < from.distance_to(best):
				best = other
		roads.append(PackedVector2Array([from, best]))
	for j in N:
		for i in N:
			var p := Vector2(i - HALF, j - HALF)
			var wobble := noise.get_noise_2d(p.x, p.y)
			var value := 0.0
			for s in village_sites:
				var r: float = s.radius
				var d := p.distance_to(s.pos)
				if d < r:
					value = maxf(value, (1.0 - smoothstep(r * 0.25, r * 0.8, d)) * (0.55 + 0.5 * wobble))
			for road in roads:
				var d := _segment_distance(p, road[0], road[1]) + wobble * 2.5
				if d < 3.0:
					value = maxf(value, (1.0 - smoothstep(0.8, 2.6, d)) * 0.75)
			bare[j * N + i] = clampf(value, 0.0, 1.0)


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _to_image(data: PackedFloat32Array) -> Image:
	return Image.create_from_data(N, N, false, Image.FORMAT_RF, data.to_byte_array())


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


## True if the point is on the island (not out in the void).
func is_inside(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	return p.length() < edge_radius(p.angle()) - 2.0


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
			var k := j * N + i
			if d > radius or _island[k] == 0:
				continue
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
					var avg := (_sample(source, i - 1, j) + _sample(source, i + 1, j)
						+ _sample(source, i, j - 1) + _sample(source, i, j + 1) + h) / 5.0
					h = lerpf(h, avg, clampf(amount * w, 0.0, 1.0))
			heights[k] = clampf(h, MIN_HEIGHT, MAX_HEIGHT)
	_mark_dirty(i0, j0, i1, j1)
	_collision_dirty = true
	_height_tex_dirty = true
	changed.emit(center, radius)


## Darkens the ground (burn marks) and burns the grass away.
func add_scorch(center: Vector3, radius: float, amount: float) -> void:
	_paint(scorch, center, radius, amount)
	_scorch_tex_dirty = true


## Wears the grass away to bare dirt (around buildings, on paths).
func add_bare(center: Vector3, radius: float, amount: float) -> void:
	_paint(bare, center, radius, amount)
	_bare_tex_dirty = true


func _paint(data: PackedFloat32Array, center: Vector3, radius: float, amount: float) -> void:
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
			data[k] = minf(1.0, data[k] + amount * w)


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
	verts.resize(n * n)
	normals.resize(n * n)
	var k := 0
	for lj in n:
		for li in n:
			var i := cx * CHUNK + li
			var j := cz * CHUNK + lj
			verts[k] = Vector3(i - HALF, heights[j * N + i], j - HALF)
			normals[k] = _grid_normal(i, j)
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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Art.terrain())
	_chunks[cz * CHUNKS + cx].mesh = mesh


func _grid_height(i: int, j: int) -> float:
	return heights[clampi(j, 0, SIZE) * N + clampi(i, 0, SIZE)]


func _grid_normal(i: int, j: int) -> Vector3:
	var hl := _grid_height(i - 1, j)
	var hr := _grid_height(i + 1, j)
	var hd := _grid_height(i, j - 1)
	var hu := _grid_height(i, j + 1)
	return Vector3(hl - hr, 2.0, hd - hu).normalized()
