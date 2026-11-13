class_name FloraFactory
extends RefCounted
## Generates trees, bushes and boulders in a cartoon style: fat curvy
## trunks and lumpy blob canopies with ink outlines. A handful of mesh
## variants per kind are built once and shared, so hundreds of plants stay
## cheap. Colours come from the nature palette (see Art.nature).

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
	mi.material_override = Art.nature("rock")
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
				_plants[key] = _make_swirl(rng)
			_:
				_plants[key] = _make_broadleaf(rng)
	return _plants[key]


static func _lumpy(rng: RandomNumberGenerator) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = rng.randi()
	noise.frequency = 0.35
	return noise


## A curvy trunk with a few branches, each ending in a lumpy blob of leaves.
static func _make_broadleaf(rng: RandomNumberGenerator) -> Dictionary:
	var h := rng.randf_range(4.6, 6.6)
	var lean := Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9))
	var trunk_pts := PackedVector3Array([Vector3(0, -1.0, 0), Vector3(0, 0.3, 0), lean * 0.5 + Vector3(0, h * 0.4, 0),
		lean * 0.4 + Vector3(0, h * 0.75, 0), lean + Vector3(0, h, 0)])
	var wood := MeshBuilder.new()
	wood.add_tube(trunk_pts, PackedFloat32Array([0.75, 0.5, 0.38, 0.3, 0.2]), 9)
	var noise := _lumpy(rng)
	var canopy := [MeshBuilder.new(), MeshBuilder.new()]
	var top := lean + Vector3(0, h + 0.8, 0)
	canopy[0].add_blob(Vector3(2.5, 2.0, 2.5) * rng.randf_range(0.9, 1.15), Transform3D(Basis(), top), noise, 0.22, 9, 14)
	var branches := rng.randi_range(2, 4)
	var spin := rng.randf() * TAU
	for k in branches:
		var a := spin + TAU * k / branches + rng.randf_range(-0.4, 0.4)
		var from := trunk_pts[2].lerp(trunk_pts[4], rng.randf_range(0.2, 0.7))
		var out := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(1.8, 2.8)
		var tip := from + out * length + Vector3(0, length * rng.randf_range(0.3, 0.7), 0)
		wood.add_tube(PackedVector3Array([from - out * 0.1, from.lerp(tip, 0.5) + Vector3(0, -0.3, 0), tip]), PackedFloat32Array([0.2, 0.15, 0.1]), 6)
		var r := rng.randf_range(1.3, 1.9)
		canopy[(k + 1) % 2].add_blob(Vector3(r, r * 0.85, r), Transform3D(Basis(), tip + Vector3(0, r * 0.4, 0)), noise, 0.22, 8, 12)
	return {
		"parts": [{"mesh": wood.commit(), "material": Art.nature("bark")},
			{"mesh": canopy[0].commit(), "material": Art.nature("leaf")}, {"mesh": canopy[1].commit(), "material": Art.nature("leaf")}],
		"height": h + 2.8, "footprint": 1.3,
	}


## A tall tree made of stacked, scalloped cones.
static func _make_pine(rng: RandomNumberGenerator) -> Dictionary:
	var h := rng.randf_range(8.0, 11.0)
	var lean := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
	var wood := MeshBuilder.new()
	wood.add_tube(PackedVector3Array([Vector3(0, -1.0, 0), Vector3(0, 0.3, 0), lean * 0.3 + Vector3(0, h * 0.4, 0)]),
		PackedFloat32Array([0.6, 0.42, 0.3]), 9)
	var canopy := [MeshBuilder.new(), MeshBuilder.new()]
	var tiers := rng.randi_range(4, 5)
	for i in tiers:
		var t := i / float(tiers)
		var y := lerpf(h * 0.22, h * 0.8, t)
		var r := lerpf(2.7, 1.1, t) * rng.randf_range(0.9, 1.1)
		var th := (h - y) * 0.75 if i == tiers - 1 else h * 0.34
		var profile := PackedVector2Array([Vector2(r * 0.3, th * 0.3), Vector2(r, 0.0), Vector2(r, 0.0), Vector2(r * 0.5, th * 0.45), Vector2(0.0, th)])
		var mb: MeshBuilder = canopy[i % 2]
		var from := mb.add_lathe(profile, 14, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), lean * t + Vector3(0, y, 0)), 7, 0.1)
		mb.bend(from, y, y + th, Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))
	return {
		"parts": [{"mesh": wood.commit(), "material": Art.nature("bark")},
			{"mesh": canopy[0].commit(), "material": Art.nature("pine")}, {"mesh": canopy[1].commit(), "material": Art.nature("pine")}],
		"height": h + 0.5, "footprint": 1.2,
	}


## A surreal tree: a trunk that curls over, tipped with a bright ball.
static func _make_swirl(rng: RandomNumberGenerator) -> Dictionary:
	var h := rng.randf_range(4.5, 7.0)
	var a := rng.randf() * TAU
	var out := Vector3(cos(a), 0, sin(a))
	var pts := PackedVector3Array([Vector3(0, -1.0, 0), Vector3(0, 0.3, 0)])
	var radii := PackedFloat32Array([0.6, 0.42])
	for k in range(1, 9):
		var t := k / 8.0
		var curl := t * t * 4.2
		pts.append(Vector3(0, h * minf(t * 1.25, 1.0), 0) + out * (sin(curl) * 1.6 * t) + Vector3(0, (cos(curl) - 1.0) * 1.2 * t, 0))
		radii.append(lerpf(0.36, 0.12, t))
	var wood := MeshBuilder.new()
	wood.add_tube(pts, radii, 8)
	var noise := _lumpy(rng)
	var ball := MeshBuilder.new()
	var r := rng.randf_range(1.1, 1.6)
	ball.add_blob(Vector3(r, r, r), Transform3D(Basis(), pts[pts.size() - 1]), noise, 0.15, 9, 14)
	var puff := MeshBuilder.new()
	puff.add_blob(Vector3(1.5, 1.1, 1.5), Transform3D(Basis(), pts[5] + Vector3(0, 0.6, 0)), noise, 0.2, 8, 12)
	return {
		"parts": [{"mesh": wood.commit(), "material": Art.nature("bark")},
			{"mesh": ball.commit(), "material": Art.nature("accent")}, {"mesh": puff.commit(), "material": Art.nature("accent")}],
		"height": h + 1.5, "footprint": 1.2,
	}


static func _make_bush(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var noise := _lumpy(rng)
	var top := 0.0
	for k in rng.randi_range(1, 3):
		var r := rng.randf_range(0.7, 1.15)
		var c := Vector3(rng.randf_range(-0.8, 0.8), r * 0.6, rng.randf_range(-0.8, 0.8)) if k > 0 else Vector3(0, r * 0.65, 0)
		mb.add_blob(Vector3(r, r * 0.85, r), Transform3D(Basis(), c), noise, 0.2, 7, 10)
		top = maxf(top, c.y + r)
	return {"parts": [{"mesh": mb.commit(), "material": Art.nature("leaf")}], "height": top, "footprint": 1.0}


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
