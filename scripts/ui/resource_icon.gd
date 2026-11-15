class_name ResourceIcon
extends Control
## A small resource icon drawn with vector shapes, so it stays sharp at any
## UI scale: a log (lumber), a stone, an ear of wheat (food), a blue droplet
## (magicko), a bone (bones) or a little person (people).

const KINDS := ["lumber", "stone", "food", "bones", "magicko", "people"]
const INK := Color(0.08, 0.06, 0.05)

var kind := "lumber"


static func make(icon_kind: String, size := 20.0) -> ResourceIcon:
	var icon := ResourceIcon.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(size, size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## "40 [log]  15 [stone]": an amount and icon for each resource in `cost`.
static func cost_row(cost: Dictionary, font_size := 14) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for res in ["lumber", "stone", "food", "bones", "magicko"]:
		if not cost.has(res):
			continue
		if row.get_child_count() > 0:
			var gap := Control.new()
			gap.custom_minimum_size.x = 8
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
		var label := Label.new()
		label.text = str(cost[res])
		label.add_theme_font_size_override("font_size", font_size)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		row.add_child(make(res, font_size + 4))
	return row


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match kind:
		"lumber":
			# A log lying on its side, cut end facing us.
			_capsule(p.call(0.14, 0.52), p.call(0.66, 0.52), s * 0.2, Color(0.55, 0.34, 0.17))
			_disc(p.call(0.7, 0.52), s * 0.22, Color(0.88, 0.68, 0.42))
			draw_arc(p.call(0.7, 0.52), s * 0.11, 0.0, TAU, 16, Color(0.6, 0.4, 0.2), maxf(1.0, s * 0.05), true)
		"stone":
			_disc(p.call(0.4, 0.58), s * 0.3, Color(0.6, 0.62, 0.66))
			_disc(p.call(0.66, 0.5), s * 0.24, Color(0.68, 0.7, 0.74))
			_disc(p.call(0.36, 0.4), s * 0.2, Color(0.74, 0.76, 0.8))
		"food":
			# An ear of wheat: a stalk and plump golden grains.
			draw_line(p.call(0.5, 0.95), p.call(0.5, 0.2), INK, maxf(2.0, s * 0.11), true)
			draw_line(p.call(0.5, 0.95), p.call(0.5, 0.2), Color(0.85, 0.66, 0.24), maxf(1.0, s * 0.06), true)
			for k in 4:
				var y := 0.28 + k * 0.14
				_grain(p.call(0.37, y), -0.6, s)
				_grain(p.call(0.63, y), 0.6, s)
			_grain(p.call(0.5, 0.15), 0.0, s)
		"bones":
			# A bone lying slantwise, with a pair of knobs at each end.
			var bone := Color(0.95, 0.92, 0.8)
			for end: Vector2 in [Vector2(0.24, 0.76), Vector2(0.76, 0.24)]:
				_disc(p.call(end.x - 0.07, end.y - 0.07), s * 0.12, bone)
				_disc(p.call(end.x + 0.07, end.y + 0.07), s * 0.12, bone)
			draw_line(p.call(0.26, 0.74), p.call(0.74, 0.26), INK, s * 0.2 + maxf(2.0, s * 0.06), true)
			draw_line(p.call(0.24, 0.76), p.call(0.76, 0.24), bone, s * 0.2, true)
		"magicko":
			# A drop of water: a round bottom joined to a point by its tangents.
			var centre := Vector2(0.5, 0.62)
			var r := 0.3
			var tip := Vector2(0.5, 0.06)
			var turn := acos(r / centre.distance_to(tip))
			var pts := PackedVector2Array([p.call(tip.x, tip.y)])
			for k in 21:
				var a := -PI * 0.5 + turn + (TAU - 2.0 * turn) * k / 20.0
				pts.append(p.call(centre.x + cos(a) * r, centre.y + sin(a) * r))
			_shape(pts, Color(0.32, 0.6, 1.0))
			_disc(p.call(0.42, 0.64), s * 0.07, Color(0.8, 0.92, 1.0), false)
		"people":
			_disc(p.call(0.5, 0.28), s * 0.17, Color(0.98, 0.9, 0.78))
			var body := PackedVector2Array()
			for k in 13:
				var t := PI * k / 12.0
				body.append(p.call(0.5 - cos(t) * 0.32, 0.95 - sin(t) * 0.42))
			_shape(body, Color(0.98, 0.9, 0.78))


func _disc(c: Vector2, r: float, color: Color, outline := true) -> void:
	if outline:
		draw_circle(c, r + maxf(1.0, r * 0.15), INK, true, -1.0, true)
	draw_circle(c, r, color, true, -1.0, true)


func _capsule(a: Vector2, b: Vector2, r: float, color: Color) -> void:
	draw_line(a, b, INK, r * 2.0 + maxf(2.0, r * 0.3))
	_disc(a, r, color)
	draw_line(a, b, color, r * 2.0)


func _grain(c: Vector2, lean: float, s: float) -> void:
	var pts := PackedVector2Array()
	for k in 12:
		var t := TAU * k / 12.0
		var v := Vector2(sin(t) * 0.07, -cos(t) * 0.12).rotated(lean) * s
		pts.append(c + v)
	_shape(pts, Color(0.98, 0.78, 0.3))


func _shape(pts: PackedVector2Array, color: Color) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, INK, maxf(2.0, size.x * 0.1), true)
	draw_colored_polygon(pts, color)
