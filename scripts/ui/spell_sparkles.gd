class_name SpellSparkles
extends Control
## Blue sparkles by a spell's cost while Overcast can cast it on its
## cooldown (see PlayMode.spell_state), and yellow ones over the creature's
## portrait while it can grow. `amount` sets how many, up to FULL.

const FULL := 3.0
const MOST := 30

## 0 (no extra cost) to 1 (FULL or more).
var amount := 0.0
## The wash behind the sparkles, and the sparkles' colour (blue for a
## dearer spell; the creature's portrait sparkles yellow).
var wash := Color(0.15, 0.4, 1.0)
var glint := Color(0.5, 0.78, 1.0)

var _stars: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	for k in MOST:
		_stars.append({"x": rng.randf(), "y": rng.randf(), "phase": rng.randf() * TAU,
			"speed": rng.randf_range(3.0, 7.0), "drift": rng.randf_range(0.08, 0.25), "size": rng.randf_range(2.0, 4.0)})


## `extra`: the share more the spell costs now (1.5 is 150% more).
func set_extra(extra: float) -> void:
	var a := clampf(extra / FULL, 0.0, 1.0)
	if not is_equal_approx(a, amount):
		amount = a
		queue_redraw()


func _process(delta: float) -> void:
	if amount > 0.0:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if amount <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(wash, 0.1 + 0.32 * amount))
	for k in ceili(MOST * amount):
		var star: Dictionary = _stars[k]
		var twinkle := 0.5 + 0.5 * sin(_time * float(star.speed) + float(star.phase))
		# Each sparkle drifts slowly up the button and comes round again.
		var at := Vector2(float(star.x), fposmod(float(star.y) - _time * float(star.drift), 1.0)) * size
		var r := float(star.size) * (0.5 + 0.7 * twinkle) * (1.0 + amount)
		var glow := Color(glint, twinkle * (0.55 + 0.45 * amount))
		draw_line(at - Vector2(r, 0.0), at + Vector2(r, 0.0), glow, 1.5)
		draw_line(at - Vector2(0.0, r), at + Vector2(0.0, r), glow, 1.5)
		draw_circle(at, r * 0.3, Color(0.92, 0.97, 1.0, glow.a))
