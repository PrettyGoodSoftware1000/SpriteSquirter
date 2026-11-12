class_name Creature
extends Node3D
## The giant two-legged creature, assembled from primitive meshes.
##
## Walking is fully procedural: each foot stays planted until the body has
## moved far enough away from it, then it steps to a predicted landing spot.
## A two-bone IK solve places the thigh and shin between hip and foot, so the
## legs adapt to hills automatically. Local +Z is the creature's front.

signal footfall(pos: Vector3)

@export var max_speed := 4.5
@export var turn_speed := 1.6
@export var hip_height := 5.2
@export var hip_width := 1.25
@export var thigh_length := 3.4
@export var shin_length := 3.4
@export var step_distance := 1.9
@export var step_time := 0.55
@export var step_height := 1.3

var has_target := false
var target := Vector3.ZERO
var speed := 0.0
var heading := 0.0

var _pelvis: Node3D
var _head: Node3D
var _tail: Node3D
var _arms: Array[Node3D] = []
var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _feet: Array[Node3D] = []
var _plant: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_t: Array[float] = [1.0, 1.0]
var _stepping: Array[bool] = [false, false]
var _ground_y := 0.0
var _time := 0.0
var _cast_timer := 0.0
var _alarm_timer := 0.0


func _ready() -> void:
	_build()


## Puts the creature somewhere with both feet on the ground.
func place(pos: Vector3, facing: float) -> void:
	heading = facing
	rotation.y = heading
	_ground_y = Game.terrain.get_height(pos.x, pos.z)
	global_position = Vector3(pos.x, _ground_y, pos.z)
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	for k in 2:
		_plant[k] = _foot_home(_side(k), fwd, right)
		_stepping[k] = false
	_update_legs()


func move_to(pos: Vector3) -> void:
	target = pos
	has_target = true


func cast_fireball(at: Vector3) -> void:
	_cast_timer = 0.7
	var mouth := _head.to_global(Vector3(0.0, -0.3, 2.0))
	var fb := Fireball.new()
	Game.world_root.add_child(fb)
	fb.launch(mouth, at)


func _process(delta: float) -> void:
	_time += delta
	_cast_timer = maxf(0.0, _cast_timer - delta)
	_update_locomotion(delta)
	_update_feet(delta)
	_update_body(delta)
	_update_legs()
	_alarm_timer -= delta
	if _alarm_timer <= 0.0:
		_alarm_timer = 0.5
		Game.alarm(global_position, 16.0 if speed > 0.5 else 9.0)


# --- Locomotion -------------------------------------------------------------

func _update_locomotion(delta: float) -> void:
	var desired_speed := 0.0
	if has_target:
		var to := target - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 1.0:
			has_target = false
		else:
			var want := atan2(to.x, to.z)
			heading = rotate_toward(heading, want, turn_speed * delta)
			var facing := cos(angle_difference(heading, want))
			desired_speed = max_speed * clampf(facing, 0.0, 1.0) * clampf(dist / 5.0, 0.25, 1.0)
	speed = move_toward(speed, desired_speed, 3.0 * delta)
	rotation.y = heading
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var p := global_position + fwd * speed * delta
	p.x = clampf(p.x, -118.0, 118.0)
	p.z = clampf(p.z, -118.0, 118.0)
	# Body height follows the feet and the ground under the belly.
	var feet_y := (_foot_target_y(0) + _foot_target_y(1)) * 0.5
	var under := Game.terrain.get_height(p.x, p.z)
	_ground_y = lerpf(_ground_y, feet_y * 0.6 + under * 0.4, 1.0 - exp(-5.0 * delta))
	p.y = _ground_y
	global_position = p


func _update_feet(delta: float) -> void:
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	var dists: Array[float] = [0.0, 0.0]
	var homes: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for k in 2:
		homes[k] = _foot_home(_side(k), fwd, right)
		dists[k] = Vector2(homes[k].x - _plant[k].x, homes[k].z - _plant[k].z).length()
	for k in 2:
		if _stepping[k]:
			_step_t[k] = minf(1.0, _step_t[k] + delta / _current_step_time())
			if _step_t[k] >= 1.0:
				_stepping[k] = false
				_plant[k] = _step_to[k]
				_on_footfall(_plant[k])
			continue
		var other := 1 - k
		var threshold := step_distance if speed > 0.2 else 0.35
		if not _stepping[other] and dists[k] > threshold and dists[k] >= dists[other]:
			_stepping[k] = true
			_step_t[k] = 0.0
			_step_from[k] = _plant[k]
			var land := homes[k] + fwd * speed * _current_step_time() * 0.8
			land.y = Game.terrain.get_height(land.x, land.z)
			_step_to[k] = land


func _current_step_time() -> float:
	return clampf(step_time * (1.25 - speed / max_speed * 0.45), 0.35, 0.8)


func _foot_home(side: float, fwd: Vector3, right: Vector3) -> Vector3:
	var p := global_position + right * side * hip_width + fwd * speed * 0.25
	p.y = Game.terrain.get_height(p.x, p.z)
	return p


func _foot_target_y(k: int) -> float:
	return _step_to[k].y if _stepping[k] else _plant[k].y


func _foot_pos(k: int) -> Vector3:
	if not _stepping[k]:
		return _plant[k]
	var t := _step_t[k]
	var pos := _step_from[k].lerp(_step_to[k], smoothstep(0.0, 1.0, t))
	var travel := _step_from[k].distance_to(_step_to[k])
	pos.y += sin(t * PI) * step_height * clampf(travel / 2.0, 0.3, 1.0)
	return pos


func _side(k: int) -> float:
	return -1.0 if k == 0 else 1.0


func _on_footfall(pos: Vector3) -> void:
	Game.effects.spawn_dust(pos, 1.2)
	Game.shake(0.35, pos)
	for node in get_tree().get_nodes_in_group("destructibles"):
		var d := node as Destructible
		var flat := Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length()
		if flat < d.footprint * 0.7 + 1.2:
			d.stomp(pos)
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v.global_position.distance_to(pos) < 1.4:
			v.squish()
	footfall.emit(pos)


# --- Animation --------------------------------------------------------------

func _update_body(delta: float) -> void:
	var blend := 1.0 - exp(-10.0 * delta)
	var swing := 0.0
	var sway := 0.0
	for k in 2:
		if _stepping[k]:
			swing = sin(_step_t[k] * PI)
			# Lean the hips over the foot that carries the weight.
			sway = 0.07 * swing * (1.0 if k == 0 else -1.0)
	var bob := swing * 0.35 - 0.25 * (speed / max_speed)
	_pelvis.position.y = lerpf(_pelvis.position.y, hip_height + bob, blend)
	_pelvis.rotation.z = lerpf(_pelvis.rotation.z, -sway, blend)
	_pelvis.rotation.x = lerpf(_pelvis.rotation.x, speed / max_speed * 0.12, blend)

	# Arms swing against the legs.
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var stride := (_foot_pos(0) - _foot_pos(1)).dot(fwd)
	var arm_targets: Array[float] = [stride * 0.14, -stride * 0.14]
	if _cast_timer > 0.0:
		arm_targets[1] = -2.0
	for k in 2:
		_arms[k].rotation.x = lerpf(_arms[k].rotation.x, arm_targets[k], blend)
		_arms[k].rotation.z = _side(k) * 0.18

	_head.rotation.x = -bob * 0.15 - (0.25 if _cast_timer > 0.0 else 0.0)
	_head.rotation.y = sin(_time * 0.7) * 0.15
	_tail.rotation.y = sin(_time * 2.2) * 0.25
	_tail.rotation.x = sin(_time * 1.3) * 0.08


func _update_legs() -> void:
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	for k in 2:
		var hip := _pelvis.to_global(Vector3(_side(k) * hip_width, -0.2, 0.0))
		var ankle := _foot_pos(k) + Vector3.UP * 0.55
		var knee := _solve_knee(hip, ankle, fwd)
		_place_segment(_thighs[k], hip, knee, fwd)
		var reach := knee + (ankle - knee).normalized() * shin_length
		_place_segment(_shins[k], knee, reach, fwd)
		_feet[k].global_transform = Transform3D(Basis(Vector3.UP, heading), reach - Vector3.UP * 0.55)


## Two-bone IK: where the knee goes so thigh and shin connect hip to ankle.
func _solve_knee(hip: Vector3, ankle: Vector3, fwd: Vector3) -> Vector3:
	var to := ankle - hip
	var d := clampf(to.length(), 0.01, thigh_length + shin_length - 0.01)
	var dir := to.normalized()
	var a := (thigh_length * thigh_length - shin_length * shin_length + d * d) / (2.0 * d)
	var h := sqrt(maxf(thigh_length * thigh_length - a * a, 0.0))
	var bend := (fwd - dir * fwd.dot(dir)).normalized()
	return hip + dir * a + bend * h


## Stretches a Y-aligned mesh from `a` to `b`.
func _place_segment(mi: MeshInstance3D, a: Vector3, b: Vector3, fwd: Vector3) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.001:
		return
	var y := axis / length
	var x := y.cross(fwd)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


# --- Construction -----------------------------------------------------------

func _build() -> void:
	var skin := _mat(Color(0.47, 0.32, 0.68))
	var belly := _mat(Color(1.0, 0.72, 0.38))
	var horn := _mat(Color(0.96, 0.92, 0.78))
	var spike := _mat(Color(0.2, 0.78, 0.72))
	var white := _mat(Color(1, 1, 1))
	var black := _mat(Color(0.05, 0.05, 0.05))

	_pelvis = Node3D.new()
	_pelvis.name = "Pelvis"
	add_child(_pelvis)
	_pelvis.position.y = hip_height

	_add(_pelvis, _sphere(1.8, 2.6), skin, Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.3, 1, 1))
	_add(_pelvis, _sphere(2.2, 5.6), skin, Vector3(0, 2.8, -0.1), Vector3(0.12, 0, 0))
	_add(_pelvis, _sphere(1.6, 4.0), belly, Vector3(0, 2.3, 0.85), Vector3(0.12, 0, 0))
	for k in 4:
		_add(_pelvis, _cone(0.45, 1.3), spike, Vector3(0, 1.4 + k * 1.15, -1.95 + k * 0.12), Vector3(-0.9, 0, 0))

	_head = Node3D.new()
	_head.name = "Head"
	_pelvis.add_child(_head)
	_head.position = Vector3(0, 5.7, 0.55)
	_add(_head, _sphere(1.5, 2.7), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 1, 1.15))
	_add(_head, _sphere(1.0, 1.4), belly, Vector3(0, -0.35, 1.25))
	var mouth := BoxMesh.new()
	mouth.size = Vector3(1.2, 0.14, 0.4)
	_add(_head, mouth, black, Vector3(0, -0.55, 1.95))
	for side in [-1.0, 1.0]:
		var s: float = side
		_add(_head, _sphere(0.45, 0.9), white, Vector3(s * 0.62, 0.45, 1.15))
		_add(_head, _sphere(0.22, 0.44), black, Vector3(s * 0.64, 0.48, 1.53))
		_add(_head, _cone(0.32, 1.5), horn, Vector3(s * 0.95, 1.25, -0.1), Vector3(0, 0, -s * 0.55))
		_add(_head, _cone(0.08, 0.3), white, Vector3(s * 0.35, -0.72, 1.9), Vector3(PI, 0, 0))

	for k in 2:
		var s := _side(k)
		var shoulder := Node3D.new()
		_pelvis.add_child(shoulder)
		shoulder.position = Vector3(s * 2.25, 4.0, 0.2)
		_add(shoulder, _capsule(0.45, 3.4), skin, Vector3(0, -1.5, 0))
		_add(shoulder, _sphere(0.65, 1.2), belly, Vector3(0, -3.1, 0.1))
		for c in 3:
			_add(shoulder, _cone(0.12, 0.45), horn, Vector3((c - 1) * 0.25, -3.55, 0.35), Vector3(PI * 0.85, 0, 0))
		_arms.append(shoulder)

	_tail = Node3D.new()
	_pelvis.add_child(_tail)
	_tail.position = Vector3(0, 0.2, -1.6)
	for k in 4:
		var r := 1.0 - k * 0.2
		_add(_tail, _sphere(r, r * 2.0), skin, Vector3(0, -0.45 * k, -0.9 - 1.1 * k))
		_add(_tail, _cone(0.3 * r + 0.1, 0.8), spike, Vector3(0, -0.45 * k + r * 0.9, -0.9 - 1.1 * k), Vector3(-0.6, 0, 0))

	for k in 2:
		var thigh := _add(self, _capsule(0.75, thigh_length + 1.0), skin, Vector3.ZERO)
		thigh.top_level = true
		_thighs.append(thigh)
		var shin := _add(self, _capsule(0.6, shin_length + 0.8), skin, Vector3.ZERO)
		shin.top_level = true
		_shins.append(shin)
		var foot := Node3D.new()
		add_child(foot)
		foot.top_level = true
		_add(foot, _sphere(0.9, 1.0), skin, Vector3(0, 0.35, 0.45), Vector3.ZERO, Vector3(1.2, 1, 1.9))
		for c in 3:
			_add(foot, _cone(0.18, 0.6), horn, Vector3((c - 1) * 0.45, 0.25, 2.1), Vector3(PI / 2.0, 0, 0))
		_feet.append(foot)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


func _sphere(radius: float, height: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = height
	return s


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	return c


func _cone(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 10
	c.rings = 1
	return c
