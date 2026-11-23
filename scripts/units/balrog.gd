class_name Balrog
extends Creature
## The goblins' giant: a horned demon that hatches at one of their caves and
## grows exactly as the player's creature does (from START_SIZE to full
## size over Game.settings.creature_grow_minutes). It walks and fights with
## the Creature's own body and animation, but it is `hostile`: its stomps
## and steps hurt the village's people and spare the goblins.
##
## Until it is full grown it only guards its cave: anyone of the village's
## (or the player's creature) who comes within Balance "balrog_guard_radius"
## of its post is attacked, and then it goes back. Once full grown it also
## marches with every midnight raid, by a painted goblin path if the map
## has one, and knocks the village's buildings down with its stomps.
##
## It smoulders: smoke and sparks rise from it, the cracks in its hide
## glow, and every step leaves a small fire that burns out by itself
## without spreading.
##
## From "balrog_fireball_size" of its full size it spits a fireball every
## "balrog_fireball_seconds" at whatever group of enemies it can see. It
## cannot fly. It always walks at "balrog_speed", a little slower than a
## goblin marches.
##
## At no health it dies (it does not get up again), and the village gets
## "balrog_bones" bones. GoblinRaids hatches the next one.
##
## Its model is the owner's Meshy model (assets/creature/balrog.glb): a
## painted texture on a humanoid (Mixamo) skeleton, with a Walking clip.
## It does not use the Creature's own blob-model body: the walk clip plays
## as fast as it really moves (so its feet do not slide), its footfalls
## come where the clip puts its feet down, and standing still it settles
## into the model's own crouched stance. Code adds the rest on top: it
## breathes, leans into its stride, turns its head to what it watches,
## tips it back to spit fire, lifts a leg high to stomp, and
## falls on its face when it dies.

signal died
signal grew_up

const SPEC := {
	"name": "Balrog", "model": "res://assets/creature/balrog.glb", "speed": 2.3,
	"nervous": 0.0, "arm": Vector3(0.3, -1.0, 0.2),
}
## The model is 1.86 m tall; this makes it about as tall as the old one
## (11 m, full grown).
const MODEL_SCALE := 6.0
## Metres the model's feet carry it in one second of the walk clip (at
## MODEL_SCALE 1): the clip is played this much faster or slower to match
## how fast it really walks.
const CLIP_SPEED := 1.43
## Where in the walk clip (as a share of its length) each foot comes down:
## leg 0 (the right foot, at -X) and leg 1 (the left).
const FOOTFALLS: Array[float] = [0.75, 0.28]
## The skeleton's bones (Mixamo names; Godot turns "mixamorig:" into
## "mixamorig_" on import). Arms, legs and feet in pairs: right (leg 0,
## at -X), then left.
const HIPS := "mixamorig_Hips"
const SPINE := "mixamorig_Spine"
const CHEST := "mixamorig_Spine2"
const NECK := "mixamorig_Neck"
const HEAD := "mixamorig_Head"
## A bone at the front of the face, just above the mouth.
const FACE := "headfront"
const ARMS: Array[String] = ["mixamorig_RightArm", "mixamorig_LeftArm"]
const FOREARMS: Array[String] = ["mixamorig_RightForeArm", "mixamorig_LeftForeArm"]
const HANDS: Array[String] = ["mixamorig_RightHand", "mixamorig_LeftHand"]
const THIGHS: Array[String] = ["mixamorig_RightUpLeg", "mixamorig_LeftUpLeg"]
const SHINS: Array[String] = ["mixamorig_RightLeg", "mixamorig_LeftLeg"]
const TOES: Array[String] = ["mixamorig_RightToeBase", "mixamorig_LeftToeBase"]
## How long the body lies there before it crumbles.
const DEATH_SECONDS := 9.0
## While raiding it goes for anyone this close.
const RAID_SIGHT := 45.0
## Its claw slashes at the other giant: one clip for each claw, right
## first, as ARMS. Made by tools/balrog_claw_slash.py (the source is
## balrog_claw_slash.blend); the claw lands about STRIKE_LANDS in.
const SLASH_MODEL := "res://assets/creature/balrog_claw_slash.glb"
const SLASH_CLIPS: Array[String] = ["ClawSlash_R", "ClawSlash_L"]

var cave: Node3D
## Marching on the village with the goblins.
var raiding := false

## Where it stands guard, in front of its cave.
var _post := Vector3.ZERO
## Where it is walking to, and the corners of the way there.
var _goal := Vector3.ZERO
var _way := PackedVector3Array()
var _way_i := 0
var _returning := false
var _fire_ready_at := 0.0
var _stroll_at := 0.0
var _dead_for := -1.0
var _was_grown := false
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D

var _model: Node3D
var _walk: Animation
## [track, bone, track type] for each track of the walk clip.
var _tracks: Array[Array] = []
## How far through the walk clip it is (0..1), and how much of the walk
## shows (0 = standing in its stance, 1 = striding).
var _phase := 0.0
var _walk_w := 0.0
## Each arm's aim while it fights, and how much of it shows.
var _arm_aim: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var _arm_w: Array[float] = [0.0, 0.0]
## The claw slashes (right claw, then left), made in Blender
## (tools/balrog_claw_slash.py), their tracks as for the walk, which one is
## playing and how far in (seconds; below 0 when none is).
var _slashes: Array[Animation] = []
var _slash_tracks: Array = []
var _slash_k := 0
var _slash_t := -1.0
## The head thrown back (to spit fire), and falling down dead (0..1).
var _rear := 0.0
var _fall := 0.0


func _init() -> void:
	kind = "balrog"
	hostile = true


func _ready() -> void:
	super._ready()
	add_to_group("balrogs")
	knocked_down.connect(_on_killed)
	_fire_ready_at = Game.now + 5.0
	# Smoke off its back and sparks from the cracks. (They ride on the
	# model, so they shrink and grow with it.)
	_smoke = Game.effects.make_smoke(1.6)
	_smoke.amount = 14
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_smoke.emission_box_extents = Vector3(2.2, 2.5, 1.4)
	add_child(_smoke)
	_smoke.position = Vector3(0, 7.0, -0.5)
	_sparks = Game.effects.make_embers(2.4)
	_sparks.amount = 22
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_sparks.emission_box_extents = Vector3(2.4, 3.2, 1.5)
	add_child(_sparks)
	_sparks.position = Vector3(0, 5.5, 0)


## Puts the balrog at its post in front of `at`.
func settle(at: Node3D) -> void:
	cave = at
	var facing: float = cave.get_meta("facing", 0.0)
	_post = cave.global_position + Vector3(sin(facing), 0.0, cos(facing)) * 13.0
	_goal = _post
	place(_post, facing)


func _species() -> Dictionary:
	return SPEC


func _hungry() -> bool:
	return false


func _top_speed() -> float:
	return Balance.num("balrog_speed")


func _rival() -> Creature:
	var beast := Game.creature
	return beast if is_instance_valid(beast) and not beast.knocked_out else null


func is_threat() -> bool:
	if knocked_out:
		return false
	var village := Game.village
	return raiding or (is_instance_valid(village) and village.founded
		and _flat(global_position, village.center) < PlayerVillage.INTRUDER_RADIUS + 10.0)


func _process(delta: float) -> void:
	super._process(delta)
	if _dead_for >= 0.0:
		_dead_for += delta
		if _dead_for > DEATH_SECONDS:
			Game.effects.spawn_dust(global_position, 6.0 * size)
			Game.effects.spawn_dust(global_position + Vector3.UP * 3.0 * size, 4.0 * size)
			queue_free()
		return
	if not _was_grown and grown() >= 1.0:
		_was_grown = true
		grew_up.emit()


## Every step leaves a little fire behind.
func _on_footfall(pos: Vector3) -> void:
	super._on_footfall(pos)
	if not knocked_out:
		Game.fire.start_fire(pos, 0, 0.35 + 0.9 * size, true)


func _on_killed() -> void:
	_sparks.emitting = false
	# (Nobody brings a balrog back.)
	_dead_for = 0.0
	raiding = false
	remove_from_group("balrogs")
	var village := Game.village
	if is_instance_valid(village) and village.founded:
		village.give("bones", roundf(Balance.num("balrog_bones") * lerpf(0.3, 1.0, size)))
	died.emit()


# --- The model and its animation ---------------------------------------------

func _build() -> void:
	_model = (load(_spec.model) as PackedScene).instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _skel.get_bone_count():
		_bone[_skel.get_bone_name(i)] = i
	# The clip is read directly (no AnimationPlayer), so the code's touches
	# always go on after it, in the same frame.
	var player := _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_walk = player.get_animation("Walking")
	player.queue_free()
	_tracks = _clip_tracks(_walk)
	# The claw slashes come in a file of their own (the same skeleton).
	var slashes := (load(SLASH_MODEL) as PackedScene).instantiate()
	var slash_player := slashes.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in SLASH_CLIPS:
		var anim := slash_player.get_animation(clip)
		_slashes.append(anim)
		_slash_tracks.append(_clip_tracks(anim))
	slashes.free()

	var skin := ShaderMaterial.new()
	skin.shader = Art.shader("giant")
	skin.next_pass = Art.outline(1.0)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var painted := mi.get_active_material(0) as BaseMaterial3D
		if painted != null:
			skin.set_shader_parameter("albedo_tex", painted.albedo_texture)
		mi.material_override = skin
		# (Skeleton units are centimetres.)
		mi.extra_cull_margin = 60.0


## [track, bone, track type] for each of `anim`'s tracks that moves a bone.
func _clip_tracks(anim: Animation) -> Array[Array]:
	var out: Array[Array] = []
	for track in anim.get_track_count():
		var path := anim.track_get_path(track)
		var bone := _skel.find_bone(String(path.get_concatenated_subnames()))
		if bone >= 0:
			out.append([track, bone, anim.track_get_type(track)])
	return out


## Poses the bones from `anim` at `time`, by `weight` over the pose they have.
func _mix_clip(anim: Animation, tracks: Array, time: float, weight: float) -> void:
	for entry in tracks:
		var track: int = entry[0]
		var bone: int = entry[1]
		match entry[2]:
			Animation.TYPE_ROTATION_3D:
				var now := _skel.get_bone_pose_rotation(bone)
				_skel.set_bone_pose_rotation(bone, now.slerp(anim.rotation_track_interpolate(track, time), weight))
			Animation.TYPE_POSITION_3D:
				var at := _skel.get_bone_pose_position(bone)
				_skel.set_bone_pose_position(bone, at.lerp(anim.position_track_interpolate(track, time), weight))


func head_position() -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_bone[HEAD]).origin


## Just under the front of the face (bone units are centimetres).
func _mouth_pos() -> Vector3:
	return _skel.global_transform * (_skel.get_bone_global_pose(_bone[FACE]).origin + Vector3(0.0, -8.0, 0.0))


func _hand_pos(k: int) -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_bone[HANDS[k]]).origin


## Steps come from the walk clip: the clip runs as fast as the balrog
## walks, and a foot comes down where and when the clip puts it down. A
## stomp is the one step taken by itself (see _start_stomp()).
func _update_feet(delta: float) -> void:
	if _stomp_leg >= 0:
		var k := _stomp_leg
		_step_t[k] = minf(1.0, _step_t[k] + delta / STOMP_TIME)
		if _step_t[k] >= 1.0:
			_stepping[k] = false
			_plant[k] = _step_to[k]
			_on_footfall(_plant[k])
			_on_stomp(_plant[k])
		return
	var striding := speed > 0.15 and not knocked_out
	_walk_w = lerpf(_walk_w, 1.0 if striding else 0.0, 1.0 - exp(-(5.0 if striding else 3.0) * delta))
	if _walk_w < 0.02:
		return
	var before := _phase
	# (Coming to a stop, the stride finishes slowly instead of freezing.)
	var pace := maxf(speed, 0.6 * size * (1.0 - _walk_w))
	_phase = fposmod(_phase + delta * pace / (CLIP_SPEED * MODEL_SCALE * size) / _walk.length, 1.0)
	if _walk_w < 0.5:
		return
	for k in 2:
		var at := FOOTFALLS[k]
		if (before < at and _phase >= at) or (_phase < before and (before < at or _phase >= at)):
			var toe := _skel.global_transform * _skel.get_bone_global_pose(_bone[TOES[k]]).origin
			toe.y = Game.terrain.get_height(toe.x, toe.z)
			_plant[k] = toe
			_on_footfall(toe)


func _update_body(delta: float) -> void:
	var blend := 1.0 - exp(-10.0 * delta)
	var pace := clampf(speed / maxf(_top_speed(), 0.1), 0.0, 1.3)
	# The walk clip, mixed with the model's stance by how much it strides.
	var time := _phase * _walk.length
	_skel.reset_bone_poses()
	for entry in _tracks:
		var track: int = entry[0]
		var bone: int = entry[1]
		match entry[2]:
			Animation.TYPE_ROTATION_3D:
				var rest := _skel.get_bone_rest(bone).basis.get_rotation_quaternion()
				_skel.set_bone_pose_rotation(bone, rest.slerp(_walk.rotation_track_interpolate(track, time), _walk_w))
			Animation.TYPE_POSITION_3D:
				var rest_at := _skel.get_bone_rest(bone).origin
				_skel.set_bone_pose_position(bone, rest_at.lerp(_walk.position_track_interpolate(track, time), _walk_w))

	# A claw slash, over the walk or stance (it starts and ends in the
	# stance; easing in and out hides the walk it may cut into).
	if _slash_t >= 0.0:
		var slash := _slashes[_slash_k]
		_slash_t += delta
		if _slash_t >= slash.length or knocked_out:
			_slash_t = -1.0
		else:
			var w := minf(1.0, _slash_t / 0.08) * minf(1.0, (slash.length - _slash_t) / 0.15)
			_mix_clip(slash, _slash_tracks[_slash_k], _slash_t, w)

	# Breathing, a lean into the stride, rearing up to stomp.
	var breath := sin(_time * 1.4)
	var stomp := 0.0
	if _stomp_leg >= 0:
		var t := _step_t[_stomp_leg]
		var drop := smoothstep(0.78, 1.0, t)
		stomp = smoothstep(0.0, 0.5, t) * (1.0 - drop * drop)
	_lean = lerpf(_lean, pace * 0.12 - stomp * 0.2 + (0.08 if _alert else 0.0), blend)
	_turn(SPINE, Vector3.RIGHT, _lean + breath * 0.015)
	_skel.set_bone_pose_scale(_bone[CHEST], Vector3.ONE * (1.0 + breath * 0.01))

	# Head: towards whatever it watches; back to spit fire (and when hit).
	var to := _look_at - global_position
	var want_yaw := clampf(angle_difference(heading, atan2(to.x, to.z)), -0.8, 0.8) if to.length() > 3.0 else 0.0
	_look_yaw = lerpf(_look_yaw, want_yaw + sin(_time * 0.5) * 0.06, 1.0 - exp(-3.0 * delta))
	_rear = lerpf(_rear, -0.4 if _cast_timer > 0.0 else 0.0, 1.0 - exp(-8.0 * delta))
	_turn(NECK, Vector3.UP, _look_yaw * 0.45)
	_turn(HEAD, Vector3.UP, _look_yaw * 0.55)
	_turn(HEAD, Vector3.RIGHT, _rear - _lean * 0.5)

	# Arms: the clips' swing, or aimed while it throws (a slash is all clip).
	for k in 2:
		var aim: Variant = _arm_one[k]
		_arm_w[k] = lerpf(_arm_w[k], 1.0 if aim != null else 0.0, 1.0 - exp(-12.0 * delta))
		if aim != null:
			var a: Vector3 = aim
			_arm_aim[k] = _arm_aim[k].lerp(Vector3(_side(k) * a.x, a.y, a.z).normalized(), 1.0 - exp(-14.0 * delta))
		if _arm_w[k] > 0.01:
			_aim_bone(ARMS[k], FOREARMS[k], _arm_aim[k], _arm_w[k])
			_aim_bone(FOREARMS[k], HANDS[k], _arm_aim[k] + Vector3.UP * 0.25, _arm_w[k] * 0.85)

	# Stomp: the thigh comes up high, the knee bends, then it slams down.
	if _stomp_leg >= 0:
		_turn(THIGHS[_stomp_leg], Vector3.RIGHT, -1.25 * stomp)
		_turn(SHINS[_stomp_leg], Vector3.RIGHT, 1.1 * stomp)

	# Dead: it topples forward onto its face.
	if knocked_out:
		_fall = minf(1.0, _fall + delta * 0.9)
	var down := _fall * _fall
	_model.rotation.x = down * PI * 0.5
	_model.position.y = down * 0.3 * MODEL_SCALE


## Code-made animation has no legs to solve: the clip and _update_body()
## pose them.
func _update_legs() -> void:
	pass


## The model's face is painted: no eyes or mouth to draw.
func _update_face(_delta: float) -> void:
	pass


## Turns `bone_name` by `angle` about `axis` (in the skeleton's space:
## +Z forward, +Y up), on top of the pose it already has.
func _turn(bone_name: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0001:
		return
	var bone: int = _bone[bone_name]
	var pose := _skel.get_bone_global_pose(bone)
	pose.basis = Basis(axis, angle) * pose.basis
	_skel.set_bone_global_pose(bone, pose)


## Turns `bone_name` (by `weight`, 0..1) so it points along `dir` (in the
## skeleton's space), towards the next bone, `child_name`.
func _aim_bone(bone_name: String, child_name: String, dir: Vector3, weight: float) -> void:
	var bone: int = _bone[bone_name]
	var pose := _skel.get_bone_global_pose(bone)
	var along := _skel.get_bone_global_pose(_bone[child_name]).origin - pose.origin
	if along.length_squared() < 0.0001 or dir.length_squared() < 0.0001:
		return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(along.normalized(), dir.normalized()), weight)
	pose.basis = Basis(turn) * pose.basis
	_skel.set_bone_global_pose(bone, pose)


# --- Raids ------------------------------------------------------------------------

## Midnight: march on the village. `route` is a painted goblin path, or
## empty to find its own way.
func start_raid(goal: Vector3, route: PackedVector3Array) -> void:
	if knocked_out:
		return
	raiding = true
	_returning = false
	_set_goal(goal, route)


## Morning: back to the cave.
func end_raid() -> void:
	if not raiding:
		return
	raiding = false
	_returning = true
	_set_goal(_post, PackedVector3Array())


func _set_goal(goal: Vector3, route: PackedVector3Array) -> void:
	_goal = goal
	_way = route if not route.is_empty() else Game.path_grid().find(global_position, goal)
	_way_i = 0


## One more stretch of the way to `_goal`.
func _march() -> void:
	while _way_i < _way.size() and _flat(_way[_way_i], global_position) < 5.0:
		_way_i += 1
	var next := _way[_way_i] if _way_i < _way.size() else _goal
	if _flat(next, global_position) > 3.0 and (not has_target or _flat(target, next) > 1.0):
		auto_move(next)


# --- Fighting ---------------------------------------------------------------------

## True if something at `pos`, `d` metres away, is worth walking over to.
func _worth_chasing(pos: Vector3, d: float) -> bool:
	if raiding:
		return d < RAID_SIGHT
	return _flat(pos, _post) < Balance.num("balrog_guard_radius")


func _update_attacks(delta: float) -> void:
	_action_cooldown = maxf(0.0, _action_cooldown - delta)
	if _action == Action.STRIKE:
		_alert = true
		_update_strike(delta)
		return
	if _action == Action.STOMP:
		_alert = true
		_jaw_want = 0.5
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 0.3
	var reach := REACH * size + 1.0
	# `focus` is in reach of a stomp; `quarry` has to be walked to.
	var focus: Node3D = null
	var focus_d := INF
	var quarry: Node3D = null
	var quarry_d := INF
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if not v.owned or not v.is_alive() or v.state == Villager.State.HELD:
			continue
		var d := _flat(v.global_position, global_position)
		if d < reach:
			if d < focus_d:
				focus_d = d
				focus = v
		elif d < quarry_d and _worth_chasing(v.global_position, d):
			quarry_d = d
			quarry = v
	var rival := _rival()
	if rival != null and not rival.is_flying():
		var d := _flat(rival.global_position, global_position) - 2.0 * rival.size
		if d < reach:
			if d < focus_d:
				focus_d = d
				focus = rival
		elif d < quarry_d and _worth_chasing(rival.global_position, d):
			quarry_d = d
			quarry = rival
	if raiding and focus == null:
		# Nobody to fight: the buildings are next.
		for node in get_tree().get_nodes_in_group("player_buildings"):
			var b := node as Destructible
			if b.destroyed or b is RopeBridge:
				continue
			var d := _flat(b.global_position, global_position) - b.footprint * 0.6
			if d < reach:
				if d < focus_d:
					focus_d = d
					focus = b
			elif quarry == null or (quarry is Destructible and d < quarry_d):
				if d < 70.0:
					quarry_d = d
					quarry = b
	_alert = focus != null or quarry != null
	_jaw_want = 0.3 if _alert else 0.0
	if _alert:
		_try_fireball()
	if focus == null:
		_turning = false
		if Game.now < snared_until:
			return
		if quarry != null:
			_returning = false
			if not has_target or _flat(target, quarry.global_position) > 1.5:
				auto_move(quarry.global_position)
		elif raiding:
			_march()
		elif _flat(global_position, _post) > 9.0:
			if not _returning:
				_returning = true
				_set_goal(_post, PackedVector3Array())
			_march()
		else:
			_returning = false
			if not has_target and Game.now > _stroll_at:
				# A turn about its post.
				_stroll_at = Game.now + randf_range(10.0, 22.0)
				var a := randf() * TAU
				var p := _post + Vector3(sin(a), 0.0, cos(a)) * randf_range(2.0, 7.0)
				if Game.terrain.is_inside(p.x, p.z) and Game.terrain.is_dry(p.x, p.z):
					auto_move(p)
		return
	has_target = false
	_auto = false
	_action_point = focus.global_position
	_look_at = _action_point
	var to := _action_point - global_position
	to.y = 0.0
	_turning = _action_cooldown < 0.4
	var facing := absf(angle_difference(heading, atan2(to.x, to.z))) < 0.55
	if not facing or _action_cooldown > 0.0 or _stepping[0] or _stepping[1] or speed > 0.6:
		return
	if focus == rival:
		_start_strike()
	else:
		_start_stomp(global_position + to.normalized() * minf(to.length(), STOMP_STRIDE * size))


## A claw slash instead of a punch: one claw and then the other.
func _start_strike() -> void:
	super._start_strike()
	_slash_k = _punch_hand
	_slash_t = 0.0


## The hit and its timing are a punch's; the arms are the clip's.
func _update_strike(delta: float) -> void:
	super._update_strike(delta)
	_arm_one = [null, null]


## Spits a fireball at the best knot of enemies in sight, if it is big
## enough yet and has its breath back.
func _try_fireball() -> void:
	if size < Balance.num("balrog_fireball_size") or Game.now < _fire_ready_at:
		return
	var aim: Variant = _fire_target()
	if aim == null:
		return
	_fire_ready_at = Game.now + Balance.num("balrog_fireball_seconds")
	watch(aim)
	var fb := Fireball.new()
	fb.hostile = true
	fb.power = Balance.num("balrog_fireball_power")
	Game.world_root.add_child(fb)
	fb.launch(mouth_position(), aim)


## Where a fireball would do most harm: villagers count one each, a
## building two, the player's creature four; goblins in the blast count
## against it. Null if nothing is worth it.
func _fire_target() -> Variant:
	var tree := get_tree()
	var radius := Fireball.BLAST_RADIUS * 0.7
	var people: Array[Vector3] = []
	for node in tree.get_nodes_in_group("villagers"):
		var v := node as Villager
		if v.owned and v.is_alive():
			people.append(v.global_position)
	var spots: Array[Vector3] = people.duplicate()
	var rival := _rival()
	if rival != null and not rival.is_flying():
		spots.append(rival.global_position)
	var buildings: Array[Destructible] = []
	if raiding:
		for node in tree.get_nodes_in_group("player_buildings"):
			var b := node as Destructible
			if not b.destroyed and not b is RopeBridge:
				buildings.append(b)
				spots.append(b.global_position)
	var goblins := tree.get_nodes_in_group("goblins")
	var guard := Balance.num("balrog_guard_radius")
	var best: Variant = null
	var best_score := 1.5
	for p in spots:
		var d := _flat(p, global_position)
		if d < 12.0 + 4.0 * size or d > 60.0:
			continue
		if not raiding and _flat(p, _post) > guard + 15.0:
			continue
		var score := 0.0
		for q in people:
			if _flat(p, q) < radius:
				score += 1.0
		if rival != null and not rival.is_flying() and _flat(p, rival.global_position) < radius + 2.0:
			score += 4.0
		for b in buildings:
			if _flat(p, b.global_position) < radius + b.footprint * 0.5:
				score += 2.0
		for node in goblins:
			if _flat(p, (node as Node3D).global_position) < radius:
				score -= 2.0
		if score > best_score:
			best_score = score
			best = p + Vector3.UP * 0.5
	return best
