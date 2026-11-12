class_name FloraFactory
extends RefCounted
## Generates trees, bushes and boulders. A handful of mesh variants per
## kind are built once and shared, so hundreds of plants stay cheap.
##
## Canopies are clumps of leaf cards whose normals point away from the
## middle of the clump, which makes them shade like soft rounded volumes.

const VARIANTS := 5

static var _plants := {}
static var _rocks: Array[ArrayMesh] = []


static func create_tree(rng: RandomNumberGenerator) -> Destructible:
	var roll := rng.randf()
	var kind := "broadleaf"
	if roll < 0.28:
		kind = "pine"
	elif roll < 0.36:
		kind = "autumn"
	elif roll < 0.52:
		kind = "bush"
	var data := _plant(kind, rng.randi() % VARIANTS)
	var t := Destructible.new()
	t.name = "Tree"
	t.is_building = false
	var s := rng.randf_range(0.85, 1.3)
	for part in data.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		mi.material_override = part.material
		mi.set_meta("debris", true)
		t.add_child(mi)
	t.scale = Vector3.ONE * s
	t.height = data.height * s
	t.footprint = data.footprint * s
	t.max_hp = 15.0 if kind == "bush" else 45.0
	t.hp = t.max_hp
	t.flammability = 0.6
	t.burn_duration = rng.randf_range(8.0, 13.0)
	if kind != "bush":
		_add_collider(t, 0.35, data.height * 0.6)
	return t


static func create_rock(rng: RandomNumberGenerator) -> MeshInstance3D:
	if _rocks.is_empty():
		_build_rocks()
	var mi := MeshInstance3D.new()
	mi.mesh = _rocks[rng.randi() % _rocks.size()]
	mi.material_override = Art.rock()
	var s := rng.randf_range(0.5, 1.0) * (2.4 if rng.randf() < 0.15 else 1.0)
	mi.scale = Vector3(s, s * rng.randf_range(0.7, 1.1), s)
	mi.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
	mi.add_to_group("grounded")
	return mi


# --- Plant library ----------------------------------------------------------

static func _plant(kind: String, variant: int) -> Dictionary:
	var key := "%s|%d" % [kind, variant]
	if not _plants.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		match kind:
			"pine":
				_plants[key] = _make_pine(rng)
			"bush":
				_plants[key] = _make_bush(rng)
			"autumn":
				_plants[key] = _make_broadleaf(rng, Art.foliage(Art.AUTUMN_DARK, Art.AUTUMN_LIGHT))
			_:
				_plants[key] = _make_broadleaf(rng, Art.foliage(Art.LEAF_DARK, Art.LEAF_LIGHT))
	return _plants[key]


static func _make_broadleaf(rng: RandomNumberGenerator, leaves: Material) -> Dictionary:
	var h := rng.randf_range(4.6, 6.6)
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	var trunk_pts := PackedVector3Array([Vector3(0, -1.0, 0), Vector3(0, 0.3, 0), lean * 0.3 + Vector3(0, h * 0.4, 0),
		lean * 0.7 + Vector3(0, h * 0.75, 0), lean + Vector3(0, h, 0)])
	var wood := MeshBuilder.new()
	wood.add_tube(trunk_pts, PackedFloat32Array([0.6, 0.42, 0.33, 0.25, 0.14]), 9)
	wood.ground_shade(0, 0.0, 1.5, 0.2)

	var canopy := [MeshBuilder.new(), MeshBuilder.new()]
	var puffs: Array[Vector3] = [lean + Vector3(0, h + 0.6, 0)]
	var branches := rng.randi_range(3, 4)
	var spin := rng.randf() * TAU
	for k in branches:
		var a := spin + TAU * k / branches + rng.randf_range(-0.4, 0.4)
		var t := rng.randf_range(0.5, 0.85)
		var from := trunk_pts[2].lerp(trunk_pts[4], (t - 0.4) / 0.6)
		var out := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(1.8, 3.0)
		var tip := from + out * length + Vector3(0, length * rng.randf_range(0.45, 0.9), 0)
		var mid := from.lerp(tip, 0.5) + Vector3(0, -0.25, 0) + out * 0.3
		wood.add_tube(PackedVector3Array([from - out * 0.1, mid, tip]), PackedFloat32Array([0.16, 0.11, 0.05]), 6)
		puffs.append(tip + Vector3(0, 0.3, 0))
	for k in puffs.size():
		var r := rng.randf_range(1.7, 2.3) if k == 0 else rng.randf_range(1.4, 2.0)
		_add_puff(canopy[k % 2], rng, puffs[k], r, 46, 0.25 + 0.6 * clampf((puffs[k].y - h * 0.6) / (h * 0.6), 0.0, 1.0))
	return {
		"parts": [{"mesh": wood.commit(), "material": Art.bark()},
			{"mesh": canopy[0].commit(), "material": leaves}, {"mesh": canopy[1].commit(), "material": leaves}],
		"height": h + 2.4, "footprint": 1.3,
	}


static func _make_pine(rng: RandomNumberGenerator) -> Dictionary:
	var h := rng.randf_range(8.0, 11.0)
	var lean := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	var wood := MeshBuilder.new()
	wood.add_tube(PackedVector3Array([Vector3(0, -1.0, 0), Vector3(0, 0.3, 0), lean * 0.5 + Vector3(0, h * 0.5, 0), lean + Vector3(0, h, 0)]),
		PackedFloat32Array([0.5, 0.36, 0.22, 0.04]), 9)
	wood.ground_shade(0, 0.0, 1.5, 0.2)
	var canopy := [MeshBuilder.new(), MeshBuilder.new()]
	var tiers := 8
	for i in tiers:
		var t := i / float(tiers - 1)
		var y := lerpf(h * 0.24, h * 0.98, t)
		var length := lerpf(3.0, 0.8, t) * rng.randf_range(0.9, 1.1)
		var count := 9 - int(t * 4.0)
		var centre := lean * (y / h) + Vector3(0, y, 0)
		var spin := rng.randf() * TAU
		var droop := lerpf(0.5, 0.15, t)
		for k in count:
			var a := spin + TAU * k / count
			var out := Vector3(cos(a), 0, sin(a))
			var along := (out * cos(droop) - Vector3.UP * sin(droop)) * length * 0.5
			var side := Vector3(-sin(a), 0, cos(a)) * length * 0.55
			var mb: MeshBuilder = canopy[i % 2]
			mb.color = Color(clampf(0.25 + 0.55 * t + rng.randf_range(-0.08, 0.12), 0.0, 1.0), 0.6, 0.0)
			mb.add_card(centre + along * 0.9, side, -along, (out * 0.55 + Vector3.UP * 0.85).normalized())
	_add_puff(canopy[0], rng, lean + Vector3(0, h + 0.2, 0), 0.7, 8, 0.9)
	var leaves := Art.foliage(Art.PINE_DARK, Art.PINE_LIGHT)
	return {
		"parts": [{"mesh": wood.commit(), "material": Art.bark()},
			{"mesh": canopy[0].commit(), "material": leaves}, {"mesh": canopy[1].commit(), "material": leaves}],
		"height": h + 0.8, "footprint": 1.2,
	}


static func _make_bush(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var count := rng.randi_range(1, 3)
	var top := 0.0
	for k in count:
		var r := rng.randf_range(0.7, 1.15)
		var c := Vector3(rng.randf_range(-0.8, 0.8), r * 0.7, rng.randf_range(-0.8, 0.8)) if k > 0 else Vector3(0, r * 0.75, 0)
		_add_puff(mb, rng, c, r, 24, 0.35)
		top = maxf(top, c.y + r)
	return {"parts": [{"mesh": mb.commit(), "material": Art.foliage(Art.LEAF_DARK, Art.LEAF_LIGHT.lerp(Art.GRASS_TIP, 0.5))}],
		"height": top, "footprint": 1.0}


## A round clump of leaf cards. `tone` (0..1) shifts it darker or lighter.
static func _add_puff(mb: MeshBuilder, rng: RandomNumberGenerator, centre: Vector3, radius: float, cards: int, tone: float) -> void:
	for k in cards:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.45, 1), rng.randf_range(-1, 1)).normalized()
		var pos := centre + dir * radius * rng.randf_range(0.4, 1.0) * Vector3(1, 0.8, 1)
		var facing := (dir + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))).normalized()
		var right := facing.cross(Vector3.UP)
		if right.length_squared() < 0.01:
			right = Vector3.RIGHT
		right = right.normalized().rotated(facing, rng.randf() * TAU)
		var up := right.cross(facing)
		var size := radius * rng.randf_range(0.45, 0.7)
		var shade := (pos - centre + Vector3.UP * radius * 0.4).normalized()
		var bright := clampf(tone * 0.5 + 0.45 * (dir.y * 0.5 + 0.5) + rng.randf_range(-0.1, 0.15), 0.0, 1.0)
		mb.color = Color(bright, 1.0, 0.0)
		mb.add_card(pos, right * size, up * size, shade)


static func _build_rocks() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.55
	for v in 5:
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + v
		noise.seed = 40 + v
		var mb := MeshBuilder.new()
		for k in rng.randi_range(1, 3):
			var r := Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.1), rng.randf_range(0.8, 1.4)) * (1.0 if k == 0 else 0.6)
			var pos := Vector3.ZERO if k == 0 else Vector3(rng.randf_range(-1.2, 1.2), -0.1, rng.randf_range(-1.2, 1.2))
			mb.add_blob(r, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos + Vector3(0, r.y * 0.35, 0)), noise, 0.35, 10, 14)
		mb.ground_shade(0, 0.0, 0.6, 0.22)
		_rocks.append(mb.commit())


static func _add_collider(node: Node3D, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = height * 0.5
	body.add_child(cs)
	node.add_child(body)
