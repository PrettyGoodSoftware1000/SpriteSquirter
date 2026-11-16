class_name Creature
extends Node3D
## The giant creature. There are three to choose from (set `kind` before
## adding it to the tree): a gloomy tortoise, a nervous squirrel that is
## 30% faster but has half the tortoise's health, and a raven that flies.
## See SPECIES. (The goblins' Balrog is a Creature too: see balrog.gd.)
##
## A creature starts at START_SIZE of its full size and grows for
## Game.settings.creature_grow_minutes (it stops growing while the village
## has no food). Its speed, reach, strength and health grow with it. It
## eats Game.settings.creature_food a minute when full grown, less while
## small. Goblins can hurt it: at no health it is knocked out for
## a while, then gets up with half its health. Health, stomp damage and the
## knock-out time come from balancing.txt (see Balance).
##
## Each model (assets/creature/*.glb) is a single skinned mesh on a
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
## somewhere. Its ordinary footsteps squash goblins and strangers and
## flatten trees and goblin huts, but never harm the player's own villagers
## or buildings. With goblins about it is "alert": it
## walks ALERT_SPEED times as fast, scowls, bares its mouth and its eyes
## dart around.
##
## Giants fight each other with their fists (Action.STRIKE): the player's
## creature and the Balrog are each other's `_rival()`.
##
## The raven flies (see _should_fly): on any journey longer than Balance
## "raven_fly_distance", over ground that climbs steeply, and to get out of
## a fight. In the air nothing on the ground can reach it and it treads on
## nothing. Hurt below "raven_flee_health" it flees a fight by itself, and
## keeps out of trouble until it has healed to "raven_return_health".
##
## The face is drawn on top of the model: eyeballs, pupils that look about,
## lids that blink and slant with its mood, and an inked mouth line that
## opens into a dark mouth with the jaw.

signal footfall(pos: Vector3)

const START_SIZE := 0.15
## What differs between the creatures. Positions are in the head bone's
## space. Pairs are [calm, alert]: how high the lids sit over the eyes, how
## they slant, how big the pupils are, how deep the mouth turns down.
const SPECIES := {
	"tortoise": {
		"name": "Tortoise", "model": "res://assets/creature/creature.glb", "speed": 3.6,
		"nervous": 0.0,
		"eye": Vector3(0.74, 0.5, 1.22), "eye_size": 0.34, "eye_color": Color(0.96, 0.94, 0.84),
		"lid_color": Color(0.36, 0.38, 0.2), "lid_y": [0.2, 0.14], "lid_tilt": [-0.38, 0.5], "pupil": [1.0, 0.72],
		# Mouth: half width, height, how far forward, how far its corners curve back.
		"mouth": [0.85, -0.08, 2.1, 0.5], "frown": [0.3, 0.2],
		"arm": Vector3(0.3, -1.0, 0.12), "elbow": -0.25,
	},
	"squirrel": {
		"name": "Squirrel", "model": "res://assets/creature/squirrel.glb", "speed": 3.6 * 1.3,
		"nervous": 1.0,
		"eye": Vector3(0.66, 0.85, 1.27), "eye_size": 0.42, "eye_color": Color(1.0, 0.98, 0.8),
		"lid_color": Color(0.8, 0.36, 0.13), "lid_y": [0.5, 0.62], "lid_tilt": [-0.3, -0.5], "pupil": [0.62, 0.42],
		"mouth": [0.55, -0.02, 1.8, 0.2], "frown": [0.1, 0.18],
		# Upper arms hang a little forward; `fore` points the forearms up
		# and in, so the paws are held in front of the chest.
		"arm": Vector3(0.25, -0.85, 0.4), "elbow": -0.4, "fore": Vector3(-0.35, 0.5, 0.8),
	},
	"raven": {
		"name": "Raven", "model": "res://assets/creature/raven.glb", "speed": 3.6,
		"nervous": 0.25, "flies": true,
		# Blank eyes that glow, and a beak in place of a drawn mouth.
		"eye": Vector3(0.63, 0.62, 1.18), "eye_size": 0.3, "eye_color": Color(0.82, 0.9, 1.0), "eye_glow": 1.5,
		"lid_color": Color(0.105, 0.12, 0.21), "lid_y": [0.34, 0.2], "lid_tilt": [0.2, 0.55], "pupil": [1.0, 1.0],
		"jaw_rest": -0.1,
		"arm": Vector3(0.3, -1.0, 0.12), "elbow": -0.25,
		# The wing's flat side faces this way (on the right; mirrored on
		# the left). To fly, the wing swings out by `wing_open` and the
		# long feathers at its tip by `tip_open`.
		"wing_normal": Vector3(0.5, 0.0, 0.866), "wing_open": 0.32, "tip_open": 0.4,
	},
}

signal knocked_down
signal got_up
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
const HUNT_RANGE := 150.0
const ALERT_SPEED := 1.2
## How much faster it turns to keep enemies in front of it.
const COMBAT_TURN := 1.3
## A blow with the fists at another giant: how long it takes, and when in
## that time it lands.
const STRIKE_TIME := 1.1
const STRIKE_LANDS := 0.6
## The raven never bothers to fly anywhere nearer than this.
const SHORT_HOP := 8.0
## Arms held out in front, for carrying a tree or a boulder.
const CARRY_POSE := Vector3(0.25, 0.15, 1.0)

enum Action { NONE, STOMP, GRAB, STRIKE }

@export var max_speed := 3.6
@export var turn_speed := 1.2
@export var step_distance := 1.6
@export var step_time := 0.7
@export var step_height := 0.9

## "tortoise" or "squirrel". Set before adding to the tree.
var kind := "tortoise"
## 1 is full grown.
var size := START_SIZE
## Seconds of growing so far.
var age := 0.0
var max_hp := 0.0
var hp := 0.0
var knocked_out := false
## True for the goblins' giant, which fights the village and not for it.
var hostile := false
## In the air (the raven), from take-off until its feet are down again.
var flying := false
## Hurt and keeping away from enemies until it has healed (the raven).
var fleeing := false
## Knowledge, likes and dislikes, and what it does when left alone.
var mind: CreatureMind
## A tree, boulder or sheaf the creature is carrying in its arms.
var carrying: Node3D

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
var _spec := {}
var _ko_timer := 0.0
var _hurt_timer := 0.0
## The nervous creature's head jerks and glances about.
var _twitch := 0.0
var _twitch_timer := 0.0
var _glance_timer := 0.0
var _fore_blend := 1.0
var _say_free_at := 0.0
## Metres above the ground, and 0..1 how far into its flying pose it is.
var _alt := 0.0
var _fly := 0.0
var _flap := 0.0
## How far the journey was when it began.
var _flight_length := 0.0
var _flee_until := 0.0
var _flee_again_at := 0.0
var _struck := false


func _ready() -> void:
	_spec = _species()
	max_speed = _spec.speed
	_arm_pose = _spec.arm
	_arm_want = _spec.arm
	_build()
	_grow(0.0)
	mind = CreatureMind.new()
	mind.name = "Mind"
	add_child(mind)


func species_name() -> String:
	return _spec.name


## Everything that sets this kind of creature apart (see SPECIES).
func _species() -> Dictionary:
	return SPECIES[kind]


## A creature with no food to eat stops growing and healing.
func _hungry() -> bool:
	var village := Game.village
	return is_instance_valid(village) and village.founded and village.amount("food") <= 0


## Walking speed at its present size, before slopes and so on.
func _top_speed() -> float:
	return max_speed * lerpf(0.5, 1.0, size) * (ALERT_SPEED if _alert else 1.0)


## The other giant: the Balrog for the player's creature, and the other
## way about. Null if there is none to fight just now.
func _rival() -> Creature:
	for node in get_tree().get_nodes_in_group("balrogs"):
		var b := node as Creature
		if not b.knocked_out:
			return b
	return null


## True if this giant is out to hurt the village right now (the Balrog).
func is_threat() -> bool:
	return false


## True while it is too high for anything on the ground to reach.
func is_flying() -> bool:
	return flying and _alt > 1.5 * size


## 0..1: how far it has grown from START_SIZE to full size.
func grown() -> float:
	return inverse_lerp(START_SIZE, 1.0, size)


## Grows, and heals slowly when nothing has hurt it for a while. A creature
## with no food to eat does neither.
func _grow(delta: float) -> void:
	var hungry := _hungry()
	if not hungry:
		age += delta
	var minutes: float = maxf(Game.settings.creature_grow_minutes, 0.05)
	var t := clampf(age / (minutes * 60.0), 0.0, 1.0)
	size = lerpf(START_SIZE, 1.0, t)
	scale = Vector3.ONE * size
	var new_max: float = Balance.num(kind + "_health") * lerpf(0.3, 1.0, t)
	hp += new_max - max_hp
	max_hp = new_max
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	if knocked_out:
		_ko_timer -= delta
		if _ko_timer <= 0.0:
			knocked_out = false
			hp = max_hp * 0.5
			_crouch = 0.0
			got_up.emit()
	elif _hurt_timer <= 0.0 and not hungry:
		hp = minf(max_hp, hp + max_hp * 0.01 * delta)


## Hurt by a goblin or an ogre.
func take_hit(amount: float, _from: Node3D) -> void:
	if knocked_out:
		return
	hp -= amount
	_hurt_timer = 6.0
	_cast_timer = maxf(_cast_timer, 0.25)
	if hp > 0.0:
		if _spec.get("flies", false) and not fleeing and hp < max_hp * Balance.num("raven_flee_health"):
			_flee()
		return
	hp = 0.0
	knocked_out = true
	fleeing = false
	_ko_timer = Balance.num("creature_knockout_seconds")
	_cancel_action()
	has_target = false
	_auto = false
	_turning = false
	_alert = false
	_crouch = 1.3
	_jaw_want = 0.0
	Game.effects.spawn_dust(global_position, 3.0 * size)
	knocked_down.emit()


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
	mind.home = global_position
	_update_body(1.0)
	_update_legs()


## The player sends the creature somewhere. It will stay around there.
func move_to(pos: Vector3) -> void:
	target = pos
	has_target = true
	_auto = false
	_look_at = pos
	mind.player_moved(pos)
	_flight_length = _flat(pos, global_position)
	if _should_fly(pos, true):
		_take_off()


## The creature goes somewhere of its own accord. (Chasing enemies and the
## player's orders come first.)
func auto_move(pos: Vector3) -> void:
	target = pos
	has_target = true
	_auto = true
	_look_at = pos
	_flight_length = _flat(pos, global_position)
	if _should_fly(pos):
		_take_off()


# --- Flying (the raven) -------------------------------------------------------

## True if the raven would rather fly to `pos` than walk: it is a long
## way, the ground climbs steeply on the way, or it is running from a
## fight (by itself, or because the player has `ordered` it away).
func _should_fly(pos: Vector3, ordered := false) -> bool:
	if flying:
		return false
	if not _spec.get("flies", false) or knocked_out or Game.now < snared_until:
		return false
	var d := _flat(pos, global_position)
	if d > Balance.num("raven_fly_distance"):
		return true
	if d < SHORT_HOP:
		return false
	if fleeing or (ordered and (_alert or _action != Action.NONE)):
		return true
	# Look for a climb on the way.
	var terrain := Game.terrain
	var steps := ceili(d / 3.0)
	var last := terrain.get_height(global_position.x, global_position.z)
	for k in range(1, steps + 1):
		var p := global_position.lerp(pos, k / float(steps))
		var h := terrain.get_height(p.x, p.z)
		if (h - last) / (d / steps) > Balance.num("slope_slow_from"):
			return true
		last = h
	return false


func _take_off() -> void:
	_cancel_action()
	flying = true
	_turning = false
	_alert = false
	_jaw_want = 0.0
	for k in 2:
		_stepping[k] = false
	Game.effects.spawn_dust(global_position, 2.0 * size)


func _land() -> void:
	flying = false
	_alt = 0.0
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	for k in 2:
		_plant[k] = _foot_home(_side(k), fwd, right)
		_stepping[k] = false
	Game.effects.spawn_dust(global_position, 2.0 * size)
	_scan_timer = 0.0


## Runs from the fight: flies to the safest spot it can find and keeps
## away from enemies until it has healed (or a minute has gone by).
func _flee() -> void:
	fleeing = true
	_flee_until = Game.now + 60.0
	_flee_again_at = Game.now + 4.0
	var enemies: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("goblins"):
		enemies.append((node as Node3D).global_position)
	var rival := _rival()
	if rival != null:
		enemies.append(rival.global_position)
	var terrain := Game.terrain
	var best := global_position
	var best_score := -INF
	for reach: float in [70.0, 50.0, 30.0]:
		for k in 12:
			var a := k / 12.0 * TAU
			var p := global_position + Vector3(sin(a), 0.0, cos(a)) * reach
			if not terrain.is_inside(p.x, p.z) or not terrain.is_dry(p.x, p.z):
				continue
			var score := 80.0
			for e in enemies:
				score = minf(score, _flat(e, p))
			# Of two safe places, the one nearer home.
			score -= 0.1 * _flat(p, mind.home)
			if score > best_score:
				best_score = score
				best = p
	say("The %s flees!" % species_name().to_lower(), Color(1.0, 0.6, 0.4))
	target = best
	has_target = true
	_auto = true
	_look_at = best
	_flight_length = _flat(best, global_position)
	if not flying and Game.now >= snared_until and _flat(best, global_position) > 2.0:
		_take_off()


## In the air: climbs to its cruising height (and over any hill ahead),
## flies to the target and comes down on it.
func _update_flight(delta: float) -> void:
	var terrain := Game.terrain
	var cruise := Balance.num("raven_fly_height") * lerpf(0.4, 1.0, size)
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	var desired_speed := 0.0
	# It starts down a little way short of the target (half way, on a short hop).
	var landing := knocked_out or not has_target or dist < maxf(minf(cruise * 1.3, _flight_length * 0.5), 3.0)
	if has_target and not knocked_out:
		if dist < 0.8:
			has_target = false
			_auto = false
		else:
			var want := atan2(to.x, to.z)
			heading = rotate_toward(heading, want, turn_speed * 2.2 * delta)
			var facing := cos(angle_difference(heading, want))
			var top := max_speed * lerpf(0.5, 1.0, size) * Balance.num("raven_fly_speed")
			# Slow until it is off the ground, and again as it comes in.
			desired_speed = top * clampf(facing, 0.15, 1.0) * clampf(dist / (cruise * 1.5 + 2.0), 0.2, 1.0) * clampf(_alt / (cruise * 0.4) + 0.25, 0.25, 1.0)
	speed = move_toward(speed, desired_speed, 7.0 * delta)
	rotation.y = heading
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var p := global_position + fwd * speed * delta
	if not terrain.is_inside(p.x, p.z):
		p = global_position
		has_target = false
	var ground := terrain.get_height(p.x, p.z)
	var want_alt := 0.0
	if not landing:
		var ahead := ground
		for k: float in [1.0, 2.0, 3.0]:
			var q := p + fwd * speed * k * 0.7
			ahead = maxf(ahead, terrain.get_height(q.x, q.z))
		want_alt = cruise + ahead - ground
	_alt = lerpf(_alt, want_alt, 1.0 - exp(-(4.0 if knocked_out else 1.8) * delta))
	_alt = move_toward(_alt, want_alt, cruise * 0.25 * delta)
	_ground_y = lerpf(_ground_y, ground, 1.0 - exp(-8.0 * delta))
	p.y = _ground_y + _alt
	global_position = p
	if landing and _alt < 0.12 * size + 0.03:
		_land()


func is_auto() -> bool:
	return _auto


## True while there are enemies to deal with.
func is_fighting() -> bool:
	return _alert or _action != Action.NONE


## Drops whatever attack is under way.
func _cancel_action() -> void:
	if _action == Action.GRAB:
		_end_grab()
	_action = Action.NONE
	_stomp_leg = -1
	_crouch = 0.0
	_arm_want = _spec.arm


## Takes `node` (already somewhere in the world) into its arms.
func carry(node: Node3D) -> void:
	drop_load()
	carrying = node


func drop_load() -> void:
	if is_instance_valid(carrying):
		carrying.queue_free()
	carrying = null


func head_position() -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_bone["head"]).origin


func mouth_position() -> Vector3:
	return _mouth_pos()


## Floats a line of text up from the creature's head. Lines that come
## close together wait their turn, so they can be read.
func say(text: String, color := Color.WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 34
	label.outline_size = 10
	label.modulate = color
	label.visible = false
	Game.effects.add_child(label)
	var wait := maxf(0.0, _say_free_at - Game.now)
	_say_free_at = Game.now + wait + 1.3
	var rise := 2.5 + 4.0 * size
	var tw := label.create_tween()
	tw.tween_interval(wait + 0.01)
	tw.tween_callback(func() -> void:
		label.global_position = head_position() + Vector3.UP * (3.4 * size + 0.6)
		label.visible = true)
	tw.tween_property(label, "position:y", rise, 5.0).as_relative()
	tw.parallel().tween_property(label, "modulate:a", 0.0, 1.5).set_delay(3.5)
	tw.parallel().tween_property(label, "outline_modulate:a", 0.0, 1.5).set_delay(3.5)
	tw.tween_callback(label.queue_free)


## Makes the creature look at something startling (such as a fireball
## landing) and gasp.
func watch(pos: Vector3) -> void:
	_look_at = pos
	_cast_timer = 0.9


func _process(delta: float) -> void:
	_time += delta
	_cast_timer = maxf(0.0, _cast_timer - delta)
	_grow(delta)
	if not knocked_out and not flying:
		_update_attacks(delta)
	if flying:
		_update_flight(delta)
	else:
		_update_locomotion(delta)
	_update_feet(delta)
	_update_body(delta)
	_update_legs()
	_update_face(delta)
	if _action == Action.NONE:
		_arm_want = CARRY_POSE if is_instance_valid(carrying) else _spec.arm
	if is_instance_valid(carrying):
		carrying.global_position = (_hand_pos(0) + _hand_pos(1)) * 0.5 + Vector3.UP * 0.4 * size
		carrying.rotation.y = heading


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
			heading = rotate_toward(heading, want, turn_speed * (COMBAT_TURN if _alert else 1.0) * delta)
			var facing := cos(angle_difference(heading, want))
			desired_speed = _top_speed() * clampf(facing, 0.0, 1.0) * clampf(dist / 5.0, 0.25, 1.0)
	if _action != Action.NONE or _turning:
		# Stand still and face the goblins.
		desired_speed = 0.0
		var facing_to := _action_point - global_position
		heading = rotate_toward(heading, atan2(facing_to.x, facing_to.z), turn_speed * 1.6 * COMBAT_TURN * delta)
	if Game.now < snared_until or knocked_out:
		desired_speed = 0.0
		speed = 0.0
	# Uphill is slow going for a creature too.
	var ahead := Vector3(sin(heading), 0.0, cos(heading)) * 2.0 * maxf(size, 0.3)
	var rise := (Game.terrain.get_height(global_position.x + ahead.x, global_position.z + ahead.z)
		- Game.terrain.get_height(global_position.x, global_position.z)) / ahead.length()
	desired_speed *= lerpf(1.0, Balance.num("slope_slowest"), clampf((rise - Balance.num("slope_slow_from")) / 0.6, 0.0, 1.0))
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
	if flying:
		# No steps in the air: the feet wait on the ground below.
		for k in 2:
			_stepping[k] = false
			_plant[k] = homes[k]
		return
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
		var threshold := (step_distance if speed > 0.2 else 0.35) * size
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
	# Small creatures take quicker steps.
	return clampf(step_time * (1.25 - speed / max_speed * 0.45), 0.35, 0.85) * lerpf(0.5, 1.0, size)


func _foot_home(side: float, fwd: Vector3, right: Vector3) -> Vector3:
	var p := global_position + right * side * _foot_spread * size + fwd * speed * 0.25
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
		high.y += 3.2 * size * smoothstep(0.0, 0.5, t) * (1.0 - drop * drop)
		return high
	var pos := _step_from[k].lerp(_step_to[k], smoothstep(0.0, 1.0, t))
	var travel := _step_from[k].distance_to(_step_to[k])
	pos.y += sin(t * PI) * step_height * size * clampf(travel / (2.0 * size), 0.3, 1.0)
	return pos


## -1 for leg 0 (the "l" bones, at -X), +1 for leg 1 (the "r" bones).
func _side(k: int) -> float:
	return -1.0 if k == 0 else 1.0


func _on_footfall(pos: Vector3) -> void:
	Game.effects.spawn_dust(pos, 1.4 * size)
	Game.shake(0.35 * size, pos)
	for node in get_tree().get_nodes_in_group("destructibles"):
		var d := node as Destructible
		var flat := Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length()
		# A small creature is too light to flatten buildings and trees, and
		# a big one treads carefully round its own village (it goes in and
		# out by itself now, fetching things).
		# (The Balrog knocks buildings down on purpose, not by walking.)
		if d.is_in_group("player_buildings") or (hostile and d.is_building):
			continue
		if size > 0.45 and flat < d.footprint * 0.7 + 1.4 * size:
			d.stomp(pos)
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		# The tortoise watches its step around its own village.
		if _spares(v) or size <= 0.3 or v.global_position.distance_to(pos) >= 1.8 * size:
			continue
		if hostile:
			# The village's fighters are not squashed flat by a careless step.
			v.take_hit(Balance.num("creature_stomp_damage") * 0.5 * lerpf(0.3, 1.0, size), self)
		else:
			v.squish()
	footfall.emit(pos)


# --- Fighting goblins ---------------------------------------------------------

## Villagers this creature's feet and stomps leave alone.
func _spares(v: Villager) -> bool:
	return v.goblin if hostile else v.owned


func _update_attacks(delta: float) -> void:
	_action_cooldown = maxf(0.0, _action_cooldown - delta)
	if _action == Action.GRAB:
		_alert = true
		_update_grab(delta)
		return
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
		if d < REACH * size + 1.0:
			near.append(g)
			if d < nearest_d:
				nearest_d = d
				nearest = g
		elif d < hunt_d and (g.raiding or _threatens_village(g)):
			hunt_d = d
			hunt = g
	# The other giant counts too: in reach of our fists, or to be hunted
	# down when it comes for the village.
	var rival := _rival()
	var focus: Node3D = nearest
	var hunt_pos := hunt.global_position if hunt != null else Vector3.ZERO
	var hunting := hunt != null
	if rival != null and not rival.is_flying():
		var d := _flat(rival.global_position, global_position) - 2.0 * rival.size
		if d < REACH * size + 1.0:
			if d < nearest_d:
				focus = rival
		elif d < hunt_d and (rival.is_threat() or d < REACH * rival.size + 6.0):
			# (Or when it is near enough to be hitting us already.)
			hunting = true
			hunt_pos = rival.global_position
	_alert = focus != null or hunting
	_jaw_want = 0.16 + 0.14 * float(_spec.nervous) if _alert else 0.0
	if fleeing:
		# Keeping out of it until the wounds have closed.
		_turning = false
		if hp >= max_hp * Balance.num("raven_return_health") or Game.now > _flee_until:
			fleeing = false
		elif focus != null and Game.now >= _flee_again_at and Game.now >= snared_until:
			_flee()
		if fleeing:
			return
	if focus == null:
		_turning = false
		# Nothing in reach: go after raiders, unless the player sent us somewhere.
		# (A little one stays out of it.)
		if hunting and size >= 0.35 and (not has_target or _auto) and Game.now >= snared_until:
			if _should_fly(hunt_pos):
				auto_move(hunt_pos)
				return
			target = hunt_pos
			has_target = true
			_auto = true
			_look_at = target
		return
	if _auto:
		has_target = false
		_auto = false
	_action_point = focus.global_position
	_look_at = _action_point
	var to := _action_point - global_position
	to.y = 0.0
	# Stop and face them, even in the middle of a walk the player ordered.
	_turning = _action_cooldown < 0.4
	var facing := absf(angle_difference(heading, atan2(to.x, to.z))) < 0.55
	if not facing or _action_cooldown > 0.0 or _stepping[0] or _stepping[1] or speed > 0.6:
		return
	if focus == rival:
		_start_strike()
		return
	var point := global_position + to.normalized() * minf(to.length(), STOMP_STRIDE * size)
	var in_blast := 0
	for g in near:
		if _flat(g.global_position, point) < STOMP_RADIUS * size:
			in_blast += 1
	# Until it is big enough to pick goblins up, all it can do is stamp on
	# them. Otherwise it does what it is keenest on (see CreatureMind).
	var can_grab := size >= 0.4
	var stomp_ok := _stomp_is_safe(point) and in_blast > 0
	var keen_stomp := mind.weight("stomp") * (2.0 if in_blast >= 3 else 1.0)
	var keen_grab := maxf(mind.weight("throw"), mind.weight("eat")) if can_grab else 0.0
	if stomp_ok and keen_stomp > 0.0 and randf() * (keen_stomp + keen_grab) < keen_stomp:
		_start_stomp(point)
	elif keen_grab > 0.0:
		_start_grab(near)
	elif stomp_ok and keen_stomp > 0.0:
		_start_stomp(point)
	else:
		_action_cooldown = 0.8


## A blow at the other giant with both fists.
func _start_strike() -> void:
	_action = Action.STRIKE
	_action_t = 0.0
	_struck = false
	_jaw_want = 0.45


func _update_strike(delta: float) -> void:
	_action_t += delta
	if _action_t < STRIKE_LANDS - 0.15:
		# Fists up and back...
		_arm_want = Vector3(0.45, 0.95, -0.25)
		_crouch = 0.0
	else:
		# ...and down on its head.
		_arm_want = Vector3(0.12, -0.25, 1.0)
		_crouch = 0.35
	if not _struck and _action_t >= STRIKE_LANDS:
		_struck = true
		var rival := _rival()
		if rival != null and not rival.is_flying() and _flat(rival.global_position, global_position) - 2.0 * rival.size < REACH * size + 2.5:
			rival.take_hit(Balance.num("creature_strike_damage") * lerpf(0.3, 1.0, size), self)
			var at := rival.global_position.lerp(global_position, 0.3)
			Game.effects.spawn_dust(at + Vector3.UP * 3.0 * rival.size, 2.5 * size)
			Game.shake(0.7 * size, at)
	if _action_t >= STRIKE_TIME:
		_action = Action.NONE
		_action_cooldown = 1.0
		_crouch = 0.0
		_jaw_want = 0.0
		_arm_want = _spec.arm


## A stomp hurts everything round the foot, so it is only allowed when no
## villager and none of the village's buildings would be caught in it.
## (The Balrog has no such scruples: its stomps leave goblins unharmed.)
func _stomp_is_safe(point: Vector3) -> bool:
	if hostile:
		return true
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if not v.goblin and _flat(v.global_position, point) < STOMP_RADIUS * size + 1.0:
			return false
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if _flat(b.global_position, point) < b.footprint * 0.7 + 1.6 * size:
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
	Game.effects.spawn_dust(pos, 3.2 * size)
	Game.shake(size, pos)
	var radius := STOMP_RADIUS * size
	var hit: Array[Villager] = []
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		var d := _flat(v.global_position, pos)
		if d >= radius:
			continue
		if _spares(v):
			continue
		hit.append(v)
		# Enough to kill a goblin at the centre; less towards the edge.
		# (At full size. A small creature's stomp is weaker.)
		v.take_hit(Balance.num("creature_stomp_damage") * (1.0 - 0.5 * d / radius) * lerpf(0.3, 1.0, size), self)
		if not v.is_alive():
			v.fling(pos, 8.0 * lerpf(0.4, 1.0, size), false)
	# The other giant feels it too, and the Balrog's stomps break buildings.
	var rival := _rival()
	if rival != null and not rival.is_flying() and _flat(rival.global_position, pos) < radius + 2.0 * rival.size:
		rival.take_hit(Balance.num("creature_stomp_damage") * lerpf(0.3, 1.0, size), self)
	if hostile:
		for node in get_tree().get_nodes_in_group("player_buildings"):
			var b := node as Destructible
			if not b.destroyed and _flat(b.global_position, pos) < radius + b.footprint * 0.6:
				b.damage(Balance.num("balrog_building_damage") * lerpf(0.3, 1.0, size), pos, 5.0)
	_stomp_leg = -1
	_action = Action.NONE
	_action_cooldown = 1.4
	if not hit.is_empty() and not hostile:
		mind.did("stomp", "The creature stomped %s" % _name_them(hit))


## "a goblin", "3 goblins and an ogre", ...
func _name_them(list: Array[Villager]) -> String:
	var counts := {"goblin": 0, "ogre": 0, "villager": 0}
	for v in list:
		if is_instance_valid(v):
			counts["ogre" if v.ogre else ("goblin" if v.goblin else "villager")] += 1
	var parts: PackedStringArray = []
	for word: String in counts:
		var n: int = counts[word]
		if n == 1:
			parts.append(("an " if word == "ogre" else "a ") + word)
		elif n > 1:
			parts.append("%d %ss" % [n, word])
	return " and ".join(parts) if not parts.is_empty() else "nothing"


## Goblins hanging about near the village are enemies even between raids.
func _threatens_village(g: Villager) -> bool:
	var village := Game.village
	return is_instance_valid(village) and village.founded and g.global_position.distance_to(village.center) < 50.0


## Scoops up the nearest goblins, at most three to five of them.
func _start_grab(near: Array[Villager]) -> void:
	near.sort_custom(func(a: Villager, b: Villager) -> bool:
		return _flat(a.global_position, _action_point) < _flat(b.global_position, _action_point))
	_held.clear()
	_held_from.clear()
	var most := maxi(1, roundi(randi_range(3, 5) * size))
	for g in near:
		# Ogres are far too big to pick up.
		if not g.ogre and _held.size() < most and _flat(g.global_position, _action_point) < GRAB_RADIUS * size:
			_held.append(g)
	if _held.is_empty():
		_action_cooldown = 0.8
		return
	_jaw_want = 0.3
	_action = Action.GRAB
	_action_t = 0.0
	_released = 0
	_eating = randf() * (mind.weight("eat") + mind.weight("throw")) < mind.weight("eat")


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
			mind.did("eat", "The creature ate %s" % _name_them(_held))
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
					g.toss((fwd * randf_range(15.0, 22.0) + Vector3.UP * randf_range(9.0, 13.0) + right * randf_range(-5.0, 5.0)) * lerpf(0.5, 1.0, size))
			_released = _held.size()
			mind.did("throw", "The creature threw %s" % _name_them(_held))
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
		var hand := _hand_pos(i % 2) + Vector3(0.0, -0.6 + 0.35 * (i >> 1), 0.0) * size
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
	_arm_want = _spec.arm


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
	var nervous: float = _spec.nervous
	var breath := sin(_time * 1.6 * (1.0 + 1.6 * nervous))
	if knocked_out:
		_crouch = 1.3
	# Crouching (to grab) bends the knees and tips the body forwards.
	var stoop := _crouch + (0.35 if _stomp_leg >= 0 else 0.0)
	# In the air the body lies forward along the way it is going.
	_fly = move_toward(_fly, 1.0 if flying and _alt > 0.4 * size else 0.0, delta * 1.6)
	var aloft := smoothstep(0.0, 1.0, _fly)
	if aloft > 0.0:
		pace = minf(pace, 1.0) * (1.0 - aloft)
		stoop *= 1.0 - aloft
	_bob = lerpf(_bob, swing * 0.3 - 0.3 * pace - 0.12 + breath * 0.03 - stoop * 0.9, blend)
	_sway = lerpf(_sway, sway_target, blend)
	_lean = lerpf(_lean, pace * 0.14 + stoop * 0.42 + aloft * 1.2, blend)

	# A nervous creature shivers, and its head jerks about.
	var shiver := Vector3(sin(_time * 31.0), sin(_time * 37.0), 0.0) * 0.035 * nervous
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(0.4, 1.8)
		_twitch = randf_range(-0.4, 0.4) * nervous
	_twitch = lerpf(_twitch, 0.0, minf(1.0, delta * 2.5))
	_skel.set_bone_pose_position(_bone["pelvis"], _rest["pelvis"] + Vector3(-_sway * 3.0, _bob, 0.0) + shiver)
	_skel.set_bone_pose_rotation(_bone["pelvis"], Quaternion.from_euler(Vector3(_lean, 0.0, -_sway)))
	_skel.set_bone_pose_rotation(_bone["spine"], Quaternion.from_euler(Vector3(_lean * 0.4 + breath * 0.01, 0.0, _sway * 0.7)))
	_skel.set_bone_pose_scale(_bone["chest"], Vector3.ONE * (1.0 + breath * 0.012))

	# Head: look towards whatever the creature is doing, and open the jaw to cast.
	var to := _look_at - global_position
	var want_yaw := clampf(angle_difference(heading, atan2(to.x, to.z)), -0.7, 0.7) if to.length() > 3.0 else 0.0
	_look_yaw = lerpf(_look_yaw, want_yaw + sin(_time * 0.6) * 0.08, 1.0 - exp(-4.0 * delta))
	var casting := _cast_timer > 0.0
	# The tortoise hangs its head, and lifts it when something startles it.
	var nod := 0.16 - _bob * 0.12 - (0.3 if casting else 0.0) - _lean * 0.8 + (0.6 if knocked_out else 0.0)
	_skel.set_bone_pose_rotation(_bone["neck"], Quaternion.from_euler(Vector3(nod * 0.5, _look_yaw * 0.5, 0.0)))
	_skel.set_bone_pose_rotation(_bone["head"], Quaternion.from_euler(Vector3(nod * 0.5, _look_yaw * 0.5 + _twitch, _sway * 0.5)))
	_jaw = lerpf(_jaw, maxf(0.4 if casting else 0.03 + 0.02 * breath, _jaw_want), 1.0 - exp(-14.0 * delta))
	_skel.set_bone_pose_rotation(_bone["jaw"], Quaternion(Vector3.RIGHT, _jaw + float(_spec.get("jaw_rest", 0.0))))
	if _bone.has("wing_l"):
		_update_wings(delta, aloft)

	# Arms hang from the bind pose and swing against the legs.
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var stride := (_foot_pos(0) - _foot_pos(1)).dot(fwd)
	# (The nervous one wrings its paws.)
	var swing_targets: Array[float] = [stride * 0.16 / size + sin(_time * 7.0) * 0.08 * nervous,
		-stride * 0.16 / size + sin(_time * 7.0 + 2.1) * 0.08 * nervous]
	_arm_pose = _arm_pose.lerp(_arm_want, 1.0 - exp(-9.0 * delta))
	_fore_blend = lerpf(_fore_blend, 1.0 if _arm_want == _spec.arm else 0.0, blend)
	for k in 2:
		var side := "l" if k == 0 else "r"
		_arm_swing[k] = lerpf(_arm_swing[k], swing_targets[k], blend)
		var rest_dir: Vector3 = (_rest["arm_lower_" + side] - _rest["arm_upper_" + side]).normalized()
		var hang := Vector3(_side(k) * _arm_pose.x, _arm_pose.y, _arm_pose.z).normalized()
		var upper := Quaternion(Vector3.RIGHT, _arm_swing[k]) * Quaternion(rest_dir, hang)
		_skel.set_bone_pose_rotation(_bone["arm_upper_" + side], upper)
		var bend: float = _spec.elbow - 0.3 * maxf(-_arm_swing[k], 0.0) - 0.1 * pace
		var lower := Quaternion(Vector3.RIGHT, bend) * Quaternion(Vector3.BACK, _side(k) * 0.2)
		if _spec.has("fore"):
			# Point the forearm where the species holds it at rest, whatever
			# way the upper arm has turned.
			var fore: Vector3 = _spec.fore
			var want := upper.inverse() * Vector3(_side(k) * fore.x, fore.y, fore.z).normalized()
			var rest_lower: Vector3 = (_rest["hand_" + side] - _rest["arm_lower_" + side]).normalized()
			lower = lower.slerp(Quaternion(rest_lower, want), _fore_blend)
		_skel.set_bone_pose_rotation(_bone["arm_lower_" + side], lower)

	# Tail: a lazy wave that trails behind turns and bounces with each step.
	for i in 4:
		var wave := sin(_time * 1.9 * (1.0 + 2.0 * nervous) - i * 0.8) * (0.07 + 0.03 * i) * (1.0 + 1.5 * nervous) - _sway * 1.2
		var lift := 0.06 - _lean * 0.5 + sin(_time * 1.3 - i * 0.6) * 0.03 + swing * 0.03
		_skel.set_bone_pose_rotation(_bone["tail%d" % (i + 1)], Quaternion.from_euler(Vector3(lift, wave, 0.0)))


## Wings: the raven's hang half open at rest and beat when it flies; the
## Balrog's little ones only twitch.
func _update_wings(delta: float, aloft: float) -> void:
	var beats := 0.0
	var lift := 0.0
	if _spec.get("flies", false):
		# Hard beats to climb, slower ones to cruise, and a flare to land.
		var climbing := flying and _fly < 0.95
		_flap += delta * (9.0 if climbing else 6.0) * (1.4 - 0.4 * size)
		var air := 1.0 if flying else 0.0
		beats = sin(_flap) * lerpf(0.05, 0.62, maxf(aloft, air * 0.8))
		lift = lerpf(0.0, -0.22, aloft) + sin(_time * 1.3) * 0.03 * (1.0 - air)
	else:
		_flap += delta * (11.0 if _alert else 2.5)
		beats = sin(_flap) * (0.3 if _alert else 0.1)
	var normal: Vector3 = _spec.get("wing_normal", Vector3.BACK)
	var open: float = float(_spec.get("wing_open", 0.0)) * aloft
	var tip_open: float = float(_spec.get("tip_open", 0.0)) * aloft
	for k in 2:
		var s := _side(k)
		var side := "l" if k == 0 else "r"
		var n := Vector3(s * normal.x, normal.y, normal.z)
		# Up and down about the spine; out and in within the wing's own plane.
		var wing := Quaternion(Vector3.UP, s * (beats + lift)) * Quaternion(n, -s * open)
		_skel.set_bone_pose_rotation(_bone["wing_" + side], wing)
		if _bone.has("wingtip_" + side):
			var tip := Quaternion(Vector3.UP, s * sin(_flap - 0.9) * 0.3 * aloft) * Quaternion(n, s * tip_open)
			_skel.set_bone_pose_rotation(_bone["wingtip_" + side], tip)


func _update_legs() -> void:
	var to_skel := _skel.global_transform.affine_inverse()
	var pelvis := _skel.get_bone_global_pose(_bone["pelvis"])
	var aloft := smoothstep(0.0, 1.0, _fly)
	for k in 2:
		var side := "l" if k == 0 else "r"
		var hip: Vector3 = pelvis * (_rest["thigh_" + side] - _rest["pelvis"])
		var sole := _foot_pos(k)
		var ankle: Vector3 = to_skel * (sole + Vector3.UP * ANKLE_HEIGHT * size)
		if flying or aloft > 0.0:
			# Legs trail under the body, knees a little bent.
			var tucked: Vector3 = pelvis * Vector3(_side(k) * _foot_spread * 0.85, -(_thigh_length + _shin_length) * 0.84, 0.9)
			ankle = ankle.lerp(tucked, maxf(aloft, 0.0 if _alt < 0.3 * size else 0.35))
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
		if aloft > 0.0:
			# Toes hang.
			foot_basis = Basis(Quaternion(foot_basis).slerp(Quaternion(pelvis.basis * Basis(Vector3.RIGHT, 0.6)), aloft))
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
	var model: Node3D = (load(_spec.model) as PackedScene).instantiate()
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
	if _spec.has("crack_glow"):
		hide.set_shader_parameter("crack_glow", _spec.crack_glow)
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
	var glowing: bool = _spec.has("eye_glow")
	var whites := MeshBuilder.new()
	whites.color = Color.WHITE if glowing else _spec.eye_color
	var e: float = _spec.eye_size
	var eye: Vector3 = _spec.eye
	for k in 2:
		var s := _side(k)
		var centre := Vector3(s * eye.x, eye.y, eye.z)
		_eye_centres.append(centre)
		whites.add_blob(Vector3(e, e, e * 0.88), Transform3D(Basis(), centre), null, 0.0, 8, 12)
		# Glowing eyes are blank: only a faint brighter spot looks about.
		var pupil := MeshBuilder.new()
		if glowing:
			pupil.color = Color.WHITE
			pupil.add_blob(Vector3(0.5, 0.5, 0.3) * e, Transform3D.IDENTITY, null, 0.0, 6, 10)
			var spark := StandardMaterial3D.new()
			spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			spark.albedo_color = Color(1.0, 1.0, 1.0) * (float(_spec.eye_glow) * 1.3)
			_pupils.append(_face_part(attach, pupil.commit(), spark))
			var shut := MeshBuilder.new()
			shut.color = _spec.lid_color
			shut.add_blob(Vector3(1.24, 0.88, 1.12) * e, Transform3D.IDENTITY, null, 0.0, 6, 10)
			_lids.append(_face_part(attach, shut.commit(), paint))
			continue
		pupil.color = Color(0.05, 0.04, 0.04)
		pupil.add_blob(Vector3(0.44, 0.5, 0.3) * e, Transform3D.IDENTITY, null, 0.0, 6, 10)
		pupil.color = Color(1.0, 1.0, 1.0)
		pupil.add_blob(Vector3(0.12, 0.13, 0.09) * e, Transform3D(Basis(), Vector3(0.15, 0.2, 0.25) * e), null, 0.0, 4, 6)
		_pupils.append(_face_part(attach, pupil.commit(), Art.paint("plaster", 0.0)))
		# The tortoise's lid droops towards the outside of the face: instant
		# gloom. The squirrel's sits high, so its eyes stare.
		var lid := MeshBuilder.new()
		lid.color = _spec.lid_color
		lid.add_blob(Vector3(1.24, 0.88, 1.12) * e, Transform3D.IDENTITY, null, 0.0, 6, 10)
		_lids.append(_face_part(attach, lid.commit(), paint))
	if kind == "squirrel":
		# Inked on: the line from nose to mouth, and kinked whiskers.
		var ink := MeshBuilder.new()
		ink.color = Color(0.04, 0.03, 0.04)
		ink.add_box(Vector3(0.05, 0.4, 0.04), 0.01, Transform3D(Basis(), Vector3(0, 0.2, 1.83)))
		for k in 2:
			var s := _side(k)
			for w in 3:
				var y := 0.02 + 0.13 * w
				ink.add_tube(PackedVector3Array([Vector3(s * 0.5, y + 0.05, 1.62), Vector3(s * 1.2, y + 0.25 * (w - 1) + 0.12, 1.5),
					Vector3(s * 1.55, y + 0.32 * (w - 1) - 0.06, 1.42), Vector3(s * 2.0, y + 0.5 * (w - 1) + 0.1, 1.25)]),
					PackedFloat32Array([0.028, 0.022, 0.016, 0.006]), 5)
		_face_part(attach, ink.commit(), Art.paint("plaster", 0.0))
	if glowing:
		var lit := StandardMaterial3D.new()
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c: Color = _spec.eye_color
		lit.albedo_color = Color(c.r, c.g, c.b) * float(_spec.eye_glow)
		_face_part(attach, whites.commit(), lit).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
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
	var nervous: float = _spec.nervous
	var e: float = _spec.eye_size / 0.34
	# The eyes dart from place to place, faster when there is danger (and
	# all the time if the creature is nervous), and lean towards whatever
	# it is looking at.
	var jumpy := _alert or nervous > 0.5
	_dart_timer -= delta
	if _dart_timer <= 0.0:
		_dart_timer = randf_range(0.2, 0.8) if jumpy else randf_range(0.7, 2.6)
		_dart = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.5)) * (0.11 if jumpy else 0.08)
		if randf() < 0.3:
			_dart = Vector2.ZERO
	# A nervous creature with nothing to do keeps glancing over its shoulder.
	if nervous > 0.5 and not has_target and _action == Action.NONE and not _alert:
		_glance_timer -= delta
		if _glance_timer <= 0.0:
			_glance_timer = randf_range(1.0, 3.2)
			var a := heading + randf_range(-1.7, 1.7)
			_look_at = global_position + Vector3(sin(a), 0.0, cos(a)) * 20.0
	var to := _look_at - global_position
	var aside := 0.0
	if to.length() > 3.0:
		aside = clampf(angle_difference(heading + _look_yaw, atan2(to.x, to.z)), -1.0, 1.0)
	var want := _dart + Vector2(aside * 0.1, -0.06 * (1.0 - _anger))
	_gaze = _gaze.lerp(want, 1.0 - exp(-18.0 * delta))
	_gaze = Vector2(clampf(_gaze.x, -0.13, 0.13), clampf(_gaze.y, -0.12, 0.1))
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.5, 6.0) / (1.0 + 1.5 * nervous)
		_blink = 0.14
	_blink = maxf(0.0, _blink - delta)
	var shut := 1.0 if _blink > 0.0 or knocked_out else 0.0
	var lid_y: Array = _spec.lid_y
	var lid_tilt: Array = _spec.lid_tilt
	var pupil: Array = _spec.pupil
	for k in 2:
		var s := _side(k)
		var c := _eye_centres[k]
		_pupils[k].position = c + Vector3(_gaze.x - s * 0.04, _gaze.y - 0.04, 0.25 - 1.2 * _gaze.length_squared()) * e
		_pupils[k].scale = Vector3.ONE * lerpf(pupil[0], pupil[1], _anger)
		# The tortoise's sad lids droop outwards, and when it is angry they
		# slant down to the nose and sit lower. The squirrel's lift in fright.
		_lids[k].rotation.z = s * lerpf(lid_tilt[0], lid_tilt[1], _anger)
		_lids[k].position = c + Vector3(s * 0.03, lerpf(lid_y[0], lid_y[1], _anger) * (1.0 - shut) - shut * 0.02, 0.02 + shut * 0.05) * Vector3(e, 1.0, e)
	if absf(_jaw - _mouth_drawn.x) > 0.01 or absf(_anger - _mouth_drawn.y) > 0.05:
		_mouth_drawn = Vector2(_jaw, _anger)
		_draw_mouth(maxf(0.0, _jaw - 0.05), _anger)


## Draws the mouth in head space: a black line along the lip that follows
## the frown carved into the model, and, when the jaw is open, the dark
## inside of the mouth with a second line for the lower lip.
func _draw_mouth(open: float, anger: float) -> void:
	_mouth.clear_surfaces()
	if not _spec.has("mouth"):
		# A beak needs no drawing.
		return
	var upper := PackedVector3Array()
	var lower := PackedVector3Array()
	var m: Array = _spec.mouth
	var frown: Array = _spec.frown
	var droop := lerpf(frown[0], frown[1], anger)
	var wide: float = m[0] / 0.85
	for i in 13:
		var t := i / 6.0 - 1.0
		var lip := Vector3(m[0] * t, m[1] - droop * t * t, m[2] - m[3] * t * t)
		var gape := 1.45 * wide * open * pow(1.0 - t * t, 0.6)
		upper.append(lip)
		# The open mouth hangs just in front of the stretched skin of the jaw.
		lower.append(lip + Vector3(0.0, -gape, 0.1 * minf(gape, 1.0) - 0.12 * gape * gape))
	if open > 0.03:
		_mouth.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mouth_material)
		_mouth.surface_set_color(_spec.get("mouth_color", Color(0.11, 0.015, 0.03)))
		for i in 13:
			_mouth.surface_add_vertex(upper[i] + Vector3(0, 0, 0.04))
			_mouth.surface_add_vertex(lower[i] + Vector3(0, 0, 0.04))
		_mouth.surface_end()
		for i in 13:
			upper[i].z += 0.06
			lower[i].z += 0.06
		_ink_line(lower, 0.04 * wide)
	_ink_line(upper, (0.05 + 0.02 * anger) * wide)


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
