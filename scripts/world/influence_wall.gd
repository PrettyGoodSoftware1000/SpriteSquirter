class_name InfluenceWall
extends Node3D
## The edge of the village's influence (PlayerVillage.influence()), drawn as
## a see-through wall of light that follows the lie of the land. It shows
## while the mouse is over a Storehouse and while the player is placing a
## building, and fades in and out. Call show_at() every frame it should be
## seen; it fades away by itself when that stops.

const HEIGHT := 7.0
const SIDES := 160

var _mesh := MeshInstance3D.new()
var _material := StandardMaterial3D.new()
var _built_radius := -1.0
var _built_center := Vector3.INF
var _want := 0.0
var _alpha := 0.0


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color(1, 1, 1, 0)
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## Shows the wall round `center` at `radius`, this frame.
func show_at(center: Vector3, radius: float) -> void:
	_want = 1.0
	if absf(radius - _built_radius) > 0.25 or center.distance_to(_built_center) > 0.25:
		_build(center, radius)


func _process(delta: float) -> void:
	_alpha = move_toward(_alpha, _want, delta * 3.0)
	_want = 0.0
	visible = _alpha > 0.01
	_material.albedo_color.a = _alpha


## A band of quads round the circle, each corner on the ground, bright at
## the foot and fading to nothing at the top, with a brighter line along
## the ground.
func _build(center: Vector3, radius: float) -> void:
	_built_radius = radius
	_built_center = center
	var terrain := Game.terrain
	var mb := MeshBuilder.new()
	var foot := Color(0.55, 0.85, 1.0, 0.42)
	var top := Color(0.55, 0.85, 1.0, 0.0)
	var line := Color(0.8, 0.95, 1.0, 0.8)
	var ring: Array[Vector3] = []
	for k in SIDES + 1:
		var a := TAU * k / SIDES
		var x := center.x + cos(a) * radius
		var z := center.z + sin(a) * radius
		var y := terrain.surface_height(x, z) if terrain.is_inside(x, z) else center.y
		ring.append(Vector3(x, y, z))
	for k in SIDES:
		var a := ring[k]
		var b := ring[k + 1]
		_quad(mb, a, b, a + Vector3.UP * HEIGHT, b + Vector3.UP * HEIGHT, foot, top)
		_quad(mb, a - Vector3.UP * 0.1, b - Vector3.UP * 0.1, a + Vector3.UP * 0.35, b + Vector3.UP * 0.35, line, line)
	_mesh.mesh = mb.commit()


func _quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, low: Color, high: Color) -> void:
	var n := mb.verts.size()
	mb.verts.append_array(PackedVector3Array([a, c, b, d]))
	mb.colors.append_array(PackedColorArray([low, high, low, high]))
	for k in 4:
		mb.normals.append(Vector3.UP)
		mb.uvs.append(Vector2.ZERO)
	mb.indices.append_array(PackedInt32Array([n, n + 1, n + 2, n + 2, n + 1, n + 3]))
