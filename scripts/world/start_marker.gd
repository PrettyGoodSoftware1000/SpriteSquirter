class_name StartMarker
extends Node3D
## A numbered banner marking a start location. The map editor places them;
## at the start of a game the player clicks one to found their village.

const COLORS := [Color(0.95, 0.3, 0.25), Color(0.25, 0.55, 0.95), Color(0.98, 0.8, 0.2), Color(0.45, 0.85, 0.35),
	Color(0.8, 0.4, 0.9), Color(1.0, 0.55, 0.2), Color(0.3, 0.85, 0.85), Color(0.95, 0.5, 0.7)]

var index := 0

var _flag: MeshInstance3D
var _label: Label3D
var _ring_mat := StandardMaterial3D.new()
var _time := randf() * 10.0
var _highlight := false


func _ready() -> void:
	add_to_group("start_markers")
	add_to_group("grounded")
	var color: Color = COLORS[index % COLORS.size()]
	var pole := MeshBuilder.new()
	pole.color = Art.TIMBER
	pole.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, 6.5, 0)]), PackedFloat32Array([0.16, 0.1]), 8)
	var pole_mesh := MeshInstance3D.new()
	pole_mesh.mesh = pole.commit()
	pole_mesh.material_override = Art.paint("planks", 0.5)
	add_child(pole_mesh)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = color
	flag_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flag := BoxMesh.new()
	flag.size = Vector3(2.4, 1.5, 0.06)
	flag.material = flag_mat
	_flag = MeshInstance3D.new()
	_flag.mesh = flag
	_flag.position = Vector3(1.25, 5.6, 0)
	add_child(_flag)

	var torus := TorusMesh.new()
	torus.inner_radius = 2.6
	torus.outer_radius = 3.0
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(color, 0.6)
	torus.material = _ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.scale = Vector3(1, 0.3, 1)
	ring.position.y = 0.3
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 72
	_label.outline_size = 18
	_label.pixel_size = 0.025
	_label.modulate = color.lightened(0.3)
	_label.position.y = 8.2
	add_child(_label)
	set_index(index)


func set_index(i: int) -> void:
	index = i
	if _label:
		_label.text = str(i + 1)


func set_highlight(on: bool) -> void:
	_highlight = on


func _process(delta: float) -> void:
	_time += delta
	# Grow when the camera is far away so the banners are easy to spot and click.
	var cam := get_viewport().get_camera_3d()
	if cam:
		scale = Vector3.ONE * clampf(cam.global_position.distance_to(global_position) / 50.0, 1.0, 14.0)
	_flag.rotation.y = sin(_time * 2.0) * 0.12
	var s := 1.0 + (0.25 + 0.1 * sin(_time * 6.0) if _highlight else 0.0)
	_label.scale = Vector3.ONE * s
	_ring_mat.albedo_color.a = 0.95 if _highlight else 0.55
