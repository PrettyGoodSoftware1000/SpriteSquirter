class_name CreatureMind
extends Node
## What the creature knows, likes and decides for itself. It is a child of
## the Creature, which does the moving and the fighting.
##
## Personality: each creature is born with traits that last its whole
## life (Balance "<kind>_<trait>_personality", 100% being average; see
## personality()): how readily it runs from a fight, does mischief, casts
## spells, notices things to learn from, and learns extra from them. Bless
## and Condemn train what it does on top of these.
##
## Knowledge: watching the player cast a spell, or the villagers store
## resources, may add knowledge towards doing it itself (if it notices:
## its observant personality; with a chance of extra: its knowledgeSeeker
## personality). With enough, the
## creature casts the spell when it suits (each spell costs the creature
## its own magicko, Balance "creature_cost_...", and has a short
## cooldown) or fetches trees, boulders and food for the storehouse.
## Rain is cast on fires and on growing wheat ("rain" with the condition
## "fire" or "crops"). Bless and Condemn are never learned.
##
## Behaviour: every action (see ActionTable and Actions.csv) has an
## affinity from -100 to 100, starting at Balance "affinity_start". Bless
## adds Balance "bless_points" (10) to what the creature last did, and
## Condemn takes "condemn_points" away. An action that has just been judged
## cannot be judged again for a while: a minute, or longer the stronger
## the affinity (see cooldown()). Bless and Condemn then judge the next
## action down its column whose condition held (see judge_target()).
##
## Every choice the creature makes is made at random, weighted by its
## affinities (see weight() and likely()): stomping, throwing or eating in
## a fight, whether to cast a spell, whether to run from a fight or hide in
## its shell, whether to go exploring, and what to fetch. The higher the
## affinity, the likelier; a low one makes a thing unlikely, never
## impossible. What it does under a condition (gathering wood when wood is
## the resource the village has least of, say) counts the affinities of the
## category and of each condition that holds, added up.
##
## All the amounts come from balancing.txt (see Balance).

const SPELLS := ["fireball", "rain", "roots", "lightning", "blood"]
const HARVESTS := ["lumber", "stone", "food"]
## The order it thinks of its spells in: fighting first.
const CASTS := ["fireball", "lightning", "roots", "rain", "blood"]
const SPELL_NAMES := {"fireball": "fireball", "rain": "rain", "roots": "roots", "lightning": "chain lightning", "blood": "blood sacrifice"}
## Bless and Condemn judge what the creature did in the last JUDGE_SECONDS.
const JUDGE_SECONDS := 30.0
## How often, in a fight, the creature thinks about running from it.
const FLEE_CHECK_SECONDS := 5.0
const KNOW_COLOR := Color(0.6, 0.85, 1.0)

## How often (seconds) it thinks about going to defend the village.
const DEFEND_CHECK_SECONDS := 5.0
var _defend_timer := 0.0
var creature: Creature
var knowledge := {}
var behavior := {}
## What it last did (an action category: see ActionTable), the conditions
## that held, and when.
var last_action := ""
## What was true when it did it (see passes()).
var last_facts := {}
var last_action_time := -1000.0
## Where the player last left the creature. It never strays far from here.
var home := Vector3.ZERO

var _ready_at := {}
## action -> when it was last blessed or condemned.
var _judged_at := {}
## The fetching job under way: {"kind", "action", "node", "stage"}, or empty.
var _task := {}
## Forest seeding: how many magic acorns it has thrown, and when (Game.now)
## it may throw the next.
var seeds_thrown := 0
var seed_ready_at := 0.0
## How far it throws a magic acorn.
const SEED_THROW := 14.0
var _think_timer := 1.0
var _idle_timer := 8.0
var _flee_timer := FLEE_CHECK_SECONDS
var _away := false


## Every action the creature can be blessed or condemned for.
static func all_actions() -> Array[String]:
	return ActionTable.all()


func _ready() -> void:
	creature = get_parent() as Creature
	for id: String in SPELLS + HARVESTS:
		knowledge[id] = 0.0
	# Some creatures are born knowing a spell (Creature.SPECIES "knows").
	for id: String in creature._species().get("knows", []):
		knowledge[id] = needed(id)
	for action in all_actions():
		behavior[action] = clampf(Balance.num("affinity_start"), -100.0, 100.0)
	if creature.hostile:
		# The goblins' giant learns nothing and decides nothing here.
		set_process(false)
		return
	if is_instance_valid(Game.village):
		Game.village.lesson.connect(_on_lesson)


# --- Knowledge ------------------------------------------------------------------

func needed(id: String) -> float:
	return Balance.num("knowledge_" + id)


func learned(id: String) -> bool:
	return knowledge.get(id, 0.0) >= needed(id)


## The player cast a spell where the creature could see it.
func watch_spell(id: String) -> void:
	if SPELLS.has(id):
		_learn(id, Balance.num("knowledge_per_watch"), "watched_spell", {"spell": SPELL_NAMES[id]})


func _on_lesson(kind: String) -> void:
	_learn(kind, Balance.num("knowledge_per_lesson"), "watched_store", {"amount": int(Balance.num("stored_per_lesson")), "resource": kind})


## One of the creature's personality traits ("flee", "mischief",
## "spellcaster", "observant", "knowledgeSeeker"): a multiplier, 1 average.
func personality(quality: String) -> float:
	return maxf(0.0, Balance.num(creature.kind + "_" + quality + "_personality"))


## Something to learn from happened: it learns `points` towards `id` if it
## notices (Balance "notice_chance" times its observant personality), and
## sometimes extra on top ("bonus_knowledge_chance" times its
## knowledgeSeeker personality: "bonus_knowledge" more).
func _learn(id: String, points: float, saw: String, fill: Dictionary) -> void:
	if learned(id):
		return
	if randf() >= Balance.num("notice_chance") * personality("observant"):
		return
	if randf() < Balance.num("bonus_knowledge_chance") * personality("knowledgeSeeker"):
		points *= 1.0 + Balance.num("bonus_knowledge")
	knowledge[id] += points
	fill["have"] = int(minf(knowledge[id], needed(id)))
	fill["need"] = int(needed(id))
	creature.say(Texts.line(saw, fill), KNOW_COLOR)
	if learned(id):
		creature.say(Texts.line("learned_" + id), Color(1.0, 0.9, 0.4))


# --- Behaviour ------------------------------------------------------------------

## The creature's affinity for doing `category` in the situation `facts`
## (see passes()): the affinities of every action in its column whose
## condition holds, added up.
func score(category: String, facts: Dictionary = {}) -> float:
	var total := 0.0
	for action in applicable(category, facts):
		total += behavior.get(action, 0.0)
	return total


## How much the creature leans towards `category` in the situation `facts`:
## 1 at an affinity of 0, growing steeply with a higher one and shrinking
## towards (but never reaching) nothing with a lower one. Choices between
## things to do are made at random, in proportion to these.
func weight(category: String, facts: Dictionary = {}) -> float:
	return exp(clampf(score(category, facts), -300.0, 300.0) / maxf(Balance.num("affinity_spread"), 1.0))


## Yes or no to doing `category` now, at random: an even chance at an
## affinity of 0, likelier the higher it is, never quite certain either way.
func likely(category: String, facts: Dictionary = {}) -> bool:
	var w := weight(category, facts)
	return randf() < w / (1.0 + w)


## Picks one of `options` (key -> weight) at random, in proportion to the weights.
static func pick(options: Dictionary) -> Variant:
	var total := 0.0
	for key: Variant in options:
		total += options[key]
	var roll := randf() * total
	for key: Variant in options:
		roll -= options[key]
		if roll <= 0.0:
			return key
	return options.keys().back() if not options.is_empty() else null


## The ids of the actions in `category`'s column, top to bottom, whose
## condition holds in `facts`.
func applicable(category: String, facts: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	for action: Dictionary in ActionTable.column(category):
		var ok := true
		for test: Array in action.tests:
			if not passes(test, facts):
				ok = false
				break
		if ok:
			out.append(action.id)
	return out


## Whether one of an action's tests (see ActionTable) holds in `facts`,
## what was true when the creature did something:
##   battle        a battle was on
##   highest, lowest, stock   the resource fetched was the one the village
##                 had most (least) of, and how much of it there was
##   health        0..1 of its health
##   magicko, housing_free    the village's magicko; room for another villager
##   target, hit   what a spell was aimed at, and every kind of thing it
##                 caught ("enemy", "villager", "tree", "enemy_building",
##                 "our_building", "fire", "crops" or "nothing")
##   wet, hits     an enemy it struck was wet; how many enemies it struck
static func passes(test: Array, facts: Dictionary) -> bool:
	var health: float = facts.get("health", 1.0)
	match test[0]:
		"never":
			return false
		"battle", "highest", "lowest", "wet", "housing_free":
			return facts.get(test[0], false)
		"housing_full":
			return not facts.get("housing_free", true)
		"stock_at_most":
			return float(facts.get("stock", INF)) <= test[1]
		"stock_above":
			return float(facts.get("stock", -INF)) > test[1]
		"health_at_least":
			return health >= test[1]
		"health_above":
			return health > test[1]
		"health_below":
			return health < test[1]
		"health_between":
			return health >= test[1] and health <= test[2]
		"magicko_below":
			return float(facts.get("magicko", INF)) < test[1]
		"magicko_above":
			return float(facts.get("magicko", -INF)) > test[1]
		"target":
			return facts.get("target", "") == test[1] or (facts.get("hit", []) as Array).has(test[1])
		"hits_at_least":
			return int(facts.get("hits", 0)) >= test[1]
	return false


## Records what the creature just did (`category`, in the situation
## `facts`) for Bless and Condemn to judge, and floats `text` up from its
## head.
func did(category: String, facts: Dictionary = {}, text := "") -> void:
	last_action = category
	last_facts = facts.duplicate()
	last_action_time = Game.now
	# What floats up is the owner's sentence for it from Actions.csv (the
	# most specific one that fits); `text` only if there is none.
	var sentence := action_sentence(category, facts)
	if sentence != "":
		creature.say(sentence)
	elif text != "":
		creature.say(text)


## The sentence from Actions.csv for doing `category` when `facts` held: the
## first (most specific) action of its column that applies and has one,
## with the enemy's name filled in. "" if there is none.
func action_sentence(category: String, facts: Dictionary) -> String:
	for action in applicable(category, facts):
		var sentence: String = ActionTable.find(action).get("sentence", "")
		if sentence != "":
			return ActionTable.fill(sentence, facts.get("enemy", ""))
	return ""


## The sentence for an action from Actions.csv, as Bless and Condemn show
## it, with the enemy's name from what the creature last did.
func describe(action: String) -> String:
	var found := ActionTable.find(action)
	var sentence: String = found.get("sentence", "")
	if sentence == "":
		sentence = action
	return ActionTable.fill(sentence, last_facts.get("enemy", "enemy"))


## How long after being blessed or condemned an action must wait before it
## can be again: longer the stronger the creature's affinity for it.
func cooldown(action: String) -> float:
	var strength := absf(behavior.get(action, 0.0))
	if strength >= 80.0:
		return Balance.num("judge_cooldown_80")
	if strength >= 60.0:
		return Balance.num("judge_cooldown_60")
	if strength >= 30.0:
		return Balance.num("judge_cooldown_30")
	return Balance.num("judge_cooldown")


## Seconds until `action` can be blessed or condemned again (0: now).
func cooling(action: String) -> float:
	if not _judged_at.has(action):
		return 0.0
	return maxf(0.0, float(_judged_at[action]) + cooldown(action) - Game.now)


## What Bless or Condemn would judge now: the first action in the column of
## what the creature last did whose condition held then and that is not
## cooling down. "" if there is none (or it did nothing lately).
func judge_target() -> String:
	if last_action == "" or Game.now - last_action_time > JUDGE_SECONDS:
		return ""
	for action in applicable(last_action, last_facts):
		if cooling(action) <= 0.0:
			return action
	return ""


## Seconds until the soonest of the actions that applied to what the
## creature last did can be judged again.
func soonest_judgement() -> float:
	var soonest := INF
	for action in applicable(last_action, last_facts):
		soonest = minf(soonest, cooling(action))
	return soonest


## True if Bless or Condemn would have something to judge.
func can_judge() -> bool:
	return judge_target() != ""


## Bless (sign +1) or Condemn (sign -1): Balance "bless_points" (or
## "condemn_points") more (or less) affinity for judge_target(). Returns
## what to tell the player.
func judge(sign_value: int) -> String:
	var who := creature.species_name().to_lower()
	if last_action == "" or Game.now - last_action_time > JUDGE_SECONDS:
		creature.say(Texts.line("creature_confused"), Color(0.8, 0.8, 0.8))
		return Texts.line("judge_nothing", {"creature": who, "seconds": int(JUDGE_SECONDS)})
	var target := judge_target()
	if target == "":
		var general: Array = ActionTable.column(last_action)
		return Texts.line("judge_cooling", {"creature": who, "action": describe(general.back().id), "seconds": ceili(soonest_judgement())})
	var points := Balance.num("bless_points") if sign_value > 0 else -Balance.num("condemn_points")
	# A rare action can count for more: Balance "<action>_judge_points".
	if Balance.num(last_action + "_judge_points") > 0.0:
		points = Balance.num(last_action + "_judge_points") * signf(sign_value)
	behavior[target] = clampf(behavior.get(target, 0.0) + points, -100.0, 100.0)
	_judged_at[target] = Game.now
	var value := roundi(behavior[target])
	creature.say(Texts.line("creature_blessed" if sign_value > 0 else "creature_condemned", {"value": value}),
		Color(1.0, 0.9, 0.3) if sign_value > 0 else Color(1.0, 0.25, 0.2))
	return Texts.line("bless_result" if sign_value > 0 else "condemn_result", {"action": describe(target), "value": value,
		"seconds": roundi(cooldown(target))})


## The player sent the creature somewhere: that is its new home.
func player_moved(pos: Vector3) -> void:
	home = pos
	_drop_task()
	_away = false
	_idle_timer = randf_range(8.0, 14.0)


## What is true now for fetching `kind` (see passes()): whether it is the
## resource (of lumber, stone and food) the village has most or least of,
## how much of it there is, and whether a battle is on.
func gather_facts(kind: String) -> Dictionary:
	var facts := {"battle": _battle_raging()}
	var village := Game.village
	if is_instance_valid(village):
		var have := village.amount(kind)
		var most := true
		var least := true
		for other: String in HARVESTS:
			if other != kind:
				most = most and have > village.amount(other)
				least = least and have < village.amount(other)
		facts["highest"] = most
		facts["lowest"] = least
		facts["stock"] = have
	return facts


## True while enemies are inside the village's influence (a battle).
func _battle_raging() -> bool:
	# Only enemies inside the village's influence make a battle: goblins
	# marching on it from outside do not.
	var village := Game.village
	if not is_instance_valid(village) or not village.founded:
		return false
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.is_alive() and not g.charmed() and village.in_territory(g.global_position):
			return true
	for node in get_tree().get_nodes_in_group("balrogs"):
		var b := node as Creature
		if not b.knocked_out and village.in_territory(b.global_position):
			return true
	return false


## How hurt the creature is now: "unharmed", "slightly", "badly" or
## "near_death".
func health_word() -> String:
	var health := creature.health_share()
	if health >= 0.95:
		return "unharmed"
	if health >= 0.6:
		return "slightly"
	if health >= 0.25:
		return "badly"
	return "near_death"


## In a fight, now and then: run from it, as readily as its flee
## personality and its affinities for running at its present health say.
func _consider_fleeing() -> bool:
	if creature.is_fleeing() or not _enemy_close():
		return false
	var facts := {"health": creature.health_share(), "battle": true}
	# How hurt it is matters only as far as it has been trained to care
	# (its affinities for running at that health); the rest is personality.
	var chance := Balance.num("flee_chance") * personality("flee") * weight("flee", facts)
	if randf() >= chance or not creature.run_from_battle():
		return false
	_drop_task()
	_away = true
	did("flee", facts, Texts.line("fled"))
	return true


## True with a goblin close enough to fight.
func _enemy_close() -> bool:
	var near := Creature.REACH * creature.size + 6.0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.is_alive() and g.state != Villager.State.HELD and not g.charmed() and creature._flat(g.global_position, creature.global_position) < near:
			return true
	var rival := creature._rival()
	return rival != null and creature._flat(rival.global_position, creature.global_position) - 2.0 * rival.size < near


# --- Deciding -------------------------------------------------------------------

func _process(delta: float) -> void:
	if creature.knocked_out or creature.hiding:
		_drop_task()
		return
	_update_task()
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = 1.0
	if creature.is_fighting():
		_drop_task()
		_flee_timer -= 1.0
		if _flee_timer <= 0.0:
			_flee_timer = FLEE_CHECK_SECONDS
			if _consider_fleeing():
				return
	if _try_spells():
		return
	if _consider_defending():
		return
	if creature.is_fighting() or not _task.is_empty():
		return
	if creature.has_target and not creature.is_auto():
		return
	_idle_timer -= 1.0
	if _idle_timer <= 0.0 and not creature.has_target:
		_choose_idle()


## Defending the village: when goblins (or the balrog) marching on it come
## within Balance "defend_range" metres of one of its Storehouses, the
## creature is likely to go and attack them (an attack move at the
## nearest), unless it is fighting already, running away, or doing what
## the player told it. How likely, each DEFEND_CHECK_SECONDS: Balance
## "defensive_weight" times its defensive personality (and its affinity
## for "defend", once Actions.csv has a Defend column for Bless and Condemn
## to train): k makes it k / (1 + k). True if it set off.
func _consider_defending() -> bool:
	_defend_timer -= 1.0
	if _defend_timer > 0.0:
		return false
	_defend_timer = DEFEND_CHECK_SECONDS
	if creature.attack_moving or creature.is_fighting() or creature.is_fleeing() or creature.hostile:
		return false
	if creature.has_target and not creature.is_auto():
		return false
	var raider := marching_on_stores()
	if raider == null:
		return false
	var facts := {"battle": true}
	var k := Balance.num("defensive_weight") * personality("defensive") * weight("defend", facts)
	if randf() >= k / (1.0 + k):
		return false
	_drop_task()
	creature.attack_move(raider.global_position)
	did("defend", facts, Texts.line("creature_defends"))
	return true


## The nearest enemy marching on the village that has come within Balance
## "defend_range" metres of one of its Storehouses, or null.
func marching_on_stores() -> Node3D:
	var stores: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if b != null and not b.destroyed and BuildingCatalog.role(b.get_meta("kind", "")) == "store":
			stores.append(b.global_position)
	if stores.is_empty():
		return null
	var reach := Balance.num("defend_range")
	var best: Node3D = null
	var best_d := INF
	var marchers: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g != null and g.raiding and g.is_alive() and not g.charmed():
			marchers.append(g)
	for node in get_tree().get_nodes_in_group("balrogs"):
		var b := node as Creature
		if b != creature and b.is_threat():
			marchers.append(b)
	for m in marchers:
		for at in stores:
			if Vector2(m.global_position.x - at.x, m.global_position.z - at.z).length() < reach:
				var d := m.global_position.distance_to(creature.global_position)
				if d < best_d:
					best_d = d
					best = m
				break
	return best


## Left to itself: come home if it has strayed; otherwise pick at random,
## weighted by its affinities, between a short wander, exploring (now and
## then: Balance "explore_weight" of the weight it would have) and
## fetching what it has learned to fetch ("gather_weight" of its weight).
func _choose_idle() -> void:
	_idle_timer = randf_range(6.0, 12.0)
	var from_home := Vector2(creature.global_position.x - home.x, creature.global_position.z - home.z).length()
	if _away or from_home > 5.0:
		_away = false
		creature.auto_move(home)
		return
	var options := {"wander": Balance.num("wander_weight"), "explore": Balance.num("explore_weight") * weight("explore", {"battle": _battle_raging()})}
	var facts := {}
	# The squirrel's forest seeding: rare (Balance "forest_seed_weight"),
	# as keen as its nature and training, and only off its cooldown.
	if creature.kind == "squirrel" and Game.now >= seed_ready_at and is_instance_valid(Game.village) and Game.village.founded:
		facts["seed"] = {"battle": _battle_raging()}
		options["seed"] = Balance.num("forest_seed_weight") * personality("forestSeeder") * weight("seed", facts["seed"])
	# (Big enough to carry something home, or a tortoise: Creature.SPECIES
	# "gathers_small".) Fetching what it knows is Balance "gather_weight" as
	# likely as its affinities alone make it.
	if creature.size >= 0.3 or creature._species().get("gathers_small", false):
		for kind: String in HARVESTS:
			if learned(kind) and _harvest_target(kind) != null:
				facts[kind] = gather_facts(kind)
				options[kind] = weight(kind, facts[kind]) * Balance.num("gather_weight")
	var choice: String = pick(options)
	match choice:
		"wander":
			_wander()
		"explore":
			if not _explore():
				_wander()
		"seed":
			var spot: Variant = seed_spot()
			if spot == null:
				_wander()
			else:
				_task = {"kind": "seed", "spot": spot, "facts": facts["seed"], "stage": "go"}
		_:
			_task = {"kind": choice, "facts": facts[choice], "node": _harvest_target(choice), "stage": "go"}


# --- Forest seeding (the squirrel) -----------------------------------------------

## Somewhere to plant a magic tree: within half the village's influence of
## its centre, on dry, level ground clear of buildings, trees and fields,
## and well away from any other magic tree. Null if nowhere is found.
func seed_spot() -> Variant:
	var village := Game.village
	if not is_instance_valid(village) or not village.founded:
		return null
	var terrain := Game.terrain
	var reach := village.influence() * 0.5
	for attempt in 24:
		var a := randf() * TAU
		var p := village.center + Vector3(cos(a), 0.0, sin(a)) * sqrt(randf()) * reach
		if not terrain.is_inside(p.x, p.z) or not terrain.is_dry(p.x, p.z) or terrain.get_normal(p.x, p.z).y < 0.85:
			continue
		p.y = terrain.get_height(p.x, p.z)
		if village._crowded(p, get_tree()):
			continue
		var crowded := false
		for node in get_tree().get_nodes_in_group("buildings") + get_tree().get_nodes_in_group("construction_sites"):
			var b := node as Node3D
			var footprint: float = b.get("footprint") if b.get("footprint") != null else 4.0
			if Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < footprint + 6.0:
				crowded = true
				break
		for node in get_tree().get_nodes_in_group("magic_trees"):
			if Vector2((node as Node3D).global_position.x - p.x, (node as Node3D).global_position.z - p.z).length() < 20.0:
				crowded = true
				break
		if not crowded:
			return p
	return null


## Off to where the magic tree is to go, then the acorn is thrown there.
func _update_seeding() -> void:
	var spot: Vector3 = _task.spot
	if _task.stage == "go":
		var d := Vector2(spot.x - creature.global_position.x, spot.z - creature.global_position.z).length()
		if d > SEED_THROW:
			if not creature.has_target or creature.target.distance_to(spot) > 1.0:
				creature.auto_move(spot)
			return
		creature.has_target = false
		creature.toss_acorn(spot)
		seeded()
		did("seed", _task.facts, Texts.line("forest_seeded"))
		_task.stage = "toss"
		_task.t = Game.now
		return
	if Game.now - float(_task.t) > 1.5:
		_task = {}
		_away = true
		_idle_timer = randf_range(4.0, 8.0)


## A magic acorn has been thrown: the next must wait Balance
## "forest_seed_cooldown_1" minutes after the first, "..._2" after the
## second and "..._3" after any more.
func seeded() -> void:
	seeds_thrown += 1
	seed_ready_at = Game.now + Balance.num("forest_seed_cooldown_%d" % mini(seeds_thrown, 3)) * 60.0


## A short walk to somewhere near home. (This is not exploring.)
func _wander() -> void:
	var terrain := Game.terrain
	var reach := 10.0 + 14.0 * creature.size
	for attempt in 8:
		var a := randf() * TAU
		var p := home + Vector3(cos(a), 0.0, sin(a)) * randf_range(reach * 0.5, reach)
		if terrain.is_inside(p.x, p.z) and terrain.is_dry(p.x, p.z):
			creature.auto_move(p)
			_away = true
			return


## Exploring: a long trip, from Balance "explore_least" metres up to half
## the map away from where it was sent, and then back. False if it found
## nowhere to go.
func _explore() -> bool:
	var terrain := Game.terrain
	var least := Balance.num("explore_least")
	var most := maxf(Terrain.SIZE * 0.5, least + 1.0)
	for attempt in 16:
		var a := randf() * TAU
		var p := home + Vector3(cos(a), 0.0, sin(a)) * randf_range(least, most)
		if terrain.is_inside(p.x, p.z) and terrain.is_dry(p.x, p.z):
			creature.auto_move(p)
			_away = true
			did("explore", {"battle": _battle_raging()})
			return true
	return false


# --- Spells ---------------------------------------------------------------------

## Thinks about each spell it knows (and can pay for, and has rested from)
## in turn: picks at random between holding off (Balance
## "spell_hold_weight") and each place it could cast it, weighted by how
## much it is for (useful places: 1; mischief, such as fireball at a
## villager, "mischief_weight" times its mischief personality), its
## spellcaster personality, and its affinity for doing that. Casts the
## first one picked.
func _try_spells() -> bool:
	if not is_instance_valid(Game.village) or not Game.village.founded:
		return false
	# (It casts in the air too: the raven over a fight, on the way somewhere.)
	if creature.running:
		return false
	for spell: String in CASTS:
		if not learned(spell) or Game.now < _ready_at.get(spell, 0.0) or creature.magicko < Balance.num("creature_cost_" + spell):
			continue
		var options := {"hold": Balance.num("spell_hold_weight")}
		var choices := _spell_options(spell)
		for k in choices.size():
			var choice: Dictionary = choices[k]
			options[k] = float(choice.base) * personality("spellcaster") * weight(spell, choice.facts)
		var picked: Variant = pick(options)
		if typeof(picked) == TYPE_STRING:
			continue
		var chosen: Dictionary = choices[picked]
		_ready_at[spell] = Game.now + Balance.num("cooldown_" + spell)
		if creature.spend_magicko(Balance.num("creature_cost_" + spell)):
			_cast(spell, chosen.pos, chosen.facts)
			return true
	return false


## Where the creature could cast `spell` now, each {pos, facts, base}:
## what it would be aimed at (see passes()) and how much it is for
## (1 for a use the spell is meant for; for mischief, Balance
## "mischief_weight" times its mischief personality).
func _spell_options(spell: String) -> Array:
	var out: Array = []
	var village := Game.village
	var tree := get_tree()
	var battle := _battle_raging()
	var mischief := Balance.num("mischief_weight") * personality("mischief")
	var reach := 45.0
	match spell:
		"fireball":
			# A knot of enemies, away from the village's buildings.
			var enemies: Variant = _enemy_cluster(Fireball.BLAST_RADIUS * 0.7, 3, 10.0, 70.0, true)
			if enemies != null:
				out.append({"pos": enemies, "base": 1.0, "facts": {"target": "enemy", "enemy": _enemy_name_near(enemies, 6.0), "battle": battle}})
			var hut := _nearest_in(tree.get_nodes_in_group("goblin_buildings"), 70.0, 10.0)
			if hut != null:
				out.append({"pos": hut.global_position, "base": 1.0, "facts": {"target": "enemy_building", "battle": battle}})
			var person := _nearest_in(village.people(), reach, 8.0)
			if person != null:
				out.append({"pos": person.global_position, "base": mischief, "facts": {"target": "villager", "battle": battle}})
			var tree_node := _nearest_in(tree.get_nodes_in_group("trees"), reach, 8.0)
			if tree_node != null:
				out.append({"pos": tree_node.global_position, "base": mischief, "facts": {"target": "tree", "battle": battle}})
			var ours := _nearest_in(tree.get_nodes_in_group("player_buildings"), reach, 10.0)
			if ours != null:
				out.append({"pos": ours.global_position, "base": mischief, "facts": {"target": "our_building", "battle": battle}})
		"lightning":
			# A crowd of enemies with none of our own people among them.
			var crowd: Variant = _enemy_cluster(Balance.num("lightning_jump_range"), 3, Balance.num("lightning_jump_range") + 3.0, 70.0, false)
			if crowd != null:
				out.append({"pos": crowd, "base": 1.0, "facts": {"target": "enemy"}})
			var person := _nearest_in(village.people(), reach, 6.0)
			if person != null:
				out.append({"pos": person.global_position, "base": mischief, "facts": {"target": "villager"}})
			out.append({"pos": _empty_spot(), "base": mischief, "facts": {"target": "nothing"}})
		"roots":
			# A bigger crowd of raiders, with none of our own people among them.
			var crowd: Variant = _enemy_cluster(RootPatch.RADIUS, 4, RootPatch.RADIUS + 4.0, 70.0, false)
			if crowd != null:
				out.append({"pos": crowd, "base": 1.0, "facts": {"target": "enemy", "enemy": _enemy_name_near(crowd, RootPatch.RADIUS)}})
			var person := _nearest_in(village.people(), reach, 6.0)
			if person != null:
				out.append({"pos": person.global_position, "base": mischief, "facts": {"target": "villager"}})
			out.append({"pos": _empty_spot(), "base": mischief, "facts": {"target": "nothing"}})
		"rain":
			var fire: Variant = null
			for node in tree.get_nodes_in_group("player_buildings"):
				if (node as Destructible).burning:
					fire = (node as Node3D).global_position
					break
			if fire == null:
				for f in Game.fire._fires:
					var p: Vector3 = f.pos
					if p.distance_to(village.center) < 45.0:
						fire = p
						break
			if fire != null:
				out.append({"pos": fire, "base": 1.0, "facts": {"target": "fire", "battle": battle}})
			for node in tree.get_nodes_in_group("fields"):
				var field := node as CropField
				if field.stage == CropField.Stage.GROWING and not field.is_wet() and not Game.fire.is_wet(field.global_position):
					out.append({"pos": field.global_position, "base": 1.0, "facts": {"target": "crops", "battle": battle}})
					break
			var raiders: Variant = _enemy_cluster(RainCloud.RADIUS * 0.6, 3, 8.0, 70.0, false)
			if raiders != null:
				out.append({"pos": raiders, "base": Balance.num("rain_enemies_weight"),
					"facts": {"target": "enemy", "enemy": _enemy_name_near(raiders, RainCloud.RADIUS * 0.6), "battle": battle}})
			out.append({"pos": _empty_spot(), "base": mischief, "facts": {"target": "nothing", "battle": battle}})
		"blood":
			# A sacrifice is meant for when magicko has run low, or there is
			# no room for more villagers, and there are people to spare; at
			# any other time it is mischief.
			if village.population() >= 12 and not village.blood_active():
				var low := village.amount("magicko") < Balance.num("creature_blood_magicko")
				var full := village.population() >= village.housing()
				out.append({"pos": village.center, "base": 1.0 if low or full else mischief,
					"facts": {"magicko": village.amount("magicko"), "housing_free": village.population() < village.housing(), "battle": battle}})
	return out


## The node of `nodes` nearest the creature, at least `least` and at most
## `most` metres away (flat), or null.
func _nearest_in(nodes: Array, most: float, least := 0.0) -> Node3D:
	var best: Node3D = null
	var best_d := most
	for node: Variant in nodes:
		var n := node as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var d := creature._flat(n.global_position, creature.global_position)
		if d < best_d and d >= least:
			best_d = d
			best = n
	return best


## Somewhere on dry land 15 to 30 m from the creature, with nothing in
## particular there.
func _empty_spot() -> Vector3:
	var terrain := Game.terrain
	for attempt in 8:
		var a := randf() * TAU
		var p := creature.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(15.0, 30.0)
		if terrain.is_inside(p.x, p.z) and terrain.is_dry(p.x, p.z):
			return Vector3(p.x, terrain.get_height(p.x, p.z), p.z)
	return creature.global_position + Vector3(20.0, 0.0, 0.0)


## The commonest kind of enemy within `radius` of `pos`: its name.
func _enemy_name_near(pos: Vector3, radius: float) -> String:
	var found: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("goblins") + get_tree().get_nodes_in_group("bats") + get_tree().get_nodes_in_group("balrogs"):
		if (node as Node3D).global_position.distance_to(pos) < radius:
			found.append(node as Node3D)
	return Creature.enemy_name(found)


## The middle of the best group of enemies within `radius` of each other.
func _enemy_cluster(radius: float, at_least: int, nearest: float, farthest: float, spare_buildings: bool) -> Variant:
	var tree := get_tree()
	var goblins := tree.get_nodes_in_group("goblins")
	var village := Game.village
	var best: Variant = null
	var best_score := at_least - 0.5
	for node in goblins:
		var g := node as Villager
		var p := g.global_position
		var d := p.distance_to(creature.global_position)
		if d < nearest or d > farthest:
			continue
		if not g.raiding and p.distance_to(village.center) > 50.0:
			continue
		var score := 0.0
		for other in goblins:
			var o := other as Villager
			if o.global_position.distance_to(p) < radius:
				score += 3.0 if o.ogre else 1.0
		for b in tree.get_nodes_in_group("balrogs"):
			if (b as Node3D).global_position.distance_to(p) < radius:
				score += 4.0
		for v in village.people():
			if v.global_position.distance_to(p) < radius + 2.0:
				score -= 1.5 if spare_buildings else 100.0
		if spare_buildings:
			for b in tree.get_nodes_in_group("player_buildings"):
				if (b as Node3D).global_position.distance_to(p) < radius + (b as Destructible).footprint + 4.0:
					score = -100.0
		if score > best_score:
			best_score = score
			best = p
	return best


## Casts `spell` at `target`. What it did is recorded with `facts`, and,
## for spells that catch things where they land, with everything caught.
func _cast(spell: String, target: Vector3, facts: Dictionary) -> void:
	creature.casting_at(target)
	var result := facts.duplicate()
	match spell:
		"fireball":
			var fb := Fireball.new()
			fb.friendly = Balance.num("creature_friendly_fire")
			Game.world_root.add_child(fb)
			fb.launch(creature.mouth_position(), target)
			did(spell, result, Texts.line("cast_fireball"))
			NeutralVillage.creature_helped(target, true)
		"rain":
			var cloud := RainCloud.new()
			Game.world_root.add_child(cloud)
			cloud.cast(target)
			did(spell, result, Texts.line("cast_water" if facts.get("target", "") == "crops" else "cast_rain"))
			NeutralVillage.creature_helped(target)
		"roots":
			var patch := RootPatch.new()
			Game.world_root.add_child(patch)
			patch.cast(target)
			result["hit"] = _caught_near(target, RootPatch.RADIUS)
			did(spell, result, Texts.line("cast_roots"))
			NeutralVillage.creature_helped(target, true)
		"lightning":
			ChainLightning.cast(target, Balance.num("creature_friendly_fire"))
			var hit: Array[String] = []
			var enemies: Array[Node3D] = []
			var wet := false
			for node in ChainLightning.last_struck:
				if not is_instance_valid(node):
					continue
				var v := node as Villager
				if v != null and v.owned:
					if not hit.has("villager"):
						hit.append("villager")
					continue
				enemies.append(node)
				wet = wet or (v != null and v.is_wet())
			if not enemies.is_empty():
				hit.append("enemy")
			result["hit"] = hit
			result["target"] = "nothing" if hit.is_empty() else result.get("target", "enemy")
			result["hits"] = enemies.size()
			result["wet"] = wet
			result["enemy"] = Creature.enemy_name(enemies)
			did(spell, result, Texts.line("cast_lightning"))
			if not enemies.is_empty():
				NeutralVillage.creature_helped(target, true)
		"blood":
			if Game.village.sacrifice_someone():
				did(spell, result, Texts.line("cast_blood"))


## The kinds of things within `radius` of `pos`: "villager", "enemy", or
## "nothing" if neither.
func _caught_near(pos: Vector3, radius: float) -> Array[String]:
	var out: Array[String] = []
	for v in Game.village.people():
		if Vector2(v.global_position.x - pos.x, v.global_position.z - pos.z).length() < radius:
			out.append("villager")
			break
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Node3D
		if Vector2(g.global_position.x - pos.x, g.global_position.z - pos.z).length() < radius:
			out.append("enemy")
			break
	if out.is_empty():
		out.append("nothing")
	return out


# --- Fetching -------------------------------------------------------------------

## The tree, boulder or wheat field the creature would go for, or null.
func _harvest_target(kind: String) -> Node:
	var village := Game.village
	if not is_instance_valid(village):
		return null
	if kind == "food":
		for node in get_tree().get_nodes_in_group("fields"):
			if (node as CropField).stage == CropField.Stage.RIPE:
				return node
		# No ripe wheat: forage at the village itself.
		return village
	var best: Node3D = null
	var best_d := 90.0
	for node in get_tree().get_nodes_in_group("trees" if kind == "lumber" else "rocks"):
		var n := node as Node3D
		var tree := n as Destructible
		if tree and (tree.burning or tree.destroyed or tree.footprint < 1.2):
			continue
		# (Only inside the village's influence.)
		if not village.in_territory(n.global_position):
			continue
		var d := n.global_position.distance_to(creature.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _update_task() -> void:
	if _task.is_empty():
		return
	var kind: String = _task.kind
	var village := Game.village
	if kind == "seed":
		_update_seeding()
		return
	if not is_instance_valid(village) or not is_instance_valid(_task.node):
		_drop_task()
		return
	var reach := 2.0 + 4.0 * creature.size
	if _task.stage == "go":
		var node: Node = _task.node
		var goal: Vector3 = village.center + Vector3(14.0, 0.0, 6.0) if node == village else (node as Node3D).global_position
		if Vector2(goal.x - creature.global_position.x, goal.z - creature.global_position.z).length() > reach:
			if not creature.has_target or creature.target.distance_to(goal) > 1.0:
				creature.auto_move(goal)
			return
		# Pick it up: the tree or boulder itself, or a sheaf of food.
		creature.has_target = false
		var load: Node3D
		if kind == "food":
			var field := node as CropField
			_task.amount = _amount() if field == null else field.take(_amount())
			load = _sheaf()
		else:
			_task.amount = _amount()
			load = node as Node3D
			var tree := node as Destructible
			if tree:
				tree.uproot()
			else:
				node.remove_from_group("rocks")
				node.remove_from_group("grounded")
		Game.effects.spawn_dust(goal, 2.0 * creature.size)
		# (A neutral village nearby sees it gathering.)
		NeutralVillage.creature_helped(goal)
		creature.carry(load)
		_task.stage = "carry"
		return
	var drop := village.drop_point(creature.global_position, kind)
	if Vector2(drop.x - creature.global_position.x, drop.z - creature.global_position.z).length() > reach + 3.0:
		if not creature.has_target or creature.target.distance_to(drop) > 1.0:
			creature.auto_move(drop)
		return
	creature.has_target = false
	var amount: float = _task.amount
	village.give(kind, amount)
	# (What it is judged on is how things were when it set out.)
	var task_facts: Dictionary = _task.get("facts", {})
	creature.drop_load()
	Game.effects.spawn_dust(drop, 2.0 * creature.size)
	_task = {}
	_away = true
	_idle_timer = randf_range(3.0, 6.0)
	did(kind, task_facts, Texts.line("brought_" + kind, {"amount": roundi(amount)}))


func _amount() -> float:
	return maxf(1.0, roundf(Balance.num("creature_gather_amount") * creature.size))


func _sheaf() -> Node3D:
	var mb := MeshBuilder.new()
	mb.color = Color(1.0, 0.8, 0.28)
	mb.add_blob(Vector3(0.9, 1.3, 0.9), Transform3D.IDENTITY, null, 0.0, 6, 10)
	mb.color = Color(0.6, 0.4, 0.2)
	mb.add_lathe(PackedVector2Array([Vector2(0.86, -0.15), Vector2(0.95, 0.0), Vector2(0.86, 0.15)]), 12)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = Art.paint("plaster", 0.5)
	mi.scale = Vector3.ONE * creature.size
	Game.world_root.add_child(mi)
	return mi


## Gives up the fetching job, dropping (and losing) anything in its arms.
func _drop_task() -> void:
	if _task.is_empty():
		return
	if _task.stage == "carry":
		creature.drop_load()
	_task = {}
