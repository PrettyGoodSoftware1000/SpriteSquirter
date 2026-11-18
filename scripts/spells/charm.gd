class_name CharmOffensive
extends Node3D
## The Charm Offensive spell: pink hearts float up over the spot, and of the
## goblins caught in it, about half (Balance "charm_share") are charmed for
## Balance "charm_seconds": their eyes turn pink and they fight their own
## kind (see Villager.charm()).

const HEART_SECONDS := 6.0

var _life := HEART_SECONDS


## Casts it at `target` (add it to the world first). Returns how many
## goblins were charmed.
func cast(target: Vector3) -> int:
	global_position = target
	var radius := Balance.num("charm_radius")
	var charmed := 0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if not g.is_alive() or g.charmed() or g.state == Villager.State.HELD:
			continue
		if Vector2(g.global_position.x - target.x, g.global_position.z - target.z).length() > radius:
			continue
		if randf() < Balance.num("charm_share"):
			g.charm(Balance.num("charm_seconds"))
			charmed += 1
	_hearts(radius)
	return charmed


func _hearts(radius: float) -> void:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = ImageTexture.create_from_image(SpellCursors.image("charm"))
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	p.amount = int(clampf(radius * radius * 0.6, 30.0, 140.0))
	p.lifetime = 2.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	fade.add_point(0.7, Color(1, 1, 1, 0.9))
	p.color_ramp = fade
	p.position = Vector3.UP * 1.5
	add_child(p)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 1.0:
		for child in get_children():
			if child is CPUParticles3D:
				(child as CPUParticles3D).emitting = false
	if _life <= -2.5:
		queue_free()
