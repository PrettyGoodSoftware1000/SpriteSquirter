class_name CreatureMind
extends Node
## What the creature knows, likes and decides for itself. It is a child of
## the Creature, which does the moving and the fighting.
##
## Knowledge: watching the player cast a spell, or the villagers store
## resources, adds knowledge towards doing it itself. With enough, the
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
## What it may cast, in the order it thinks of them: fighting first.
## ("water" is the rain spell, cast on growing wheat.)
const CASTS := ["fireball", "lightning", "roots", "rain", "blood", "water"]
## More than this of a resource in store is plenty.
const PLENTY := 200.0
const SPELL_NAMES := {"fireball": "fireball", "rain": "rain", "roots": "roots", "lightning": "chain lightning", "blood": "blood sacrifice"}
## Bless and Condemn judge what the creature did in the last JUDGE_SECONDS.
const JUDGE_SECONDS := 30.0
## How often, in a fight, the creature thinks about running from it.
const FLEE_CHECK_SECONDS := 5.0
const KNOW_COLOR := Color(0.6, 0.85, 1.0)

var creature: Creature
var knowledge := {}
var behavior := {}
## What it last did (an action category: see ActionTable), the conditions
## that held, and when.
var last_action := ""
var last_flags: Array = []
var last_action_time := -1000.0
## Where the player last left the creature. It never strays far from here.
var home := Vector3.ZERO

var _ready_at := {}
## action -> when it was last blessed or condemned.
var _judged_at := {}
## The fetching job under way: {"kind", "action", "node", "stage"}, or empty.
var _task := {}
var _think_timer := 1.0
var _idle_timer := 8.0
var _flee_timer := FLEE_CHECK_SECONDS
var _away := false


## Every action the creature can be blessed or condemned for.
static func all_actions() -> Array[String]:
	return ActionTable.all()


## The sentence for an action, as Bless and Condemn show it.
static func describe(action: String) -> String:
	return Texts.line("action_" + action)


func _ready() -> void:
	creature = get_parent() as Creature
	for id: String in SPELLS + HARVESTS:
		knowledge[id] = 0.0
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


func _learn(id: String, points: float, saw: String, fill: Dictionary) -> void:
	if learned(id):
		return
	knowledge[id] += points
	fill["have"] = int(minf(knowledge[id], needed(id)))
	fill["need"] = int(needed(id))
	creature.say(Texts.line(saw, fill), KNOW_COLOR)
	if learned(id):
		creature.say(Texts.line("learned_" + id), Color(1.0, 0.9, 0.4))


# --- Behaviour ------------------------------------------------------------------

## The creature's affinity for doing `category` under `flags` (the
## conditions that hold: see ActionTable): the affinities of the category
## and of each of those conditions in it, added up.
func score(category: String, flags: Array = []) -> float:
	var total := 0.0
	for action in applicable(category, flags):
		total += behavior.get(action, 0.0)
	return total


## How much the creature leans towards `category` under `flags`: 1 at an
## affinity of 0, growing steeply with a higher one and shrinking towards
## (but never reaching) nothing with a lower one. Choices between things
## to do are made at random, in proportion to these.
func weight(category: String, flags: Array = []) -> float:
	return exp(clampf(score(category, flags), -300.0, 300.0) / maxf(Balance.num("affinity_spread"), 1.0))


## Yes or no to doing `category` now, at random: an even chance at an
## affinity of 0, likelier the higher it is, never quite certain either way.
func likely(category: String, flags: Array = []) -> bool:
	var w := weight(category, flags)
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


## The actions in `category`'s column whose condition holds under `flags`.
func applicable(category: String, flags: Array = []) -> Array[String]:
	var out: Array[String] = []
	for action in ActionTable.column(category):
		var condition := ActionTable.condition(category, action)
		if condition == "" or flags.has(condition):
			out.append(action)
	return out


## Records what the creature just did (`category`, under the conditions in
## `flags`) for Bless and Condemn to judge, and floats `text` up from its
## head.
func did(category: String, flags: Array = [], text := "") -> void:
	last_action = category
	last_flags = flags.duplicate()
	last_action_time = Game.now
	if text != "":
		creature.say(text)


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
	for action in applicable(last_action, last_flags):
		if cooling(action) <= 0.0:
			return action
	return ""


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
		var soonest := INF
		for action in applicable(last_action, last_flags):
			soonest = minf(soonest, cooling(action))
		return Texts.line("judge_cooling", {"creature": who, "action": describe(last_action), "seconds": ceili(soonest)})
	var points := Balance.num("bless_points") if sign_value > 0 else -Balance.num("condemn_points")
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


## The conditions that hold now for fetching `kind`: "highest" or "lowest"
## (of lumber, stone and food in store), "none", "plenty", "battle", and
## "day" or "night".
func gather_flags(kind: String) -> Array[String]:
	var flags: Array[String] = []
	var village := Game.village
	if is_instance_valid(village):
		var have := village.amount(kind)
		var most := true
		var least := true
		for other: String in HARVESTS:
			if other != kind:
				most = most and have >= village.amount(other)
				least = least and have <= village.amount(other)
		if most:
			flags.append("highest")
		if least:
			flags.append("lowest")
		if have <= 0:
			flags.append("none")
		if have > PLENTY:
			flags.append("plenty")
	if _battle_raging():
		flags.append("battle")
	flags.append("night" if Game.day_cycle != null and is_instance_valid(Game.day_cycle) and Game.day_cycle.is_night() else "day")
	return flags


## True while the creature fights, goblins raid, or goblins prowl the village.
func _battle_raging() -> bool:
	if creature.is_fighting() and not creature.is_fleeing():
		return true
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.is_alive() and (g.raiding or g.threatens_village()):
			return true
	for node in get_tree().get_nodes_in_group("balrogs"):
		if (node as Creature).is_threat():
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


## In a fight, now and then: run from it, the likelier the more hurt it is
## and the higher its affinity for running from battle (as hurt as it is).
func _consider_fleeing() -> bool:
	if creature.is_fleeing() or not _enemy_close():
		return false
	var hurt := health_word()
	var chance := Balance.num("flee_chance_" + hurt) * weight("flee", [hurt])
	if randf() >= chance or not creature.run_from_battle():
		return false
	_drop_task()
	_away = true
	did("flee", [hurt], Texts.line("fled"))
	return true


## True with a goblin close enough to fight.
func _enemy_close() -> bool:
	var near := Creature.REACH * creature.size + 6.0
	for node in get_tree().get_nodes_in_group("goblins"):
		var g := node as Villager
		if g.is_alive() and g.state != Villager.State.HELD and creature._flat(g.global_position, creature.global_position) < near:
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
	if creature.is_fighting() or not _task.is_empty():
		return
	if creature.has_target and not creature.is_auto():
		return
	_idle_timer -= 1.0
	if _idle_timer <= 0.0 and not creature.has_target:
		_choose_idle()


## Left to itself: come home if it has strayed; otherwise pick at random,
## weighted by its affinities, between a short wander, exploring (now and
## then: Balance "explore_weight" of the weight it would have) and
## fetching what it has learned to fetch.
func _choose_idle() -> void:
	_idle_timer = randf_range(6.0, 12.0)
	var from_home := Vector2(creature.global_position.x - home.x, creature.global_position.z - home.z).length()
	if _away or from_home > 5.0:
		_away = false
		creature.auto_move(home)
		return
	var options := {"wander": Balance.num("wander_weight"), "explore": Balance.num("explore_weight") * weight("explore")}
	var flags := {}
	if creature.size >= 0.3:
		for kind: String in HARVESTS:
			if learned(kind) and _harvest_target(kind) != null:
				flags[kind] = gather_flags(kind)
				options[kind] = weight(kind, flags[kind])
	var choice: String = pick(options)
	match choice:
		"wander":
			_wander()
		"explore":
			if not _explore():
				_wander()
		_:
			_task = {"kind": choice, "flags": flags[choice], "node": _harvest_target(choice), "stage": "go"}


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
			did("explore")
			return true
	return false


# --- Spells ---------------------------------------------------------------------

## The conditions casting `id` comes under: rain is cast on a fire, or on
## growing wheat ("water").
func _cast_flags(id: String) -> Array:
	match id:
		"rain":
			return ["fire"]
		"water":
			return ["crops"]
	return []


func _try_spells() -> bool:
	if not is_instance_valid(Game.village) or not Game.village.founded:
		return false
	if creature.flying or creature.running:
		return false
	for id: String in CASTS:
		var spell := "rain" if id == "water" else id
		if not learned(spell) or Game.now < _ready_at.get(id, 0.0) or creature.magicko < Balance.num("creature_cost_" + spell):
			continue
		if not likely(spell, _cast_flags(id)):
			continue
		var target: Variant = _spell_target(id)
		if target == null:
			continue
		_ready_at[id] = Game.now + Balance.num("cooldown_" + spell)
		if creature.spend_magicko(Balance.num("creature_cost_" + spell)):
			_cast(id, target)
			return true
	return false


## Where to cast `id` right now, or null if there is no call for it.
func _spell_target(id: String) -> Variant:
	var village := Game.village
	var tree := get_tree()
	match id:
		"fireball":
			# A knot of enemies, away from the village's buildings.
			return _enemy_cluster(Fireball.BLAST_RADIUS * 0.7, 3, 10.0, 70.0, true)
		"roots":
			# A bigger crowd of raiders, with none of our own people among them.
			return _enemy_cluster(RootPatch.RADIUS, 4, RootPatch.RADIUS + 4.0, 70.0, false)
		"lightning":
			# A crowd of enemies with none of our own people among them.
			return _enemy_cluster(Balance.num("lightning_jump_range"), 3, Balance.num("lightning_jump_range") + 3.0, 70.0, false)
		"rain":
			for node in tree.get_nodes_in_group("player_buildings"):
				if (node as Destructible).burning:
					return (node as Node3D).global_position
			for f in Game.fire._fires:
				var p: Vector3 = f.pos
				if p.distance_to(village.center) < 45.0:
					return p
		"water":
			# Growing wheat that is not wet already.
			for node in tree.get_nodes_in_group("fields"):
				var field := node as CropField
				if field.stage == CropField.Stage.GROWING and not field.is_wet() and not Game.fire.is_wet(field.global_position):
					return field.global_position
		"blood":
			# Only when magicko has run dry and there are people to spare.
			if village.amount("magicko") < 10 and village.population() >= 12 and not village.blood_active():
				return village.center
	return null


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


func _cast(id: String, target: Vector3) -> void:
	creature.watch(target)
	match id:
		"fireball":
			var fb := Fireball.new()
			fb.friendly = Balance.num("creature_friendly_fire")
			Game.world_root.add_child(fb)
			fb.launch(creature.mouth_position(), target)
			did(id, [], Texts.line("cast_fireball"))
		"rain":
			var cloud := RainCloud.new()
			Game.world_root.add_child(cloud)
			cloud.cast(target)
			did("rain", ["fire"], Texts.line("cast_rain"))
		"water":
			var shower := RainCloud.new()
			Game.world_root.add_child(shower)
			shower.cast(target)
			did("rain", ["crops"], Texts.line("cast_water"))
		"roots":
			var patch := RootPatch.new()
			Game.world_root.add_child(patch)
			patch.cast(target)
			did(id, [], Texts.line("cast_roots"))
		"lightning":
			ChainLightning.cast(target, Balance.num("creature_friendly_fire"))
			did(id, [], Texts.line("cast_lightning"))
		"blood":
			if Game.village.sacrifice_someone():
				did(id, [], Texts.line("cast_blood"))


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
		if n.global_position.distance_to(village.center) > PlayerVillage.WORK_REACH:
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
	var task_flags: Array = _task.get("flags", [])
	creature.drop_load()
	Game.effects.spawn_dust(drop, 2.0 * creature.size)
	_task = {}
	_away = true
	_idle_timer = randf_range(3.0, 6.0)
	did(kind, task_flags, Texts.line("brought_" + kind, {"amount": roundi(amount)}))


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
