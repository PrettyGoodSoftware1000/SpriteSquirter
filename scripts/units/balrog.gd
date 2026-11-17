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
## "balrog_fireball_seconds" at whatever group of enemies it can see. It has
## two little wings and cannot fly. It always walks at "balrog_speed", a
## little slower than a goblin marches.
##
## At no health it dies (it does not get up again), and the village gets
## "balrog_bones" bones. GoblinRaids hatches the next one.

signal died
signal grew_up

const SPEC := {
	"name": "Balrog", "model": "res://assets/creature/balrog.glb", "speed": 2.3,
	"nervous": 0.0,
	"eye_size": 0.28, "eye_color": Color(0.72, 0.36, 1.0), "eye_glow": 1.8,
	"lid_color": Color(0.125, 0.075, 0.07), "lid_y": [0.26, 0.16], "lid_tilt": [0.45, 0.62], "pupil": [1.0, 1.0],
	# (No drawn mouth: the model's jaws hang open on a glowing throat.)
	"eye": Vector3(0.62, 0.62, 1.1), "frown": [0.22, 0.3],
	"arm": Vector3(0.3, -1.0, 0.2), "elbow": -0.35,
	"crack_glow": Color(1.5, 0.36, 0.04),
}
## How long the body lies there before it crumbles.
const DEATH_SECONDS := 9.0
## While raiding it goes for anyone this close.
const RAID_SIGHT := 45.0

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
