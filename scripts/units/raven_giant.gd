class_name RavenGiant
extends Creature
## The raven (0.61): the owner's two Meshy ravens, one standing to walk on
## the ground (assets/creature/raven_walk.glb) and one flying level
## (raven_fly.glb), rigged with the same skeleton and animated in Blender
## by tools/raven_new_rig.py and tools/raven_new_anim.py. It swaps from one
## model to the other as it takes off and lands. Everything it does is the
## Creature's (walking, flying, fighting, carrying); only the body is
## posed differently, by the models' own clips instead of code:
##
##   Walk         played as fast as it really walks (so its feet do not
##                slide), and blended into its stance as it stops; its
##                footfalls come where the clip puts its feet down
##   Fly          the wingbeat, all the time it is in the air
##   AttackLeft,  its strike (Action.STRIKE): the left claw, then the right
##   AttackRight
##   Throw        scooping goblins up and hurling them (Action.GRAB); to
##                eat them it lifts them the same way and holds them up
##   StompLeft,   its stomp: the knee comes up and the foot slams down
##   StompRight
##
## Each joint bends only the way it can (the clips are made inside the
## rig's limits). Code adds only a turn of the head to what it watches and
## its fall when it dies.

const WALK_MODEL := "res://assets/creature/raven_walk.glb"
const FLY_MODEL := "res://assets/creature/raven_fly.glb"
## The models are about 2 m tall; this makes it as big as the old raven
## (full grown).
const MODEL_SCALE := 8.0
## Metres its feet carry it in one second of the walk clip (at MODEL_SCALE
## 1): the clip is played this much faster or slower to match its speed.
const CLIP_SPEED := 0.475
## Where in the walk clip (a share of its length) each foot comes down:
## leg 0 (the "_l" bones, at -X) and leg 1 (the "_r" bones).
const FOOTFALLS: Array[float] = [0.5, 0.0]
const FEET: Array[String] = ["foot_l", "foot_r"]
## The claw clips, by hand (0: "_l", 1: "_r"), and the stomps by leg.
const CLAW_CLIPS: Array[String] = ["AttackLeft", "AttackRight"]
const STOMP_CLIPS: Array[String] = ["StompLeft", "StompRight"]
## When the foot lands in a stomp clip (seconds in), and in the throw clip
## when the goblins are in hand, when they are let go, and when they are
## held up high (for eating). (tools/raven_new_anim.py's STOMP_IMPACT,
## THROW_GRAB, THROW_RELEASE.)
const STOMP_LANDS := 0.8
const THROW_GRABS := 0.6
const THROW_LETS_GO := 1.62
const THROW_HOLDS := 1.02
## (Creature._update_grab()'s moments, which the throw clip is timed to.)
const GRAB_GRABS := 0.7
const GRAB_LETS_GO := 1.95
## How long it lies dead before it is still.
const FALL_SECONDS := 1.2

var _walk_model: Node3D
var _fly_model: Node3D
var _walk_skel: Skeleton3D
var _fly_skel: Skeleton3D
var _walk_bone := {}
var _fly_bone := {}
var _clips := {}
## [track, bone, track type] for each clip's tracks, by clip name.
var _tracks := {}
## How far through the walk clip it is (0..1), and how much of the walk
## shows (0 = standing, 1 = striding).
var _phase := 0.0
var _walk_w := 0.0
var _fly_t := 0.0
## Clips playing over the walk or stance: each [name, time, weight, fading,
## held]. A new one fades in over the last.
var _playing: Array[Array] = []
var _fall := 0.0
var _shown_flying := false


func _init() -> void:
	kind = "raven"


func _build() -> void:
	_walk_model = _load_model(WALK_MODEL)
	_fly_model = _load_model(FLY_MODEL)
	_walk_skel = _walk_model.find_children("*", "Skeleton3D", true, false)[0]
	_fly_skel = _fly_model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _walk_skel.get_bone_count():
		_walk_bone[_walk_skel.get_bone_name(i)] = i
	for i in _fly_skel.get_bone_count():
		_fly_bone[_fly_skel.get_bone_name(i)] = i
	_fly_model.visible = false
	_skel = _walk_skel
	_bone = _walk_bone
	for i in _walk_skel.get_bone_count():
		_rest[_walk_skel.get_bone_name(i)] = _walk_skel.get_bone_global_rest(i).origin
	_foot_spread = absf(_rest["foot_r"].x) * MODEL_SCALE
	# The clips are read directly (no AnimationPlayer), so the code's touches
	# always go on after them, in the same frame.
	for pair: Array in [[_walk_model, _walk_skel], [_fly_model, _fly_skel]]:
		var player := (pair[0] as Node3D).find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for clip_name in player.get_animation_list():
			var anim := player.get_animation(clip_name)
			_clips[String(clip_name)] = anim
			_tracks[String(clip_name)] = _clip_tracks(anim, pair[1])
		player.queue_free()


func _load_model(path: String) -> Node3D:
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	# The model's own material, as Meshy made it: no cel shading, no outline.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).extra_cull_margin = 6.0
	return model


## [track, bone, track type] for each of `anim`'s tracks that moves a bone of `skel`.
static func _clip_tracks(anim: Animation, skel: Skeleton3D) -> Array[Array]:
	var out: Array[Array] = []
	for track in anim.get_track_count():
		var bone := skel.find_bone(String(anim.track_get_path(track).get_concatenated_subnames()))
		if bone >= 0:
			out.append([track, bone, anim.track_get_type(track)])
	return out


## Poses `skel`'s bones from clip `clip_name` at `time`, by `weight` over
## the pose they have.
func _mix_clip(skel: Skeleton3D, clip_name: String, time: float, weight: float) -> void:
	var anim: Animation = _clips[clip_name]
	for entry: Array in _tracks[clip_name]:
		var track: int = entry[0]
		var bone: int = entry[1]
		match entry[2]:
			Animation.TYPE_ROTATION_3D:
				var now := skel.get_bone_pose_rotation(bone)
				skel.set_bone_pose_rotation(bone, now.slerp(anim.rotation_track_interpolate(track, time), weight))
			Animation.TYPE_POSITION_3D:
				var at := skel.get_bone_pose_position(bone)
				skel.set_bone_pose_position(bone, at.lerp(anim.position_track_interpolate(track, time), weight))


## Starts clip `clip_name` over whatever is playing.
func _play(clip_name: String) -> void:
	if not _clips.has(clip_name):
		return
	for p in _playing:
		p[3] = true
	_playing.append([clip_name, 0.0, 0.0, false, false])


## The clip playing now (the last started), or an empty array.
func _current() -> Array:
	return _playing[-1] if not _playing.is_empty() and not _playing[-1][3] else []


# --- The body's place ---------------------------------------------------------

func head_position() -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_bone["head"]).origin


## Under the beak, near its base.
func _mouth_pos() -> Vector3:
	var pose := _skel.get_bone_global_pose(_bone["head"])
	return _skel.global_transform * (pose.origin + pose.basis.y.normalized() * 0.3 + Vector3(0.0, -0.07, 0.0))


func _hand_pos(k: int) -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_bone["hand_l" if k == 0 else "hand_r"]).origin


# --- Actions: the Creature's, with the clips to show them -------------------------

func _start_strike() -> void:
	super._start_strike()
	_play(CLAW_CLIPS[_punch_hand])


func _start_stomp(point: Vector3) -> void:
	super._start_stomp(point)
	_play(STOMP_CLIPS[_stomp_leg])


func _start_grab(near: Array[Villager]) -> void:
	super._start_grab(near)
	if _action == Action.GRAB:
		_play("Throw")


func _take_off() -> void:
	super._take_off()
	_playing.clear()
	_show_flying(true)


func _land() -> void:
	super._land()
	_show_flying(false)


## Shows the flying model (or the walking one) in the other's place.
func _show_flying(up: bool) -> void:
	if up == _shown_flying:
		return
	_shown_flying = up
	_walk_model.visible = not up
	_fly_model.visible = up
	_skel = _fly_skel if up else _walk_skel
	_bone = _fly_bone if up else _walk_bone
	_fly_t = 0.0


# --- Animation ----------------------------------------------------------------

## Steps come from the walk clip: it runs as fast as the raven walks, and a
## foot comes down where and when the clip puts it down. A stomp is the one
## step taken by itself, landing when its clip's foot does.
func _update_feet(delta: float) -> void:
	if flying:
		var fwd := Vector3(sin(heading), 0.0, cos(heading))
		var right := Vector3(cos(heading), 0.0, -sin(heading))
		for k in 2:
			_stepping[k] = false
			_plant[k] = _foot_home(_side(k), fwd, right)
		_walk_w = 0.0
		return
	if _stomp_leg >= 0:
		var k := _stomp_leg
		_step_t[k] = minf(1.0, _step_t[k] + delta / STOMP_LANDS)
		if _step_t[k] >= 1.0:
			_stepping[k] = false
			_plant[k] = _step_to[k]
			_on_footfall(_plant[k])
			_on_stomp(_plant[k])
		_walk_w = move_toward(_walk_w, 0.0, delta * 4.0)
		return
	var striding := speed > 0.15 and not knocked_out and _action == Action.NONE
	_walk_w = lerpf(_walk_w, 1.0 if striding else 0.0, 1.0 - exp(-(5.0 if striding else 3.0) * delta))
	if _walk_w < 0.02:
		return
	var walk: Animation = _clips["Walk"]
	var before := _phase
	# (Coming to a stop, the stride finishes slowly instead of freezing.)
	var pace := maxf(speed, 0.6 * size * (1.0 - _walk_w))
	_phase = fposmod(_phase + delta * pace / (CLIP_SPEED * MODEL_SCALE * size) / walk.length, 1.0)
	if _walk_w < 0.5:
		return
	for k in 2:
		var at := FOOTFALLS[k]
		if (before < at and _phase >= at) or (_phase < before and (before < at or _phase >= at)):
			var foot := _skel.global_transform * _skel.get_bone_global_pose(_bone[FEET[k]]).origin
			foot.y = Game.terrain.get_height(foot.x, foot.z)
			_plant[k] = foot
			_on_footfall(foot)


func _update_body(delta: float) -> void:
	if flying != _shown_flying:
		_show_flying(flying)
	if _shown_flying:
		# The wingbeat, on and on.
		var fly: Animation = _clips["Fly"]
		_fly_t = fposmod(_fly_t + delta, fly.length)
		_fly_skel.reset_bone_poses()
		_mix_clip(_fly_skel, "Fly", _fly_t, 1.0)
		_update_fall(delta)
		return

	# The walk clip, mixed with its stance by how much it strides.
	var walk: Animation = _clips["Walk"]
	var time := _phase * walk.length
	_walk_skel.reset_bone_poses()
	if _walk_w > 0.001:
		_mix_clip(_walk_skel, "Walk", time, _walk_w)

	# The action clips over it. The throw follows the grab's own clock;
	# the rest play at their own pace.
	var now := _current()
	if not now.is_empty() and now[0] == "Throw":
		if _action == Action.GRAB:
			now[1] = _throw_time(_action_t)
			now[4] = _eating
		elif now[4]:
			# (Done eating: it lowers its hand.)
			now[3] = true
	for p in _playing:
		var anim: Animation = _clips[p[0]]
		if not (p[0] == "Throw" and _action == Action.GRAB and is_same(p, now)):
			p[1] += delta
		if p[1] >= anim.length or knocked_out:
			p[3] = true
		p[2] = move_toward(p[2], 0.0 if p[3] else 1.0, delta / (0.3 if p[3] else 0.12))
	_playing = _playing.filter(func(p: Array) -> bool: return not (p[3] and p[2] <= 0.0))
	for p in _playing:
		_mix_clip(_walk_skel, p[0], minf(p[1], (_clips[p[0]] as Animation).length), p[2])

	# The head turns a little towards whatever it watches.
	var to := _look_at - global_position
	var want_yaw := clampf(angle_difference(heading, atan2(to.x, to.z)), -0.7, 0.7) if to.length() > 3.0 else 0.0
	_look_yaw = lerpf(_look_yaw, want_yaw, 1.0 - exp(-3.0 * delta))
	_turn(_walk_skel, _walk_bone["neck2"], _look_yaw * 0.4)
	_turn(_walk_skel, _walk_bone["head"], _look_yaw * 0.6)
	_update_fall(delta)


## Throw clip time for the grab's own time `t` (see Creature._update_grab()):
## the goblins are in hand, and let go, when the clip says. Eating, it
## lifts them and holds them up.
func _throw_time(t: float) -> float:
	var clip: float
	if t < GRAB_GRABS:
		clip = t / GRAB_GRABS * THROW_GRABS
	elif t < GRAB_LETS_GO:
		clip = lerpf(THROW_GRABS, THROW_LETS_GO, (t - GRAB_GRABS) / (GRAB_LETS_GO - GRAB_GRABS))
	else:
		clip = THROW_LETS_GO + (t - GRAB_LETS_GO)
	return minf(clip, THROW_HOLDS) if _eating else clip


## Turns `bone` about the skeleton's up axis by `angle`, on top of its pose.
func _turn(skel: Skeleton3D, bone: int, angle: float) -> void:
	if absf(angle) < 0.0001:
		return
	var pose := skel.get_bone_global_pose(bone)
	pose.basis = Basis(Vector3.UP, angle) * pose.basis
	skel.set_bone_global_pose(bone, pose)


## Dead, it topples onto its side (and is put right when it is brought back).
func _update_fall(delta: float) -> void:
	_fall = move_toward(_fall, 1.0 if knocked_out else 0.0, delta / FALL_SECONDS)
	var down := smoothstep(0.0, 1.0, _fall)
	var model := _fly_model if _shown_flying else _walk_model
	model.rotation.z = down * PI * 0.45
	model.position.y = down * 0.35 * MODEL_SCALE


## The clips pose the legs.
func _update_legs() -> void:
	pass


## The face is painted: no eyes or mouth to draw.
func _update_face(_delta: float) -> void:
	pass
