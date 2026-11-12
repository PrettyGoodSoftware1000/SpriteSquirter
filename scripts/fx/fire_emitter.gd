class_name FireEmitter
extends Node3D
## One flickering fire: flame particles, smoke and (if available) a light.
## Set `size` and `with_light` before adding it to the tree.

var size := 1.0
var with_light := true

var _flames: CPUParticles3D
var _smoke: CPUParticles3D
var _embers: CPUParticles3D
var _light: OmniLight3D
var _time := randf() * 10.0
var _strength := 1.0
var _dying := false


func _ready() -> void:
	_flames = Game.effects.make_flames(size)
	add_child(_flames)
	_smoke = Game.effects.make_smoke(size)
	add_child(_smoke)
	_smoke.position.y = size * 1.5
	_embers = Game.effects.make_embers(size)
	add_child(_embers)
	_embers.position.y = size * 0.5
	if with_light and Game.effects.claim_fire_light():
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.55, 0.2)
		_light.omni_range = 9.0 + size * 9.0
		_light.position.y = size
		add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	if _light:
		_light.light_energy = _strength * size * (4.5 + sin(_time * 11.0) * 0.7 + sin(_time * 17.3) * 0.5)


## Stops the flames, lets the smoke drift away, then frees itself.
func extinguish() -> void:
	if _dying:
		return
	_dying = true
	_flames.emitting = false
	_embers.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "_strength", 0.0, 1.0)
	tw.tween_callback(func() -> void: _smoke.emitting = false)
	tw.tween_interval(3.5)
	tw.tween_callback(queue_free)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _light != null and is_instance_valid(Game.effects):
		Game.effects.release_fire_light()
