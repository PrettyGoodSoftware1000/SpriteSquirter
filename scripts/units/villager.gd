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
##
## The dead lie where they fell for CORPSE_SECONDS (group "corpses") and
## leave the village a few bones. A necromancer (a wizard trained on,
## group "necromancers") raises one body at a time as a skeleton (group
## "skeletons"): see raise_skeleton().
##
## Villagers also climb ladders and cross rope bridges between treehouse
## Homes when one is on their way (State.CROSS, see RopeBridge), and
## goblins take the "build" job on their own buildings (see GoblinRaids).

enum State { IDLE, WALK, FLEE, BURNING, DEAD, JOB, FIGHT, HELD, RAISE, CROSS }

const LOOKS := 14
const GROW_SECONDS := 60.0
const CHILD_SCALE := 0.45
## The same for grown-up villagers and goblins.
static var HEALTH := 30.0
static var ATTACK_DAMAGE := 6.0
static var ATTACK_SECONDS := 1.0
static var SOLDIER_HEALTH := 4.0
static var SOLDIER_DAMAGE := 2.0
## How close an enemy must be before a fighter goes for it.
const AGGRO := 13.0
const SOLDIER_AGGRO := 60.0
## Units of a resource a worker gathers before walking it to the storehouse.
const CARRY_CAPACITY := 2.0
## The load a wheelbarrow takes, once the village has a Blacksmith.
const BARROW_CAPACITY := 6.0
## Archers shoot an arrow every ARROW_SECONDS at goblins within ARCHER_RANGE.
const ARCHER_RANGE := 22.0
static var ARROW_SECONDS := 1.5
static var ARROW_DAMAGE := 12.0
static var ARCHER_HEALTH := 1.5
## Speed while wading through roots.
const SLOWED_SPEED := 0.25
## Wizards throw a firebolt every FIREBOLT_SECONDS at goblins within
## WIZARD_RANGE. That beats a soldier's sword (12 damage a second), and a
## bolt may set the goblin alight.
const WIZARD_RANGE := 16.0
static var FIREBOLT_SECONDS := 0.7
static var FIREBOLT_DAMAGE := 11.0
## An ogre against a goblin.
static var OGRE_HEALTH := 10.0
static var OGRE_DAMAGE := 3.0
## Camera distances at which the detailed meshes switch on and off.
## Necromancers: how far they look for a body, how near they stand to
## raise it and how long the raising takes.
const RAISE_SIGHT := 32.0
const RAISE_REACH := 7.0
const RAISE_SECONDS := 2.0
## How long the dead lie where they fell before they sink away.
const CORPSE_SECONDS := 40.0

const LOD_NEAR := 58.0
const LOD_FAR := 66.0
## Small black shapes stand in for pen lines on faces and clothes.
const INK := Color(0.05, 0.04, 0.06)
const LEATHER := Color(0.5, 0.31, 0.16)
const STEEL := Color(0.72, 0.75, 0.8)
const STRAW := Color(0.86, 0.72, 0.36)
const SHOE := Color(0.2, 0.14, 0.1)
const GOBLIN_EYE := Color(0.98, 0.9, 0.3)

static var GOBLIN_HEALTH := 30.0
static var GOBLIN_DAMAGE := 6.0
static var GOBLIN_ATTACK_SECONDS := 1.0

static var _looks: Array[Dictionary] = []
static var _goblin_looks: Array[Dictionary] = []
static var _soldier_looks: Array[Dictionary] = []
static var _wizard_looks: Array[Dictionary] = []
static var _archer_looks: Array[Dictionary] = []
static var _ogre_look := {}
static var _necro_looks: Array[Dictionary] = []
## [warrior, archer]
static var _skeleton_looks: Array[Dictionary] = []
## Shared meshes: sword, shield, club, staff and the workers' wheelbarrows.
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
## Trained at a Town guard once bows are researched: shoots from a distance.
var archer := false
## A goblin on a night raid.
var raiding := false
## Set before adding to the scene, together with `goblin`: a huge goblin
## with a club, OGRE_HEALTH times the health and OGRE_DAMAGE times the damage.
var ogre := false
## A wizard trained on at a Necromancer tower: it raises the dead.
var necromancer := false
## Raised by a necromancer: fights for the village until it crumbles. It is
## `owned` (the creature and its fireballs spare it) but is not one of the
## "people": it does not eat, work or count as a villager.
var skeleton := false

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
## Wheeling the load home in a barrow (rather than carrying it).
var _pushing := false
var _base_look := {}
var _gear_nodes: Array[Node3D] = []
var _look := {}
var _near := false
## Skeletons keep the size of whoever they were, and fall apart at `_expires`.
var _fixed_scale := 0.0
var _expires := 0.0
## Necromancers: the skeleton they have up, and the body they are raising.
var _minion: Villager
var _raise_target: Villager
var _raise_timer := 0.0
var _raise_walk := 0.0
var _raise_ready := 0.0
## Crossing a rope bridge: the way, how far along it, and when the villager
## may next take one.
var _route := PackedVector3Array()
var _route_i := 0
var _bridge: RopeBridge
var _cross_time := 0.0
var _cross_cool := 0.0


## Takes the fighting numbers from balancing.txt (see Balance). The ones
## above that are multipliers are worked out from the file's plain numbers.
static func apply_balance() -> void:
	HEALTH = Balance.num("villager_health")
	ATTACK_DAMAGE = Balance.num("villager_damage")
	ATTACK_SECONDS = Balance.num("villager_attack_seconds")
	SOLDIER_HEALTH = Balance.num("warrior_health") / HEALTH
	SOLDIER_DAMAGE = Balance.num("warrior_damage") / ATTACK_DAMAGE
	ARCHER_HEALTH = Balance.num("archer_health") / HEALTH
	ARROW_DAMAGE = Balance.num("archer_arrow_damage")
	ARROW_SECONDS = Balance.num("archer_arrow_seconds")
	FIREBOLT_DAMAGE = Balance.num("wizard_firebolt_damage")
	FIREBOLT_SECONDS = Balance.num("wizard_firebolt_seconds")
	GOBLIN_HEALTH = Balance.num("goblin_health")
	GOBLIN_DAMAGE = Balance.num("goblin_damage")
	GOBLIN_ATTACK_SECONDS = Balance.num("goblin_attack_seconds")
	OGRE_HEALTH = Balance.num("ogre_health") / GOBLIN_HEALTH
	OGRE_DAMAGE = Balance.num("ogre_damage") / GOBLIN_DAMAGE


func _ready() -> void:
	if goblin:
		max_hp = GOBLIN_HEALTH
		hp = max_hp
		damage = GOBLIN_DAMAGE
	if skeleton:
		hp = max_hp
		add_to_group("skeletons")
	add_to_group("villagers")
	if goblin:
		add_to_group("goblins")
	if ogre:
		add_to_group("ogres")
	if owned and not skeleton:
		add_to_group("people")
	_build_body()
	_timer = randf_range(0.0, 3.0)


func _build_body() -> void:
	if _looks.is_empty():
		_build_looks()
	if ogre:
		_look = _ogre_look
	elif skeleton:
		_look = _skeleton_looks[1 if archer else 0]
	else:
		var library := _goblin_looks if goblin else _looks
		_look = library[randi() % library.size()]
	_base_look = _look
	_body = Node3D.new()
	add_child(_body)
	var leg_x: float = _look.get("leg_x", 0.1)
	var arm_x: float = _look.get("arm_x", 0.27)
	_torso = _add_mesh(_look.body, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		_legs.append(_add_mesh(_look.leg, Vector3(sx * leg_x, 0.8, 0.0)))
		_arms.append(_add_mesh(_look.arm, Vector3(sx * arm_x, 1.33, 0.0)))
	_adult_scale = randf_range(0.72, 0.86) if goblin else randf_range(0.92, 1.08)
	if ogre:
		_adult_scale = randf_range(2.2, 2.5)
		max_hp = GOBLIN_HEALTH * OGRE_HEALTH
		hp = max_hp
		damage = GOBLIN_DAMAGE * OGRE_DAMAGE
		_add_gear("club", _arms[0], Vector3(0.0, -0.85, 0.03))
	if skeleton:
		if _fixed_scale > 0.0:
			_adult_scale = _fixed_scale
		if archer:
			_add_gear("bow", _arms[1], Vector3(0.0, -0.55, 0.0))
		else:
			_add_gear("rusty_sword", _arms[0], Vector3(0.0, -0.55, 0.0))
	scale = Vector3.ONE * _adult_scale * (CHILD_SCALE if child else 1.0)


func _add_mesh(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Art.cloth()
	mi.position = pos
	_body.add_child(mi)
	_meshes.append(mi)
	return mi


## Swaps between the detailed meshes (camera close) and the simple ones.
func _apply_lod(near: bool) -> void:
	_near = near
	var suffix := "_hi" if near and _look.has("body_hi") else ""
	_torso.mesh = _look["body" + suffix]
	for k in 2:
		_legs[k].mesh = _look["leg" + suffix]
		_arms[k].mesh = _look["arm" + suffix]


# --- Looks ----------------------------------------------------------------------
# Every look is a dictionary of meshes: body, leg and arm for far away, and
# body_hi, leg_hi and arm_hi for close up. The detailed ones have faces,
# hands, trims and seams, with small black shapes standing in for ink lines.

static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## A dark band round the body: `r` is the body's radius at height `y`.
static func _band(mb: MeshBuilder, r: float, y: float, half: float, out := 0.012, segments := 16) -> void:
	mb.add_lathe(PackedVector2Array([Vector2(r, y - half), Vector2(r + out, y), Vector2(r, y + half)]), segments)


## Ears, nose and inked eyes, brows and mouth on a head centred at height
## `y` whose face is `z` in front of the neck.
static func _face(mb: MeshBuilder, skin: Color, y: float, z: float, grim := false) -> void:
	mb.color = skin
	for sx in [-1.0, 1.0]:
		var s: float = sx
		mb.add_blob(Vector3(0.03, 0.05, 0.035), _at(s * 0.155, y, 0.0), null, 0.0, 4, 6)
	mb.color = skin.darkened(0.14)
	mb.add_blob(Vector3(0.028, 0.034, 0.04), _at(0.0, y - 0.015, z + 0.01), null, 0.0, 4, 6)
	mb.color = INK
	for sx in [-1.0, 1.0]:
		var s: float = sx
		mb.add_blob(Vector3(0.021, 0.03, 0.012), _at(s * 0.058, y + 0.025, z - 0.014), null, 0.0, 4, 6)
		mb.add_box(Vector3(0.06, 0.013, 0.012), 0.003,
			Transform3D(Basis(Vector3.BACK, s * (0.3 if grim else -0.12)), Vector3(s * 0.058, y + 0.073, z - 0.017)))
	mb.add_box(Vector3(0.075 if grim else 0.06, 0.013, 0.012), 0.003, _at(0.0, y - 0.072, z - 0.016))


static func _villager_far(c: Dictionary) -> Dictionary:
	var body := MeshBuilder.new()
	body.color = c.tunic
	var hem: float = 0.35 if c.skirt else 0.72
	body.add_lathe(PackedVector2Array([Vector2(0.0, hem), Vector2(0.33 if c.skirt else 0.25, hem), Vector2(0.21, 1.0),
		Vector2(0.24, 1.3), Vector2(0.13, 1.44), Vector2(0.0, 1.46)]), 10)
	body.color = c.tunic.darkened(0.45)
	_band(body, 0.225, 1.02, 0.04, 0.015, 10)
	body.color = c.skin
	body.add_blob(Vector3(0.15, 0.17, 0.16), _at(0, 1.58, 0), null, 0.0, 6, 10)
	match c.hat:
		0: # Pointed hat
			body.color = c.hat_color
			body.add_lathe(PackedVector2Array([Vector2(0.0, 1.66), Vector2(0.27, 1.66), Vector2(0.27, 1.69), Vector2(0.15, 1.72),
				Vector2(0.08, 1.92), Vector2(0.0, 2.08)]), 10)
		1: # Straw hat
			body.color = STRAW
			body.add_lathe(PackedVector2Array([Vector2(0.0, 1.66), Vector2(0.36, 1.64), Vector2(0.36, 1.67), Vector2(0.16, 1.71),
				Vector2(0.13, 1.8), Vector2(0.0, 1.83)]), 10)
		2: # Hood
			body.color = c.tunic.darkened(0.25)
			body.add_blob(Vector3(0.19, 0.2, 0.2), _at(0, 1.6, -0.04), null, 0.0, 6, 10)
		_: # Bare head with hair
			body.color = c.hair
			body.add_blob(Vector3(0.165, 0.14, 0.175), _at(0, 1.64, -0.03), null, 0.0, 6, 10)
	var leg := MeshBuilder.new()
	leg.color = c.trousers
	leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.095, 0.07]), 6)
	leg.color = SHOE
	leg.add_blob(Vector3(0.08, 0.06, 0.14), _at(0, -0.74, 0.05), null, 0.0, 4, 8)
	var arm := MeshBuilder.new()
	arm.color = c.tunic.darkened(0.1)
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.5, 0)]), PackedFloat32Array([0.075, 0.055]), 6)
	arm.color = c.skin
	arm.add_blob(Vector3(0.06, 0.07, 0.06), _at(0, -0.55, 0), null, 0.0, 4, 8)
	return {"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()}


static func _villager_near(c: Dictionary) -> Dictionary:
	var body := MeshBuilder.new()
	var hem: float = 0.35 if c.skirt else 0.7
	var flare: float = 0.35 if c.skirt else 0.26
	body.color = c.tunic
	body.add_lathe(PackedVector2Array([Vector2(0.0, hem), Vector2(flare, hem), Vector2(flare - 0.02, hem + 0.1), Vector2(0.205, 0.98),
		Vector2(0.215, 1.08), Vector2(0.25, 1.27), Vector2(0.21, 1.39), Vector2(0.1, 1.45), Vector2(0.0, 1.46)]), 16)
	# Dark trim at the hem and collar, a belt with a buckle, an inked seam.
	body.color = c.tunic.darkened(0.55)
	_band(body, flare - 0.004, hem + 0.035, 0.035, 0.018)
	_band(body, 0.1, 1.465, 0.035, 0.03, 12)
	body.color = Color(0.2, 0.13, 0.09)
	_band(body, 0.212, 1.02, 0.045, 0.024)
	body.color = Color(0.92, 0.74, 0.25)
	body.add_box(Vector3(0.07, 0.07, 0.03), 0.01, _at(0, 1.02, 0.232))
	body.color = INK
	body.add_box(Vector3(0.012, 0.2, 0.012), 0.003, Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(0, 1.185, 0.238)))
	body.color = c.skin
	body.add_tube(PackedVector3Array([Vector3(0, 1.4, 0), Vector3(0, 1.5, 0)]), PackedFloat32Array([0.075, 0.07]), 8)
	body.add_blob(Vector3(0.155, 0.175, 0.165), _at(0, 1.6, 0), null, 0.0, 8, 12)
	_face(body, c.skin, 1.6, 0.165)
	match c.hat:
		0: # Pointed hat with a brim, a band and a flopping tip
			body.color = c.hat_color
			body.add_lathe(PackedVector2Array([Vector2(0.0, 1.67), Vector2(0.3, 1.655), Vector2(0.3, 1.685), Vector2(0.16, 1.72)]), 16)
			var cone := body.add_lathe(PackedVector2Array([Vector2(0.16, 1.72), Vector2(0.13, 1.84), Vector2(0.07, 1.99), Vector2(0.0, 2.13)]), 12)
			body.bend(cone, 1.72, 2.13, Vector3(0.0, -0.04, -0.16))
			body.color = c.hat_color.darkened(0.55)
			_band(body, 0.158, 1.75, 0.028, 0.014)
		1: # Straw hat with a ribbon
			body.color = STRAW
			body.add_lathe(PackedVector2Array([Vector2(0.0, 1.66), Vector2(0.38, 1.63), Vector2(0.385, 1.66), Vector2(0.17, 1.71),
				Vector2(0.14, 1.8), Vector2(0.0, 1.83)]), 16)
			body.color = STRAW.darkened(0.35)
			_band(body, 0.383, 1.645, 0.016, 0.008)
			body.color = c.hat_color
			_band(body, 0.162, 1.735, 0.028, 0.014)
		2: # Hood with a dark rim round the face
			body.color = c.tunic.darkened(0.25)
			body.add_blob(Vector3(0.195, 0.205, 0.2), _at(0, 1.605, -0.045), null, 0.0, 8, 12)
			body.add_tube(PackedVector3Array([Vector3(0, 1.72, -0.2), Vector3(0, 1.62, -0.3)]), PackedFloat32Array([0.07, 0.015]), 6)
			body.color = c.tunic.darkened(0.6)
			body.add_ring(0.158, 0.016, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.61, 0.105)), 14, 5)
		_: # Hair: a cap, a fringe and sometimes a bun
			body.color = c.hair
			body.add_blob(Vector3(0.168, 0.14, 0.178), _at(0, 1.655, -0.03), null, 0.0, 8, 12)
			for x: float in [-0.085, 0.0, 0.085]:
				body.add_blob(Vector3(0.06, 0.04, 0.05), _at(x, 1.71, 0.105), null, 0.0, 4, 6)
			if c.skirt:
				body.add_blob(Vector3(0.075, 0.075, 0.075), _at(0, 1.72, -0.17), null, 0.0, 5, 8)
	var leg := MeshBuilder.new()
	leg.color = c.trousers
	leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.36, 0.02), Vector3(0, -0.7, 0)]), PackedFloat32Array([0.1, 0.085, 0.07]), 8)
	leg.color = c.trousers.darkened(0.5)
	_band(leg, 0.07, -0.665, 0.025, 0.014, 8)
	leg.color = SHOE
	leg.add_blob(Vector3(0.085, 0.065, 0.15), _at(0, -0.735, 0.055), null, 0.0, 5, 8)
	leg.color = INK
	leg.add_box(Vector3(0.15, 0.02, 0.27), 0.006, _at(0, -0.79, 0.055))
	var arm := MeshBuilder.new()
	arm.color = c.tunic.darkened(0.1)
	arm.add_blob(Vector3(0.095, 0.09, 0.095), _at(0, -0.02, 0), null, 0.0, 5, 8)
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.26, -0.015), Vector3(0, -0.47, 0)]), PackedFloat32Array([0.08, 0.068, 0.06]), 8)
	arm.color = c.tunic.darkened(0.55)
	_band(arm, 0.06, -0.455, 0.025, 0.014, 8)
	arm.color = c.skin
	arm.add_blob(Vector3(0.058, 0.07, 0.058), _at(0, -0.54, 0), null, 0.0, 5, 8)
	arm.add_blob(Vector3(0.022, 0.035, 0.022), _at(0, -0.53, 0.055), null, 0.0, 4, 6)
	return {"body_hi": body.commit(), "leg_hi": leg.commit(), "arm_hi": arm.commit()}


static func _goblin_far(skin: Color, hide: Color) -> Dictionary:
	var body := MeshBuilder.new()
	body.color = hide
	body.add_lathe(PackedVector2Array([Vector2(0.0, 0.62), Vector2(0.3, 0.62), Vector2(0.24, 1.0), Vector2(0.27, 1.25), Vector2(0.14, 1.4), Vector2(0.0, 1.42)]), 10)
	body.color = skin
	body.add_blob(Vector3(0.23, 0.21, 0.22), _at(0, 1.56, 0.06), null, 0.0, 6, 10)
	body.add_tube(PackedVector3Array([Vector3(0, 1.54, 0.24), Vector3(0, 1.48, 0.5)]), PackedFloat32Array([0.07, 0.02]), 6)
	for sx in [-1.0, 1.0]:
		var s: float = sx
		body.add_blob(Vector3(0.24, 0.1, 0.04), Transform3D(Basis(Vector3.BACK, s * 0.5), Vector3(s * 0.36, 1.66, 0.0)), null, 0.0, 4, 8)
		body.color = GOBLIN_EYE
		body.add_blob(Vector3(0.05, 0.05, 0.03), _at(s * 0.1, 1.62, 0.26), null, 0.0, 4, 6)
		body.color = skin
	var leg := MeshBuilder.new()
	leg.color = skin.darkened(0.15)
	leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.09, 0.07]), 6)
	leg.add_blob(Vector3(0.09, 0.06, 0.16), _at(0, -0.74, 0.06), null, 0.0, 4, 8)
	var arm := MeshBuilder.new()
	arm.color = skin
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.62, 0)]), PackedFloat32Array([0.07, 0.05]), 6)
	arm.add_blob(Vector3(0.07, 0.08, 0.07), _at(0, -0.66, 0), null, 0.0, 4, 8)
	return {"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()}


static func _goblin_near(skin: Color, hide: Color) -> Dictionary:
	var bone := Color(0.93, 0.9, 0.8)
	var body := MeshBuilder.new()
	# A ragged hide tunic, a rope belt and a necklace of teeth.
	body.color = hide
	body.add_lathe(PackedVector2Array([Vector2(0.0, 0.6), Vector2(0.31, 0.6), Vector2(0.29, 0.72), Vector2(0.235, 1.0), Vector2(0.25, 1.12),
		Vector2(0.275, 1.26), Vector2(0.2, 1.38), Vector2(0.1, 1.42), Vector2(0.0, 1.43)]), 14, Transform3D.IDENTITY, 7, 0.035)
	body.color = hide.darkened(0.55)
	_band(body, 0.24, 1.03, 0.04, 0.03, 14)
	body.color = bone
	for k in 5:
		var a := (k - 2) * 0.38
		body.add_blob(Vector3(0.026, 0.042, 0.026), _at(sin(a) * 0.25, 1.3 + 0.02 * absf(k - 2), cos(a) * 0.25), null, 0.0, 4, 6)
	# A big head: long nose, heavy brow, slit eyes, a wide mouth with fangs.
	body.color = skin
	body.add_blob(Vector3(0.235, 0.215, 0.225), _at(0, 1.56, 0.06), null, 0.0, 8, 12)
	body.add_blob(Vector3(0.15, 0.09, 0.12), _at(0, 1.43, 0.14), null, 0.0, 5, 8)
	body.color = skin.darkened(0.12)
	body.add_tube(PackedVector3Array([Vector3(0, 1.55, 0.26), Vector3(0, 1.5, 0.42), Vector3(0, 1.46, 0.52)]), PackedFloat32Array([0.075, 0.05, 0.02]), 8)
	for sx in [-1.0, 1.0]:
		var s: float = sx
		body.color = skin
		body.add_tube(PackedVector3Array([Vector3(s * 0.2, 1.6, 0.02), Vector3(s * 0.38, 1.68, -0.02), Vector3(s * 0.56, 1.8, -0.08)]),
			PackedFloat32Array([0.085, 0.06, 0.012]), 6)
		body.color = skin.darkened(0.45)
		body.add_blob(Vector3(0.05, 0.03, 0.02), _at(s * 0.34, 1.665, 0.035), null, 0.0, 4, 6)
		body.color = GOBLIN_EYE
		body.add_blob(Vector3(0.062, 0.066, 0.03), _at(s * 0.105, 1.62, 0.262), null, 0.0, 5, 8)
		body.color = bone
		body.add_tube(PackedVector3Array([Vector3(s * 0.07, 1.455, 0.27), Vector3(s * 0.075, 1.51, 0.275)]), PackedFloat32Array([0.02, 0.004]), 5)
		body.color = INK
		body.add_blob(Vector3(0.016, 0.045, 0.014), _at(s * 0.1, 1.62, 0.29), null, 0.0, 4, 6)
		body.add_box(Vector3(0.13, 0.024, 0.03), 0.006, Transform3D(Basis(Vector3.BACK, s * 0.45), Vector3(s * 0.105, 1.69, 0.258)))
	body.color = INK
	body.add_box(Vector3(0.22, 0.016, 0.014), 0.004, _at(0, 1.455, 0.262))
	var leg := MeshBuilder.new()
	leg.color = skin.darkened(0.15)
	leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.36, 0.04), Vector3(0, -0.7, 0)]), PackedFloat32Array([0.095, 0.08, 0.07]), 8)
	leg.add_blob(Vector3(0.1, 0.06, 0.17), _at(0, -0.74, 0.07), null, 0.0, 5, 8)
	leg.color = INK
	for x: float in [-0.06, 0.0, 0.06]:
		leg.add_blob(Vector3(0.022, 0.022, 0.04), _at(x, -0.75, 0.23), null, 0.0, 4, 6)
	var arm := MeshBuilder.new()
	arm.color = skin
	arm.add_blob(Vector3(0.09, 0.085, 0.09), _at(0, -0.02, 0), null, 0.0, 5, 8)
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.32, -0.02), Vector3(0, -0.6, 0.02)]), PackedFloat32Array([0.075, 0.06, 0.05]), 8)
	arm.add_blob(Vector3(0.075, 0.085, 0.075), _at(0, -0.66, 0.02), null, 0.0, 5, 8)
	arm.color = hide.darkened(0.3)
	_band(arm, 0.05, -0.53, 0.03, 0.016, 8)
	arm.color = INK
	for x: float in [-0.045, 0.0, 0.045]:
		arm.add_blob(Vector3(0.018, 0.04, 0.018), _at(x, -0.75, 0.03), null, 0.0, 4, 6)
	return {"body_hi": body.commit(), "leg_hi": leg.commit(), "arm_hi": arm.commit()}


static func _soldier_far(skin: Color) -> Dictionary:
	var body := MeshBuilder.new()
	body.color = LEATHER
	body.add_lathe(PackedVector2Array([Vector2(0.0, 0.58), Vector2(0.31, 0.58), Vector2(0.23, 1.0),
		Vector2(0.28, 1.3), Vector2(0.14, 1.44), Vector2(0.0, 1.46)]), 10)
	body.color = LEATHER.darkened(0.45)
	_band(body, 0.235, 1.02, 0.05, 0.02, 10)
	body.color = skin
	body.add_blob(Vector3(0.15, 0.17, 0.16), _at(0, 1.58, 0), null, 0.0, 6, 10)
	body.color = STEEL
	body.add_lathe(PackedVector2Array([Vector2(0.0, 1.63), Vector2(0.25, 1.61), Vector2(0.25, 1.65), Vector2(0.185, 1.69),
		Vector2(0.14, 1.82), Vector2(0.0, 1.88)]), 10)
	var leg := MeshBuilder.new()
	leg.color = Color(0.24, 0.2, 0.17)
	leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.095, 0.08]), 6)
	leg.color = LEATHER.darkened(0.3)
	leg.add_blob(Vector3(0.09, 0.07, 0.15), _at(0, -0.74, 0.05), null, 0.0, 4, 8)
	var arm := MeshBuilder.new()
	arm.color = LEATHER.lightened(0.1)
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.5, 0)]), PackedFloat32Array([0.085, 0.065]), 6)
	arm.color = skin
	arm.add_blob(Vector3(0.06, 0.07, 0.06), _at(0, -0.55, 0), null, 0.0, 4, 8)
	return {"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()}


static func _soldier_near(skin: Color) -> Dictionary:
	var body := MeshBuilder.new()
	# A leather jerkin with a skirt of straps, stitched in rows.
	body.color = LEATHER
	body.add_lathe(PackedVector2Array([Vector2(0.0, 0.58), Vector2(0.32, 0.58), Vector2(0.3, 0.7), Vector2(0.235, 1.0), Vector2(0.24, 1.1),
		Vector2(0.285, 1.3), Vector2(0.22, 1.4), Vector2(0.11, 1.45), Vector2(0.0, 1.46)]), 16, Transform3D.IDENTITY, 8, 0.02)
	body.color = LEATHER.darkened(0.65)
	_band(body, 0.252, 1.15, 0.012, 0.008)
	_band(body, 0.27, 1.23, 0.012, 0.008)
	_band(body, 0.31, 0.64, 0.014, 0.008)
	body.color = Color(0.2, 0.13, 0.09)
	_band(body, 0.24, 1.03, 0.045, 0.024)
	body.color = STEEL
	body.add_box(Vector3(0.08, 0.08, 0.03), 0.01, _at(0, 1.03, 0.262))
	body.color = LEATHER.lightened(0.1)
	for sx in [-1.0, 1.0]:
		var s: float = sx
		body.add_blob(Vector3(0.13, 0.075, 0.125), _at(s * 0.27, 1.37, 0.0), null, 0.0, 5, 8)
	body.color = skin
	body.add_tube(PackedVector3Array([Vector3(0, 1.4, 0), Vector3(0, 1.5, 0)]), PackedFloat32Array([0.075, 0.07]), 8)
	body.add_blob(Vector3(0.155, 0.175, 0.165), _at(0, 1.6, 0), null, 0.0, 8, 12)
	_face(body, skin, 1.6, 0.165, true)
	# A steel helmet with a rim, a nose guard and a red crest.
	body.color = STEEL
	body.add_lathe(PackedVector2Array([Vector2(0.0, 1.64), Vector2(0.2, 1.63), Vector2(0.255, 1.6), Vector2(0.26, 1.635), Vector2(0.19, 1.69),
		Vector2(0.15, 1.81), Vector2(0.06, 1.88), Vector2(0.0, 1.89)]), 16)
	body.add_box(Vector3(0.045, 0.17, 0.035), 0.008, _at(0, 1.6, 0.19))
	body.color = INK
	_band(body, 0.188, 1.7, 0.012, 0.01)
	body.color = Color(0.74, 0.15, 0.12)
	body.add_box(Vector3(0.035, 0.07, 0.3), 0.01, _at(0, 1.9, -0.01))
	var leg := MeshBuilder.new()
	leg.color = Color(0.24, 0.2, 0.17)
	leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.36, 0.02), Vector3(0, -0.5, 0.0)]), PackedFloat32Array([0.1, 0.088, 0.085]), 8)
	leg.color = LEATHER.darkened(0.3)
	leg.add_tube(PackedVector3Array([Vector3(0, -0.42, 0), Vector3(0, -0.72, 0)]), PackedFloat32Array([0.1, 0.088]), 8)
	leg.add_blob(Vector3(0.09, 0.07, 0.155), _at(0, -0.735, 0.055), null, 0.0, 5, 8)
	leg.color = INK
	_band(leg, 0.1, -0.425, 0.014, 0.008, 8)
	leg.add_box(Vector3(0.16, 0.02, 0.28), 0.006, _at(0, -0.795, 0.055))
	var arm := MeshBuilder.new()
	arm.color = LEATHER.lightened(0.1)
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.26, -0.015), Vector3(0, -0.32, -0.01)]), PackedFloat32Array([0.085, 0.072, 0.07]), 8)
	arm.color = STEEL
	arm.add_tube(PackedVector3Array([Vector3(0, -0.3, -0.01), Vector3(0, -0.47, 0)]), PackedFloat32Array([0.072, 0.064]), 8)
	arm.color = INK
	_band(arm, 0.072, -0.3, 0.012, 0.008, 8)
	arm.color = skin
	arm.add_blob(Vector3(0.058, 0.07, 0.058), _at(0, -0.54, 0), null, 0.0, 5, 8)
	arm.add_blob(Vector3(0.022, 0.035, 0.022), _at(0, -0.53, 0.055), null, 0.0, 4, 6)
	return {"body_hi": body.commit(), "leg_hi": leg.commit(), "arm_hi": arm.commit()}


## The ogre: a pot-bellied brute, more than twice a goblin's height, with
## tusks and a spiked wooden club. Always drawn in full detail.
static func _build_ogre() -> void:
	var skin := Color(0.5, 0.56, 0.34)
	var hide := Color(0.4, 0.25, 0.15)
	var bone := Color(0.93, 0.9, 0.8)
	var body := MeshBuilder.new()
	body.color = skin
	body.add_lathe(PackedVector2Array([Vector2(0.0, 0.62), Vector2(0.36, 0.62), Vector2(0.5, 0.9), Vector2(0.52, 1.1), Vector2(0.46, 1.32),
		Vector2(0.3, 1.5), Vector2(0.12, 1.56), Vector2(0.0, 1.57)]), 16)
	body.color = hide
	body.add_lathe(PackedVector2Array([Vector2(0.0, 0.5), Vector2(0.42, 0.5), Vector2(0.45, 0.7), Vector2(0.53, 0.92), Vector2(0.5, 0.96)]),
		16, Transform3D.IDENTITY, 8, 0.04)
	body.color = hide.darkened(0.55)
	_band(body, 0.525, 0.95, 0.05, 0.03)
	# A skull for a belt buckle, an inked line under the chest, a navel.
	body.color = bone
	body.add_blob(Vector3(0.09, 0.1, 0.06), _at(0, 0.95, 0.55), null, 0.0, 5, 8)
	body.color = INK
	for sx in [-1.0, 1.0]:
		var s: float = sx
		body.add_blob(Vector3(0.022, 0.028, 0.012), _at(s * 0.035, 0.968, 0.603), null, 0.0, 4, 6)
		body.add_box(Vector3(0.2, 0.016, 0.016), 0.004, Transform3D(Basis(Vector3.BACK, -s * 0.2) * Basis(Vector3.UP, s * 0.3), Vector3(s * 0.12, 1.33, 0.44)))
	body.add_blob(Vector3(0.022, 0.03, 0.012), _at(0, 1.12, 0.522), null, 0.0, 4, 6)
	# A small head sunk between the shoulders, with an underbite and tusks.
	body.color = skin
	body.add_blob(Vector3(0.22, 0.2, 0.21), _at(0, 1.66, 0.12), null, 0.0, 8, 12)
	body.color = skin.darkened(0.1)
	body.add_blob(Vector3(0.2, 0.11, 0.17), _at(0, 1.56, 0.2), null, 0.0, 6, 10)
	body.add_blob(Vector3(0.06, 0.05, 0.06), _at(0, 1.68, 0.33), null, 0.0, 4, 6)
	body.color = skin.darkened(0.35)
	body.add_blob(Vector3(0.2, 0.045, 0.08), _at(0, 1.755, 0.27), null, 0.0, 5, 8)
	body.color = Color(0.1, 0.08, 0.08)
	body.add_blob(Vector3(0.08, 0.07, 0.08), _at(0, 1.86, 0.06), null, 0.0, 5, 8)
	for sx in [-1.0, 1.0]:
		var s: float = sx
		body.color = skin
		body.add_blob(Vector3(0.05, 0.07, 0.03), _at(s * 0.23, 1.68, 0.08), null, 0.0, 4, 6)
		body.color = bone
		body.add_tube(PackedVector3Array([Vector3(s * 0.1, 1.6, 0.34), Vector3(s * 0.125, 1.73, 0.36)]), PackedFloat32Array([0.036, 0.008]), 6)
		body.color = INK
		body.add_blob(Vector3(0.024, 0.024, 0.014), _at(s * 0.085, 1.712, 0.318), null, 0.0, 4, 6)
	body.color = INK
	body.add_box(Vector3(0.26, 0.018, 0.014), 0.004, _at(0, 1.6, 0.366))
	var leg := MeshBuilder.new()
	leg.color = skin.darkened(0.1)
	leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.4, 0.03), Vector3(0, -0.68, 0)]), PackedFloat32Array([0.19, 0.16, 0.14]), 10)
	leg.add_blob(Vector3(0.17, 0.09, 0.26), _at(0, -0.72, 0.08), null, 0.0, 5, 8)
	leg.color = INK
	for x: float in [-0.1, 0.0, 0.1]:
		leg.add_blob(Vector3(0.035, 0.03, 0.05), _at(x, -0.74, 0.32), null, 0.0, 4, 6)
	var arm := MeshBuilder.new()
	arm.color = skin
	arm.add_blob(Vector3(0.17, 0.16, 0.17), _at(0, -0.02, 0), null, 0.0, 6, 10)
	arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.4, -0.02), Vector3(0, -0.75, 0.03)]), PackedFloat32Array([0.15, 0.13, 0.12]), 10)
	arm.add_blob(Vector3(0.14, 0.15, 0.14), _at(0, -0.85, 0.03), null, 0.0, 6, 10)
	arm.color = hide.darkened(0.3)
	_band(arm, 0.118, -0.66, 0.04, 0.02, 10)
	_ogre_look = {"body": body.commit(), "leg": leg.commit(), "arm": arm.commit(), "leg_x": 0.2, "arm_x": 0.58}

	# The club points forwards out of the fist, like a soldier's sword.
	var club := MeshBuilder.new()
	club.color = Art.WOOD
	club.add_tube(PackedVector3Array([Vector3(0, 0, -0.18), Vector3(0, 0, 0.5), Vector3(0, 0.02, 1.25)]), PackedFloat32Array([0.06, 0.09, 0.2]), 8)
	club.color = Art.WOOD_DARK
	for k in 3:
		club.add_blob(Vector3(0.07, 0.07, 0.07), _at(0.12 * cos(k * 2.1), 0.02 + 0.12 * sin(k * 2.1), 0.75 + 0.16 * k), null, 0.0, 4, 6)
	club.color = STEEL
	for k in 5:
		var a := k * TAU / 5.0
		var out := Vector3(cos(a), sin(a), 0.0)
		var base := Vector3(0, 0.02, 0.95 + 0.06 * (k % 2)) + out * 0.15
		club.add_tube(PackedVector3Array([base, base + out * 0.16]), PackedFloat32Array([0.04, 0.004]), 5)
	_gear["club"] = club.commit()


## Builds the shared library of looks, gear and loads.
static func _build_looks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for k in LOOKS:
		var c := {
			"tunic": Art.CLOTH_COLORS[rng.randi() % Art.CLOTH_COLORS.size()],
			"trousers": Color(0.28, 0.2, 0.14).lerp(Art.CLOTH_COLORS[rng.randi() % Art.CLOTH_COLORS.size()], 0.3),
			"skin": Art.SKIN_COLORS[rng.randi() % Art.SKIN_COLORS.size()],
			"hair": Color(0.16, 0.1, 0.06).lerp(Color(0.75, 0.5, 0.2), rng.randf()),
			"skirt": rng.randf() < 0.45,
			"hat": rng.randi_range(0, 3),
			"hat_color": (Art.CLOTH_COLORS[rng.randi() % Art.CLOTH_COLORS.size()] as Color).darkened(0.2),
		}
		var look := _villager_far(c)
		look.merge(_villager_near(c))
		_looks.append(look)
	for k in 6:
		var skin: Color = Art.GOBLIN_SKIN[k % Art.GOBLIN_SKIN.size()]
		var hide := Color(0.42, 0.28, 0.16).lerp(Color(0.5, 0.2, 0.2), rng.randf() * 0.6)
		var look := _goblin_far(skin, hide)
		look.merge(_goblin_near(skin, hide))
		_goblin_looks.append(look)
	for skin: Color in Art.SKIN_COLORS:
		var look := _soldier_far(skin)
		look.merge(_soldier_near(skin))
		_soldier_looks.append(look)
	_build_ogre()

	# The sword points forwards out of the hand; the shield faces sideways.
	var sword := MeshBuilder.new()
	sword.color = STEEL.lightened(0.2)
	sword.add_box(Vector3(0.04, 0.1, 0.7), 0.01, _at(0, 0, 0.46))
	sword.color = INK
	sword.add_box(Vector3(0.046, 0.016, 0.6), 0.004, _at(0, 0, 0.44))
	sword.color = Color(0.78, 0.6, 0.2)
	sword.add_box(Vector3(0.26, 0.05, 0.05), 0.01, _at(0, 0, 0.1))
	_gear["sword"] = sword.commit()
	var shield := MeshBuilder.new()
	var sideways := Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO)
	shield.color = Color(0.62, 0.2, 0.16)
	shield.add_lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.31, 0.0), Vector2(0.31, 0.04), Vector2(0.0, 0.08)]), 12, sideways)
	shield.color = STEEL
	shield.add_lathe(PackedVector2Array([Vector2(0.1, 0.05), Vector2(0.07, 0.11), Vector2(0.0, 0.13)]), 8, sideways)
	shield.add_lathe(PackedVector2Array([Vector2(0.29, -0.005), Vector2(0.325, 0.02), Vector2(0.29, 0.05)]), 12, sideways)
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
	# Archers: a hooded green jerkin, a quiver on the back and a longbow.
	var green := Color(0.2, 0.42, 0.2)
	for skin: Color in Art.SKIN_COLORS:
		var body := MeshBuilder.new()
		body.color = green
		body.add_lathe(PackedVector2Array([Vector2(0.0, 0.62), Vector2(0.29, 0.62), Vector2(0.21, 1.0), Vector2(0.25, 1.28),
			Vector2(0.13, 1.44), Vector2(0.0, 1.46)]), 14)
		body.color = Color(0.2, 0.13, 0.09)
		_band(body, 0.215, 1.02, 0.04, 0.02, 14)
		body.color = skin
		body.add_blob(Vector3(0.155, 0.175, 0.165), _at(0, 1.6, 0), null, 0.0, 8, 12)
		_face(body, skin, 1.6, 0.165)
		body.color = green.darkened(0.25)
		body.add_blob(Vector3(0.195, 0.2, 0.2), _at(0, 1.62, -0.05), null, 0.0, 8, 12)
		body.add_tube(PackedVector3Array([Vector3(0, 1.74, -0.18), Vector3(0, 1.66, -0.32)]), PackedFloat32Array([0.07, 0.015]), 6)
		body.color = LEATHER
		body.add_tube(PackedVector3Array([Vector3(0.1, 0.95, -0.24), Vector3(-0.12, 1.5, -0.24)]), PackedFloat32Array([0.07, 0.075]), 8)
		body.color = Color(0.95, 0.9, 0.75)
		for k in 3:
			body.add_tube(PackedVector3Array([Vector3(-0.12 + 0.03 * (k - 1), 1.5, -0.24), Vector3(-0.17 + 0.04 * (k - 1), 1.68, -0.24)]),
				PackedFloat32Array([0.012, 0.02]), 4)
		var leg := MeshBuilder.new()
		leg.color = Color(0.32, 0.24, 0.16)
		leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.36, 0.02), Vector3(0, -0.7, 0)]), PackedFloat32Array([0.1, 0.085, 0.07]), 8)
		leg.color = LEATHER.darkened(0.3)
		leg.add_blob(Vector3(0.085, 0.065, 0.15), _at(0, -0.735, 0.055), null, 0.0, 5, 8)
		var arm := MeshBuilder.new()
		arm.color = green.lightened(0.08)
		arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.26, -0.015), Vector3(0, -0.36, -0.01)]), PackedFloat32Array([0.08, 0.068, 0.066]), 8)
		arm.color = LEATHER
		arm.add_tube(PackedVector3Array([Vector3(0, -0.34, -0.01), Vector3(0, -0.47, 0)]), PackedFloat32Array([0.068, 0.062]), 8)
		arm.color = skin
		arm.add_blob(Vector3(0.058, 0.07, 0.058), _at(0, -0.54, 0), null, 0.0, 5, 8)
		_archer_looks.append({"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()})
	# The bow lies along the forearm's Z axis, so it stands upright when the
	# arm is held out to shoot, and bulges away from the hand.
	var bow := MeshBuilder.new()
	bow.color = Art.WOOD
	bow.add_tube(PackedVector3Array([Vector3(0, 0.03, -0.62), Vector3(0, -0.13, -0.34), Vector3(0, -0.2, 0.0), Vector3(0, -0.13, 0.34),
		Vector3(0, 0.03, 0.62)]), PackedFloat32Array([0.012, 0.022, 0.028, 0.022, 0.012]), 5)
	bow.color = INK
	bow.add_tube(PackedVector3Array([Vector3(0, 0.03, -0.62), Vector3(0, 0.03, 0.62)]), PackedFloat32Array([0.006, 0.006]), 4)
	_gear["bow"] = bow.commit()

	_build_undead()

	# Without wheelbarrows a worker carries a small load on its back.
	var back := _at(0, 1.22, -0.27)
	var logs := MeshBuilder.new()
	logs.color = Art.WOOD
	for z: float in [-0.07, 0.07]:
		logs.add_tube(PackedVector3Array([Vector3(-0.3, 0, z), Vector3(0.3, 0, z)]), PackedFloat32Array([0.065, 0.065]), 6, back)
	logs.add_tube(PackedVector3Array([Vector3(-0.3, 0.11, 0), Vector3(0.3, 0.11, 0)]), PackedFloat32Array([0.065, 0.065]), 6, back)
	_gear["pack_lumber"] = logs.commit()
	var lump := MeshBuilder.new()
	lump.color = Color(0.62, 0.64, 0.68)
	lump.add_blob(Vector3(0.18, 0.15, 0.16), back, null, 0.0, 5, 8)
	_gear["pack_stone"] = lump.commit()
	var sack := MeshBuilder.new()
	sack.color = Color(0.88, 0.74, 0.36)
	sack.add_blob(Vector3(0.16, 0.2, 0.14), back, null, 0.0, 5, 8)
	_gear["pack_food"] = sack.commit()

	var staff := MeshBuilder.new()
	staff.color = Art.WOOD_DARK
	staff.add_tube(PackedVector3Array([Vector3(0, -0.7, 0), Vector3(0, 0.75, 0)]), PackedFloat32Array([0.035, 0.03]), 6)
	_gear["staff"] = staff.commit()
	var orb := MeshBuilder.new()
	orb.add_blob(Vector3(0.09, 0.09, 0.09), Transform3D(Basis(), Vector3(0, 0.83, 0)), null, 0.0, 6, 8)
	_gear["orb"] = orb.commit()

	# Wheelbarrows, one for each kind of load. They are built in the
	# villager's own space: the wheel out in front, the handles at the hands.
	for kind: String in ["lumber", "stone", "food"]:
		var mb := MeshBuilder.new()
		mb.color = Art.WOOD
		mb.add_box(Vector3(0.46, 0.22, 0.62), 0.02, _at(0, 0.44, 0.74), Vector2(1.22, 1.15))
		mb.color = Art.WOOD_DARK
		for sx in [-1.0, 1.0]:
			var s: float = sx
			mb.add_tube(PackedVector3Array([Vector3(s * 0.2, 0.4, 0.5), Vector3(s * 0.27, 0.84, 0.24)]), PackedFloat32Array([0.028, 0.024]), 5)
			mb.add_tube(PackedVector3Array([Vector3(s * 0.18, 0.36, 0.52), Vector3(s * 0.18, 0.06, 0.5)]), PackedFloat32Array([0.025, 0.025]), 5)
			mb.add_tube(PackedVector3Array([Vector3(s * 0.08, 0.36, 0.95), Vector3(s * 0.08, 0.17, 1.12)]), PackedFloat32Array([0.022, 0.022]), 5)
		var axle := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.17, 1.12))
		mb.color = INK
		mb.add_lathe(PackedVector2Array([Vector2(0.0, -0.03), Vector2(0.17, -0.03), Vector2(0.17, 0.03), Vector2(0.0, 0.03)]), 12, axle)
		mb.color = Art.WOOD
		mb.add_lathe(PackedVector2Array([Vector2(0.0, -0.045), Vector2(0.07, -0.045), Vector2(0.07, 0.045), Vector2(0.0, 0.045)]), 8, axle)
		match kind:
			"lumber":
				for spot: Vector2 in [Vector2(-0.11, 0.6), Vector2(0.11, 0.6), Vector2(0.0, 0.74)]:
					mb.color = Art.WOOD.lightened(0.12)
					mb.add_tube(PackedVector3Array([Vector3(spot.x, spot.y, 0.42), Vector3(spot.x, spot.y, 1.06)]), PackedFloat32Array([0.085, 0.085]), 7)
			"stone":
				for spot: Vector3 in [Vector3(-0.1, 0.6, 0.62), Vector3(0.1, 0.61, 0.82), Vector3(0.02, 0.72, 0.7)]:
					mb.color = Color(0.62, 0.64, 0.7).darkened(0.12 * spot.x + 0.05)
					mb.add_blob(Vector3(0.15, 0.12, 0.15), Transform3D(Basis(), spot), null, 0.0, 5, 8)
			_:
				mb.color = Color(0.9, 0.82, 0.62)
				mb.add_blob(Vector3(0.15, 0.17, 0.14), _at(-0.08, 0.64, 0.62), null, 0.0, 5, 8)
				mb.add_blob(Vector3(0.14, 0.16, 0.14), _at(0.09, 0.63, 0.86), null, 0.0, 5, 8)
				mb.color = Color(1.0, 0.8, 0.28)
				mb.add_blob(Vector3(0.1, 0.1, 0.2), _at(0.02, 0.76, 0.74), null, 0.0, 5, 8)
		_gear["barrow_" + kind] = mb.commit()


## Necromancers, the skeletons they raise, and what both carry.
static func _build_undead() -> void:
	var bone := Color(0.9, 0.87, 0.74)
	var night := Color(0.11, 0.1, 0.14)
	var rune := Color(0.66, 0.34, 0.95)
	for skin: Color in [Color(0.8, 0.78, 0.86), Color(0.72, 0.76, 0.74)]:
		var body := MeshBuilder.new()
		# A long black robe, ragged at the hem, with glowing runes down the front.
		body.color = night
		body.add_lathe(PackedVector2Array([Vector2(0.0, 0.06), Vector2(0.4, 0.06), Vector2(0.3, 0.5), Vector2(0.2, 0.95),
			Vector2(0.24, 1.3), Vector2(0.13, 1.44), Vector2(0.0, 1.46)]), 14, Transform3D.IDENTITY, 7, 0.07)
		body.add_lathe(PackedVector2Array([Vector2(0.13, 1.42), Vector2(0.21, 1.62)]), 12)
		body.color = rune
		for sx: float in [-1.0, 1.0]:
			body.add_tube(PackedVector3Array([Vector3(sx * 0.06, 1.3, 0.235), Vector3(sx * 0.06, 0.95, 0.205), Vector3(sx * 0.08, 0.5, 0.305),
				Vector3(sx * 0.1, 0.1, 0.4)]), PackedFloat32Array([0.022, 0.022, 0.024, 0.026]), 5)
		# A belt of bone with a skull for a buckle, and bone spikes at the shoulders.
		body.color = bone
		_band(body, 0.2, 1.0, 0.04, 0.03, 14)
		body.add_blob(Vector3(0.07, 0.075, 0.06), _at(0, 0.99, 0.23), null, 0.0, 4, 7)
		for sx: float in [-1.0, 1.0]:
			body.add_tube(PackedVector3Array([Vector3(sx * 0.2, 1.38, 0.0), Vector3(sx * 0.33, 1.7, -0.04)]), PackedFloat32Array([0.05, 0.008]), 5)
			body.add_tube(PackedVector3Array([Vector3(sx * 0.23, 1.34, -0.06), Vector3(sx * 0.4, 1.56, -0.1)]), PackedFloat32Array([0.045, 0.008]), 5)
		body.color = INK
		for sx: float in [-1.0, 1.0]:
			body.add_blob(Vector3(0.018, 0.02, 0.012), _at(sx * 0.028, 1.0, 0.285), null, 0.0, 3, 5)
		body.color = skin
		body.add_blob(Vector3(0.155, 0.175, 0.165), _at(0, 1.6, 0), null, 0.0, 8, 12)
		_face(body, skin, 1.6, 0.165, true)
		# Wild black hair.
		body.color = Color(0.07, 0.06, 0.09)
		body.add_blob(Vector3(0.185, 0.16, 0.19), _at(0, 1.68, -0.05), null, 0.0, 6, 10)
		for k in 7:
			var a := -1.9 + 3.8 * k / 6.0
			var out := Vector3(sin(a), 0.75, -0.25 - 0.3 * cos(a)).normalized()
			body.add_tube(PackedVector3Array([Vector3(0, 1.68, -0.05) + out * 0.12, Vector3(0, 1.68, -0.05) + out * (0.3 + 0.07 * (k % 2))]),
				PackedFloat32Array([0.06, 0.008]), 5)
		var leg := MeshBuilder.new()
		leg.color = night.darkened(0.3)
		leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.72, 0)]), PackedFloat32Array([0.08, 0.07]), 6)
		var arm := MeshBuilder.new()
		# Wide sleeves with a rune cuff.
		arm.color = night.lightened(0.04)
		arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.3, 0), Vector3(0, -0.5, 0)]), PackedFloat32Array([0.085, 0.1, 0.15]), 8)
		arm.color = rune
		_band(arm, 0.15, -0.49, 0.025, 0.012, 8)
		arm.color = skin
		arm.add_blob(Vector3(0.055, 0.075, 0.055), _at(0, -0.57, 0), null, 0.0, 4, 8)
		_necro_looks.append({"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()})
	# Ghost fire in one hand, the book of the dead in the other.
	var soul := MeshBuilder.new()
	soul.color = rune.lightened(0.15)
	soul.add_blob(Vector3(0.09, 0.11, 0.09), _at(0, 0.0, 0), null, 0.0, 5, 8)
	soul.add_tube(PackedVector3Array([Vector3(0, 0.05, 0), Vector3(0.04, 0.2, 0.0), Vector3(-0.02, 0.36, 0.02)]), PackedFloat32Array([0.07, 0.045, 0.005]), 6)
	_gear["soul"] = soul.commit()
	var book := MeshBuilder.new()
	book.color = Color(0.3, 0.2, 0.34)
	book.add_box(Vector3(0.24, 0.07, 0.3), 0.012, _at(0, 0, 0.1))
	book.color = Color(0.92, 0.88, 0.76)
	book.add_box(Vector3(0.21, 0.045, 0.31), 0.006, _at(0.012, 0, 0.1))
	book.color = bone
	book.add_blob(Vector3(0.05, 0.02, 0.055), _at(0, 0.04, 0.1), null, 0.0, 4, 6)
	_gear["book"] = book.commit()
	var rusty := MeshBuilder.new()
	rusty.color = Color(0.52, 0.42, 0.36)
	rusty.add_box(Vector3(0.04, 0.09, 0.62), 0.01, _at(0, 0, 0.42))
	rusty.color = INK
	rusty.add_box(Vector3(0.046, 0.016, 0.52), 0.004, _at(0, 0, 0.4))
	rusty.color = Color(0.36, 0.26, 0.2)
	rusty.add_box(Vector3(0.22, 0.05, 0.05), 0.01, _at(0, 0, 0.1))
	_gear["rusty_sword"] = rusty.commit()

	# Skeletons: a warrior in a rusty helmet and an archer with a quiver.
	for archer_look: bool in [false, true]:
		var body := MeshBuilder.new()
		body.color = bone
		body.add_tube(PackedVector3Array([Vector3(0, 0.8, 0), Vector3(0, 1.1, -0.03), Vector3(0, 1.47, 0)]), PackedFloat32Array([0.04, 0.035, 0.04]), 6)
		body.add_blob(Vector3(0.17, 0.085, 0.1), _at(0, 0.81, 0), null, 0.0, 5, 8)
		body.add_tube(PackedVector3Array([Vector3(-0.25, 1.4, 0), Vector3(0.25, 1.4, 0)]), PackedFloat32Array([0.035, 0.035]), 5)
		# Ribs: hoops of bone round a dark hollow.
		for k in 4:
			var y := 1.09 + k * 0.082
			var r := 0.15 + 0.03 * sin((k + 0.5) * 0.8)
			body.add_lathe(PackedVector2Array([Vector2(r - 0.02, y - 0.024), Vector2(r, y), Vector2(r - 0.02, y + 0.024)]), 10)
		body.add_blob(Vector3(0.15, 0.16, 0.165), _at(0, 1.61, 0.0), null, 0.0, 8, 12)
		body.add_box(Vector3(0.17, 0.08, 0.12), 0.015, _at(0, 1.475, 0.07))
		body.color = INK
		body.add_tube(PackedVector3Array([Vector3(0, 1.04, 0), Vector3(0, 1.38, 0)]), PackedFloat32Array([0.1, 0.11]), 8)
		for sx: float in [-1.0, 1.0]:
			body.add_blob(Vector3(0.042, 0.05, 0.02), _at(sx * 0.058, 1.625, 0.148), null, 0.0, 4, 6)
		body.add_blob(Vector3(0.016, 0.026, 0.014), _at(0, 1.56, 0.163), null, 0.0, 3, 5)
		body.add_box(Vector3(0.12, 0.012, 0.012), 0.003, _at(0, 1.5, 0.133))
		for k in 3:
			body.add_box(Vector3(0.012, 0.06, 0.012), 0.003, _at((k - 1) * 0.04, 1.49, 0.133))
		# Rags round the hips.
		body.color = Color(0.36, 0.29, 0.2)
		body.add_lathe(PackedVector2Array([Vector2(0.17, 0.86), Vector2(0.2, 0.74), Vector2(0.22, 0.52)]), 9, Transform3D.IDENTITY, 5, 0.12)
		if archer_look:
			body.color = LEATHER.darkened(0.2)
			body.add_tube(PackedVector3Array([Vector3(0.1, 0.98, -0.2), Vector3(-0.12, 1.5, -0.2)]), PackedFloat32Array([0.065, 0.07]), 7)
			body.color = bone
			for k in 3:
				body.add_tube(PackedVector3Array([Vector3(-0.12 + 0.03 * (k - 1), 1.5, -0.2), Vector3(-0.17 + 0.04 * (k - 1), 1.68, -0.2)]),
					PackedFloat32Array([0.012, 0.02]), 4)
		else:
			body.color = Color(0.46, 0.34, 0.27)
			body.add_lathe(PackedVector2Array([Vector2(0.175, 1.62), Vector2(0.17, 1.7), Vector2(0.1, 1.775), Vector2(0.0, 1.79)]), 10)
			body.add_lathe(PackedVector2Array([Vector2(0.175, 1.6), Vector2(0.2, 1.625), Vector2(0.175, 1.65)]), 10)
			body.add_blob(Vector3(0.1, 0.07, 0.11), _at(0.25, 1.43, 0), null, 0.0, 4, 7)
		var leg := MeshBuilder.new()
		leg.color = bone
		leg.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.36, 0.012)]), PackedFloat32Array([0.036, 0.028]), 5)
		leg.add_tube(PackedVector3Array([Vector3(0, -0.36, 0.012), Vector3(0, -0.72, 0)]), PackedFloat32Array([0.03, 0.024]), 5)
		leg.add_blob(Vector3(0.045, 0.045, 0.045), _at(0, -0.36, 0.012), null, 0.0, 4, 6)
		leg.add_blob(Vector3(0.05, 0.03, 0.11), _at(0, -0.745, 0.05), null, 0.0, 4, 7)
		var arm := MeshBuilder.new()
		arm.color = bone
		arm.add_blob(Vector3(0.045, 0.045, 0.045), _at(0, 0, 0), null, 0.0, 4, 6)
		arm.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.27, -0.01)]), PackedFloat32Array([0.03, 0.025]), 5)
		arm.add_tube(PackedVector3Array([Vector3(0, -0.27, -0.01), Vector3(0, -0.5, 0)]), PackedFloat32Array([0.026, 0.02]), 5)
		arm.add_blob(Vector3(0.036, 0.036, 0.036), _at(0, -0.27, -0.01), null, 0.0, 4, 6)
		arm.add_blob(Vector3(0.042, 0.055, 0.042), _at(0, -0.55, 0), null, 0.0, 4, 6)
		_skeleton_looks.append({"body": body.commit(), "leg": leg.commit(), "arm": arm.commit()})


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
	if skeleton and Game.now >= _expires:
		_crumble()
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
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d := cam.global_position.distance_to(global_position)
			if _near != (d < (LOD_FAR if _near else LOD_NEAR)):
				_apply_lod(not _near)
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
		State.RAISE:
			_update_raise(delta)
		State.CROSS:
			_update_cross(delta)
		State.WALK:
			var pace := 2.6 if raiding else (1.8 if goblin else 1.3)
			if ogre:
				pace = 2.1
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
	if state == State.CROSS and _route_i > 0:
		# Up a ladder or out on a bridge: not on the ground.
		_animate(delta)
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
	return owned and not skeleton and not child and not soldier and not wizard and not archer and state != State.DEAD and state != State.BURNING and state != State.HELD


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
		if kind != "train" and not goblin:
			_try_bridge(pos)


func clear_job() -> void:
	job = ""
	job_target = null
	_working = false
	if goblin:
		carry_pack("")
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
	var barrows := is_instance_valid(Game.village) and Game.village.barrows
	if carry >= (BARROW_CAPACITY if barrows else CARRY_CAPACITY):
		_start_delivery()


func _start_delivery() -> void:
	if not is_instance_valid(Game.village):
		return
	_delivering = true
	_working = false
	_drop_pos = Game.village.drop_point(global_position)
	# The load goes home in a wheelbarrow if the village has a Blacksmith to
	# make them, and on the worker's back if not.
	if _load == null:
		_load = MeshInstance3D.new()
		_load.material_override = Art.cloth()
		add_child(_load)
	_pushing = Game.village.barrows
	_load.mesh = _gear[("barrow_" if _pushing else "pack_") + carry_kind]
	_load.visible = true
	if state == State.IDLE or state == State.WALK:
		state = State.JOB
	if state == State.JOB and not _pushing:
		_try_bridge(_drop_pos)


## Shows a load of "lumber", "stone" or "food" on the back, or takes it off
## with "". (Goblins fetching what they build with from their cave.)
func carry_pack(kind: String) -> void:
	if kind == "":
		if _load:
			_load.visible = false
		return
	if _load == null:
		_load = MeshInstance3D.new()
		_load.material_override = Art.cloth()
		add_child(_load)
	_load.mesh = _gear["pack_" + kind]
	_load.visible = true


func _unload() -> void:
	if carry > 0.0 and is_instance_valid(Game.village):
		Game.village.store(carry_kind, carry)
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
	if is_instance_valid(Game.village) and Game.village.has_research("swords"):
		sharpen()
	_look = _soldier_looks[randi() % _soldier_looks.size()]
	_apply_lod(_near)
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
	_look = look
	_apply_lod(_near)


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


## A wizard trained on at a Necromancer tower: black robes, a book of the
## dead and a handful of ghost fire. It still throws firebolts, and raises
## one fallen villager or enemy at a time as a skeleton.
func become_necromancer(post: Vector3) -> void:
	if necromancer or not wizard or state == State.DEAD:
		return
	clear_job()
	necromancer = true
	remove_from_group("wizards")
	add_to_group("necromancers")
	home = post
	home_radius = 10.0
	for g in _gear_nodes:
		g.queue_free()
	_gear_nodes.clear()
	_wear(_necro_looks[randi() % _necro_looks.size()])
	_add_gear("soul", _arms[0], Vector3(0.0, -0.62, 0.04), Art.glow(3.0))
	_add_gear("book", _arms[1], Vector3(0.0, -0.6, 0.1))
	Game.effects.spawn_raise(global_position)


## What a blow, arrow or firebolt from this one does.
func power() -> float:
	if archer and not skeleton:
		return ARROW_DAMAGE
	return FIREBOLT_DAMAGE if wizard else damage


## The skeleton a necromancer (`master`) raises from the dead `body`: an
## archer or a warrior with Balance "skeleton_share" of the health and
## damage of whoever it was, for "skeleton_seconds".
static func raise_skeleton(body: Villager, master: Villager) -> Villager:
	var share := Balance.num("skeleton_share")
	var s := Villager.new()
	s.skeleton = true
	s.owned = true
	s.archer = body.archer or body.wizard or randf() < 0.35
	s.max_hp = maxf(1.0, body.max_hp * share)
	s.damage = body.power() * share
	s._fixed_scale = body._adult_scale * (CHILD_SCALE if body.child else 1.0)
	s.home = master.home
	s.home_radius = 8.0
	s._expires = Game.now + Balance.num("skeleton_seconds")
	Game.world_root.add_child(s)
	var p := body.global_position
	s.global_position = Vector3(p.x, Game.terrain.get_height(p.x, p.z), p.z)
	s.rotation.y = body.rotation.y
	return s


## A necromancer looks for a body to raise when it has no skeleton up.
func _look_for_body() -> bool:
	if Game.now < _raise_ready or (is_instance_valid(_minion) and _minion.is_alive()):
		return false
	if not is_instance_valid(Game.village) or Game.village.amount("bones") < roundi(Balance.num("raise_bones")):
		return false
	var best: Villager = null
	var best_d := RAISE_SIGHT
	for node in get_tree().get_nodes_in_group("corpses"):
		var body := node as Villager
		if body._airborne or body._timer > CORPSE_SECONDS - 10.0 or body.get_meta("claimed", 0.0) > Game.now:
			continue
		var d := _flat_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	if best == null:
		return false
	best.set_meta("claimed", Game.now + 14.0)
	_raise_target = best
	_raise_timer = 0.0
	_raise_walk = 0.0
	_foe = null
	_working = false
	state = State.RAISE
	return true


func _update_raise(delta: float) -> void:
	var body := _raise_target
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not body.is_in_group("corpses"):
		state = State.IDLE
		_timer = 0.2
		return
	var to := body.global_position - global_position
	to.y = 0.0
	if to.length() > RAISE_REACH:
		_raise_walk += delta
		if _move_towards(body.global_position, 2.4 * _speed_scale, delta) or _raise_walk > 15.0:
			# Cannot get to it.
			_raise_ready = Game.now + 5.0
			state = State.IDLE
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	if _raise_timer == 0.0:
		Game.effects.spawn_raise(body.global_position)
	_raise_timer += delta
	if _raise_timer < RAISE_SECONDS:
		return
	if Game.village.spend({"bones": roundi(Balance.num("raise_bones"))}):
		_minion = Villager.raise_skeleton(body, self)
		body.queue_free()
	_raise_ready = Game.now + 3.0
	state = State.IDLE
	_timer = 0.3


## The skeleton's time is up: it falls into a heap.
func _crumble() -> void:
	Game.effects.spawn_dust(global_position, 0.5)
	_die(false)
	_body.scale = Vector3(1.0, 0.3, 1.0)
	_timer = CORPSE_SECONDS - 5.0


# --- Rope bridges -------------------------------------------------------------------

## Sets off over a rope bridge if one lies more or less on the way to
## `goal` (or, on a `stroll`, if one is simply near). True if it did.
func _try_bridge(goal: Vector3, stroll := false) -> bool:
	if goblin or skeleton or Game.now < _cross_cool:
		return false
	for node in get_tree().get_nodes_in_group("bridges"):
		var bridge := node as RopeBridge
		if not bridge.usable():
			continue
		for from_a: bool in [true, false]:
			var foot := RopeBridge.ladder_foot(bridge.a if from_a else bridge.b)
			var far := RopeBridge.ladder_foot(bridge.b if from_a else bridge.a)
			var there := _flat_to(foot)
			if stroll:
				if there > 24.0:
					continue
			elif there + bridge.length + 8.0 + Vector2(far.x - goal.x, far.z - goal.z).length() > _flat_to(goal) * 1.2 + 4.0:
				continue
			_route = bridge.route(from_a)
			_route_i = 0
			_bridge = bridge
			_cross_time = 0.0
			_cross_cool = Game.now + (45.0 if stroll else 20.0)
			state = State.CROSS
			return true
	return false


func _update_cross(delta: float) -> void:
	if not is_instance_valid(_bridge) or not _bridge.usable():
		_end_cross()
		return
	var goal := _route[_route_i]
	if _route_i == 0:
		# Walk to the foot of the ladder.
		_cross_time += delta
		if _move_towards(goal, 1.7 * _speed_scale, delta):
			if _flat_to(goal) > 1.0:
				_end_cross()
			else:
				_route_i = 1
		elif _cross_time > 40.0:
			_end_cross()
		return
	var to := goal - global_position
	var dist := to.length()
	var step := 1.6 * _speed_scale * delta
	if dist <= step:
		global_position = goal
		_route_i += 1
		if _route_i >= _route.size():
			_end_cross()
	else:
		global_position += to / dist * step
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.25:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.y), minf(1.0, delta * 8.0))
	_moving = true


func _end_cross() -> void:
	_bridge = null
	_route_i = 0
	state = State.JOB if job != "" or _delivering else State.IDLE
	_timer = randf_range(0.5, 2.0)


## Sharper swords from the Blacksmith: warriors hit harder.
func sharpen() -> void:
	if soldier:
		damage = ATTACK_DAMAGE * SOLDIER_DAMAGE * Balance.num("sharper_swords_bonus")


## Trained at a Town guard once the village has bows: a green hood, a
## quiver and a longbow.
func become_archer(post: Vector3) -> void:
	if archer or soldier or wizard or goblin or state == State.DEAD:
		return
	_unload()
	clear_job()
	archer = true
	add_to_group("archers")
	home = post
	home_radius = 10.0
	max_hp = HEALTH * ARCHER_HEALTH
	hp = max_hp
	_wear(_archer_looks[randi() % _archer_looks.size()])
	_add_gear("bow", _arms[1], Vector3(0.0, -0.55, 0.0))
	Game.effects.spawn_dust(global_position, 0.5)


## A soldier, archer or wizard goes back to ordinary work (and would have
## to train again to return).
func become_worker() -> void:
	if not (soldier or wizard or archer) or state == State.DEAD:
		return
	for g in _gear_nodes:
		g.queue_free()
	_gear_nodes.clear()
	soldier = false
	wizard = false
	archer = false
	necromancer = false
	guard = null
	remove_from_group("soldiers")
	remove_from_group("wizards")
	remove_from_group("archers")
	remove_from_group("necromancers")
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
	if state == State.BURNING or state == State.RAISE or state == State.CROSS:
		return
	if necromancer and job != "train" and (state == State.IDLE or state == State.WALK or state == State.FIGHT) and _look_for_body():
		return
	if goblin:
		if not raiding or (state == State.FIGHT and _foe_ok() and (_foe is Villager or _foe is Creature)):
			return
		var victim := _nearest_villager(AGGRO)
		# The creature is fair game when it is close, unless a villager is closer.
		var beast := Game.creature
		if is_instance_valid(beast) and not beast.knocked_out:
			var d := _flat_to(beast.global_position)
			if d < 4.0 + 5.0 * beast.size and (victim == null or d < _flat_to(victim.global_position)):
				_engage(beast)
				return
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
	var best_d := SOLDIER_AGGRO if soldier or wizard or archer or skeleton else (AGGRO if fighter else 8.0)
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
		if d < best_d and not b.destroyed and not b is RopeBridge:
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
	var beast := _foe as Creature
	if beast:
		return raiding and not beast.knocked_out
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
	if archer and _foe is Villager:
		_shoot_at(_foe as Villager, to, delta)
		return
	var reach := 2.6 if ogre else 1.2
	var building := _foe as Destructible
	var beast := _foe as Creature
	if building:
		reach += building.footprint * 0.8 - 0.4
	elif beast:
		reach += 2.2 * beast.size
	_in_reach = to.length() <= reach
	if not _in_reach:
		_move_towards(_foe.global_position, (3.0 if soldier else (2.1 if ogre else 2.6)) * _speed_scale, delta)
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	if _attack_timer <= 0.0:
		_attack_timer = GOBLIN_ATTACK_SECONDS if goblin else ATTACK_SECONDS
		if building:
			# Buildings are tough: goblins only chip at them.
			building.damage(damage * 0.5, global_position, 3.0)
		elif beast:
			beast.take_hit(damage, self)
		else:
			(_foe as Villager).take_hit(damage, self)


## Archers stand off and shoot.
func _shoot_at(foe: Villager, to: Vector3, delta: float) -> void:
	_in_reach = to.length() <= ARCHER_RANGE
	if not _in_reach:
		_move_towards(foe.global_position, 2.6 * _speed_scale, delta)
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	if _attack_timer <= 0.0:
		_attack_timer = ARROW_SECONDS
		var arrow := Arrow.new()
		Game.world_root.add_child(arrow)
		arrow.launch(global_position + Vector3.UP * 1.35 * scale.y + to.normalized() * 0.5, foe, self, damage if skeleton else ARROW_DAMAGE)


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
	if attacker and state != State.FIGHT and state != State.BURNING and state != State.CROSS and can_fight():
		if goblin and not raiding:
			start_raid(global_position)
		_engage(attacker)


func _choose_wander_target() -> void:
	# Now and then, a stroll over a rope bridge.
	if not goblin and randf() < 0.3 and _try_bridge(home, true):
		return
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
	if state == State.RAISE and _raise_timer > 0.0:
		# Both arms up, calling the dead.
		_body.rotation.x = lerpf(_body.rotation.x, -0.15, blend)
		for k in 2:
			_legs[k].rotation.x = lerpf(_legs[k].rotation.x, 0.0, blend)
			_arms[k].rotation.x = lerpf(_arms[k].rotation.x, -2.5 + 0.25 * sin(_raise_timer * 9.0 + k), blend)
			_arms[k].rotation.z = lerpf(_arms[k].rotation.z, (1.0 if k == 0 else -1.0) * -0.4, blend)
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
		if _delivering and _pushing and state == State.JOB:
			# Both hands on the wheelbarrow.
			arm = -0.55
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
		elif archer:
			# The bow arm is held out; the other draws the string.
			arm = -1.5 if k == 1 else -1.4 + 0.4 * wind
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
	if raiding or soldier or skeleton or state == State.FIGHT or state == State.CROSS:
		return
	_danger = from
	_working = false
	state = State.FLEE
	_timer = randf_range(3.0, 6.0)


func catch_fire() -> void:
	if state == State.DEAD or state == State.BURNING or state == State.HELD or Game.fire.is_wet(global_position):
		return
	if ogre:
		# Too big to go up in flames: it is only singed.
		take_hit(HEALTH, null)
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
	if ogre and state != State.DEAD:
		# A blast hurts an ogre badly but does not throw it.
		take_hit(Balance.num("fireball_damage"), null)
		if state != State.DEAD:
			return
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
	if ogre:
		take_hit(Balance.num("creature_stomp_damage"), null)
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


## The Blood Sacrifice spell.
func sacrifice() -> void:
	if state == State.DEAD:
		return
	Game.effects.spawn_blood(global_position)
	_die(false)
	_set_tint(Color(1.5, 0.2, 0.2))


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
	for group in ["villagers", "people", "goblins", "ogres", "raiders", "soldiers", "wizards", "archers", "necromancers", "skeletons"]:
		remove_from_group(group)
	if not skeleton and is_instance_valid(Game.village) and Game.village.founded:
		# Everyone who dies leaves bones for the village, and a body a
		# necromancer can raise.
		Game.village.give("bones", randi_range(roundi(Balance.num("bones_min")), maxi(roundi(Balance.num("bones_min")), roundi(Balance.num("bones_max")))))
		add_to_group("corpses")
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
	if _timer > CORPSE_SECONDS - 3.0:
		remove_from_group("corpses")
		global_position.y -= delta * 0.3
	if _timer > CORPSE_SECONDS:
		queue_free()
