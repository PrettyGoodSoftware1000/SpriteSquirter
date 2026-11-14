class_name GroundRing
extends MeshInstance3D
## Circles drawn on the terrain: the sculpt brush, building footprints and
## the editor's tool outlines.

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


func clear() -> void:
	_mesh.clear_surfaces()
	visible = false
