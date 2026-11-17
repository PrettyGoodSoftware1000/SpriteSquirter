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
## Rain is two things to do: putting out fires ("rain") and watering
## growing wheat ("water"). Bless and Curse are never learned.
##
## Behaviour: every action has a keenness from -100 (never) to 100
## (always), starting at Balance "behavior_start". The Bless spell raises
## it for whatever the creature did last, and Curse lowers it, once for
## each thing the creature does. Past 50 (or -50) each blessing (or curse)
## counts for less and less, so 100 and -100 are never quite reached. The
## keenness decides between stomping, throwing and eating in a fight,
## whether a spell is cast, whether it runs from a fight, how often it goes
## exploring, and what it does with itself when left alone: wander a little
## way from where it was last sent and come back, or fetch something.
##
## Some actions depend on what was going on. Fetching lumber, stone or food
## is one action when a battle is on, another when the village has none of
## it, another when it has plenty (over PLENTY), and otherwise one by day
## and one by night. Running from battle is one action for each of four
## states of health, and so is the tortoise's hiding in its shell.
## Exploring is a long trip away from where it was sent: the keener it is,
## the more often it goes. (The squirrel's running and the raven's flying
## are not things to judge.) Texts "action_<name>" says what each one is.
##
## All the amounts come from balancing.txt (see Balance).

const SPELLS := ["fireball", "rain", "roots", "lightning", "blood"]
const HARVESTS := ["lumber", "stone", "food"]
const FIGHTS := ["stomp", "throw", "eat"]
## What was going on while the creature fetched something (see _context()).
const CONTEXTS := ["battle", "none", "plenty", "day", "night"]
## Running from battle, by how hurt the creature was (see _flee_action()).
const FLEES := ["flee_unharmed", "flee_slightly", "flee_badly", "flee_near_death"]
## The tortoise hiding in its shell, by how hurt it was.
const SHELLS := ["shell_unharmed", "shell_slightly", "shell_badly", "shell_near_death"]
## What it may cast, in the order it thinks of them: fighting first.
## ("water" is the rain spell, cast on growing wheat.)
const CASTS := ["fireball", "lightning", "roots", "rain", "blood", "water"]
## More than this of a resource in store is plenty.
const PLENTY := 200.0
const SPELL_NAMES := {"fireball": "fireball", "rain": "rain", "roots": "roots", "lightning": "chain lightning", "blood": "blood sacrifice"}
## Bless and Curse judge what the creature did in the last JUDGE_SECONDS.
const JUDGE_SECONDS := 30.0
## How often, in a fight, the creature thinks about running from it.
const FLEE_CHECK_SECONDS := 5.0
const KNOW_COLOR := Color(0.6, 0.85, 1.0)

var creature: Creature
var knowledge := {}
var behavior := {}
var last_action := ""
var last_action_time := -1000.0
## True once the last action has been blessed or cursed: each thing the
## creature does can be judged only once.
var last_judged := false
## Where the player last left the creature. It never strays far from here.
var home := Vector3.ZERO

var _ready_at := {}
## The fetching job under way: {"kind", "action", "node", "stage"}, or empty.
var _task := {}
var _think_timer := 1.0
var _idle_timer := 8.0
var _flee_timer := FLEE_CHECK_SECONDS
var _away := false


## Every action the creature can be blessed or cursed for.
static func all_actions() -> Array[String]:
	var out: Array[String] = []
	for id: String in FIGHTS + SPELLS + FLEES + SHELLS + ["explore", "water"]:
		out.append(id)
	for kind: String in HARVESTS:
		for context: String in CONTEXTS:
			out.append(kind + "_" + context)
	return out


## The sentence for an action, as Bless and Curse show it.
static func describe(action: String) -> String:
	return Texts.line("action_" + action)


func _ready() -> void:
	creature = get_parent() as Creature
	for id: String in SPELLS + HARVESTS:
		knowledge[id] = 0.0
	for action in all_actions():
		behavior[action] = clampf(Balance.num("behavior_start"), -100.0, 100.0)
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

## How keen the creature is on `action`, from 0 (never) to 100 (always):
## its keenness of -100 to 100 moved onto that scale.
func weight(action: String) -> float:
	return (behavior.get(action, 0.0) + 100.0) * 0.5


## Records what the creature just did, for Bless and Curse to judge, and
## floats `text` up from its head.
func did(action: String, text := "") -> void:
	last_action = action
	last_action_time = Game.now
	last_judged = false
	if text != "":
		creature.say(text)


## True if Bless or Curse would have something to judge.
func can_judge() -> bool:
	return last_action != "" and Game.now - last_action_time <= JUDGE_SECONDS and not last_judged


## Moves a keenness by `points`: in full between -50 and 50, and for less
## and less the further past them it goes.
static func nudge(value: float, points: float) -> float:
	const STEPS := 20
	var v := value
	for k in STEPS:
		var p := points / STEPS
		if absf(v) > 50.0 and signf(p) == signf(v):
			p *= (100.0 - absf(v)) / 50.0
		v = clampf(v + p, -100.0, 100.0)
	return v


## Bless (sign +1) or Curse (sign -1). Returns what to tell the player.
func judge(sign_value: int) -> String:
	if last_action == "" or Game.now - last_action_time > JUDGE_SECONDS:
		creature.say(Texts.line("creature_confused"), Color(0.8, 0.8, 0.8))
		return Texts.line("judge_nothing", {"creature": creature.species_name().to_lower(), "seconds": int(JUDGE_SECONDS)})
	if last_judged:
		return Texts.line("judge_judged", {"action": describe(last_action), "ago": int(Game.now - last_action_time)})
	var points := Balance.num("bless_points") if sign_value > 0 else -Balance.num("curse_points")
	behavior[last_action] = nudge(behavior.get(last_action, 0.0), points)
	last_judged = true
	var value := roundi(behavior[last_action])
	creature.say(Texts.line("creature_blessed" if sign_value > 0 else "creature_cursed", {"value": value}),
		Color(1.0, 0.9, 0.3) if sign_value > 0 else Color(1.0, 0.25, 0.2))
	return Texts.line("bless_result" if sign_value > 0 else "curse_result", {"action": describe(last_action), "value": value})


## The player sent the creature somewhere: that is its new home.
func player_moved(pos: Vector3) -> void:
	home = pos
	_drop_task()
	_away = false
	_idle_timer = randf_range(8.0, 14.0)


## What is going on, as it matters to fetching `kind`: a battle, none of it
## in store, plenty of it, or else day or night.
func _context(kind: String) -> String:
	if _battle_raging():
		return "battle"
	var village := Game.village
	if is_instance_valid(village):
		var have := village.amount(kind)
		if have <= 0:
			return "none"
		if have > PLENTY:
			return "plenty"
	return "night" if Game.day_cycle != null and is_instance_valid(Game.day_cycle) and Game.day_cycle.is_night() else "day"


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


## The flee action for how hurt the creature is now.
func _flee_action() -> String:
	return "flee_" + health_word()


## In a fight, now and then: run from it, as keen as it is.
func _consider_fleeing() -> bool:
	if creature.is_fleeing() or not _enemy_close():
		return false
	var action := _flee_action()
	var chance := Balance.num("flee_chance_" + action.trim_prefix("flee_")) * weight(action) / 50.0
	if randf() >= chance or not creature.run_from_battle():
		return false
	_drop_task()
	_away = true
	did(action, Texts.line("fled"))
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


## Left to itself: come home if it has strayed; now and then go exploring
## (as keen as it is on that); otherwise wander a little way or fetch
## something, whichever it is keenest on.
func _choose_idle() -> void:
	_idle_timer = randf_range(6.0, 12.0)
	var from_home := Vector2(creature.global_position.x - home.x, creature.global_position.z - home.z).length()
	if _away or from_home > 5.0:
		_away = false
		creature.auto_move(home)
		return
	if randf() < Balance.num("explore_chance") * weight("explore") / 50.0 and _explore():
		return
	# (A short wander is not keenly sought: anything it has learned to
	# fetch comes first, as keen as it is on that.)
	var options := {"wander": 20.0}
	var actions := {}
	if creature.size >= 0.3:
		for kind: String in HARVESTS:
			var action: String = kind + "_" + _context(kind)
			if learned(kind) and weight(action) > 0.0 and _harvest_target(kind) != null:
				options[kind] = weight(action)
				actions[kind] = action
	var total := 0.0
	for key: String in options:
		total += options[key]
	var roll := randf() * total
	var choice := "wander"
	for key: String in options:
		roll -= options[key]
		if roll <= 0.0:
			choice = key
			break
	if choice == "wander":
		_wander()
	else:
		_task = {"kind": choice, "action": actions[choice], "node": _harvest_target(choice), "stage": "go"}


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

func _try_spells() -> bool:
	if not is_instance_valid(Game.village) or not Game.village.founded:
		return false
	if creature.flying or creature.running:
		return false
	for id: String in CASTS:
		var spell := "rain" if id == "water" else id
		if not learned(spell) or Game.now < _ready_at.get(id, 0.0) or creature.magicko < Balance.num("creature_cost_" + spell):
			continue
		if randf() * 100.0 >= weight(id):
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
			did(id, Texts.line("cast_fireball"))
		"rain":
			var cloud := RainCloud.new()
			Game.world_root.add_child(cloud)
			cloud.cast(target)
			did(id, Texts.line("cast_rain"))
		"water":
			var shower := RainCloud.new()
			Game.world_root.add_child(shower)
			shower.cast(target)
			did(id, Texts.line("cast_water"))
		"roots":
			var patch := RootPatch.new()
			Game.world_root.add_child(patch)
			patch.cast(target)
			did(id, Texts.line("cast_roots"))
		"lightning":
			ChainLightning.cast(target, Balance.num("creature_friendly_fire"))
			did(id, Texts.line("cast_lightning"))
		"blood":
			if Game.village.sacrifice_someone():
				did(id, Texts.line("cast_blood"))


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
	var action: String = _task.get("action", kind + "_day")
	creature.drop_load()
	Game.effects.spawn_dust(drop, 2.0 * creature.size)
	_task = {}
	_away = true
	_idle_timer = randf_range(3.0, 6.0)
	did(action, Texts.line("brought_" + kind, {"amount": roundi(amount)}))


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
