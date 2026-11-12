class_name BuildingFactory
extends RefCounted
## Generates funky buildings and trees out of primitive meshes.
##
## Every structural piece is tagged with the "debris" meta so it can fly apart
## when the structure is destroyed. Small details (windows, doors, spots) are
## children of those pieces and travel with them.
## The same RNG seed always produces the same building.

const WALL_COLORS := [
	Color(0.96, 0.65, 0.76), Color(0.66, 0.90, 0.81), Color(1.0, 0.83, 0.65),
	Color(0.76, 0.69, 0.88), Color(0.99, 0.99, 0.59), Color(0.60, 0.82, 0.96),
	Color(1.0, 0.70, 0.65), Color(0.71, 0.92, 0.84)]
const ROOF_COLORS := [
	Color(0.75, 0.22, 0.17), Color(0.56, 0.27, 0.68), Color(0.90, 0.49, 0.13),
	Color(0.17, 0.50, 0.72), Color(0.09, 0.63, 0.52), Color(0.83, 0.33, 0.0),
	Color(0.42, 0.20, 0.51)]
const ACCENT_COLORS := [
	Color(0.95, 0.77, 0.06), Color(0.93, 0.94, 0.95), Color(0.91, 0.26, 0.58),
	Color(0.0, 0.81, 0.79)]

static var _window_dark: StandardMaterial3D
static var _window_lit: StandardMaterial3D
static var _door_mat: StandardMaterial3D


# --- Buildings --------------------------------------------------------------

static func create_building(rng: RandomNumberGenerator) -> Destructible:
	_ensure_shared_materials()
	var b := Destructible.new()
	b.name = "Building"
	b.is_building = true
	var wall := _mat(b, _pick(rng, WALL_COLORS))
	var roof := _mat(b, _pick(rng, ROOF_COLORS))
	var accent := _mat(b, _pick(rng, ACCENT_COLORS))
	var top := 0.0
	match rng.randi_range(0, 4):
		0:
			top = _build_stack(b, rng, wall, roof, accent)
		1:
			top = _build_mushroom(b, rng, roof, accent)
		2:
			top = _build_crooked_tower(b, rng, wall, roof, accent)
		3:
			top = _build_dome(b, rng, wall, roof, accent)
		_:
			top = _build_bubbles(b, rng, wall, roof, accent)
	b.height = top
	b.max_hp = 70.0 + top * 5.0
	b.hp = b.max_hp
	b.flammability = 0.35
	b.burn_duration = rng.randf_range(16.0, 26.0)
	_add_collider(b, b.footprint * 0.8, top)
	return b


## Stacked, twisted boxes with a random roof.
static func _build_stack(b: Destructible, rng: RandomNumberGenerator, wall: Material, roof: Material, accent: Material) -> float:
	var floors := rng.randi_range(1, 4)
	var w := rng.randf_range(3.6, 5.4)
	var d := rng.randf_range(3.6, 5.4)
	b.footprint = maxf(w, d) * 0.62
	var y := 0.0
	var twist := 0.0
	var lean := Vector2.ZERO
	for f in floors:
		var fh := rng.randf_range(2.4, 3.2)
		# The ground floor reaches into the ground so slopes never show a gap.
		var sink := 1.0 if f == 0 else 0.0
		var box := BoxMesh.new()
		box.size = Vector3(w, fh + sink, d)
		var mat := wall if f % 2 == 0 or rng.randf() < 0.5 else accent
		var node := _part(b, box, mat, Vector3(lean.x, y + (fh - sink) * 0.5, lean.y), Vector3(0, twist, 0))
		_add_box_windows(node, rng, w, fh, d, sink * 0.5, f == 0)
		y += fh
		twist += rng.randf_range(-0.35, 0.35)
		lean += Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
		w = maxf(2.6, w * rng.randf_range(0.82, 1.12))
		d = maxf(2.6, d * rng.randf_range(0.82, 1.12))

	var rw := maxf(w, d)
	var rh := rng.randf_range(2.2, 4.5)
	var roof_pos := Vector3(lean.x, y + rh * 0.5, lean.y)
	match rng.randi_range(0, 3):
		0: # Square pyramid
			var pyr := _cone(rw * 0.78, rh, 4)
			_part(b, pyr, roof, roof_pos, Vector3(0, twist + PI / 4.0, 0))
		1: # Floppy witch hat
			rh = rng.randf_range(3.5, 6.0)
			var hat := _cone(rw * 0.62, rh, 16)
			_part(b, hat, roof, Vector3(lean.x, y + rh * 0.5, lean.y),
				Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)))
		2: # Gable roof
			var prism := PrismMesh.new()
			prism.size = Vector3(w * 1.12, rh, d * 1.12)
			_part(b, prism, roof, roof_pos, Vector3(0, twist, 0))
		_: # Onion dome with a spike
			var onion := _sphere(rw * 0.55, rh * 1.2)
			_part(b, onion, roof, Vector3(lean.x, y + rh * 0.45, lean.y))
			_part(b, _cone(0.25, 1.6, 8), accent, Vector3(lean.x, y + rh * 1.05 + 0.7, lean.y))
			rh += 1.6
	if rng.randf() < 0.5:
		var chimney := BoxMesh.new()
		chimney.size = Vector3(0.6, 1.8, 0.6)
		_part(b, chimney, accent, Vector3(lean.x + w * 0.25, y + 0.9, lean.y + d * 0.2))
	return y + rh


## A mushroom house: fat stem, spotted cap.
static func _build_mushroom(b: Destructible, rng: RandomNumberGenerator, roof: Material, accent: Material) -> float:
	var stem_r := rng.randf_range(1.4, 2.0)
	var stem_h := rng.randf_range(3.0, 4.5)
	var cream := _mat(b, Color(0.96, 0.92, 0.82))
	var stem := CylinderMesh.new()
	stem.top_radius = stem_r * 0.85
	stem.bottom_radius = stem_r
	stem.height = stem_h + 1.0
	var stem_node := _part(b, stem, cream, Vector3(0, (stem_h - 1.0) * 0.5, 0))
	var ground_local := -(stem_h - 1.0) * 0.5
	var door := BoxMesh.new()
	door.size = Vector3(0.9, 1.6, 0.3)
	_detail(stem_node, door, _door_mat, Vector3(0, ground_local + 0.8, stem_r * 0.9))
	_porthole(stem_node, rng, Vector3(0, ground_local + 2.4, 0), stem_r * 0.88, rng.randf_range(-0.6, 0.6))

	var cap_r := stem_r * rng.randf_range(1.8, 2.4)
	var cap_h := cap_r * rng.randf_range(1.0, 1.3)
	var cap := _sphere(cap_r, cap_h)
	var cap_node := _part(b, cap, roof, Vector3(0, stem_h + cap_h * 0.15, 0))
	for k in rng.randi_range(5, 9):
		var a := rng.randf() * TAU
		var p := rng.randf_range(0.2, 1.2)
		var dir := Vector3(cos(a) * sin(p), cos(p), sin(a) * sin(p))
		var spot := _sphere(rng.randf_range(0.3, 0.55), 0.5)
		_detail(cap_node, spot, accent, Vector3(dir.x * cap_r, dir.y * cap_h * 0.5, dir.z * cap_r))
	b.footprint = cap_r * 0.8
	return stem_h + cap_h * 0.65


## A leaning stack of cylinders with a pointy hat.
static func _build_crooked_tower(b: Destructible, rng: RandomNumberGenerator, wall: Material, roof: Material, accent: Material) -> float:
	var r := rng.randf_range(1.7, 2.4)
	b.footprint = r * 1.1
	var y := 0.0
	var drift := Vector2.ZERO
	var drift_dir := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.2, 0.5)
	for s in rng.randi_range(3, 5):
		var sh := rng.randf_range(2.4, 3.4)
		var sink := 1.0 if s == 0 else 0.0
		var cyl := CylinderMesh.new()
		cyl.top_radius = r * 0.95
		cyl.bottom_radius = r
		cyl.height = sh + sink
		var mat := wall if s % 2 == 0 else accent
		var node := _part(b, cyl, mat, Vector3(drift.x, y + (sh - sink) * 0.5, drift.y),
			Vector3(drift.y * 0.08, 0, -drift.x * 0.08))
		_porthole(node, rng, Vector3(0, sink * 0.5, 0), r * 0.97, rng.randf() * TAU)
		if s == 0:
			var door := BoxMesh.new()
			door.size = Vector3(0.9, 1.7, 0.4)
			_detail(node, door, _door_mat, Vector3(0, sink * 0.5 - sh * 0.5 + 0.85, r * 0.95))
		y += sh
		drift += drift_dir
		r *= rng.randf_range(0.85, 0.97)
	var hat_h := rng.randf_range(3.5, 6.0)
	var hat := _cone(r * 1.35, hat_h, 14)
	_part(b, hat, roof, Vector3(drift.x, y + hat_h * 0.5, drift.y),
		Vector3(drift_dir.y * 0.4, 0, -drift_dir.x * 0.4))
	return y + hat_h


## A half-buried dome with a tunnel door and an antenna.
static func _build_dome(b: Destructible, rng: RandomNumberGenerator, wall: Material, roof: Material, accent: Material) -> float:
	var r := rng.randf_range(2.8, 3.8)
	var squash := rng.randf_range(1.3, 1.8)
	b.footprint = r
	var dome := _sphere(r, r * squash)
	var node := _part(b, dome, wall, Vector3.ZERO)
	var tunnel := CylinderMesh.new()
	tunnel.top_radius = 1.0
	tunnel.bottom_radius = 1.0
	tunnel.height = 2.0
	var tunnel_node := _part(b, tunnel, accent, Vector3(0, 0.6, r * 0.85), Vector3(PI / 2.0, 0, 0))
	var door := BoxMesh.new()
	door.size = Vector3(1.0, 0.3, 1.2)
	_detail(tunnel_node, door, _door_mat, Vector3(0, 1.0, 0.0))
	for k in rng.randi_range(2, 4):
		var a := rng.randf_range(-2.4, 2.4)
		_porthole(node, rng, Vector3(0, r * squash * 0.18, 0), r * 0.9, a + PI)
	var top := r * squash * 0.5
	var mast := CylinderMesh.new()
	mast.top_radius = 0.08
	mast.bottom_radius = 0.12
	mast.height = 2.4
	_part(b, mast, accent, Vector3(0, top + 1.0, 0))
	_part(b, _sphere(0.45, 0.9), roof, Vector3(0, top + 2.3, 0))
	return top + 2.7


## A wobbly snowman of spheres.
static func _build_bubbles(b: Destructible, rng: RandomNumberGenerator, wall: Material, roof: Material, accent: Material) -> float:
	var r := rng.randf_range(2.4, 3.2)
	b.footprint = r
	var y := r * 0.55
	var offset := Vector2.ZERO
	for k in rng.randi_range(2, 4):
		var mat := wall if k % 2 == 0 else accent
		var node := _part(b, _sphere(r, r * 2.0 * rng.randf_range(0.85, 1.0)), mat, Vector3(offset.x, y, offset.y))
		_porthole(node, rng, Vector3(0, r * 0.1, 0), r * 0.92, rng.randf() * TAU)
		if k == 0:
			var door := BoxMesh.new()
			door.size = Vector3(1.0, 1.7, 0.6)
			_detail(node, door, _door_mat, Vector3(0, -r * 0.55 + 0.85, r * 0.8))
		var next_r := r * rng.randf_range(0.6, 0.8)
		y += r * 0.75 + next_r * 0.75
		offset += Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
		r = next_r
	var hat_h := rng.randf_range(1.5, 3.0)
	_part(b, _cone(r * 0.9, hat_h, 10), roof, Vector3(offset.x, y - r * 0.6 + hat_h * 0.5, offset.y))
	return y - r * 0.6 + hat_h


# --- Trees ------------------------------------------------------------------

static func create_tree(rng: RandomNumberGenerator) -> Destructible:
	var t := Destructible.new()
	t.name = "Tree"
	t.is_building = false
	var s := rng.randf_range(0.8, 1.5)
	var trunk_mat := _mat(t, Color(0.42, 0.29, 0.18))
	var kind := rng.randi_range(0, 9)
	var top := 0.0
	if kind < 4:
		# Pine: stacked cones.
		var green := _mat(t, Color(0.13, 0.42, 0.24).lerp(Color(0.2, 0.5, 0.3), rng.randf()))
		_part(t, _cylinder(0.25 * s, 0.32 * s, 2.4 * s), trunk_mat, Vector3(0, 1.0 * s, 0))
		var y := 1.8 * s
		var r := 1.9 * s
		for k in 3:
			var h := 2.3 * s
			_part(t, _cone(r, h, 10), green, Vector3(0, y + h * 0.5, 0))
			y += h * 0.55
			r *= 0.72
		top = y + 1.0 * s
	elif kind < 8:
		# Round leafy blobs.
		var green := _mat(t, Color(0.30, 0.62, 0.22).lerp(Color(0.45, 0.70, 0.25), rng.randf()))
		_part(t, _cylinder(0.25 * s, 0.35 * s, 3.2 * s), trunk_mat, Vector3(0, 1.3 * s, 0))
		var r := 1.6 * s
		_part(t, _sphere(r, r * 1.8), green, Vector3(0, 3.6 * s, 0))
		for k in rng.randi_range(1, 2):
			var a := rng.randf() * TAU
			_part(t, _sphere(r * 0.6, r * 1.1), green,
				Vector3(cos(a) * r * 0.8, 3.1 * s, sin(a) * r * 0.8))
		top = 3.6 * s + r * 0.9
	else:
		# Funky lollipop tree.
		var colors := [Color(0.95, 0.45, 0.75), Color(0.55, 0.4, 0.9), Color(0.2, 0.8, 0.8), Color(1.0, 0.6, 0.2)]
		var candy := _mat(t, _pick(rng, colors))
		_part(t, _cylinder(0.12 * s, 0.18 * s, 4.6 * s), trunk_mat, Vector3(0, 1.9 * s, 0),
			Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)))
		var r := 1.3 * s
		_part(t, _sphere(r, r * 2.0), candy, Vector3(0, 4.4 * s + r * 0.6, 0))
		top = 4.4 * s + r * 1.6
	t.height = top
	t.footprint = 1.2 * s
	t.max_hp = 45.0
	t.hp = t.max_hp
	t.flammability = 0.6
	t.burn_duration = rng.randf_range(8.0, 12.0)
	_add_collider(t, 0.35 * s, top * 0.6)
	return t


# --- Ghost previews ---------------------------------------------------------

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


# --- Helpers ------------------------------------------------------------------

static func _ensure_shared_materials() -> void:
	if _window_dark != null:
		return
	_window_dark = StandardMaterial3D.new()
	_window_dark.albedo_color = Color(0.12, 0.16, 0.28)
	_window_dark.roughness = 0.2
	_window_lit = StandardMaterial3D.new()
	_window_lit.albedo_color = Color(1.0, 0.85, 0.45)
	_window_lit.emission_enabled = true
	_window_lit.emission = Color(1.0, 0.75, 0.35)
	_window_lit.emission_energy_multiplier = 0.6
	_door_mat = StandardMaterial3D.new()
	_door_mat.albedo_color = Color(0.36, 0.22, 0.14)


static func _pick(rng: RandomNumberGenerator, options: Array) -> Color:
	return options[rng.randi() % options.size()]


static func _mat(owner: Destructible, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	owner.register_material(m)
	return m


static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.set_meta("debris", true)
	parent.add_child(mi)
	return mi


## Small decoration that rides along with its parent piece.
static func _detail(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _add_box_windows(node: Node3D, rng: RandomNumberGenerator, w: float, h: float, d: float, y_center: float, ground_floor: bool) -> void:
	var y := y_center + 0.1
	# Faces: +z, -z, +x, -x. Each gets one or two windows.
	for face in 4:
		var along := w if face < 2 else d
		var count := 2 if along > 4.2 else 1
		for k in count:
			var offset := 0.0 if count == 1 else (k - 0.5) * along * 0.45
			if ground_floor and face == 0 and k == 0:
				var door := BoxMesh.new()
				door.size = Vector3(1.0, 1.7, 0.14)
				_detail(node, door, _door_mat, Vector3(offset, y_center - h * 0.5 + 0.85, d * 0.5 + 0.04))
				continue
			var win := BoxMesh.new()
			var mat := _window_lit if rng.randf() < 0.3 else _window_dark
			match face:
				0:
					win.size = Vector3(0.8, 0.9, 0.12)
					_detail(node, win, mat, Vector3(offset, y, d * 0.5 + 0.04))
				1:
					win.size = Vector3(0.8, 0.9, 0.12)
					_detail(node, win, mat, Vector3(offset, y, -d * 0.5 - 0.04))
				2:
					win.size = Vector3(0.12, 0.9, 0.8)
					_detail(node, win, mat, Vector3(w * 0.5 + 0.04, y, offset))
				_:
					win.size = Vector3(0.12, 0.9, 0.8)
					_detail(node, win, mat, Vector3(-w * 0.5 - 0.04, y, offset))


## A round window on a curved surface, facing outwards at `angle`.
static func _porthole(node: Node3D, rng: RandomNumberGenerator, center: Vector3, radius: float, angle: float) -> void:
	var disc := _cylinder(0.42, 0.42, 0.25)
	var mat := _window_lit if rng.randf() < 0.3 else _window_dark
	var pos := center + Vector3(sin(angle), 0, cos(angle)) * radius
	_detail(node, disc, mat, pos, Vector3(PI / 2.0, angle, 0))


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


static func _sphere(radius: float, height: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = height
	s.radial_segments = 24
	s.rings = 12
	return s


static func _cone(radius: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 12
	c.rings = 1
	return c
