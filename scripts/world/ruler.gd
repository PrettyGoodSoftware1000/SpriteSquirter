class_name Ruler
extends Node3D
## The dev menu's ruler: a see-through line laid over the ground from one
## point to another, with the distance between them written over its
## middle (straight across, ignoring height, and how much it rises or
## falls). PlayMode sets the two ends as the player clicks and moves.

const LIFT := 0.35

var _mesh := MeshInstance3D.new()
var _label := Label3D.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 40
	_label.outline_size = 16
	_label.outline_modulate = Color(0.05, 0.04, 0.02)
	_label.modulate = Color(1.0, 0.95, 0.55)
	# Drawn over other labels (such as a building site's).
	_label.render_priority = 10
	_label.outline_render_priority = 9
	add_child(_label)
	visible = false


## Draws the line from `a` to `b` (points on the ground).
func show_line(a: Vector3, b: Vector3) -> void:
	visible = true
	var terrain := Game.terrain
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := clampi(ceili(flat / 1.5), 1, 200)
	var points := PackedVector3Array()
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		var y := terrain.surface_height(p.x, p.z) if terrain.is_inside(p.x, p.z) else p.y
		points.append(Vector3(p.x, y + LIFT, p.z))
	var mb := MeshBuilder.new()
	var width := clampf(flat * 0.006, 0.12, 0.6)
	mb.color = Color(1.0, 0.92, 0.35, 0.8)
	if points.size() >= 2 and flat > 0.05:
		var radii := PackedFloat32Array()
		radii.resize(points.size())
		radii.fill(width)
		mb.add_tube(points, radii, 6)
	# A ring at each end.
	mb.color = Color(1.0, 0.98, 0.7, 0.9)
	for end in [points[0], points[points.size() - 1]]:
		mb.add_blob(Vector3.ONE * width * 2.5, Transform3D(Basis(), end), null, 0.0, 6, 10)
	_mesh.mesh = mb.commit()
	var rise := b.y - a.y
	_label.text = "%.1f m" % flat + ("  (%s%.1f m)" % ["+" if rise >= 0.0 else "-", absf(rise)] if absf(rise) >= 0.5 else "")
	_label.global_position = points[points.size() / 2] + Vector3.UP * 3.0


func clear() -> void:
	visible = false
