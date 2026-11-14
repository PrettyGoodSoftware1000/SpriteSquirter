class_name GroundRing
extends MeshInstance3D
## Lines drawn on the terrain: the sculpt brush, building footprints, spell
## areas, field outlines and the editor's tool outlines.

var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func draw(center: Vector3, radii: Array, color: Color) -> void:
	_mesh.clear_surfaces()
	var terrain := Game.terrain
	for radius in radii:
		var r: float = radius
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material)
		_mesh.surface_set_color(color)
		var steps := clampi(int(r * 3.0), 24, 96)
		for k in steps + 1:
			var a := TAU * k / steps
			var x := center.x + cos(a) * r
			var z := center.z + sin(a) * r
			_mesh.surface_add_vertex(Vector3(x, terrain.get_height(x, z) + 0.25, z))
		_mesh.surface_end()
	visible = true


## A closed outline through `corners` (world positions), hugging the ground.
func draw_loop(corners: PackedVector3Array, color: Color) -> void:
	_mesh.clear_surfaces()
	var terrain := Game.terrain
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material)
	_mesh.surface_set_color(color)
	for k in corners.size():
		var a := corners[k]
		var b := corners[(k + 1) % corners.size()]
		var steps := maxi(1, int(a.distance_to(b)))
		for i in steps + (1 if k == corners.size() - 1 else 0):
			var p := a.lerp(b, float(i) / steps)
			_mesh.surface_add_vertex(Vector3(p.x, terrain.get_height(p.x, p.z) + 0.25, p.z))
	_mesh.surface_end()
	visible = true


func clear() -> void:
	_mesh.clear_surfaces()
	visible = false
