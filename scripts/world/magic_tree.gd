class_name MagicTree
extends Node3D
## The giant magic tree the squirrel plants by tossing a magic acorn (see
## MagicAcorn, CreatureMind's forest seeding). It grows from a sprig to a
## tree as big as the Storehouse's over Balance "magic_tree_grow_days"
## days, and gives the village magicko all the while: Balance
## "magic_tree_magicko_small" a minute when tiny, rising to
## "magic_tree_magicko_full" when full grown. Now and then it drops a seed
## that becomes a sapling of an ordinary tree (Balance
## "magic_tree_seed_minutes"), and pixies flit about its crown. It is not a
## tree for chopping: villagers leave it alone.

## How big it starts, as a share of its full size.
const SMALL := 0.1
## Its full height, and where its crown sits, in metres.
const HEIGHT := 15.0
const CROWN := 11.5
const MOST_PIXIES := 4
const BARK := Color(0.42, 0.3, 0.36)
const LEAF := Color(0.42, 0.95, 0.78)
const LEAF_DARK := Color(0.3, 0.32, 0.86)
const GLOW := Color(0.85, 1.0, 0.55)

var _age := 0.0
var _visual: Node3D
var _seed_due := 0.0
var _pixie_due := 0.0
var _pixies: Array[Pixie] = []


func _ready() -> void:
	add_to_group("magic_trees")
	_visual = Node3D.new()
	add_child(_visual)
	_build()
	_visual.scale = Vector3.ONE * SMALL
	_seed_due = Balance.num("magic_tree_seed_minutes") * 60.0
	_pixie_due = randf_range(8.0, 20.0)


## How far grown it is, 0..1.
func share() -> float:
	var days := maxf(0.01, Balance.num("magic_tree_grow_days")) * maxf(0.1, Game.settings.day_minutes) * 60.0
	return clampf(_age / days, 0.0, 1.0)


## Magicko it gives the village a minute, now.
func magicko_rate() -> float:
	return lerpf(Balance.num("magic_tree_magicko_small"), Balance.num("magic_tree_magicko_full"), share())


## Where its crown is now, in the world.
func crown() -> Vector3:
	return global_position + Vector3.UP * CROWN * _visual.scale.y


## How far its crown spreads now.
func crown_radius() -> float:
	return 5.5 * _visual.scale.x


func _process(delta: float) -> void:
	_age += delta
	var grown := share()
	_visual.scale = Vector3.ONE * lerpf(SMALL, 1.0, grown)
	var village := Game.village
	if is_instance_valid(village) and village.founded:
		village.give("magicko", magicko_rate() / 60.0 * delta)
	_seed_due -= delta
	if _seed_due <= 0.0:
		_seed_due = maxf(5.0, Balance.num("magic_tree_seed_minutes") * 60.0 * randf_range(0.7, 1.3))
		_drop_seed()
	for p in _pixies.duplicate():
		if not is_instance_valid(p):
			_pixies.erase(p)
	_pixie_due -= delta
	if _pixie_due <= 0.0:
		_pixie_due = randf_range(15.0, 40.0)
		if _pixies.size() < MOST_PIXIES and grown > 0.15:
			var pixie := Pixie.new()
			pixie.tree = self
			add_child(pixie)
			_pixies.append(pixie)


## A glowing seed falls from the crown and becomes a sapling where it lands.
func _drop_seed() -> void:
	if share() < 0.25 or not is_instance_valid(Game.village):
		return
	var terrain := Game.terrain
	for attempt in 10:
		var a := randf() * TAU
		var p := global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(6.0, 18.0)
		if not terrain.is_inside(p.x, p.z) or not terrain.is_dry(p.x, p.z) or terrain.get_normal(p.x, p.z).y < 0.85:
			continue
		p.y = terrain.get_height(p.x, p.z)
		if Game.village._crowded(p, get_tree()):
			continue
		var seed := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.18
		ball.height = 0.36
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = GLOW
		ball.material = mat
		seed.mesh = ball
		get_parent().add_child(seed)
		seed.global_position = crown() + Vector3(cos(a), 0.0, sin(a)) * crown_radius() * 0.6
		var fall := seed.create_tween()
		fall.tween_property(seed, "global_position", p + Vector3.UP * 0.2, 2.5).set_trans(Tween.TRANS_SINE)
		fall.tween_callback(func() -> void:
			Sapling.plant(p)
			Game.effects.spawn_dust(p, 0.4)
			seed.queue_free())
		return


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	# A thick, twisting trunk on spreading roots.
	var wood := MeshBuilder.new()
	wood.color = BARK
	var twist := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
	wood.add_tube(PackedVector3Array([Vector3(0, -1.2, 0), Vector3(0, 0.6, 0), twist * 0.6 + Vector3(0, 4.0, 0),
		-twist * 0.5 + Vector3(0, 7.5, 0), twist * 0.3 + Vector3(0, CROWN - 1.0, 0)]),
		PackedFloat32Array([2.4, 1.8, 1.3, 1.05, 0.8]), 14)
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf()
		var out := Vector3(cos(a), 0, sin(a))
		wood.add_tube(PackedVector3Array([out * 1.0 + Vector3(0, 1.2, 0), out * 2.8 + Vector3(0, 0.3, 0), out * 4.2 + Vector3(0, -0.6, 0)]),
			PackedFloat32Array([0.65, 0.42, 0.2]), 7)
	# Boughs out to the crown.
	var leaves := [MeshBuilder.new(), MeshBuilder.new()]
	leaves[0].color = Color(1, 1, 1)
	leaves[1].color = Color(0.85, 0.85, 0.85)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.25
	var top := Vector3(0, CROWN, 0)
	leaves[0].add_blob(Vector3(4.6, 3.2, 4.6), Transform3D(Basis(), top + Vector3(0, 1.0, 0)), noise, 0.22, 10, 16)
	var lights: Array[Vector3] = []
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var from := Vector3(0, CROWN - rng.randf_range(2.5, 4.0), 0)
		var tip := from + out * rng.randf_range(3.8, 5.0) + Vector3(0, rng.randf_range(1.0, 2.2), 0)
		wood.add_tube(PackedVector3Array([from, from.lerp(tip, 0.5) + Vector3(0, -0.4, 0), tip]), PackedFloat32Array([0.55, 0.38, 0.22]), 7)
		var r := rng.randf_range(2.3, 2.9)
		leaves[k % 2].add_blob(Vector3(r, r * 0.8, r), Transform3D(Basis(), tip + Vector3(0, r * 0.4, 0)), noise, 0.22, 9, 14)
		lights.append(tip + Vector3(0, -r * 0.55, 0))
	_mesh(wood, Art.paint("bark"))
	var leaf := Art.surface("hide", LEAF, LEAF_DARK, {"ink": 0.45})
	for builder: MeshBuilder in leaves:
		_mesh(builder, leaf)
	# Glowing fruit hanging under the boughs, and a soft light.
	var fruit := SphereMesh.new()
	fruit.radius = 0.32
	fruit.height = 0.64
	fruit.radial_segments = 10
	fruit.rings = 5
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = GLOW
	fruit.material = glow
	for p in lights:
		var mi := MeshInstance3D.new()
		mi.mesh = fruit
		mi.position = p
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(mi)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.6, 1.0, 0.7)
	lamp.light_energy = 1.4
	lamp.omni_range = 14.0
	lamp.position = Vector3(0, CROWN - 1.5, 0)
	_visual.add_child(lamp)
	# Magic drifting up through the crown.
	var sparkles := CPUParticles3D.new()
	var dot := QuadMesh.new()
	dot.size = Vector2(0.18, 0.18)
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.vertex_color_use_as_albedo = true
	dot.material = spark
	sparkles.mesh = dot
	sparkles.amount = 40
	sparkles.lifetime = 3.0
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 5.0
	sparkles.gravity = Vector3(0, 0.4, 0)
	sparkles.initial_velocity_min = 0.1
	sparkles.initial_velocity_max = 0.4
	var fade := Gradient.new()
	fade.set_color(0, Color(GLOW, 0.0))
	fade.set_color(1, Color(LEAF, 0.0))
	fade.add_point(0.3, Color(GLOW, 1.0))
	sparkles.color_ramp = fade
	sparkles.position = Vector3(0, CROWN, 0)
	_visual.add_child(sparkles)


func _mesh(mb: MeshBuilder, material: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = material
	_visual.add_child(mi)
