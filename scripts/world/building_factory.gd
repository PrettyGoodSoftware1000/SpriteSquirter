class_name BuildingFactory
extends RefCounted
## Generates the game's surreal buildings, modelled on the concept art in
## docs/ART_STYLE.md: the tall house, crystal tower, moon tower, mushroom
## house, singing rocks, store-in-a-tree and winged windmill for villagers,
## plus the goblin hut and cave.
##
## Each building is a Destructible made of big structural pieces (tagged
## with the "debris" meta so they fly apart when destroyed). Windows, doors
## and beams are merged into a few detail meshes that ride along with the
## piece they sit on. Shapes are coloured with MeshBuilder.color on white
## "paint" materials. The same RNG seed always gives the same building.

const STOREY := 2.7
const SINK := 1.3 # how far ground floors reach below the surface


## Collects the small details of one structural piece, grouped by material.
class Details:
	var timber := MeshBuilder.new()
	var glass := MeshBuilder.new()
	var wood := MeshBuilder.new()
	var stone := MeshBuilder.new()

	func attach(part: Node3D) -> void:
		_add(part, timber, Art.timber())
		_add(part, glass, Art.glass())
		_add(part, wood, Art.wood())
		_add(part, stone, Art.paint("stone", 0.0))

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

const VILLAGE_KINDS := ["tall_house", "tall_house", "crystal_tower", "moon_tower", "mushroom_house",
	"singing_rocks", "store", "windmill"]


## A random building that villagers build.
static func create_building(rng: RandomNumberGenerator) -> Destructible:
	return create(VILLAGE_KINDS[rng.randi() % VILLAGE_KINDS.size()], rng)


static func create(kind: String, rng: RandomNumberGenerator) -> Destructible:
	var b := Destructible.new()
	b.name = kind.capitalize()
	b.set_meta("kind", kind)
	b.is_building = true
	var top := 0.0
	match kind:
		"tall_house":
			top = _build_tall_house(b, rng)
		"crystal_tower":
			top = _build_crystal_tower(b, rng)
		"moon_tower":
			top = _build_moon_tower(b, rng)
		"mushroom_house":
			top = _build_mushroom_house(b, rng)
		"singing_rocks":
			top = _build_singing_rocks(b, rng)
		"store":
			top = _build_store(b, rng)
		"windmill":
			top = _build_windmill(b, rng)
		_:
			top = _build_goblin_hut(b, rng)
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
		if child is StaticBody3D or child is CPUParticles3D:
			child.queue_free()
			continue
		if child is MeshInstance3D:
			child.material_override = ghost_material
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		make_ghost(child, ghost_material)


# --- Shared pieces ------------------------------------------------------------

## A little plank house (one wall piece and one roof piece) used by several
## buildings. Returns the height of its roof peak above `pos`.
static func _mini_house(b: Node3D, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: Vector3,
		wall: Color, roof: Color, sink := 0.0, door := true) -> float:
	var mb := MeshBuilder.new()
	mb.color = wall
	mb.add_box(Vector3(size.x, size.y + sink, size.z), 0.14, Transform3D(Basis(), Vector3(0, (size.y - sink) * 0.5, 0)), Vector2(0.94, 0.94))
	var tilt := Vector3(rng.randf_range(-0.05, 0.05), yaw, rng.randf_range(-0.05, 0.05))
	var part := _part(b, mb.commit(), Art.paint("planks"), pos, tilt)
	var det := Details.new()
	_timber_frame(det, rng, size.x * 0.97, size.y, size.z * 0.97)
	if door:
		det.door(Transform3D(Basis(), Vector3(-size.x * 0.18, 0.0, size.z * 0.48)), 0.95, 1.9)
		det.window(_face(0, size.x, size.z * 0.96, size.x * 0.24, size.y * 0.58), 0.7, 0.8, true)
	else:
		det.window(_face(0, size.x, size.z * 0.96, 0.0, size.y * 0.55), 0.8, 0.9, true)
	det.window(_face(2, size.x * 0.96, size.z, 0.0, size.y * 0.55), 0.7, 0.8)
	det.window(_face(3, size.x * 0.96, size.z, 0.0, size.y * 0.55), 0.7, 0.8)
	det.attach(part)
	var rh := size.z * rng.randf_range(0.7, 1.0)
	mb = MeshBuilder.new()
	mb.color = roof
	_gable_roof(mb, size.x, size.z, rh, 0.45, rng.randf_range(0.05, 0.25), rng.randf_range(0.15, 0.45))
	mb.color = wall
	_gable_walls(mb, size.x, size.z, rh, 0.45)
	# The roof leans exactly as the walls do, so they cannot cut through it.
	_part(b, mb.commit(), Art.paint("shingles"), pos + Basis.from_euler(tilt) * Vector3(0, size.y, 0), tilt)
	return size.y + rh + ROOF_LIFT


static func _timber_frame(det: Details, rng: RandomNumberGenerator, w: float, h: float, d: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			det.beam(Vector3(sx * x, 0, sz * z), Vector3(sx * x, h, sz * z), 0.24)
	for yy in [0.08, h - 0.08]:
		det.beam(Vector3(-x, yy, z), Vector3(x, yy, z), 0.22)
		det.beam(Vector3(-x, yy, -z), Vector3(x, yy, -z), 0.22)
		det.beam(Vector3(x, yy, -z), Vector3(x, yy, z), 0.22)
		det.beam(Vector3(-x, yy, -z), Vector3(-x, yy, z), 0.22)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			if rng.randf() < 0.6:
				det.beam(Vector3(sx * x, h * 0.05, sz * (z + 0.02)), Vector3(sx * (x - h * 0.4), h * 0.95, sz * (z + 0.02)), 0.15)


## A solid gable roof with its ridge along X: curved slopes, a sagging ridge
## and upturned ends.
## How far a gable roof sits above the top of its walls, so that wall tops
## and beams never poke through the slope near the eaves.
const ROOF_LIFT := 0.35


static func _gable_roof(mb: MeshBuilder, w: float, d: float, h: float, overhang: float, sag: float, flare: float) -> void:
	var half_len := w * 0.5 + overhang
	var half_span := d * 0.5 + overhang
	for side in [-1.0, 1.0]:
		var s: float = side
		var top := func(u: float, v: float) -> Vector3:
			var end := absf(u * 2.0 - 1.0)
			var yy := ROOF_LIFT - 0.4 + (h + 0.4) * pow(v, 1.3) - sag * sin(u * PI) * v + flare * end * end * (0.35 + 0.65 * v)
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
			pts.append(Vector3(x, ROOF_LIFT - 0.4 + (h + 0.4) * pow(v, 1.3) - 0.3, z))
		pts.append(Vector3(x, -0.05, d * 0.5 - 0.1))
		mb.add_fan(pts, Vector3(side, 0, 0))


## A pointed hat roof. Returns the index of its first vertex so the caller
## can bend the tip.
static func _hat_roof(mb: MeshBuilder, radius: float, h: float, droop: float, segments := 20, lobes := 0) -> int:
	var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(radius * 0.9, -droop * 0.8), Vector2(radius, -droop), Vector2(radius, -droop)])
	for k in range(1, 11):
		var t := k / 10.0
		profile.append(Vector2(radius * pow(1.0 - t, 1.55), -droop + (h + droop) * t))
	return mb.add_lathe(profile, segments, Transform3D.IDENTITY, lobes, 0.07)


## A bent, striped, pointed hat (the tall house's candy-cane chimney).
static func _striped_hat(mb: MeshBuilder, radius: float, h: float, bend: Vector3, a: Color, c: Color) -> void:
	var from := mb.verts.size()
	var bands := 9
	for k in bands:
		var t0 := k / float(bands)
		var t1 := (k + 1) / float(bands)
		mb.color = a if k % 2 == 0 else c
		mb.add_lathe(PackedVector2Array([Vector2(radius * (1.0 - t0 * 0.92), h * t0), Vector2(radius * (1.0 - t1 * 0.92), h * t1)]), 12)
	mb.bend(from, h * 0.25, h, bend)


## A mushroom: bent stalk and spotted cap, added to two builders.
static func _mushroom(stalks: MeshBuilder, caps: MeshBuilder, rng: RandomNumberGenerator, base: Vector3, lean: Vector3,
		h: float, cap_r: float, cap_color: Color, spot_color: Color) -> void:
	var top := base + Vector3(0, h, 0) + lean
	stalks.color = Color(0.92, 0.86, 0.70)
	stalks.add_tube(PackedVector3Array([base - Vector3(0, 0.4, 0), base + Vector3(0, h * 0.5, 0) + lean * 0.25, top]),
		PackedFloat32Array([cap_r * 0.3, cap_r * 0.22, cap_r * 0.26]), 10)
	var tilt := Basis(Vector3(lean.z, 0, -lean.x).normalized(), lean.length() * 0.25) if lean.length() > 0.05 else Basis()
	var xf := Transform3D(tilt, top - Vector3(0, cap_r * 0.12, 0))
	var cap_h := cap_r * 0.75
	caps.color = cap_color
	caps.add_lathe(PackedVector2Array([Vector2(0.0, 0.28 * cap_h), Vector2(cap_r * 0.9, 0.05), Vector2(cap_r, 0.1), Vector2(cap_r * 0.95, cap_h * 0.35),
		Vector2(cap_r * 0.75, cap_h * 0.7), Vector2(cap_r * 0.4, cap_h * 0.93), Vector2(0.0, cap_h)]), 18, xf, 6, 0.03)
	caps.color = spot_color
	for k in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var t := rng.randf_range(0.25, 0.8)
		var p := Vector3(cos(a) * cap_r * t, cap_h * (1.0 - t * t * 0.75), sin(a) * cap_r * t)
		var sr := cap_r * rng.randf_range(0.1, 0.17)
		caps.add_blob(Vector3(sr, sr * 0.3, sr), xf * Transform3D(basis_y(Vector3(p.x * 0.6, cap_r, p.z * 0.6)), p), null, 0.0, 4, 8)


# --- Tall house ---------------------------------------------------------------

## A crooked plank tower-house with a steep roof, a striped bent chimney
## hat, a lean-to at its side and a string of flags.
static func _build_tall_house(b: Destructible, rng: RandomNumberGenerator) -> float:
	var wall := Color.from_hsv(rng.randf_range(0.5, 0.62), 0.62, 0.72)
	var roof := Color.from_hsv(rng.randf_range(0.04, 0.1), 0.85, 0.9)
	var w := rng.randf_range(3.6, 4.2)
	b.footprint = w * 0.95
	var mb := MeshBuilder.new()
	mb.color = Color(0.56, 0.54, 0.52)
	mb.add_box(Vector3(w + 0.8, 1.1 + SINK, w + 0.8), 0.25, Transform3D(Basis(), Vector3(0, (1.1 - SINK) * 0.5, 0)))
	_part(b, mb.commit(), Art.paint("stone"))
	var y := 1.1
	var twist := 0.0
	var lean := Vector3.ZERO
	var floors := rng.randi_range(2, 3)
	for f in floors:
		var fh := rng.randf_range(2.7, 3.2)
		mb = MeshBuilder.new()
		mb.color = wall if f % 2 == 0 else wall.lightened(0.15)
		mb.add_box(Vector3(w, fh, w), 0.12, Transform3D(Basis(), Vector3(0, fh * 0.5, 0)), Vector2(1.06, 1.06))
		var part := _part(b, mb.commit(), Art.paint("planks"), lean + Vector3(0, y, 0), Vector3(0, twist, 0))
		var det := Details.new()
		_timber_frame(det, rng, w * 1.02, fh, w * 1.02)
		if f == 0:
			det.door(Transform3D(Basis(), Vector3(0.0, 0.0, w * 0.5)), 1.0, 2.0)
		else:
			det.window(_face(0, w, w, 0.0, fh * 0.55), 0.8, 1.2, true)
		det.window(_face(2, w, w, 0.0, fh * 0.55), 0.7, 1.0)
		det.window(_face(3, w, w, 0.0, fh * 0.55), 0.7, 1.0)
		det.attach(part)
		y += fh
		if f < floors - 1:
			# Each floor sits askew on the one below; the roof sits square on the top one.
			twist += rng.randf_range(-0.16, 0.16)
			lean += Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		w *= 1.05
	var rh := rng.randf_range(3.2, 4.2)
	mb = MeshBuilder.new()
	mb.color = roof
	_gable_roof(mb, w, w, rh, 0.5, 0.2, 0.6)
	mb.color = wall
	_gable_walls(mb, w, w, rh, 0.5)
	_part(b, mb.commit(), Art.paint("planks"), lean + Vector3(0, y, 0), Vector3(0, twist, 0))
	# Striped chimney hat.
	var hat_h := rng.randf_range(3.0, 4.0)
	mb = MeshBuilder.new()
	_striped_hat(mb, 0.75, hat_h, Vector3(rng.randf_range(0.8, 1.6), -0.5, rng.randf_range(-0.6, 0.6)), Color(0.86, 0.14, 0.12), Color(0.96, 0.94, 0.9))
	_part(b, mb.commit(), Art.paint("plaster"), lean + Vector3(0, y + rh * 0.8, 0))
	# Lean-to and flags.
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	_mini_house(b, rng, Vector3(side * (w * 0.5 + 1.2), 1.0, 0.4), 0.0, Vector3(2.4, 2.3, 2.8), Color(0.86, 0.5, 0.16), Color(0.5, 0.58, 0.24), 2.0, false)
	var flags := MeshBuilder.new()
	var pole_a := lean + Vector3(-side * w * 0.5, y - 0.5, w * 0.3)
	var pole_b := pole_a + Vector3(-side * 2.2, 0.5, 0.6)
	flags.color = Art.TIMBER
	flags.add_tube(PackedVector3Array([pole_a, pole_b]), PackedFloat32Array([0.07, 0.05]), 5)
	for k in 3:
		flags.color = Art.CLOTH_COLORS[rng.randi() % Art.CLOTH_COLORS.size()]
		flags.add_box(Vector3(0.5, 0.8, 0.05), 0.02, Transform3D(Basis(Vector3.UP, 0.3), pole_a.lerp(pole_b, 0.3 + k * 0.3) - Vector3(0, 0.5, 0)))
	_part(b, flags.commit(), Art.paint("plaster", 0.0))
	return y + rh + hat_h * 0.7


# --- Crystal tower ------------------------------------------------------------

## A lavender stone tower with side turrets, crowned by a giant glowing
## crystal, with glowing mushrooms growing around its foot.
static func _build_crystal_tower(b: Destructible, rng: RandomNumberGenerator) -> float:
	var stone := Color.from_hsv(rng.randf_range(0.68, 0.76), 0.3, 0.78)
	var roof := Color.from_hsv(rng.randf_range(0.72, 0.8), 0.6, 0.6)
	var ice := Color.from_hsv(rng.randf_range(0.5, 0.56), 0.5, 1.0)
	var r := rng.randf_range(2.3, 2.8)
	b.footprint = r * 1.5
	var y := 0.0
	var drift := Vector3.ZERO
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.3
	for s in 3:
		var sh := rng.randf_range(3.2, 4.0)
		var sink := SINK if s == 0 else 0.0
		var r_top := r * 0.84
		var mb := MeshBuilder.new()
		mb.color = stone if s != 1 else stone.darkened(0.12)
		mb.add_lathe(PackedVector2Array([Vector2(r * 1.08, -sink), Vector2(r, sh * 0.2), Vector2(r_top, sh - 0.3), Vector2(r_top + 0.2, sh - 0.2),
			Vector2(r_top + 0.2, sh), Vector2(r_top + 0.2, sh), Vector2(0.0, sh)]), 20)
		var part := _part(b, mb.commit(), Art.paint("stone"), drift + Vector3(0, y, 0), Vector3(dir.z * 0.1, 0, -dir.x * 0.1))
		var det := Details.new()
		if s == 0:
			det.arch_door(_around(0.0, r * 1.02, 0.0), 1.3, 2.4)
		for k in 2:
			det.window(_around(rng.randf() * TAU if s > 0 else 2.0 + k * 2.2, (r + r_top) * 0.5, sh * 0.55), 0.55, 1.2)
		det.attach(part)
		y += sh
		drift += dir
		r = r_top
	# Roof skirt and the crystal.
	var mb2 := MeshBuilder.new()
	mb2.color = roof
	_hat_roof(mb2, r + 1.0, 2.4, 0.5, 18, 8)
	_part(b, mb2.commit(), Art.paint("shingles"), drift + Vector3(0, y, 0))
	var crystal := MeshBuilder.new()
	crystal.color = ice
	var ch := rng.randf_range(5.0, 6.5)
	crystal.add_lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.2, 0.8), Vector2(1.45, ch * 0.55), Vector2(0.0, ch)]), 6, Transform3D.IDENTITY, 0, 0.0, true)
	for k in 3:
		var a := rng.randf() * TAU
		crystal.add_lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.45, 0.4), Vector2(0.5, 1.3), Vector2(0.0, 2.4)]), 6,
			Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.5), Vector3(sin(a), 0.3, -cos(a)) * 0.9), 0, 0.0, true)
	_part(b, crystal.commit(), Art.glow(0.9), drift + Vector3(0, y + 1.2, 0), Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08)))
	# Side turrets.
	for k in rng.randi_range(2, 3):
		var a := rng.randf() * TAU
		var base := Vector3(sin(a), 0, cos(a)) * (r + 1.5) + Vector3(0, rng.randf_range(1.5, y * 0.6), 0) + drift * 0.4
		var mb := MeshBuilder.new()
		mb.color = stone.lightened(0.1)
		mb.add_lathe(PackedVector2Array([Vector2(0.0, -1.6), Vector2(0.5, -1.0), Vector2(0.9, 0.0), Vector2(0.9, 2.4), Vector2(0.9, 2.4), Vector2(0.0, 2.4)]), 12)
		var turret := _part(b, mb.commit(), Art.paint("stone"), base)
		var det := Details.new()
		det.window(_around(a, 0.9, 1.3), 0.4, 0.9)
		det.attach(turret)
		mb = MeshBuilder.new()
		mb.color = roof
		_hat_roof(mb, 1.3, 2.6, 0.2, 12)
		_part(b, mb.commit(), Art.paint("shingles"), base + Vector3(0, 2.4, 0))
	# Glowing mushrooms at the foot.
	var stalks := MeshBuilder.new()
	var caps := MeshBuilder.new()
	for k in rng.randi_range(4, 6):
		var a := rng.randf() * TAU
		var base := Vector3(sin(a), 0, cos(a)) * (b.footprint * rng.randf_range(0.75, 1.0))
		_mushroom(stalks, caps, rng, base, Vector3(sin(a), 0, cos(a)) * 0.3, rng.randf_range(0.8, 1.6), rng.randf_range(0.45, 0.8), ice, Color(1, 1, 1))
	var shrooms := _part(b, caps.commit(), Art.glow(0.7))
	_child(shrooms, stalks.commit(), Art.paint("plaster", 0.5))
	return y + ch + 1.2


# --- Moon tower ---------------------------------------------------------------

## A squat stone observatory with a melting pastel crescent moon on top,
## brass telescopes and gems set into the walls.
static func _build_moon_tower(b: Destructible, rng: RandomNumberGenerator) -> float:
	var stone := Color(0.66, 0.66, 0.74)
	var r := rng.randf_range(2.9, 3.4)
	var h := rng.randf_range(6.0, 7.5)
	b.footprint = r * 1.25
	var mb := MeshBuilder.new()
	mb.color = Color(0.56, 0.32, 0.66)
	for k in 7:
		var a := TAU * k / 7.0
		mb.add_blob(Vector3(1.3, 0.8, 1.3), Transform3D(Basis(), Vector3(sin(a), 0, cos(a)) * r * 1.05), null, 0.0, 5, 8)
	mb.color = stone
	mb.add_lathe(PackedVector2Array([Vector2(r * 1.1, -SINK), Vector2(r, 0.6), Vector2(r * 0.8, h - 0.9), Vector2(r * 0.92, h - 0.8), Vector2(r * 0.92, h),
		Vector2(r * 0.92, h), Vector2(0.0, h)]), 22)
	for k in 8:
		var a := TAU * k / 8.0
		mb.add_box(Vector3(0.8, 0.7, 0.5), 0.08, Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * r * 0.86 + Vector3(0, h + 0.3, 0)))
	var body := _part(b, mb.commit(), Art.paint("stone"))
	var det := Details.new()
	det.arch_door(_around(0.0, r * 0.98, 0.0), 1.3, 2.3)
	det.window(_around(1.2, r * 0.9, h * 0.5), 0.6, 1.3)
	det.window(_around(-1.3, r * 0.88, h * 0.6), 0.6, 1.3)
	det.attach(body)
	# Telescopes and gems.
	var brass := MeshBuilder.new()
	var gems := MeshBuilder.new()
	for k in rng.randi_range(2, 3):
		var a := rng.randf_range(0.6, TAU - 0.6)
		var out := Vector3(sin(a), 0, cos(a))
		var from := out * r * 0.8 + Vector3(0, h * rng.randf_range(0.55, 0.85), 0)
		brass.color = Color(0.78, 0.56, 0.2)
		brass.add_tube(PackedVector3Array([from, from + out * 1.4 + Vector3(0, 0.5, 0), from + out * 2.6 + Vector3(0, 1.0, 0)]), PackedFloat32Array([0.22, 0.3, 0.42]), 10)
	for k in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var yy := rng.randf_range(0.8, h - 1.5)
		gems.color = Color.from_hsv(rng.randf(), 0.6, 1.0)
		gems.add_lathe(PackedVector2Array([Vector2(0.0, -0.3), Vector2(0.24, 0.0), Vector2(0.0, 0.3)]), 5,
			Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI * 0.5), _around(a, lerpf(r, r * 0.8, yy / h) + 0.05, yy).origin), 0, 0.0, true)
	_child(body, brass.commit(), Art.paint("plaster", 0.6))
	_child(body, gems.commit(), Art.glow(1.0))
	# The crescent moon, its drips and the puddle at the foot of the tower.
	var moon := MeshBuilder.new()
	var mr := r * 1.0
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in 25:
		var t := k / 24.0
		var a := deg_to_rad(lerpf(50.0, 310.0, t))
		pts.append(Vector3(cos(a), sin(a), 0.0) * mr)
		radii.append(mr * 0.5 * pow(sin(t * PI), 0.7) + 0.04)
	var from := moon.add_tube(pts, radii, 12, Transform3D(Basis().scaled(Vector3(1, 1, 0.6)), Vector3.ZERO))
	var pastel := [Color(0.62, 0.92, 0.96), Color(0.74, 0.64, 0.98), Color(0.98, 0.96, 0.62), Color(0.62, 0.96, 0.78)]
	for k in range(from, moon.verts.size()):
		var t := (moon.verts[k].y / mr + 1.0) * 1.5
		moon.colors[k] = pastel[int(t) % 4].lerp(pastel[(int(t) + 1) % 4], fposmod(t, 1.0))
	for k in 4:
		var x := rng.randf_range(-mr * 0.8, mr * 0.2)
		var top := Vector3(x, -sqrt(maxf(mr * mr - x * x, 0.0)) + 0.2, 0.0)
		moon.color = pastel[k]
		moon.add_tube(PackedVector3Array([top, top - Vector3(0, rng.randf_range(0.8, 2.2), 0)]), PackedFloat32Array([0.22, 0.1]), 6)
	_part(b, moon.commit(), Art.glow(0.6), Vector3(0, h + mr * 1.15, 0), Vector3(0, rng.randf_range(-0.4, 0.4), 0.25))
	var puddle := MeshBuilder.new()
	for k in 5:
		puddle.color = pastel[k % 4]
		puddle.add_blob(Vector3(rng.randf_range(1.0, 1.8), 0.12, rng.randf_range(0.8, 1.4)),
			Transform3D(Basis(), Vector3(rng.randf_range(-1.5, 1.5), 0.06, r + rng.randf_range(0.3, 1.6))), null, 0.0, 4, 10)
	_child(body, puddle.commit(), Art.glow(0.5))
	return h + mr * 2.2


# --- Mushroom house -----------------------------------------------------------

## A six-sided timber cabin with a cluster of giant mushrooms growing
## out of its roof.
static func _build_mushroom_house(b: Destructible, rng: RandomNumberGenerator) -> float:
	var r := rng.randf_range(3.0, 3.6)
	var h := 2.3
	var cap := Color.from_hsv(fposmod(rng.randf_range(0.9, 1.02), 1.0), 0.72, 0.56)
	b.footprint = r * 1.15
	var mb := MeshBuilder.new()
	mb.color = Color(0.2, 0.56, 0.52)
	mb.add_lathe(PackedVector2Array([Vector2(r, -SINK), Vector2(r, h), Vector2(r, h), Vector2(r * 1.12, h + 0.1), Vector2(r * 0.5, h + 1.0), Vector2(0.0, h + 1.1)]), 6, Transform3D.IDENTITY, 0, 0.0, true)
	var base := _part(b, mb.commit(), Art.paint("planks"))
	var det := Details.new()
	for k in 6:
		var a := TAU * k / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * r
		det.beam(p, p + Vector3(0, h, 0), 0.28)
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0 + PI * 0.5
		var xf := _around(a, r * 0.866, 0.0)
		if k == 0:
			det.door(xf, 1.0, 1.9)
		elif k % 2 == 0:
			det.window(xf.translated_local(Vector3(0, h * 0.55, 0)), 0.8, 0.9, true)
	det.attach(base)
	var stalks := MeshBuilder.new()
	var caps := MeshBuilder.new()
	var big_h := rng.randf_range(4.2, 5.4)
	var big_r := r * rng.randf_range(1.0, 1.2)
	_mushroom(stalks, caps, rng, Vector3(0, h + 0.6, 0), Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)), big_h, big_r, cap, Color(0.95, 0.9, 0.72))
	var main := _part(b, caps.commit(), Art.paint("plaster"))
	_child(main, stalks.commit(), Art.paint("plaster", 0.6))
	for k in rng.randi_range(3, 4):
		var a := TAU * k / 4.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0, sin(a))
		stalks = MeshBuilder.new()
		caps = MeshBuilder.new()
		_mushroom(stalks, caps, rng, out * r * 0.55 + Vector3(0, h + 0.3, 0), out * rng.randf_range(1.2, 2.0), rng.randf_range(1.2, 2.6), rng.randf_range(1.0, 1.5), cap, Color(0.95, 0.9, 0.72))
		var small := _part(b, caps.commit(), Art.paint("plaster"))
		_child(small, stalks.commit(), Art.paint("plaster", 0.6))
	return h + 0.6 + big_h + big_r * 0.7


# --- Singing rocks ------------------------------------------------------------

## A heap of mossy boulders with glowing faces and runes, and a little door.
static func _build_singing_rocks(b: Destructible, rng: RandomNumberGenerator) -> float:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.4
	var rocks := [MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new()]
	var faces := [MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new()]
	var glows := [Color(0.3, 0.98, 0.92), Color(0.98, 0.5, 0.82), Color(0.6, 0.98, 0.5)]
	var top := 0.0
	var layers := [[6, 3.3, 1.5], [4, 2.0, 4.0], [1, 0.0, 6.2]]
	for l in 3:
		var count: int = layers[l][0]
		for k in count:
			var a := TAU * k / count + rng.randf_range(-0.2, 0.2) + l * 0.5
			var out := Vector3(sin(a), 0, cos(a))
			var size := Vector3(rng.randf_range(1.6, 2.1), rng.randf_range(1.5, 2.0), rng.randf_range(1.6, 2.1)) * (1.0 if l < 2 else 1.15)
			var ring: float = layers[l][1]
			var layer_y: float = layers[l][2]
			var c := out * ring + Vector3(0, layer_y + rng.randf_range(-0.3, 0.3), 0)
			var rock: MeshBuilder = rocks[l]
			rock.color = Color.from_hsv(rng.randf_range(0.2, 0.45), rng.randf_range(0.08, 0.2), rng.randf_range(0.6, 0.78))
			rock.add_blob(size, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c), noise, 0.12, 8, 12)
			top = maxf(top, c.y + size.y)
			if l == 0 and k == 0:
				continue
			# A glowing face: two eyes and a smile, looking outwards.
			var look := (out + Vector3(0, 0.25, 0)).normalized() if l < 2 else Vector3(0, 0.3, 1).normalized()
			var xf := Transform3D(Basis.looking_at(-look, Vector3.UP), c + look * size.x * 0.98)
			var face: MeshBuilder = faces[l]
			face.color = glows[rng.randi() % 3]
			var s := size.x * 0.42
			var happy := rng.randf() < 0.75
			for sx in [-1.0, 1.0]:
				face.add_blob(Vector3(s * 0.16, s * (0.08 if happy else 0.2), 0.08), xf.translated_local(Vector3(sx * s * 0.42, s * 0.3, 0)), null, 0.0, 4, 8)
			var smile := PackedVector3Array()
			for m in 7:
				var t := m / 3.0 - 1.0
				smile.append(xf * Vector3(t * s * 0.55, -s * 0.38 + s * 0.26 * t * t * (1.0 if happy else 0.2), 0.03 - 0.1 * t * t))
			face.add_tube(smile, PackedFloat32Array([0.05, 0.08, 0.1, 0.1, 0.1, 0.08, 0.05]), 5)
	b.footprint = 5.0
	for l in 3:
		var part := _part(b, (rocks[l] as MeshBuilder).commit(), Art.surface("rock", Color(1, 1, 1), Color(0.86, 0.86, 0.86), {"moss": 1.0}))
		_child(part, (faces[l] as MeshBuilder).commit(), Art.glow(1.3))
		if l == 0:
			var det := Details.new()
			det.arch_door(_around(0.0, 5.05, 0.0), 1.2, 2.1)
			det.attach(part)
	return top


# --- Store in a tree ----------------------------------------------------------

## Little shops huddled round a twisting tree trunk, with a treehouse
## restaurant on a platform above and a crow's-nest hut on top.
static func _build_store(b: Destructible, rng: RandomNumberGenerator) -> float:
	b.footprint = 5.6
	var h := rng.randf_range(8.0, 9.5)
	var wobble := Vector3(rng.randf_range(0.6, 1.1), 0, rng.randf_range(-0.6, 0.6))
	var mb := MeshBuilder.new()
	mb.color = Color(0.5, 0.34, 0.2)
	mb.add_tube(PackedVector3Array([Vector3(0, -1.2, 0), Vector3(0, 0.4, 0), wobble + Vector3(0, h * 0.3, 0), -wobble * 0.8 + Vector3(0, h * 0.55, 0),
		wobble * 0.5 + Vector3(0, h * 0.8, 0), Vector3(0, h, 0)]), PackedFloat32Array([2.0, 1.5, 1.15, 1.0, 0.95, 1.1]), 12)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf()
		mb.add_tube(PackedVector3Array([Vector3(cos(a), 0, sin(a)) * 0.8 + Vector3(0, 0.9, 0), Vector3(cos(a), 0, sin(a)) * 2.2 + Vector3(0, 0.2, 0),
			Vector3(cos(a), 0, sin(a)) * 3.2 + Vector3(0, -0.6, 0)]), PackedFloat32Array([0.5, 0.36, 0.2]), 7)
	_part(b, mb.commit(), Art.paint("bark"))
	var walls := [Color(0.9, 0.74, 0.24), Color(0.22, 0.6, 0.62), Color(0.82, 0.3, 0.22), Color(0.36, 0.5, 0.82), Color(0.62, 0.8, 0.3)]
	var roofs := [Color(0.82, 0.26, 0.16), Color(0.24, 0.44, 0.7), Color(0.94, 0.6, 0.14), Color(0.5, 0.3, 0.62)]
	var first := rng.randi()
	for k in 3:
		var a: float = [0.75, -0.75, PI][k] + rng.randf_range(-0.15, 0.15)
		var pos := Vector3(sin(a), 0, cos(a)) * 3.3
		_mini_house(b, rng, pos, a, Vector3(rng.randf_range(2.8, 3.3), rng.randf_range(2.3, 2.8), 2.6), walls[(first + k) % 5], roofs[(first + k) % 4], SINK)
	# Platform, restaurant and crow's nest.
	mb = MeshBuilder.new()
	mb.color = Color(0.66, 0.46, 0.26)
	mb.add_lathe(PackedVector2Array([Vector2(0.0, -0.5), Vector2(2.6, -0.3), Vector2(3.4, 0.0), Vector2(3.4, 0.25), Vector2(3.4, 0.25), Vector2(0.0, 0.25)]), 10, Transform3D.IDENTITY, 0, 0.0, true)
	for k in 10:
		var a := TAU * k / 10.0
		mb.add_tube(PackedVector3Array([Vector3(cos(a), 0, sin(a)) * 3.3 + Vector3(0, 0.2, 0), Vector3(cos(a), 0, sin(a)) * 3.3 + Vector3(0, 1.1, 0)]), PackedFloat32Array([0.07, 0.07]), 5)
	_part(b, mb.commit(), Art.paint("planks"), Vector3(0, h, 0))
	var top := h + 0.25 + _mini_house(b, rng, Vector3(0.3, h + 0.25, -0.2), rng.randf_range(-0.4, 0.4), Vector3(3.6, 2.6, 3.0), walls[(first + 3) % 5], roofs[(first + 3) % 4])
	top += _mini_house(b, rng, Vector3(rng.randf_range(-0.5, 0.5), top - 0.9, 0.0), rng.randf_range(0.6, 1.2), Vector3(2.0, 1.8, 1.9), walls[(first + 4) % 5], roofs[first % 4], 0.0, false) - 0.9
	var board := MeshBuilder.new()
	board.color = Color(0.95, 0.82, 0.4)
	board.add_box(Vector3(1.8, 0.9, 0.12), 0.05, Transform3D(Basis(Vector3.BACK, 0.12), Vector3(0, 3.6, 2.2)))
	board.color = Art.TIMBER
	board.add_tube(PackedVector3Array([Vector3(0, 2.0, 1.6), Vector3(0, 3.3, 2.15)]), PackedFloat32Array([0.09, 0.07]), 5)
	_part(b, board.commit(), Art.paint("planks", 0.5))
	return top


# --- Windmill -----------------------------------------------------------------

## A lumpy coral-covered rock with four feathered wings turning on its face.
static func _build_windmill(b: Destructible, rng: RandomNumberGenerator) -> float:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.3
	var low := Color.from_hsv(rng.randf_range(0.42, 0.5), 0.42, 0.66)
	var high := Color.from_hsv(rng.randf_range(0.01, 0.06), 0.52, 0.94)
	b.footprint = 4.2
	var mb := MeshBuilder.new()
	mb.color = low
	mb.add_blob(Vector3(3.6, 3.0, 3.4), Transform3D(Basis(), Vector3(0, 1.4, 0)), noise, 0.16, 10, 16)
	var body := _part(b, mb.commit(), Art.paint("rock"))
	var det := Details.new()
	det.arch_door(_around(0.5, 3.45, 0.0), 1.1, 2.0)
	det.round_window(_around(-0.7, 3.3, 2.4), 0.4)
	det.attach(body)
	mb = MeshBuilder.new()
	mb.color = high
	mb.add_blob(Vector3(2.6, 3.4, 2.5), Transform3D(Basis(Vector3.BACK, 0.12), Vector3(0.2, 5.4, -0.2)), noise, 0.18, 10, 16)
	var upper := _part(b, mb.commit(), Art.paint("rock"))
	det = Details.new()
	det.round_window(Transform3D(Basis(), Vector3(0.9, 4.6, 2.35)), 0.45)
	det.attach(upper)
	# Coral branches.
	var coral := MeshBuilder.new()
	for k in rng.randi_range(4, 6):
		var a := rng.randf_range(0.9, TAU - 0.9)
		var out := Vector3(sin(a), 0, cos(a))
		var from := out * 2.4 + Vector3(0, rng.randf_range(1.5, 6.5), 0)
		coral.color = Color.from_hsv(fposmod(rng.randf_range(0.95, 1.05), 1.0), 0.6, 0.95)
		for f in 3:
			var tip := from + out * rng.randf_range(1.2, 2.2) + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.8, 2.2), rng.randf_range(-0.6, 0.6))
			coral.add_tube(PackedVector3Array([from, from.lerp(tip, 0.5) + out * 0.3, tip]), PackedFloat32Array([0.26, 0.2, 0.13]), 6)
	_part(b, coral.commit(), Art.paint("plaster"))
	# The wings.
	var rotor := Spinner.new()
	rotor.name = "Rotor"
	rotor.speed = rng.randf_range(0.35, 0.6)
	b.add_child(rotor)
	rotor.position = Vector3(0.2, 6.0, 2.75)
	rotor.rotation.x = -0.12
	for k in 4:
		var wing := MeshBuilder.new()
		wing.color = Color(0.72, 0.56, 0.36)
		wing.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0.3, 3.5, 0), Vector3(0.9, 6.6, 0)]), PackedFloat32Array([0.2, 0.14, 0.06]), 6)
		for f in 8:
			var t := (f + 1) / 8.5
			wing.color = Color(0.95, 0.9, 0.76) if f % 2 == 0 else Color(0.86, 0.78, 0.62)
			var flen := lerpf(1.0, 2.0, sin(t * PI) * 0.7 + t * 0.3)
			wing.add_blob(Vector3(0.36, flen, 0.07), Transform3D(Basis(Vector3.BACK, -1.0 - t * 0.5), Vector3(0.3 + t * 0.6 + flen * 0.75, t * 6.4 - flen * 0.3, 0.05 * f)), null, 0.0, 5, 8)
		var blade := _part(rotor, wing.commit(), Art.paint("plaster", 0.7))
		blade.rotation.z = TAU * k / 4.0
	var hub := MeshBuilder.new()
	hub.color = Color(0.72, 0.56, 0.36)
	hub.add_blob(Vector3(0.5, 0.5, 0.4), Transform3D.IDENTITY, null, 0.0, 6, 10)
	_child(rotor, hub.commit(), Art.paint("planks", 0.6))
	return 9.2


# --- Goblin hut ---------------------------------------------------------------

## A drooping tent of moss and roots with crooked smoking chimneys, a bird
## skull on its peak and glowing charms hung from the eaves.
static func _build_goblin_hut(b: Destructible, rng: RandomNumberGenerator) -> float:
	var r := rng.randf_range(3.6, 4.4)
	var h := rng.randf_range(7.0, 8.5)
	b.footprint = r
	var mb := MeshBuilder.new()
	mb.color = Color(0.3, 0.36, 0.16)
	mb.add_lathe(PackedVector2Array([Vector2(r * 0.95, -SINK), Vector2(r, 0.2), Vector2(r * 0.8, h * 0.3), Vector2(r * 0.95, h * 0.32), Vector2(r * 0.95, h * 0.32),
		Vector2(r * 0.55, h * 0.6), Vector2(r * 0.68, h * 0.62), Vector2(r * 0.68, h * 0.62), Vector2(r * 0.25, h * 0.88), Vector2(0.0, h)]), 18, Transform3D.IDENTITY, 9, 0.09)
	var tent := _part(b, mb.commit(), Art.paint("thatch"))
	var roots := MeshBuilder.new()
	roots.color = Color(0.36, 0.26, 0.16)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.2, 0.2)
		if absf(angle_difference(a, 0.0)) < 0.45:
			continue
		var out := Vector3(sin(a), 0, cos(a))
		roots.add_tube(PackedVector3Array([out * (r + 0.9) + Vector3(0, -0.5, 0), out * (r + 0.1) + Vector3(0, h * 0.2, 0), out * r * 0.7 + Vector3(0, h * 0.5, 0),
			out * r * 0.3 + Vector3(0, h * 0.85, 0)]), PackedFloat32Array([0.45, 0.32, 0.22, 0.1]), 7)
	_child(tent, roots.commit(), Art.paint("bark", 0.6))
	# Doorway, skull and charms.
	var extras := MeshBuilder.new()
	extras.color = Color(0.03, 0.03, 0.04)
	extras.add_blob(Vector3(1.1, 1.7, 0.5), Transform3D(Basis(), Vector3(0, 0.7, r * 0.9)), null, 0.0, 6, 10)
	extras.color = Color(0.92, 0.9, 0.8)
	extras.add_blob(Vector3(0.45, 0.4, 0.5), Transform3D(Basis(), Vector3(0, h + 0.3, 0.1)), null, 0.0, 5, 8)
	extras.add_tube(PackedVector3Array([Vector3(0, h + 0.3, 0.4), Vector3(0, h + 0.15, 1.2)]), PackedFloat32Array([0.2, 0.03]), 6)
	_child(tent, extras.commit(), Art.paint("plaster", 0.5))
	var charms := MeshBuilder.new()
	for k in 8:
		var a := TAU * k / 8.0 + 0.4
		var p := Vector3(sin(a), 0, cos(a)) * r * 0.97 + Vector3(0, h * 0.3 - rng.randf_range(0.5, 1.2), 0)
		charms.color = Color.from_hsv(rng.randf(), 0.5, 1.0)
		charms.add_lathe(PackedVector2Array([Vector2(0.0, -0.35), Vector2(0.14, 0.0), Vector2(0.0, 0.35)]), 5, Transform3D(Basis(), p), 0, 0.0, true)
	_child(tent, charms.commit(), Art.glow(1.2))
	# Chimneys.
	for side in [-1.0, 1.0]:
		var s: float = side
		var base := Vector3(s * r * 0.5, h * 0.5, -0.4)
		var tip := base + Vector3(s * rng.randf_range(0.6, 1.4), rng.randf_range(2.4, 3.4), rng.randf_range(-0.5, 0.5))
		mb = MeshBuilder.new()
		mb.color = Color(0.42, 0.36, 0.3)
		mb.add_tube(PackedVector3Array([base, base.lerp(tip, 0.5) + Vector3(-s * 0.3, 0.2, 0), tip]), PackedFloat32Array([0.42, 0.34, 0.3]), 8)
		var chimney := _part(b, mb.commit(), Art.paint("bark"))
		if is_instance_valid(Game.effects):
			var smoke := Game.effects.make_smoke(0.45)
			chimney.add_child(smoke)
			smoke.position = tip + Vector3(0, 0.4, 0)
	return h + 0.8


# --- Cave ---------------------------------------------------------------------

## A rocky cave mouth with stone teeth and torches. Scenery only: it cannot
## be destroyed.
static func create_cave(rng: RandomNumberGenerator) -> Node3D:
	var cave := Node3D.new()
	cave.name = "Cave"
	cave.add_to_group("grounded")
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.22
	var mb := MeshBuilder.new()
	mb.add_blob(Vector3(9.0, 7.0, 7.5), Transform3D(Basis(), Vector3(0, 1.5, -4.5)), noise, 0.22, 12, 18)
	mb.add_blob(Vector3(3.6, 5.2, 4.0), Transform3D(Basis(), Vector3(-5.2, 1.0, 0.5)), noise, 0.2, 9, 14)
	mb.add_blob(Vector3(3.4, 4.8, 3.8), Transform3D(Basis(), Vector3(5.0, 0.8, 0.8)), noise, 0.2, 9, 14)
	mb.add_blob(Vector3(6.0, 2.6, 3.6), Transform3D(Basis(Vector3.BACK, 0.08), Vector3(0, 6.6, 0.4)), noise, 0.2, 9, 14)
	for k in 5:
		var a := rng.randf() * TAU
		mb.add_blob(Vector3(1.4, 1.1, 1.4) * rng.randf_range(0.7, 1.3), Transform3D(Basis(), Vector3(cos(a) * 9.0, 0.2, sin(a) * 6.0 - 3.0)), noise, 0.25, 6, 10)
	_child(cave, mb.commit(), Art.nature("rock"))
	var extras := MeshBuilder.new()
	extras.color = Color(0.02, 0.02, 0.03)
	extras.add_blob(Vector3(3.3, 4.6, 2.0), Transform3D(Basis(), Vector3(0, 0.6, 1.2)), null, 0.0, 8, 14)
	extras.color = Color(0.86, 0.82, 0.7)
	for k in 7:
		var x := lerpf(-2.4, 2.4, k / 6.0)
		var up := k % 2 == 0
		var tooth := rng.randf_range(0.8, 1.5)
		var base := Vector3(x, -0.2 if up else 4.6 - absf(x) * 0.5, 2.6)
		extras.add_tube(PackedVector3Array([base, base + Vector3(0, tooth if up else -tooth, 0.1)]), PackedFloat32Array([0.34, 0.03]), 6)
	_child(cave, extras.commit(), Art.paint("plaster", 0.5))
	# Torches either side of the mouth.
	var posts := MeshBuilder.new()
	posts.color = Art.TIMBER
	for sx in [-1.0, 1.0]:
		var s: float = sx
		var base := Vector3(s * 4.6, -0.5, 5.0)
		posts.add_tube(PackedVector3Array([base, base + Vector3(s * 0.2, 3.4, 0)]), PackedFloat32Array([0.16, 0.12]), 6)
		var fire := FireEmitter.new()
		fire.size = 0.5
		cave.add_child(fire)
		fire.position = base + Vector3(s * 0.2, 3.6, 0)
	_child(cave, posts.commit(), Art.paint("planks", 0.5))
	return cave


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
