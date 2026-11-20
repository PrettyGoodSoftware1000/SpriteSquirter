class_name CostBolts
extends Control
## Red, jittering lightning bolts round a spell's cost while Overcast can
## cast it on its cooldown (see PlayMode.spell_state). When it is
## overcast they burst outwards and fade (burst()).

const COUNT := 6
const RED := Color(1.0, 0.18, 0.12)
const HOT := Color(1.0, 0.75, 0.65)
const BURST_SECONDS := 0.45

## True while the bolts crackle round the number.
var active := false
var _time := 0.0
var _jiggle := 0.0
## Seconds since the burst began (negative: no burst).
var _burst := -1.0
var _bolts: Array[PackedVector2Array] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# A little bigger than the number, so the bolts frame it.
	offset_left = -6.0
	offset_right = 6.0
	offset_top = -3.0
	offset_bottom = 3.0
	_rng.seed = get_instance_id()


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		_burst = -1.0
	queue_redraw()


## The bolts fly outwards and vanish.
func burst() -> void:
	active = false
	_burst = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not active and _burst < 0.0:
		return
	_time += delta
	_jiggle -= delta
	if _burst >= 0.0:
		_burst += delta
		if _burst >= BURST_SECONDS:
			_burst = -1.0
			_bolts.clear()
	if _jiggle <= 0.0 or _bolts.is_empty():
		_jiggle = 0.06
		_make_bolts()
	queue_redraw()


## New zigzags round the edge of the number (each frame or so, so they jitter).
func _make_bolts() -> void:
	_bolts.clear()
	var r := Rect2(Vector2.ZERO, size)
	for k in COUNT:
		var a := TAU * (float(k) + _rng.randf_range(-0.25, 0.25)) / COUNT
		var dir := Vector2(cos(a), sin(a))
		var from := r.get_center() + Vector2(dir.x * r.size.x * 0.5, dir.y * r.size.y * 0.5)
		var line := PackedVector2Array([from])
		var p := from
		var along := Vector2(-dir.y, dir.x) * (1.0 if k % 2 == 0 else -1.0)
		for s in 4:
			p += along * _rng.randf_range(2.0, 4.0) + dir * _rng.randf_range(-2.5, 2.5)
			line.append(p)
		_bolts.append(line)


func _draw() -> void:
	if _bolts.is_empty() or (not active and _burst < 0.0):
		return
	var centre := size * 0.5
	var push := 0.0
	var fade := 1.0
	if _burst >= 0.0:
		var t := _burst / BURST_SECONDS
		push = 1.0 + 3.0 * t
		fade = 1.0 - t
	for line in _bolts:
		var shown := PackedVector2Array()
		for p in line:
			shown.append(centre + (p - centre) * (1.0 + push * 0.6))
		draw_polyline(shown, Color(RED, 0.55 * fade), 3.0)
		draw_polyline(shown, Color(HOT, 0.95 * fade), 1.2)
