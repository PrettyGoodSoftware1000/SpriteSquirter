class_name RainCloud
extends Node3D
## The rain spell: a dark cloud gathers over the target and pours for a few
## seconds. Everything under it is put out (ground fires, burning buildings,
## trees and villagers) and stays too wet to burn for a while afterwards.
## Call cast() right after adding it to the tree.

const RADIUS := 14.0
const HEIGHT := 22.0
const DURATION := 9.0
## How long the ground stays wet after the rain stops.
const WET_AFTER := 12.0

var _center := Vector3.ZERO
var _time := 0.0
var _soak_timer := 0.0
var _cloud: Node3D
var _rain: CPUParticles3D
var _ending := false


func cast(target: Vector3) -> void:
	_center = target
	global_position = target + Vector3.UP * HEIGHT


func _ready() -> void:
	_cloud = Node3D.new()
	add_child(_cloud)
	var mat := StandardMaterial3D.new()
	# Dark and a little see-through, so the spot it soaks stays visible.
	mat.albedo_color = Color(0.3, 0.33, 0.42, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.35
	var mb := MeshBuilder.new()
	for k in 9:
		var a := TAU * k / 9.0 + randf_range(-0.3, 0.3)
		var r := RADIUS * randf_range(0.2, 0.6)
		var size := Vector3(randf_range(4.0, 6.5), randf_range(2.2, 3.4), randf_range(4.0, 6.5))
		mb.add_blob(size, Transform3D(Basis(), Vector3(cos(a) * r, randf_range(-0.6, 1.2), sin(a) * r)), noise, 0.25, 8, 12)
	mb.add_blob(Vector3(7.5, 3.6, 7.5), Transform3D(Basis(), Vector3(0, 1.0, 0)), noise, 0.2, 8, 14)
	var cloud_mesh := MeshInstance3D.new()
	cloud_mesh.mesh = mb.commit()
	cloud_mesh.material_override = mat
	cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud.add_child(cloud_mesh)
	_cloud.scale = Vector3.ONE * 0.05
	var grow := create_tween()
	grow.tween_property(_cloud, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_rain = Game.effects.make_rain(RADIUS, HEIGHT)
	_rain.emitting = false
	add_child(_rain)
	_rain.position.y = -1.0
	get_tree().create_timer(0.5).timeout.connect(func() -> void: _rain.emitting = true)


func _process(delta: float) -> void:
	_time += delta
	_cloud.rotation.y += delta * 0.15
	if _ending:
		return
	_soak_timer -= delta
	if _soak_timer <= 0.0 and _time > 0.6:
		_soak_timer = 0.3
		Game.fire.soak(_center, RADIUS, DURATION - _time + WET_AFTER)
	if _time >= DURATION:
		_end()


func _end() -> void:
	_ending = true
	_rain.emitting = false
	var fade := create_tween()
	fade.tween_interval(_rain.lifetime)
	fade.tween_property(_cloud, "scale", Vector3.ONE * 0.05, 1.2).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(queue_free)
