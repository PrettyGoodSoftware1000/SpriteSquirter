class_name RtsCamera
extends Node3D
## Free-moving strategy camera.
##
## The rig orbits a focus point on the ground. Pitch is clamped so the view
## never looks straight down or straight up.
##   WASD / arrows  pan        Q / E          rotate
##   mouse wheel    zoom       middle drag    rotate + tilt
##   Shift          pan faster

@export var pan_speed := 45.0
@export var rotate_speed := 1.8
@export var zoom_min := 14.0
@export var zoom_max := 230.0
@export var pitch_min_deg := 15.0
@export var pitch_max_deg := 78.0
@export var bounds := 128.0

var camera: Camera3D
var focus := Vector3.ZERO
var yaw := 0.7
var pitch := deg_to_rad(48.0)
var distance := 85.0

var _target_distance := 85.0
var _rotating := false
var _shake := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.3
	camera.far = 1500.0
	add_child(camera)
	camera.make_current()


func focus_on(pos: Vector3, instant := false) -> void:
	focus = Vector3(pos.x, focus.y, pos.z)
	if instant:
		focus.y = _ground(pos)
		_update_camera(0.0)


func add_shake(amount: float, at: Vector3) -> void:
	var falloff := clampf(1.0 - camera.global_position.distance_to(at) / 200.0, 0.0, 1.0)
	_shake = minf(1.5, _shake + amount * falloff)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_target_distance = clampf(_target_distance * 0.88, zoom_min, zoom_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_target_distance = clampf(_target_distance * 1.14, zoom_min, zoom_max)
			MOUSE_BUTTON_MIDDLE:
				_rotating = button.pressed
		return
	var motion := event as InputEventMouseMotion
	if motion and _rotating:
		yaw -= motion.relative.x * 0.006
		pitch = clampf(pitch + motion.relative.y * 0.004, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func _process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += rotate_speed * delta
	if Input.is_physical_key_pressed(KEY_E):
		yaw -= rotate_speed * delta

	if input != Vector2.ZERO:
		var speed := pan_speed * clampf(distance / 80.0, 0.4, 3.0)
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= 2.5
		var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		focus += (forward * input.y + right * input.x).normalized() * speed * delta
		focus.x = clampf(focus.x, -bounds, bounds)
		focus.z = clampf(focus.z, -bounds, bounds)

	distance = lerpf(distance, _target_distance, 1.0 - exp(-10.0 * delta))
	focus.y = lerpf(focus.y, _ground(focus), 1.0 - exp(-6.0 * delta))
	_shake = move_toward(_shake, 0.0, delta * 2.5)
	_update_camera(delta)


func _update_camera(_delta: float) -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var pos := focus + offset
	# Never dip below the ground or the water.
	pos.y = maxf(pos.y, _ground(pos) + 3.0)
	var xf := Transform3D(Basis(), pos).looking_at(focus, Vector3.UP)
	if _shake > 0.0:
		xf.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
	camera.global_transform = xf


func _ground(p: Vector3) -> float:
	if Game.terrain == null:
		return 0.0
	return maxf(Game.terrain.get_height(p.x, p.z), Terrain.WATER_LEVEL)
