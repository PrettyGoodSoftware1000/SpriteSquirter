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
## How far the village's own people will run to meet an enemy that is
## inside PlayerVillage.DEFEND_RADIUS.
const DEFEND_REACH := 55.0
const AGGRO := 13.0
## Walks longer than this look for a route (see PathGrid).
const PATH_FROM := 5.0
const SOLDIER_AGGRO := 60.0
## Units of a resource a worker gathers before walking it to the storehouse.
const CARRY_CAPACITY := 2.0
## The load a wheelbarrow takes, once the village has a Blacksmith.
const BARROW_CAPACITY := 6.0
## Archers shoot an arrow every ARROW_SECONDS at goblins within ARCHER_RANGE.
const ARCHER_RANGE := 22.0
## How far off archers and wizards spot a giant bat to shoot down.
const BAT_SIGHT := 50.0
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

## The detailed meshes switch on within Game.settings.villager_detail
## metres of the camera, and off again this much farther away. At
## ALWAYS_DETAILED or more, they are used however far away.
const ALWAYS_DETAILED := 300.0
const LOD_MARGIN := 8.0
## Where the knee and the elbow are, below the hip and the shoulder.
const KNEE_Y := -0.36
const ELBOW_Y := -0.26
## Bodies are this much thinner front to back than side to side.
const BODY_DEPTH := 0.84
const APRON := Color(0.9, 0.86, 0.74)
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
## Trained at a Wizardry tower: robed, makes magicko and throws firebolts.
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
## Wet from the rain until Game.now passes this.
var wet_until := 0.0
## Walks at SLOWED_SPEED until Game.now passes this (roots, on your own people).
var slowed_until := 0.0

## Current job: "", "lumber", "stone", "food", "farm", "build", "train" or
## "plant" (kneeling to plant a sapling).
## The job the player set this worker to: "lumber", "stone", "food",
## "build" (a builder), or "" for an unassigned worker.
var pin := ""
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
## The lower halves: each is a child of its thigh or upper arm.
var _shins: Array[MeshInstance3D] = []
var _fores: Array[MeshInstance3D] = []
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
## A goblin charmed by Charm Offensive fights its own kind until then
## (Game.now), with pink eyes.
var charmed_until := 0.0
## A shove that slides it along the ground (see knock_back()), dying away,
## and staggered by it (it cannot walk) until then (Game.now).
var _shove := Vector3.ZERO
var _stagger_until := 0.0
var _pink_eyes: Array[MeshInstance3D] = []
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
## The route being walked to `_path_goal` (see _path_aim).
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _path_until := 0.0
var _path_next := 0.0
## A raider's way to the village along a path painted in the map editor.
var _raid_route := PackedVector3Array()
var _raid_i := 0
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
		# Thigh and shin, upper arm and forearm: each lower part hangs from
		# the upper one's joint.
		var thigh := _add_mesh(_look.leg, Vector3(sx * leg_x, 0.8, 0.0))
		_legs.append(thigh)
		_shins.append(_add_mesh(_look.shin, Vector3(0.0, _look.knee_y, 0.0), thigh))
		var upper := _add_mesh(_look.arm, Vector3(sx * arm_x, 1.33, 0.0))
		_arms.append(upper)
		_fores.append(_add_mesh(_look.fore, Vector3(0.0, _look.elbow_y, 0.0), upper))
	_adult_scale = randf_range(0.72, 0.86) if goblin else randf_range(0.92, 1.08)
	if ogre:
		_adult_scale = randf_range(2.2, 2.5)
		max_hp = GOBLIN_HEALTH * OGRE_HEALTH
		hp = max_hp
		damage = GOBLIN_DAMAGE * OGRE_DAMAGE
		_hold("club", 0, Vector3(0.0, -0.85, 0.03))
	if skeleton:
		if _fixed_scale > 0.0:
			_adult_scale = _fixed_scale
		if archer:
			_hold("bow", 1, Vector3(0.0, -0.55, 0.0))
		else:
			_hold("rusty_sword", 0, Vector3(0.0, -0.55, 0.0))
	scale = Vector3.ONE * _adult_scale * (CHILD_SCALE if child else 1.0)
	# In full detail from the start when villagers are always drawn so.
	if Game.settings.villager_detail >= ALWAYS_DETAILED:
		_apply_lod(true)


func _add_mesh(mesh: Mesh, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Art.cloth()
	mi.position = pos
	(parent if parent else _body).add_child(mi)
	_meshes.append(mi)
	return mi


## Swaps between the detailed meshes (camera close) and the simple ones.
func _apply_lod(near: bool) -> void:
	_near = near
	var suffix := "_hi" if near and _look.has("body_hi") else ""
	_torso.mesh = _look["body" + suffix]
	for k in 2:
		_legs[k].mesh = _look["leg" + suffix]
		_shins[k].mesh = _look["shin" + suffix]
		_shins[k].position.y = _look.knee_y
		_arms[k].mesh = _look["arm" + suffix]
		_fores[k].mesh = _look["fore" + suffix]
		_fores[k].position.y = _look.elbow_y


# --- Looks ----------------------------------------------------------------------
# Every look is a dictionary of meshes: body, leg and arm for far away, and
# body_hi, leg_hi and arm_hi for close up. The detailed ones have faces,
# hands, trims and seams, with small black shapes standing in for ink lines.

static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## A dark band round the body: `r` is the body's radius at height `y`.
static func _band(mb: MeshBuilder, r: float, y: float, half: float, out := 0.012, segments := 16) -> void:
	mb.add_lathe(PackedVector2Array([Vector2(r, y - half), Vector2(r + out, y), Vector2(r, y + half)]), segments)


## A leg in two parts, each built round its own joint so it can bend:
## "leg" is the thigh, hanging from the hip, and "shin" the shin and foot,
## hanging from the knee. `o` may set: color, shin_color, boot (colour),
## boot_top (how far up the shin the boot comes; 0 for a shoe), cuff,
## kneepad, top, knee and ankle (radii), length, knee_y, foot (radii),
## bare (a bare foot), toes (claws) and bone (a skeleton's leg).
static func _leg_parts(o: Dictionary, fine: bool) -> Dictionary:
	var seg := 12 if fine else 6
	var top: float = o.get("top", 0.1)
	var knee: float = o.get("knee", 0.084)
	var ankle: float = o.get("ankle", 0.066)
	var knee_y: float = o.get("knee_y", KNEE_Y)
	var shin_len: float = float(o.get("length", 0.72)) + knee_y
	var color: Color = o.get("color", Color.WHITE)
	var shin_color: Color = o.get("shin_color", color)
	var boot: Color = o.get("boot", SHOE)
	var foot: Vector3 = o.get("foot", Vector3(0.085, 0.065, 0.15))
	var bare: bool = o.get("bare", false)
	var thigh := MeshBuilder.new()
	var shin := MeshBuilder.new()
	thigh.color = color
	shin.color = shin_color
	if o.get("bone", false):
		# Two thin bones with a knob at each end.
		thigh.add_blob(Vector3.ONE * top * 1.5, _at(0, 0, 0), null, 0.0, 4, 6)
		thigh.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, knee_y, 0.012)]), PackedFloat32Array([top, knee]), 6)
		shin.add_blob(Vector3.ONE * knee * 1.6, _at(0, 0, 0.012), null, 0.0, 4, 6)
		shin.add_tube(PackedVector3Array([Vector3(0, 0, 0.012), Vector3(0, -shin_len, 0)]), PackedFloat32Array([knee, ankle]), 6)
		shin.add_blob(Vector3.ONE * ankle * 1.5, _at(0, -shin_len, 0), null, 0.0, 4, 6)
		shin.add_blob(foot, _at(0, -shin_len - 0.025, foot.z * 0.45), null, 0.0, 4, 7)
		return {"leg": thigh.commit(), "shin": shin.commit()}
	if fine:
		thigh.add_blob(Vector3(top, top * 0.9, top) * 1.05, _at(0, -0.01, 0), null, 0.0, 6, seg)
		thigh.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, knee_y * 0.45, 0.014), Vector3(0, knee_y, 0.0)]),
			PackedFloat32Array([top, lerpf(top, knee, 0.35), knee]), seg)
	else:
		thigh.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, knee_y, 0)]), PackedFloat32Array([top, knee]), seg)
	# The knee is a ball, so no gap opens when the leg bends.
	shin.add_blob(Vector3.ONE * knee * 1.05, _at(0, 0, 0), null, 0.0, 6 if fine else 4, seg)
	if fine:
		shin.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -shin_len * 0.35, -0.014), Vector3(0, -shin_len, 0)]),
			PackedFloat32Array([knee, knee * 1.04, ankle]), seg)
		if o.has("kneepad"):
			shin.color = o.kneepad
			shin.add_blob(Vector3(knee * 0.9, knee * 1.0, knee * 0.6), _at(0, 0.0, knee * 0.7), null, 0.0, 5, 8)
	else:
		shin.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -shin_len, 0)]), PackedFloat32Array([knee, ankle]), seg)
	var boot_top: float = o.get("boot_top", 0.0)
	if boot_top > 0.0:
		shin.color = boot
		var r_top := lerpf(ankle, knee, boot_top / shin_len) + 0.016
		shin.add_tube(PackedVector3Array([Vector3(0, -shin_len + boot_top, -0.006), Vector3(0, -shin_len, 0)]), PackedFloat32Array([r_top, ankle + 0.016]), seg)
		if fine:
			shin.color = o.get("cuff", boot.darkened(0.4))
			_band(shin, r_top, -shin_len + boot_top, 0.018, 0.012, seg)
	elif fine and o.has("cuff"):
		shin.color = o.cuff
		_band(shin, ankle + 0.004, -shin_len + 0.04, 0.024, 0.014, seg)
	shin.color = shin_color if bare else boot
	shin.add_blob(foot, _at(0, -shin_len - 0.015, foot.z * 0.37), null, 0.0, 6 if fine else 4, seg)
	if fine and not bare:
		shin.add_blob(Vector3(foot.x * 0.92, foot.y * 0.9, foot.x), _at(0, -shin_len - 0.02, -0.012), null, 0.0, 5, 8)
		shin.color = INK
		shin.add_box(Vector3(foot.x * 1.8, 0.022, foot.z * 1.85), 0.006, _at(0, -shin_len - 0.015 - foot.y * 0.85, foot.z * 0.37))
	if fine and o.get("toes", false):
		shin.color = INK
		for x: float in [-0.65, 0.0, 0.65]:
			shin.add_blob(Vector3(foot.x * 0.25, foot.y * 0.36, foot.x * 0.42), _at(x * foot.x, -shin_len - 0.025, foot.z * 1.33), null, 0.0, 4, 6)
	return {"leg": thigh.commit(), "shin": shin.commit()}


## An arm in two parts: "arm" is the upper arm, hanging from the shoulder,
## and "fore" the forearm and hand, hanging from the elbow. `o` may set:
## color, fore_color, hand (skin colour), cuff, bracer (colours), shoulder,
## elbow and wrist (radii), flare (a wide sleeve's radius at the wrist),
## length, elbow_y, hand_size, claws and bone (a skeleton's arm).
static func _arm_parts(o: Dictionary, fine: bool) -> Dictionary:
	var seg := 12 if fine else 6
	var shoulder: float = o.get("shoulder", 0.08)
	var elbow: float = o.get("elbow", 0.067)
	var wrist: float = o.get("wrist", 0.058)
	var elbow_y: float = o.get("elbow_y", ELBOW_Y)
	var fore_len: float = float(o.get("length", 0.47)) + elbow_y
	var color: Color = o.get("color", Color.WHITE)
	var fore_color: Color = o.get("fore_color", color)
	var skin: Color = o.get("hand", color)
	var h: float = o.get("hand_size", 1.0)
	var upper := MeshBuilder.new()
	var fore := MeshBuilder.new()
	upper.color = color
	fore.color = fore_color
	if o.get("bone", false):
		upper.add_blob(Vector3.ONE * shoulder * 1.5, _at(0, 0, 0), null, 0.0, 4, 6)
		upper.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, elbow_y, -0.01)]), PackedFloat32Array([shoulder, elbow]), 6)
		fore.add_blob(Vector3.ONE * elbow * 1.5, _at(0, 0, -0.01), null, 0.0, 4, 6)
		fore.add_tube(PackedVector3Array([Vector3(0, 0, -0.01), Vector3(0, -fore_len, 0)]), PackedFloat32Array([elbow, wrist]), 6)
		fore.add_blob(Vector3(0.042, 0.055, 0.042), _at(0, -fore_len - 0.055, 0), null, 0.0, 4, 6)
		for x: float in [-0.022, 0.0, 0.022]:
			fore.add_tube(PackedVector3Array([Vector3(x, -fore_len - 0.09, 0), Vector3(x * 1.3, -fore_len - 0.15, 0.012)]), PackedFloat32Array([0.01, 0.006]), 4)
		return {"arm": upper.commit(), "fore": fore.commit()}
	if fine:
		upper.add_blob(Vector3(shoulder, shoulder * 0.95, shoulder) * 1.16, _at(0, -0.015, 0), null, 0.0, 6, seg)
		upper.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, elbow_y * 0.5, -0.006), Vector3(0, elbow_y, -0.012)]),
			PackedFloat32Array([shoulder, lerpf(shoulder, elbow, 0.4), elbow]), seg)
	else:
		upper.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, elbow_y, -0.012)]), PackedFloat32Array([shoulder, elbow]), seg)
	fore.add_blob(Vector3.ONE * elbow * 1.05, _at(0, 0, -0.012), null, 0.0, 6 if fine else 4, seg)
	var end: float = o.get("flare", wrist)
	fore.add_tube(PackedVector3Array([Vector3(0, 0, -0.012), Vector3(0, -fore_len, 0)]), PackedFloat32Array([elbow, end]), seg)
	if o.has("bracer"):
		fore.color = o.bracer
		fore.add_tube(PackedVector3Array([Vector3(0, -fore_len * 0.3, -0.008), Vector3(0, -fore_len, 0)]),
			PackedFloat32Array([lerpf(elbow, end, 0.3) + 0.012, end + 0.012]), seg)
		if fine:
			fore.color = INK
			_band(fore, lerpf(elbow, end, 0.3) + 0.012, -fore_len * 0.3, 0.012, 0.008, seg)
	if fine and o.has("cuff"):
		fore.color = o.cuff
		_band(fore, end, -fore_len + 0.02, 0.024, 0.014, seg)
	if o.has("flare"):
		# The dark inside of a wide sleeve.
		fore.color = fore_color.darkened(0.6)
		fore.add_lathe(PackedVector2Array([Vector2(0.0, -fore_len + 0.02), Vector2(end - 0.01, -fore_len)]), seg)
	# The hand: a palm, a thumb and a row of fingers.
	fore.color = skin
	fore.add_blob(Vector3(0.052, 0.062, 0.046) * h, _at(0, -fore_len - 0.062 * h, 0.004), null, 0.0, 6 if fine else 4, 8)
	if fine:
		fore.add_blob(Vector3(0.02, 0.038, 0.022) * h, Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, -fore_len - 0.055 * h, 0.05 * h)), null, 0.0, 4, 6)
		fore.color = skin.darkened(0.08)
		for x: float in [-0.03, -0.01, 0.01, 0.03]:
			fore.add_blob(Vector3(0.012, 0.034, 0.016) * h, _at(x * h, -fore_len - 0.118 * h, 0.012 * h), null, 0.0, 4, 5)
		if o.get("claws", false):
			fore.color = INK
			for x: float in [-0.03, 0.0, 0.03]:
				fore.add_blob(Vector3(0.012, 0.03, 0.012) * h, _at(x * h, -fore_len - 0.155 * h, 0.02 * h), null, 0.0, 4, 5)
	return {"arm": upper.commit(), "fore": fore.commit()}


## The whole of a look: `body` committed, with two-part legs and arms.
static func _look_of(body: MeshBuilder, leg: Dictionary, arm: Dictionary, fine: bool, suffix := "") -> Dictionary:
	var out := {"body" + suffix: body.commit(), "knee_y": leg.get("knee_y", KNEE_Y), "elbow_y": arm.get("elbow_y", ELBOW_Y)}
	var legs := _leg_parts(leg, fine)
	var arms := _arm_parts(arm, fine)
	out["leg" + suffix] = legs.leg
	out["shin" + suffix] = legs.shin
	out["arm" + suffix] = arms.arm
	out["fore" + suffix] = arms.fore
	return out


## A head with a jaw, ears, a nose, eyes with whites, lids and brows, and
## a mouth. It is centred at height `y`; the face is `z` in front of it.
## `brow` is the colour of the eyebrows.
static func _head(mb: MeshBuilder, skin: Color, y: float, z: float, grim := false, brow := INK) -> void:
	mb.color = skin
	mb.add_blob(Vector3(0.155, 0.175, 0.165), _at(0, y, 0), null, 0.0, 12, 18)
	mb.add_blob(Vector3(0.118, 0.085, 0.12), _at(0, y - 0.105, 0.03), null, 0.0, 6, 12)
	for sx: float in [-1.0, 1.0]:
		mb.color = skin
		mb.add_blob(Vector3(0.03, 0.052, 0.036), _at(sx * 0.155, y, 0.0), null, 0.0, 5, 8)
		mb.color = skin.darkened(0.22)
		mb.add_blob(Vector3(0.012, 0.03, 0.02), _at(sx * 0.172, y, 0.012), null, 0.0, 4, 6)
		# Cheeks with a little colour in them.
		mb.color = skin.lerp(Color(0.95, 0.45, 0.4), 0.22)
		mb.add_blob(Vector3(0.036, 0.03, 0.02), _at(sx * 0.096, y - 0.045, z - 0.05), null, 0.0, 4, 8)
		# Eyes: a white, a dark pupil with a glint, an upper lid and a brow.
		mb.color = Color(0.97, 0.96, 0.92)
		mb.add_blob(Vector3(0.034, 0.04, 0.016), _at(sx * 0.06, y + 0.026, z - 0.02), null, 0.0, 5, 8)
		mb.color = INK
		mb.add_blob(Vector3(0.019, 0.026, 0.012), _at(sx * 0.058, y + 0.022, z - 0.008), null, 0.0, 4, 6)
		mb.add_box(Vector3(0.07, 0.012, 0.012), 0.003, Transform3D(Basis(Vector3.BACK, sx * (0.1 if grim else -0.06)), Vector3(sx * 0.06, y + 0.062, z - 0.018)))
		mb.color = Color(1.0, 1.0, 1.0)
		mb.add_blob(Vector3(0.006, 0.007, 0.005), _at(sx * 0.058 + 0.007, y + 0.032, z + 0.002), null, 0.0, 3, 4)
		mb.color = brow
		mb.add_box(Vector3(0.068, 0.018, 0.016), 0.004,
			Transform3D(Basis(Vector3.BACK, sx * (0.32 if grim else -0.14)), Vector3(sx * 0.06, y + 0.092, z - 0.02)))
	mb.color = skin.darkened(0.14)
	mb.add_blob(Vector3(0.03, 0.04, 0.045), _at(0.0, y - 0.012, z + 0.008), null, 0.0, 5, 8)
	mb.color = INK
	mb.add_box(Vector3(0.078 if grim else 0.064, 0.013, 0.012), 0.003, _at(0.0, y - 0.078, z - 0.018))
	mb.color = skin.darkened(0.2)
	mb.add_blob(Vector3(0.03, 0.012, 0.012), _at(0.0, y - 0.097, z - 0.02), null, 0.0, 3, 6)
	if not grim:
		# The corners of the mouth turn up.
		mb.color = INK
		for sx: float in [-1.0, 1.0]:
			mb.add_box(Vector3(0.018, 0.012, 0.012), 0.003, Transform3D(Basis(Vector3.BACK, sx * 0.7), Vector3(sx * 0.036, y - 0.072, z - 0.022)))


## A neck, and a body that is wider than it is deep: `profile` is spun
## round and then flattened front to back.
static func _trunk(mb: MeshBuilder, profile: PackedVector2Array, lobes := 0, depth := 0.0) -> void:
	mb.add_lathe(profile, 20, _flat_body(), lobes, depth)


static func _flat_body() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(1.0, 1.0, BODY_DEPTH)), Vector3.ZERO)


## A band round a body made with _trunk(): `r` is its radius at height `y`.
static func _hoop(mb: MeshBuilder, r: float, y: float, half: float, out := 0.012) -> void:
	mb.add_lathe(PackedVector2Array([Vector2(r, y - half), Vector2(r + out, y), Vector2(r, y + half)]), 20, _flat_body())


static func _villager_leg(c: Dictionary) -> Dictionary:
	return {"color": c.trousers, "boot": SHOE.lerp(c.trousers, 0.15), "boot_top": 0.13 if c.boots else 0.0, "cuff": c.trousers.darkened(0.5),
		"kneepad": c.trousers.lightened(0.18)}


static func _villager_arm(c: Dictionary) -> Dictionary:
	var sleeve: Color = (c.tunic as Color).darkened(0.1)
	if c.rolled:
		# Sleeves rolled to the elbow.
		return {"color": sleeve, "fore_color": c.skin, "hand": c.skin}
	return {"color": sleeve, "cuff": (c.tunic as Color).darkened(0.55), "hand": c.skin}


static func _villager_far(c: Dictionary) -> Dictionary:
	var body := MeshBuilder.new()
	body.color = c.tunic
	var hem: float = 0.35 if c.skirt else 0.72
	body.add_lathe(PackedVector2Array([Vector2(0.0, hem), Vector2(0.33 if c.skirt else 0.25, hem), Vector2(0.21, 1.0),
		Vector2(0.25, 1.3), Vector2(0.13, 1.44), Vector2(0.0, 1.46)]), 10, _flat_body())
	body.color = (c.tunic as Color).darkened(0.45)
	_band(body, 0.2, 1.02, 0.04, 0.015, 10)
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
			body.color = (c.tunic as Color).darkened(0.25)
			body.add_blob(Vector3(0.19, 0.2, 0.2), _at(0, 1.6, -0.04), null, 0.0, 6, 10)
		_: # Bare head with hair
			body.color = c.hair
			body.add_blob(Vector3(0.165, 0.14, 0.175), _at(0, 1.64, -0.03), null, 0.0, 6, 10)
	if c.apron:
		body.color = APRON
		body.add_box(Vector3(0.24, 0.5, 0.02), 0.004, Transform3D(Basis(Vector3.RIGHT, -0.22 if c.skirt else -0.08), Vector3(0, 0.88, 0.215)))
	return _look_of(body, _villager_leg(c), _villager_arm(c), false)


static func _villager_near(c: Dictionary) -> Dictionary:
	var body := MeshBuilder.new()
	var tunic: Color = c.tunic
	var hem: float = 0.35 if c.skirt else 0.7
	var flare: float = 0.37 if c.skirt else 0.27
	var depth := BODY_DEPTH
	# The tunic: shoulders, chest and waist, and below the belt a skirt
	# that hangs in folds (or the short skirts of a jerkin).
	body.color = tunic
	_trunk(body, PackedVector2Array([Vector2(0.0, 0.98), Vector2(0.214, 0.98), Vector2(0.22, 1.08), Vector2(0.248, 1.2), Vector2(0.262, 1.3),
		Vector2(0.236, 1.39), Vector2(0.13, 1.45), Vector2(0.0, 1.46)]))
	_trunk(body, PackedVector2Array([Vector2(0.0, hem), Vector2(flare, hem), Vector2(flare - 0.012, hem + 0.07), Vector2(0.245, 0.9), Vector2(0.214, 1.0)]),
		10 if c.skirt else 6, 0.04 if c.skirt else 0.015)
	for sx: float in [-1.0, 1.0]:
		body.add_blob(Vector3(0.095, 0.07, 0.1), _at(sx * 0.21, 1.365, 0.0), null, 0.0, 6, 10)
	# Dark trim at the hem and a paler collar.
	body.color = tunic.darkened(0.55)
	_hoop(body, flare - 0.004, hem + 0.03, 0.03, 0.02)
	body.color = tunic.lightened(0.35)
	_hoop(body, 0.105, 1.462, 0.034, 0.03)
	body.add_box(Vector3(0.08, 0.07, 0.02), 0.006, Transform3D(Basis(Vector3.BACK, 0.5), Vector3(0.045, 1.43, 0.1)))
	body.add_box(Vector3(0.08, 0.07, 0.02), 0.006, Transform3D(Basis(Vector3.BACK, -0.5), Vector3(-0.045, 1.43, 0.1)))
	# A belt with a buckle, a pouch on one hip and a knife on the other.
	body.color = Color(0.2, 0.13, 0.09)
	_hoop(body, 0.214, 1.01, 0.042, 0.024)
	body.color = Color(0.92, 0.74, 0.25)
	body.add_box(Vector3(0.075, 0.075, 0.03), 0.01, _at(0, 1.01, 0.214 * depth + 0.022))
	body.color = INK
	body.add_box(Vector3(0.035, 0.035, 0.034), 0.006, _at(0, 1.01, 0.214 * depth + 0.024))
	body.color = LEATHER
	body.add_box(Vector3(0.09, 0.1, 0.06), 0.015, _at(0.19, 0.93, 0.06))
	body.color = LEATHER.darkened(0.45)
	body.add_box(Vector3(0.094, 0.04, 0.064), 0.012, _at(0.19, 0.965, 0.06))
	body.color = Color(0.95, 0.9, 0.75)
	body.add_blob(Vector3(0.012, 0.012, 0.012), _at(0.19, 0.945, 0.094), null, 0.0, 3, 5)
	body.color = LEATHER.darkened(0.3)
	body.add_tube(PackedVector3Array([Vector3(-0.2, 1.0, 0.05), Vector3(-0.225, 0.82, 0.03)]), PackedFloat32Array([0.022, 0.012]), 6)
	body.color = Art.WOOD
	body.add_tube(PackedVector3Array([Vector3(-0.198, 1.0, 0.05), Vector3(-0.19, 1.07, 0.055)]), PackedFloat32Array([0.016, 0.018]), 6)
	if c.apron:
		# An apron with a bib, a pocket and ties.
		body.color = APRON
		body.add_box(Vector3(0.27, 0.5, 0.018), 0.006, Transform3D(Basis(Vector3.RIGHT, -0.24 if c.skirt else -0.08), Vector3(0, 0.84, 0.222)))
		body.add_box(Vector3(0.18, 0.24, 0.018), 0.006, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 1.2, 0.216)))
		body.color = APRON.darkened(0.25)
		body.add_box(Vector3(0.11, 0.09, 0.02), 0.006, Transform3D(Basis(Vector3.RIGHT, -0.24 if c.skirt else -0.08), Vector3(0.04, 0.8, 0.24)))
		for sx: float in [-1.0, 1.0]:
			body.add_tube(PackedVector3Array([Vector3(sx * 0.08, 1.3, 0.215), Vector3(sx * 0.1, 1.44, 0.07)]), PackedFloat32Array([0.012, 0.012]), 5)
	else:
		# Buttons down the front, an inked seam and a patch.
		body.color = INK
		body.add_box(Vector3(0.01, 0.3, 0.01), 0.003, Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0, 1.2, 0.214)))
		body.color = Color(0.93, 0.88, 0.7)
		for k in 3:
			body.add_blob(Vector3(0.016, 0.016, 0.01), _at(0.018, 1.11 + 0.095 * k, 0.196 + 0.012 * k), null, 0.0, 4, 6)
		body.color = c.hat_color
		body.add_box(Vector3(0.075, 0.07, 0.012), 0.004, Transform3D(Basis(Vector3.BACK, 0.25) * Basis(Vector3.UP, -0.55), Vector3(-0.13, 1.15, 0.17)))
	if c.scarf:
		body.color = c.hat_color
		_hoop(body, 0.1, 1.44, 0.045, 0.04)
		body.add_blob(Vector3(0.04, 0.035, 0.035), _at(0.06, 1.42, 0.11), null, 0.0, 4, 7)
		body.add_tube(PackedVector3Array([Vector3(0.06, 1.42, 0.12), Vector3(0.085, 1.3, 0.2), Vector3(0.08, 1.2, 0.215)]), PackedFloat32Array([0.03, 0.028, 0.02]), 6)
	body.color = c.skin
	body.add_tube(PackedVector3Array([Vector3(0, 1.4, 0), Vector3(0, 1.5, 0)]), PackedFloat32Array([0.075, 0.07]), 10)
	var hair: Color = c.hair
	_head(body, c.skin, 1.6, 0.165, false, hair.darkened(0.35))
	if c.beard:
		body.color = hair
		body.add_blob(Vector3(0.1, 0.065, 0.07), _at(0, 1.455, 0.085), null, 0.0, 6, 10)
		for sx: float in [-1.0, 1.0]:
			body.add_blob(Vector3(0.04, 0.016, 0.018), Transform3D(Basis(Vector3.BACK, sx * -0.35), Vector3(sx * 0.035, 1.537, 0.166)), null, 0.0, 4, 6)
			body.add_blob(Vector3(0.024, 0.07, 0.04), _at(sx * 0.14, 1.53, 0.03), null, 0.0, 4, 6)
	match c.hat:
		0: # Pointed hat with a brim, a band, a buckle and a flopping tip
			body.color = c.hat_color
			body.add_lathe(PackedVector2Array([Vector2(0.0, 1.67), Vector2(0.3, 1.655), Vector2(0.3, 1.685), Vector2(0.16, 1.72)]), 20)
			var cone := body.add_lathe(PackedVector2Array([Vector2(0.16, 1.72), Vector2(0.14, 1.8), Vector2(0.11, 1.9), Vector2(0.07, 2.0), Vector2(0.03, 2.08), Vector2(0.0, 2.14)]), 16)
			body.bend(cone, 1.72, 2.14, Vector3(0.0, -0.04, -0.17))
			body.color = (c.hat_color as Color).darkened(0.55)
			_band(body, 0.158, 1.75, 0.028, 0.014)
			body.color = Color(0.92, 0.74, 0.25)
			body.add_box(Vector3(0.05, 0.05, 0.02), 0.006, _at(0, 1.75, 0.165))
			body.color = hair
			body.add_blob(Vector3(0.162, 0.1, 0.17), _at(0, 1.6, -0.04), null, 0.0, 6, 10)
		1: # Straw hat with a ribbon and a frayed brim
			body.color = STRAW
			body.add_lathe(PackedVector2Array([Vector2(0.0, 1.66), Vector2(0.38, 1.63), Vector2(0.385, 1.66), Vector2(0.17, 1.71),
				Vector2(0.14, 1.8), Vector2(0.0, 1.83)]), 20, Transform3D.IDENTITY, 14, 0.012)
			body.color = STRAW.darkened(0.35)
			_band(body, 0.383, 1.645, 0.016, 0.008, 20)
			_band(body, 0.27, 1.685, 0.008, 0.006, 20)
			body.color = c.hat_color
			_band(body, 0.162, 1.735, 0.028, 0.014)
			body.add_tube(PackedVector3Array([Vector3(0.0, 1.735, -0.17), Vector3(0.03, 1.68, -0.26)]), PackedFloat32Array([0.022, 0.012]), 5)
			body.color = hair
			body.add_blob(Vector3(0.162, 0.1, 0.17), _at(0, 1.6, -0.04), null, 0.0, 6, 10)
		2: # Hood with a dark rim round the face and a little cape
			body.color = tunic.darkened(0.25)
			body.add_blob(Vector3(0.195, 0.205, 0.2), _at(0, 1.61, -0.07), null, 0.0, 10, 14)
			body.add_tube(PackedVector3Array([Vector3(0, 1.72, -0.22), Vector3(0, 1.62, -0.32)]), PackedFloat32Array([0.07, 0.015]), 8)
			_trunk(body, PackedVector2Array([Vector2(0.3, 1.3), Vector2(0.27, 1.4), Vector2(0.11, 1.5)]), 8, 0.012)
			body.color = tunic.darkened(0.6)
			body.add_ring(0.165, 0.016, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.61, 0.085)), 18, 6)
			body.color = hair
			body.add_blob(Vector3(0.1, 0.035, 0.03), _at(0, 1.725, 0.12), null, 0.0, 4, 7)
		_: # Hair: a cap, a fringe, and a braid or a tuft
			body.color = hair
			body.add_blob(Vector3(0.168, 0.14, 0.178), _at(0, 1.655, -0.03), null, 0.0, 10, 14)
			body.add_blob(Vector3(0.15, 0.13, 0.08), _at(0, 1.56, -0.12), null, 0.0, 6, 10)
			for x: float in [-0.1, -0.035, 0.035, 0.1]:
				body.add_blob(Vector3(0.05, 0.04, 0.05), _at(x, 1.715 - 0.03 * absf(x) / 0.1, 0.105), null, 0.0, 4, 6)
			if c.skirt:
				body.add_tube(PackedVector3Array([Vector3(0, 1.62, -0.17), Vector3(0, 1.45, -0.21), Vector3(0, 1.25, -0.215)]),
					PackedFloat32Array([0.045, 0.036, 0.024]), 8)
				body.color = c.hat_color
				body.add_blob(Vector3(0.032, 0.02, 0.032), _at(0, 1.28, -0.215), null, 0.0, 4, 7)
			else:
				body.add_blob(Vector3(0.04, 0.05, 0.04), _at(0.03, 1.79, 0.0), null, 0.0, 4, 6)
	return _look_of(body, _villager_leg(c), _villager_arm(c), true, "_hi")


static func _goblin_leg(skin: Color) -> Dictionary:
	return {"color": skin.darkened(0.15), "bare": true, "toes": true, "top": 0.095, "knee": 0.08, "ankle": 0.07, "foot": Vector3(0.1, 0.06, 0.17)}


static func _goblin_arm(skin: Color, hide: Color) -> Dictionary:
	return {"color": skin, "hand": skin, "cuff": hide.darkened(0.3), "claws": true, "shoulder": 0.078, "elbow": 0.062, "wrist": 0.05,
		"length": 0.6, "elbow_y": -0.32, "hand_size": 1.25}


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
	return _look_of(body, _goblin_leg(skin), _goblin_arm(skin, hide), false)


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
	return _look_of(body, _goblin_leg(skin), _goblin_arm(skin, hide), true, "_hi")


static func _soldier_leg() -> Dictionary:
	return {"color": Color(0.24, 0.2, 0.17), "boot": LEATHER.darkened(0.3), "boot_top": 0.2, "cuff": INK, "kneepad": STEEL, "top": 0.102, "knee": 0.088}


static func _soldier_arm(skin: Color) -> Dictionary:
	return {"color": LEATHER.lightened(0.1), "bracer": STEEL, "hand": skin, "shoulder": 0.086, "elbow": 0.072, "wrist": 0.062}


static func _soldier_far(skin: Color) -> Dictionary:
	var body := MeshBuilder.new()
	body.color = LEATHER
	body.add_lathe(PackedVector2Array([Vector2(0.0, 0.58), Vector2(0.31, 0.58), Vector2(0.23, 1.0),
		Vector2(0.28, 1.3), Vector2(0.14, 1.44), Vector2(0.0, 1.46)]), 10, _flat_body())
	body.color = STEEL
	body.add_lathe(PackedVector2Array([Vector2(0.245, 1.06), Vector2(0.295, 1.3), Vector2(0.15, 1.45)]), 10, _flat_body())
	body.color = skin
	body.add_blob(Vector3(0.15, 0.17, 0.16), _at(0, 1.58, 0), null, 0.0, 6, 10)
	body.color = STEEL
	body.add_lathe(PackedVector2Array([Vector2(0.0, 1.63), Vector2(0.25, 1.61), Vector2(0.25, 1.65), Vector2(0.185, 1.69),
		Vector2(0.14, 1.82), Vector2(0.0, 1.88)]), 10)
	return _look_of(body, _soldier_leg(), _soldier_arm(skin), false)


static func _soldier_near(skin: Color) -> Dictionary:
	var body := MeshBuilder.new()
	var depth := BODY_DEPTH
	# A leather jerkin with a skirt of straps, under a steel breastplate.
	body.color = LEATHER
	_trunk(body, PackedVector2Array([Vector2(0.0, 0.58), Vector2(0.32, 0.58), Vector2(0.3, 0.7), Vector2(0.235, 1.0), Vector2(0.24, 1.1),
		Vector2(0.28, 1.3), Vector2(0.22, 1.4), Vector2(0.11, 1.45), Vector2(0.0, 1.46)]), 10, 0.022)
	body.color = LEATHER.darkened(0.65)
	_hoop(body, 0.31, 0.64, 0.014, 0.008)
	_hoop(body, 0.275, 0.82, 0.012, 0.008)
	body.color = STEEL
	_trunk(body, PackedVector2Array([Vector2(0.246, 1.07), Vector2(0.262, 1.16), Vector2(0.296, 1.3), Vector2(0.262, 1.39), Vector2(0.16, 1.45), Vector2(0.1, 1.47)]))
	body.color = STEEL.lightened(0.25)
	body.add_box(Vector3(0.022, 0.3, 0.02), 0.006, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 1.23, 0.275 * depth + 0.004)))
	body.color = INK
	_hoop(body, 0.25, 1.075, 0.012, 0.01)
	_hoop(body, 0.15, 1.455, 0.012, 0.012)
	body.color = STEEL.darkened(0.3)
	for sx: float in [-1.0, 1.0]:
		for k in 3:
			body.add_blob(Vector3(0.012, 0.012, 0.008), _at(sx * 0.13, 1.14 + 0.09 * k, (0.25 + 0.016 * k) * depth - 0.012 + 0.01 * k), null, 0.0, 3, 5)
	# Belt, buckle and a scabbard at the hip.
	body.color = Color(0.2, 0.13, 0.09)
	_hoop(body, 0.238, 1.02, 0.045, 0.024)
	body.color = STEEL
	body.add_box(Vector3(0.08, 0.08, 0.03), 0.01, _at(0, 1.02, 0.238 * depth + 0.024))
	body.color = LEATHER.darkened(0.5)
	body.add_tube(PackedVector3Array([Vector3(-0.23, 1.0, 0.04), Vector3(-0.29, 0.5, -0.26)]), PackedFloat32Array([0.032, 0.022]), 8)
	body.color = STEEL
	body.add_blob(Vector3(0.028, 0.035, 0.028), _at(-0.29, 0.5, -0.26), null, 0.0, 4, 6)
	# Shoulder plates in two layers.
	for sx: float in [-1.0, 1.0]:
		body.color = STEEL
		body.add_blob(Vector3(0.135, 0.085, 0.135), _at(sx * 0.265, 1.385, 0.0), null, 0.0, 6, 10)
		body.color = STEEL.darkened(0.2)
		body.add_blob(Vector3(0.115, 0.05, 0.12), _at(sx * 0.305, 1.315, 0.0), null, 0.0, 5, 10)
		body.color = INK
		body.add_blob(Vector3(0.014, 0.014, 0.014), _at(sx * 0.3, 1.4, 0.1), null, 0.0, 3, 5)
	body.color = skin
	body.add_tube(PackedVector3Array([Vector3(0, 1.4, 0), Vector3(0, 1.5, 0)]), PackedFloat32Array([0.075, 0.07]), 10)
	_head(body, skin, 1.6, 0.165, true)
	# A steel helmet with a rim, a nose guard, cheek plates and a red crest.
	body.color = STEEL
	body.add_lathe(PackedVector2Array([Vector2(0.0, 1.64), Vector2(0.2, 1.63), Vector2(0.255, 1.6), Vector2(0.26, 1.635), Vector2(0.19, 1.69),
		Vector2(0.17, 1.76), Vector2(0.13, 1.84), Vector2(0.06, 1.885), Vector2(0.0, 1.895)]), 20)
	body.add_box(Vector3(0.045, 0.17, 0.035), 0.008, _at(0, 1.6, 0.19))
	for sx: float in [-1.0, 1.0]:
		body.add_box(Vector3(0.03, 0.15, 0.11), 0.008, Transform3D(Basis(Vector3.BACK, sx * 0.12), Vector3(sx * 0.165, 1.555, 0.05)))
	body.color = INK
	_band(body, 0.188, 1.7, 0.012, 0.01, 20)
	body.color = Color(0.74, 0.15, 0.12)
	for k in 5:
		var a := -0.9 + 0.45 * k
		body.add_box(Vector3(0.04, 0.09, 0.075), 0.012, Transform3D(Basis(Vector3.RIGHT, -a), Vector3(0, 1.69 + 0.215 * cos(a), -0.01 + 0.2 * sin(a))))
	return _look_of(body, _soldier_leg(), _soldier_arm(skin), true, "_hi")


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
	_ogre_look = _look_of(body,
		{"color": skin.darkened(0.1), "bare": true, "toes": true, "top": 0.19, "knee": 0.16, "ankle": 0.14, "length": 0.68,
			"foot": Vector3(0.17, 0.09, 0.26)},
		{"color": skin, "hand": skin, "cuff": hide.darkened(0.3), "shoulder": 0.155, "elbow": 0.13, "wrist": 0.118, "length": 0.75,
			"elbow_y": -0.4, "hand_size": 2.2}, true)
	_ogre_look["leg_x"] = 0.2
	_ogre_look["arm_x"] = 0.58

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
			"apron": rng.randf() < 0.35,
			"scarf": rng.randf() < 0.3,
			"boots": rng.randf() < 0.5,
			"rolled": rng.randf() < 0.4,
			"beard": false,
		}
		c.beard = not c.skirt and rng.randf() < 0.45
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

	# Wizards: long robes sewn with stars, a rope belt, a white beard and a
	# tall pointed hat, in night colours.
	var robes := [Color(0.24, 0.2, 0.55), Color(0.36, 0.16, 0.5), Color(0.14, 0.3, 0.52), Color(0.5, 0.14, 0.3)]
	var gold := Color(0.95, 0.8, 0.3)
	var white := Color(0.92, 0.92, 0.94)
	for k in robes.size():
		var robe: Color = robes[k]
		var skin: Color = Art.SKIN_COLORS[k % Art.SKIN_COLORS.size()]
		var body := MeshBuilder.new()
		body.color = robe
		_trunk(body, PackedVector2Array([Vector2(0.0, 0.06), Vector2(0.39, 0.06), Vector2(0.37, 0.16), Vector2(0.29, 0.6), Vector2(0.235, 0.95),
			Vector2(0.225, 1.02), Vector2(0.25, 1.25), Vector2(0.24, 1.38), Vector2(0.13, 1.45), Vector2(0.0, 1.46)]), 11, 0.03)
		# A short cape over the shoulders.
		body.color = robe.darkened(0.2)
		_trunk(body, PackedVector2Array([Vector2(0.3, 1.25), Vector2(0.325, 1.27), Vector2(0.29, 1.4), Vector2(0.11, 1.49)]), 9, 0.012)
		body.color = gold
		_hoop(body, 0.385, 0.1, 0.035, 0.014)
		_hoop(body, 0.322, 1.275, 0.014, 0.01)
		body.add_blob(Vector3(0.03, 0.03, 0.02), _at(0, 1.44, 0.105), null, 0.0, 4, 7)
		# Stars and moons sewn on the robe.
		for j in 9:
			var a := -1.5 + 0.42 * j + 0.2 * (j % 2)
			var y := 0.28 + 0.2 * ((j * 3) % 4) + 0.05 * (j % 3)
			var r := lerpf(0.37, 0.235, clampf((y - 0.16) / 0.79, 0.0, 1.0)) + 0.004
			body.add_blob(Vector3(0.024, 0.024, 0.01), Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * r, y, cos(a) * r * BODY_DEPTH)), null, 0.0, 3, 5)
		# A rope belt, knotted, with a pouch and a scroll.
		body.color = Color(0.85, 0.75, 0.5)
		_hoop(body, 0.226, 1.0, 0.028, 0.022)
		body.add_blob(Vector3(0.034, 0.034, 0.03), _at(0.07, 1.0, 0.2), null, 0.0, 4, 6)
		body.add_tube(PackedVector3Array([Vector3(0.07, 1.0, 0.205), Vector3(0.085, 0.8, 0.235)]), PackedFloat32Array([0.016, 0.012]), 5)
		body.add_tube(PackedVector3Array([Vector3(0.07, 1.0, 0.205), Vector3(0.045, 0.84, 0.23)]), PackedFloat32Array([0.016, 0.012]), 5)
		body.color = LEATHER
		body.add_box(Vector3(0.09, 0.1, 0.06), 0.015, _at(-0.19, 0.92, 0.07))
		body.color = Color(0.93, 0.9, 0.78)
		body.add_tube(PackedVector3Array([Vector3(-0.24, 0.88, -0.05), Vector3(-0.2, 1.04, 0.0)]), PackedFloat32Array([0.022, 0.022]), 6)
		body.color = skin
		body.add_tube(PackedVector3Array([Vector3(0, 1.4, 0), Vector3(0, 1.5, 0)]), PackedFloat32Array([0.075, 0.07]), 10)
		_head(body, skin, 1.6, 0.165, false, white)
		# Long white hair, a moustache and a beard to the belt.
		body.color = white
		body.add_blob(Vector3(0.17, 0.16, 0.12), _at(0, 1.56, -0.09), null, 0.0, 6, 10)
		for sx: float in [-1.0, 1.0]:
			body.add_blob(Vector3(0.04, 0.12, 0.07), _at(sx * 0.14, 1.52, 0.02), null, 0.0, 5, 7)
			body.add_blob(Vector3(0.05, 0.022, 0.024), Transform3D(Basis(Vector3.BACK, sx * -0.4), Vector3(sx * 0.04, 1.535, 0.168)), null, 0.0, 4, 6)
		body.add_blob(Vector3(0.12, 0.1, 0.075), _at(0, 1.48, 0.1), null, 0.0, 6, 10)
		body.add_blob(Vector3(0.1, 0.12, 0.065), _at(0, 1.37, 0.15), null, 0.0, 6, 10)
		body.add_blob(Vector3(0.07, 0.11, 0.05), _at(0, 1.25, 0.18), null, 0.0, 5, 8)
		body.add_tube(PackedVector3Array([Vector3(0, 1.2, 0.185), Vector3(0, 1.08, 0.215)]), PackedFloat32Array([0.04, 0.006]), 6)
		# The hat: a wide brim and a tall crooked point, with a band and a buckle.
		body.color = robe.darkened(0.2)
		body.add_lathe(PackedVector2Array([Vector2(0.0, 1.67), Vector2(0.35, 1.65), Vector2(0.355, 1.68), Vector2(0.17, 1.73)]), 20, Transform3D.IDENTITY, 9, 0.012)
		var point := body.add_lathe(PackedVector2Array([Vector2(0.17, 1.73), Vector2(0.15, 1.85), Vector2(0.115, 2.0), Vector2(0.08, 2.15), Vector2(0.04, 2.3),
			Vector2(0.0, 2.42)]), 16)
		body.bend(point, 1.73, 2.42, Vector3(0.05, -0.06, -0.22))
		body.color = gold
		_band(body, 0.168, 1.765, 0.03, 0.014, 16)
		body.add_box(Vector3(0.06, 0.06, 0.022), 0.006, _at(0, 1.765, 0.178))
		body.add_blob(Vector3(0.026, 0.026, 0.012), _at(0.012, 1.98, 0.105), null, 0.0, 3, 5)
		_wizard_looks.append(_look_of(body, {"color": robe.darkened(0.35), "boot": SHOE, "top": 0.085, "knee": 0.076},
			{"color": robe, "flare": 0.105, "cuff": gold, "hand": skin, "shoulder": 0.092, "elbow": 0.082}, true))
	# Archers: a hooded green jerkin laced up the front, a bracer, tall
	# boots, a quiver on the back and a longbow.
	var green := Color(0.2, 0.42, 0.2)
	for skin: Color in Art.SKIN_COLORS:
		var body := MeshBuilder.new()
		body.color = green
		_trunk(body, PackedVector2Array([Vector2(0.0, 0.62), Vector2(0.29, 0.62), Vector2(0.28, 0.7), Vector2(0.215, 1.0), Vector2(0.222, 1.1), Vector2(0.252, 1.28),
			Vector2(0.23, 1.39), Vector2(0.13, 1.45), Vector2(0.0, 1.46)]), 7, 0.018)
		for sx: float in [-1.0, 1.0]:
			body.add_blob(Vector3(0.095, 0.07, 0.1), _at(sx * 0.21, 1.365, 0.0), null, 0.0, 6, 10)
		body.color = green.darkened(0.5)
		_hoop(body, 0.286, 0.65, 0.022, 0.012)
		# Lacing.
		body.color = Color(0.9, 0.84, 0.66)
		for j in 3:
			for sx: float in [-1.0, 1.0]:
				body.add_box(Vector3(0.07, 0.012, 0.01), 0.003, Transform3D(Basis(Vector3.BACK, sx * 0.6), Vector3(0, 1.15 + 0.075 * j, 0.2 + 0.008 * j)))
		body.color = Color(0.2, 0.13, 0.09)
		_hoop(body, 0.216, 1.02, 0.04, 0.022)
		body.color = Color(0.92, 0.74, 0.25)
		body.add_box(Vector3(0.07, 0.07, 0.03), 0.01, _at(0, 1.02, 0.216 * BODY_DEPTH + 0.02))
		body.color = LEATHER
		body.add_box(Vector3(0.09, 0.1, 0.06), 0.015, _at(0.19, 0.94, 0.06))
		# The strap of the quiver across the chest.
		body.color = LEATHER.darkened(0.3)
		body.add_tube(PackedVector3Array([Vector3(-0.2, 1.4, 0.05), Vector3(-0.05, 1.25, 0.2), Vector3(0.17, 1.06, 0.15)]), PackedFloat32Array([0.016, 0.016, 0.016]), 5)
		body.color = skin
		body.add_tube(PackedVector3Array([Vector3(0, 1.4, 0), Vector3(0, 1.5, 0)]), PackedFloat32Array([0.075, 0.07]), 10)
		_head(body, skin, 1.6, 0.165)
		body.color = green.darkened(0.25)
		body.add_blob(Vector3(0.195, 0.2, 0.2), _at(0, 1.62, -0.07), null, 0.0, 10, 14)
		body.add_tube(PackedVector3Array([Vector3(0, 1.74, -0.18), Vector3(0, 1.66, -0.32)]), PackedFloat32Array([0.07, 0.015]), 8)
		_trunk(body, PackedVector2Array([Vector2(0.3, 1.3), Vector2(0.27, 1.4), Vector2(0.11, 1.5)]), 8, 0.012)
		body.color = green.darkened(0.6)
		body.add_ring(0.165, 0.016, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.62, 0.085)), 18, 6)
		body.color = LEATHER
		body.add_tube(PackedVector3Array([Vector3(0.1, 0.95, -0.24), Vector3(-0.12, 1.5, -0.24)]), PackedFloat32Array([0.07, 0.075]), 10)
		body.color = LEATHER.darkened(0.5)
		body.add_ring(0.076, 0.012, Transform3D(Basis(Vector3.BACK, 0.38) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.12, 1.5, -0.24)), 10, 5)
		for j in 4:
			var x := -0.12 + 0.03 * (j - 1.5)
			body.color = Art.WOOD
			body.add_tube(PackedVector3Array([Vector3(x, 1.5, -0.24), Vector3(x - 0.04, 1.66, -0.24)]), PackedFloat32Array([0.008, 0.008]), 4)
			body.color = Color(0.95, 0.9, 0.75) if j % 2 == 0 else Color(0.75, 0.2, 0.15)
			body.add_box(Vector3(0.012, 0.07, 0.04), 0.003, Transform3D(Basis(Vector3.BACK, 0.25), Vector3(x - 0.05, 1.7, -0.24)))
		_archer_looks.append(_look_of(body, {"color": Color(0.32, 0.24, 0.16), "boot": LEATHER.darkened(0.3), "boot_top": 0.18, "cuff": LEATHER.lightened(0.15)},
			{"color": green.lightened(0.08), "bracer": LEATHER, "hand": skin}, true))
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
		_head(body, skin, 1.6, 0.165, true)
		# Wild black hair.
		body.color = Color(0.07, 0.06, 0.09)
		body.add_blob(Vector3(0.185, 0.16, 0.19), _at(0, 1.68, -0.05), null, 0.0, 6, 10)
		for k in 7:
			var a := -1.9 + 3.8 * k / 6.0
			var out := Vector3(sin(a), 0.75, -0.25 - 0.3 * cos(a)).normalized()
			body.add_tube(PackedVector3Array([Vector3(0, 1.68, -0.05) + out * 0.12, Vector3(0, 1.68, -0.05) + out * (0.3 + 0.07 * (k % 2))]),
				PackedFloat32Array([0.06, 0.008]), 5)
		_necro_looks.append(_look_of(body, {"color": night.darkened(0.3), "boot": Color(0.05, 0.05, 0.07), "top": 0.085, "knee": 0.076},
			{"color": night.lightened(0.04), "flare": 0.15, "cuff": rune, "hand": skin, "shoulder": 0.088, "elbow": 0.095}, true))
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
		_skeleton_looks.append(_look_of(body, {"bone": true, "color": bone, "top": 0.036, "knee": 0.03, "ankle": 0.024, "foot": Vector3(0.05, 0.03, 0.11)},
			{"bone": true, "color": bone, "shoulder": 0.03, "elbow": 0.026, "wrist": 0.02}, true))


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
	if _shove.length_squared() > 0.01:
		var next := global_position + _shove * delta
		if _open(next):
			global_position = Vector3(next.x, Game.terrain.get_height(next.x, next.z), next.z)
		_shove = _shove.move_toward(Vector3.ZERO, 16.0 * delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.4
		if not _pink_eyes.is_empty() and not charmed():
			_uncharm()
		_think()
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d := cam.global_position.distance_to(global_position)
			var detail: float = Game.settings.villager_detail
			if detail >= ALWAYS_DETAILED:
				detail = INF
			if _near != (d < detail + (LOD_MARGIN if _near else 0.0)):
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
				if raiding and _raid_i <= _raid_route.size() and not _raid_route.is_empty():
					# On to the next stretch of the path, and at its end the village.
					_target = _raid_route[_raid_i] if _raid_i < _raid_route.size() else _raid_goal
					_raid_i += 1
					return
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
				var site := job_target as ConstructionSite
				if goblin and site:
					# A goblin builder never gives up on its building: it works
					# from here if it is close enough, or tries another spot.
					if _flat_to(site.global_position) > site.footprint + 4.0:
						job_pos = site.work_spot(randi() % 8, 8)
						return
				else:
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
	_drop_pos = Game.village.drop_point(global_position, carry_kind)
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
	pin = ""
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
	_hold("sword", 0, Vector3(0.0, -0.55, 0.0))
	_hold("shield", 1, Vector3(0.09, -0.36, 0.04))
	Game.effects.spawn_dust(global_position, 0.5)


func _add_gear(kind: String, parent: Node3D, pos: Vector3, material: Material = null) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _gear[kind]
	mi.material_override = material if material else Art.cloth()
	mi.position = pos
	parent.add_child(mi)
	_gear_nodes.append(mi)


## Puts a piece of gear in (or on) hand `k`. `pos` is measured from the
## shoulder with the arm hanging straight.
func _hold(kind: String, k: int, pos: Vector3, material: Material = null) -> void:
	_add_gear(kind, _fores[k], pos - Vector3(0.0, _look.elbow_y, 0.0), material)


func _wear(look: Dictionary) -> void:
	_look = look
	_apply_lod(_near)


## Trained at a Wizardry tower: a robe, a tall hat and a glowing staff.
func become_wizard(post: Vector3) -> void:
	if wizard or soldier or goblin or state == State.DEAD:
		return
	_unload()
	clear_job()
	pin = ""
	wizard = true
	add_to_group("wizards")
	home = post
	home_radius = 10.0
	_wear(_wizard_looks[randi() % _wizard_looks.size()])
	_hold("staff", 0, Vector3(0.0, -0.55, 0.08))
	_hold("orb", 0, Vector3(0.0, -0.55, 0.08), Art.glow(3.0))
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
	_hold("soul", 0, Vector3(0.0, -0.62, 0.04), Art.glow(3.0))
	_hold("book", 1, Vector3(0.0, -0.6, 0.1))
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
				if there > 40.0:
					continue
			elif there + bridge.length + 8.0 + Vector2(far.x - goal.x, far.z - goal.z).length() > _flat_to(goal) * 1.5 + 12.0:
				# Too far out of the way.
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
	pin = ""
	archer = true
	add_to_group("archers")
	home = post
	home_radius = 10.0
	max_hp = HEALTH * ARCHER_HEALTH
	hp = max_hp
	_wear(_archer_looks[randi() % _archer_looks.size()])
	_hold("bow", 1, Vector3(0.0, -0.55, 0.0))
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

## Goblins: leave for the village. `goal` is where they gather, and
## `route` the points to pass on the way there (a path from the map editor).
func start_raid(goal: Vector3, route := PackedVector3Array()) -> void:
	if not goblin or state == State.DEAD or state == State.HELD or state == State.BURNING:
		return
	raiding = true
	add_to_group("raiders")
	_raid_goal = goal
	_raid_route = route
	_raid_i = 0
	_target = goal
	if not route.is_empty():
		_target = route[0]
		_raid_i = 1
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
	if goblin and charmed():
		# Charmed: it goes for the nearest goblin that is not.
		if state == State.FIGHT and _foe_ok():
			return
		var rival := _nearest_goblin(AGGRO * 2.0)
		if rival != null:
			_engage(rival)
		return
	if goblin:
		if not raiding or (state == State.FIGHT and _foe_ok() and (_foe is Villager or _foe is Creature)):
			return
		var victim := _nearest_villager(AGGRO)
		# The creature is fair game when it is close, unless a villager is closer.
		var beast := Game.creature
		if is_instance_valid(beast) and not beast.knocked_out and not beast.is_flying():
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
	# Anyone who can shoot always goes for a giant bat first.
	if owned and (archer or wizard) and not (_foe is GiantBat and _foe_ok()):
		var bat := _nearest_bat(BAT_SIGHT)
		if bat != null:
			_engage(bat)
			return
	var goblins := get_tree().get_nodes_in_group("goblins")
	var fiend := _fiend()
	if (goblins.is_empty() and fiend == null) or (state == State.FIGHT and _foe_ok()):
		return
	var fighter := can_fight()
	var best: Villager = null
	var reach := SOLDIER_AGGRO if soldier or wizard or archer or skeleton else (AGGRO if fighter else 8.0)
	var best_d := INF
	for node in goblins:
		var g := node as Villager
		if g.charmed():
			continue
		# An enemy is a raider, or a goblin that has walked into the village.
		# When one is close, every grown-up nearby turns out to fight it.
		var close := owned and g.threatens_village()
		if not g.raiding and not close:
			continue
		var d := _flat_to(g.global_position)
		if d < best_d and d < (maxf(reach, DEFEND_REACH) if close and fighter else reach):
			best_d = d
			best = g
	if fiend != null:
		# The Balrog: fighters take it on, the rest keep well clear.
		var d := _flat_to(fiend.global_position) - 2.0 * fiend.size
		if fighter and d < best_d and d < maxf(reach, DEFEND_REACH):
			_engage(fiend)
			return
		if not fighter and d < 14.0 and d < best_d:
			flee(fiend.global_position)
			return
	if best == null:
		return
	if fighter:
		_engage(best)
	else:
		flee(best.global_position)


## The Balrog, if it is out to hurt the village and this is one of the
## village's people. Otherwise null.
func _fiend() -> Creature:
	if not owned:
		return null
	for node in get_tree().get_nodes_in_group("balrogs"):
		var b := node as Creature
		if not b.knocked_out and b.is_threat():
			return b
	return null


## True for a goblin the whole village turns out against: a raider that has
## come close, or any goblin that has walked right into the village.
func threatens_village() -> bool:
	var village := Game.village
	if not goblin or not is_instance_valid(village) or not village.founded or state == State.DEAD:
		return false
	var d := Vector2(global_position.x - village.center.x, global_position.z - village.center.z).length()
	return d < (PlayerVillage.DEFEND_RADIUS if raiding else PlayerVillage.INTRUDER_RADIUS)


## The nearest giant bat in the air within `reach`, or null.
func _nearest_bat(reach: float) -> GiantBat:
	var best: GiantBat = null
	var best_d := reach
	for node in get_tree().get_nodes_in_group("bats"):
		var bat := node as GiantBat
		var d := _flat_to(bat.global_position)
		if bat.is_alive() and d < best_d:
			best_d = d
			best = bat
	return best


func _nearest_villager(reach: float) -> Villager:
	var best: Villager = null
	var best_d := reach
	for node in get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		# (A goblin's victims include goblins that have been charmed.)
		if (v.goblin and not v.charmed()) or v.state == State.DEAD:
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
	if not is_instance_valid(_foe) or (goblin and not raiding and not charmed()):
		return false
	if _foe is GiantBat:
		return (_foe as GiantBat).is_alive()
	var v := _foe as Villager
	if v:
		if v.state == State.DEAD or v.state == State.HELD:
			return false
		if goblin:
			# Goblins fight charmed goblins, and charmed goblins fight goblins.
			return v.charmed() != charmed() if v.goblin else not charmed()
		return not v.charmed() and (v.raiding or v.threatens_village())
	if charmed():
		return false
	var beast := _foe as Creature
	if beast:
		if beast.hostile:
			return owned and not beast.knocked_out and beast.is_threat()
		return raiding and not beast.knocked_out and not beast.is_flying()
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
	if wizard and (_foe is Villager or _foe is Creature or _foe is GiantBat):
		_cast_at(_foe, to, delta)
		return
	if archer and (_foe is Villager or _foe is Creature or _foe is GiantBat):
		_shoot_at(_foe, to, delta)
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
func _shoot_at(foe: Node3D, to: Vector3, delta: float) -> void:
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
func _cast_at(foe: Node3D, to: Vector3, delta: float) -> void:
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
	# Often as not, a stroll over a rope bridge if there is one about.
	# (Not for warriors, archers and wizards, who must be ready for a raid.)
	if not goblin and not soldier and not archer and not wizard and randf() < 0.6 and _try_bridge(home, true):
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


## Moves towards `goal` on the ground, by a route that keeps off cliffs,
## water and steep slopes where it can (see PathGrid). Walking uphill is
## slow, and a sheer cliff cannot be climbed. Returns true when arrived or
## blocked.
func _move_towards(goal: Vector3, speed: float, delta: float) -> bool:
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.3:
		return true
	if Game.now < snared_until or Game.now < _stagger_until:
		# Held fast by roots, or staggered by a shove.
		return false
	if Game.now < slowed_until:
		# Wading through roots.
		speed *= SLOWED_SPEED
	if dist > PATH_FROM:
		var via := _path_aim(goal) - global_position
		via.y = 0.0
		if via.length() > 0.05:
			to = via
			dist = via.length()
	var dir := to / dist
	speed *= _slope_speed(dir)
	var step := dir * minf(speed * delta, dist)
	if not _open(global_position + step) or _is_cliff(dir):
		_path_until = 0.0
		if not raiding:
			return true
		# Raiders feel their way round the island's edge and along a cliff.
		var found := false
		for turn: float in [0.7, 1.4, -0.7, -1.4]:
			var side := step.rotated(Vector3.UP, turn * _steer)
			if _open(global_position + side) and not _is_cliff(side.normalized()):
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


## The next point to make for on the way to `goal`. The route is worked out
## again when the goal moves, and every few seconds in case the ground has
## changed.
func _path_aim(goal: Vector3) -> Vector3:
	if (_path_goal.distance_squared_to(goal) > 9.0 or Game.now >= _path_until) and Game.now >= _path_next:
		_path_next = Game.now + randf_range(0.6, 1.0)
		_path_until = Game.now + randf_range(7.0, 10.0)
		_path_goal = goal
		_path_i = 0
		var grid := Game.path_grid()
		_path = PackedVector3Array() if grid.clear_line(global_position, goal, goblin) else grid.find(global_position, goal, goblin)
	while _path_i < _path.size() and _flat_to(_path[_path_i]) < 1.6:
		_path_i += 1
	return _path[_path_i] if _path_i < _path.size() else goal


## How steeply the ground rises over the next metre in direction `dir`.
func _grade(dir: Vector3) -> float:
	var p := global_position
	var terrain := Game.terrain
	var here := terrain.get_height(p.x, p.z)
	var ahead := terrain.get_height(p.x + dir.x, p.z + dir.z)
	if goblin:
		# Goblins swim: in the water it is the surface that counts.
		here = maxf(here, terrain.water_level_at(p.x, p.z) - 0.8)
		ahead = maxf(ahead, terrain.water_level_at(p.x + dir.x, p.z + dir.z) - 0.8)
	return ahead - here


## True if the step ahead is onto a grey rock slope, too steep to walk
## over (Terrain.is_steep()). Someone already on one may walk off it, but
## not straight up or down it; a goblin swims over whatever is under water.
func _is_cliff(dir: Vector3) -> bool:
	var terrain := Game.terrain
	var p := global_position + dir
	if goblin and terrain.water_depth(p.x, p.z) > 0.3:
		return false
	if not terrain.is_steep(p.x, p.z):
		return false
	return not terrain.is_steep(global_position.x, global_position.z) or absf(_grade(dir)) > Balance.num("cliff_grade")


## 1 on the flat and downhill, falling to Balance "slope_slowest" as the
## climb gets steeper.
func _slope_speed(dir: Vector3) -> float:
	var from := Balance.num("slope_slow_from")
	return lerpf(1.0, Balance.num("slope_slowest"), clampf((_grade(dir) - from) / 0.6, 0.0, 1.0))


## True if the villager may stand at `p`. Only goblins go into the water.
func _open(p: Vector3) -> bool:
	var terrain := Game.terrain
	if not terrain.is_inside(p.x, p.z):
		return false
	return goblin or terrain.water_depth(p.x, p.z) < 0.15


## Eases the limbs on side `k` towards a pose. `thigh` and `arm` swing the
## leg and the arm from the hip and the shoulder (forwards is negative);
## `knee` and `elbow` bend the joints (0 is straight); `out` holds the arm
## away from the body.
func _pose(k: int, thigh: float, knee: float, arm: float, elbow: float, out: float, blend: float, arm_blend := -1.0) -> void:
	var quick := blend if arm_blend < 0.0 else arm_blend
	_legs[k].rotation.x = lerpf(_legs[k].rotation.x, thigh, blend)
	_shins[k].rotation.x = lerpf(_shins[k].rotation.x, knee, blend)
	_arms[k].rotation.x = lerpf(_arms[k].rotation.x, arm, quick)
	_arms[k].rotation.z = lerpf(_arms[k].rotation.z, (1.0 if k == 0 else -1.0) * out, blend)
	_fores[k].rotation.x = lerpf(_fores[k].rotation.x, -elbow, quick)


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
			_pose(k, 0.0, 0.0, -2.4 + 0.25 * sin(_raise_timer * 9.0 + k), 0.45 + 0.25 * sin(_raise_timer * 7.0 + k * 2.0), -0.4, blend)
		return
	var stride := 0.0
	var lift := 0.0
	if _moving:
		_phase += delta * (17.0 if panicking else 8.5)
		stride = sin(_phase) * (0.9 if panicking else 0.55)
		lift = cos(_phase)
		_body.position.y = absf(lift) * 0.05
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, blend)
	_body.rotation.x = lerpf(_body.rotation.x, 0.22 if panicking and _moving else 0.0, blend)
	for k in 2:
		var s := 1.0 if k == 0 else -1.0
		# The knee bends while the leg swings forward, and straightens to land.
		var knee := 0.0
		if _moving:
			knee = 0.08 + (1.5 if panicking else 1.05) * maxf(0.0, -lift * s)
		# Panicking villagers throw their arms in the air.
		var arm := -2.7 + sin(_phase * 1.3 + k) * 0.35 if panicking else -stride * s * 0.8
		var elbow := 0.5 + 0.3 * sin(_phase * 1.7 + k * 2.0) if panicking else (0.3 + 0.55 * maxf(0.0, -arm) if _moving else 0.14)
		if _delivering and _pushing and state == State.JOB:
			# Both hands on the wheelbarrow.
			arm = -0.48
			elbow = 0.14
		_pose(k, stride * s, knee, arm, elbow, -0.35 if panicking else -0.08, blend)


## Chopping, digging, foraging and hammering poses.
func _animate_work(blend: float) -> void:
	var swing := 0.5 + 0.5 * sin(_work_phase)
	var lean := 0.0
	var arms := [0.0, 0.0]
	var elbows := [0.2, 0.2]
	var thigh := 0.0
	var knee := 0.0
	match job:
		"food", "farm":
			# Stooping, knees bent, hands busy near the ground.
			lean = 0.55
			thigh = -0.4
			knee = 0.8
			arms = [-0.75 + 0.3 * sin(_work_phase), -0.75 + 0.3 * sin(_work_phase + 1.7)]
			elbows = [0.45 + 0.3 * sin(_work_phase + 0.8), 0.45 + 0.3 * sin(_work_phase + 2.5)]
		"plant":
			# Down on its knees, working the soil with both hands.
			lean = 0.4
			thigh = -1.15
			knee = 2.1
			arms = [-0.95 + 0.25 * sin(_work_phase * 0.8), -0.95 + 0.25 * sin(_work_phase * 0.8 + 2.0)]
			elbows = [0.7 + 0.2 * sin(_work_phase * 0.8 + 1.0), 0.7 + 0.2 * sin(_work_phase * 0.8 + 3.0)]
		"build":
			# The hammer comes up at the elbow and down on the nail.
			var hammer := 0.5 + 0.5 * sin(_work_phase * 1.6)
			lean = 0.12
			arms = [-1.5 + 0.6 * hammer, -0.45]
			elbows = [1.35 - 1.05 * hammer, 0.7]
		_:
			# An axe or a pick: over the head, then down.
			lean = 0.3 * swing
			thigh = -0.12 * swing
			knee = 0.24 * swing
			arms = [-2.3 + 1.4 * swing, -2.3 + 1.4 * swing]
			elbows = [0.2 + 0.9 * (1.0 - swing), 0.2 + 0.9 * (1.0 - swing)]
	_body.position.y = lerpf(_body.position.y, -0.72 * (1.0 - cos(thigh)) if thigh != 0.0 else 0.0, blend)
	_body.rotation.x = lerpf(_body.rotation.x, lean, blend)
	for k in 2:
		_pose(k, thigh, knee, arms[k], elbows[k], -0.12, blend)


## The weapon arm winds up between blows and chops down on each one.
func _animate_fight(blend: float) -> void:
	var wind := smoothstep(0.25, 0.9, 1.0 - _attack_timer / ATTACK_SECONDS)
	_body.position.y = lerpf(_body.position.y, 0.0, blend)
	_body.rotation.x = lerpf(_body.rotation.x, 0.3 * (1.0 - wind), blend)
	for k in 2:
		var s := 1.0 if k == 0 else -1.0
		var arm := -0.5 - 1.7 * wind
		var elbow := 0.3 + 0.9 * wind
		if wizard:
			# The staff is raised to throw; the other hand points.
			arm = -2.0 + 0.5 * wind if k == 0 else -1.5
			elbow = 0.5 if k == 0 else 0.1
		elif archer:
			# The bow arm is held out straight; the other draws the string
			# back to the cheek.
			arm = -1.5 if k == 1 else -1.45
			elbow = 0.0 if k == 1 else 0.25 + 1.7 * wind
		elif k == 1:
			# Soldiers keep the shield up; everyone else flails with both arms.
			arm = -0.9 if soldier else -0.5 - 1.7 * (1.0 - wind)
			elbow = 0.55 if soldier else 0.3 + 0.9 * (1.0 - wind)
		# A fighting stance: one foot forward, both knees a little bent.
		_pose(k, 0.3 * s, 0.14 if s > 0.0 else 0.42, arm, elbow, -0.1, blend, minf(1.0, blend * 2.0))


## True while Charm Offensive has this goblin fighting its own kind.
func charmed() -> bool:
	return goblin and Game.now < charmed_until


## Charms this goblin for `seconds`: its eyes turn pink and it turns on the
## other goblins, who turn on it.
func charm(seconds: float) -> void:
	if not goblin or state == State.DEAD:
		return
	charmed_until = Game.now + seconds
	_foe = null
	if state == State.FIGHT:
		state = State.IDLE
	if _pink_eyes.is_empty():
		var eye := SphereMesh.new()
		eye.radius = 0.055
		eye.height = 0.11
		eye.radial_segments = 8
		eye.rings = 4
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.35, 0.75)
		eye.material = mat
		for sx in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = eye
			mi.position = Vector3(sx * 0.105, 1.62, 0.27)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_torso.add_child(mi)
			_pink_eyes.append(mi)
	Game.effects.spawn_dust(global_position + Vector3.UP * 1.6, 0.3)


func _uncharm() -> void:
	for mi in _pink_eyes:
		if is_instance_valid(mi):
			mi.queue_free()
	_pink_eyes.clear()
	_foe = null
	if state == State.FIGHT:
		state = State.IDLE


## The nearest goblin that is not charmed, within `reach`.
func _nearest_goblin(reach: float) -> Villager:
	var best: Villager = null
	var best_d := reach
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g == self or g.charmed() or g.state == State.DEAD or g.state == State.HELD:
			continue
		var d := _flat_to(g.global_position)
		if d < best_d:
			best_d = d
			best = g
	return best


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


## Knocked away from `from` without being hurt: it slides back along the
## ground, starting at `force` metres a second.
func knock_back(from: Vector3, force: float) -> void:
	if state == State.DEAD or state == State.HELD:
		return
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	_shove = away * force
	_stagger_until = Game.now + 1.0


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


## Wet from the rain for a while (chain lightning hurts the wet twice as much).
func soak() -> void:
	wet_until = Game.now + Balance.num("wet_seconds")


## Rained on lately, or standing in a river or lake.
func is_wet() -> bool:
	return Game.now < wet_until or Game.terrain.water_depth(global_position.x, global_position.z) > Terrain.WET_DEPTH


## Dropped by whatever was holding it (a giant bat shot down): back on its feet.
func release() -> void:
	if state != State.HELD:
		return
	var p := global_position
	global_position = Vector3(p.x, Game.terrain.get_height(p.x, p.z), p.z)
	rotation = Vector3(0.0, rotation.y, 0.0)
	state = State.IDLE
	_timer = 0.5


## Carried away for good (into a goblin cave): gone without a body or bones.
func carried_off() -> void:
	for group in ["villagers", "people", "soldiers", "wizards", "archers", "necromancers"]:
		remove_from_group(group)
	state = State.DEAD
	queue_free()


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
