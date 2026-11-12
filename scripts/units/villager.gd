class_name Villager
extends Node3D
## A tiny villager. Wanders around home, panics near danger, can catch fire,
## be flung by explosions or squashed flat by a giant foot.
##
## Bodies come from a small library of pre-built looks (tunic, skin, hair
## and hat colours are baked into the mesh), with separate legs and arms
## that swing as the villager walks.

enum State { IDLE, WALK, FLEE, BURNING, DEAD }

const LOOKS := 14

static var _looks: Array[Dictionary] = []

var home := Vector3.ZERO
var home_radius := 14.0
var state := State.IDLE

var _target := Vector3.ZERO
var _timer := 0.0
var _danger := Vector3.ZERO
var _velocity := Vector3.ZERO
var _airborne := false
var _moving := false
var _phase := randf() * TAU
var _speed_scale := randf_range(0.85, 1.15)
var _run_dir := Vector3.FORWARD
var _body: Node3D
var _legs: Array[MeshInstance3D] = []
var _arms: Array[MeshInstance3D] = []
var _meshes: Array[MeshInstance3D] = []
var _fire: FireEmitter


func _ready() -> void:
	add_to_group("villagers")
	_build_body()
	_timer = randf_range(0.0, 3.0)


func _build_body() -> void:
	if _looks.is_empty():
		_build_looks()
	var look: Dictionary = _looks[randi() % _looks.size()]
	_body = Node3D.new()
	add_child(_body)
	_add_mesh(look.body, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		_legs.append(_add_mesh(look.leg, Vector3(sx * 0.1, 0.8, 0.0)))
		_arms.append(_add_mesh(look.arm, Vector3(sx * 0.27, 1.33, 0.0)))
	scale = Vector3.ONE * randf_range(0.92, 1.08)


func _add_mesh(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Art.cloth()
	mi.position = pos
	_body.add_child(mi)
	_meshes.append(mi)
	return mi


## Builds the shared library of villager looks.
static func _build_looks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for k in LOOKS:
		var tunic: Color = Art.CLOTH_COLORS[rng.randi() % Art.CLOTH_COLORS.size()]
		var trousers := Color(0.28, 0.2, 0.14).lerp(Art.CLOTH_COLORS[rng.randi() % Art.CLOTH_COLORS.size()], 0.3)
		var skin: Color = Art.SKIN_COLORS[rng.randi() % Art.SKIN_COLORS.size()]
		var hair := Color(0.16, 0.1, 0.06).lerp(Color(0.75, 0.5, 0.2), rng.randf())
		var skirt := rng.randf() < 0.45

		var body := MeshBuilder.new()
		body.color = tunic
		var hem := 0.35 if skirt else 0.72
		body.add_lathe(PackedVector2Array([Vector2(0.0, hem), Vector2(0.33 if skirt else 0.25, hem), Vector2(0.21, 1.0),
			Vector2(0.24, 1.3), Vector2(0.13, 1.44), Vector2(0.0, 1.46)]), 10)
		body.color = tunic.darkened(0.45)
		body.add_lathe(PackedVector2Array([Vector2(0.225, 0.98), Vector2(0.24, 1.02), Vector2(0.225, 1.06)]), 10)
		body.color = skin
		body.add_blob(Vector3(0.15, 0.17, 0.16), Transform3D(Basis(), Vector3(0, 1.58, 0)), null, 0.0, 6, 10)
		match rng.randi_range(0, 3):
			0: # Pointed hat
				body.color = Art.CLOTH_COLORS[rng.randi() % Art.CLOTH_COLORS.size()].darkened(0.2)
				body.add_lathe(PackedVector2Array([Vector2(0.0, 1.66), Vector2(0.27, 1.66), Vector2(0.27, 1.69), Vector2(0.15, 1.72),
					Vector2(0.08, 1.92), Vector2(0.0, 2.08)]), 10)
			1: # Straw hat
				body.color = Art.THATCH_COLORS[0]
				body.add_lathe(PackedVector2Array([Vector2(0.0, 1.66), Vector2(0.36, 1.64), Vector2(0.36, 1.67), Vector2(0.16, 1.71),
					Vector2(0.13, 1.8), Vector2(0.0, 1.83)]), 10)
			2: # Hood
				body.color = tunic.darkened(0.25)
				body.add_blob(Vector3(0.19, 0.2, 0.2), Transform3D(Basis(), Vector3(0, 1.6, -0.04)), null, 0.0, 6, 10)
			_: # Bare head with hair
				body.color = hair
				body.add_blob(Vector3(0.165, 0.14, 0.175), Transform3D(Basis(), Vector3(0, 1.64, -0.03)), null, 0.0, 6, 10)

		var leg := MeshBuilder.new()
		leg.color = trousers
		leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.095, 0.07]), 6)
		leg.color = Color(0.2, 0.14, 0.1)
		leg.add_blob(Vector3(0.08, 0.06, 0.14), Transform3D(Basis(), Vector3(0, -0.74, 0.05)), null, 0.0, 4, 8)

		var arm := MeshBuilder.new()
		arm.color = tunic.darkened(0.1)
		arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.5, 0)]), PackedFloat32Array([0.075, 0.055]), 6)
		arm.color = skin
		arm.add_blob(Vector3(0.06, 0.07, 0.06), Transform3D(Basis(), Vector3(0, -0.55, 0)), null, 0.0, 4, 8)
		_looks.append({"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()})


func _process(delta: float) -> void:
	_moving = false
	match state:
		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_choose_wander_target()
		State.WALK:
			if _move_towards(_target, 1.3 * _speed_scale, delta):
				state = State.IDLE
				_timer = randf_range(1.5, 5.0)
		State.FLEE:
			_timer -= delta
			var away := global_position - _danger
			away.y = 0.0
			if away.length_squared() < 0.01:
				away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
			if _move_towards(global_position + away.normalized() * 3.0, 4.4 * _speed_scale, delta):
				_timer = 0.0
			if _timer <= 0.0:
				state = State.IDLE
				_timer = randf_range(0.5, 2.0)
		State.BURNING:
			_timer -= delta
			if randf() < delta * 2.0:
				var a := randf() * TAU
				_run_dir = Vector3(cos(a), 0.0, sin(a))
			_move_towards(global_position + _run_dir * 3.0, 5.2, delta)
			if _timer <= 0.0:
				Game.fire.start_fire(global_position, 3, 0.6)
				_die(true)
		State.DEAD:
			_update_dead(delta)
			return
	global_position.y = Game.terrain.get_height(global_position.x, global_position.z)
	_animate(delta)


func _choose_wander_target() -> void:
	for attempt in 6:
		var a := randf() * TAU
		var d := randf() * home_radius
		var p := home + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if Game.terrain.get_height(p.x, p.z) > Terrain.WATER_LEVEL + 0.3:
			_target = p
			state = State.WALK
			return
	_timer = 1.0


## Moves towards `goal` on the ground. Returns true when arrived or blocked.
func _move_towards(goal: Vector3, speed: float, delta: float) -> bool:
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.3:
		return true
	var step := to / dist * minf(speed * delta, dist)
	var next := global_position + step
	var terrain := Game.terrain
	if not terrain.is_inside(next.x, next.z) or terrain.get_height(next.x, next.z) < Terrain.WATER_LEVEL + 0.15:
		return true
	global_position = Vector3(next.x, global_position.y, next.z)
	rotation.y = lerp_angle(rotation.y, atan2(step.x, step.z), minf(1.0, delta * 10.0))
	_moving = true
	return false


func _animate(delta: float) -> void:
	var panicking := state == State.FLEE or state == State.BURNING
	var blend := minf(1.0, delta * 12.0)
	var stride := 0.0
	if _moving:
		_phase += delta * (17.0 if panicking else 8.5)
		stride = sin(_phase) * (0.9 if panicking else 0.55)
		_body.position.y = absf(cos(_phase)) * 0.05
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, blend)
	_body.rotation.x = lerpf(_body.rotation.x, 0.22 if panicking and _moving else 0.0, blend)
	for k in 2:
		var s := 1.0 if k == 0 else -1.0
		_legs[k].rotation.x = lerpf(_legs[k].rotation.x, stride * s, blend)
		# Panicking villagers throw their arms in the air.
		var arm := -2.7 + sin(_phase * 1.3 + k) * 0.35 if panicking else -stride * s * 0.8
		_arms[k].rotation.x = lerpf(_arms[k].rotation.x, arm, blend)
		_arms[k].rotation.z = lerpf(_arms[k].rotation.z, s * (-0.35 if panicking else -0.08), blend)


func is_alive() -> bool:
	return state != State.DEAD


func flee(from: Vector3) -> void:
	if state == State.DEAD or state == State.BURNING:
		return
	_danger = from
	state = State.FLEE
	_timer = randf_range(3.0, 6.0)


func catch_fire() -> void:
	if state == State.DEAD or state == State.BURNING:
		return
	state = State.BURNING
	_timer = randf_range(3.0, 5.0)
	_set_burn(0.3)
	_fire = FireEmitter.new()
	_fire.size = 0.4
	_fire.with_light = false
	add_child(_fire)
	_fire.position.y = 1.0


## Thrown through the air by an explosion.
func fling(from: Vector3, force: float) -> void:
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	_die(true)
	_velocity = (away + Vector3.UP * 1.2).normalized() * force * randf_range(0.7, 1.2)
	_airborne = true


## Flattened like a pancake under a giant foot.
func squish() -> void:
	if state == State.DEAD:
		return
	_die(false)
	_body.rotation = Vector3.ZERO
	_body.scale = Vector3(1.8, 0.07, 1.8)
	_body.position.y = 0.0


func _set_burn(value: float) -> void:
	for mi in _meshes:
		mi.set_instance_shader_parameter("burn", value)


func _die(charred: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	remove_from_group("villagers")
	_timer = 0.0
	if charred:
		_set_burn(1.0)
	if _fire:
		_fire.reparent(Game.fire, true)
		_fire.extinguish()
		_fire = null
	if not _airborne:
		_lie_down()


func _lie_down() -> void:
	_body.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_body.position = Vector3(0.0, 0.2, -0.8)


func _update_dead(delta: float) -> void:
	if _airborne:
		_velocity.y -= 20.0 * delta
		global_position += _velocity * delta
		_body.rotation.x += delta * 9.0
		var ground := Game.terrain.get_height(global_position.x, global_position.z)
		if global_position.y <= ground and _velocity.y < 0.0:
			global_position.y = ground
			_airborne = false
			_lie_down()
		return
	_timer += delta
	if _timer > 12.0:
		global_position.y -= delta * 0.3
	if _timer > 15.0:
		queue_free()
