class_name Villager
extends Node3D
## A tiny villager. Wanders around home, panics near danger, can catch fire,
## be flung by explosions or squashed flat by a giant foot.
##
## Bodies come from a small library of pre-built looks (tunic, skin, hair
## and hat colours are baked into the mesh), with separate legs and arms
## that swing as the villager walks.
##
## The player's villagers ("owned", group "people") also take jobs from
## their PlayerVillage: walk to a tree, rock, field or building site and
## work there. Children are born small and grow up in GROW_SECONDS.

enum State { IDLE, WALK, FLEE, BURNING, DEAD, JOB }

const LOOKS := 14
const GROW_SECONDS := 60.0
const CHILD_SCALE := 0.45

static var _looks: Array[Dictionary] = []
static var _goblin_looks: Array[Dictionary] = []

## Set before adding to the scene: goblins are green, big-eared and stay
## close to their cave.
var goblin := false

## Set before adding to the scene: belongs to the player's village.
var owned := false
## Set before adding to the scene: a newborn that grows up over time.
var child := false

## Current job: "", "lumber", "stone", "food" or "build".
var job := ""
## What the job works on: a tree, rock, construction site or the village.
var job_target: Node
var job_pos := Vector3.ZERO

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
var _working := false
var _work_phase := 0.0
var _age := 0.0
var _adult_scale := 1.0


func _ready() -> void:
	add_to_group("villagers")
	if goblin:
		add_to_group("goblins")
	if owned:
		add_to_group("people")
	_build_body()
	_timer = randf_range(0.0, 3.0)


func _build_body() -> void:
	if _looks.is_empty():
		_build_looks()
	var library := _goblin_looks if goblin else _looks
	var look: Dictionary = library[randi() % library.size()]
	_body = Node3D.new()
	add_child(_body)
	_add_mesh(look.body, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		_legs.append(_add_mesh(look.leg, Vector3(sx * 0.1, 0.8, 0.0)))
		_arms.append(_add_mesh(look.arm, Vector3(sx * 0.27, 1.33, 0.0)))
	_adult_scale = randf_range(0.72, 0.86) if goblin else randf_range(0.92, 1.08)
	scale = Vector3.ONE * _adult_scale * (CHILD_SCALE if child else 1.0)


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
				body.color = Color(0.86, 0.72, 0.36)
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

	for k in 6:
		var skin: Color = Art.GOBLIN_SKIN[k % Art.GOBLIN_SKIN.size()]
		var hide := Color(0.42, 0.28, 0.16).lerp(Color(0.5, 0.2, 0.2), rng.randf() * 0.6)
		var body := MeshBuilder.new()
		body.color = hide
		body.add_lathe(PackedVector2Array([Vector2(0.0, 0.62), Vector2(0.3, 0.62), Vector2(0.24, 1.0), Vector2(0.27, 1.25), Vector2(0.14, 1.4), Vector2(0.0, 1.42)]), 10)
		body.color = skin
		body.add_blob(Vector3(0.23, 0.21, 0.22), Transform3D(Basis(), Vector3(0, 1.56, 0.06)), null, 0.0, 6, 10)
		body.add_tube(PackedVector3Array([Vector3(0, 1.54, 0.24), Vector3(0, 1.48, 0.5)]), PackedFloat32Array([0.07, 0.02]), 6)
		for sx in [-1.0, 1.0]:
			var s: float = sx
			body.add_blob(Vector3(0.24, 0.1, 0.04), Transform3D(Basis(Vector3.BACK, s * 0.5), Vector3(s * 0.36, 1.66, 0.0)), null, 0.0, 4, 8)
			body.color = Color(0.98, 0.9, 0.3)
			body.add_blob(Vector3(0.05, 0.05, 0.03), Transform3D(Basis(), Vector3(s * 0.1, 1.62, 0.26)), null, 0.0, 4, 6)
			body.color = skin
		var leg := MeshBuilder.new()
		leg.color = skin.darkened(0.15)
		leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.09, 0.07]), 6)
		leg.add_blob(Vector3(0.09, 0.06, 0.16), Transform3D(Basis(), Vector3(0, -0.74, 0.06)), null, 0.0, 4, 8)
		var arm := MeshBuilder.new()
		arm.color = skin
		arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.62, 0)]), PackedFloat32Array([0.07, 0.05]), 6)
		arm.add_blob(Vector3(0.07, 0.08, 0.07), Transform3D(Basis(), Vector3(0, -0.66, 0)), null, 0.0, 4, 8)
		_goblin_looks.append({"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()})


func _process(delta: float) -> void:
	_moving = false
	if child and state != State.DEAD:
		_grow(delta)
	match state:
		State.IDLE:
			_timer -= delta
			if job != "":
				state = State.JOB
			elif _timer <= 0.0:
				_choose_wander_target()
		State.JOB:
			_update_job(delta)
		State.WALK:
			if _move_towards(_target, 1.3 * _speed_scale, delta):
				state = State.IDLE
				_timer = randf_range(4.0, 12.0) if goblin else randf_range(1.5, 5.0)
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


func _grow(delta: float) -> void:
	_age += delta
	var t := clampf(_age / GROW_SECONDS, 0.0, 1.0)
	scale = Vector3.ONE * _adult_scale * lerpf(CHILD_SCALE, 1.0, t)
	if t >= 1.0:
		child = false


func is_adult() -> bool:
	return not child


## True if the villager could start a job right now.
func can_work() -> bool:
	return owned and not child and state != State.DEAD and state != State.BURNING


func assign_job(kind: String, pos: Vector3, target: Node) -> void:
	job = kind
	job_target = target
	job_pos = pos
	_working = false
	if state == State.IDLE or state == State.WALK or state == State.JOB:
		state = State.JOB


func clear_job() -> void:
	job = ""
	job_target = null
	_working = false
	if state == State.JOB:
		state = State.IDLE
		_timer = randf_range(0.3, 1.0)


## True while the villager is at its job and working.
func is_working() -> bool:
	return state == State.JOB and _working


func _update_job(delta: float) -> void:
	var gone := not is_instance_valid(job_target)
	if not gone and job_target is Destructible:
		gone = (job_target as Destructible).destroyed
	if gone:
		clear_job()
		return
	if not _working:
		if _move_towards(job_pos, 1.7 * _speed_scale, delta):
			var gap := Vector2(job_pos.x - global_position.x, job_pos.z - global_position.z).length()
			if gap > 2.5:
				# Blocked by water or the island's edge: let the village pick another job.
				clear_job()
				return
			_working = true
		return
	var target_3d := job_target as Node3D
	if target_3d and job != "food":
		var to := target_3d.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 8.0))
	_work_phase += delta * 7.0
	if is_instance_valid(Game.village):
		Game.village.work(self, delta)


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
	if is_working():
		_animate_work(blend)
		return
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


## Chopping, digging, foraging and hammering poses.
func _animate_work(blend: float) -> void:
	var swing := 0.5 + 0.5 * sin(_work_phase)
	var lean := 0.0
	var arms := [0.0, 0.0]
	match job:
		"food":
			lean = 0.6
			arms = [-0.9 + 0.35 * sin(_work_phase), -0.9 + 0.35 * sin(_work_phase + 1.7)]
		"build":
			var hammer := 0.5 + 0.5 * sin(_work_phase * 1.6)
			lean = 0.12
			arms = [-2.3 + 1.3 * hammer, -0.5]
		_:
			lean = 0.3 * swing
			arms = [-2.5 + 1.6 * swing, -2.5 + 1.6 * swing]
	_body.position.y = lerpf(_body.position.y, 0.0, blend)
	_body.rotation.x = lerpf(_body.rotation.x, lean, blend)
	for k in 2:
		_legs[k].rotation.x = lerpf(_legs[k].rotation.x, 0.0, blend)
		_arms[k].rotation.x = lerpf(_arms[k].rotation.x, arms[k], blend)
		_arms[k].rotation.z = lerpf(_arms[k].rotation.z, (1.0 if k == 0 else -1.0) * -0.12, blend)


func is_alive() -> bool:
	return state != State.DEAD


func flee(from: Vector3) -> void:
	if state == State.DEAD or state == State.BURNING:
		return
	_danger = from
	_working = false
	state = State.FLEE
	_timer = randf_range(3.0, 6.0)


func catch_fire() -> void:
	if state == State.DEAD or state == State.BURNING or Game.fire.is_wet(global_position):
		return
	_working = false
	state = State.BURNING
	_timer = randf_range(3.0, 5.0)
	_set_burn(0.3)
	_fire = FireEmitter.new()
	_fire.size = 0.4
	_fire.with_light = false
	add_child(_fire)
	_fire.position.y = 1.0


## Rain puts a burning villager out before it burns up.
func douse() -> void:
	if state != State.BURNING:
		return
	state = State.IDLE
	_timer = randf_range(0.5, 1.5)
	_set_burn(0.15)
	if _fire:
		_fire.extinguish()
		_fire = null


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
	remove_from_group("people")
	job = ""
	job_target = null
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
