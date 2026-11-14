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
##
## The tortoise fights goblins by itself. Goblins within REACH get a stomp
## (everything inside STOMP_RADIUS of the foot is hurt, so it never stomps
## when a villager or one of the village's buildings would be caught) or
## are scooped up, up to five at a time, and thrown or eaten. During a
## raid it walks over to raiders by itself unless the player sent it
## somewhere. Its ordinary footsteps squash goblins and strangers, but
## never the player's own villagers. With goblins about it is "alert": it
## walks ALERT_SPEED times as fast, scowls, bares its mouth and its eyes
## dart around.
##
## The face is drawn on top of the model: eyeballs, pupils that look about,
## lids that blink and slant with its mood, and an inked mouth line that
## opens into a dark mouth with the jaw.

signal footfall(pos: Vector3)

const MODEL := "res://assets/creature/creature.glb"
## Height of the ankle joint above the sole of the foot.
const ANKLE_HEIGHT := 0.75
## How close goblins must be before the tortoise attacks them.
const REACH := 7.5
const STOMP_RADIUS := 5.0
const STOMP_TIME := 1.1
## How far from the body the stomping foot can come down.
const STOMP_STRIDE := 2.6
const GRAB_RADIUS := 5.5
## During a raid, raiders this close are walked to.
const HUNT_RANGE := 55.0
const ALERT_SPEED := 1.2

enum Action { NONE, STOMP, GRAB }

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
var _bob := 0.0
var _sway := 0.0
var _lean := 0.0
var _look_yaw := 0.0
var _look_at := Vector3.ZERO
var _arm_swing: Array[float] = [0.0, 0.0]
var _jaw := 0.0

## Cannot walk until Game.now passes this (the roots spell).
var snared_until := 0.0

var _action := Action.NONE
var _action_t := 0.0
var _action_cooldown := 0.0
var _action_point := Vector3.ZERO
var _stomp_leg := -1
var _held: Array[Villager] = []
var _held_from: Array[Vector3] = []
var _eating := false
var _released := 0
var _scan_timer := 0.0
## Walking somewhere by its own choice (to reach raiders).
var _auto := false
## Standing still and turning to face goblins before attacking.
var _turning := false
var _crouch := 0.0
var _jaw_want := 0.0
## Where the arms point: x outwards, y up, z forwards.
var _arm_pose := Vector3(0.3, -1.0, 0.12)
var _arm_want := Vector3(0.3, -1.0, 0.12)

## Goblins in reach or raiders in sight.
var _alert := false
## 0 gloomy .. 1 angry.
var _anger := 0.0
var _pupils: Array[MeshInstance3D] = []
var _lids: Array[MeshInstance3D] = []
var _eye_centres: Array[Vector3] = []
var _gaze := Vector2.ZERO
var _dart := Vector2.ZERO
var _dart_timer := 0.0
var _blink := 0.0
var _blink_timer := 3.0
var _mouth := ImmediateMesh.new()
var _mouth_material := StandardMaterial3D.new()
## The jaw opening and anger the mouth was last drawn with.
var _mouth_drawn := Vector2(-1.0, -1.0)


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
	_auto = false
	_look_at = pos


## Makes the creature look at something startling (such as a fireball
## landing) and gasp.
func watch(pos: Vector3) -> void:
	_look_at = pos
	_cast_timer = 0.9


func _process(delta: float) -> void:
	_time += delta
	_cast_timer = maxf(0.0, _cast_timer - delta)
	_update_attacks(delta)
	_update_locomotion(delta)
	_update_feet(delta)
	_update_body(delta)
	_update_legs()
	_update_face(delta)


# --- Locomotion -------------------------------------------------------------

func _update_locomotion(delta: float) -> void:
	var desired_speed := 0.0
	if has_target:
		var to := target - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 1.0:
			has_target = false
			_auto = false
		else:
			var want := atan2(to.x, to.z)
			heading = rotate_toward(heading, want, turn_speed * delta)
			var facing := cos(angle_difference(heading, want))
			var top := max_speed * (ALERT_SPEED if _alert else 1.0)
			desired_speed = top * clampf(facing, 0.0, 1.0) * clampf(dist / 5.0, 0.25, 1.0)
	if _action != Action.NONE or _turning:
		# Stand still and face the goblins.
		desired_speed = 0.0
		var facing_to := _action_point - global_position
		heading = rotate_toward(heading, atan2(facing_to.x, facing_to.z), turn_speed * 1.6 * delta)
	if Game.now < snared_until:
		desired_speed = 0.0
		speed = 0.0
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
			_step_t[k] = minf(1.0, _step_t[k] + delta / (STOMP_TIME if k == _stomp_leg else _current_step_time()))
			if _step_t[k] >= 1.0:
				_stepping[k] = false
				_plant[k] = _step_to[k]
				_on_footfall(_plant[k])
				if k == _stomp_leg:
					_on_stomp(_plant[k])
			continue
		if _action != Action.NONE:
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
	if k == _stomp_leg:
		# Lift the foot high, hold it, then slam it down.
		var high := _step_from[k].lerp(_step_to[k], smoothstep(0.0, 0.7, t))
		var drop := smoothstep(0.78, 1.0, t)
		high.y += 3.2 * smoothstep(0.0, 0.5, t) * (1.0 - drop * drop)
		return high
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
		# The tortoise watches its step around its own village.
		if not v.owned and v.global_position.distance_to(pos) < 1.8:
			v.squish()
	footfall.emit(pos)


# --- Fighting goblins ---------------------------------------------------------

func _update_attacks(delta: float) -> void:
	_action_cooldown = maxf(0.0, _action_cooldown - delta)
	if _action == Action.GRAB:
		_alert = true
		_update_grab(delta)
		return
	if _action == Action.STOMP:
		_alert = true
		_jaw_want = 0.5
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 0.3
	var near: Array[Villager] = []
	var nearest: Villager = null
	var nearest_d := INF
	var hunt: Villager = null
	var hunt_d := HUNT_RANGE
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.state == Villager.State.HELD:
			continue
		var d := _flat(g.global_position, global_position)
		if d < REACH:
			near.append(g)
			if d < nearest_d:
				nearest_d = d
				nearest = g
		elif g.raiding and d < hunt_d:
			hunt_d = d
			hunt = g
	_alert = nearest != null or hunt != null
	_jaw_want = 0.16 if _alert else 0.0
	if nearest == null:
		_turning = false
		# Nothing in reach: go after raiders, unless the player sent us somewhere.
		if hunt != null and (not has_target or _auto) and Game.now >= snared_until:
			target = hunt.global_position
			has_target = true
			_auto = true
			_look_at = target
		return
	if _auto:
		has_target = false
		_auto = false
	_action_point = nearest.global_position
	_look_at = _action_point
	var to := _action_point - global_position
	to.y = 0.0
	# Stop and face them, even in the middle of a walk the player ordered.
	_turning = _action_cooldown < 0.4
	var facing := absf(angle_difference(heading, atan2(to.x, to.z))) < 0.55
	if not facing or _action_cooldown > 0.0 or _stepping[0] or _stepping[1] or speed > 0.6:
		return
	var point := global_position + to.normalized() * minf(to.length(), STOMP_STRIDE)
	var in_blast := 0
	for g in near:
		if _flat(g.global_position, point) < STOMP_RADIUS:
			in_blast += 1
	if _stomp_is_safe(point) and in_blast > 0 and (in_blast >= 3 or randf() < 0.5):
		_start_stomp(point)
	else:
		_start_grab(near)


## A stomp hurts everything round the foot, so it is only allowed when no
## villager and none of the village's buildings would be caught in it.
func _stomp_is_safe(point: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if not v.goblin and _flat(v.global_position, point) < STOMP_RADIUS + 1.0:
			return false
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if _flat(b.global_position, point) < b.footprint * 0.7 + 1.6:
			return false
	return true


func _start_stomp(point: Vector3) -> void:
	_action = Action.STOMP
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	var k := 1 if (point - global_position).dot(right) > 0.0 else 0
	point.y = Game.terrain.get_height(point.x, point.z)
	_stomp_leg = k
	_stepping[k] = true
	_step_t[k] = 0.0
	_step_from[k] = _plant[k]
	_step_to[k] = point


func _on_stomp(pos: Vector3) -> void:
	Game.effects.spawn_dust(pos, 3.2)
	Game.shake(1.0, pos)
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		var d := _flat(v.global_position, pos)
		if d >= STOMP_RADIUS:
			continue
		if v.owned:
			continue
		# Enough to kill a goblin at the centre; less towards the edge.
		v.take_hit(Villager.HEALTH * (2.0 - d / STOMP_RADIUS), self)
		if not v.is_alive():
			v.fling(pos, 8.0, false)
	_stomp_leg = -1
	_action = Action.NONE
	_action_cooldown = 1.4


## Scoops up the nearest goblins, at most three to five of them.
func _start_grab(near: Array[Villager]) -> void:
	near.sort_custom(func(a: Villager, b: Villager) -> bool:
		return _flat(a.global_position, _action_point) < _flat(b.global_position, _action_point))
	_held.clear()
	_held_from.clear()
	var most := randi_range(3, 5)
	for g in near:
		# Ogres are far too big to pick up.
		if not g.ogre and _held.size() < most and _flat(g.global_position, _action_point) < GRAB_RADIUS:
			_held.append(g)
	if _held.is_empty():
		_action_cooldown = 0.8
		return
	_jaw_want = 0.3
	_action = Action.GRAB
	_action_t = 0.0
	_released = 0
	_eating = randf() < 0.5


## Reach down, pick the goblins up, then eat them one by one or hurl them.
func _update_grab(delta: float) -> void:
	var before := _action_t
	_action_t += delta
	var t := _action_t
	if t < 0.7:
		_crouch = 1.0
		_arm_want = Vector3(0.2, -0.75, 0.9)
	elif before < 0.7:
		for g in _held:
			if is_instance_valid(g) and g.is_alive():
				g.grab()
				_held_from.append(g.global_position)
			else:
				_held_from.append(global_position)
	elif t < 1.5:
		_crouch = 0.0
		_arm_want = Vector3(0.25, 0.15, 1.0)
	elif _eating:
		_arm_want = Vector3(-0.3, 0.75, 0.8)
		_jaw_want = 0.25 + 0.3 * absf(sin(t * 12.0))
		# One goblin goes in every quarter of a second.
		var due := floori((t - 1.7) / 0.25) + 1
		while _released < mini(due, _held.size()):
			var g := _held[_released]
			if is_instance_valid(g) and g.state == Villager.State.HELD:
				g.eaten()
			_released += 1
		if t > 1.9 + 0.25 * _held.size():
			_end_grab()
			return
	else:
		# Wind up, then throw.
		_arm_want = Vector3(0.35, 0.9, -0.3) if t < 1.9 else Vector3(0.2, 0.0, 1.0)
		if before < 1.95 and t >= 1.95:
			var fwd := Vector3(sin(heading), 0.0, cos(heading))
			var right := Vector3(cos(heading), 0.0, -sin(heading))
			for g in _held:
				if is_instance_valid(g) and g.state == Villager.State.HELD:
					g.toss(fwd * randf_range(15.0, 22.0) + Vector3.UP * randf_range(9.0, 13.0) + right * randf_range(-5.0, 5.0))
			_released = _held.size()
		if t > 2.5:
			_end_grab()
			return
	# Goblins in hand: half in each fist, flying up from the ground at first.
	var lift := smoothstep(0.7, 1.05, t)
	var mouth := _mouth_pos()
	for i in range(_released, mini(_held.size(), _held_from.size())):
		var g := _held[i]
		if not is_instance_valid(g) or g.state != Villager.State.HELD:
			continue
		var hand := _hand_pos(i % 2) + Vector3(0.0, -0.6 + 0.35 * (i >> 1), 0.0)
		if _eating and t > 1.5:
			hand = hand.lerp(mouth, 0.6)
		g.global_position = _held_from[i].lerp(hand, lift)


func _end_grab() -> void:
	for g in _held:
		# Anything still in hand (it should not happen) is dropped, dead.
		if is_instance_valid(g) and g.state == Villager.State.HELD:
			g.toss(Vector3.UP * 3.0)
	_held.clear()
	_held_from.clear()
	_action = Action.NONE
	_action_cooldown = 1.0
	_crouch = 0.0
	_jaw_want = 0.0
	_arm_want = Vector3(0.3, -1.0, 0.12)


func _hand_pos(k: int) -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_bone["hand_l" if k == 0 else "hand_r"]).origin


func _mouth_pos() -> Vector3:
	return _skel.global_transform * (_skel.get_bone_global_pose(_bone["head"]) * Vector3(0.0, -0.3, 1.5))


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
	# Crouching (to grab) bends the knees and tips the body forwards.
	var stoop := _crouch + (0.35 if _stomp_leg >= 0 else 0.0)
	_bob = lerpf(_bob, swing * 0.3 - 0.3 * pace - 0.12 + breath * 0.03 - stoop * 0.9, blend)
	_sway = lerpf(_sway, sway_target, blend)
	_lean = lerpf(_lean, pace * 0.14 + stoop * 0.42, blend)

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
	_jaw = lerpf(_jaw, maxf(0.4 if casting else 0.03 + 0.02 * breath, _jaw_want), 1.0 - exp(-14.0 * delta))
	_skel.set_bone_pose_rotation(_bone["jaw"], Quaternion(Vector3.RIGHT, _jaw))

	# Arms hang from the bind pose and swing against the legs.
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var stride := (_foot_pos(0) - _foot_pos(1)).dot(fwd)
	var swing_targets: Array[float] = [stride * 0.16, -stride * 0.16]
	_arm_pose = _arm_pose.lerp(_arm_want, 1.0 - exp(-9.0 * delta))
	for k in 2:
		var side := "l" if k == 0 else "r"
		_arm_swing[k] = lerpf(_arm_swing[k], swing_targets[k], blend)
		var rest_dir: Vector3 = (_rest["arm_lower_" + side] - _rest["arm_upper_" + side]).normalized()
		var hang := Vector3(_side(k) * _arm_pose.x, _arm_pose.y, _arm_pose.z).normalized()
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

	# The face, attached to the head bone: eyeballs, pupils and lids that
	# move on their own, and the mouth.
	var attach := BoneAttachment3D.new()
	_skel.add_child(attach)
	attach.bone_name = "head"
	var paint := Art.paint("plaster", 0.25)
	var whites := MeshBuilder.new()
	whites.color = Color(0.96, 0.94, 0.84)
	for k in 2:
		var s := _side(k)
		var centre := Vector3(s * 0.74, 0.5, 1.22)
		_eye_centres.append(centre)
		whites.add_blob(Vector3(0.34, 0.34, 0.3), Transform3D(Basis(), centre), null, 0.0, 8, 12)
		var pupil := MeshBuilder.new()
		pupil.color = Color(0.05, 0.04, 0.04)
		pupil.add_blob(Vector3(0.15, 0.17, 0.1), Transform3D.IDENTITY, null, 0.0, 6, 10)
		pupil.color = Color(1.0, 1.0, 1.0)
		pupil.add_blob(Vector3(0.04, 0.045, 0.03), Transform3D(Basis(), Vector3(0.05, 0.07, 0.085)), null, 0.0, 4, 6)
		_pupils.append(_face_part(attach, pupil.commit(), Art.paint("plaster", 0.0)))
		# The lid droops towards the outside of the face: instant gloom.
		var lid := MeshBuilder.new()
		lid.color = Color(0.36, 0.38, 0.2)
		lid.add_blob(Vector3(0.42, 0.3, 0.38), Transform3D.IDENTITY, null, 0.0, 6, 10)
		_lids.append(_face_part(attach, lid.commit(), paint))
	_face_part(attach, whites.commit(), paint)
	_mouth_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mouth_material.vertex_color_use_as_albedo = true
	_mouth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mouth := _face_part(attach, _mouth, null)
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_face(0.0)


func _face_part(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	return mi


# --- Face -----------------------------------------------------------------------

func _update_face(delta: float) -> void:
	_anger = move_toward(_anger, 1.0 if _alert else 0.0, delta * 3.0)
	# The eyes dart from place to place, faster when there is danger, and
	# lean towards whatever the tortoise is looking at.
	_dart_timer -= delta
	if _dart_timer <= 0.0:
		_dart_timer = randf_range(0.25, 0.9) if _alert else randf_range(0.7, 2.6)
		_dart = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.5)) * (0.11 if _alert else 0.08)
		if randf() < 0.3:
			_dart = Vector2.ZERO
	var to := _look_at - global_position
	var aside := 0.0
	if to.length() > 3.0:
		aside = clampf(angle_difference(heading + _look_yaw, atan2(to.x, to.z)), -1.0, 1.0)
	var want := _dart + Vector2(aside * 0.1, -0.06 * (1.0 - _anger))
	_gaze = _gaze.lerp(want, 1.0 - exp(-18.0 * delta))
	_gaze = Vector2(clampf(_gaze.x, -0.13, 0.13), clampf(_gaze.y, -0.12, 0.1))
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.5, 6.0)
		_blink = 0.14
	_blink = maxf(0.0, _blink - delta)
	var shut := 1.0 if _blink > 0.0 else 0.0
	for k in 2:
		var s := _side(k)
		var c := _eye_centres[k]
		_pupils[k].position = c + Vector3(_gaze.x - s * 0.04, _gaze.y - 0.04, 0.25 - 1.2 * _gaze.length_squared())
		_pupils[k].scale = Vector3.ONE * lerpf(1.0, 0.72, _anger)
		# Sad lids droop outwards; angry ones slant down to the nose and sit lower.
		_lids[k].rotation.z = lerpf(-s * 0.38, s * 0.5, _anger)
		_lids[k].position = c + Vector3(s * 0.03, lerpf(0.2, 0.14, _anger) - shut * 0.22, 0.02 + shut * 0.05)
	if absf(_jaw - _mouth_drawn.x) > 0.01 or absf(_anger - _mouth_drawn.y) > 0.05:
		_mouth_drawn = Vector2(_jaw, _anger)
		_draw_mouth(maxf(0.0, _jaw - 0.05), _anger)


## Draws the mouth in head space: a black line along the lip that follows
## the frown carved into the model, and, when the jaw is open, the dark
## inside of the mouth with a second line for the lower lip.
func _draw_mouth(open: float, anger: float) -> void:
	_mouth.clear_surfaces()
	var upper := PackedVector3Array()
	var lower := PackedVector3Array()
	var droop := lerpf(0.3, 0.2, anger)
	for i in 13:
		var t := i / 6.0 - 1.0
		var lip := Vector3(0.85 * t, -0.08 - droop * t * t, 2.1 - 0.5 * t * t)
		var gape := 1.45 * open * pow(1.0 - t * t, 0.6)
		upper.append(lip)
		# The open mouth hangs just in front of the stretched skin of the jaw.
		lower.append(lip + Vector3(0.0, -gape, 0.1 * minf(gape, 1.0) - 0.12 * gape * gape))
	if open > 0.03:
		_mouth.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mouth_material)
		_mouth.surface_set_color(Color(0.11, 0.015, 0.03))
		for i in 13:
			_mouth.surface_add_vertex(upper[i] + Vector3(0, 0, 0.04))
			_mouth.surface_add_vertex(lower[i] + Vector3(0, 0, 0.04))
		_mouth.surface_end()
		for i in 13:
			upper[i].z += 0.06
			lower[i].z += 0.06
		_ink_line(lower, 0.04)
	_ink_line(upper, 0.05 + 0.02 * anger)


## A black ribbon along `points`, thinner towards its ends.
func _ink_line(points: PackedVector3Array, half_width: float) -> void:
	_mouth.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mouth_material)
	_mouth.surface_set_color(Color(0.03, 0.02, 0.03))
	for i in points.size():
		var t := i * 2.0 / (points.size() - 1) - 1.0
		var half := Vector3(0.0, half_width * (0.4 + 0.6 * (1.0 - t * t)), 0.0)
		_mouth.surface_add_vertex(points[i] + half)
		_mouth.surface_add_vertex(points[i] - half)
	_mouth.surface_end()
