class_name UiTheme
extends RefCounted
## The shared look of every on-screen panel: dark, mostly opaque and
## rounded, so text stays readable over the bright, busy world.

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.1, 0.13, 0.86)
	panel.border_color = Color(1.0, 0.9, 0.6, 0.18)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(10)
	_theme.set_stylebox("panel", "PanelContainer", panel)
	return _theme
