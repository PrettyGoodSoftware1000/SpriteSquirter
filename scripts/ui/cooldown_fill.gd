class_name CooldownFill
extends Control
## Over a spell button while the spell cools down: a see-through band that
## rises from the bottom of the icon and reaches the top as the spell is
## ready again.

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
	# The whole icon dims a little; the band of what has cooled rises over it.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.12, 0.35))
	var risen := size.y * (1.0 - left)
	draw_rect(Rect2(0.0, size.y - risen, size.x, risen), Color(0.75, 0.85, 1.0, 0.35))
	draw_line(Vector2(0.0, size.y - risen), Vector2(size.x, size.y - risen), Color(1.0, 1.0, 1.0, 0.8), 2.0)
