class_name Effects
extends Node3D
## Builds and spawns visual effects (fire, smoke, explosions, dust, markers)
## and owns the physics debris that destroyed objects break into.

const MAX_DEBRIS := 450
const MAX_FIRE_LIGHTS := 16
const DEBRIS_LIFETIME := 11.0

var _fire_lights_in_use := 0

var _flame_mesh: QuadMesh
var _smoke_mesh: QuadMesh
var _fire_gradient: Gradient
var _smoke_gradient: Gradient
var _dust_gradient: Gradient
var _grow_shrink: Curve
var _grow: Curve
var _debris: Array[Dictionary] = []


func _ready() -> void:
	var soft := _soft_circle_texture()
	_flame_mesh = _particle_quad(soft, BaseMaterial3D.BLEND_MODE_MIX, 1.6)
	_smoke_mesh = _particle_quad(soft, BaseMaterial3D.BLEND_MODE_MIX, 2.0)
	_fire_gradient = _gradient([0.0, 0.2, 0.55, 1.0], [
		Color(1.0, 0.9, 0.35, 1.0),
		Color(1.0, 0.5, 0.05, 1.0),
		Color(0.85, 0.15, 0.02, 0.8),
		Color(0.25, 0.08, 0.04, 0.0)])
	_smoke_gradient = _gradient([0.0, 0.15, 1.0], [
		Color(0.16, 0.14, 0.13, 0.0),
		Color(0.15, 0.14, 0.13, 0.7),
		Color(0.35, 0.34, 0.34, 0.0)])
	_dust_gradient = _gradient([0.0, 0.15, 1.0], [
		Color(0.62, 0.55, 0.42, 0.0),
		Color(0.6, 0.53, 0.4, 0.6),
		Color(0.7, 0.65, 0.55, 0.0)])
	_grow_shrink = Curve.new()
	_grow_shrink.add_point(Vector2(0.0, 0.35))
	_grow_shrink.add_point(Vector2(0.25, 1.0))
	_grow_shrink.add_point(Vector2(1.0, 0.1))
	_grow = Curve.new()
	_grow.add_point(Vector2(0.0, 0.3))
	_grow.add_point(Vector2(1.0, 1.0))


func _process(delta: float) -> void:
	for k in range(_debris.size() - 1, -1, -1):
		var d := _debris[k]
		var body: RigidBody3D = d.body
		if not is_instance_valid(body):
			_debris.remove_at(k)
			continue
		d.age += delta
		var life: float = d.life
		var age: float = d.age
		if age > life or body.global_position.y < -25.0:
			_debris.remove_at(k)
			body.queue_free()
			continue
		if age > life - 1.0:
			var part: Node3D = d.part
			if is_instance_valid(part):
				var base: Vector3 = d.scale
				part.scale = base * clampf(life - age, 0.01, 1.0)


# --- Fire lights (capped so lots of fires stay cheap) ----------------------

func claim_fire_light() -> bool:
	if _fire_lights_in_use >= MAX_FIRE_LIGHTS:
		return false
	_fire_lights_in_use += 1
	return true


func release_fire_light() -> void:
	_fire_lights_in_use = maxi(0, _fire_lights_in_use - 1)


# --- Particle builders ------------------------------------------------------

func make_flames(size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _flame_mesh
	p.amount = clampi(int(18 * size), 8, 48)
	p.lifetime = 0.8
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 * size
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0.0, 2.5 * size, 0.0)
	p.initial_velocity_min = 0.8 * size
	p.initial_velocity_max = 2.0 * size
	p.scale_amount_min = 0.9 * size
	p.scale_amount_max = 1.7 * size
	p.scale_amount_curve = _grow_shrink
	p.color_ramp = _fire_gradient
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func make_smoke(size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _smoke_mesh
	p.amount = clampi(int(10 * size), 5, 30)
	p.lifetime = 3.2
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4 * size
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3(0.5, 1.0, 0.25) * size
	p.initial_velocity_min = 0.8 * size
	p.initial_velocity_max = 1.8 * size
	p.scale_amount_min = 1.4 * size
	p.scale_amount_max = 2.8 * size
	p.scale_amount_curve = _grow
	p.color_ramp = _smoke_gradient
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _burst(mesh: Mesh, gradient: Gradient, amount: int, lifetime: float, speed_min: float,
		speed_max: float, scale_min: float, scale_max: float, gravity: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = gravity
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.scale_amount_curve = _grow_shrink
	p.color_ramp = gradient
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _spawn_oneshot(p: CPUParticles3D, pos: Vector3, life: float) -> void:
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life).timeout.connect(p.queue_free)


# --- Spawnable effects -----------------------------------------------------

func spawn_explosion(pos: Vector3, radius: float) -> void:
	var fireball := _burst(_flame_mesh, _fire_gradient, 70, 0.9, radius * 0.6, radius * 1.7, 1.6, 3.8, Vector3(0, 2, 0))
	fireball.damping_min = radius * 0.9
	fireball.damping_max = radius * 1.5
	_spawn_oneshot(fireball, pos + Vector3.UP, 2.0)

	var sparks := _burst(_flame_mesh, _fire_gradient, 40, 1.3, radius * 1.2, radius * 2.6, 0.25, 0.6, Vector3(0, -14, 0))
	_spawn_oneshot(sparks, pos + Vector3.UP, 2.5)

	var smoke := _burst(_smoke_mesh, _smoke_gradient, 36, 3.5, radius * 0.25, radius * 0.8, 3.0, 6.5, Vector3(0.4, 1.4, 0.2))
	smoke.scale_amount_curve = _grow
	smoke.damping_min = radius * 0.2
	smoke.damping_max = radius * 0.4
	_spawn_oneshot(smoke, pos + Vector3.UP * 1.5, 5.0)

	_spawn_dirt(pos, radius)

	# Bright core that swells and fades.
	var flash_mat := _glow_material(Color(1.0, 0.55, 0.1, 0.9))
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.material = flash_mat
	var flash := MeshInstance3D.new()
	flash.mesh = sphere
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	flash.global_position = pos
	flash.scale = Vector3.ONE * 0.5
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * radius * 0.7, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash_mat, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(flash.queue_free)

	# Shockwave ring along the ground.
	var ring_mat := _glow_material(Color(1.0, 0.85, 0.6, 0.8))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.material = ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.4
	ring.scale = Vector3(1.0, 0.3, 1.0)
	var tw2 := ring.create_tween().set_parallel(true)
	tw2.tween_property(ring, "scale", Vector3(radius * 1.8, 0.3, radius * 1.8), 0.5).set_ease(Tween.EASE_OUT)
	tw2.tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
	tw2.chain().tween_callback(ring.queue_free)

	# Light flash.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 10.0
	light.omni_range = radius * 4.0
	add_child(light)
	light.global_position = pos + Vector3.UP * 2.0
	var tw3 := light.create_tween()
	tw3.tween_property(light, "light_energy", 0.0, 0.7)
	tw3.tween_callback(light.queue_free)


func _spawn_dirt(pos: Vector3, radius: float) -> void:
	var dirt := _burst(_smoke_mesh, _dust_gradient, 30, 1.8, radius * 0.8, radius * 1.6, 1.2, 2.6, Vector3(0, -9, 0))
	dirt.direction = Vector3.UP
	dirt.spread = 45.0
	_spawn_oneshot(dirt, pos, 3.0)


func spawn_dust(pos: Vector3, size: float) -> void:
	var dust := _burst(_smoke_mesh, _dust_gradient, 22, 1.6, 3.0 * size, 6.0 * size, 1.2 * size, 2.6 * size, Vector3(0, 0.4, 0))
	dust.spread = 90.0
	dust.flatness = 0.85
	dust.damping_min = 4.0 * size
	dust.damping_max = 6.0 * size
	dust.scale_amount_curve = _grow
	_spawn_oneshot(dust, pos + Vector3.UP * 0.3, 2.5)


## A ring that shrinks into the ground where a move order was given.
func spawn_marker(pos: Vector3) -> void:
	var mat := _glow_material(Color(0.4, 1.0, 0.5, 0.9))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.material = mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.3
	ring.scale = Vector3(2.5, 0.5, 2.5)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(0.6, 0.5, 0.6), 0.6)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(ring.queue_free)


# --- Debris -----------------------------------------------------------------

## Turns a mesh piece into a physics body thrown away from `from`.
func spawn_debris(part: MeshInstance3D, from: Vector3, force: float, on_fire: bool) -> void:
	if _debris.size() >= MAX_DEBRIS:
		return
	var xf := part.global_transform
	var s := xf.basis.get_scale()
	var aabb := part.get_aabb()
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1 | 2 | 4
	add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	part.reparent(body, true)
	part.transform = Transform3D(Basis.from_scale(s), Vector3.ZERO)

	var size := aabb.size * s
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.2), maxf(size.y, 0.2), maxf(size.z, 0.2))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = aabb.get_center() * s
	body.add_child(cs)
	body.mass = clampf(size.x * size.y * size.z * 0.4, 0.3, 40.0)

	var away := body.global_position - from
	var dist := away.length()
	away = away / dist if dist > 0.01 else Vector3.UP
	var push := force / (1.0 + dist * 0.12)
	body.linear_velocity = (away + Vector3.UP * 0.7).normalized() * push * randf_range(0.6, 1.2)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * clampf(push * 0.4, 0.5, 6.0)

	if on_fire and randf() < 0.3:
		var fire := FireEmitter.new()
		fire.size = 0.5
		fire.with_light = false
		body.add_child(fire)

	body.add_to_group("debris")
	_debris.append({"body": body, "part": part, "scale": s, "age": 0.0,
		"life": randf_range(DEBRIS_LIFETIME * 0.7, DEBRIS_LIFETIME)})


## Gives loose debris near an explosion an extra kick.
func push_debris(pos: Vector3, radius: float, force: float) -> void:
	for d in _debris:
		var body: RigidBody3D = d.body
		if not is_instance_valid(body):
			continue
		var away := body.global_position - pos
		var dist := away.length()
		if dist < radius and dist > 0.01:
			body.linear_velocity += (away / dist + Vector3.UP * 0.5) * force * (1.0 - dist / radius)


# --- Helpers ------------------------------------------------------------------

func _glow_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	return mat


func _particle_quad(tex: Texture2D, blend: BaseMaterial3D.BlendMode, size: float) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	return quad


func _soft_circle_texture() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = _gradient([0.0, 0.5, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


func _gradient(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g
