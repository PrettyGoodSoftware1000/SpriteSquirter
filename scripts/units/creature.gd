class_name Creature
extends Node3D
## The giant creature: a gloomy tortoise that walks on two legs.
##
## The model (assets/creature/creature.glb) is a single skinned mesh on a
## skeleton, sculpted by tools/bake_creature.py. All animation is procedural:
## each foot stays planted until the body has moved far enough away, then it
## steps to a predicted landing spot, and a two-bone IK solve bends the
## thigh and shin to connect hip and ankle. Spine, arms, head, jaw and tail
## are posed with simple rotations on top. Local +Z is the creature's front.

signal footfall(pos: Vector3)

const MODEL := "res://assets/creature/creature.glb"
## Height of the ankle joint above the sole of the foot.
const ANKLE_HEIGHT := 0.75

@export var max_speed := 3.6
@export var turn_speed := 1.2
@export var step_distance := 1.6
@export var step_time := 0.7
@export var step_height := 0.9

var has_target := false
var target := Vector3.ZERO
var speed := 0.0
var heading := 0.0

var _skel: Skeleton3D
var _bone := {}
var _rest := {}
var _foot_spread := 1.5
var _thigh_length := 2.4
var _shin_length := 2.3
var _plant: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_t: Array[float] = [1.0, 1.0]
var _stepping: Array[bool] = [false, false]
var _ground_y := 0.0
var _time := 0.0
var _cast_timer := 0.0
var _alarm_timer := 0.0
var _bob := 0.0
var _sway := 0.0
var _lean := 0.0
var _look_yaw := 0.0
var _look_at := Vector3.ZERO
var _arm_swing: Array[float] = [0.0, 0.0]
var _jaw := 0.0


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
	_look_at = global_position + fwd * 20.0
	_update_body(1.0)
	_update_legs()


func move_to(pos: Vector3) -> void:
	target = pos
	has_target = true
	_look_at = pos


## Makes the creature look at something startling (such as a fireball
## landing) and gasp.
func watch(pos: Vector3) -> void:
	_look_at = pos
	_cast_timer = 0.9


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
		Game.alarm(global_position, 18.0 if speed > 0.5 else 10.0)


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
	if not Game.terrain.is_inside(p.x, p.z):
		# Never step off the edge of the island.
		p = global_position
		has_target = false
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
			if not Game.terrain.is_inside(land.x, land.z):
				land = homes[k]
			land.y = Game.terrain.get_height(land.x, land.z)
			_step_to[k] = land


func _current_step_time() -> float:
	return clampf(step_time * (1.25 - speed / max_speed * 0.45), 0.35, 0.85)


func _foot_home(side: float, fwd: Vector3, right: Vector3) -> Vector3:
	var p := global_position + right * side * _foot_spread + fwd * speed * 0.25
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


## -1 for leg 0 (the "l" bones, at -X), +1 for leg 1 (the "r" bones).
func _side(k: int) -> float:
	return -1.0 if k == 0 else 1.0


func _on_footfall(pos: Vector3) -> void:
	Game.effects.spawn_dust(pos, 1.4)
	Game.shake(0.35, pos)
	for node in get_tree().get_nodes_in_group("destructibles"):
		var d := node as Destructible
		var flat := Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length()
		if flat < d.footprint * 0.7 + 1.4:
			d.stomp(pos)
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v.global_position.distance_to(pos) < 1.8:
			v.squish()
	footfall.emit(pos)


# --- Animation --------------------------------------------------------------

func _update_body(delta: float) -> void:
	var blend := 1.0 - exp(-10.0 * delta)
	var pace := speed / max_speed
	var swing := 0.0
	var sway_target := 0.0
	for k in 2:
		if _stepping[k]:
			swing = sin(_step_t[k] * PI)
			# Shift the weight over the foot that stays on the ground.
			sway_target = 0.08 * swing * (1.0 if k == 0 else -1.0)
	var breath := sin(_time * 1.6)
	_bob = lerpf(_bob, swing * 0.3 - 0.3 * pace - 0.12 + breath * 0.03, blend)
	_sway = lerpf(_sway, sway_target, blend)
	_lean = lerpf(_lean, pace * 0.14, blend)

	_skel.set_bone_pose_position(_bone["pelvis"], _rest["pelvis"] + Vector3(-_sway * 3.0, _bob, 0.0))
	_skel.set_bone_pose_rotation(_bone["pelvis"], Quaternion.from_euler(Vector3(_lean, 0.0, -_sway)))
	_skel.set_bone_pose_rotation(_bone["spine"], Quaternion.from_euler(Vector3(_lean * 0.4 + breath * 0.01, 0.0, _sway * 0.7)))
	_skel.set_bone_pose_scale(_bone["chest"], Vector3.ONE * (1.0 + breath * 0.012))

	# Head: look towards whatever the creature is doing, and open the jaw to cast.
	var to := _look_at - global_position
	var want_yaw := clampf(angle_difference(heading, atan2(to.x, to.z)), -0.7, 0.7) if to.length() > 3.0 else 0.0
	_look_yaw = lerpf(_look_yaw, want_yaw + sin(_time * 0.6) * 0.08, 1.0 - exp(-4.0 * delta))
	var casting := _cast_timer > 0.0
	# The tortoise hangs its head, and lifts it when something startles it.
	var nod := 0.16 - _bob * 0.12 - (0.3 if casting else 0.0) - _lean * 0.8
	_skel.set_bone_pose_rotation(_bone["neck"], Quaternion.from_euler(Vector3(nod * 0.5, _look_yaw * 0.5, 0.0)))
	_skel.set_bone_pose_rotation(_bone["head"], Quaternion.from_euler(Vector3(nod * 0.5, _look_yaw * 0.5, _sway * 0.5)))
	_jaw = lerpf(_jaw, 0.4 if casting else 0.03 + 0.02 * breath, 1.0 - exp(-14.0 * delta))
	_skel.set_bone_pose_rotation(_bone["jaw"], Quaternion(Vector3.RIGHT, _jaw))

	# Arms hang from the bind pose and swing against the legs.
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var stride := (_foot_pos(0) - _foot_pos(1)).dot(fwd)
	var swing_targets: Array[float] = [stride * 0.16, -stride * 0.16]
	for k in 2:
		var side := "l" if k == 0 else "r"
		_arm_swing[k] = lerpf(_arm_swing[k], swing_targets[k], blend)
		var rest_dir: Vector3 = (_rest["arm_lower_" + side] - _rest["arm_upper_" + side]).normalized()
		var hang := Vector3(_side(k) * 0.3, -1.0, 0.12).normalized()
		var upper := Quaternion(Vector3.RIGHT, _arm_swing[k]) * Quaternion(rest_dir, hang)
		_skel.set_bone_pose_rotation(_bone["arm_upper_" + side], upper)
		var bend := -0.25 - 0.3 * maxf(-_arm_swing[k], 0.0) - 0.1 * pace
		_skel.set_bone_pose_rotation(_bone["arm_lower_" + side], Quaternion(Vector3.RIGHT, bend) * Quaternion(Vector3.BACK, _side(k) * 0.2))

	# Tail: a lazy wave that trails behind turns and bounces with each step.
	for i in 4:
		var wave := sin(_time * 1.9 - i * 0.8) * (0.07 + 0.03 * i) - _sway * 1.2
		var lift := 0.06 - _lean * 0.5 + sin(_time * 1.3 - i * 0.6) * 0.03 + swing * 0.03
		_skel.set_bone_pose_rotation(_bone["tail%d" % (i + 1)], Quaternion.from_euler(Vector3(lift, wave, 0.0)))


func _update_legs() -> void:
	var to_skel := _skel.global_transform.affine_inverse()
	var pelvis := _skel.get_bone_global_pose(_bone["pelvis"])
	for k in 2:
		var side := "l" if k == 0 else "r"
		var hip: Vector3 = pelvis * (_rest["thigh_" + side] - _rest["pelvis"])
		var sole := _foot_pos(k)
		var ankle: Vector3 = to_skel * (sole + Vector3.UP * ANKLE_HEIGHT)
		var knee := _solve_knee(hip, ankle)
		var reach := knee + (ankle - knee).normalized() * _shin_length
		var thigh_rest: Vector3 = _rest["shin_" + side] - _rest["thigh_" + side]
		var shin_rest: Vector3 = _rest["foot_" + side] - _rest["shin_" + side]
		_skel.set_bone_global_pose(_bone["thigh_" + side], Transform3D(_aim(knee - hip, thigh_rest), hip))
		_skel.set_bone_global_pose(_bone["shin_" + side], Transform3D(_aim(reach - knee, shin_rest), knee))
		# Planted feet tilt to match the slope; a foot in the air points its toes down.
		var normal := to_skel.basis * Game.terrain.get_normal(sole.x, sole.z)
		var foot_basis := Basis(Quaternion(Vector3.UP, normal.normalized()))
		if _stepping[k]:
			foot_basis = foot_basis * Basis(Vector3.RIGHT, sin(_step_t[k] * PI) * 0.45)
		_skel.set_bone_global_pose(_bone["foot_" + side], Transform3D(foot_basis, reach))


## Two-bone IK: where the knee goes so thigh and shin connect hip to ankle.
## Works in skeleton space, where +Z is forward.
func _solve_knee(hip: Vector3, ankle: Vector3) -> Vector3:
	var to := ankle - hip
	var d := clampf(to.length(), 0.01, _thigh_length + _shin_length - 0.01)
	var dir := to.normalized()
	var a := (_thigh_length * _thigh_length - _shin_length * _shin_length + d * d) / (2.0 * d)
	var h := sqrt(maxf(_thigh_length * _thigh_length - a * a, 0.0))
	var bend := (Vector3.BACK - dir * Vector3.BACK.dot(dir)).normalized()
	return hip + dir * a + bend * h


## The rotation that turns a bone from its rest direction to `dir`, keeping
## the knee pointing forwards.
func _aim(dir: Vector3, rest_dir: Vector3) -> Basis:
	return _frame(dir) * _frame(rest_dir).inverse()


func _frame(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


# --- Construction -----------------------------------------------------------

func _build() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _skel.get_bone_count():
		_bone[_skel.get_bone_name(i)] = i
		_rest[_skel.get_bone_name(i)] = _skel.get_bone_global_rest(i).origin
	_foot_spread = absf(_rest["foot_r"].x)
	_thigh_length = _rest["thigh_r"].distance_to(_rest["shin_r"])
	_shin_length = _rest["shin_r"].distance_to(_rest["foot_r"])

	var hide := ShaderMaterial.new()
	hide.shader = Art.shader("creature")
	hide.set_shader_parameter("detail_tex", Art.tex("hide_detail"))
	hide.next_pass = Art.outline(1.0)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.material_override = hide
		mi.extra_cull_margin = 6.0

	# Sad eyes with heavy lids, attached to the head bone.
	var attach := BoneAttachment3D.new()
	_skel.add_child(attach)
	attach.bone_name = "head"
	var eyes := MeshBuilder.new()
	var lids := MeshBuilder.new()
	for sx in [-1.0, 1.0]:
		var s: float = sx
		var centre := Vector3(s * 0.74, 0.5, 1.22)
		eyes.color = Color(0.96, 0.94, 0.84)
		eyes.add_blob(Vector3(0.34, 0.34, 0.3), Transform3D(Basis(), centre), null, 0.0, 6, 10)
		eyes.color = Color(0.05, 0.04, 0.04)
		eyes.add_blob(Vector3(0.15, 0.17, 0.1), Transform3D(Basis(), centre + Vector3(-s * 0.04, -0.1, 0.24)), null, 0.0, 5, 8)
		# The lid droops towards the outside of the face: instant gloom.
		lids.color = Color(0.36, 0.38, 0.2)
		lids.add_blob(Vector3(0.42, 0.3, 0.38), Transform3D(Basis(Vector3.BACK, -s * 0.38), centre + Vector3(s * 0.03, 0.2, 0.02)), null, 0.0, 6, 10)
	for builder in [eyes, lids]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = (builder as MeshBuilder).commit()
		mesh.material_override = Art.paint("plaster", 0.25)
		attach.add_child(mesh)
