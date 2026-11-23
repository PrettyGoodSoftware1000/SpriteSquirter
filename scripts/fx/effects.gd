class_name Effects
extends Node3D
## Builds and spawns visual effects (fire, smoke, explosions, dust, markers)
## and owns the physics debris that destroyed objects break into.

const MAX_DEBRIS := 450
const MAX_FIRE_LIGHTS := 16
const DEBRIS_LIFETIME := 11.0

var _fire_lights_in_use := 0

var _flame_mesh: ArrayMesh
var _ember_mesh: QuadMesh
var _smoke_mesh: QuadMesh
var _dust_mesh: QuadMesh
var _fire_gradient: Gradient
var _ember_gradient: Gradient
var _smoke_gradient: Gradient
var _dust_gradient: Gradient
var _steam_gradient: Gradient
var _grow_shrink: Curve
var _flame_curve: Curve
var _grow: Curve
var _debris: Array[Dictionary] = []


func _ready() -> void:
	# A tongue of flame is a solid teardrop, so fires look right from above.
	var tongue := MeshBuilder.new()
	tongue.add_lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.14, 0.02), Vector2(0.22, 0.14), Vector2(0.23, 0.28),
		Vector2(0.17, 0.5), Vector2(0.09, 0.74), Vector2(0.03, 0.92), Vector2(0.0, 1.0)]), 9)
	_flame_mesh = tongue.commit()
	var flame_material := ShaderMaterial.new()
	flame_material.shader = Art.shader("flame")
	_flame_mesh.surface_set_material(0, flame_material)
	_ember_mesh = _sprite_quad("ember", 0.22)
	_smoke_mesh = _sprite_quad("smoke", 2.8)
	_dust_mesh = _sprite_quad("dust", 2.0)
	# Particle colours multiply the sprite: flames stay bright, then redden
	# and fade; smoke and dust fade in and out.
	# For flames only the alpha matters: the shader reads it as the tongue's age.
	_fire_gradient = _gradient([0.0, 0.35, 1.0], [
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.0)])
	_ember_gradient = _gradient([0.0, 0.7, 1.0], [
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.7, 0.5, 1.0),
		Color(1.0, 0.4, 0.2, 0.0)])
	_smoke_gradient = _gradient([0.0, 0.15, 0.6, 1.0], [
		Color(0.14, 0.12, 0.11, 0.0),
		Color(0.16, 0.14, 0.13, 0.75),
		Color(0.3, 0.29, 0.29, 0.5),
		Color(0.45, 0.45, 0.46, 0.0)])
	_dust_gradient = _gradient([0.0, 0.15, 1.0], [
		Color(0.58, 0.5, 0.38, 0.0),
		Color(0.58, 0.5, 0.38, 0.65),
		Color(0.68, 0.62, 0.52, 0.0)])
	_steam_gradient = _gradient([0.0, 0.15, 1.0], [
		Color(0.92, 0.94, 0.97, 0.0),
		Color(0.92, 0.94, 0.97, 0.6),
		Color(0.85, 0.88, 0.92, 0.0)])
	_grow_shrink = Curve.new()
	_grow_shrink.add_point(Vector2(0.0, 0.35))
	_grow_shrink.add_point(Vector2(0.25, 1.0))
	_grow_shrink.add_point(Vector2(1.0, 0.1))
	_flame_curve = Curve.new()
	_flame_curve.add_point(Vector2(0.0, 0.3))
	_flame_curve.add_point(Vector2(0.2, 1.0))
	_flame_curve.add_point(Vector2(0.7, 0.55))
	_flame_curve.add_point(Vector2(1.0, 0.0))
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
	# Each particle is one tongue of flame, a solid shape (see flame.gdshader):
	# many small ones round the base, a few tall ones leaping out of the middle.
	p.mesh = _flame_mesh
	p.amount = clampi(int(20 * size), 9, 48)
	p.lifetime = 1.0
	p.lifetime_randomness = 0.55
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.6, 0.12, 0.6) * size
	p.direction = Vector3.UP
	p.spread = 16.0
	p.gravity = Vector3(0.0, 3.0 * size, 0.0)
	p.initial_velocity_min = 0.3 * size
	p.initial_velocity_max = 2.4 * size
	p.scale_amount_min = 0.7 * size
	p.scale_amount_max = 2.6 * size
	p.scale_amount_curve = _flame_curve
	p.color_ramp = _fire_gradient
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Soft white spray for the top of a waterfall.
func make_mist(size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 3.0)
	quad.material = Art.particle("mist")
	p.mesh = quad
	p.amount = 14
	p.lifetime = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size
	p.direction = Vector3.DOWN
	p.spread = 30.0
	p.gravity = Vector3(0, -3.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.scale_amount_curve = _grow
	p.color_ramp = _gradient([0.0, 0.2, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Glowing sparks that drift up from a fire.
func make_embers(size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _ember_mesh
	p.amount = clampi(int(8 * size), 4, 20)
	p.lifetime = 2.2
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 * size
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0.6, 1.2, 0.3)
	p.initial_velocity_min = 1.5 * size
	p.initial_velocity_max = 4.0 * size
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _ember_gradient
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
	p.angle_min = -180.0
	p.angle_max = 180.0
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
	# Tongues of flame pointing every way.
	fireball.angle_min = -180.0
	fireball.angle_max = 180.0
	fireball.damping_min = radius * 0.9
	fireball.damping_max = radius * 1.5
	_spawn_oneshot(fireball, pos + Vector3.UP, 2.0)

	var sparks := _burst(_ember_mesh, _ember_gradient, 60, 1.5, radius * 1.2, radius * 2.8, 0.8, 2.2, Vector3(0, -14, 0))
	_spawn_oneshot(sparks, pos + Vector3.UP, 2.5)

	var smoke := _burst(_smoke_mesh, _smoke_gradient, 36, 3.5, radius * 0.25, radius * 0.8, 3.0, 6.5, Vector3(0.4, 1.4, 0.2))
	smoke.scale_amount_curve = _grow
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.damping_min = radius * 0.2
	smoke.damping_max = radius * 0.4
	_spawn_oneshot(smoke, pos + Vector3.UP * 1.5, 5.0)

	_spawn_dirt(pos, radius)

	# Bright core that swells and fades.
	var flash_mat := _glow_material(Color(3.0, 1.6, 0.4, 0.9))
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
	var ring_mat := _glow_material(Color(2.0, 1.4, 0.8, 0.8))
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
	var dirt := _burst(_dust_mesh, _dust_gradient, 30, 1.8, radius * 0.8, radius * 1.6, 1.2, 2.6, Vector3(0, -9, 0))
	dirt.direction = Vector3.UP
	dirt.spread = 45.0
	_spawn_oneshot(dirt, pos, 3.0)


## Bless: a fountain of golden sparkles and a warm flash round the creature.
## Condemn: a sinking swirl of dark red wisps under a blood-red light.
func spawn_judgement(pos: Vector3, size: float, blessing: bool) -> void:
	var colors := [Color(1.0, 0.85, 0.2, 0.0), Color(1.0, 0.8, 0.1, 1.0), Color(1.0, 0.6, 0.05, 0.0)]
	if not blessing:
		colors = [Color(0.5, 0.0, 0.05, 0.0), Color(0.8, 0.02, 0.08, 1.0), Color(0.12, 0.0, 0.02, 0.0)]
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9) if blessing else Vector2(1.6, 1.6)
	var mat := _glow_material(Color(1, 1, 1))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	if blessing:
		# Each sparkle is a soft round glint, bright in the middle.
		var glint := GradientTexture2D.new()
		glint.fill = GradientTexture2D.FILL_RADIAL
		glint.fill_from = Vector2(0.5, 0.5)
		glint.fill_to = Vector2(0.5, 0.0)
		glint.gradient = _gradient([0.0, 0.25, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		glint.width = 32
		glint.height = 32
		mat.albedo_texture = glint
	else:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.albedo_texture = Art.tex("smoke")
	quad.material = mat
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = 90 if blessing else 40
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0 * size
	p.direction = Vector3.UP if blessing else Vector3.DOWN
	p.spread = 25.0 if blessing else 60.0
	p.gravity = Vector3(0, 2.0, 0) if blessing else Vector3(0, -1.0, 0)
	p.initial_velocity_min = 1.0 * size
	p.initial_velocity_max = 5.0 * size
	p.orbit_velocity_min = 0.0 if blessing else 0.3
	p.orbit_velocity_max = 0.0 if blessing else 0.6
	p.scale_amount_min = 0.5 * maxf(size, 0.4)
	p.scale_amount_max = 1.6 * maxf(size, 0.4)
	p.color_ramp = _gradient([0.0, 0.25, 1.0], colors)
	if blessing:
		# Twinkle: swell and shrink away.
		p.scale_amount_curve = _grow_shrink
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn_oneshot(p, pos, 3.5)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.9, 0.4) if blessing else Color(1.0, 0.05, 0.05)
	light.light_energy = 6.0
	light.omni_range = 16.0 * maxf(size, 0.4)
	add_child(light)
	light.global_position = pos + Vector3.UP * 2.0
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 1.8 if blessing else 2.8)
	tw.tween_callback(light.queue_free)


## The creature brought back to life: a shaft of warm light comes down
## from the sky onto it, golden motes rise through it, and both fade.
func spawn_god_ray(pos: Vector3, size: float) -> void:
	var ray := Node3D.new()
	add_child(ray)
	ray.global_position = pos
	var width := 5.0 + 6.0 * size
	var tall := 90.0
	# Three nested open cones, fading towards the top and the edge.
	var mat := _glow_material(Color(1.0, 0.86, 0.5, 0.0))
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	var mb := MeshBuilder.new()
	for layer in 3:
		var r := width * (0.55 + 0.3 * layer)
		var alpha := 0.32 - 0.08 * layer
		var sides := 28
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var bottom0 := Vector3(cos(a0), 0.0, sin(a0)) * r
			var bottom1 := Vector3(cos(a1), 0.0, sin(a1)) * r
			var top0 := Vector3(cos(a0), 0.0, sin(a0)) * r * 1.6 + Vector3.UP * tall
			var top1 := Vector3(cos(a1), 0.0, sin(a1)) * r * 1.6 + Vector3.UP * tall
			var low := Color(1.0, 0.92, 0.65, alpha)
			var high := Color(1.0, 0.92, 0.65, 0.0)
			mb.verts.append_array(PackedVector3Array([bottom0, top0, bottom1, bottom1, top0, top1]))
			mb.colors.append_array(PackedColorArray([low, high, low, low, high, high]))
			for j in 6:
				mb.normals.append(Vector3.UP)
				mb.uvs.append(Vector2.ZERO)
				mb.indices.append(mb.verts.size() - 6 + j)
	var shaft := MeshInstance3D.new()
	shaft.mesh = mb.commit()
	shaft.material_override = mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ray.add_child(shaft)
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.88, 0.55)
	light.light_energy = 0.0
	light.omni_range = 22.0 + 10.0 * size
	ray.add_child(light)
	light.position = Vector3.UP * (3.0 + 4.0 * size)
	# Motes of light drifting up the shaft.
	spawn_judgement(pos + Vector3.UP * 2.0 * size, maxf(size, 0.6), true)
	var tw := ray.create_tween()
	tw.tween_property(mat, "albedo_color:a", 1.0, 0.8)
	tw.parallel().tween_property(light, "light_energy", 7.0, 0.8)
	tw.tween_interval(3.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.5)
	tw.parallel().tween_property(light, "light_energy", 0.0, 2.5)
	tw.tween_callback(ray.queue_free)


## A necromancer raising the dead: purple and green wisps wind up out of
## the ground under a sickly light.
func spawn_raise(pos: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var mat := _glow_material(Color(1, 1, 1))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Art.tex("smoke")
	quad.material = mat
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = 36
	p.lifetime = 2.0
	p.one_shot = true
	p.explosiveness = 0.25
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.9
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.2
	p.orbit_velocity_min = 0.4
	p.orbit_velocity_max = 0.9
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	p.color_ramp = _gradient([0.0, 0.2, 0.6, 1.0], [Color(0.6, 0.2, 1.0, 0.0), Color(0.7, 0.3, 1.0, 0.9), Color(0.3, 1.0, 0.4, 0.7), Color(0.2, 0.8, 0.3, 0.0)])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn_oneshot(p, pos + Vector3.UP * 0.3, 3.2)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.4, 1.0)
	light.light_energy = 4.0
	light.omni_range = 9.0
	add_child(light)
	light.global_position = pos + Vector3.UP * 1.5
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 2.4)
	tw.tween_callback(light.queue_free)


## A spray of blood for the Blood Sacrifice spell.
func spawn_blood(pos: Vector3) -> void:
	var red := _gradient([0.0, 0.7, 1.0], [Color(0.75, 0.02, 0.04, 1.0), Color(0.6, 0.0, 0.03, 1.0), Color(0.4, 0.0, 0.02, 0.0)])
	var drops := _burst(_dust_mesh, red, 28, 1.0, 2.5, 6.5, 0.1, 0.28, Vector3(0, -14.0, 0))
	drops.spread = 60.0
	drops.emission_sphere_radius = 0.2
	_spawn_oneshot(drops, pos + Vector3.UP * 1.2, 1.6)


func spawn_dust(pos: Vector3, size: float) -> void:
	var dust := _burst(_dust_mesh, _dust_gradient, 22, 1.6, 3.0 * size, 6.0 * size, 1.2 * size, 2.6 * size, Vector3(0, 0.4, 0))
	dust.spread = 90.0
	dust.flatness = 0.85
	dust.damping_min = 4.0 * size
	dust.damping_max = 6.0 * size
	dust.scale_amount_curve = _grow
	dust.angle_min = -180.0
	dust.angle_max = 180.0
	_spawn_oneshot(dust, pos + Vector3.UP * 0.3, 2.5)


## A white puff where rain puts a fire out.
func spawn_steam(pos: Vector3, size: float) -> void:
	var steam := _burst(_smoke_mesh, _steam_gradient, 10, 1.8, 1.0 * size, 2.5 * size, 0.6 * size, 1.4 * size, Vector3(0, 2.5, 0))
	steam.direction = Vector3.UP
	steam.spread = 35.0
	steam.scale_amount_curve = _grow
	_spawn_oneshot(steam, pos + Vector3.UP * 0.4, 2.5)


## Rain falling from a cloud `height` metres up over a disc of `radius`.
func make_rain(radius: float, height: float) -> CPUParticles3D:
	var drop := QuadMesh.new()
	drop.size = Vector2(0.06, 1.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.albedo_color = Color(0.78, 0.86, 1.0, 0.55)
	drop.material = mat
	var p := CPUParticles3D.new()
	p.mesh = drop
	p.amount = int(clampf(radius * radius * 2.2, 120.0, 700.0))
	# Time for a drop thrown down at 24 m/s to fall `height` metres.
	p.lifetime = (-24.0 + sqrt(24.0 * 24.0 + 2.0 * 9.8 * height)) / 9.8
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(radius * 0.75, 0.5, radius * 0.75)
	p.direction = Vector3.DOWN
	p.spread = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = 22.0
	p.initial_velocity_max = 26.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A ring that shrinks into the ground where a move order was given.
## A ring that shrinks where the creature was sent: green for a move, red
## for an attack move.
func spawn_marker(pos: Vector3, color := Color(0.4, 1.0, 0.5, 0.9)) -> void:
	var mat := _glow_material(color)
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


func _sprite_quad(kind: String, size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = Art.particle(kind)
	return quad


func _gradient(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g
