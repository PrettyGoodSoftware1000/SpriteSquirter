class_name GiantBat
extends Node3D
## A giant armoured bat that flies out of a goblin cave during a raid,
## snatches one of the player's villagers at random and carries it back to
## the cave, where the villager is lost. A fireball or chain lightning can
## bring it down (Balance "bat_health"), and a single arrow or wizard's
## firebolt always does; the villager it was carrying then drops and lives. GoblinRaids launches them: set `cave` first.

signal took(victim: Villager)

enum State { HUNT, CARRY, LEAVE, FALL }

const CRUISE := 15.0
const FUR := Color(0.2, 0.16, 0.21)
const BONE := Color(0.9, 0.86, 0.72)
const INK := Color(0.04, 0.03, 0.05)

var cave: Node3D
var hp := 80.0
var state := State.HUNT

var _victim: Villager
var _wings: Array[Node3D] = []
var _body: Node3D
var _time := randf() * 5.0
var _fall := Vector3.ZERO
var _grounded := 0.0


func _ready() -> void:
	add_to_group("bats")
	hp = Balance.num("bat_health")
	_build()
	_choose_victim()


func is_alive() -> bool:
	return state != State.FALL


## Leaves off hunting and flies home (the raid is over).
func go_home() -> void:
	if state == State.HUNT:
		state = State.LEAVE


func take_hit(amount: float, _from: Node3D) -> void:
	if state == State.FALL:
		return
	# One arrow or firebolt from the village's archers and wizards is enough.
	if _from is Villager:
		amount = maxf(amount, hp)
	hp -= amount
	if hp > 0.0:
		return
	if is_instance_valid(_victim):
		_victim.release()
	_victim = null
	state = State.FALL
	_fall = Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2))
	remove_from_group("bats")


func _choose_victim() -> void:
	_victim = null
	var village := Game.village
	if not is_instance_valid(village):
		return
	var choice: Array[Villager] = []
	for v in village.people():
		if v.is_alive() and v.state != Villager.State.HELD:
			choice.append(v)
	if not choice.is_empty():
		_victim = choice[randi() % choice.size()]


func _process(delta: float) -> void:
	_time += delta
	var flap := sin(_time * 7.5)
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		_wings[k].rotation.z = s * (0.2 + 0.6 * flap) if state != State.FALL else s * 1.1
	_body.position.y = -0.25 * flap if state != State.FALL else 0.0
	match state:
		State.HUNT:
			if not is_instance_valid(_victim) or not _victim.is_alive() or _victim.state == Villager.State.HELD:
				_choose_victim()
				if _victim == null:
					state = State.LEAVE
					return
			var prey := _victim.global_position + Vector3.UP * 2.0 * _victim.scale.y
			if _fly_to(prey, delta) < 1.3:
				_victim.grab()
				state = State.CARRY
				took.emit(_victim)
		State.CARRY:
			if not is_instance_valid(_victim) or not _victim.is_alive():
				state = State.LEAVE
				return
			var near := _fly_to(_cave_mouth(), delta)
			_victim.global_position = global_position + Vector3(0.0, -2.0 * _victim.scale.y - 0.5, 0.0)
			_victim.rotation.y = rotation.y
			if near < 2.5:
				# Into the cave with it.
				_victim.carried_off()
				queue_free()
		State.LEAVE:
			if _fly_to(_cave_mouth(), delta) < 2.5:
				queue_free()
		State.FALL:
			_fall.y -= 20.0 * delta
			global_position += _fall * delta
			_body.rotation.x += delta * 5.0
			var ground := Game.terrain.surface_height(global_position.x, global_position.z)
			if global_position.y <= ground + 0.6:
				global_position.y = ground + 0.6
				if _grounded == 0.0:
					Game.effects.spawn_dust(global_position, 1.6)
					_body.rotation = Vector3(0.0, 0.0, PI)
				_fall = Vector3.ZERO
				_grounded += delta
				if _grounded > 6.0:
					queue_free()


func _cave_mouth() -> Vector3:
	if not is_instance_valid(cave):
		return global_position + Vector3.UP * 60.0
	var facing: float = cave.get_meta("facing", 0.0)
	return cave.global_position + Vector3(sin(facing), 0.0, cos(facing)) * 2.5 + Vector3.UP * 2.2


## Flies towards `goal`: high over the ground on the way, stooping to it at
## the end. Returns how far there is still to go.
func _fly_to(goal: Vector3, delta: float) -> float:
	var to := goal - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var far := flat.length()
	var speed := Balance.num("bat_speed")
	var cruise := Game.terrain.surface_height(global_position.x, global_position.z) + CRUISE
	# Start the stoop from about one and a half times the cruising height away.
	var want := lerpf(goal.y, maxf(cruise, goal.y), smoothstep(4.0, CRUISE * 1.5, far))
	var step := flat.normalized() * minf(speed * delta, far) if far > 0.01 else Vector3.ZERO
	var climb := clampf(want - global_position.y, -speed * 0.9 * delta, speed * 0.7 * delta)
	global_position += step + Vector3.UP * climb
	if far > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), minf(1.0, delta * 5.0))
	_body.rotation.x = lerpf(_body.rotation.x, clampf(-climb / maxf(speed * delta, 0.001), -1.0, 1.0) * 0.5, minf(1.0, delta * 4.0))
	return (goal - global_position).length()


# --- The model -------------------------------------------------------------------

static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var mb := MeshBuilder.new()
	# Body, ruff and head (it faces +Z).
	mb.color = FUR
	mb.add_blob(Vector3(0.95, 0.85, 1.35), _at(0, 0, 0), null, 0.0, 8, 12)
	mb.add_blob(Vector3(0.64, 0.6, 0.64), _at(0, 0.3, 1.45), null, 0.0, 8, 12)
	mb.color = FUR.lightened(0.14)
	mb.add_blob(Vector3(0.72, 0.5, 0.75), _at(0, -0.4, 0.45), null, 0.0, 6, 10)
	# A pig's snout, a gaping mouth and fangs.
	mb.color = Color(0.52, 0.32, 0.38)
	mb.add_blob(Vector3(0.3, 0.24, 0.28), _at(0, 0.22, 2.02), null, 0.0, 6, 8)
	mb.color = Color(0.45, 0.08, 0.1)
	mb.add_blob(Vector3(0.34, 0.24, 0.26), _at(0, -0.12, 1.86), null, 0.0, 6, 8)
	mb.color = INK
	for sx: float in [-1.0, 1.0]:
		mb.add_blob(Vector3(0.06, 0.07, 0.04), _at(sx * 0.11, 0.24, 2.28), null, 0.0, 3, 5)
		mb.add_box(Vector3(0.3, 0.07, 0.06), 0.01, Transform3D(Basis(Vector3.BACK, sx * -0.5), Vector3(sx * 0.3, 0.62, 1.9)))
	mb.color = BONE
	for sx: float in [-1.0, 1.0]:
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.2, 0.06, 2.05), Vector3(sx * 0.22, -0.3, 2.1)]), PackedFloat32Array([0.07, 0.008]), 5)
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.14, -0.3, 2.0), Vector3(sx * 0.15, -0.06, 2.08)]), PackedFloat32Array([0.05, 0.008]), 5)
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.07, 0.04, 2.14), Vector3(sx * 0.07, -0.1, 2.16)]), PackedFloat32Array([0.035, 0.006]), 4)
	# Glaring eyes.
	mb.color = Color(1.0, 0.86, 0.3)
	for sx: float in [-1.0, 1.0]:
		mb.add_blob(Vector3(0.1, 0.09, 0.06), _at(sx * 0.3, 0.48, 1.94), null, 0.0, 4, 6)
	mb.color = INK
	for sx: float in [-1.0, 1.0]:
		mb.add_blob(Vector3(0.04, 0.06, 0.03), _at(sx * 0.3, 0.48, 1.99), null, 0.0, 3, 5)
	# Great ears, pink inside, and a pair of horns between them.
	for sx: float in [-1.0, 1.0]:
		mb.color = FUR
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.36, 0.68, 1.3), Vector3(sx * 0.66, 1.2, 1.26), Vector3(sx * 0.8, 1.75, 1.15)]),
			PackedFloat32Array([0.3, 0.26, 0.02]), 7)
		mb.color = Color(0.6, 0.36, 0.44)
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.4, 0.74, 1.42), Vector3(sx * 0.66, 1.2, 1.38), Vector3(sx * 0.78, 1.6, 1.26)]),
			PackedFloat32Array([0.18, 0.17, 0.02]), 6)
		mb.color = BONE
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.16, 0.8, 1.4), Vector3(sx * 0.2, 1.15, 1.5), Vector3(sx * 0.12, 1.45, 1.7)]),
			PackedFloat32Array([0.1, 0.07, 0.01]), 5)
	# Armour strapped on its back, with bone spikes.
	mb.color = Color(0.42, 0.44, 0.36)
	mb.add_blob(Vector3(0.9, 0.36, 1.05), _at(0, 0.62, -0.05), null, 0.0, 6, 10)
	mb.add_blob(Vector3(0.62, 0.3, 0.5), _at(0, -0.62, 0.5), null, 0.0, 5, 8)
	for sx: float in [-1.0, 1.0]:
		mb.add_blob(Vector3(0.42, 0.3, 0.46), _at(sx * 0.82, 0.5, 0.55), null, 0.0, 5, 8)
	mb.color = Color(0.3, 0.22, 0.14)
	mb.add_lathe(PackedVector2Array([Vector2(0.9, -0.08), Vector2(0.96, 0.0), Vector2(0.9, 0.08)]), 12,
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.5)))
	mb.color = BONE
	for k in 5:
		var z := 0.7 - k * 0.38
		mb.add_tube(PackedVector3Array([Vector3(0, 0.86, z), Vector3(0, 1.5 + 0.2 * sin(k * 1.3), z - 0.22)]), PackedFloat32Array([0.15, 0.01]), 6)
	for sx: float in [-1.0, 1.0]:
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.9, 0.7, 0.55), Vector3(sx * 1.3, 1.2, 0.5)]), PackedFloat32Array([0.13, 0.01]), 5)
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.6, 0.85, -0.5), Vector3(sx * 0.95, 1.3, -0.7)]), PackedFloat32Array([0.11, 0.01]), 5)
	# Rags, legs and claws.
	mb.color = Color(0.42, 0.13, 0.13)
	for k in 3:
		mb.add_box(Vector3(0.34, 0.9 - 0.15 * (k % 2), 0.05), 0.01, Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3((k - 1) * 0.38, -1.0, -0.75)))
	for sx: float in [-1.0, 1.0]:
		mb.color = FUR
		mb.add_tube(PackedVector3Array([Vector3(sx * 0.42, -0.5, -0.7), Vector3(sx * 0.6, -1.1, -0.35), Vector3(sx * 0.55, -1.6, -0.55)]),
			PackedFloat32Array([0.26, 0.17, 0.1]), 6)
		mb.color = BONE
		for k in 3:
			mb.add_tube(PackedVector3Array([Vector3(sx * 0.55, -1.6, -0.55), Vector3(sx * 0.55 + (k - 1) * 0.16, -1.95, -0.35)]), PackedFloat32Array([0.05, 0.006]), 4)
	_mesh(_body, mb)
	# The wings: an arm, three long fingers and skin between them.
	for sx: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 0.8, 0.35, 0.35)
		_body.add_child(pivot)
		_wings.append(pivot)
		var wing := MeshBuilder.new()
		var wrist := Vector3(sx * 3.2, 0.5, 0.9)
		var tips := [Vector3(sx * 5.8, 0.1, 0.7), Vector3(sx * 5.2, -0.1, -1.3), Vector3(sx * 3.7, -0.15, -2.5)]
		var hip := Vector3(sx * 0.05, -0.3, -1.4)
		wing.color = FUR
		wing.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(sx * 1.9, 0.6, 0.2), wrist]), PackedFloat32Array([0.24, 0.16, 0.11]), 6)
		wing.color = FUR.darkened(0.25)
		for tip: Vector3 in tips:
			wing.add_tube(PackedVector3Array([wrist, wrist.lerp(tip, 0.5) + Vector3(0, 0.12, 0), tip]), PackedFloat32Array([0.09, 0.06, 0.015]), 5)
		wing.color = BONE
		wing.add_tube(PackedVector3Array([wrist, wrist + Vector3(sx * 0.25, 0.6, 0.55), wrist + Vector3(sx * 0.1, 0.95, 0.95)]), PackedFloat32Array([0.11, 0.07, 0.01]), 5)
		for tip: Vector3 in tips:
			wing.add_tube(PackedVector3Array([tip, tip + (tip - wrist).normalized() * 0.5 + Vector3(0, -0.2, 0)]), PackedFloat32Array([0.05, 0.006]), 4)
		# The skin, torn into scallops between the fingers.
		var edge: Array[Vector3] = [Vector3(0, 0.0, 0.25), wrist, tips[0]]
		edge.append(tips[0].lerp(tips[1], 0.5).lerp(wrist, 0.22))
		edge.append(tips[1])
		edge.append(tips[1].lerp(tips[2], 0.5).lerp(wrist, 0.25))
		edge.append(tips[2])
		edge.append(tips[2].lerp(hip, 0.5).lerp(wrist, 0.3))
		edge.append(hip)
		for k in range(1, edge.size() - 1):
			wing.color = Color(0.34, 0.26, 0.33) if k % 2 == 0 else Color(0.29, 0.22, 0.3)
			for up: float in [1.0, -1.0]:
				wing.add_fan(PackedVector3Array([edge[0], edge[k], edge[k + 1]]), Vector3.UP * up * sx)
		_mesh(pivot, wing)


func _mesh(parent: Node3D, mb: MeshBuilder) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = Art.cloth()
	parent.add_child(mi)
