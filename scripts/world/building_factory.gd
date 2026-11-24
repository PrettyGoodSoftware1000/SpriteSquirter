class_name BuildingFactory
extends RefCounted
## Generates the game's surreal buildings, modelled on the concept art in
## docs/ART_STYLE.md: four treehouses and their rope bridges, crystal tower,
## moon tower, mushroom house, singing rocks, store-in-a-tree, winged
## windmill, blacksmith and necromancer tower for villagers (and the tall
## house of older maps), plus the goblins' hut, cave and bone-and-rag shacks.
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
		for side: float in [-1.0, 1.0]:
			timber.add_box(Vector3(t, h, 0.22), 0.03, xf.translated_local(Vector3(side * (w * 0.5 + t * 0.5), 0, 0.05)))
		timber.add_box(Vector3(0.05, h, 0.13), 0.01, xf.translated_local(Vector3(0, 0, 0.03)))
		timber.add_box(Vector3(w, 0.05, 0.13), 0.01, xf.translated_local(Vector3(0, 0, 0.03)))
		if shutters:
			for side: float in [-1.0, 1.0]:
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
		for side: float in [-1.0, 1.0]:
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

const VILLAGE_KINDS := ["treehouse", "lookout_treehouse", "twin_treehouse", "great_treehouse", "crystal_tower", "moon_tower", "mushroom_house",
	"singing_rocks", "store", "store_house", "windmill"]


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
		"store_house":
			top = _build_store_house(b, rng)
		"windmill":
			top = _build_windmill(b, rng)
		"blacksmith":
			top = _build_blacksmith(b, rng)
		"treehouse":
			top = _build_treehouse(b, rng)
		"lookout_treehouse":
			top = _build_lookout_treehouse(b, rng)
		"twin_treehouse":
			top = _build_twin_treehouse(b, rng)
		"great_treehouse":
			top = _build_great_treehouse(b, rng)
		"necro_tower":
			top = _build_necro_tower(b, rng)
		"goblin_tent", "goblin_war_hut", "goblin_forge", "goblin_potion_hut", "goblin_watchtower":
			top = _build_goblin_shack(b, rng, kind)
		_:
			top = _build_goblin_hut(b, rng)
	b.height = top
	b.max_hp = Balance.num("building_health") + top * Balance.num("building_health_per_metre")
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
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			det.beam(Vector3(sx * x, 0, sz * z), Vector3(sx * x, h, sz * z), 0.24)
	for yy in [0.08, h - 0.08]:
		det.beam(Vector3(-x, yy, z), Vector3(x, yy, z), 0.22)
		det.beam(Vector3(-x, yy, -z), Vector3(x, yy, -z), 0.22)
		det.beam(Vector3(x, yy, -z), Vector3(x, yy, z), 0.22)
		det.beam(Vector3(-x, yy, -z), Vector3(-x, yy, z), 0.22)
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
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
	for side: float in [-1.0, 1.0]:
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
	for side: float in [-1.0, 1.0]:
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
			for sx: float in [-1.0, 1.0]:
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


# --- Store house (a Meshy model) -----------------------------------------------

## The owner's Meshy storehouse (assets/buildings/StoreHouse.glb), in its
## own painted material (no cel shading or outline), about 14 m tall.
const STORE_HOUSE_MODEL := "res://assets/buildings/StoreHouse.glb"
const STORE_HOUSE_HEIGHT := 14.0


static func _build_store_house(b: Destructible, rng: RandomNumberGenerator) -> float:
	var scene := (load(STORE_HOUSE_MODEL) as PackedScene).instantiate() as Node3D
	var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var box := source.mesh.get_aabb()
	var scale := STORE_HOUSE_HEIGHT / maxf(box.size.y, 0.001)
	var mi := MeshInstance3D.new()
	mi.mesh = source.mesh
	mi.material_override = source.get_active_material(0)
	mi.scale = Vector3.ONE * scale
	# (Not every one faces the same way.)
	mi.rotation.y = rng.randf_range(-0.3, 0.3)
	mi.position.y = -box.position.y * scale - 0.3
	mi.set_meta("debris", true)
	b.add_child(mi)
	scene.free()
	b.footprint = maxf(box.size.x, box.size.z) * 0.5 * scale
	return box.size.y * scale - 0.3


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
## The Blacksmith: a squat stone smithy with a fat chimney, a hearth of
## glowing coals beside the door and an anvil on a stump out front.
static func _build_blacksmith(b: Destructible, rng: RandomNumberGenerator) -> float:
	b.footprint = 3.7
	var top := _mini_house(b, rng, Vector3(0, 0, -0.4), 0.0, Vector3(4.4, 2.7, 3.6), Color(0.56, 0.54, 0.62), Color(0.26, 0.22, 0.32), SINK)
	var stone := MeshBuilder.new()
	stone.color = Color(0.5, 0.48, 0.56)
	stone.add_box(Vector3(1.4, 6.4 + SINK, 1.4), 0.12, Transform3D(Basis(), Vector3(1.75, (6.4 - SINK) * 0.5, -1.3)), Vector2(0.72, 0.72))
	stone.add_box(Vector3(1.3, 0.4, 1.3), 0.08, Transform3D(Basis(), Vector3(1.75, 6.4, -1.3)))
	stone.color = Color(0.44, 0.42, 0.5)
	stone.add_box(Vector3(1.6, 0.9 + SINK, 1.1), 0.1, Transform3D(Basis(), Vector3(-1.35, (0.9 - SINK) * 0.5, 2.0)))
	_part(b, stone.commit(), Art.paint("stone"))
	var fire := MeshBuilder.new()
	fire.color = Color(1.0, 0.45, 0.1)
	fire.add_blob(Vector3(0.6, 0.2, 0.38), Transform3D(Basis(), Vector3(-1.35, 0.95, 2.0)), null, 0.0, 5, 8)
	fire.add_blob(Vector3(0.38, 0.2, 0.38), Transform3D(Basis(), Vector3(1.75, 6.62, -1.3)), null, 0.0, 5, 8)
	_part(b, fire.commit(), Art.glow(2.6))
	var anvil := MeshBuilder.new()
	anvil.color = Art.WOOD_DARK
	anvil.add_tube(PackedVector3Array([Vector3(1.0, -0.3, 2.3), Vector3(1.0, 0.6, 2.3)]), PackedFloat32Array([0.4, 0.36]), 10)
	anvil.color = Color(0.2, 0.2, 0.24)
	anvil.add_box(Vector3(0.42, 0.22, 0.3), 0.03, Transform3D(Basis(), Vector3(1.0, 0.71, 2.3)))
	anvil.add_box(Vector3(0.85, 0.2, 0.34), 0.04, Transform3D(Basis(), Vector3(1.0, 0.92, 2.3)))
	anvil.add_tube(PackedVector3Array([Vector3(1.4, 0.94, 2.3), Vector3(1.75, 0.98, 2.3)]), PackedFloat32Array([0.09, 0.02]), 6)
	# A hammer leaning on the stump, and a barrel of water to quench in.
	anvil.color = Art.WOOD
	anvil.add_tube(PackedVector3Array([Vector3(0.45, 0.0, 2.55), Vector3(0.6, 0.75, 2.45)]), PackedFloat32Array([0.035, 0.035]), 5)
	anvil.add_tube(PackedVector3Array([Vector3(2.3, -0.2, 1.7), Vector3(2.3, 0.85, 1.7)]), PackedFloat32Array([0.42, 0.46]), 10)
	anvil.color = Color(0.2, 0.2, 0.24)
	anvil.add_box(Vector3(0.3, 0.16, 0.16), 0.03, Transform3D(Basis(Vector3.BACK, 0.2), Vector3(0.62, 0.82, 2.44)))
	anvil.color = Color(0.3, 0.6, 0.8)
	anvil.add_tube(PackedVector3Array([Vector3(2.3, 0.8, 1.7), Vector3(2.3, 0.88, 1.7)]), PackedFloat32Array([0.4, 0.4]), 10)
	_part(b, anvil.commit(), Art.paint("planks", 0.6))
	return maxf(top, 6.8)


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
	for side: float in [-1.0, 1.0]:
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


# --- Treehouse ------------------------------------------------------------------

const ROPE := Color(0.76, 0.62, 0.4)
const BONE := Color(0.9, 0.86, 0.72)
const INK := Color(0.04, 0.03, 0.05)


## The trunk, roots, deck braces and leafy boughs of a treehouse whose deck
## is `deck` metres up and `deck_r` across. `girth` fattens the trunk and
## `spread` the crown. Returns where the crown sits.
static func _tree_body(b: Destructible, rng: RandomNumberGenerator, deck: float, deck_r: float, top: float, girth := 1.0, spread := 1.0) -> Vector3:
	var lean := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
	var crown := lean + Vector3(0, top, 0)
	var knee := lean * 0.4 + Vector3(0, deck + (top - deck) * 0.6, 0)
	var mb := MeshBuilder.new()
	mb.color = Color(0.5, 0.34, 0.2)
	mb.add_tube(PackedVector3Array([Vector3(0, -1.2, 0), Vector3(0, 0.4, 0), Vector3(0, deck, 0), knee, crown]),
		PackedFloat32Array([1.9 * girth, 1.3 * girth, 0.95 * girth, 0.75 * girth, 0.45 * girth]), 12)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf()
		var out := Vector3(cos(a), 0, sin(a))
		mb.add_tube(PackedVector3Array([out * 0.7 * girth + Vector3(0, 0.9, 0), out * 2.0 * girth + Vector3(0, 0.2, 0), out * 3.0 * girth + Vector3(0, -0.6, 0)]),
			PackedFloat32Array([0.48 * girth, 0.34 * girth, 0.18 * girth]), 7)
	# Braces under the deck.
	for k in 4:
		var a := TAU * k / 4.0 + 0.8
		var out := Vector3(cos(a), 0, sin(a))
		mb.add_tube(PackedVector3Array([out * 0.7 * girth + Vector3(0, deck - 2.3, 0), out * (deck_r - 0.5) + Vector3(0, deck - 0.3, 0)]),
			PackedFloat32Array([0.2, 0.13]), 6)
	# Boughs, each ending in a ball of leaves.
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.3
	# The leaves take the nature palette's colours, like the trees around
	# them (one bunch a shade darker than the other).
	var leaves := [MeshBuilder.new(), MeshBuilder.new()]
	leaves[0].color = Color(1, 1, 1)
	leaves[1].color = Color(0.86, 0.86, 0.86)
	leaves[0].add_blob(Vector3(3.2, 2.3, 3.2) * spread * rng.randf_range(0.92, 1.08), Transform3D(Basis(), crown + Vector3(0, 1.3, 0)), noise, 0.2, 9, 14)
	var boughs := rng.randi_range(3, 4)
	var spin := rng.randf() * TAU
	for k in boughs:
		var a := spin + TAU * k / boughs + rng.randf_range(-0.3, 0.3)
		var from := knee.lerp(crown, rng.randf_range(0.45, 0.9))
		var out := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(2.6, 3.4) * spread
		var tip := from + out * length + Vector3(0, length * rng.randf_range(0.2, 0.5), 0)
		mb.add_tube(PackedVector3Array([from - out * 0.1, from.lerp(tip, 0.5) + Vector3(0, -0.25, 0), tip]), PackedFloat32Array([0.3, 0.22, 0.14]), 6)
		var r := rng.randf_range(1.7, 2.2) * spread
		leaves[(k + 1) % 2].add_blob(Vector3(r, r * 0.8, r), Transform3D(Basis(), tip + Vector3(0, r * 0.45, 0)), noise, 0.2, 8, 12)
	_part(b, mb.commit(), Art.paint("bark"))
	for builder: MeshBuilder in leaves:
		_part(b, builder.commit(), Art.nature("leaf"))
	return crown


## A treehouse's round deck with its rail (open at the ladder on the front,
## +Z), the ladder and hanging lanterns. Also notes the deck in the
## "deck_h" and "deck_r" metas, which rope bridges go by (see RopeBridge).
static func _tree_deck(b: Destructible, rng: RandomNumberGenerator, deck: float, deck_r: float) -> MeshInstance3D:
	b.set_meta("deck_h", deck + 0.22)
	b.set_meta("deck_r", deck_r)
	var mb := MeshBuilder.new()
	mb.color = Color(0.66, 0.46, 0.26)
	mb.add_lathe(PackedVector2Array([Vector2(0.0, -0.45), Vector2(deck_r * 0.75, -0.3), Vector2(deck_r, 0.0), Vector2(deck_r, 0.22),
		Vector2(deck_r, 0.22), Vector2(0.0, 0.22)]), 12, Transform3D.IDENTITY, 0, 0.0, true)
	var rail := PackedVector3Array()
	for k in 13:
		var a := 0.42 + (TAU - 0.84) * k / 12.0
		var post := Vector3(sin(a), 0, cos(a)) * (deck_r - 0.12)
		mb.color = Color(0.5, 0.33, 0.18)
		mb.add_tube(PackedVector3Array([post + Vector3(0, 0.2, 0), post + Vector3(0, 1.05, 0)]), PackedFloat32Array([0.07, 0.06]), 5)
		rail.append(post + Vector3(0, 0.95, 0))
	var widths := PackedFloat32Array()
	widths.resize(rail.size())
	widths.fill(0.04)
	mb.color = ROPE
	mb.add_tube(rail, widths, 5)
	var platform := _part(b, mb.commit(), Art.paint("planks"), Vector3(0, deck, 0))
	var det := Details.new()
	_ladder(det, Vector3(0, -deck - 0.6, deck_r + 1.0), Vector3(0, 0.5, deck_r - 0.05))
	det.attach(platform)
	# Lanterns hang from the edge of the deck.
	var strings := MeshBuilder.new()
	var lamps := MeshBuilder.new()
	for k in 3:
		var a := 1.2 + TAU * k / 3.0 + rng.randf_range(-0.3, 0.3)
		var p := Vector3(sin(a), 0, cos(a)) * (deck_r - 0.05)
		var drop := rng.randf_range(0.7, 1.3)
		strings.color = ROPE
		strings.add_tube(PackedVector3Array([p, p + Vector3(0, -drop, 0)]), PackedFloat32Array([0.025, 0.025]), 4)
		strings.color = Color(0.25, 0.2, 0.16)
		strings.add_lathe(PackedVector2Array([Vector2(0.0, 0.12), Vector2(0.17, 0.0), Vector2(0.0, -0.02)]), 6, Transform3D(Basis(), p + Vector3(0, -drop + 0.02, 0)))
		lamps.color = Color(1.0, 0.8, 0.35)
		lamps.add_blob(Vector3(0.15, 0.2, 0.15), Transform3D(Basis(), p + Vector3(0, -drop - 0.2, 0)), null, 0.0, 5, 8)
	_child(platform, strings.commit(), Art.paint("planks", 0.5))
	_child(platform, lamps.commit(), Art.glow(2.2))
	return platform


## A ladder of two rails and rungs from `foot` up to `head`.
static func _ladder(det: Details, foot: Vector3, head: Vector3) -> void:
	var across := (head - foot).cross(Vector3.UP)
	across = across.normalized() if across.length_squared() > 0.001 else Vector3.RIGHT
	for sx: float in [-1.0, 1.0]:
		det.beam(foot + across * sx * 0.36, head + across * sx * 0.36, 0.11)
	var rungs := maxi(3, roundi(foot.distance_to(head) / 0.45))
	for k in range(1, rungs):
		var p := foot.lerp(head, k / float(rungs))
		det.beam(p - across * 0.4, p + across * 0.4, 0.08)


## A small extra platform out on a bracket, `r` across, at `at`.
static func _side_platform(b: Destructible, at: Vector3, r: float) -> void:
	var mb := MeshBuilder.new()
	mb.color = Color(0.66, 0.46, 0.26)
	mb.add_lathe(PackedVector2Array([Vector2(0.0, -0.35), Vector2(r * 0.7, -0.25), Vector2(r, 0.0), Vector2(r, 0.2), Vector2(r, 0.2), Vector2(0.0, 0.2)]),
		10, Transform3D(Basis(), at), 0, 0.0, true)
	mb.color = Color(0.5, 0.33, 0.18)
	var inward := Vector3(-at.x, 0, -at.z).normalized()
	mb.add_tube(PackedVector3Array([at + inward * (r + 0.6) + Vector3(0, -2.0, 0), at + Vector3(0, -0.3, 0)]), PackedFloat32Array([0.2, 0.14]), 6)
	_part(b, mb.commit(), Art.paint("planks"))


const TREEHOUSE_WALLS := [Color(0.24, 0.66, 0.66), Color(0.56, 0.4, 0.8), Color(0.92, 0.74, 0.3), Color(0.86, 0.5, 0.62), Color(0.5, 0.74, 0.36)]
const TREEHOUSE_ROOFS := [Color(0.16, 0.56, 0.6), Color(0.5, 0.3, 0.72), Color(0.94, 0.6, 0.14), Color(0.82, 0.24, 0.3), Color(0.3, 0.36, 0.76)]


## The Treehouse: a little house on a round deck high in a bright-leaved
## tree, with a ladder up to it on the front (+Z).
static func _build_treehouse(b: Destructible, rng: RandomNumberGenerator) -> float:
	b.footprint = 4.2
	var deck := rng.randf_range(4.3, 5.0)
	var top := deck + rng.randf_range(6.2, 7.0)
	_tree_body(b, rng, deck, 3.5, top)
	_tree_deck(b, rng, deck, 3.5)
	_mini_house(b, rng, Vector3(0, deck + 0.22, -0.15), rng.randf_range(-0.25, 0.25), Vector3(2.9, 1.9, 2.4),
		_pick(rng, TREEHOUSE_WALLS), _pick(rng, TREEHOUSE_ROOFS))
	return top + 3.4


## The Lookout treehouse: a round summer-house with a swirled pointed roof
## high up a tree, a little balcony below it and a slide back to the ground.
static func _build_lookout_treehouse(b: Destructible, rng: RandomNumberGenerator) -> float:
	b.footprint = 4.0
	var deck := rng.randf_range(5.2, 5.8)
	var deck_r := 3.2
	var top := deck + rng.randf_range(6.6, 7.2)
	_tree_body(b, rng, deck, deck_r, top, 0.9)
	_tree_deck(b, rng, deck, deck_r)
	var base := deck + 0.22
	# The summer-house: a round wall of arches under a tall striped roof.
	var wall_h := 2.1
	var mb := MeshBuilder.new()
	mb.color = Color(0.93, 0.87, 0.72)
	mb.add_lathe(PackedVector2Array([Vector2(1.75, 0.0), Vector2(1.85, 0.1), Vector2(1.8, wall_h), Vector2(1.95, wall_h + 0.12)]), 14)
	var wall := _part(b, mb.commit(), Art.paint("plaster"), Vector3(0, base, 0))
	var det := Details.new()
	det.arch_door(_around(0.0, 1.8, 0.0), 0.9, 1.75)
	for k in range(1, 6):
		var xf := _around(TAU * k / 6.0, 1.82, 1.15)
		det.glass.add_box(Vector3(0.62, 0.75, 0.1), 0.02, xf.translated_local(Vector3(0, -0.2, 0)))
		det.glass.add_blob(Vector3(0.31, 0.31, 0.06), xf.translated_local(Vector3(0, 0.18, 0)), null, 0.0, 5, 10)
		det.timber.add_box(Vector3(0.8, 0.1, 0.24), 0.02, xf.translated_local(Vector3(0, -0.62, 0.06)))
	det.attach(wall)
	mb = MeshBuilder.new()
	var roof_h := rng.randf_range(2.6, 3.1)
	_striped_hat(mb, 2.5, roof_h, Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)),
		_pick(rng, [Color(0.86, 0.2, 0.2), Color(0.9, 0.5, 0.12), Color(0.6, 0.25, 0.75)]), Color(0.98, 0.84, 0.3))
	_part(b, mb.commit(), Art.paint("shingles"), Vector3(0, base + wall_h + 0.05, 0))
	# The balcony half way up, and the slide winding down from it.
	var balcony := deck - 2.5
	mb = MeshBuilder.new()
	mb.color = Color(0.66, 0.46, 0.26)
	mb.add_lathe(PackedVector2Array([Vector2(0.8, -0.2), Vector2(2.1, 0.0), Vector2(2.1, 0.18), Vector2(2.1, 0.18), Vector2(0.8, 0.18)]), 12,
		Transform3D(Basis(), Vector3(0, balcony, 0)), 0, 0.0, true)
	var rail := PackedVector3Array()
	for k in 9:
		var a := -2.6 + 3.6 * k / 8.0
		var post := Vector3(sin(a), 0, cos(a)) * 2.0 + Vector3(0, balcony, 0)
		mb.color = Color(0.5, 0.33, 0.18)
		mb.add_tube(PackedVector3Array([post + Vector3(0, 0.15, 0), post + Vector3(0, 0.95, 0)]), PackedFloat32Array([0.06, 0.05]), 5)
		rail.append(post + Vector3(0, 0.9, 0))
	var widths := PackedFloat32Array()
	widths.resize(rail.size())
	widths.fill(0.04)
	mb.color = ROPE
	mb.add_tube(rail, widths, 5)
	_part(b, mb.commit(), Art.paint("planks"))
	mb = MeshBuilder.new()
	mb.color = Color(0.62, 0.64, 0.72)
	var slide := PackedVector3Array()
	var bore := PackedFloat32Array()
	for k in 12:
		var t := k / 11.0
		var a := 2.2 + t * 3.4
		slide.append(Vector3(sin(a), 0, cos(a)) * lerpf(1.9, 3.3, t) + Vector3(0, lerpf(balcony + 0.5, 0.35, t * t * (3.0 - 2.0 * t)), 0))
		bore.append(0.46)
	mb.add_tube(slide, bore, 9)
	mb.color = INK
	mb.add_blob(Vector3(0.36, 0.36, 0.36), Transform3D(Basis(), slide[slide.size() - 1]), null, 0.0, 5, 8)
	_part(b, mb.commit(), Art.paint("stone", 0.6))
	return top + 3.4


## The Twin treehouse: one house on the deck and a second, smaller one on a
## platform of its own higher up the same tree, with a ladder between them.
static func _build_twin_treehouse(b: Destructible, rng: RandomNumberGenerator) -> float:
	b.footprint = 4.4
	var deck := rng.randf_range(4.2, 4.8)
	var deck_r := 3.6
	var top := deck + rng.randf_range(8.0, 8.8)
	_tree_body(b, rng, deck, deck_r, top, 1.05, 1.1)
	var platform := _tree_deck(b, rng, deck, deck_r)
	var first := rng.randi()
	_mini_house(b, rng, Vector3(-1.0, deck + 0.22, 0.3), rng.randf_range(0.1, 0.5), Vector3(2.5, 1.8, 2.2),
		TREEHOUSE_WALLS[first % 5], TREEHOUSE_ROOFS[first % 5])
	var upper := Vector3(2.5, deck + 3.5, -1.5)
	_side_platform(b, upper, 1.9)
	_mini_house(b, rng, upper + Vector3(0, 0.2, 0), rng.randf_range(-0.9, -0.4), Vector3(2.0, 1.5, 1.8),
		TREEHOUSE_WALLS[(first + 2) % 5], TREEHOUSE_ROOFS[(first + 3) % 5])
	var det := Details.new()
	_ladder(det, Vector3(2.3, 0.3, 0.9), upper + Vector3(-0.3, 0.3 - deck, 1.7))
	det.attach(platform)
	# Bunting from the trunk out to the rail.
	var flags := MeshBuilder.new()
	for k in 6:
		var p := Vector3(-0.7, deck + 2.6, 0.9).lerp(Vector3(-2.2, deck + 1.3, 2.7), k / 5.0)
		flags.color = Color.from_hsv(fmod(0.13 * k + rng.randf() * 0.1, 1.0), 0.75, 0.95)
		flags.add_lathe(PackedVector2Array([Vector2(0.0, -0.4), Vector2(0.17, 0.0), Vector2(0.0, 0.02)]), 3, Transform3D(Basis(), p), 0, 0.0, true)
	_part(b, flags.commit(), Art.paint("plaster", 0.5))
	return top + 3.6


## The Great treehouse: an old giant of a tree with a door and windows in
## its trunk and three little houses about it, one on the wide deck and two
## on platforms of their own.
static func _build_great_treehouse(b: Destructible, rng: RandomNumberGenerator) -> float:
	b.footprint = 5.6
	var deck := rng.randf_range(5.0, 5.6)
	var deck_r := 4.5
	var girth := 1.7
	var top := deck + rng.randf_range(8.6, 9.4)
	_tree_body(b, rng, deck, deck_r, top, girth, 1.3)
	var platform := _tree_deck(b, rng, deck, deck_r)
	var first := rng.randi()
	_mini_house(b, rng, Vector3(-1.9, deck + 0.22, 0.8), 0.5, Vector3(2.2, 1.7, 1.9), TREEHOUSE_WALLS[first % 5], TREEHOUSE_ROOFS[(first + 1) % 5])
	var side := Vector3(3.1, deck + 3.0, 0.4)
	_side_platform(b, side, 1.8)
	_mini_house(b, rng, side + Vector3(0, 0.2, 0), -0.5, Vector3(1.9, 1.5, 1.7), TREEHOUSE_WALLS[(first + 1) % 5], TREEHOUSE_ROOFS[(first + 2) % 5])
	var back := Vector3(-1.2, deck + 4.2, -2.9)
	_side_platform(b, back, 1.7)
	_mini_house(b, rng, back + Vector3(0, 0.2, 0), 2.6, Vector3(1.8, 1.4, 1.6), TREEHOUSE_WALLS[(first + 3) % 5], TREEHOUSE_ROOFS[(first + 4) % 5])
	# A round door and lit windows in the trunk, and moss on its roots.
	var det := Details.new()
	var r_low := 1.3 * girth + 0.1
	det.arch_door(_around(0.75, r_low, -deck), 1.0, 1.9)
	det.round_window(_around(-0.6, lerpf(1.3, 0.95, 0.45) * girth + 0.12, -deck + 2.6), 0.42)
	det.round_window(_around(1.9, lerpf(1.3, 0.95, 0.6) * girth + 0.12, -deck + 3.4), 0.36)
	_ladder(det, Vector3(1.6, 0.3, -0.6), side + Vector3(-0.9, 0.3 - deck, 0.0))
	det.attach(platform)
	var moss := MeshBuilder.new()
	moss.color = Color(0.36, 0.62, 0.2)
	for k in 9:
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.2, 3.6)
		var r := lerpf(1.9, 1.3, clampf(y / 0.4, 0.0, 1.0)) * girth * lerpf(1.0, 0.8, clampf(y / deck, 0.0, 1.0))
		moss.add_blob(Vector3(0.5, 0.3, 0.5) * rng.randf_range(0.6, 1.2), Transform3D(Basis(), Vector3(cos(a) * r, y, sin(a) * r)), null, 0.0, 4, 7)
	_part(b, moss.commit(), Art.surface("hide", Color(1, 1, 1), Color(0.8, 0.8, 0.8), {"ink": 0.45}))
	return top + 4.2


## A rope bridge `length` metres long, built along X about its middle: it
## hangs from height `ya` at the -X end to `yb` at the +X end.
static func create_bridge(length: float, ya: float, yb: float) -> RopeBridge:
	var b := RopeBridge.new()
	b.name = "Rope bridge"
	b.set_meta("kind", "bridge")
	b.is_building = false
	b.length = length
	b.ya = ya
	b.yb = yb
	b.sag = minf(1.4, length * 0.05)
	b.footprint = 1.5
	b.height = maxf(ya, yb) + 1.0
	b.max_hp = 60.0
	b.hp = b.max_hp
	b.flammability = 0.2
	b.burn_duration = 10.0
	var steps := maxi(4, ceili(length / 0.55))
	var planks := MeshBuilder.new()
	for k in steps:
		var t := (k + 0.5) / steps
		var slope := b.local_at(t + 0.01) - b.local_at(t - 0.01)
		planks.color = Art.WOOD.lightened(0.12) if k % 2 == 0 else Art.WOOD
		planks.add_box(Vector3(length / steps * 0.86, 0.07, 1.15), 0.015, Transform3D(Basis(Vector3.BACK, atan2(slope.y, slope.x)), b.local_at(t)))
		if k % 10 == 9 or k == steps - 1:
			_part(b, planks.commit(), Art.paint("planks", 0.6))
			planks = MeshBuilder.new()
	var ropes := MeshBuilder.new()
	var spans := maxi(3, ceili(length / 1.6))
	for sz: float in [-1.0, 1.0]:
		var z: float = sz * 0.6
		var low := PackedVector3Array()
		var high := PackedVector3Array()
		for k in spans + 1:
			var p := b.local_at(k / float(spans))
			low.append(p + Vector3(0, -0.06, z))
			high.append(p + Vector3(0, 0.95, z))
			ropes.color = Art.WOOD_DARK if k == 0 or k == spans else ROPE
			var thick := 0.08 if k == 0 or k == spans else 0.025
			ropes.add_tube(PackedVector3Array([low[k], high[k] + Vector3(0, 0.12 if thick > 0.05 else 0.0, 0)]), PackedFloat32Array([thick, thick]), 5)
		var thin := PackedFloat32Array()
		thin.resize(spans + 1)
		thin.fill(0.04)
		ropes.color = ROPE
		ropes.add_tube(low, thin, 5)
		ropes.add_tube(high, thin, 5)
	_part(b, ropes.commit(), Art.paint("planks", 0.5))
	return b


# --- Bones ----------------------------------------------------------------------

## A long bone from `a` to `c` with a knob at each end.
static func _bone(mb: MeshBuilder, a: Vector3, c: Vector3, r: float) -> void:
	mb.color = BONE
	mb.add_tube(PackedVector3Array([a, c]), PackedFloat32Array([r, r]), 6)
	for p: Vector3 in [a, c]:
		mb.add_blob(Vector3.ONE * r * 1.7, Transform3D(Basis(), p), null, 0.0, 4, 7)


## A skull `s` metres across looking along `xf`'s +Z. `horns` above zero
## gives it a pair of horns that long.
static func _skull(mb: MeshBuilder, xf: Transform3D, s: float, horns := 0.0) -> void:
	mb.color = BONE
	mb.add_blob(Vector3(0.5, 0.46, 0.55) * s, xf, null, 0.0, 6, 10)
	mb.add_box(Vector3(0.52, 0.3, 0.34) * s, 0.05 * s, xf.translated_local(Vector3(0, -0.4, 0.2) * s))
	for sx: float in [-1.0, 1.0]:
		var side: float = sx
		if horns > 0.0:
			mb.color = BONE.darkened(0.08)
			mb.add_tube(PackedVector3Array([Vector3(side * 0.4, 0.2, 0) * s, Vector3(side * 0.85, 0.45, 0.05) * s * horns,
				Vector3(side * 0.95, 1.0, 0.18) * s * horns]), PackedFloat32Array([0.17 * s, 0.11 * s, 0.02 * s]), 6, xf)
		mb.color = INK
		mb.add_blob(Vector3(0.15, 0.17, 0.08) * s, xf.translated_local(Vector3(side * 0.2, 0.02, 0.47) * s), null, 0.0, 4, 8)
	mb.add_blob(Vector3(0.06, 0.09, 0.05) * s, xf.translated_local(Vector3(0, -0.17, 0.53) * s), null, 0.0, 4, 6)
	for k in 3:
		mb.add_box(Vector3(0.03, 0.2, 0.02) * s, 0.004 * s, xf.translated_local(Vector3((k - 1) * 0.13, -0.43, 0.375) * s))


# --- Necromancer tower -------------------------------------------------------------

## A cracked stone keep with a giant horned skull and a crossed bone on top,
## gargoyle turrets either side of its door and green and purple wisps
## winding round it.
static func _build_necro_tower(b: Destructible, rng: RandomNumberGenerator) -> float:
	b.footprint = 3.8
	var h := rng.randf_range(8.6, 9.6)
	var w := 4.0
	var stone := MeshBuilder.new()
	stone.color = Color(0.5, 0.5, 0.46)
	stone.add_box(Vector3(w, h + SINK, w), 0.16, Transform3D(Basis(), Vector3(0, (h - SINK) * 0.5, 0)), Vector2(0.86, 0.86))
	var tw := w * 0.86
	stone.color = Color(0.56, 0.56, 0.52)
	stone.add_box(Vector3(tw + 0.7, 0.55, tw + 0.7), 0.08, Transform3D(Basis(), Vector3(0, h + 0.1, 0)))
	for k in 12:
		# Merlons round the top.
		var edge := floori(k / 3.0)
		var along := ((k % 3) - 1) * (tw + 0.2) * 0.36
		var xf := _face(edge, tw + 0.3, tw + 0.3, along, h + 0.7)
		stone.add_box(Vector3(0.62, 0.75, 0.42), 0.05, xf)
	var tower := _part(b, stone.commit(), Art.paint("stone"), Vector3.ZERO, Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03)))
	# The two turrets by the door, each with a gargoyle.
	for sx: float in [-1.0, 1.0]:
		var side: float = sx
		var th := rng.randf_range(3.2, 3.9)
		var at := Vector3(side * 2.5, 0, 1.5)
		stone = MeshBuilder.new()
		stone.color = Color(0.46, 0.46, 0.43)
		stone.add_box(Vector3(1.7, th + SINK, 1.7), 0.1, Transform3D(Basis(), Vector3(0, (th - SINK) * 0.5, 0)), Vector2(0.9, 0.9))
		stone.add_box(Vector3(1.9, 0.35, 1.9), 0.06, Transform3D(Basis(), Vector3(0, th + 0.05, 0)))
		stone.color = Color(0.4, 0.42, 0.4)
		stone.add_blob(Vector3(0.38, 0.5, 0.42), Transform3D(Basis(), Vector3(0, th + 0.7, 0.1)), null, 0.0, 5, 8)
		stone.add_blob(Vector3(0.26, 0.26, 0.3), Transform3D(Basis(), Vector3(0, th + 1.3, 0.3)), null, 0.0, 5, 8)
		for wing: float in [-1.0, 1.0]:
			var ws: float = wing
			stone.add_tube(PackedVector3Array([Vector3(ws * 0.2, th + 0.9, -0.1), Vector3(ws * 0.8, th + 1.7, -0.35), Vector3(ws * 1.0, th + 1.0, -0.4)]),
				PackedFloat32Array([0.16, 0.1, 0.02]), 5)
			stone.add_tube(PackedVector3Array([Vector3(ws * 0.14, th + 1.45, 0.3), Vector3(ws * 0.26, th + 1.8, 0.28)]), PackedFloat32Array([0.07, 0.01]), 4)
		_part(b, stone.commit(), Art.paint("stone"), at, Vector3(0, -side * 0.25, 0))
	# Doorway, window slits, the bones round the door and the pile outside.
	var extras := MeshBuilder.new()
	extras.color = INK
	extras.add_box(Vector3(1.25, 1.5, 0.3), 0.04, Transform3D(Basis(), Vector3(0, 0.75, w * 0.5 - 0.05)))
	extras.add_blob(Vector3(0.625, 0.62, 0.15), Transform3D(Basis(), Vector3(0, 1.5, w * 0.5 - 0.05)), null, 0.0, 6, 12)
	for k in 3:
		var y := h * (0.42 + 0.2 * k)
		var half := lerpf(w, tw, y / h) * 0.5
		extras.add_box(Vector3(0.34, 0.95, 0.12), 0.03, _face(k % 2 * 2, half * 2.0, half * 2.0, 0.0, y))
		extras.add_blob(Vector3(0.17, 0.2, 0.06), _face(k % 2 * 2, half * 2.0, half * 2.0, 0.0, y + 0.47), null, 0.0, 4, 8)
	_bone(extras, Vector3(-0.85, -0.2, w * 0.5 + 0.12), Vector3(-0.8, 2.2, w * 0.5 + 0.05), 0.1)
	_bone(extras, Vector3(0.85, -0.2, w * 0.5 + 0.12), Vector3(0.8, 2.2, w * 0.5 + 0.05), 0.1)
	_skull(extras, Transform3D(Basis(), Vector3(0, 2.55, w * 0.5 + 0.1)), 0.62, 0.8)
	for k in 6:
		var a := rng.randf_range(-1.2, 1.2)
		var r := w * 0.5 + rng.randf_range(0.6, 1.5)
		_skull(extras, Transform3D(Basis(Vector3.UP, a + rng.randf_range(-0.6, 0.6)), Vector3(sin(a) * r, 0.16, cos(a) * r)), rng.randf_range(0.3, 0.42))
	_child(tower, extras.commit(), Art.paint("plaster", 0.5))
	# The great skull, with ribs like fingers behind it and a bone across the top.
	var crown := MeshBuilder.new()
	var sy := h + 1.95
	_skull(crown, Transform3D(Basis(), Vector3(0, sy, 0.25)), 2.5, 1.0)
	for k in 5:
		var x := (k - 2) * 0.55
		crown.color = BONE.darkened(0.1)
		crown.add_tube(PackedVector3Array([Vector3(x, h + 0.4, -1.3), Vector3(x * 1.2, h + 2.6, -1.7), Vector3(x * 1.1, h + 4.0 - absf(x) * 0.5, -0.8)]),
			PackedFloat32Array([0.17, 0.14, 0.05]), 6)
	_bone(crown, Vector3(-3.0, sy + 1.55, -0.2), Vector3(3.0, sy + 2.0, 0.1), 0.3)
	_part(b, crown.commit(), Art.paint("plaster", 0.6))
	# Wisps of green and purple magic wind round the tower.
	var wisps := MeshBuilder.new()
	for k in 2:
		wisps.color = Color(0.35, 1.0, 0.45) if k == 0 else Color(0.7, 0.3, 1.0)
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		var from := h * (0.62 if k == 0 else 0.28)
		for j in 15:
			var t := j / 14.0
			var a := k * PI + t * 4.4
			var r := w * 0.5 + 0.55 + 0.35 * sin(t * 9.0)
			path.append(Vector3(cos(a) * r, from + t * h * 0.3 + 0.3 * sin(t * 7.0), sin(a) * r))
			radii.append(0.2 * sin(t * PI) + 0.02)
		wisps.add_tube(path, radii, 6)
	_child(tower, wisps.commit(), Art.glow(2.4))
	return h + 4.6


# --- Goblin buildings --------------------------------------------------------------

## What the goblins build for themselves (see GoblinRaids).
const GOBLIN_KINDS := ["goblin_tent", "goblin_war_hut", "goblin_forge", "goblin_potion_hut", "goblin_watchtower"]


## One storey of a goblin shack: crooked plank walls under a roof of rags
## held down by crossed bones, with a horned skull over the front. It is
## built with its ridge along X and its front at +X, inside `pivot`.
## Returns the height of the ridge above `y`.
static func _shack_storey(pivot: Node3D, rng: RandomNumberGenerator, y: float, size: Vector3, cloth: Color, door: bool, skull: float) -> float:
	var w := size.x
	var h := size.y
	var d := size.z
	var sink := SINK if y < 0.1 else 0.0
	var mb := MeshBuilder.new()
	mb.color = Color(0.36, 0.33, 0.2).lerp(Color(0.3, 0.24, 0.16), rng.randf())
	mb.add_box(Vector3(w, h + sink, d), 0.1, Transform3D(Basis(), Vector3(0, (h - sink) * 0.5, 0)), Vector2(0.92, 0.9))
	var tilt := Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
	var walls := _part(pivot, mb.commit(), Art.paint("planks"), Vector3(0, y, 0), tilt)
	var det := MeshBuilder.new()
	det.color = INK
	if door:
		det.add_box(Vector3(0.2, 1.6, 1.0), 0.03, Transform3D(Basis(), Vector3(w * 0.47, 0.75, 0)))
	else:
		det.add_box(Vector3(0.2, 0.6, 0.7), 0.03, Transform3D(Basis(), Vector3(w * 0.46, h * 0.55, 0)))
	det.add_box(Vector3(0.6, 0.5, 0.2), 0.03, Transform3D(Basis(), Vector3(0.2, h * 0.6, d * 0.46)))
	# Rough timbers at the corners, standing proud of the roof.
	det.color = Color(0.3, 0.2, 0.12)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			det.add_tube(PackedVector3Array([Vector3(sx * w * 0.49, -0.2, sz * d * 0.48), Vector3(sx * w * 0.45, h + 0.5, sz * d * 0.44)]),
				PackedFloat32Array([0.13, 0.09]), 5)
	_child(walls, det.commit(), Art.paint("planks", 0.5))
	var rh := d * rng.randf_range(0.5, 0.7)
	mb = MeshBuilder.new()
	mb.color = cloth
	_gable_roof(mb, w, d, rh, 0.6, rng.randf_range(0.25, 0.5), rng.randf_range(0.3, 0.6))
	mb.color = Color(0.3, 0.26, 0.17)
	_gable_walls(mb, w, d, rh, 0.6)
	var roof := _part(pivot, mb.commit(), Art.paint("plaster", 0.8), Vector3(0, y, 0) + Basis.from_euler(tilt) * Vector3(0, h, 0), tilt)
	var bones := MeshBuilder.new()
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (w * 0.5 + 0.5)
		for sz: float in [-1.0, 1.0]:
			_bone(bones, Vector3(x, -0.25, sz * (d * 0.5 + 0.65)), Vector3(x, rh + 1.0, -sz * 0.4), 0.11)
	# Patches sewn on, and rags hanging from the eaves.
	for k in 3:
		bones.color = cloth.darkened(rng.randf_range(0.2, 0.45))
		var u := rng.randf_range(-0.35, 0.35) * w
		var side := 1.0 if k % 2 == 0 else -1.0
		bones.add_box(Vector3(0.7, 0.05, 0.5), 0.01, Transform3D(Basis(Vector3.RIGHT, side * 0.75), Vector3(u, rh * 0.5 + 0.12, side * (d * 0.25 + 0.15))))
		bones.add_box(Vector3(0.5, 0.7, 0.04), 0.01, Transform3D(Basis(), Vector3(u, -0.55, side * (d * 0.5 + 0.55))))
	if skull > 0.0:
		_skull(bones, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5 + 0.7, rh * 0.72, 0)), skull, 1.0)
	_child(roof, bones.commit(), Art.paint("plaster", 0.5))
	return h + rh + ROOF_LIFT


static func _build_goblin_shack(b: Destructible, rng: RandomNumberGenerator, kind: String) -> float:
	var pivot := Node3D.new()
	pivot.rotation.y = -PI * 0.5
	b.add_child(pivot)
	var top := 0.0
	var size := Vector3(3.6, 2.3, 3.2)
	match kind:
		"goblin_tent":
			size = Vector3(4.2, 1.4, 3.8)
			top = _shack_storey(pivot, rng, 0.0, size, Color(0.3, 0.24, 0.5), true, 1.5)
		"goblin_war_hut":
			size = Vector3(3.6, 2.3, 3.4)
			top = _shack_storey(pivot, rng, 0.0, size, Color(0.56, 0.14, 0.12), true, 0.0)
			top = top - 1.0 + _shack_storey(pivot, rng, top - 1.0, Vector3(2.5, 1.5, 2.6), Color(0.5, 0.12, 0.1), false, 1.0)
		"goblin_forge":
			size = Vector3(3.8, 2.4, 3.4)
			top = _shack_storey(pivot, rng, 0.0, size, Color(0.2, 0.22, 0.42), true, 1.1)
		"goblin_potion_hut":
			size = Vector3(3.4, 2.3, 3.2)
			top = _shack_storey(pivot, rng, 0.0, size, Color(0.72, 0.36, 0.14), true, 0.9)
		_:
			size = Vector3(2.9, 3.4, 2.9)
			top = _shack_storey(pivot, rng, 0.0, size, Color(0.2, 0.42, 0.26), true, 0.0)
			top = top - 0.9 + _shack_storey(pivot, rng, top - 0.9, Vector3(2.5, 2.4, 2.5), Color(0.16, 0.36, 0.22), false, 1.1)
	b.footprint = maxf(size.x, size.z) * 0.5 + 1.2
	var w := size.x
	var d := size.z
	# Sharpened stakes and a heap of bones round the bottom.
	var yard := MeshBuilder.new()
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.3, 0.3)
		if absf(angle_difference(a, 0.0)) < 0.6:
			continue
		var out := Vector3(cos(a), 0, sin(a))
		var base := out * (b.footprint - 0.5) + Vector3(0, -0.3, 0)
		yard.color = Color(0.32, 0.22, 0.13)
		yard.add_tube(PackedVector3Array([base, base + out * 0.5 + Vector3(0, rng.randf_range(1.1, 1.7), 0)]), PackedFloat32Array([0.11, 0.015]), 5)
	for k in 4:
		var at := Vector3(w * 0.5 + rng.randf_range(0.5, 1.2), 0.12, rng.randf_range(0.9, d * 0.5 + 0.6) * (1.0 if k % 2 == 0 else -1.0))
		if k == 0:
			_skull(yard, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at + Vector3(0, 0.1, 0)), 0.4)
		else:
			var a := rng.randf() * TAU
			_bone(yard, at, at + Vector3(cos(a), 0.1, sin(a)) * 0.7, 0.07)
	var glow := MeshBuilder.new()
	match kind:
		"goblin_tent":
			# A crooked stove pipe.
			yard.color = Color(0.3, 0.3, 0.34)
			yard.add_tube(PackedVector3Array([Vector3(-0.8, top - 0.9, -0.6), Vector3(-0.8, top + 0.5, -0.6), Vector3(-1.3, top + 0.9, -0.7)]),
				PackedFloat32Array([0.16, 0.16, 0.17]), 7)
		"goblin_war_hut":
			# A banner on a pole.
			yard.color = Color(0.3, 0.2, 0.12)
			yard.add_tube(PackedVector3Array([Vector3(w * 0.5 + 0.2, -0.3, d * 0.5 + 0.5), Vector3(w * 0.5 + 0.5, top + 0.6, d * 0.5 + 0.7)]),
				PackedFloat32Array([0.09, 0.06]), 5)
			yard.color = Color(0.6, 0.12, 0.1)
			yard.add_box(Vector3(0.05, 1.5, 0.85), 0.01, Transform3D(Basis(), Vector3(w * 0.5 + 0.5, top - 0.35, d * 0.5 + 1.15)))
			_skull(yard, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5 + 0.56, top - 0.2, d * 0.5 + 1.15)), 0.4)
		"goblin_forge":
			# A stone furnace with a glowing mouth, and an anvil on a stump.
			var fz := -d * 0.5 - 1.0
			yard.color = Color(0.46, 0.45, 0.42)
			yard.add_lathe(PackedVector2Array([Vector2(1.05, -0.4), Vector2(1.0, 1.2), Vector2(0.55, 2.3), Vector2(0.42, 4.2), Vector2(0.5, 4.3),
				Vector2(0.0, 4.3)]), 10, Transform3D(Basis(), Vector3(0.4, 0, fz)))
			yard.color = INK
			yard.add_blob(Vector3(0.2, 0.5, 0.5), Transform3D(Basis(), Vector3(1.4, 0.75, fz)), null, 0.0, 5, 8)
			glow.color = Color(1.0, 0.42, 0.1)
			glow.add_blob(Vector3(0.12, 0.34, 0.36), Transform3D(Basis(), Vector3(1.5, 0.7, fz)), null, 0.0, 5, 8)
			glow.add_blob(Vector3(0.3, 0.12, 0.3), Transform3D(Basis(), Vector3(0.4, 4.32, fz)), null, 0.0, 5, 8)
			yard.color = Color(0.34, 0.24, 0.14)
			yard.add_tube(PackedVector3Array([Vector3(w * 0.5 + 1.1, -0.3, -1.3), Vector3(w * 0.5 + 1.1, 0.55, -1.3)]), PackedFloat32Array([0.36, 0.32]), 9)
			yard.color = Color(0.2, 0.2, 0.24)
			yard.add_box(Vector3(0.34, 0.2, 0.75), 0.03, Transform3D(Basis(), Vector3(w * 0.5 + 1.1, 0.78, -1.3)))
			yard.add_box(Vector3(0.22, 0.2, 0.36), 0.03, Transform3D(Basis(), Vector3(w * 0.5 + 1.1, 0.62, -1.3)))
		"goblin_potion_hut":
			# A cauldron of something green, a shelf of bottles and toadstools.
			var cz := d * 0.5 + 1.1
			yard.color = Color(0.14, 0.14, 0.17)
			yard.add_lathe(PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.5, 0.15), Vector2(0.66, 0.55), Vector2(0.52, 0.95), Vector2(0.58, 1.0),
				Vector2(0.5, 1.0), Vector2(0.0, 0.9)]), 10, Transform3D(Basis(), Vector3(w * 0.5 + 0.5, 0, cz)))
			glow.color = Color(0.4, 1.0, 0.3)
			glow.add_blob(Vector3(0.48, 0.1, 0.48), Transform3D(Basis(), Vector3(w * 0.5 + 0.5, 0.95, cz)), null, 0.0, 4, 10)
			yard.color = Color(0.34, 0.24, 0.14)
			yard.add_box(Vector3(0.4, 0.08, 1.7), 0.02, Transform3D(Basis(), Vector3(w * 0.5 + 0.3, 1.0, -0.2 - d * 0.25)))
			for k in 5:
				glow.color = [Color(0.4, 1.0, 0.3), Color(0.72, 0.3, 1.0), Color(0.3, 0.8, 1.0)][k % 3]
				glow.add_blob(Vector3(0.1, 0.14, 0.1), Transform3D(Basis(), Vector3(w * 0.5 + 0.3, 1.18, -0.2 - d * 0.25 + (k - 2) * 0.3)), null, 0.0, 4, 6)
			for k in 4:
				var at := Vector3(rng.randf_range(-1.0, 1.0), 0, -d * 0.5 - rng.randf_range(0.6, 1.1))
				yard.color = Color(0.9, 0.88, 0.8)
				yard.add_tube(PackedVector3Array([at + Vector3(0, -0.1, 0), at + Vector3(0, 0.4, 0)]), PackedFloat32Array([0.08, 0.06]), 5)
				yard.color = Color(0.6, 0.3, 0.75)
				yard.add_lathe(PackedVector2Array([Vector2(0.26, 0.36), Vector2(0.2, 0.5), Vector2(0.0, 0.58)]), 7, Transform3D(Basis(), at))
		_:
			# A ladder up the side of the watchtower.
			yard.color = Color(0.3, 0.2, 0.12)
			for sx: float in [-1.0, 1.0]:
				yard.add_tube(PackedVector3Array([Vector3(sx * 0.3, -0.3, d * 0.5 + 1.0), Vector3(sx * 0.3, top - 3.0, d * 0.5 + 0.1)]), PackedFloat32Array([0.05, 0.05]), 4)
			for k in 8:
				var p := Vector3(0, -0.3, d * 0.5 + 1.0).lerp(Vector3(0, top - 3.0, d * 0.5 + 0.1), (k + 0.5) / 8.0)
				yard.add_tube(PackedVector3Array([p - Vector3(0.34, 0, 0), p + Vector3(0.34, 0, 0)]), PackedFloat32Array([0.04, 0.04]), 4)
	var yard_part := _part(pivot, yard.commit(), Art.paint("plaster", 0.5))
	if not glow.is_empty():
		_child(yard_part, glow.commit(), Art.glow(2.6))
	if is_instance_valid(Game.effects) and (kind == "goblin_forge" or kind == "goblin_potion_hut" or kind == "goblin_tent"):
		var smoke := Game.effects.make_smoke(0.4)
		yard_part.add_child(smoke)
		match kind:
			"goblin_forge":
				smoke.position = Vector3(0.4, 4.6, -d * 0.5 - 1.0)
			"goblin_potion_hut":
				smoke.position = Vector3(w * 0.5 + 0.5, 1.3, d * 0.5 + 1.1)
			_:
				smoke.position = Vector3(-1.4, top + 1.1, -0.7)
	return top + 0.9


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
	for sx: float in [-1.0, 1.0]:
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
