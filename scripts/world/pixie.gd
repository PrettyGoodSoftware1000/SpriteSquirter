class_name Pixie
extends Node3D
## A pixie flitting about the top of a magic tree for a while: half a
## gnome's size, inside a glowing green ball, trailing green magic dust.

const GREEN := Color(0.45, 1.0, 0.45)

var tree: MagicTree
var _life := 0.0
var _angle := randf() * TAU
var _speed := randf_range(0.6, 1.1) * (1.0 if randf() < 0.5 else -1.0)
var _height := randf_range(-1.0, 2.5)
var _wings: Array[Node3D] = []
var _time := randf() * 10.0


func _ready() -> void:
	_life = randf_range(20.0, 45.0)
	_build()
	scale = Vector3.ZERO


func _process(delta: float) -> void:
	_life -= delta
	_time += delta
	if not is_instance_valid(tree) or _life <= -1.0:
		queue_free()
		return
	# In and out with a shrink, and round and round the crown, bobbing.
	var appear := clampf(minf(_time * 2.0, _life + 1.0), 0.0, 1.0)
	scale = Vector3.ONE * appear
	_angle += _speed * delta
	var r := tree.crown_radius() * 1.15 + sin(_time * 0.7) * 0.8
	var at := tree.crown() + Vector3(cos(_angle) * r, _height + sin(_time * 2.3) * 0.6, sin(_angle) * r)
	global_position = at
	rotation.y = -_angle + (PI if _speed > 0.0 else 0.0)
	for k in _wings.size():
		_wings[k].rotation.y = (1.0 if k == 0 else -1.0) * (0.5 + 0.6 * sin(_time * 40.0))


func _build() -> void:
	# The glow around it.
	var aura := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.32
	ball.height = 0.64
	var haze := StandardMaterial3D.new()
	haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze.albedo_color = Color(GREEN, 0.3)
	haze.cull_mode = BaseMaterial3D.CULL_DISABLED
	ball.material = haze
	aura.mesh = ball
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aura)
	var light := OmniLight3D.new()
	light.light_color = GREEN
	light.light_energy = 0.8
	light.omni_range = 2.5
	add_child(light)
	# A tiny figure (a gnome is a third of a villager; a pixie half that).
	var mb := MeshBuilder.new()
	mb.color = Color(0.6, 0.95, 0.55)
	mb.add_blob(Vector3(0.04, 0.07, 0.035), Transform3D(Basis(), Vector3(0, -0.02, 0)), null, 0.0, 6, 8)
	mb.color = Color(1.0, 0.85, 0.75)
	mb.add_blob(Vector3(0.04, 0.04, 0.04), Transform3D(Basis(), Vector3(0, 0.08, 0)), null, 0.0, 6, 8)
	var body := MeshInstance3D.new()
	body.mesh = mb.commit()
	body.material_override = Art.cloth()
	add_child(body)
	var wing := QuadMesh.new()
	wing.size = Vector2(0.14, 0.1)
	var gauze := StandardMaterial3D.new()
	gauze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gauze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gauze.albedo_color = Color(0.85, 1.0, 0.9, 0.6)
	gauze.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing.material = gauze
	for k in 2:
		var hinge := Node3D.new()
		hinge.position = Vector3(0, 0.02, -0.03)
		add_child(hinge)
		var w := MeshInstance3D.new()
		w.mesh = wing
		w.position = Vector3((0.07 if k == 0 else -0.07), 0.02, 0)
		hinge.add_child(w)
		_wings.append(hinge)
	# Magic dust falling from it.
	var dust := CPUParticles3D.new()
	var dot := QuadMesh.new()
	dot.size = Vector2(0.06, 0.06)
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.vertex_color_use_as_albedo = true
	dot.material = spark
	dust.mesh = dot
	dust.amount = 24
	dust.lifetime = 1.8
	dust.local_coords = false
	dust.gravity = Vector3(0, -1.5, 0)
	dust.initial_velocity_min = 0.0
	dust.initial_velocity_max = 0.2
	dust.spread = 180.0
	var fade := Gradient.new()
	fade.set_color(0, Color(GREEN, 1.0))
	fade.set_color(1, Color(GREEN, 0.0))
	dust.color_ramp = fade
	add_child(dust)
