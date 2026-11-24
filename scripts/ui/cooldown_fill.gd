class_name CooldownFill
extends Control
## Over a spell button while the spell cools down (with or without
## Overcast): the part still cooling is dark, and the cooled part rises from
## the bottom of the icon, its top edge a bright line, until it reaches the
## top as the spell is ready again.

## 0..1: how much of the cooldown is still to go (0: ready).
var left := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_left(share: float) -> void:
	var s := clampf(share, 0.0, 1.0)
	if not is_equal_approx(s, left):
		left = s
		queue_redraw()


func _draw() -> void:
	if left <= 0.0:
		return
	var risen := size.y * (1.0 - left)
	var edge := size.y - risen
	# Still cooling: dark. Cooled: a light wash rising from the bottom.
	draw_rect(Rect2(0.0, 0.0, size.x, edge), Color(0.02, 0.02, 0.06, 0.62))
	draw_rect(Rect2(0.0, edge, size.x, risen), Color(0.7, 0.82, 1.0, 0.22))
	draw_line(Vector2(0.0, edge), Vector2(size.x, edge), Color(1.0, 1.0, 1.0, 0.95), 2.0)
