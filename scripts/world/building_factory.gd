class_name BuildingFactory
extends RefCounted
## Generates funky fantasy buildings: crooked timber cottages, leaning
## wizard towers, mushroom houses, turf-roofed burrows and gourd houses.
##
## Each building is a Destructible made of big structural pieces (tagged
## with the "debris" meta so they fly apart when destroyed). Windows, doors
## and beams are merged into a few detail meshes that ride along with the
## piece they sit on. The same RNG seed always gives the same building.

const STOREY := 2.7
const SINK := 1.3 # how far ground floors reach below the surface


## Collects the small details of one structural piece, grouped by material.
class Details:
	var timber := MeshBuilder.new()
	var glass := MeshBuilder.new()
	var wood := MeshBuilder.new()
	var stone := MeshBuilder.new()

	func attach(part: Node3D, stone_material: Material) -> void:
		_add(part, timber, Art.timber())
		_add(part, glass, Art.glass())
		_add(part, wood, Art.wood())
		_add(part, stone, stone_material)

	func _add(part: Node3D, builder: MeshBuilder, material: Material) -> void:
		if builder.is_empty():
			return
		var mi := MeshInstance3D.new()
		mi.mesh = builder.commit()
		mi.material_override = material
		part.add_child(mi)

	## A timber beam between two points.
	func beam(a: Vector3, b: Vector3, thickness := 0.2) -> void:
		timber.add_box(Vector3(thickness, a.distance_to(b), thickness), 0.03,
			Transform3D(BuildingFactory.basis_y(b - a), (a + b) * 0.5))

	## A framed window. `xf` sits on the wall with +Z pointing outwards.
	func window(xf: Transform3D, w: float, h: float, shutters := false) -> void:
		var t := 0.11
		glass.add_box(Vector3(w, h, 0.1), 0.02, xf)
		timber.add_box(Vector3(w + t * 2.0, t, 0.22), 0.03, xf.translated_local(Vector3(0, h * 0.5 + t * 0.5, 0.05)))
		timber.add_box(Vector3(w + 0.36, 0.13, 0.32), 0.03, xf.translated_local(Vector3(0, -h * 0.5 - 0.06, 0.09)))
		for side in [-1.0, 1.0]:
			timber.add_box(Vector3(t, h, 0.22), 0.03, xf.translated_local(Vector3(side * (w * 0.5 + t * 0.5), 0, 0.05)))
		timber.add_box(Vector3(0.05, h, 0.13), 0.01, xf.translated_local(Vector3(0, 0, 0.03)))
		timber.add_box(Vector3(w, 0.05, 0.13), 0.01, xf.translated_local(Vector3(0, 0, 0.03)))
		if shutters:
			for side in [-1.0, 1.0]:
				var hinge := xf.translated_local(Vector3(side * (w * 0.5 + t), 0, 0.1))
				hinge = hinge * Transform3D(Basis(Vector3.UP, -side * 0.35), Vector3.ZERO)
				wood.add_box(Vector3(w * 0.5, h, 0.06), 0.02, hinge.translated_local(Vector3(side * w * 0.25, 0, 0)))

	func round_window(xf: Transform3D, r: float) -> void:
		glass.add_blob(Vector3(r, r, 0.07), xf, null, 0.0, 6, 14)
		timber.add_ring(r, 0.09, xf.translated_local(Vector3(0, 0, 0.04)), 16, 6)
		timber.add_box(Vector3(0.05, r * 2.0, 0.1), 0.01, xf.translated_local(Vector3(0, 0, 0.05)))
		timber.add_box(Vector3(r * 2.0, 0.05, 0.1), 0.01, xf.translated_local(Vector3(0, 0, 0.05)))

	## A plank door with a timber frame. `xf` is at the bottom centre.
	func door(xf: Transform3D, w: float, h: float) -> void:
		wood.add_box(Vector3(w, h, 0.16), 0.04, xf.translated_local(Vector3(0, h * 0.5, 0.02)))
		for side in [-1.0, 1.0]:
			timber.add_box(Vector3(0.18, h + 0.1, 0.3), 0.04, xf.translated_local(Vector3(side * (w * 0.5 + 0.09), h * 0.5, 0.05)))
		timber.add_box(Vector3(w + 0.5, 0.2, 0.34), 0.04, xf.translated_local(Vector3(0, h + 0.1, 0.06)))
		timber.add_blob(Vector3(0.07, 0.07, 0.07), xf.translated_local(Vector3(w * 0.3, h * 0.48, 0.13)), null, 0.0, 4, 8)

	## A round-topped door inside a stone arch.
	func arch_door(xf: Transform3D, w: float, h: float) -> void:
		var r := w * 0.5
		wood.add_box(Vector3(w, h - r, 0.16), 0.03, xf.translated_local(Vector3(0, (h - r) * 0.5, 0.02)))
		wood.add_blob(Vector3(r, r, 0.08), xf.translated_local(Vector3(0, h - r, 0.02)), null, 0.0, 6, 16)
		var path := PackedVector3Array([Vector3(-r - 0.1, -0.3, 0.05), Vector3(-r - 0.1, h - r, 0.05)])
		for k in range(1, 8):
			var a := PI - PI * k / 8.0
			path.append(Vector3(cos(a) * (r + 0.1), h - r + sin(a) * (r + 0.1), 0.05))
		path.append(Vector3(r + 0.1, h - r, 0.05))
		path.append(Vector3(r + 0.1, -0.3, 0.05))
		var radii := PackedFloat32Array()
		radii.resize(path.size())
		radii.fill(0.2)
		stone.add_tube(path, radii, 8, xf)
		timber.add_blob(Vector3(0.07, 0.07, 0.07), xf.translated_local(Vector3(w * 0.25, h * 0.42, 0.13)), null, 0.0, 4, 8)


# --- Entry points -----------------------------------------------------------

static func create_building(rng: RandomNumberGenerator) -> Destructible:
	var b := Destructible.new()
	b.name = "Building"
	b.is_building = true
	var top := 0.0
	match rng.randi_range(0, 5):
		0, 1:
			top = _build_cottage(b, rng)
		2:
			top = _build_tower(b, rng)
		3:
			top = _build_mushroom(b, rng)
		4:
			top = _build_burrow(b, rng)
		_:
			top = _build_gourd(b, rng)
	b.height = top
	b.max_hp = 70.0 + top * 5.0
	b.hp = b.max_hp
	b.flammability = 0.35
	b.burn_duration = rng.randf_range(16.0, 26.0)
	_add_collider(b, b.footprint * 0.8, top)
	return b


## Turns a freshly built object into a see-through placement preview.
static func make_ghost(node: Node, ghost_material: Material) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			child.queue_free()
			continue
		if child is MeshInstance3D:
			child.material_override = ghost_material
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		make_ghost(child, ghost_material)


# --- Cottage ------------------------------------------------------------------

## Stone ground floor, jettied plaster-and-timber upper floors that twist
## and lean, and a sagging gable roof.
static func _build_cottage(b: Destructible, rng: RandomNumberGenerator) -> float:
	var floors := rng.randi_range(1, 3)
	var w := rng.randf_range(4.8, 6.4)
	var d := rng.randf_range(4.2, 5.4)
	var stone_mat := Art.stone(rng.randi())
	var plaster_mat := Art.plaster(_pick(rng, Art.PLASTER_COLORS))
	b.footprint = maxf(w, d) * 0.62

	# Ground floor.
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(w, STOREY + SINK, d), 0.25, Transform3D(Basis(), Vector3(0, (STOREY - SINK) * 0.5, 0)), Vector2(0.95, 0.95))
	mb.ground_shade(0, 0.0, 1.6)
	var ground := _part(b, mb.commit(), stone_mat if floors > 1 or rng.randf() < 0.5 else plaster_mat)
	var det := Details.new()
	var door_x := rng.randf_range(-0.25, 0.25) * w
	det.door(Transform3D(Basis(), Vector3(door_x, 0.0, d * 0.5 * 0.96)), 1.1, 2.05)
	var win_x := door_x + (1.9 if door_x < 0.0 else -1.9)
	det.window(_face(0, w, d, win_x, 1.5), 0.9, 1.0, true)
	det.window(_face(1, w, d, rng.randf_range(-1.0, 1.0), 1.5), 0.9, 1.0, rng.randf() < 0.5)
	det.window(_face(2, w, d, 0.0, 1.5), 0.8, 1.0)
	det.window(_face(3, w, d, 0.0, 1.5), 0.8, 1.0)
	det.attach(ground, stone_mat)

	# Upper floors.
	var y := STOREY
	var twist := 0.0
	var lean := Vector3.ZERO
	for f in range(1, floors):
		w += rng.randf_range(0.35, 0.6)
		d += rng.randf_range(0.3, 0.5)
		twist += rng.randf_range(-0.14, 0.14)
		lean += Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var fh := rng.randf_range(2.3, 2.7)
		mb = MeshBuilder.new()
		mb.add_box(Vector3(w, fh, d), 0.12, Transform3D(Basis(), Vector3(0, fh * 0.5, 0)))
		var floor_part := _part(b, mb.commit(), plaster_mat, lean + Vector3(0, y, 0), Vector3(0, twist, 0))
		det = Details.new()
		_timber_frame(det, rng, w, fh, d)
		det.window(_face(0, w, d, -w * 0.22, fh * 0.52), 0.85, 1.0, rng.randf() < 0.4)
		det.window(_face(0, w, d, w * 0.22, fh * 0.52), 0.85, 1.0)
		det.window(_face(1, w, d, 0.0, fh * 0.52), 0.85, 1.0)
		det.window(_face(2, w, d, 0.0, fh * 0.52), 0.85, 1.0, rng.randf() < 0.4)
		det.window(_face(3, w, d, 0.0, fh * 0.52), 0.85, 1.0)
		det.attach(floor_part, stone_mat)
		y += fh

	# Roof: gable or tall tented hat.
	var roof_mat: Material = Art.thatch() if rng.randf() < 0.35 else Art.roof(_pick(rng, Art.ROOF_COLORS))
	var roof_h := rng.randf_range(0.55, 0.95) * d
	var roof_pos := lean + Vector3(0, y, 0)
	if rng.randf() < 0.75:
		mb = MeshBuilder.new()
		_gable_roof(mb, w, d, roof_h, 0.55, rng.randf_range(0.1, 0.4), rng.randf_range(0.2, 0.6))
		var roof := _part(b, mb.commit(), roof_mat, roof_pos, Vector3(0, twist, 0))
		var gable := MeshBuilder.new()
		_gable_walls(gable, w, d, roof_h, 0.55)
		var gable_mesh := MeshInstance3D.new()
		gable_mesh.mesh = gable.commit()
		gable_mesh.material_override = plaster_mat
		roof.add_child(gable_mesh)
	else:
		roof_h = rng.randf_range(0.9, 1.4) * d
		mb = MeshBuilder.new()
		var start := _hat_roof(mb, maxf(w, d) * 0.72, roof_h, 0.35, 4, true)
		mb.bend(start, roof_h * 0.35, roof_h, Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9)))
		_part(b, mb.commit(), roof_mat, roof_pos, Vector3(0, twist + PI * 0.25, 0))

	# Chimney.
	if rng.randf() < 0.75:
		var cx := (w * 0.5 - 0.7) * (1.0 if rng.randf() < 0.5 else -1.0)
		var ch := roof_h * 0.75 + 1.4
		mb = MeshBuilder.new()
		var tilt := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		mb.add_tube(PackedVector3Array([Vector3(0, -0.5, 0), Vector3(0, ch * 0.5, 0) + tilt * 0.4, Vector3(0, ch, 0) + tilt]),
			PackedFloat32Array([0.5, 0.42, 0.36]), 8)
		mb.add_box(Vector3(0.95, 0.22, 0.95), 0.06, Transform3D(Basis(), Vector3(0, ch, 0) + tilt))
		_part(b, mb.commit(), stone_mat, roof_pos + Basis(Vector3.UP, twist) * Vector3(cx, 0, 0))
		roof_h = maxf(roof_h, ch)
	return y + roof_h


static func _timber_frame(det: Details, rng: RandomNumberGenerator, w: float, h: float, d: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			det.beam(Vector3(sx * x, 0, sz * z), Vector3(sx * x, h, sz * z), 0.26)
	for yy in [0.08, h - 0.08]:
		det.beam(Vector3(-x, yy, z), Vector3(x, yy, z), 0.24)
		det.beam(Vector3(-x, yy, -z), Vector3(x, yy, -z), 0.24)
		det.beam(Vector3(x, yy, -z), Vector3(x, yy, z), 0.24)
		det.beam(Vector3(-x, yy, -z), Vector3(-x, yy, z), 0.24)
	# Diagonal braces in the corners of each wall.
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			if rng.randf() < 0.8:
				det.beam(Vector3(sx * x, h * 0.05, sz * (z + 0.02)), Vector3(sx * (x - h * 0.42), h * 0.95, sz * (z + 0.02)), 0.16)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			if rng.randf() < 0.8:
				det.beam(Vector3(sx * (x + 0.02), h * 0.05, sz * z), Vector3(sx * (x + 0.02), h * 0.95, sz * (z - h * 0.42)), 0.16)


## A solid gable roof with its ridge along X: curved slopes, a sagging ridge
## and upturned ends.
static func _gable_roof(mb: MeshBuilder, w: float, d: float, h: float, overhang: float, sag: float, flare: float) -> void:
	var half_len := w * 0.5 + overhang
	var half_span := d * 0.5 + overhang
	for side in [-1.0, 1.0]:
		var s: float = side
		var top := func(u: float, v: float) -> Vector3:
			var end := absf(u * 2.0 - 1.0)
			var yy := -0.4 + (h + 0.4) * pow(v, 1.3) - sag * sin(u * PI) * v + flare * end * end * (0.35 + 0.65 * v)
			return Vector3((u - 0.5) * 2.0 * half_len, yy, s * half_span * (1.0 - v))
		var under := func(u: float, v: float) -> Vector3:
			var p: Vector3 = top.call(u, v)
			var edge := minf(minf(u, 1.0 - u) * 8.0, v * 6.0)
			p.y -= 0.24 * clampf(edge, 0.0, 1.0)
			return p
		mb.add_grid(8, 6, top, Transform3D.IDENTITY, s > 0.0)
		mb.add_grid(8, 6, under, Transform3D.IDENTITY, s < 0.0)


## Triangular wall pieces that close the two ends under a gable roof.
static func _gable_walls(mb: MeshBuilder, w: float, d: float, h: float, overhang: float) -> void:
	var half_span := d * 0.5 + overhang
	for side in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var x: float = side * (w * 0.5 - 0.06)
		pts.append(Vector3(x, -0.05, -d * 0.5 + 0.1))
		for k in 9:
			var z := lerpf(-d * 0.5 + 0.1, d * 0.5 - 0.1, k / 8.0)
			var v := 1.0 - absf(z) / half_span
			pts.append(Vector3(x, -0.4 + (h + 0.4) * pow(v, 1.3) - 0.3, z))
		pts.append(Vector3(x, -0.05, d * 0.5 - 0.1))
		mb.add_fan(pts, Vector3(side, 0, 0))


## A pointed hat roof (round, or faceted when `flat`). Returns the index of
## its first vertex so the caller can bend the tip.
static func _hat_roof(mb: MeshBuilder, radius: float, h: float, droop: float, segments := 20, flat := false) -> int:
	var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(radius * 0.9, -droop * 0.8), Vector2(radius, -droop), Vector2(radius, -droop)])
	for k in range(1, 11):
		var t := k / 10.0
		profile.append(Vector2(radius * pow(1.0 - t, 1.55), -droop + (h + droop) * t))
	return mb.add_lathe(profile, segments, Transform3D.IDENTITY, 0, 0.0, flat)


# --- Wizard tower -------------------------------------------------------------

static func _build_tower(b: Destructible, rng: RandomNumberGenerator) -> float:
	var r := rng.randf_range(1.9, 2.5)
	var sections := rng.randi_range(2, 4)
	var stone_index := rng.randi()
	var stone_mat := Art.stone(stone_index)
	b.footprint = r * 1.25
	var y := 0.0
	var drift := Vector3.ZERO
	var drift_dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.15, 0.45)
	var window_angle := rng.randf() * TAU
	for s in sections:
		var sh := rng.randf_range(2.6, 3.4)
		var sink := SINK if s == 0 else 0.0
		var r_top := r * rng.randf_range(0.88, 0.96)
		var profile := PackedVector2Array([Vector2(r * 1.06, -sink), Vector2(r * 1.03, sh * 0.15), Vector2((r + r_top) * 0.5 * 1.02, sh * 0.55),
			Vector2(r_top, sh - 0.3), Vector2(r_top + 0.14, sh - 0.2), Vector2(r_top + 0.14, sh), Vector2(r_top + 0.14, sh), Vector2(0.0, sh)])
		var mb := MeshBuilder.new()
		mb.add_lathe(profile, 22)
		if s == 0:
			mb.ground_shade(0, 0.0, 1.6)
		var tilt := Vector3(drift_dir.z * 0.06, 0, -drift_dir.x * 0.06)
		var part := _part(b, mb.commit(), stone_mat, drift + Vector3(0, y, 0), tilt)
		var det := Details.new()
		if s == 0:
			det.arch_door(_around(0.0, r * 1.02, 0.0), 1.2, 2.2)
			window_angle = 1.6 + rng.randf() * 2.0
		for k in rng.randi_range(1, 2):
			window_angle += rng.randf_range(1.3, 2.4)
			det.window(_around(window_angle, (r + r_top) * 0.5 * 1.0, sh * 0.55), 0.5, 1.2)
		det.attach(part, stone_mat)
		y += sh
		drift += drift_dir
		r = r_top

	# A wider timber-framed room on top.
	if rng.randf() < 0.65:
		var room_r := r + rng.randf_range(0.5, 0.8)
		var rh := 2.5
		var mb := MeshBuilder.new()
		mb.add_lathe(PackedVector2Array([Vector2(r * 0.9, -0.1), Vector2(room_r, 0.55), Vector2(room_r, rh), Vector2(room_r, rh), Vector2(0.0, rh)]), 22)
		var room := _part(b, mb.commit(), Art.plaster(_pick(rng, Art.PLASTER_COLORS)), drift + Vector3(0, y, 0))
		var det := Details.new()
		for k in 8:
			var a := TAU * k / 8.0
			var dir := Vector3(sin(a), 0, cos(a)) * (room_r + 0.02)
			det.beam(dir + Vector3(0, 0.55, 0), dir + Vector3(0, rh, 0), 0.2)
		det.timber.add_lathe(PackedVector2Array([Vector2(room_r, 0.5), Vector2(room_r + 0.12, 0.55), Vector2(room_r + 0.12, 0.75), Vector2(room_r, 0.8)]), 22)
		det.timber.add_lathe(PackedVector2Array([Vector2(room_r, rh - 0.3), Vector2(room_r + 0.12, rh - 0.25), Vector2(room_r + 0.12, rh - 0.05), Vector2(room_r, rh)]), 22)
		for k in 4:
			det.window(_around(TAU * (k + 0.5) / 4.0, room_r, rh * 0.58), 0.7, 0.9)
		det.attach(room, stone_mat)
		y += rh
		r = room_r

	# A little turret hanging off the side.
	if rng.randf() < 0.4 and sections >= 3:
		var a := rng.randf() * TAU
		var tr := 0.95
		var base := drift * 0.6 + Vector3(sin(a), 0, cos(a)) * (r + 0.35) + Vector3(0, y * 0.55, 0)
		var mb := MeshBuilder.new()
		mb.add_lathe(PackedVector2Array([Vector2(0.0, -1.3), Vector2(tr * 0.5, -0.9), Vector2(tr, 0.0), Vector2(tr, 2.2), Vector2(tr, 2.2), Vector2(0.0, 2.2)]), 14)
		var turret := _part(b, mb.commit(), stone_mat, base)
		var det := Details.new()
		det.window(_around(a, tr, 1.2), 0.4, 0.9)
		det.attach(turret, stone_mat)
		mb = MeshBuilder.new()
		_hat_roof(mb, tr + 0.35, 2.4, 0.2, 14)
		_part(b, mb.commit(), Art.roof(_pick(rng, Art.ROOF_COLORS)), base + Vector3(0, 2.2, 0))

	var hat_h := rng.randf_range(4.2, 6.8)
	var mb2 := MeshBuilder.new()
	var start := _hat_roof(mb2, r + rng.randf_range(0.5, 0.9), hat_h, 0.45)
	mb2.bend(start, hat_h * 0.3, hat_h, Vector3(drift_dir.x, 0, drift_dir.z).normalized() * rng.randf_range(0.6, 1.8))
	_part(b, mb2.commit(), Art.roof(_pick(rng, Art.ROOF_COLORS)), drift + Vector3(0, y, 0))
	return y + hat_h


# --- Mushroom house -----------------------------------------------------------

static func _build_mushroom(b: Destructible, rng: RandomNumberGenerator) -> float:
	var r := rng.randf_range(1.5, 2.1)
	var h := rng.randf_range(3.0, 4.4)
	var stalk := Art.plaster(Color(0.88, 0.83, 0.70))
	var mb := MeshBuilder.new()
	mb.add_lathe(PackedVector2Array([Vector2(r * 1.3, -SINK), Vector2(r * 1.18, 0.0), Vector2(r * 0.98, h * 0.35),
		Vector2(r * 0.86, h * 0.75), Vector2(r * 0.95, h), Vector2(r * 0.95, h), Vector2(0.0, h)]), 20, Transform3D.IDENTITY, 5, 0.03)
	mb.ground_shade(0, 0.0, 1.4)
	var stem := _part(b, mb.commit(), stalk)
	var det := Details.new()
	det.arch_door(_around(0.0, r * 1.1, 0.0), 1.1, 2.0)
	det.round_window(_around(rng.randf_range(1.2, 2.2), r * 0.95, h * 0.5), 0.42)
	det.round_window(_around(rng.randf_range(-2.2, -1.2), r * 0.92, h * 0.62), 0.38)
	det.attach(stem, Art.stone(0))

	var cap_r := r * rng.randf_range(2.0, 2.6)
	var cap_h := cap_r * rng.randf_range(0.55, 0.8)
	var cap_color: Color = _pick(rng, Art.CAP_COLORS)
	var cap_mat := Art.surface("plaster", cap_color, cap_color.darkened(0.35), {"scale": 0.25, "roughness": 0.6})
	var profile := PackedVector2Array([Vector2(cap_r * 0.9, 0.08), Vector2(cap_r * 0.98, -0.02), Vector2(cap_r, 0.14), Vector2(cap_r * 0.96, cap_h * 0.32),
		Vector2(cap_r * 0.8, cap_h * 0.63), Vector2(cap_r * 0.52, cap_h * 0.88), Vector2(cap_r * 0.22, cap_h * 0.98), Vector2(0.0, cap_h)])
	mb = MeshBuilder.new()
	mb.add_lathe(profile, 26, Transform3D.IDENTITY, rng.randi_range(5, 7), 0.035)
	var tilt := Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
	var cap := _part(b, mb.commit(), cap_mat, Vector3(0, h - 0.15, 0), tilt)
	# Gills underneath and pale spots on top.
	var gills := MeshBuilder.new()
	gills.add_lathe(PackedVector2Array([Vector2(0.0, 0.5), Vector2(r * 0.9, 0.42), Vector2(cap_r * 0.9, 0.08)]), 26)
	_child(cap, gills.commit(), Art.surface("thatch", Color(0.80, 0.70, 0.55), Color(0.55, 0.45, 0.35), {"scale": 1.2}))
	var spots := MeshBuilder.new()
	for k in rng.randi_range(6, 11):
		var t := rng.randf_range(0.12, 0.85)
		var idx := 3 + int(t * 4.0)
		var p := profile[mini(idx, profile.size() - 1)].lerp(profile[mini(idx + 1, profile.size() - 1)], fposmod(t * 4.0, 1.0))
		var a := rng.randf() * TAU
		var sr := rng.randf_range(0.28, 0.55)
		var up := Vector3(cos(a) * p.x, p.y + 0.6 * cap_h, sin(a) * p.x).normalized()
		spots.add_blob(Vector3(sr, 0.12, sr), Transform3D(basis_y(up), Vector3(cos(a) * p.x, p.y, sin(a) * p.x)), null, 0.0, 5, 10)
	_child(cap, spots.commit(), Art.plaster(Color(0.93, 0.90, 0.80)))
	# Crooked stove pipe.
	if rng.randf() < 0.7:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * cap_r * 0.45 + Vector3(0, cap_h * 0.8, 0)
		var pipe := MeshBuilder.new()
		pipe.add_tube(PackedVector3Array([base - Vector3(0, 0.5, 0), base + Vector3(0, 0.9, 0), base + Vector3(cos(a) * 0.5, 1.5, sin(a) * 0.5)]),
			PackedFloat32Array([0.2, 0.19, 0.18]), 8)
		_child(cap, pipe.commit(), Art.timber())
	b.footprint = cap_r * 0.8
	return h + cap_h + 0.3


# --- Turf burrow --------------------------------------------------------------

static func _build_burrow(b: Destructible, rng: RandomNumberGenerator) -> float:
	var r := rng.randf_range(3.1, 4.1)
	var wall := rng.randf_range(1.5, 2.1)
	var stone_mat := Art.stone(rng.randi(), 0.6)
	b.footprint = r * 1.05
	var mb := MeshBuilder.new()
	mb.add_lathe(PackedVector2Array([Vector2(r * 1.06, -SINK), Vector2(r * 1.02, 0.3), Vector2(r * 0.97, wall), Vector2(r * 0.97, wall), Vector2(0.0, wall)]), 24)
	mb.ground_shade(0, 0.0, 1.2)
	var drum := _part(b, mb.commit(), stone_mat)
	var det := Details.new()
	det.arch_door(_around(0.0, r * 1.0, 0.0), 1.3, minf(2.0, wall + 0.35))
	for a in [rng.randf_range(0.9, 1.4), rng.randf_range(-1.4, -0.9), rng.randf_range(2.4, 3.6)]:
		det.round_window(_around(a, r * 0.99, wall * 0.62), 0.42)
	det.attach(drum, stone_mat)

	var dome := r * rng.randf_range(0.55, 0.85)
	var profile := PackedVector2Array([Vector2(r * 0.9, -0.1), Vector2(r * 1.13, -0.3), Vector2(r * 1.15, -0.12)])
	for k in range(1, 9):
		var t := k / 8.0 * PI * 0.5
		profile.append(Vector2(r * 1.15 * cos(t), -0.12 + dome * sin(t)))
	mb = MeshBuilder.new()
	mb.add_lathe(profile, 24, Transform3D.IDENTITY, 6, 0.03)
	var turf := Art.surface("ground", Art.GRASS_ROOT.lerp(Art.GRASS_TIP, 0.3), Art.GRASS_ROOT.lerp(Art.GRASS_TIP, 0.75), {"scale": 0.5, "roughness": 0.95})
	var roof := _part(b, mb.commit(), turf, Vector3(0, wall, 0))

	var a := rng.randf_range(1.5, 4.5)
	var base := Vector3(sin(a), 0, cos(a)) * r * 0.5 + Vector3(0, dome * 0.6, 0)
	var ch := rng.randf_range(1.8, 2.6)
	var tilt := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var chimney := MeshBuilder.new()
	chimney.add_tube(PackedVector3Array([base - Vector3(0, 0.6, 0), base + Vector3(0, ch * 0.5, 0) + tilt * 0.4, base + Vector3(0, ch, 0) + tilt]),
		PackedFloat32Array([0.5, 0.42, 0.36]), 8)
	chimney.add_box(Vector3(0.95, 0.22, 0.95), 0.06, Transform3D(Basis(), base + Vector3(0, ch, 0) + tilt))
	_child(roof, chimney.commit(), stone_mat)
	return wall + maxf(dome, dome * 0.6 + ch)


# --- Gourd house --------------------------------------------------------------

static func _build_gourd(b: Destructible, rng: RandomNumberGenerator) -> float:
	var r := rng.randf_range(2.7, 3.5)
	var color: Color = _pick(rng, Art.GOURD_COLORS)
	var skin := Art.surface("plaster", color, color.darkened(0.3), {"scale": 0.22, "roughness": 0.55})
	var lobes := rng.randi_range(8, 11)
	b.footprint = r
	var y := 0.0
	var offset := Vector3.ZERO
	var top_r := r
	var top_offset := Vector3.ZERO
	var count := 1 if rng.randf() < 0.65 else 2
	for g in count:
		var squash := rng.randf_range(0.72, 0.95)
		var gh := r * 2.0 * squash
		var sink := SINK * 0.7 if g == 0 else gh * 0.12
		var profile := PackedVector2Array()
		for k in 13:
			var phi := lerpf(0.12, 1.0, k / 12.0) * PI
			profile.append(Vector2(r * sin(phi) + 0.02, r * squash * (1.0 - cos(phi)) - sink))
		profile[12] = Vector2(0.0, profile[12].y - 0.25)
		var mb := MeshBuilder.new()
		mb.add_lathe(profile, 32, Transform3D.IDENTITY, lobes, 0.06)
		if g == 0:
			mb.ground_shade(0, 0.0, 1.5)
		var body := _part(b, mb.commit(), skin, offset + Vector3(0, y, 0), Vector3(rng.randf_range(-0.06, 0.06), rng.randf() * TAU / lobes, rng.randf_range(-0.06, 0.06)))
		var det := Details.new()
		# The piece is turned a little, so undo that for the door to face front.
		var front := -body.rotation.y
		if g == 0:
			det.arch_door(_around(front, _lathe_radius(profile, 1.0) * 0.99, 0.0), 1.2, 2.1)
		det.round_window(_around(front + rng.randf_range(0.9, 1.5), _lathe_radius(profile, gh * 0.5 - sink) * 0.97, gh * 0.5 - sink), 0.45)
		det.round_window(_around(front - rng.randf_range(0.9, 1.5), _lathe_radius(profile, gh * 0.55 - sink) * 0.97, gh * 0.55 - sink), 0.45)
		det.attach(body, Art.stone(1))
		y += gh - sink - 0.25
		top_r = r
		top_offset = offset
		r *= rng.randf_range(0.55, 0.7)
		offset += Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))

	# Curly stem.
	var stem_h := top_r * rng.randf_range(0.7, 1.1)
	var curl := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * stem_h * 0.6
	var path := PackedVector3Array([Vector3(0, -0.4, 0), Vector3(0, stem_h * 0.4, 0) + curl * 0.1, Vector3(0, stem_h * 0.8, 0) + curl * 0.45,
		Vector3(0, stem_h, 0) + curl * 0.9, Vector3(0, stem_h * 0.85, 0) + curl * 1.3])
	var mb2 := MeshBuilder.new()
	mb2.add_tube(path, PackedFloat32Array([top_r * 0.2, top_r * 0.13, top_r * 0.1, top_r * 0.08, top_r * 0.05]), 10)
	_part(b, mb2.commit(), Art.surface("bark", Color(0.30, 0.36, 0.14), Color(0.20, 0.22, 0.10)), top_offset + Vector3(0, y, 0))
	return y + stem_h


# --- Helpers ------------------------------------------------------------------

## A basis whose Y axis points along `dir`.
static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


## A spot on one wall of a w x d box, facing outwards.
## face: 0 = front (+Z), 1 = back, 2 = right (+X), 3 = left.
static func _face(face: int, w: float, d: float, along: float, y: float) -> Transform3D:
	match face:
		0:
			return Transform3D(Basis(), Vector3(along, y, d * 0.5))
		1:
			return Transform3D(Basis(Vector3.UP, PI), Vector3(along, y, -d * 0.5))
		2:
			return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, y, along))
		_:
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, y, along))


## A spot on a round wall at `angle` (0 = front), facing outwards.
static func _around(angle: float, radius: float, y: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, angle), Vector3(sin(angle) * radius, y, cos(angle) * radius))


## Radius of a lathe profile at height y.
static func _lathe_radius(profile: PackedVector2Array, y: float) -> float:
	for k in profile.size() - 1:
		var a := profile[k]
		var c := profile[k + 1]
		if (a.y <= y and c.y >= y) and c.y > a.y:
			return lerpf(a.x, c.x, (y - a.y) / (c.y - a.y))
	return profile[0].x


static func _pick(rng: RandomNumberGenerator, options: Array) -> Color:
	return options[rng.randi() % options.size()]


## Adds a structural piece that becomes debris when the building breaks.
static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.set_meta("debris", true)
	parent.add_child(mi)
	return mi


## Adds a decoration that rides along with its parent piece.
static func _child(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _add_collider(node: Node3D, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.2)
	shape.height = maxf(height, 0.5)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = height * 0.5
	body.add_child(cs)
	node.add_child(body)
