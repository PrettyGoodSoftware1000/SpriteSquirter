class_name Villager
extends Node3D
## A tiny villager. Wanders around home, panics near danger, can catch fire,
## be flung by explosions or squashed flat by a giant foot.

enum State { IDLE, WALK, FLEE, BURNING, DEAD }

const SHIRT_COLORS := [
	Color(0.9, 0.25, 0.25), Color(0.25, 0.5, 0.9), Color(0.95, 0.8, 0.2),
	Color(0.3, 0.75, 0.35), Color(0.75, 0.35, 0.85), Color(1.0, 0.55, 0.15), Color(0.95, 0.95, 0.95)]
const SKIN_COLORS := [Color(1.0, 0.85, 0.7), Color(0.85, 0.62, 0.45), Color(0.55, 0.38, 0.25), Color(0.95, 0.75, 0.6)]
const CHAR_COLOR := Color(0.08, 0.07, 0.07)

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
var _shirt_mat := StandardMaterial3D.new()
var _skin_mat := StandardMaterial3D.new()
var _fire: FireEmitter


func _ready() -> void:
	add_to_group("villagers")
	_build_body()
	_timer = randf_range(0.0, 3.0)


func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)
	_shirt_mat.albedo_color = SHIRT_COLORS[randi() % SHIRT_COLORS.size()]
	_skin_mat.albedo_color = SKIN_COLORS[randi() % SKIN_COLORS.size()]
	var torso := CapsuleMesh.new()
	torso.radius = 0.17
	torso.height = 0.62
	torso.radial_segments = 8
	torso.rings = 2
	_add_mesh(torso, _shirt_mat, Vector3(0, 0.42, 0))
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	head.radial_segments = 8
	head.rings = 4
	_add_mesh(head, _skin_mat, Vector3(0, 0.86, 0))
	if randf() < 0.5:
		var hat := CylinderMesh.new()
		hat.top_radius = 0.0 if randf() < 0.6 else 0.1
		hat.bottom_radius = 0.16
		hat.height = 0.28
		hat.radial_segments = 8
		var hat_mat := StandardMaterial3D.new()
		hat_mat.albedo_color = SHIRT_COLORS[randi() % SHIRT_COLORS.size()].darkened(0.3)
		_add_mesh(hat, hat_mat, Vector3(0, 1.04, 0))
	scale = Vector3.ONE * 1.15


func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_body.add_child(mi)


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
			if _move_towards(global_position + away.normalized() * 3.0, 4.2 * _speed_scale, delta):
				_timer = 0.0
			if _timer <= 0.0:
				state = State.IDLE
				_timer = randf_range(0.5, 2.0)
		State.BURNING:
			_timer -= delta
			if randf() < delta * 2.0:
				var a := randf() * TAU
				_run_dir = Vector3(cos(a), 0.0, sin(a))
			_move_towards(global_position + _run_dir * 3.0, 5.0, delta)
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
	if _moving:
		var rate := 18.0 if state == State.FLEE or state == State.BURNING else 9.0
		_phase += delta * rate
		_body.position.y = absf(sin(_phase)) * 0.08
		_body.rotation.z = sin(_phase) * 0.15
		_body.rotation.x = 0.25 if state == State.FLEE else 0.0
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, minf(1.0, delta * 10.0))
		_body.rotation.z = lerpf(_body.rotation.z, 0.0, minf(1.0, delta * 10.0))
		_body.rotation.x = 0.0


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
	_fire = FireEmitter.new()
	_fire.size = 0.3
	_fire.with_light = false
	add_child(_fire)
	_fire.position.y = 0.6


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
	_body.scale = Vector3(1.7, 0.12, 1.7)
	_body.position.y = 0.0


func _die(charred: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	remove_from_group("villagers")
	_timer = 0.0
	if charred:
		_shirt_mat.albedo_color = CHAR_COLOR
		_skin_mat.albedo_color = CHAR_COLOR
	if _fire:
		_fire.reparent(Game.fire, true)
		_fire.extinguish()
		_fire = null
	if not _airborne:
		_body.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		_body.position.y = 0.17


func _update_dead(delta: float) -> void:
	if _airborne:
		_velocity.y -= 20.0 * delta
		global_position += _velocity * delta
		_body.rotation.x += delta * 9.0
		var ground := Game.terrain.get_height(global_position.x, global_position.z)
		if global_position.y <= ground and _velocity.y < 0.0:
			global_position.y = ground
			_airborne = false
			_body.rotation = Vector3(PI / 2.0, 0.0, 0.0)
			_body.position.y = 0.17
		return
	_timer += delta
	if _timer > 12.0:
		global_position.y -= delta * 0.3
	if _timer > 15.0:
		queue_free()
