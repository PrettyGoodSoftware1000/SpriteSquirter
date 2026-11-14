class_name RootPatch
extends Node3D
## The roots spell: glowing green roots burst out of the ground for
## DURATION seconds. Goblins, strangers and the tortoise in the circle are
## held where they stand (they can still fight what is in reach); the
## player's own villagers, warriors and wizards are only slowed, to
## Villager.SLOWED_SPEED. Anything that wanders in while the roots are up
## is caught too.
## Call cast() right after adding it to the tree.

const RADIUS := 9.0
const DURATION := 20.0

var _ends := 0.0
var _check := 0.0
var _withering := false


func cast(target: Vector3) -> void:
	global_position = target
	_ends = Game.now + DURATION
	_build()
	_snare()
	scale = Vector3(1.0, 0.05, 1.0)
	var grow := create_tween()
	grow.tween_property(self, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Game.effects.spawn_dust(target, 2.0)


func _process(delta: float) -> void:
	if _withering:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.25
		_snare()
	if Game.now >= _ends:
		_withering = true
		var fade := create_tween()
		fade.tween_property(self, "scale", Vector3(1.0, 0.02, 1.0), 1.2).set_trans(Tween.TRANS_SINE)
		fade.tween_callback(queue_free)


func _snare() -> void:
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if not _inside(v.global_position):
			continue
		if v.owned:
			v.slowed_until = maxf(v.slowed_until, _ends)
		else:
			v.snared_until = maxf(v.snared_until, _ends)
	var creature := Game.creature
	if is_instance_valid(creature) and _inside(creature.global_position):
		creature.snared_until = maxf(creature.snared_until, _ends)


func _inside(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < RADIUS


func _build() -> void:
	var terrain := Game.terrain
	var origin := global_position
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var roots := MeshBuilder.new()
	var vines := MeshBuilder.new()
	var ground := func(x: float, z: float) -> float:
		return terrain.get_height(origin.x + x, origin.z + z) - origin.y

	# Thick roots creeping outwards along the ground.
	for k in 11:
		var a := TAU * k / 11.0 + rng.randf_range(-0.2, 0.2)
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		var reach := RADIUS * rng.randf_range(0.8, 1.0)
		for i in 8:
			var t := i / 7.0
			var bend := a + sin(t * 5.0 + k) * 0.25
			var x := cos(bend) * reach * t
			var z := sin(bend) * reach * t
			points.append(Vector3(x, ground.call(x, z) + 0.1 + 0.25 * sin(t * 9.0 + k) * (1.0 - t), z))
			radii.append(lerpf(0.3, 0.06, t))
		roots.color = Color(0.2, 0.3, 0.12).lerp(Color(0.3, 0.24, 0.12), rng.randf())
		roots.add_tube(points, radii, 6)

	# Roots curling up out of the ground, each wound with a glowing vine.
	for k in 44:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * RADIUS * 0.95
		var x := cos(a) * d
		var z := sin(a) * d
		var base := Vector3(x, ground.call(x, z) - 0.3, z)
		var h := rng.randf_range(0.9, 2.4)
		var curl := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized() * h * 0.45
		var points := PackedVector3Array([base, base + Vector3.UP * h * 0.55 + curl * 0.25,
			base + Vector3.UP * h + curl * 0.8, base + Vector3.UP * h * 0.8 + curl * 1.35])
		var thick := rng.randf_range(0.12, 0.22)
		roots.color = Color(0.18, 0.34, 0.12).lerp(Color(0.32, 0.26, 0.12), rng.randf())
		roots.add_tube(points, PackedFloat32Array([thick, thick * 0.75, thick * 0.45, 0.03]), 6)
		if k % 2 == 0:
			vines.color = Color(0.45, 1.0, 0.5)
			var wound := PackedVector3Array()
			var widths := PackedFloat32Array()
			for i in 7:
				var t := i / 6.0
				var along := base.lerp(points[2], t) + Vector3.UP * 0.3
				wound.append(along + Vector3(cos(t * 9.0 + k), 0.0, sin(t * 9.0 + k)) * (thick + 0.07))
				widths.append(0.035)
			vines.add_tube(wound, widths, 4)
			vines.color = Color(0.7, 1.0, 0.6)
			vines.add_blob(Vector3.ONE * rng.randf_range(0.09, 0.15), Transform3D(Basis(), points[3]), null, 0.0, 5, 8)

	var root_mesh := MeshInstance3D.new()
	root_mesh.mesh = roots.commit()
	root_mesh.material_override = Art.paint("bark", 0.6)
	add_child(root_mesh)
	var vine_mesh := MeshInstance3D.new()
	vine_mesh.mesh = vines.commit()
	vine_mesh.material_override = Art.glow(2.2)
	vine_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vine_mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.5)
	light.light_energy = 2.2
	light.omni_range = RADIUS * 1.5
	light.position.y = 3.0
	add_child(light)

	# Motes of green magic drifting up.
	var mote := QuadMesh.new()
	mote.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.5, 1.0, 0.55, 0.9)
	mote.material = mat
	var motes := CPUParticles3D.new()
	motes.mesh = mote
	motes.amount = 60
	motes.lifetime = 3.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = RADIUS * 0.85
	motes.direction = Vector3.UP
	motes.spread = 20.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.5
	motes.initial_velocity_max = 1.4
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	motes.color_ramp = fade
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)
	motes.scale = Vector3(1.0, 0.25, 1.0)
	motes.position.y = 1.0
