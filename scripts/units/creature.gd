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
## small. Goblins can hurt it: at no health it is knocked out for a while
## and shrinks by Balance "creature_shrink_on_knockout" of its size, then
## gets up with "creature_getup_health" of its health. Health, stomp damage
## and the knock-out time come from balancing.txt (see Balance). Its mind
## may make it run from a fight (run_from_battle()).
##
## Each model (assets/creature/*.glb) is a single skinned mesh on a
## skeleton, sculpted by tools/bake_creature.py (the tortoise and the
## squirrel) or made by the owner in Meshy and rigged by tools/raven_rig.py
## (the raven, which wears its own painted texture and has finger bones
## that curl round what it holds). All animation is procedural:
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
## The raven flies (see _should_hurry): on any journey longer than Balance
## "raven_fly_distance", over ground that climbs steeply, and to get out of
## a fight. In the air nothing on the ground can reach it and it treads on
## nothing. When its mind makes it run from a fight, it flies.
##
## The squirrel runs on all fours where the raven would fly: half as fast
## again, and no slope slows it. Both use up stamina, and must stop when it
## is gone. The tortoise can do neither, but when it is hurt it may pull
## into its shell, where blows do a fifth of their harm. Hiding is a thing
## the player can Bless or Condemn (separately for each of four states of
## health: see CreatureMind); flying and running are not.
##
## Stamina, the magicko the creature's own spells cost, and health each
## level up with use (see _use): 10% more of it and 20% faster back. The
## tortoise tires slowly as it walks, and walks at half speed when it has
## no stamina left.
##
## At no health the creature dies (`knocked_out` stays true) and lies
## where it fell until the player pays Balance "resurrect_animus" animus to
## bring it back at a Shrine (resurrect()).
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
		"nervous": 0.0, "shell": true,
		"eye": Vector3(0.74, 0.5, 1.22), "eye_size": 0.34, "eye_color": Color(0.96, 0.94, 0.84),
		"lid_color": Color(0.36, 0.38, 0.2), "lid_y": [0.2, 0.14], "lid_tilt": [-0.38, 0.5], "pupil": [1.0, 0.72],
		# Mouth: half width, height, how far forward, how far its corners curve back.
		"mouth": [0.85, -0.08, 2.1, 0.5], "frown": [0.3, 0.2],
		"arm": Vector3(0.3, -1.0, 0.12), "elbow": -0.25,
	},
	"squirrel": {
		"name": "Squirrel", "model": "res://assets/creature/squirrel.glb", "speed": 3.6 * 1.3,
		"nervous": 1.0, "runs": true, "climbs": true,
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
		# The owner's Meshy model: its own texture (no cel shading or
		# outline), its eyes painted on (no drawn face), and a closed beak
		# (no jaw). Its ankle is where its rig puts it (a bird's leg: the
		# "foot" bone is the long bone above the toes).
		"own_skin": true, "painted_face": true, "ankle_from_rig": true,
		# Under the beak, in the head bone's space.
		"mouth_at": Vector3(0.0, -1.0, 1.1),
		# The arms hang as the model was made; the hands have fingers.
		"arm": Vector3(-0.2, -0.98, -0.1), "elbow": 0.0, "fingers": true,
		# The wings are spread at rest, flat side forwards. To fly they
		# swing out and down by `wing_open` within their plane, and the
		# long feathers hanging from their outer edge out by `tip_open`.
		"wing_normal": Vector3(0.0, 0.0, 1.0), "wing_open": 0.3, "tip_open": 0.5,
	},
}

## At no health: the creature has died (the Balrog's death too).
signal knocked_down
## Brought back to life at a Shrine.
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
## The fingers (the raven's): how far each of a finger's three joints
## bends with a full grip (radians), and how fast the grip changes.
const FINGER_CURL := [0.45, 0.6, 0.5]
const GRIP_SPEED := 4.0
## Arms held out in front, for carrying a tree or a boulder.
const CARRY_POSE := Vector3(0.25, 0.15, 1.0)
## Arms reaching for the ground in front, for running on all fours.
const RUN_POSE := Vector3(0.14, -0.5, 0.95)

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
## Growing can take animus (the player's creature only): with Balance
## "growth_animus_step" above 0, each tenth of the way from START_SIZE to
## full size must be paid for before it grows on, the first 1 step, the
## second 2, and so on, by clicking its portrait (see pay_for_growth()).
## With it at 0 (as the owner has it) it grows by itself, and each tenth
## counts as paid as it starts. How many tenths have been paid for (Bless
## and Condemn come with the first two).
var growth_paid := 0
## Out of its shell: a burst of speed until then (Game.now).
var _burst_until := 0.0
var max_hp := 0.0
var hp := 0.0
var knocked_out := false
## True for the goblins' giant, which fights the village and not for it.
var hostile := false
## In the air (the raven), from take-off until its feet are down again.
var flying := false
## On all fours and going fast (the squirrel).
var running := false
## Pulled into its shell (the tortoise).
var hiding := false
## Stamina (for running and flying) and the magicko its spells cost.
var stamina := 100.0
var max_stamina := 100.0
var magicko := 100.0
var max_magicko := 100.0
## How many times each has levelled up.
var levels := {"stamina": 0, "magicko": 0, "health": 0}
## How much of each has been used since its last level.
var used := {"stamina": 0.0, "magicko": 0.0, "health": 0.0}
## Knowledge, likes and dislikes, and what it does when left alone.
var mind: CreatureMind
## A tree, boulder or sheaf the creature is carrying in its arms.
var carrying: Node3D

var has_target := false
var target := Vector3.ZERO
## The way to `target` round grey rock slopes and water (PathGrid), the
## corner it is making for, and when to work it out again.
var _route := PackedVector3Array()
var _route_i := 0
var _route_goal := Vector3.INF
var _route_at := 0.0
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
## Running away from a fight until Game.now passes this: it does not attack.
var fleeing_until := 0.0

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
## An attack move (right-click): on the way to `_attack_goal` it goes after
## any enemy within its aggressiveness range, and once it is fighting one
## in reach it forgets the rest of the way.
var attack_moving := false
var _attack_goal := Vector3.ZERO
## What the next blow with the fists is aimed at: the other giant or a
## giant bat.
var _strike_target: Node3D
## In the air: when it next looks about, and the bat it is chasing.
var _air_scan := 0.0
var _air_bat: GiantBat
## Buffs on it (BuffBook): id -> when it wears off; their particles; and
## when the Flaming Aura next burns.
var _buffs := {}
var _buff_fx := {}
var _aura_tick := 0.0
## Standing still and turning to face goblins before attacking.
var _turning := false
var _crouch := 0.0
var _jaw_want := 0.0
## Where the arms point: x outwards, y up, z forwards. Each arm follows
## _arm_want unless _arm_one has a pose of its own for it (a punch with
## one fist, a throw with one hand).
var _arm_poses: Array[Vector3] = [Vector3(0.3, -1.0, 0.12), Vector3(0.3, -1.0, 0.12)]
var _arm_want := Vector3(0.3, -1.0, 0.12)
var _arm_one: Array = [null, null]
## Fingers: [bone indices of the three joints, the axis they curl about,
## and a little offset so they do not all twitch together] for each.
var _fingers: Array = []
## -1 spread wide .. 0 relaxed .. 1 clenched round something.
var _grip := 0.0
## Height of the ankle joint above the sole (see ANKLE_HEIGHT).
var _ankle := ANKLE_HEIGHT
## The fist the next punch is thrown with: they take turns.
var _punch_hand := 0
## The hand that throws (the other stays down).
const THROW_HAND := 1
## The magic acorn being thrown (forest seeding): where it is to land
## (null when there is none), and how far through the throw it is.
var _toss_to: Variant = null
var _toss_t := 0.0

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
var _hurt_timer := 0.0
## The nervous creature's head jerks and glances about.
var _twitch := 0.0
var _twitch_timer := 0.0
var _glance_timer := 0.0
var _fore_blends: Array[float] = [1.0, 1.0]
var _say_free_at := 0.0
## Metres above the ground, and 0..1 how far into its flying pose it is.
var _alt := 0.0
var _fly := 0.0
var _flap := 0.0
## How far the journey was when it began.
var _flight_length := 0.0
var _struck := false
## Too tired to run or fly until some stamina is back.
var _tired := false
var _run := 0.0
var _gallop := 0.0
var _shell := 0.0
var _hid_at := 0.0
var _last_hit_at := -100.0
var _shell_think_at := 0.0


func _ready() -> void:
	_spec = _species()
	max_speed = _spec.speed
	_arm_poses = [_spec.arm, _spec.arm]
	_arm_want = _spec.arm
	_build()
	_grow(0.0)
	max_stamina = Balance.num("creature_stamina")
	stamina = max_stamina
	max_magicko = Balance.num("creature_magicko")
	magicko = max_magicko
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
	# (The tortoise drags its feet when it has no stamina left.)
	var weary := 0.5 if _tired and _spec.get("shell", false) else 1.0
	var burst := 1.0 + Balance.num("shell_burst_speed") if Game.now < _burst_until else 1.0
	return max_speed * lerpf(0.5, 1.0, size) * (ALERT_SPEED if _alert else 1.0) * weary * burst


## Out of its shell with a whoosh: an unseen blast that hurts nobody but
## knocks the enemies close by away (Balance "shell_burst_radius"), and a
## burst of speed for a while ("shell_burst_speed", "shell_burst_seconds").
func _burst_out() -> void:
	_burst_until = Game.now + Balance.num("shell_burst_seconds")
	var reach := Balance.num("shell_burst_radius") * maxf(size, 0.3)
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.is_alive() and not g.charmed() and _flat(g.global_position, global_position) < reach:
			g.knock_back(global_position, Balance.num("shell_burst_force"))


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


# --- Stamina and magicko ------------------------------------------------------

## Stamina drains while it runs or flies (or, for the tortoise, walks) and
## comes back otherwise; magicko comes back all the time.
func _update_stats(delta: float) -> void:
	if hostile or knocked_out:
		return
	var drain := 0.0
	if flying or running:
		drain = Balance.num("fly_stamina_per_second" if flying else "run_stamina_per_second")
	elif _spec.get("shell", false) and speed > 0.3:
		drain = Balance.num("tortoise_walk_stamina")
	if drain > 0.0:
		var spent := minf(stamina, drain * delta)
		stamina -= spent
		_use("stamina", spent)
		if stamina <= 0.0:
			stamina = 0.0
			_tired = true
			running = false
	else:
		stamina = minf(max_stamina, stamina + Balance.num("creature_stamina_regen") * regen_boost("stamina") * delta)
	if _tired and stamina >= max_stamina * 0.3:
		_tired = false
	magicko = minf(max_magicko, magicko + Balance.num("creature_magicko_regen") * regen_boost("magicko") * delta)


## How many times as fast `stat` refills, for its levels.
func regen_boost(stat: String) -> float:
	return pow(1.0 + Balance.num("level_regen_gain"), levels[stat])


## `amount` of `stat` has been used (stamina spent, magicko spent on a
## spell, health lost). Enough of it and the stat levels up: 10% more of
## it, refilling 20% faster.
func _use(stat: String, amount: float) -> void:
	if hostile or amount <= 0.0:
		return
	used[stat] += amount
	while used[stat] >= level_cost(stat):
		used[stat] -= level_cost(stat)
		levels[stat] += 1
		var gain := 1.0 + Balance.num("level_max_gain")
		match stat:
			"stamina":
				max_stamina *= gain
			"magicko":
				max_magicko *= gain
			"health":
				var before := max_hp
				max_hp *= gain
				hp += max_hp - before
		say(Texts.line("stat_grew", {"creature": species_name().to_lower(), "stat": stat, "level": int(levels[stat]) + 1}), Color(0.6, 1.0, 0.7))


## How much of `stat` must be used for its next level: Balance
## "level_points" for the first, twice that for the second, and so on, but
## never more than "level_points_most".
func level_cost(stat: String) -> float:
	return minf(Balance.num("level_points") * (int(levels[stat]) + 1), Balance.num("level_points_most"))


## Pays for one of its own spells. False if it has not the magicko.
func spend_magicko(cost: float) -> bool:
	if magicko < cost:
		return false
	magicko -= cost
	_use("magicko", cost)
	return true


# --- The shell (the tortoise) ---------------------------------------------------

## "shell_unharmed", "shell_slightly", "shell_badly" or "shell_near_death":
## the action for hiding in its shell as hurt as it is now (the same four
## states as running from battle).
func shell_action() -> String:
	return "shell_" + mind.health_word()


func _hide() -> void:
	hiding = true
	_hid_at = Game.now
	_cancel_action()
	_turning = false
	running = false
	mind.did("shell", {"health": health_share(), "battle": true}, Texts.line("hid_in_shell", {"creature": species_name().to_lower(), "health": roundi(100.0 * health_share())}))


## True while it is too high for anything on the ground to reach.
func is_flying() -> bool:
	return flying and _alt > 1.5 * size


## 0..1: how far it has grown from START_SIZE to full size.
func grown() -> float:
	return inverse_lerp(START_SIZE, 1.0, size)


## Grows, and heals slowly when nothing has hurt it for a while. A creature
## with no food to eat does neither, and a dead one does not either.
func _grow(delta: float) -> void:
	var hungry := _hungry() or knocked_out
	var minutes: float = maxf(Game.settings.creature_grow_minutes, 0.05)
	if not hungry:
		if hostile:
			age += delta
		elif growth_cost() <= 0 and is_instance_valid(Game.village) and Game.village.founded:
			# Free growth: it grows by itself (faster under the Creature
			# Growth buff).
			age += delta * (1.0 + (Balance.num("growth_buff_speed") if buff_on("growth") else 0.0))
			var tenth := 0.1 * minutes * 60.0
			while growth_paid < 10 and age >= growth_paid * tenth - 0.01:
				growth_paid += 1
				Game.village.unlock_growth_spells(growth_paid)
		else:
			# As far as the animus paid for so far allows (faster under
			# the Creature Growth buff).
			var rate := 1.0 + (Balance.num("growth_buff_speed") if buff_on("growth") else 0.0)
			age = maxf(age, minf(age + delta * rate, _growth_allowed()))
	var t := clampf(age / (minutes * 60.0), 0.0, 1.0)
	size = lerpf(START_SIZE, 1.0, t)
	scale = Vector3.ONE * size
	var new_max: float = Balance.num(kind + "_health") * lerpf(0.3, 1.0, t) * pow(1.0 + Balance.num("level_max_gain"), levels.health)
	hp += new_max - max_hp
	max_hp = new_max
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	if knocked_out:
		hp = 0.0
	elif _hurt_timer <= 0.0 and not hungry:
		hp = minf(max_hp, hp + max_hp * 0.01 * regen_boost("health") * delta)


# --- Buffs ------------------------------------------------------------------------

## True while buff `id` (BuffBook) is on.
func buff_on(id: String) -> bool:
	return float(_buffs.get(id, -INF)) > Game.now


## Seconds buff `id` has left (0 if it is off).
func buff_left(id: String) -> float:
	return maxf(0.0, float(_buffs.get(id, -INF)) - Game.now)


## Puts buff `id` on for `seconds`.
func start_buff(id: String, seconds: float) -> void:
	_buffs[id] = Game.now + seconds
	if not _buff_fx.has(id):
		_buff_fx[id] = _make_buff_fx(id)


func _update_buffs(delta: float) -> void:
	for id: String in _buff_fx:
		var fx := _buff_fx[id] as CPUParticles3D
		fx.emitting = buff_on(id) and not knocked_out
		fx.position = Vector3.UP * 2.2
		fx.emission_sphere_radius = 1.6
		fx.scale_amount_min = 0.6
		fx.scale_amount_max = 1.3
	if not buff_on("aura") or knocked_out:
		_aura_tick = 0.0
		return
	# Flaming Aura: every second, fire damage to every enemy close by.
	_aura_tick += delta
	while _aura_tick >= 1.0:
		_aura_tick -= 1.0
		var reach := Balance.num("aura_radius")
		var burn := Balance.num("aura_damage")
		for node in get_tree().get_nodes_in_group("goblins"):
			var g := node as Villager
			if g != null and g.is_alive() and not g.charmed() and g.state != Villager.State.HELD \
					and _flat(g.global_position, global_position) < reach:
				g.take_hit(burn, self)
		var rival := _rival()
		if rival != null and rival != self and _flat(rival.global_position, global_position) < reach + 2.0 * rival.size:
			rival.take_hit(burn, self)
		for node in get_tree().get_nodes_in_group("bats"):
			var bat := node as GiantBat
			if bat != null and bat.is_alive() and bat.global_position.distance_to(global_position) < reach:
				bat.take_hit(burn, self)


## The particles a buff sheds while it is on: yellow sparkles drifting
## down to the ground (Creature Growth), or flames falling off it (Flaming
## Aura). They are left behind as it moves.
func _make_buff_fx(id: String) -> CPUParticles3D:
	var fx := CPUParticles3D.new()
	var dot := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	dot.material = mat
	fx.mesh = dot
	fx.local_coords = false
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.spread = 180.0
	var fade := Gradient.new()
	if id == "growth":
		dot.size = Vector2(0.28, 0.28)
		fx.amount = 48
		fx.lifetime = 2.2
		fx.gravity = Vector3(0, -2.2, 0)
		fx.initial_velocity_min = 0.2
		fx.initial_velocity_max = 0.8
		fade.set_color(0, Color(1.0, 0.95, 0.4, 1.0))
		fade.set_color(1, Color(1.0, 0.8, 0.15, 0.0))
		fade.add_point(0.7, Color(1.0, 0.88, 0.25, 0.9))
	else:
		dot.size = Vector2(0.6, 0.6)
		fx.amount = 70
		fx.lifetime = 1.1
		fx.gravity = Vector3(0, -3.0, 0)
		fx.initial_velocity_min = 0.3
		fx.initial_velocity_max = 1.4
		fade.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
		fade.set_color(1, Color(0.6, 0.08, 0.02, 0.0))
		fade.add_point(0.35, Color(1.0, 0.45, 0.08, 0.95))
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.5, 0.15)
		glow.light_energy = 1.2
		glow.omni_range = 6.0
		fx.add_child(glow)
	fx.color_ramp = fade
	fx.emitting = false
	add_child(fx)
	return fx


## How old (in seconds of growing) the animus paid for lets it grow.
func _growth_allowed() -> float:
	return float(growth_paid) * 0.1 * maxf(Game.settings.creature_grow_minutes, 0.05) * 60.0


## The animus the next tenth of its growth costs.
func growth_cost() -> int:
	return roundi(float(growth_paid + 1) * Balance.num("growth_animus_step"))


## True when it has grown as far as it has been paid for and the village
## has the animus for the next tenth (its portrait sparkles).
func can_grow() -> bool:
	var village := Game.village
	return not hostile and growth_paid < 10 and growth_cost() > 0 and age >= _growth_allowed() - 0.01 and is_instance_valid(village) \
		and village.founded and village.amount("animus") >= growth_cost()


## Pays the village's animus for the next tenth of its growth, if it can
## grow on now (see can_grow()). True if it did.
func pay_for_growth() -> bool:
	if not can_grow():
		return false
	Game.village.give("animus", -growth_cost())
	growth_paid += 1
	Game.village.unlock_growth_spells(growth_paid)
	return true


## Hurt by a goblin or an ogre.
func take_hit(amount: float, _from: Node3D) -> void:
	if knocked_out:
		return
	if hiding:
		amount *= Balance.num("shell_damage_share")
	_use("health", minf(amount, maxf(hp, 0.0)))
	hp -= amount
	_hurt_timer = 6.0
	_last_hit_at = Game.now
	_cast_timer = maxf(_cast_timer, 0.25)
	if hp > 0.0:
		if _spec.get("shell", false) and not hiding and Game.now >= _shell_think_at and Balance.num("shell_damage_share") < 1.0:
			# Hurt in a fight: into the shell, if it is that way inclined.
			_shell_think_at = Game.now + Balance.num("shell_think_seconds")
			if mind.likely("shell", {"health": health_share(), "battle": true}):
				_hide()
		return
	hp = 0.0
	knocked_out = true
	hiding = false
	running = false
	flying = false
	_alt = 0.0
	fleeing_until = 0.0
	if not hostile:
		shrink(Balance.num("creature_shrink_on_knockout"))
	_cancel_action()
	has_target = false
	_auto = false
	_turning = false
	_alert = false
	_crouch = 1.3
	_jaw_want = 0.0
	Game.effects.spawn_dust(global_position, 3.0 * size)
	knocked_down.emit()


## Brings the dead creature back to life at `at` (a Shrine), in a shaft
## of light, with Balance "creature_getup_health" of its health.
func resurrect(at: Vector3) -> void:
	if not knocked_out:
		return
	knocked_out = false
	_crouch = 0.0
	_jaw_want = 0.0
	hp = max_hp * Balance.num("creature_getup_health")
	stamina = max_stamina
	_tired = false
	place(at, heading)
	mind.home = global_position
	Game.effects.spawn_god_ray(global_position, size)
	got_up.emit()


## Makes the creature smaller by `share` of its size (never below
## START_SIZE). It grows back over time like before.
func shrink(share: float) -> void:
	var minutes: float = maxf(Game.settings.creature_grow_minutes, 0.05)
	var smaller := maxf(START_SIZE, size * (1.0 - clampf(share, 0.0, 1.0)))
	age = inverse_lerp(START_SIZE, 1.0, smaller) * minutes * 60.0
	_grow(0.0)


## 0..1 of its health left.
func health_share() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


## Runs away from the enemies around it, towards the village if that is
## away from them. Returns false if there is nowhere to run to.
func run_from_battle(seconds := 8.0) -> bool:
	var middle := Vector3.ZERO
	var n := 0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.is_alive() and _flat(g.global_position, global_position) < HUNT_RANGE * 0.3:
			middle += g.global_position
			n += 1
	# The other giant counts for a crowd.
	var rival := _rival()
	if rival != null and _flat(rival.global_position, global_position) < HUNT_RANGE * 0.3:
		middle += rival.global_position * 5.0
		n += 5
	if n == 0:
		return false
	middle /= n
	var away := global_position - middle
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3(sin(heading), 0.0, cos(heading))
	var village := Game.village
	var tries: Array[Vector3] = [away, away.rotated(Vector3.UP, 0.8), away.rotated(Vector3.UP, -0.8)]
	if is_instance_valid(village) and village.founded:
		var home_way := village.center - global_position
		home_way.y = 0.0
		if home_way.length_squared() > 1.0 and home_way.normalized().dot(away) > 0.0:
			tries.push_front(home_way.normalized())
	for dir in tries:
		var p := global_position + dir * (25.0 + 15.0 * size)
		if Game.terrain.is_inside(p.x, p.z) and Game.terrain.is_dry(p.x, p.z):
			# (A stomp under way finishes as an ordinary step.)
			_cancel_action()
			_turning = false
			hiding = false
			fleeing_until = Game.now + seconds
			# The raven takes to the air to get away, and the squirrel runs.
			auto_move(p)
			return true
	return false


func is_fleeing() -> bool:
	return Game.now < fleeing_until


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
	attack_moving = false
	target = pos
	has_target = true
	_auto = false
	_look_at = pos
	mind.player_moved(pos)
	_flight_length = _flat(pos, global_position)
	if _should_hurry(pos, true):
		_hurry()


## The player's attack move (right-click): off to `pos`, fighting on the
## way. Enemies within its aggressiveness range are gone after first (and
## it casts at them as its mind likes, as always); once it is in a fight
## within reach it stays there and does not finish the walk.
func attack_move(pos: Vector3) -> void:
	move_to(pos)
	attack_moving = true
	_attack_goal = pos


## The creature goes somewhere of its own accord. (Chasing enemies and the
## player's orders come first.)
func auto_move(pos: Vector3) -> void:
	attack_moving = false
	target = pos
	has_target = true
	_auto = true
	_look_at = pos
	_flight_length = _flat(pos, global_position)
	if _should_hurry(pos):
		_hurry()


# --- Flying (the raven) and running (the squirrel) ------------------------------

## "fly", "run" or "": the fast way this creature has of getting about.
func haste() -> String:
	return "fly" if _spec.get("flies", false) else ("run" if _spec.get("runs", false) else "")


## True if the raven would rather fly to `pos` than walk (or the squirrel
## run): it is a long way, the ground climbs steeply on the way, or it is
## getting out of a fight (by itself, or because the player has `ordered`
## it away).
func _should_hurry(pos: Vector3, ordered := false) -> bool:
	var how := haste()
	if how == "" or flying or running or _tired or hiding:
		return false
	if knocked_out or Game.now < snared_until or (how == "run" and is_instance_valid(carrying)):
		return false
	var d := _flat(pos, global_position)
	if d < SHORT_HOP:
		return false
	if d > Balance.num("raven_fly_distance" if how == "fly" else "squirrel_run_distance"):
		return true
	if is_fleeing() or (ordered and (_alert or _action != Action.NONE)):
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


## Takes to the air, or drops to all fours and runs.
func _hurry() -> void:
	if haste() == "fly":
		_take_off()
		return
	_cancel_action()
	running = true
	_turning = false


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


## In the air: climbs to its cruising height (and over any hill ahead),
## flies to the target and comes down on it.
func _update_flight(delta: float) -> void:
	var terrain := Game.terrain
	var cruise := Balance.num("raven_fly_height") * lerpf(0.4, 1.0, size)
	_action_cooldown = maxf(0.0, _action_cooldown - delta)
	_air_scan -= delta
	if _air_scan <= 0.0 and not knocked_out:
		_air_scan = 0.3
		_air_combat()
	var chasing_bat := is_instance_valid(_air_bat) and _air_bat.is_alive()
	if chasing_bat:
		target = Vector3(_air_bat.global_position.x, global_position.y, _air_bat.global_position.z)
		has_target = true
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	var desired_speed := 0.0
	# It starts down a little way short of the target (half way, on a short hop).
	# (Out of stamina, it comes down wherever it is and walks the rest.)
	# Chasing a bat, it stays up.
	var landing := knocked_out or _tired or (not chasing_bat and (not has_target or dist < maxf(minf(cruise * 1.3, _flight_length * 0.5), 3.0)))
	if has_target and not knocked_out:
		if dist < 0.8:
			has_target = false
			_auto = false
		elif not _tired:
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
		if chasing_bat:
			# Up or down to the bat's height.
			want_alt = clampf(_air_bat.global_position.y - ground - 1.0, 1.5, cruise * 1.6)
	_alt = lerpf(_alt, want_alt, 1.0 - exp(-(4.0 if knocked_out else 1.8) * delta))
	_alt = move_toward(_alt, want_alt, cruise * 0.25 * delta)
	_ground_y = lerpf(_ground_y, ground, 1.0 - exp(-8.0 * delta))
	p.y = _ground_y + _alt
	global_position = p
	if landing and _alt < 0.12 * size + 0.03:
		_land()


## Looking about in the air: it buffets any giant bat within reach with its
## wings, and on an attack move it goes after bats in the air and comes
## down to fight anything on the ground on the way.
func _air_combat() -> void:
	if hostile:
		return
	var close := _nearest_bat(REACH * size + 3.0)
	if close != null and _action_cooldown <= 0.0:
		_hit_bat(close)
		_action_cooldown = 1.0
	if not attack_moving:
		_air_bat = null
		return
	var aggro := Balance.num("creature_aggro_range")
	_air_bat = _nearest_bat(aggro)
	if _air_bat != null:
		_auto = true
		return
	var foe := _nearest_ground_enemy(aggro)
	if foe != null:
		# Down to it (it lands short of the target, on the way in).
		target = foe.global_position
		has_target = true
		_auto = true
		_flight_length = maxf(_flight_length, _flat(foe.global_position, global_position))
		_look_at = target
	elif _auto:
		target = _attack_goal
		has_target = true
		_auto = false
		_look_at = target


## The live giant bat nearest to it within `within` metres (in 3D), or null.
func _nearest_bat(within: float) -> GiantBat:
	var best: GiantBat = null
	var best_d := within
	for node in get_tree().get_nodes_in_group("bats"):
		var bat := node as GiantBat
		if bat == null or not bat.is_alive():
			continue
		var d := bat.global_position.distance_to(global_position + Vector3.UP * 2.0 * size)
		if d < best_d:
			best_d = d
			best = bat
	return best


## A giant bat low and near enough to be hit from where it stands, or null.
func _bat_in_reach() -> GiantBat:
	for node in get_tree().get_nodes_in_group("bats"):
		var bat := node as GiantBat
		if bat != null and bat.is_alive() and _can_reach_bat(bat):
			return bat
	return null


func _can_reach_bat(bat: GiantBat) -> bool:
	if flying:
		return bat.global_position.distance_to(global_position) < REACH * size + 3.0
	var up := head_position().y - global_position.y
	return _flat(bat.global_position, global_position) < REACH * size + 1.5 \
		and bat.global_position.y - global_position.y < up + 2.5 * size + 1.0


func _hit_bat(bat: GiantBat) -> void:
	bat.take_hit(Balance.num("creature_strike_damage") * lerpf(0.3, 1.0, size), self)
	Game.effects.spawn_dust(bat.global_position, 1.2 + size)
	Game.shake(0.3 * size, bat.global_position)


## The nearest enemy on the ground within `within` metres: a goblin, an
## ogre, or the other giant. Null if none.
func _nearest_ground_enemy(within: float) -> Node3D:
	var best: Node3D = null
	var best_d := within
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.state == Villager.State.HELD or g.charmed() or not g.is_alive():
			continue
		var d := _flat(g.global_position, global_position)
		if d < best_d:
			best_d = d
			best = g
	var rival := _rival()
	if rival != null and rival != self and not rival.is_flying() and _flat(rival.global_position, global_position) < best_d:
		best = rival
	return best


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
	_arm_one = [null, null]


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
	label.font_size = 26
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
	_update_buffs(delta)
	_update_stats(delta)
	_update_toss(delta)
	if hiding and (Game.now - _last_hit_at > Balance.num("shell_calm_seconds") or Game.now - _hid_at > Balance.num("shell_max_seconds")):
		# Nothing has hit it for a while (or it cannot stay in for ever).
		hiding = false
		_shell_think_at = Game.now + Balance.num("shell_think_seconds")
		_burst_out()
	if running and (not has_target or knocked_out or Game.now < snared_until):
		running = false
	if not knocked_out and not flying and not running and not hiding:
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
		_arm_want = CARRY_POSE if is_instance_valid(carrying) else (RUN_POSE if _run > 0.3 else _spec.arm)
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
			# Far off, it follows a route round the grey rock slopes.
			var via := _route_aim() - global_position
			via.y = 0.0
			if via.length() > 0.5:
				to = via
			var want := atan2(to.x, to.z)
			heading = rotate_toward(heading, want, turn_speed * (COMBAT_TURN if _alert else 1.0) * delta)
			var facing := cos(angle_difference(heading, want))
			desired_speed = _top_speed() * clampf(facing, 0.0, 1.0) * clampf(dist / 5.0, 0.25, 1.0)
			if running:
				desired_speed *= Balance.num("squirrel_run_speed")
	if _action != Action.NONE or _turning:
		# Stand still and face the goblins.
		desired_speed = 0.0
		var facing_to := _action_point - global_position
		heading = rotate_toward(heading, atan2(facing_to.x, facing_to.z), turn_speed * 1.6 * COMBAT_TURN * delta)
	if Game.now < snared_until or knocked_out or hiding:
		desired_speed = 0.0
		speed = 0.0
	# Uphill is slow going for a creature too (but not for one on all fours).
	if not running:
		var ahead := Vector3(sin(heading), 0.0, cos(heading)) * 2.0 * maxf(size, 0.3)
		var rise := (Game.terrain.get_height(global_position.x + ahead.x, global_position.z + ahead.z)
			- Game.terrain.get_height(global_position.x, global_position.z)) / ahead.length()
		desired_speed *= lerpf(1.0, Balance.num("slope_slowest"), clampf((rise - Balance.num("slope_slow_from")) / 0.6, 0.0, 1.0))
	# Grey rock slopes are too steep to walk (Balance "cliff_grade"): it
	# feels its way round one, or stops. Only the squirrel climbs them.
	if desired_speed > 0.0 and not _spec.get("climbs", false):
		var turned := _round_steep(heading)
		if turned == INF:
			desired_speed = 0.0
			speed = 0.0
		else:
			heading = turned
	speed = move_toward(speed, desired_speed, (6.0 if running else 3.0) * delta)
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


## The next point on the way to `target`: straight there if the way is
## clear, else the next corner of a route round the slopes and water. The
## route is worked out again when the target moves and every few seconds.
func _route_aim() -> Vector3:
	if _flat(target, global_position) < 6.0 or _spec.get("climbs", false):
		return target
	if _route_goal.distance_squared_to(target) > 4.0 or Game.now >= _route_at:
		_route_goal = target
		_route_at = Game.now + 4.0
		_route_i = 0
		var grid := Game.path_grid()
		_route = PackedVector3Array() if grid.clear_line(global_position, target) else grid.find(global_position, target)
	while _route_i < _route.size() and _flat(_route[_route_i], global_position) < 2.0 + size:
		_route_i += 1
	return _route[_route_i] if _route_i < _route.size() else target


## True if the ground in direction `angle` is a grey rock slope it would
## be stepping onto (Terrain.is_steep()). (Already on one, it may walk off
## it, but not straight up or down it.)
func _steep_towards(angle: float) -> bool:
	var reach := 1.0 + size
	var p := global_position + Vector3(sin(angle), 0.0, cos(angle)) * reach
	var t := Game.terrain
	if not t.is_steep(p.x, p.z):
		return false
	var rise := absf(t.get_height(p.x, p.z) - t.get_height(global_position.x, global_position.z)) / reach
	return not t.is_steep(global_position.x, global_position.z) or rise > Balance.num("cliff_grade")


## `angle` if the way is clear, else the nearest heading either side of it
## that is (as far round as going back the way it came, so it works its
## way along a grey rock slope instead of standing stuck), or INF if none is.
func _round_steep(angle: float) -> float:
	for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 2.5, -2.5, PI]:
		if not _steep_towards(angle + turn):
			return angle + turn
	return INF


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
		# The tortoise watches its step around its own village. (Archers up
		# on their posts are out of reach.)
		if _spares(v) or v.on_post() or size <= 0.3 or v.global_position.distance_to(pos) >= 1.8 * size:
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
	if is_fleeing():
		# Running away: scared, and not stopping for anyone.
		_alert = true
		_jaw_want = 0.3
		return
	var near: Array[Villager] = []
	var nearest: Villager = null
	var nearest_d := INF
	var hunt: Villager = null
	# The player's creature goes after any enemy within its aggressiveness
	# range (Balance "creature_aggro_range" metres of it).
	var hunt_d := HUNT_RANGE if hostile else Balance.num("creature_aggro_range")
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		# (A charmed goblin is on our side for now.)
		if g.state == Villager.State.HELD or (not hostile and g.charmed()):
			continue
		var d := _flat(g.global_position, global_position)
		if d < REACH * size + 1.0:
			near.append(g)
			if d < nearest_d:
				nearest_d = d
				nearest = g
		elif d < hunt_d and (not hostile or g.raiding or _threatens_village(g)):
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
	# A giant bat low enough to reach is swatted too.
	if focus == null and not hostile:
		focus = _bat_in_reach()
	# On an attack move, a flyer takes to the air after bats it cannot reach.
	if attack_moving and focus == null and not hunting and haste() == "fly" and Game.now >= snared_until:
		var high := _nearest_bat(Balance.num("creature_aggro_range"))
		if high != null:
			target = Vector3(high.global_position.x, global_position.y, high.global_position.z)
			has_target = true
			_auto = true
			_hurry()
			return
	_alert = focus != null or hunting
	_jaw_want = 0.16 + 0.14 * float(_spec.nervous) if _alert else 0.0
	if attack_moving:
		if focus != null:
			# In a fight: the rest of the way is forgotten.
			attack_moving = false
			has_target = false
			_auto = false
		elif not hunting and _flat(_attack_goal, global_position) < 1.5 + 2.0 * size:
			# There.
			attack_moving = false
		elif not hunting and (_auto or not has_target):
			# The enemy it went after is gone: on to where it was sent.
			target = _attack_goal
			has_target = true
			_auto = false
			_look_at = target
			_flight_length = _flat(target, global_position)
	if focus == null:
		_turning = false
		# Nothing in reach: go after raiders, unless the player sent us somewhere
		# (an attack move goes after them on the way). A little one stays out
		# of it, unless the player said to attack.
		if hunting and (size >= 0.35 or attack_moving) and (not has_target or _auto or attack_moving) and Game.now >= snared_until:
			target = hunt_pos
			has_target = true
			_auto = true
			_look_at = target
			_flight_length = _flat(hunt_pos, global_position)
			if _should_hurry(hunt_pos):
				_hurry()
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
	if focus == rival or focus is GiantBat:
		_strike_target = focus
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


## Forest seeding: turns to `spot` and tosses a magic acorn there with one
## hand (see MagicAcorn).
func toss_acorn(spot: Vector3) -> void:
	_toss_to = spot
	_toss_t = 0.0
	has_target = false
	_look_at = spot


func _update_toss(delta: float) -> void:
	if _toss_to == null:
		return
	var spot: Vector3 = _toss_to
	var before := _toss_t
	_toss_t += delta
	var to := spot - global_position
	heading = lerp_angle(heading, atan2(to.x, to.z), minf(1.0, delta * 6.0))
	# Wind up behind the shoulder, then over and forward.
	_arm_one[THROW_HAND] = Vector3(0.35, 0.9, -0.35) if _toss_t < 0.5 else Vector3(0.15, 0.3, 1.0)
	if before < 0.5 and _toss_t >= 0.5:
		MagicAcorn.toss(_hand_pos(THROW_HAND), spot)
	if _toss_t >= 0.95:
		_toss_to = null
		_arm_one[THROW_HAND] = null


## A punch at the other giant, with one fist and then the other.
func _start_strike() -> void:
	_action = Action.STRIKE
	_action_t = 0.0
	_struck = false
	_jaw_want = 0.45
	_punch_hand = 1 - _punch_hand


func _update_strike(delta: float) -> void:
	_action_t += delta
	var other := 1 - _punch_hand
	if _action_t < STRIKE_LANDS - 0.15:
		# The fist drawn back, the other up on guard...
		_arm_one[_punch_hand] = Vector3(0.5, 0.45, -0.5)
		_arm_one[other] = Vector3(0.2, 0.2, 0.9)
		_crouch = 0.0
	else:
		# ...and thrown at its head, the guard pulled back.
		_arm_one[_punch_hand] = Vector3(0.0, 0.2, 1.0)
		_arm_one[other] = Vector3(0.35, -0.1, 0.45)
		_crouch = 0.3
	if not _struck and _action_t >= STRIKE_LANDS:
		_struck = true
		var bat := _strike_target as GiantBat
		if bat != null:
			if is_instance_valid(bat) and bat.is_alive() and _can_reach_bat(bat):
				_hit_bat(bat)
			_strike_target = null
		var rival := _rival() if bat == null else null
		if rival != null and not rival.is_flying() and _flat(rival.global_position, global_position) - 2.0 * rival.size < REACH * size + 2.5:
			rival.take_hit(Balance.num("creature_strike_damage") * lerpf(0.3, 1.0, size), self)
			var at := rival.global_position.lerp(global_position, 0.3)
			Game.effects.spawn_dust(at + Vector3.UP * 3.0 * rival.size, 2.5 * size)
			Game.shake(0.7 * size, at)
	if _action_t >= STRIKE_TIME:
		_action = Action.NONE
		# (Quick to follow up with the other fist.)
		_action_cooldown = 0.5
		_crouch = 0.0
		_jaw_want = 0.0
		_arm_want = _spec.arm
		_arm_one = [null, null]


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
		if _spares(v) or v.on_post():
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
		mind.did("stomp", {"enemy": enemy_name(hit), "battle": true}, Texts.line("stomped", {"them": _name_them(hit)}))


## The name of the commonest kind of enemy in `list` (goblins, ogres,
## giant bats, the balrog), as Actions.csv's [enemy name] is filled in.
static func enemy_name(list: Array) -> String:
	var counts := {}
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var word := "goblin"
		if node is Villager and (node as Villager).ogre:
			word = "ogre"
		elif node is GiantBat:
			word = "giant bat"
		elif node is Balrog:
			word = "balrog"
		counts[word] = counts.get(word, 0) + 1
	var best := "goblin"
	var most := 0
	for word: String in counts:
		if counts[word] > most:
			most = counts[word]
			best = word
	return best


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
	_eating = CreatureMind.pick({true: mind.weight("eat"), false: mind.weight("throw")})


## Reach down, pick the goblins up, then eat them one by one or hurl them.
## Eating takes both hands; a throw is with one (THROW_HAND), the other
## hanging at its side.
func _update_grab(delta: float) -> void:
	var before := _action_t
	_action_t += delta
	var t := _action_t
	if not _eating:
		# Whatever the throwing arm is told below, the other stays down.
		_arm_one[1 - THROW_HAND] = _spec.arm
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
			mind.did("eat", {"enemy": enemy_name(_held), "battle": true}, Texts.line("ate", {"them": _name_them(_held)}))
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
			mind.did("throw", {"enemy": enemy_name(_held), "battle": true}, Texts.line("threw", {"them": _name_them(_held)}))
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
		# (In both fists to eat; all in one to throw.)
		var hand := _hand_pos(i % 2) + Vector3(0.0, -0.6 + 0.35 * (i >> 1), 0.0) * size if _eating \
			else _hand_pos(THROW_HAND) + Vector3(0.0, -0.5 + 0.25 * i, 0.0) * size
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
	_arm_one = [null, null]


func _hand_pos(k: int) -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_bone["hand_l" if k == 0 else "hand_r"]).origin


func _mouth_pos() -> Vector3:
	var at: Vector3 = _spec.get("mouth_at", Vector3(0.0, -0.3, 1.5))
	return _skel.global_transform * (_skel.get_bone_global_pose(_bone["head"]) * at)


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
	# On all fours the body is low and level, and bounds along.
	_run = move_toward(_run, 1.0 if running and speed > 0.3 * max_speed * size else 0.0, delta * 3.0)
	var prone := smoothstep(0.0, 1.0, _run)
	_gallop += delta * (6.0 + 5.0 * minf(pace, 2.0)) * (1.5 - 0.5 * size)
	var bound := sin(_gallop) * prone
	# In its shell the body sits on the ground.
	_shell = move_toward(_shell, 1.0 if hiding else 0.0, delta * 2.5)
	var tucked := smoothstep(0.0, 1.0, _shell)
	pace = minf(pace, 1.3)
	_bob = lerpf(_bob, swing * 0.3 * (1.0 - tucked) - 0.3 * pace - 0.12 + breath * 0.03 - stoop * 0.9
		- prone * (float(_spec.get("run_drop", 1.9)) + 0.25 * bound) - tucked * float(_spec.get("shell_drop", 2.3)), blend)
	_sway = lerpf(_sway, sway_target * (1.0 - tucked), blend)
	_lean = lerpf(_lean, pace * 0.14 + stoop * 0.42 + aloft * 1.2 + prone * (0.72 + 0.1 * bound), blend)

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
	var nod := 0.16 - (_bob + prone * float(_spec.get("run_drop", 1.9))) * 0.12 * (1.0 - tucked) - (0.3 if casting else 0.0) - _lean * 0.8 + (0.6 if knocked_out else 0.0)
	_skel.set_bone_pose_rotation(_bone["neck"], Quaternion.from_euler(Vector3(nod * 0.5, _look_yaw * 0.5, 0.0)))
	# Head, arms and tail shrink away into the shell.
	var pulled := Vector3.ONE * lerpf(1.0, 0.08, tucked)
	_skel.set_bone_pose_scale(_bone["neck"], pulled)
	_skel.set_bone_pose_scale(_bone["tail1"], pulled)
	_skel.set_bone_pose_scale(_bone["arm_upper_l"], pulled)
	_skel.set_bone_pose_scale(_bone["arm_upper_r"], pulled)
	_skel.set_bone_pose_rotation(_bone["head"], Quaternion.from_euler(Vector3(nod * 0.5, _look_yaw * 0.5 + _twitch, _sway * 0.5)))
	_jaw = lerpf(_jaw, maxf(0.4 if casting else 0.03 + 0.02 * breath, _jaw_want), 1.0 - exp(-14.0 * delta))
	if _bone.has("jaw"):
		_skel.set_bone_pose_rotation(_bone["jaw"], Quaternion(Vector3.RIGHT, _jaw + float(_spec.get("jaw_rest", 0.0))))
	if _bone.has("wing_l"):
		_update_wings(delta, aloft)
	if not _fingers.is_empty():
		_update_fingers(delta)

	# Arms hang from the bind pose and swing against the legs.
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var stride := (_foot_pos(0) - _foot_pos(1)).dot(fwd)
	# (The nervous one wrings its paws.)
	var swing_targets: Array[float] = [stride * 0.16 / size + sin(_time * 7.0) * 0.08 * nervous,
		-stride * 0.16 / size + sin(_time * 7.0 + 2.1) * 0.08 * nervous]
	if prone > 0.0:
		# Both front paws reach and pull together, one a little behind.
		swing_targets = [lerpf(swing_targets[0], 0.75 * sin(_gallop + 1.6), prone), lerpf(swing_targets[1], 0.75 * sin(_gallop + 2.1), prone)]
	for k in 2:
		var aim: Vector3 = _arm_one[k] if _arm_one[k] != null else _arm_want
		_arm_poses[k] = _arm_poses[k].lerp(aim, 1.0 - exp(-9.0 * delta))
		_fore_blends[k] = lerpf(_fore_blends[k], 1.0 if aim == _spec.arm else 0.0, blend)
		var arm_pose := _arm_poses[k]
		var side := "l" if k == 0 else "r"
		_arm_swing[k] = lerpf(_arm_swing[k], swing_targets[k], blend)
		var rest_dir: Vector3 = (_rest["arm_lower_" + side] - _rest["arm_upper_" + side]).normalized()
		var hang := Vector3(_side(k) * arm_pose.x, arm_pose.y, arm_pose.z).normalized()
		var upper := Quaternion(Vector3.RIGHT, _arm_swing[k]) * Quaternion(rest_dir, hang)
		_skel.set_bone_pose_rotation(_bone["arm_upper_" + side], upper)
		var bend: float = _spec.elbow * (1.0 - 0.6 * prone) - 0.3 * maxf(-_arm_swing[k], 0.0) - 0.1 * pace
		var lower := Quaternion(Vector3.RIGHT, bend) * Quaternion(Vector3.BACK, _side(k) * 0.2)
		if _spec.has("fore"):
			# Point the forearm where the species holds it at rest, whatever
			# way the upper arm has turned.
			var fore: Vector3 = _spec.fore
			var want := upper.inverse() * Vector3(_side(k) * fore.x, fore.y, fore.z).normalized()
			var rest_lower: Vector3 = (_rest["hand_" + side] - _rest["arm_lower_" + side]).normalized()
			lower = lower.slerp(Quaternion(rest_lower, want), _fore_blends[k])
		_skel.set_bone_pose_rotation(_bone["arm_lower_" + side], lower)

	# Tail: a lazy wave that trails behind turns and bounces with each step.
	for i in 4:
		var wave := sin(_time * 1.9 * (1.0 + 2.0 * nervous) - i * 0.8) * (0.07 + 0.03 * i) * (1.0 + 1.5 * nervous) - _sway * 1.2
		var lift := 0.06 - _lean * 0.5 + sin(_time * 1.3 - i * 0.6) * 0.03 + swing * 0.03
		_skel.set_bone_pose_rotation(_bone["tail%d" % (i + 1)], Quaternion.from_euler(Vector3(lift, wave, 0.0)))


## Fingers: clenched round what the hands hold, spread to strike or stomp,
## and otherwise loose, flexing a little now and then.
func _update_fingers(delta: float) -> void:
	var want := 0.15
	if _action == Action.GRAB and _held.size() > _released:
		want = 1.0
	elif is_instance_valid(carrying):
		want = 0.8
	elif _action == Action.STRIKE or _action == Action.STOMP or _alert:
		want = -0.6 if _action == Action.STRIKE else -0.3
	elif knocked_out:
		want = 0.5
	_grip = move_toward(_grip, want, delta * GRIP_SPEED)
	for f: Array in _fingers:
		var flex := _grip + 0.06 * sin(_time * 0.9 + float(f[2]))
		for j in 3:
			_skel.set_bone_pose_rotation(f[0][j], Quaternion(f[1], flex * FINGER_CURL[j]))


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
		var ankle: Vector3 = to_skel * (sole + Vector3.UP * _ankle * size)
		var small := lerpf(1.0, 0.1, smoothstep(0.0, 1.0, _shell))
		if small < 1.0:
			# Drawn up into the shell.
			_skel.set_bone_global_pose(_bone["thigh_" + side], Transform3D(Basis().scaled(Vector3.ONE * small), hip))
			_skel.set_bone_global_pose(_bone["shin_" + side], Transform3D(Basis().scaled(Vector3.ONE * small), hip + Vector3(0, -0.2, 0.05)))
			_skel.set_bone_global_pose(_bone["foot_" + side], Transform3D(Basis().scaled(Vector3.ONE * small), hip + Vector3(0, -0.4, 0.05)))
			continue
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
	if _spec.get("ankle_from_rig", false):
		_ankle = _rest["foot_r"].y
	if _spec.get("fingers", false):
		_find_fingers()

	if _spec.get("own_skin", false):
		# The model's own material, as Meshy made it: no cel shading, no outline.
		for node in model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).extra_cull_margin = 6.0
	else:
		_dress(model)
	if _spec.get("painted_face", false):
		_update_face(0.0)
		return
	_build_face()


## The rig's fingers (thumb, index, middle, ring on each hand; bones
## <finger>1_l .. <finger>3_l, from the knuckle out), each with the axis
## it curls about: the one it already bends round at rest.
func _find_fingers() -> void:
	for side in ["l", "r"]:
		for finger in ["thumb", "index", "middle", "ring"]:
			var names := ["%s1_%s" % [finger, side], "%s2_%s" % [finger, side], "%s3_%s" % [finger, side]]
			if not (_bone.has(names[0]) and _bone.has(names[1]) and _bone.has(names[2])):
				continue
			var a: Vector3 = _rest[names[1]] - _rest[names[0]]
			var b: Vector3 = _rest[names[2]] - _rest[names[1]]
			var axis := a.cross(b)
			if axis.length() < 1e-4:
				axis = a.cross(Vector3.FORWARD)
			_fingers.append([[_bone[names[0]], _bone[names[1]], _bone[names[2]]], axis.normalized(), float(_fingers.size()) * 1.7])


## The game's own look: the creature shader (cel lighting, hide texture)
## with an ink outline.
func _dress(model: Node3D) -> void:
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


## The face, attached to the head bone: eyeballs, pupils and lids that
## move on their own, and the mouth.
func _build_face() -> void:
	var attach := BoneAttachment3D.new()
	_skel.add_child(attach)
	attach.bone_name = "head"
	var paint := Art.paint("plaster", 0.25)
	var glowing: bool = _spec.has("eye_glow")
	var blank: bool = _spec.get("blank_eyes", false)
	var whites := MeshBuilder.new()
	whites.color = Color.WHITE if glowing else _spec.eye_color
	var e: float = _spec.eye_size
	var eye: Vector3 = _spec.eye
	for k in 2:
		var s := _side(k)
		var centre := Vector3(s * eye.x, eye.y, eye.z)
		_eye_centres.append(centre)
		whites.add_blob(Vector3(e, e, e * 0.88), Transform3D(Basis(), centre), null, 0.0, 8, 12)
		if blank:
			# No pupils: only the lids move.
			var cover := MeshBuilder.new()
			cover.color = _spec.lid_color
			cover.add_blob(Vector3(1.24, 0.88, 1.12) * e, Transform3D.IDENTITY, null, 0.0, 6, 10)
			_lids.append(_face_part(attach, cover.commit(), paint))
			continue
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
	if _lids.is_empty():
		# A face painted on the model.
		return
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
	var shut := 1.0 if _blink > 0.0 or knocked_out or hiding else 0.0
	var lid_y: Array = _spec.lid_y
	var lid_tilt: Array = _spec.lid_tilt
	var pupil: Array = _spec.pupil
	for k in 2:
		var s := _side(k)
		var c := _eye_centres[k]
		if k < _pupils.size():
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
