class_name MagicAcorn
extends Node3D
## The squirrel's magic acorn, the size of a villager and sparkling with
## magic. It flies in an arc from the squirrel's hand and, where it lands,
## a giant magic tree (MagicTree) springs up.

const FLIGHT := 1.4
const ARC := 7.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0


## Throws one from `from` to land on `to` (on the ground).
static func toss(from: Vector3, to: Vector3) -> MagicAcorn:
	var acorn := MagicAcorn.new()
	acorn._from = from
	acorn._to = to
	Game.world_root.add_child(acorn)
	acorn.global_position = from
	return acorn


func _ready() -> void:
	var mb := MeshBuilder.new()
	# The nut, pointed at the bottom, and its knobbly cap.
	mb.color = Color(0.78, 0.5, 0.2)
	mb.add_lathe(PackedVector2Array([Vector2(0.0, -0.85), Vector2(0.18, -0.75), Vector2(0.42, -0.4), Vector2(0.5, 0.0),
		Vector2(0.46, 0.25), Vector2(0.0, 0.3)]), 14)
	mb.color = Color(0.45, 0.3, 0.16)
	mb.add_blob(Vector3(0.56, 0.24, 0.56), Transform3D(Basis(), Vector3(0, 0.32, 0)), null, 0.0, 8, 14)
	mb.add_tube(PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0.06, 0.7, 0)]), PackedFloat32Array([0.07, 0.04]), 6)
	var nut := MeshInstance3D.new()
	nut.mesh = mb.commit()
	nut.material_override = Art.cloth()
	add_child(nut)
	var sparkles := CPUParticles3D.new()
	var dot := QuadMesh.new()
	dot.size = Vector2(0.14, 0.14)
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.vertex_color_use_as_albedo = true
	dot.material = spark
	sparkles.mesh = dot
	sparkles.amount = 40
	sparkles.lifetime = 1.0
	sparkles.local_coords = false
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 0.6
	sparkles.spread = 180.0
	sparkles.initial_velocity_min = 0.3
	sparkles.initial_velocity_max = 1.0
	sparkles.gravity = Vector3.ZERO
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.95, 0.5, 1.0))
	fade.set_color(1, Color(0.5, 1.0, 0.7, 0.0))
	sparkles.color_ramp = fade
	add_child(sparkles)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.9, 0.5)
	light.light_energy = 1.0
	light.omni_range = 4.0
	add_child(light)


func _process(delta: float) -> void:
	_t += delta / FLIGHT
	var t := minf(_t, 1.0)
	global_position = _from.lerp(_to, t) + Vector3.UP * ARC * sin(PI * t)
	rotation.x += delta * 6.0
	if _t < 1.0:
		return
	var tree := MagicTree.new()
	Game.world_root.add_child(tree)
	tree.global_position = _to
	Game.effects.spawn_dust(_to, 1.5)
	queue_free()
