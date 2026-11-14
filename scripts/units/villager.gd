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
## their PlayerVillage: walk to a tree, rock, field or building site, work
## there, and carry what they gather back to the storehouse. Children are
## born small and grow up in GROW_SECONDS.
##
## Fighting: every grown-up villager and every goblin has the same health,
## damage and attack speed (HEALTH, ATTACK_DAMAGE, ATTACK_SECONDS). Goblins
## on a raid (group "raiders") march on the village and attack people, then
## buildings. Grown-ups fight back; children and strangers run. Soldiers
## (group "soldiers") have SOLDIER_HEALTH times the health and
## SOLDIER_DAMAGE times the damage, and go looking for raiders.

enum State { IDLE, WALK, FLEE, BURNING, DEAD, JOB, FIGHT, HELD }

const LOOKS := 14
const GROW_SECONDS := 60.0
const CHILD_SCALE := 0.45
## The same for grown-up villagers and goblins.
const HEALTH := 30.0
const ATTACK_DAMAGE := 6.0
const ATTACK_SECONDS := 1.0
const SOLDIER_HEALTH := 4.0
const SOLDIER_DAMAGE := 2.0
## How close an enemy must be before a fighter goes for it.
const AGGRO := 13.0
const SOLDIER_AGGRO := 60.0
## Units of a resource a worker gathers before walking it to the storehouse.
const CARRY_CAPACITY := 2.0
## Speed while wading through roots.
const SLOWED_SPEED := 0.25
## Wizards throw a firebolt every FIREBOLT_SECONDS at goblins within
## WIZARD_RANGE. That beats a soldier's sword (12 damage a second), and a
## bolt may set the goblin alight.
const WIZARD_RANGE := 16.0
const FIREBOLT_SECONDS := 0.7
const FIREBOLT_DAMAGE := 11.0

static var _looks: Array[Dictionary] = []
static var _goblin_looks: Array[Dictionary] = []
static var _soldier_looks: Array[Dictionary] = []
static var _wizard_looks: Array[Dictionary] = []
## Shared meshes: sword, shield and the loads workers carry.
static var _gear := {}

## Set before adding to the scene: goblins are green, big-eared and stay
## close to their cave.
var goblin := false

## Set before adding to the scene: belongs to the player's village.
var owned := false
## Set before adding to the scene: a newborn that grows up over time.
var child := false
## Trained at a Town guard: armoured, stronger, and does not work.
var soldier := false
## The Town guard building this soldier belongs to.
var guard: Node
## Trained at the Singing rocks: robed, makes magicko and throws firebolts.
var wizard := false
## A goblin on a night raid.
var raiding := false

var max_hp := HEALTH
var hp := HEALTH
var damage := ATTACK_DAMAGE
## Cannot walk until Game.now passes this (the roots spell, on goblins).
var snared_until := 0.0
## Walks at SLOWED_SPEED until Game.now passes this (roots, on your own people).
var slowed_until := 0.0

## Current job: "", "lumber", "stone", "food", "farm", "build" or "train".
var job := ""
## What the job works on: a tree, rock, field, construction site, Town
## guard or the village.
var job_target: Node
var job_pos := Vector3.ZERO
## What the worker is holding, on its way to the storehouse.
var carry := 0.0
var carry_kind := ""

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
var _torso: MeshInstance3D
var _legs: Array[MeshInstance3D] = []
var _arms: Array[MeshInstance3D] = []
var _meshes: Array[MeshInstance3D] = []
var _fire: FireEmitter
var _working := false
var _work_phase := 0.0
var _age := 0.0
var _adult_scale := 1.0
var _foe: Node3D
var _in_reach := false
var _attack_timer := 0.0
var _think_timer := randf() * 0.4
var _hit_flash := 0.0
var _raid_goal := Vector3.ZERO
## Which way a raider turns to get round water or the island's edge.
var _steer := 1.0 if randf() < 0.5 else -1.0
var _delivering := false
var _drop_pos := Vector3.ZERO
var _farm_timer := 0.0
var _load: MeshInstance3D
var _base_look := {}
var _gear_nodes: Array[Node3D] = []


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
	_base_look = look
	_body = Node3D.new()
	add_child(_body)
	_torso = _add_mesh(look.body, Vector3.ZERO)
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

	# Soldiers: leather armour, a steel helmet, a sword and a shield.
	var leather := Color(0.5, 0.31, 0.16)
	var steel := Color(0.72, 0.75, 0.8)
	for skin: Color in Art.SKIN_COLORS:
		var body := MeshBuilder.new()
		body.color = leather
		body.add_lathe(PackedVector2Array([Vector2(0.0, 0.58), Vector2(0.31, 0.58), Vector2(0.23, 1.0),
			Vector2(0.28, 1.3), Vector2(0.14, 1.44), Vector2(0.0, 1.46)]), 10)
		body.color = leather.darkened(0.45)
		body.add_lathe(PackedVector2Array([Vector2(0.235, 0.97), Vector2(0.255, 1.02), Vector2(0.235, 1.07)]), 10)
		body.add_lathe(PackedVector2Array([Vector2(0.27, 1.25), Vector2(0.32, 1.31), Vector2(0.23, 1.39)]), 10)
		body.color = skin
		body.add_blob(Vector3(0.15, 0.17, 0.16), Transform3D(Basis(), Vector3(0, 1.58, 0)), null, 0.0, 6, 10)
		body.color = steel
		body.add_lathe(PackedVector2Array([Vector2(0.0, 1.63), Vector2(0.25, 1.61), Vector2(0.25, 1.65), Vector2(0.185, 1.69),
			Vector2(0.14, 1.82), Vector2(0.0, 1.88)]), 10)
		body.add_box(Vector3(0.05, 0.16, 0.04), 0.01, Transform3D(Basis(), Vector3(0, 1.58, 0.165)))
		var leg := MeshBuilder.new()
		leg.color = Color(0.24, 0.2, 0.17)
		leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.095, 0.08]), 6)
		leg.color = leather.darkened(0.3)
		leg.add_tube(PackedVector3Array([Vector3(0, -0.45, 0), Vector3(0, -0.72, 0)]), PackedFloat32Array([0.1, 0.09]), 6)
		leg.add_blob(Vector3(0.09, 0.07, 0.15), Transform3D(Basis(), Vector3(0, -0.74, 0.05)), null, 0.0, 4, 8)
		var arm := MeshBuilder.new()
		arm.color = leather.lightened(0.1)
		arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.5, 0)]), PackedFloat32Array([0.085, 0.065]), 6)
		arm.color = skin
		arm.add_blob(Vector3(0.06, 0.07, 0.06), Transform3D(Basis(), Vector3(0, -0.55, 0)), null, 0.0, 4, 8)
		_soldier_looks.append({"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()})

	# The sword points forwards out of the hand; the shield faces sideways.
	var sword := MeshBuilder.new()
	sword.color = steel.lightened(0.2)
	sword.add_box(Vector3(0.04, 0.1, 0.7), 0.01, Transform3D(Basis(), Vector3(0, 0, 0.46)))
	sword.color = Color(0.78, 0.6, 0.2)
	sword.add_box(Vector3(0.26, 0.05, 0.05), 0.01, Transform3D(Basis(), Vector3(0, 0, 0.1)))
	_gear["sword"] = sword.commit()
	var shield := MeshBuilder.new()
	var sideways := Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO)
	shield.color = Color(0.62, 0.2, 0.16)
	shield.add_lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.31, 0.0), Vector2(0.31, 0.04), Vector2(0.0, 0.08)]), 10, sideways)
	shield.color = steel
	shield.add_lathe(PackedVector2Array([Vector2(0.1, 0.05), Vector2(0.07, 0.11), Vector2(0.0, 0.13)]), 8, sideways)
	_gear["shield"] = shield.commit()

	# Wizards: long robes and tall pointed hats in night colours.
	var robes := [Color(0.24, 0.2, 0.55), Color(0.36, 0.16, 0.5), Color(0.14, 0.3, 0.52), Color(0.5, 0.14, 0.3)]
	for k in robes.size():
		var robe: Color = robes[k]
		var skin: Color = Art.SKIN_COLORS[k % Art.SKIN_COLORS.size()]
		var body := MeshBuilder.new()
		body.color = robe
		body.add_lathe(PackedVector2Array([Vector2(0.0, 0.06), Vector2(0.36, 0.06), Vector2(0.22, 0.9),
			Vector2(0.25, 1.3), Vector2(0.13, 1.44), Vector2(0.0, 1.46)]), 12)
		body.color = Color(0.95, 0.8, 0.3)
		body.add_lathe(PackedVector2Array([Vector2(0.36, 0.06), Vector2(0.37, 0.12), Vector2(0.345, 0.16)]), 12)
		body.color = skin
		body.add_blob(Vector3(0.15, 0.17, 0.16), Transform3D(Basis(), Vector3(0, 1.58, 0)), null, 0.0, 6, 10)
		body.color = Color(0.9, 0.9, 0.92)
		body.add_blob(Vector3(0.11, 0.16, 0.07), Transform3D(Basis(), Vector3(0, 1.45, 0.12)), null, 0.0, 5, 8)
		body.color = robe.darkened(0.2)
		body.add_lathe(PackedVector2Array([Vector2(0.0, 1.66), Vector2(0.32, 1.65), Vector2(0.32, 1.68), Vector2(0.15, 1.73),
			Vector2(0.07, 2.1), Vector2(0.0, 2.4)]), 12)
		var leg := MeshBuilder.new()
		leg.color = robe.darkened(0.35)
		leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.08, 0.07]), 6)
		var arm := MeshBuilder.new()
		arm.color = robe
		arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.5, 0)]), PackedFloat32Array([0.1, 0.09]), 6)
		arm.color = skin
		arm.add_blob(Vector3(0.06, 0.07, 0.06), Transform3D(Basis(), Vector3(0, -0.55, 0)), null, 0.0, 4, 8)
		_wizard_looks.append({"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()})
	var staff := MeshBuilder.new()
	staff.color = Art.WOOD_DARK
	staff.add_tube(PackedVector3Array([Vector3(0, -0.7, 0), Vector3(0, 0.75, 0)]), PackedFloat32Array([0.035, 0.03]), 6)
	_gear["staff"] = staff.commit()
	var orb := MeshBuilder.new()
	orb.add_blob(Vector3(0.09, 0.09, 0.09), Transform3D(Basis(), Vector3(0, 0.83, 0)), null, 0.0, 6, 8)
	_gear["orb"] = orb.commit()

	# What workers carry on their backs.
	var logs := MeshBuilder.new()
	logs.color = Art.WOOD
	for z in [-0.07, 0.07]:
		logs.add_tube(PackedVector3Array([Vector3(-0.3, 0, z), Vector3(0.3, 0, z)]), PackedFloat32Array([0.065, 0.065]), 6)
	logs.add_tube(PackedVector3Array([Vector3(-0.3, 0.11, 0), Vector3(0.3, 0.11, 0)]), PackedFloat32Array([0.065, 0.065]), 6)
	_gear["lumber"] = logs.commit()
	var lump := MeshBuilder.new()
	lump.color = Color(0.62, 0.64, 0.68)
	lump.add_blob(Vector3(0.18, 0.15, 0.16), Transform3D.IDENTITY, null, 0.0, 5, 8)
	_gear["stone"] = lump.commit()
	var sack := MeshBuilder.new()
	sack.color = Color(0.88, 0.74, 0.36)
	sack.add_blob(Vector3(0.16, 0.2, 0.14), Transform3D.IDENTITY, null, 0.0, 5, 8)
	_gear["food"] = sack.commit()


func _process(delta: float) -> void:
	_moving = false
	if state == State.DEAD:
		_update_dead(delta)
		return
	if state == State.HELD:
		# Kicking in the tortoise's grip; it moves us about.
		_moving = true
		_animate(delta)
		return
	if child:
		_grow(delta)
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if _hit_flash <= 0.0:
			_set_tint(Color.WHITE)
	hp = minf(max_hp, hp + delta * 0.5)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.4
		_think()
	match state:
		State.IDLE:
			_timer -= delta
			if raiding:
				_target = _prowl_point()
				state = State.WALK
			elif job != "":
				state = State.JOB
			elif _timer <= 0.0:
				_choose_wander_target()
		State.JOB:
			_update_job(delta)
		State.FIGHT:
			_update_fight(delta)
		State.WALK:
			var pace := 2.6 if raiding else (1.8 if goblin else 1.3)
			if _move_towards(_target, pace * _speed_scale, delta):
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
	if state == State.DEAD:
		return
	var ground := Game.terrain.get_height(global_position.x, global_position.z)
	# Goblins swim across rivers and lakes.
	global_position.y = maxf(ground, Game.terrain.water_level_at(global_position.x, global_position.z) - 0.95 * scale.y) if goblin else ground
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
	return owned and not child and not soldier and not wizard and state != State.DEAD and state != State.BURNING and state != State.HELD


## Grown-up villagers of the player's village and goblins fight. Children
## and villagers of other villages run instead.
func can_fight() -> bool:
	return not child and (goblin or owned)


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
	if state == State.JOB and not _delivering:
		state = State.IDLE
		_timer = randf_range(0.3, 1.0)


## True while the villager is at its job and working.
func is_working() -> bool:
	return state == State.JOB and _working


func _update_job(delta: float) -> void:
	if _delivering:
		if _move_towards(_drop_pos, 1.7 * _speed_scale, delta):
			_unload()
			if job == "":
				clear_job()
		return
	if job == "":
		state = State.IDLE
		return
	var gone := not is_instance_valid(job_target)
	if not gone and job_target is Destructible:
		gone = (job_target as Destructible).destroyed
	if gone:
		clear_job()
		if carry > 0.01:
			_start_delivery()
		return
	if not _working:
		if _move_towards(job_pos, 1.7 * _speed_scale, delta):
			var gap := Vector2(job_pos.x - global_position.x, job_pos.z - global_position.z).length()
			if gap > 2.5:
				# Blocked by water or the island's edge: let the village pick another job.
				clear_job()
				return
			_working = true
			_farm_timer = randf_range(3.0, 6.0)
		return
	var target_3d := job_target as Node3D
	if job == "farm":
		# Work along the rows: move to a new spot in the field now and then.
		_farm_timer -= delta
		if _farm_timer <= 0.0:
			job_pos = (job_target as CropField).work_spot()
			_working = false
			return
	elif target_3d and job != "food":
		var to := target_3d.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 8.0))
	_work_phase += delta * 7.0
	if is_instance_valid(Game.village):
		Game.village.work(self, delta)


# --- Carrying -----------------------------------------------------------------

## Adds to what the worker is holding. A full load is walked to the
## storehouse before the resource counts.
func gather(kind: String, amount: float) -> void:
	if carry_kind != kind:
		_unload()
		carry_kind = kind
	carry += amount
	if carry >= CARRY_CAPACITY:
		_start_delivery()


func _start_delivery() -> void:
	if not is_instance_valid(Game.village):
		return
	_delivering = true
	_working = false
	_drop_pos = Game.village.drop_point(global_position)
	if _load == null:
		_load = MeshInstance3D.new()
		_load.material_override = Art.cloth()
		_load.position = Vector3(0.0, 1.22, -0.27)
		_body.add_child(_load)
	_load.mesh = _gear[carry_kind]
	_load.visible = true
	if state == State.IDLE or state == State.WALK:
		state = State.JOB


func _unload() -> void:
	if carry > 0.0 and is_instance_valid(Game.village):
		Game.village.give(carry_kind, carry)
	carry = 0.0
	_delivering = false
	if _load:
		_load.visible = false


# --- Soldiers -------------------------------------------------------------------

## Puts on leather armour and a helmet and picks up a sword and shield.
## `post` is where the soldier stands guard.
func become_soldier(post: Vector3) -> void:
	if soldier or goblin or state == State.DEAD:
		return
	_unload()
	clear_job()
	soldier = true
	add_to_group("soldiers")
	home = post
	home_radius = 9.0
	max_hp = HEALTH * SOLDIER_HEALTH
	hp = max_hp
	damage = ATTACK_DAMAGE * SOLDIER_DAMAGE
	_wear(_soldier_looks[randi() % _soldier_looks.size()])
	_add_gear("sword", _arms[0], Vector3(0.0, -0.55, 0.0))
	_add_gear("shield", _arms[1], Vector3(0.09, -0.36, 0.04))
	Game.effects.spawn_dust(global_position, 0.5)


func _add_gear(kind: String, parent: Node3D, pos: Vector3, material: Material = null) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _gear[kind]
	mi.material_override = material if material else Art.cloth()
	mi.position = pos
	parent.add_child(mi)
	_gear_nodes.append(mi)


func _wear(look: Dictionary) -> void:
	_torso.mesh = look.body
	for k in 2:
		_legs[k].mesh = look.leg
		_arms[k].mesh = look.arm


## Trained at the Singing rocks: a robe, a tall hat and a glowing staff.
func become_wizard(post: Vector3) -> void:
	if wizard or soldier or goblin or state == State.DEAD:
		return
	_unload()
	clear_job()
	wizard = true
	add_to_group("wizards")
	home = post
	home_radius = 10.0
	_wear(_wizard_looks[randi() % _wizard_looks.size()])
	_add_gear("staff", _arms[0], Vector3(0.0, -0.55, 0.08))
	_add_gear("orb", _arms[0], Vector3(0.0, -0.55, 0.08), Art.glow(3.0))
	Game.effects.spawn_dust(global_position, 0.5)


## A soldier or wizard goes back to ordinary work (and would have to train
## again to return).
func become_worker() -> void:
	if not (soldier or wizard) or state == State.DEAD:
		return
	for g in _gear_nodes:
		g.queue_free()
	_gear_nodes.clear()
	soldier = false
	wizard = false
	guard = null
	remove_from_group("soldiers")
	remove_from_group("wizards")
	max_hp = HEALTH
	hp = minf(hp, max_hp)
	damage = ATTACK_DAMAGE
	_wear(_base_look)
	_foe = null
	if state == State.FIGHT:
		state = State.IDLE
	if is_instance_valid(Game.village):
		home = Game.village.center
		home_radius = PlayerVillage.HOME_RADIUS


## Dies of hunger when the village has no food.
func starve() -> void:
	_die(false)


# --- Fighting -------------------------------------------------------------------

## Goblins: leave for the village. `goal` is where they gather.
func start_raid(goal: Vector3) -> void:
	if not goblin or state == State.DEAD or state == State.HELD or state == State.BURNING:
		return
	raiding = true
	add_to_group("raiders")
	_raid_goal = goal
	_target = goal
	state = State.WALK


## Goblins: the night is over, go home.
func end_raid() -> void:
	raiding = false
	remove_from_group("raiders")
	_foe = null
	if state == State.FIGHT or state == State.WALK or state == State.IDLE:
		var a := randf() * TAU
		_target = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 7.0)
		state = State.WALK


## Looks for someone to fight (or to run from), a few times a second.
func _think() -> void:
	if state == State.BURNING:
		return
	if goblin:
		if not raiding or (state == State.FIGHT and _foe_ok() and _foe is Villager):
			return
		var victim := _nearest_villager(AGGRO)
		if victim:
			_engage(victim)
		elif state != State.FIGHT and _flat_to(_raid_goal) < 22.0:
			var building := _nearest_building(24.0)
			if building:
				_engage(building)
		return
	var raiders := get_tree().get_nodes_in_group("raiders")
	if raiders.is_empty() or (state == State.FIGHT and _foe_ok()):
		return
	var fighter := can_fight()
	var best: Villager = null
	var best_d := SOLDIER_AGGRO if soldier or wizard else (AGGRO if fighter else 8.0)
	for node in raiders:
		var g := node as Villager
		var d := _flat_to(g.global_position)
		if d < best_d:
			best_d = d
			best = g
	if best == null:
		return
	if fighter:
		_engage(best)
	else:
		flee(best.global_position)


func _nearest_villager(reach: float) -> Villager:
	var best: Villager = null
	var best_d := reach
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v.goblin or v.state == State.DEAD:
			continue
		var d := _flat_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best


func _nearest_building(reach: float) -> Destructible:
	var best: Destructible = null
	var best_d := reach
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		var d := _flat_to(b.global_position)
		if d < best_d and not b.destroyed:
			best_d = d
			best = b
	return best


func _flat_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _prowl_point() -> Vector3:
	var a := randf() * TAU
	return _raid_goal + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 16.0)


func _engage(foe: Node3D) -> void:
	_foe = foe
	_working = false
	state = State.FIGHT


func _foe_ok() -> bool:
	if not is_instance_valid(_foe) or (goblin and not raiding):
		return false
	var v := _foe as Villager
	if v:
		return v.state != State.DEAD and v.state != State.HELD and (goblin or v.raiding)
	var b := _foe as Destructible
	return b != null and not b.destroyed


func _update_fight(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if not _foe_ok():
		_foe = null
		_in_reach = false
		state = State.IDLE
		_timer = 0.2
		return
	var to := _foe.global_position - global_position
	to.y = 0.0
	if wizard and _foe is Villager:
		_cast_at(_foe as Villager, to, delta)
		return
	var reach := 1.2
	var building := _foe as Destructible
	if building:
		reach = building.footprint * 0.8 + 0.8
	_in_reach = to.length() <= reach
	if not _in_reach:
		_move_towards(_foe.global_position, (3.0 if soldier else 2.6) * _speed_scale, delta)
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	if _attack_timer <= 0.0:
		_attack_timer = ATTACK_SECONDS
		if building:
			# Buildings are tough: goblins only chip at them.
			building.damage(damage * 0.5, global_position, 3.0)
		else:
			(_foe as Villager).take_hit(damage, self)


## Wizards keep their distance and throw firebolts.
func _cast_at(foe: Villager, to: Vector3, delta: float) -> void:
	_in_reach = to.length() <= WIZARD_RANGE
	if not _in_reach:
		_move_towards(foe.global_position, 2.4 * _speed_scale, delta)
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	if _attack_timer <= 0.0:
		_attack_timer = FIREBOLT_SECONDS
		var bolt := Firebolt.new()
		Game.world_root.add_child(bolt)
		bolt.launch(global_position + Vector3.UP * 1.9 * scale.y + to.normalized() * 0.4, foe, self)


## Loses health to a blow. Fighters hit back.
func take_hit(amount: float, from: Node3D) -> void:
	if state == State.DEAD or state == State.HELD:
		return
	hp -= amount
	_hit_flash = 0.15
	_set_tint(Color(2.2, 0.55, 0.45))
	if hp <= 0.0:
		_die(false)
		return
	var attacker := from as Villager
	if attacker and state != State.FIGHT and state != State.BURNING and can_fight():
		if goblin and not raiding:
			start_raid(global_position)
		_engage(attacker)


func _choose_wander_target() -> void:
	for attempt in 6:
		var a := randf() * TAU
		var d := randf() * home_radius
		var p := home + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if Game.terrain.is_dry(p.x, p.z):
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
	if Game.now < snared_until:
		# Held fast by roots.
		return false
	if Game.now < slowed_until:
		# Wading through roots.
		speed *= SLOWED_SPEED
	var step := to / dist * minf(speed * delta, dist)
	if not _open(global_position + step):
		if not raiding:
			return true
		# Raiders feel their way round the island's edge.
		var found := false
		for turn: float in [0.7, 1.4, -0.7, -1.4]:
			var side := step.rotated(Vector3.UP, turn * _steer)
			if _open(global_position + side):
				step = side
				found = true
				break
		if not found:
			return true
	var next := global_position + step
	global_position = Vector3(next.x, global_position.y, next.z)
	rotation.y = lerp_angle(rotation.y, atan2(step.x, step.z), minf(1.0, delta * 10.0))
	_moving = true
	return false


## True if the villager may stand at `p`. Only goblins go into the water.
func _open(p: Vector3) -> bool:
	var terrain := Game.terrain
	if not terrain.is_inside(p.x, p.z):
		return false
	return goblin or terrain.water_depth(p.x, p.z) < 0.15


func _animate(delta: float) -> void:
	var panicking := state == State.FLEE or state == State.BURNING or state == State.HELD
	var blend := minf(1.0, delta * 12.0)
	if is_working():
		_animate_work(blend)
		return
	if state == State.FIGHT and _in_reach:
		_animate_fight(blend)
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
		"food", "farm":
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


## The weapon arm winds up between blows and chops down on each one.
func _animate_fight(blend: float) -> void:
	var wind := smoothstep(0.25, 0.9, 1.0 - _attack_timer / ATTACK_SECONDS)
	_body.position.y = lerpf(_body.position.y, 0.0, blend)
	_body.rotation.x = lerpf(_body.rotation.x, 0.3 * (1.0 - wind), blend)
	for k in 2:
		var s := 1.0 if k == 0 else -1.0
		_legs[k].rotation.x = lerpf(_legs[k].rotation.x, 0.3 * s, blend)
		var arm := -0.4 - 2.3 * wind
		if wizard:
			# The staff is raised to throw; the other hand points.
			arm = -2.4 + 0.6 * wind if k == 0 else -1.5
		elif k == 1:
			# Soldiers keep the shield up; everyone else flails with both arms.
			arm = -1.1 if soldier else -0.4 - 2.3 * (1.0 - wind)
		_arms[k].rotation.x = lerpf(_arms[k].rotation.x, arm, minf(1.0, blend * 2.0))
		_arms[k].rotation.z = lerpf(_arms[k].rotation.z, s * -0.1, blend)


func is_alive() -> bool:
	return state != State.DEAD


func flee(from: Vector3) -> void:
	if state == State.DEAD or state == State.BURNING or state == State.HELD:
		return
	# Raiders, soldiers and anyone in a fight stand their ground.
	if raiding or soldier or state == State.FIGHT:
		return
	_danger = from
	_working = false
	state = State.FLEE
	_timer = randf_range(3.0, 6.0)


func catch_fire() -> void:
	if state == State.DEAD or state == State.BURNING or state == State.HELD or Game.fire.is_wet(global_position):
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


## Thrown through the air by an explosion (charred) or a stomp (not).
func fling(from: Vector3, force: float, charred := true) -> void:
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	_die(charred)
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


## Picked up by the tortoise, which carries the villager about until it
## calls toss() or eaten().
func grab() -> void:
	if state == State.DEAD:
		return
	if _fire:
		_fire.extinguish()
		_fire = null
	raiding = false
	remove_from_group("raiders")
	_foe = null
	_working = false
	state = State.HELD


## Thrown by the tortoise: dead on landing.
func toss(velocity: Vector3) -> void:
	_airborne = true
	_velocity = velocity
	state = State.IDLE
	_die(false)


## Swallowed whole.
func eaten() -> void:
	state = State.IDLE
	_die(false)
	queue_free()


func _set_burn(value: float) -> void:
	for mi in _meshes:
		mi.set_instance_shader_parameter("burn", value)


func _set_tint(color: Color) -> void:
	for mi in _meshes:
		mi.set_instance_shader_parameter("tint", color)


func _die(charred: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	for group in ["villagers", "people", "goblins", "raiders", "soldiers", "wizards"]:
		remove_from_group(group)
	raiding = false
	job = ""
	job_target = null
	_foe = null
	_timer = 0.0
	_set_tint(Color.WHITE)
	if _load:
		_load.visible = false
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
