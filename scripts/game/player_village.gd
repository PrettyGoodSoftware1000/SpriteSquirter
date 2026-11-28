class_name PlayerVillage
extends Node
## The player's village: its resources, its people and their work.
##
## Grown-up villagers gather lumber (felling trees), stone (breaking up
## boulders) and food (foraging round the village, or sowing and reaping
## wheat fields) at the rates set in Game.settings, in units per worker per
## minute. What they gather only counts once they have carried it to the
## nearest Storehouse (or to the village centre while there is none; food
## may go to a Granary too). Each Storehouse holds Balance
## "storehouse_holds" of each of lumber, stone, food and bones, and each
## Granary "granary_holds" more food: more than that is lost. Every
## grown-up also adds a trickle of magicko, and every Shrine makes
## "animus_per_shrine" animus a minute. While a building is under
## construction up to Balance "builders_per_building" villagers work on
## it: the builders first, then unassigned workers. Each site gets its own.
##
## A new child is born every `birth_seconds` while there is housing for it
## (Homes add housing) and food in store, and grows up in Villager.GROW_SECONDS.
##
## Grown-ups are workers unless the player asks for warriors or wizards
## (the jobs panel). Each Town guard trains one warrior at a time, taking
## Balance "warrior_training_seconds", up to WARRIORS_PER_GUARD; each
## Wizardry tower trains one wizard at a time, taking
## "wizard_training_seconds", up to MAGES_PER_TOWER. (The dev menu's
## training time multiplies all the training times.) Buildings train side
## by side. A warrior or wizard sent back to work must train from the start
## to return. Recruits come from the unassigned workers, so no job's count
## can go up unless one of them is free (free_workers()).
##
## A Necromancer tower trains wizards on into necromancers
## ("necromancers_per_tower", "necromancer_training_seconds"), who raise the
## dead as skeletons. Everyone who dies, villager or goblin, leaves the
## village a few bones (Villager._die).
##
## A Blacksmith lets the village research one thing at a time from
## Research.ITEMS: sharper swords, bows (archers: ARCHERS_PER_GUARD per Town
## guard), wheelbarrows (bigger loads), and three tiers of tools for food,
## stone and lumber (Balance "tool_tier_bonus" faster each). A Wizardry
## tower researches the spells and Overcast, and a Necromancer tower the
## Blood Sacrifice upgrade.
##
## A Windmill (one or more, standing) adds Balance "windmill_food_rate" to
## the food rate per worker (see food_rate()).
##
## Everyone eats: villagers FOOD_PER_VILLAGER a minute, warriors
## FOOD_PER_WARRIOR, archers FOOD_PER_ARCHER and wizards FOOD_PER_WIZARD.
## The creature eats too: Game.settings.creature_food a minute when full
## grown, and in proportion to its size before that (and only Balance
## "creature_young_appetite" of that while it is under half grown). With no food, no children
## are born; after STARVE_AFTER seconds without food, villagers starve,
## Game.settings.starve_per_minute of them a minute (the dev menu's
## Starvation deaths), until there is food again.

const RESOURCES := ["lumber", "stone", "food", "bones", "animus", "magicko", "storm_essence"]
const START_RESOURCES := {"lumber": 100.0, "stone": 100.0, "food": 100.0, "bones": 0.0, "animus": 0.0, "magicko": 30.0, "storm_essence": 0.0}
## What the Storehouses (and, for food, the Granaries) hold.
const STORED := ["lumber", "stone", "food", "bones"]
const HOME_RADIUS := 16.0
## Every grown-up turns out to fight a raider this close to the village
## centre, and any goblin at all (raid or no raid) within INTRUDER_RADIUS.
const DEFEND_RADIUS := 50.0
const INTRUDER_RADIUS := 25.0
## How far workers walk to reach trees and rocks.
const WORK_REACH := 65.0
const MAX_PER_TARGET := 2
const TREE_WOOD := 30.0
const BUSH_WOOD := 10.0
const WARRIORS_PER_GUARD := 4
## (Archers are trained at Lumber mills since 0.62: Balance "archers_per_mill".)
const ARCHERS_PER_MILL := 4
## (Wizards are called Mages in the game since 0.61; the code still calls
## them wizards, and so do balancing.txt's names.)
const MAGES_PER_TOWER := 4
## Magicko each wizard makes per minute.
## Magicko a wizard makes a minute (5 every 2 minutes): Balance "wizard_magicko".
## Food eaten per minute.
const FOOD_PER_VILLAGER := 1.0
const FOOD_PER_WARRIOR := 3.0
const FOOD_PER_WIZARD := 2.0
const FOOD_PER_ARCHER := 2.0
const FOOD_PER_BANSHEE := 2.0
const STARVE_AFTER := 30.0
## The most times a game "Villager stuck" is said.
const STUCK_REPORTS := 3
## role -> [building role in the catalog, per building]. The training
## times come from balancing.txt ("<role>_training_seconds"). Necromancers
## are wizards trained on at a Necromancer tower; how many a tower takes
## comes from balancing.txt too (see per_building() and train_seconds()).
const ARMY := {
	"warrior": ["guard", WARRIORS_PER_GUARD],
	"archer": ["mill", ARCHERS_PER_MILL],
	"wizard": ["wizard", MAGES_PER_TOWER],
	"necromancer": ["necro", 2],
	"fey_archer": ["mill", 0],
	"banshee": ["storm", 0],
}
## Blood Sacrifice: how long the magicko boost lasts, and how near the
## click a villager must be. How big the boost is: blood_boost().
const BLOOD_SECONDS := 30.0
const BLOOD_REACH := 9.0

signal research_done(id: String)
## A villager has tried to walk for Villager.STUCK_SECONDS and got nowhere.
signal villager_stuck(v: Villager)
## A spell has been researched at a Wizardry tower (see SpellBook).
signal spell_researched(id: String)
signal buff_researched(id: String)
## Kinky Fey Stuff: the villager and the pixie have gone in, and the fey
## are about (births twice as fast).
signal fey_birthing
## Bless or Condemn has come with the creature's growth.
signal spell_unlocked(id: String)
## Another Balance "stored_per_lesson" of `kind` has been carried in: the
## creature learns a little about harvesting it.
signal lesson(kind: String)

var founded := false
var center := Vector3.ZERO
## A neutral village (NeutralVillage) rather than the player's. Its people
## and buildings are in groups of their own; the player's are "people"
## and "player_buildings".
var neutral := false
var people_group := "people"
var buildings_group := "player_buildings"
## The centres of the neutral villages the player has taken over: their
## buildings and people are the player's now, and so is the ground round
## them (in_territory()).
var taken_centres: Array[Vector3] = []
var resources := {}
## Seconds towards the next birth.
var birth_progress := 0.0

## How many warriors and wizards the player asked for.
var wanted := {"warrior": 0, "archer": 0, "wizard": 0, "necromancer": 0, "fey_archer": 0, "banshee": 0}
## Storm Spire -> when (Game.now) it may strike with chain lightning again.
var _spire_ready := {}
## Kinky Fey Stuff: until then (Game.now) births come twice as fast and
## every child is fey; and the villagers away with a pixie, each ->
## {"t": seconds away, "pixie": its pixie}.
var fey_until := 0.0
var _trysts := {}
## Finished research: id -> true.
var researched := {}
## The research under way at the Blacksmiths ("smith"), the Wizardry
## towers ("wizard") and the Necromancer towers ("necro"): each a list of
## {"id": ..., "t": seconds done}, as many at once as there are buildings
## of that kind.
var research_jobs := {"smith": [], "wizard": [], "necro": [], "mill": []}
## Spells researched at the Wizardry tower: id -> true.
var spells_known := {}
## The spell bar: each slot's spell id, or "" (0-9 the first row, cast with
## the number keys; 10-19 the second, with Ctrl; 20-29 the third, with
## Shift). A spell learned goes where the player had it last game
## (SpellLayout), or else in the last spot, after the others.
var spell_slots: Array[String] = []
## The spells being researched at the Wizardry towers: a list of
## {"id": ..., "t": seconds done}, one for each tower at most.
var spell_jobs: Array = []
## Creature buffs researched at the Shrines (BuffBook): id -> true, and the
## ones being researched (they share the Shrines with the spells: one
## thing for each Shrine at a time).
var buffs_known := {}
var buff_jobs: Array = []
## True once Wheelbarrows are researched: loads three times as big.
var barrows := false
## How many villagers the player has set to each job (Villager.pin): the
## lumberjacks, miners, farmers and builders. Everyone else is an
## unassigned worker, who helps on building sites when the builders are too
## few, and otherwise, each time it brings a load home, goes after whatever
## the village has least of: lumber, stone or food (reaping ripe wheat;
## only farmers sow). Farmers reap before they sow, every field gets a
## farmer before any field gets a second, and everyone takes what they
## gathered to the nearest place that stores it.
var quota := {"lumber": 0, "stone": 0, "food": 0, "build": 0}
## How many workers are on each gathering job (food includes the farmers).
var gatherers := {"lumber": 0, "stone": 0, "food": 0}

var _stored := {}
## Each resource's income so far (what came in, less what is eaten as it
## goes: see _flow_add), sampled once a second for the last minute.
var _history := {}
## Each resource's income so far. Paying for buildings, research and spells
## does not count: only what comes in, and food eaten all the time.
var _flow := {}
var _history_timer := 0.0
## Seconds with no food, and towards the next death from hunger.
var hungry_for := 0.0
## Magicko comes in blood_boost() times as fast until Game.now passes this.
var blood_until := 0.0

var _assign_timer := 0.0
var _army_timer := 0.0
## Towards the next sapling (Game.settings.sapling_rate a minute), and how
## long each villager planting one has been at it.
var _plant_due := 0.0
var _planting := {}
var _starve_timer := 0.0
## How many times a villager getting stuck has been said.
var _stuck_reports := 0
## When the out-of-food warning last floated up over the Storehouse.
var _food_warned_at := -INF
## Training building -> {"v": the trainee, "t": seconds trained, "role": ...}
var _training := {}


func _ready() -> void:
	for res in RESOURCES:
		resources[res] = START_RESOURCES[res]
		# (The owner's starting amounts, from balancing.txt.)
		if Balance.DEFAULTS.has("start_" + res):
			resources[res] = Balance.num("start_" + res)


## Starts the village at `pos`. In a random world, `site` is the village
## site there: its buildings and villagers join the player. Otherwise the
## village starts with a few villagers and no buildings.
func found(pos: Vector3, site := -1) -> void:
	founded = true
	center = pos
	var tree := get_tree()
	if site >= 0:
		for node in tree.get_nodes_in_group("buildings"):
			if node.get_meta("site", -1) == site:
				adopt(node)
		for node in tree.get_nodes_in_group("villagers"):
			var v := node as Villager
			if v.get_meta("site", -1) == site and not v.goblin:
				join(v)
				v.home = center
				v.home_radius = HOME_RADIUS
	_raise_first_storehouse()
	if people().is_empty():
		Game.terrain.add_bare(center, 9.0, 0.7)
		for k in start_people():
			spawn_person(center, 6.0)
		for v in people():
			v.home_radius = HOME_RADIUS


## Makes villager `v` (one already on the island) one of the village's people.
func join(v: Villager) -> void:
	v.owned = true
	v.worshiper = true
	v.add_to_group(people_group)


## Makes building `b` one of the village's.
func adopt(b: Node) -> void:
	b.add_to_group(buildings_group)
	if neutral:
		b.add_to_group("neutral_buildings")
		b.set_meta("village", self)


## How many villagers the village starts with: Balance "start_villagers".
func start_people() -> int:
	return roundi(Balance.num("start_villagers"))


## One of the village's own people (a newborn if `child`), near `at`.
func spawn_person(at: Vector3, radius: float, child := false, fey := false) -> Villager:
	return WorldPopulator.spawn_villager(Game.world_root, Game.terrain, at, radius, false, true, child, fey)


## The village's first Storehouse is free and stands on the start location
## (or as close to it as the buildings already there allow).
func _raise_first_storehouse() -> void:
	var terrain := Game.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.world_seed + 7
	var store := BuildingFactory.create(BuildingCatalog.kind_for_role("store", "store"), rng)
	var spot := center
	var found_spot := false
	for ring in 16:
		for k in maxi(1, ring * 6):
			var a := TAU * k / maxf(ring * 6.0, 1.0)
			var p := center + Vector3(cos(a), 0.0, sin(a)) * ring * 2.5
			if not terrain.is_inside(p.x, p.z) or not terrain.is_dry(p.x, p.z):
				continue
			var clear := true
			for node in get_tree().get_nodes_in_group("buildings"):
				var b := node as Destructible
				if Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < b.footprint + store.footprint + 1.0:
					clear = false
					break
			if clear:
				spot = p
				found_spot = true
				break
		if found_spot:
			break
	var h := maxf(terrain.average_height(spot, store.footprint), Terrain.WATER_LEVEL + 0.5)
	terrain.apply_brush(Vector3(spot.x, h, spot.z), store.footprint + 3.0, Terrain.Brush.FLATTEN, 1.0, h, store.footprint / (store.footprint + 3.0))
	for node in get_tree().get_nodes_in_group("trees"):
		var t := node as Destructible
		if Vector2(t.global_position.x - spot.x, t.global_position.z - spot.z).length() < store.footprint + 1.5:
			t.fell()
	Game.world_root.add_child(store)
	store.global_position = Vector3(spot.x, h, spot.z)
	store.rotation.y = rng.randf() * TAU
	adopt(store)
	terrain.add_bare(store.global_position, store.footprint + 1.5, 0.9)


## A worker carries `amount` of `kind` into the store. Every so much stored
## is a lesson for the creature.
func store(kind: String, amount: float) -> void:
	give(kind, amount)
	var per := maxf(Balance.num("stored_per_lesson"), 1.0)
	var before: float = _stored.get(kind, 0.0)
	_stored[kind] = before + amount
	if not neutral and quota.has(kind) and floorf(_stored[kind] / per) > floorf(before / per):
		lesson.emit(kind)


## Sets one of the unassigned workers to a job ("lumber", "stone", "food"
## or "build"), or with a `change` of -1 sends one back to the unassigned.
## It happens at once. Never takes warriors, archers or wizards.
func change_quota(kind: String, change: int) -> void:
	if change > 0 and free_workers() <= 0:
		return
	var chosen: Villager = null
	for v in people():
		if not v.can_work() or v.job == "train":
			continue
		if change < 0 and v.pin == kind:
			chosen = v
			break
		if change > 0 and v.pin == "":
			# Someone already doing it, if there is one.
			if chosen == null or v.job == kind or (kind == "food" and v.job == "farm"):
				chosen = v
			if v.job == kind:
				break
	if chosen:
		chosen.pin = kind if change > 0 else ""
		# Given a job, a worker drops whatever it was doing (building too)
		# at once and goes to it.
		if (change > 0 and chosen.job != kind and not (kind == "food" and chosen.job == "farm")) or (change < 0 and chosen.job != "build"):
			chosen.clear_job()
	_assign_jobs()


## Workers the player has not set to any job.
func unassigned() -> int:
	var n := 0
	for v in people():
		if v.can_work() and v.job != "train" and v.pin == "":
			n += 1
	return n


## Unassigned workers not already promised to a warrior, archer or wizard
## the player asked for. A job's count only goes up while this is above 0.
func free_workers() -> int:
	var promised := 0
	for role: String in ["warrior", "archer", "wizard"]:
		promised += maxi(0, wanted[role] - count(role) - training_progress(role).size())
	return maxi(0, unassigned() - promised)


## Wizards that could still be trained on into necromancers.
func free_wizards() -> int:
	var n := 0
	for v in people():
		if v.wizard and not v.necromancer and v.job != "train" and v.is_alive():
			n += 1
	var promised := maxi(0, wanted.necromancer - count("necromancer") - training_progress("necromancer").size())
	return maxi(0, n - promised)


## A villager is stuck (see Villager._watch_stuck()): said at most
## STUCK_REPORTS times a game.
func report_stuck(v: Villager) -> void:
	if neutral or _stuck_reports >= STUCK_REPORTS:
		return
	_stuck_reports += 1
	villager_stuck.emit(v)


## Blood Sacrifice cast by the creature: any one of the workers.
func sacrifice_someone() -> bool:
	var all := people()
	if all.is_empty():
		return false
	return sacrifice(all[randi() % all.size()].global_position)


## True if `node` (a wheat field, a building site) is this village's: the
## player's have no "village" meta, a neutral village's carry it.
func owns(node: Node) -> bool:
	var of: Variant = node.get_meta("village") if node.has_meta("village") else null
	return (of == self) if neutral else (of == null or not is_instance_valid(of))


func fields() -> Array:
	return get_tree().get_nodes_in_group("fields").filter(owns)


func construction_sites() -> Array:
	return get_tree().get_nodes_in_group("construction_sites").filter(owns)


func people() -> Array[Villager]:
	var out: Array[Villager] = []
	for node in get_tree().get_nodes_in_group(people_group):
		out.append(node as Villager)
	return out


func population() -> int:
	return get_tree().get_nodes_in_group(people_group).size()


func adults() -> int:
	var count := 0
	for v in people():
		if v.is_adult():
			count += 1
	return count


func housing() -> int:
	var total := BuildingCatalog.BASE_HOUSING
	for node in get_tree().get_nodes_in_group(buildings_group):
		total += BuildingCatalog.housing(node.get_meta("kind", ""))
	return total


func amount(res: String) -> int:
	return floori(resources.get(res, 0.0))


func blood_active() -> bool:
	return Game.now < blood_until


## How many times as fast magicko comes in while Blood Sacrifice runs:
## Balance "blood_sacrifice_boost", or "blood_sacrifice_upgraded_boost"
## once the Necromancer tower's upgrade is researched.
func blood_boost() -> float:
	return Balance.num("blood_sacrifice_upgraded_boost" if has_research("blood_x3") else "blood_sacrifice_boost")


## Blood Sacrifice: kills the villager of yours nearest to `pos` and speeds
## up the magicko income (blood_boost()) for BLOOD_SECONDS. A second one
## while it runs does not stack: the time starts again, no more. False if
## nobody is near enough.
func sacrifice(pos: Vector3) -> bool:
	var victim: Villager = null
	var best := BLOOD_REACH
	for v in people():
		var d := Vector2(v.global_position.x - pos.x, v.global_position.z - pos.z).length()
		if d < best:
			best = d
			victim = v
	if victim == null:
		return false
	victim.sacrifice()
	blood_until = Game.now + BLOOD_SECONDS
	return true


func soldiers() -> int:
	return _in_group("soldiers")


func wizards() -> int:
	return _in_group("wizards")


func archers() -> int:
	return _in_group("archers")


## How many of the village's people are in `group` ("soldiers", "wizards"...).
func _in_group(group: String) -> int:
	var n := 0
	for v in people():
		if v.is_in_group(group):
			n += 1
	return n


func count(role: String) -> int:
	match role:
		"warrior":
			return soldiers()
		"archer":
			return archers()
		"necromancer":
			return _in_group("necromancers")
		"fey_archer":
			return _in_group("fey_archers")
		"banshee":
			return _in_group("banshees")
	# (Mages promised to become necromancers count as necromancers already.)
	return wizards() - clampi(wanted.necromancer - _in_group("necromancers"), 0, wizards())


## The village's grown-up fey (workers and Fey Archers alike).
func fey_adults() -> int:
	var n := 0
	for v in people():
		if v.fey and not v.child:
			n += 1
	return n


## How many of `role` one of its buildings can keep, and how long each
## takes to train.
func per_building(role: String) -> int:
	if role == "banshee":
		return roundi(Balance.num("banshees_per_spire"))
	if role == "archer":
		return roundi(Balance.num("archers_per_mill"))
	return roundi(Balance.num("necromancers_per_tower")) if role == "necromancer" else ARMY[role][1]


func train_seconds(role: String) -> float:
	return Balance.num(role + "_training_seconds") * maxf(Game.settings.training_time, 0.01)


## The most warriors (or archers, or wizards) the village's buildings can
## train. (Archers and Fey Archers: at Lumber mills.)
func max_count(role: String) -> int:
	if role == "fey_archer":
		# As many as there are winged villagers, once archers can be trained.
		return fey_adults() if not _training_buildings(role).is_empty() else 0
	return _training_buildings(role).size() * per_building(role)


# --- Blacksmith and research ----------------------------------------------------

func has_blacksmith() -> bool:
	for node in get_tree().get_nodes_in_group(buildings_group):
		if BuildingCatalog.role(node.get_meta("kind", "")) == "smith":
			return true
	return false


func has_research(id: String) -> bool:
	return researched.has(id)


## True while one of the village's buildings with `role` stands.
func has_role(role: String) -> bool:
	for node in get_tree().get_nodes_in_group(buildings_group):
		if BuildingCatalog.role(node.get_meta("kind", "")) == role and not (node as Destructible).destroyed:
			return true
	return false


## How many times faster `kind` ("food", "stone" or "lumber") is gathered
## thanks to researched tools: Balance "tool_tier_bonus" more for each tier.
func tool_bonus(kind: String) -> float:
	var tiers := 0
	for n in range(1, Research.TIERS + 1):
		if has_research("%s_%d" % [Research.TOOLS[kind], n]):
			tiers += 1
	return 1.0 + tiers * Balance.num("tool_tier_bonus")


## The research under way at `place` ("smith" or "wizard").
func researching(place: String) -> Array:
	return research_jobs[place]


## How many things `place` can research at once: one for each of its
## buildings that stands.
func research_slots(place: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(buildings_group):
		if BuildingCatalog.role(node.get_meta("kind", "")) == place and not (node as Destructible).destroyed:
			count += 1
	return count


## The research job for `id` under way ({"id", "t"}), or empty.
func research_job(id: String) -> Dictionary:
	for place: String in research_jobs:
		for job: Dictionary in research_jobs[place]:
			if job.id == id:
				return job
	return {}


## Starts researching. Returns why it can't, or "" if it began.
func start_research(id: String) -> String:
	var item := Research.find(id)
	if item.is_empty() or has_research(id):
		return "That is already researched."
	if not research_job(id).is_empty():
		return "That is being researched."
	var place: String = item.place
	if not has_role(place):
		return "Research needs a %s: build one first." % BuildingCatalog.role_name(place)
	if item.has("needs") and not has_research(item.needs):
		return "Research %s first." % Research.find(item.needs).name
	if researching(place).size() >= research_slots(place):
		return "Every %s is busy: build another to research more at once." % BuildingCatalog.role_name(place)
	var short := shortfall(item.cost)
	if short != "":
		return "Need %s more." % short
	spend(item.cost)
	researching(place).append({"id": id, "t": 0.0})
	return ""


## 0..1 for the research under way, 1 for finished research, else 0.
func research_progress(id: String) -> float:
	if has_research(id):
		return 1.0
	var job := research_job(id)
	if not job.is_empty():
		return clampf(job.t / Research.find(id).seconds, 0.0, 1.0)
	return 0.0


## Research goes on at each place, one thing for each building that stands.
func _update_research(delta: float) -> void:
	for place: String in research_jobs:
		var jobs: Array = research_jobs[place]
		var slots := research_slots(place)
		for job: Dictionary in jobs.duplicate():
			if slots <= 0:
				break
			slots -= 1
			job.t += delta
			var id: String = job.id
			if job.t < Research.find(id).seconds:
				continue
			jobs.erase(job)
			researched[id] = true
			if id == "swords":
				for v in people():
					v.sharpen()
			if id == "wheelbarrows":
				barrows = true
			research_done.emit(id)


# --- Spells researched at the Wizardry tower ------------------------------------

## True if spell `id` can be cast: it has been researched (or, for Bless
## and Condemn, has come with the creature's growth).
func knows_spell(id: String) -> bool:
	return spells_known.has(id)


## Starts researching spell `id` at a Wizardry tower. Returns why it can't,
## or "" if it began. One spell for each tower at a time, paid for up front.
func start_spell_research(id: String) -> String:
	if knows_spell(id):
		return "You know that spell already."
	if not SpellBook.needs_research(id):
		return "That spell comes as your creature grows."
	if research_slots("wizard") <= 0:
		return "Spells are researched at the %s: build one first." % BuildingCatalog.role_name("wizard")
	if not spell_job(id).is_empty():
		return "That spell is being researched."
	if spell_jobs.size() >= research_slots("wizard"):
		return "Every %s is busy: build another to research more spells at once." % BuildingCatalog.role_name("wizard")
	var cost := spell_research_cost()
	var short := shortfall(cost)
	if short != "":
		return "Need %s more." % short
	spend(cost)
	spell_jobs.append({"id": id, "t": 0.0})
	return ""


## The research of spell `id` under way ({"id", "t"}), or empty.
func spell_job(id: String) -> Dictionary:
	for job: Dictionary in spell_jobs:
		if job.id == id:
			return job
	return {}


## What the next spell costs to research (see SpellBook.research_cost()):
## spells being researched count as known.
func spell_research_cost() -> Dictionary:
	var researched := spell_jobs.size()
	for id: String in spells_known:
		if SpellBook.needs_research(id):
			researched += 1
	return SpellBook.research_cost(researched)


## 0..1 for a spell being researched, 1 for one known, else 0.
func spell_research_progress(id: String) -> float:
	if knows_spell(id):
		return 1.0
	var job := spell_job(id)
	if not job.is_empty():
		return clampf(job.t / maxf(0.01, SpellBook.research_seconds(id)), 0.0, 1.0)
	return 0.0


## Research goes on at the Wizardry towers (one spell for each that
## stands) and at the Shrines (one buff for each).
func _update_spell_research(delta: float) -> void:
	_update_buff_research(delta)
	var slots := research_slots("wizard")
	for job: Dictionary in spell_jobs.duplicate():
		if slots <= 0:
			break
		slots -= 1
		job.t += delta
		var id: String = job.id
		if job.t < SpellBook.research_seconds(id):
			continue
		spell_jobs.erase(job)
		_learn_spell(id)
		spell_researched.emit(id)


## Buff research goes on at the Shrines, one buff for each that stands.
func _update_buff_research(delta: float) -> void:
	var slots := shrines().size()
	for job: Dictionary in buff_jobs.duplicate():
		if slots <= 0:
			break
		slots -= 1
		job.t += delta
		var id: String = job.id
		if job.t < Balance.num("buff_research_seconds"):
			continue
		buff_jobs.erase(job)
		buffs_known[id] = true
		buff_researched.emit(id)


# --- Creature buffs (BuffBook), researched at the Shrines --------------------------

func knows_buff(id: String) -> bool:
	return buffs_known.has(id)


## Starts researching buff `id` at a Shrine. Returns why it can't, or "" if
## it began.
func start_buff_research(id: String) -> String:
	if BuffBook.find(id).is_empty():
		return "There is no such buff."
	if knows_buff(id):
		return "You know that buff already."
	if not buff_job(id).is_empty():
		return "That buff is being researched."
	if shrines().is_empty():
		return "Buffs are researched at the %s: build one first." % BuildingCatalog.role_name("shrine")
	if buff_jobs.size() >= shrines().size():
		return "Every %s is busy: build another to research more at once." % BuildingCatalog.role_name("shrine")
	var cost := buff_research_cost()
	var short := shortfall(cost)
	if short != "":
		return "Need %s more." % short
	spend(cost)
	buff_jobs.append({"id": id, "t": 0.0, "buff": true})
	return ""


func buff_job(id: String) -> Dictionary:
	for job: Dictionary in buff_jobs:
		if job.id == id:
			return job
	return {}


## What the next buff costs to research: Balance "buff_research_first"
## animus, and "buff_research_step" more for each one researched (or
## being researched).
func buff_research_cost() -> Dictionary:
	return BuffBook.research_cost(buffs_known.size() + buff_jobs.size())


func buff_research_progress(id: String) -> float:
	if knows_buff(id):
		return 1.0
	var job := buff_job(id)
	if not job.is_empty():
		return clampf(job.t / maxf(0.01, Balance.num("buff_research_seconds")), 0.0, 1.0)
	return 0.0


func _learn_spell(id: String) -> void:
	spells_known[id] = true
	_bar()
	if spell_slots.has(id):
		return
	var want := SpellLayout.slot_of(id)
	if want < 0 or want >= spell_slots.size() or spell_slots[want] != "":
		want = _last_spot()
	if want >= 0:
		spell_slots[want] = id
		SpellLayout.remember(spell_slots)
		# A spell put in a row the bar is not showing brings that row out.
		@warning_ignore("integer_division")
		var row := want / SpellLayout.PER_ROW
		if row >= SpellLayout.row_count():
			SpellLayout.set_rows(row + 1)


## The spell bar, made empty the first time it is asked for.
func _bar() -> Array[String]:
	if spell_slots.is_empty():
		spell_slots.resize(SpellLayout.ROWS_MOST * SpellLayout.PER_ROW)
		spell_slots.fill("")
	return spell_slots


## The last spot on the bar: the slot after the last spell on it (or the
## first empty one, if that is past the end). -1 if the bar is full.
func _last_spot() -> int:
	var last := -1
	for k in spell_slots.size():
		if spell_slots[k] != "":
			last = k
	if last + 1 < spell_slots.size():
		return last + 1
	return spell_slots.find("")


## Moves spell `id` to `slot` on the spell bar, swapping with whatever was
## there.
func move_spell(id: String, slot: int) -> void:
	_bar()
	var from := spell_slots.find(id)
	if from < 0 or slot < 0 or slot >= spell_slots.size() or slot == from:
		return
	spell_slots[from] = spell_slots[slot]
	spell_slots[slot] = id
	SpellLayout.remember(spell_slots)


## The spell in `slot` on the bar, or "".
func spell_at(slot: int) -> String:
	_bar()
	return spell_slots[slot] if slot >= 0 and slot < spell_slots.size() else ""


## Bless and Condemn come as the creature grows: each at its level (see
## SpellBook.GROWTH_SPELLS) of `level` tenths of growth paid for.
func unlock_growth_spells(level: int) -> void:
	for id: String in SpellBook.GROWTH_SPELLS:
		if level >= int(SpellBook.GROWTH_SPELLS[id]) and not spells_known.has(id):
			_learn_spell(id)
			spell_unlocked.emit(id)


# --- Kinky Fey Stuff ----------------------------------------------------------------

## The worker (unassigned, lumberjack, miner, farmer or builder) nearest
## `p`, within BLOOD_REACH, for Kinky Fey Stuff. Null if there is none.
func fey_target(p: Vector3) -> Villager:
	var best: Villager = null
	var best_d := BLOOD_REACH
	for v in people():
		if not v.can_work() or v.job == "tryst" or v.job == "train":
			continue
		var d := Vector2(v.global_position.x - p.x, v.global_position.z - p.z).length()
		if d < best_d:
			best_d = d
			best = v
	return best


## The pixie has come: villager `v` goes off with it into the village's
## nearest building, for Balance "fey_tryst_seconds".
func start_tryst(v: Villager, pixie: Node3D) -> void:
	var best: Destructible = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		if b.destroyed or b is RopeBridge:
			continue
		var d := b.global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return
	var door := v.global_position - best.global_position
	door.y = 0.0
	door = door.normalized() if door.length_squared() > 0.01 else Vector3.RIGHT
	v.clear_job()
	v.pin = ""
	v.assign_job("tryst", best.global_position + door * (best.footprint + 0.6), best)
	_trysts[v] = {"t": 0.0, "pixie": pixie}


## At the building: in they go (out of sight), and at once the fey are
## about (births come faster for Balance "fey_birth_seconds"); after the
## tryst is over out comes the villager, its eyes no longer glowing.
func _tryst(v: Villager, delta: float) -> void:
	var entry: Dictionary = _trysts.get(v, {})
	if entry.is_empty():
		v.clear_job()
		return
	if entry.t == 0.0:
		v.visible = false
		if is_instance_valid(entry.pixie):
			(entry.pixie as Node3D).queue_free()
		fey_until = Game.now + Balance.num("fey_birth_seconds")
		fey_birthing.emit()
	entry.t += delta
	if entry.t < Balance.num("fey_tryst_seconds"):
		return
	_trysts.erase(v)
	v.visible = true
	v.clear_eye_glow()
	v.clear_job()
	Game.effects.spawn_dust(v.global_position, 0.6)


## Every spell, researched at once (the dev menu).
func learn_all_spells() -> void:
	for spell in SpellBook.SPELLS:
		_learn_spell(spell.id)
	spell_jobs.clear()
	for buff in BuffBook.BUFFS:
		buffs_known[buff.id] = true
	buff_jobs.clear()


## Food the creature eats per minute: its full appetite once grown, in
## proportion to its size before that, and less again while it is young.
func creature_upkeep() -> float:
	var c := Game.creature
	if neutral or not is_instance_valid(c) or c.knocked_out:
		return 0.0
	var young := Balance.num("creature_young_appetite") if c.grown() < 0.5 else 1.0
	return Game.settings.creature_food * c.size * young


## Grown-ups that are not warriors, wizards or in training.
func workers() -> int:
	var n := 0
	for v in people():
		if v.can_work() and v.job != "train":
			n += 1
	return n


## Sets how many warriors or wizards the player wants (clamped to what the
## buildings allow). It only goes up while there is someone free to train:
## an unassigned worker (or, for necromancers, a wizard).
##
## A necromancer is a mage trained on: asking for one gives up that mage's
## place at once (one fewer mage wanted), so another mage can be trained
## while the necromancer trains. Asking for one fewer while one is still in
## training gives the mage's place back.
func set_wanted(role: String, value: int) -> void:
	var top := max_count(role)
	var was: int = wanted[role]
	if value > was:
		var free_now := free_wizards() if role == "necromancer" else free_workers()
		top = mini(top, was + free_now)
	wanted[role] = clampi(value, 0, maxi(top, 0))
	if role == "necromancer":
		var more: int = wanted.necromancer - was
		if more > 0:
			wanted.wizard = maxi(0, wanted.wizard - more)
		elif more < 0:
			var back := mini(-more, training_progress("necromancer").size())
			wanted.wizard = mini(wanted.wizard + back, max_count("wizard"))
	_army_timer = 0.0


## What building `b` is doing, for the label over it when the mouse is on
## it: what is being researched at its kind of building (Blacksmith,
## Wizardry tower, Shrine), and who it is training, each with how far
## along. "" if nothing.
func status_of(b: Destructible) -> String:
	var role := BuildingCatalog.role(b.get_meta("kind", ""))
	var parts: PackedStringArray = []
	if research_jobs.has(role):
		for job: Dictionary in research_jobs[role]:
			parts.append("Researching %s: %d%%" % [Research.find(job.id).name, floori(research_progress(job.id) * 100.0)])
	if role == "wizard":
		for job: Dictionary in spell_jobs:
			parts.append("Researching %s: %d%%" % [SpellBook.find(job.id).name, floori(spell_research_progress(job.id) * 100.0)])
	if role == "shrine":
		for job: Dictionary in buff_jobs:
			parts.append("Researching %s: %d%%" % [BuffBook.find(job.id).name, floori(buff_research_progress(job.id) * 100.0)])
	if _training.has(b):
		var entry: Dictionary = _training[b]
		var what: String = String(entry.role).replace("_", " ")
		parts.append("Training a %s: %d%%" % [what, floori(clampf(entry.t / maxf(train_seconds(entry.role), 0.01), 0.0, 1.0) * 100.0)])
	if parts.is_empty() and (research_jobs.has(role) or role == "shrine"):
		parts.append("Researching nothing")
	return "\n".join(parts)


## Progress (0..1) of each recruit now training for `role`.
func training_progress(role: String) -> Array[float]:
	var out: Array[float] = []
	for b in _training:
		var entry: Dictionary = _training[b]
		if entry.role == role:
			out.append(clampf(entry.t / train_seconds(role), 0.0, 1.0))
	return out


## Food eaten per minute by everyone in the village.
func food_upkeep() -> float:
	var total := 0.0
	for v in people():
		if v.soldier:
			total += FOOD_PER_WARRIOR
		elif v.wizard:
			total += FOOD_PER_WIZARD
		elif v.archer:
			total += FOOD_PER_ARCHER
		elif v.banshee:
			total += FOOD_PER_BANSHEE
		else:
			total += FOOD_PER_VILLAGER
	return total + creature_upkeep()


## Where a worker standing at `from` takes what it gathered: the door of
## the nearest Storehouse (or, for food, Granary), or the middle of the
## village if there is none.
func drop_point(from: Vector3, kind := "") -> Vector3:
	var best := center
	var best_d := INF
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		var role := BuildingCatalog.role(b.get_meta("kind", ""))
		if role != "store" and not (role == "granary" and kind == "food"):
			continue
		var d := b.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			var out := from - b.global_position
			out.y = 0.0
			out = out.normalized() if out.length_squared() > 0.01 else Vector3.RIGHT
			best = b.global_position + out * (b.footprint + 0.6)
	return best


## Food gathered per worker per minute: the dev menu's food rate, and
## Balance "windmill_food_rate" more while the village has a Windmill
## standing (one is enough; more add nothing).
func food_rate() -> float:
	var rate: float = Game.settings.food_rate
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		if b != null and not b.destroyed and b.get_meta("kind", "") == "windmill":
			return rate + Balance.num("windmill_food_rate")
	return rate


func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if amount(res) < cost[res]:
			return false
	return true


## What is still needed, e.g. "12 lumber, 3 stone". Empty if affordable.
func shortfall(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in RESOURCES:
		if cost.has(res) and amount(res) < cost[res]:
			parts.append("%d %s" % [cost[res] - amount(res), res])
	return ", ".join(parts)


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res in cost:
		resources[res] -= cost[res]
	return true


## Adds (or, with a negative `value`, takes away) some of `res`. What
## comes in counts towards the rate shown beside it unless `income` is
## false (the dev menu's gift).
func give(res: String, value: float, income := true) -> void:
	var before: float = resources.get(res, 0.0)
	var now: float = before + value
	if value > 0.0 and STORED.has(res):
		# Whatever does not fit is lost (but nothing already stored is).
		now = minf(now, maxf(capacity(res), before))
	resources[res] = now
	if value > 0.0 and income:
		_flow_add(res, now - before)


func _flow_add(res: String, value: float) -> void:
	_flow[res] = _flow.get(res, 0.0) + value


## How much of `res` the village can keep: Balance "storehouse_holds" for
## every Storehouse (at least one's worth, so a village that has lost its
## Storehouse can still keep something), and "granary_holds" more food for
## every Granary. Magicko and animus have no limit.
func capacity(res: String) -> float:
	if not STORED.has(res):
		return INF
	var stores := 0
	var granaries := 0
	for node in get_tree().get_nodes_in_group(buildings_group):
		match BuildingCatalog.role(node.get_meta("kind", "")):
			"store":
				stores += 1
			"granary":
				granaries += 1
	var most := maxi(stores, 1) * Balance.num("storehouse_holds")
	if res == "lumber":
		most += _role_count("mill") * Balance.num("lumber_mill_holds")
	if res == "food":
		most += granaries * Balance.num("granary_holds")
	return most


## How much of `res` came in over the last minute (for food, less what was
## eaten, so it can be negative), from samples taken once a second. What is
## paid for buildings, research and spells does not count.
func last_minute(res: String) -> int:
	var samples: Array = _history.get(res, [])
	if samples.is_empty():
		return 0
	return roundi(_flow.get(res, 0.0) - float(samples[0]))


## Keeps a minute of samples of every resource.
func _sample(delta: float) -> void:
	_history_timer -= delta
	if _history_timer > 0.0:
		return
	_history_timer = 1.0
	for res in RESOURCES:
		var samples: Array = _history.get(res, [])
		samples.append(_flow.get(res, 0.0))
		while samples.size() > 61:
			samples.pop_front()
		_history[res] = samples


# --- Planting saplings ------------------------------------------------------------

## Now and then (Game.settings.sapling_rate a minute) an unassigned worker
## or a lumberjack kneels for Balance "plant_seconds" and plants a sapling,
## so the forest grows back where it is cut.
func _plan_planting(delta: float) -> void:
	for v in _planting.keys():
		if not is_instance_valid(v) or (v as Villager).job != "plant":
			_planting.erase(v)
	var rate: float = Game.settings.get("sapling_rate", 0.0)
	if rate <= 0.0 or not founded:
		return
	_plant_due += delta * rate / 60.0
	if _plant_due < 1.0:
		return
	_plant_due -= 1.0
	var planters: Array[Villager] = []
	for v in people():
		if v.can_work() and (v.pin == "" or v.pin == "lumber") and (v.job == "" or v.job == "lumber") \
				and not v._delivering and v.state != Villager.State.FIGHT:
			planters.append(v)
	if planters.is_empty():
		return
	var v: Villager = planters[randi() % planters.size()]
	var spot: Variant = _sapling_spot(v.global_position)
	if spot == null:
		return
	v.assign_job("plant", spot, self)
	_planting[v] = 0.0


## Somewhere near `near` to plant a tree: dry, not steep, clear of trees,
## rocks, buildings and fields, and within reach of the village. Null if
## nowhere is found.
func _sapling_spot(near: Vector3) -> Variant:
	var terrain := Game.terrain
	var tree := get_tree()
	for attempt in 12:
		var a := randf() * TAU
		var d := randf_range(4.0, 14.0)
		var p := near + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if not terrain.is_inside(p.x, p.z) or not terrain.is_dry(p.x, p.z) or terrain.get_normal(p.x, p.z).y < 0.85:
			continue
		if Vector2(p.x - center.x, p.z - center.z).length() > WORK_REACH * 0.9:
			continue
		p.y = terrain.get_height(p.x, p.z)
		if _crowded(p, tree):
			continue
		return p
	return null


func _crowded(p: Vector3, tree: SceneTree) -> bool:
	for group in ["trees", "saplings", "rocks"]:
		for node in tree.get_nodes_in_group(group):
			var n := node as Node3D
			if Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < 3.0:
				return true
	for group in ["buildings", "construction_sites"]:
		for node in tree.get_nodes_in_group(group):
			var n := node as Node3D
			var reach: float = n.get("footprint") if n.get("footprint") != null else 4.0
			if Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < reach + 3.0:
				return true
	for node in tree.get_nodes_in_group("fields"):
		if (node as CropField).contains(p):
			return true
	return false


## How far the village's influence reaches from its centre:
## Game.settings.influence_start, and influence_per_person more for every
## villager. Buildings go up, and the player's spells are cast, inside it.
func influence() -> float:
	return Game.settings.influence_start + Game.settings.influence_per_person * population()


## True where the village may put up a building, or the player cast a spell.
func in_territory(p: Vector3) -> bool:
	if not founded:
		return false
	var reach := influence()
	if Vector2(p.x - center.x, p.z - center.z).length() < reach:
		return true
	for c in taken_centres:
		if Vector2(p.x - c.x, p.z - c.z).length() < reach:
			return true
	return false


## The Shrines the village has built itself (they make animus).
func built_shrines() -> int:
	var n := 0
	for b in shrines():
		if int(b.get_meta("site", -1)) < 0:
			n += 1
	return n


## The Shrines that stand, for animus and bringing the creature back.
func shrines() -> Array[Destructible]:
	var out: Array[Destructible] = []
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		if BuildingCatalog.role(b.get_meta("kind", "")) == "shrine" and not b.destroyed:
			out.append(b)
	return out


## 0..1 of the way to the next birth (0 while no child can be born).
## Magicko the village makes a minute: Game.settings.magicko_rate from each
## grown-up worshiper (every one of the village's own people is one; the fey
## make Balance "fey_magicko" times as much), the worshipers in the neutral
## villages too (NeutralVillage.worshipers()), Balance "wizard_magicko" from
## each wizard, all blood_boost() times as much while a Blood Sacrifice
## lasts. (Magic trees give theirs themselves.)
## Where the village's magicko comes from, a minute: [amount, what], for
## the magicko rate's tooltip. (They add up to magicko_per_minute().)
func magicko_sources() -> Array[Array]:
	var rate: float = Game.settings.magicko_rate
	var mages := wizards()
	var fey := fey_adults()
	var plain := maxi(0, adults() - mages - fey)
	var worshipers := 0
	for node in get_tree().get_nodes_in_group("neutral_villages"):
		worshipers += (node as NeutralVillage).grown_worshipers()
	var out: Array[Array] = [
		[mages * Balance.num("wizard_magicko"), "%d mage%s" % [mages, "" if mages == 1 else "s"]],
		[plain * rate, "%d villager%s" % [plain, "" if plain == 1 else "s"]],
	]
	if fey > 0:
		out.append([fey * Balance.num("fey_magicko") * rate, "%d fey villager%s" % [fey, "" if fey == 1 else "s"]])
	if worshipers > 0:
		out.append([worshipers * rate, "%d worshiper%s in neutral villages" % [worshipers, "" if worshipers == 1 else "s"]])
	if blood_active():
		var base := 0.0
		for part in out:
			base += part[0]
		out.append([base * (blood_boost() - 1.0), "Blood Sacrifice (x%s)" % String.num(blood_boost(), 1)])
	return out


## The magicko rate's tooltip: the magicko a minute, and where it comes from.
func magicko_tip() -> String:
	var lines := PackedStringArray(["Magicko: %s a minute" % _signed(magicko_per_minute())])
	for part in magicko_sources():
		lines.append("%s from %s" % [_signed(part[0]), part[1]])
	return "\n".join(lines)


static func _signed(value: float) -> String:
	var text := str(roundi(value)) if absf(value - roundf(value)) < 0.05 else String.num(value, 1)
	return ("+" + text) if value >= 0.0 else text


func magicko_per_minute() -> float:
	var grown := adults() - wizards()
	var fey_extra := fey_adults() * (Balance.num("fey_magicko") - 1.0)
	for node in get_tree().get_nodes_in_group("neutral_villages"):
		grown += (node as NeutralVillage).grown_worshipers()
	var boost := blood_boost() if blood_active() else 1.0
	return ((grown + fey_extra) * Game.settings.magicko_rate + wizards() * Balance.num("wizard_magicko")) * boost


func birth_share() -> float:
	if next_birth_in() < 0.0:
		return 0.0
	return clampf(birth_progress / maxf(Game.settings.birth_seconds, 0.01), 0.0, 1.0)


## Seconds until the next child, or -1 when the village is out of housing.
func next_birth_in() -> float:
	if population() >= housing() or amount("food") <= 0:
		return -1.0
	return maxf(0.0, Game.settings.birth_seconds - birth_progress)


func _process(delta: float) -> void:
	if not founded:
		return
	if neutral:
		_live(delta)
		return
	give("magicko", magicko_per_minute() / 60.0 * delta)
	# Animus: Balance "animus_per_minute" to begin with, and more for every
	# Shrine the village has built (not the ones its site came with).
	give("animus", (Balance.num("animus_per_minute") + built_shrines() * Balance.num("animus_per_shrine")) / 60.0 * delta)
	_update_storm_spires(delta)
	_live(delta)
	_update_research(delta)
	_update_spell_research(delta)
	_plan_planting(delta)


## What every village does, the player's and the neutral ones: eat, have
## children, and set its people to work and to train.
func _live(delta: float) -> void:
	_sample(delta)
	_eat(delta)
	if population() < housing() and amount("food") > 0:
		birth_progress += delta * (Balance.num("fey_birth_boost") if Game.now < fey_until else 1.0)
		if birth_progress >= Game.settings.birth_seconds:
			birth_progress = 0.0
			_spawn_child()
	_assign_timer -= delta
	if _assign_timer <= 0.0:
		_assign_timer = 0.5
		_assign_jobs()
	_army_timer -= delta
	if _army_timer <= 0.0:
		_army_timer = 0.5
		barrows = has_research("wheelbarrows")
		_manage_army()


## The dev menu's Advance time: `seconds` go by at once for births (as
## many as there is room and food for), children growing up, research and
## training.
func advance(seconds: float) -> void:
	var boost := Balance.num("fey_birth_boost") if Game.now < fey_until else 1.0
	var every := maxf(Game.settings.birth_seconds, 0.01)
	birth_progress += seconds * boost
	var born := 0
	while birth_progress >= every and population() < housing() and amount("food") > 0 and born < 500:
		birth_progress -= every
		_spawn_child()
		born += 1
	birth_progress = minf(birth_progress, every)
	for v in people():
		if v.child:
			v._grow(seconds)
	_update_research(seconds)
	_update_spell_research(seconds)
	for b in _training:
		_training[b].t += seconds


func _eat(delta: float) -> void:
	var eaten := food_upkeep() / 60.0 * delta
	give("food", -eaten)
	# (Eating goes on all the time, so it counts against the food rate.)
	_flow_add("food", -eaten)
	if resources.food > 0.0:
		hungry_for = 0.0
		_starve_timer = 0.0
		return
	resources.food = 0.0
	hungry_for += delta
	if founded and not neutral and Game.now >= _food_warned_at + Balance.num("food_warning_seconds"):
		_food_warned_at = Game.now
		_float_over_storehouse(Texts.line("out_of_food" if hungry_for < STARVE_AFTER else "starving"))
	if hungry_for < STARVE_AFTER:
		return
	var per_minute: float = Game.settings.get("starve_per_minute", 6.0)
	if per_minute <= 0.0:
		return
	_starve_timer -= delta
	if _starve_timer <= 0.0:
		_starve_timer = 60.0 / per_minute
		var all := people()
		if not all.is_empty():
			all[randi() % all.size()].starve()


## A line of text floats up from the Storehouse (the nearest to the
## middle of the village), or from the middle if there is none.
func _float_over_storehouse(text: String, color := Color(1.0, 0.55, 0.4)) -> void:
	var at := center
	var high := 6.0
	var best := INF
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		if b != null and not b.destroyed and BuildingCatalog.role(b.get_meta("kind", "")) == "store" and b.global_position.distance_to(center) < best:
			best = b.global_position.distance_to(center)
			at = b.global_position
			high = b.height
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 26
	label.outline_size = 10
	label.modulate = color
	label.add_to_group("food_warnings")
	Game.effects.add_child(label)
	label.global_position = at + Vector3.UP * (high + 1.5)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", 4.0, 5.0).as_relative()
	tw.parallel().tween_property(label, "modulate:a", 0.0, 1.5).set_delay(3.5)
	tw.parallel().tween_property(label, "outline_modulate:a", 0.0, 1.5).set_delay(3.5)
	tw.tween_callback(label.queue_free)


func _spawn_child() -> Villager:
	var spot := center
	var homes := get_tree().get_nodes_in_group(buildings_group)
	if not homes.is_empty():
		var b := homes[randi() % homes.size()] as Destructible
		var a := randf() * TAU
		spot = b.global_position + Vector3(cos(a), 0.0, sin(a)) * (b.footprint + 1.0)
	# (While the fey are about, every child is fey: a girl with wings.)
	var v := spawn_person(spot, 1.0, true, Game.now < fey_until)
	v.home = center
	v.home_radius = HOME_RADIUS
	Game.effects.spawn_dust(v.global_position, 0.4)
	return v


# --- Work ---------------------------------------------------------------------

## Called every frame by a villager that is at its job.
func work(v: Villager, delta: float) -> void:
	match v.job:
		"build":
			var site := v.job_target as ConstructionSite
			# (Goblin builders go back to their cave for more between spells of work.)
			if site and Vector2(v.global_position.x - site.global_position.x, v.global_position.z - site.global_position.z).length() < site.footprint + 4.0:
				site.add_work(delta)
		"train":
			var post := v.job_target as Node3D
			var entry: Dictionary = _training.get(post, {})
			if entry.is_empty() or entry.v != v:
				v.clear_job()
				return
			entry.t += delta
			if entry.t >= train_seconds(entry.role):
				_training.erase(post)
				match entry.role:
					"warrior":
						v.guard = post
						v.become_soldier(post.global_position)
					"archer":
						v.guard = post
						v.become_archer(post.global_position)
					"fey_archer":
						v.guard = post
						v.become_fey_archer(post.global_position)
					"banshee":
						v.become_banshee(post.global_position)
					"necromancer":
						# A mage upgraded (its place among the mages was given
						# up when the necromancer was asked for: set_wanted()).
						v.become_necromancer(post.global_position)
					_:
						v.become_wizard(post.global_position)
		"tryst":
			_tryst(v, delta)
		"plant":
			_planting[v] = _planting.get(v, 0.0) + delta
			if _planting[v] >= Balance.num("plant_seconds"):
				_planting.erase(v)
				var ahead := Vector3(sin(v.rotation.y), 0.0, cos(v.rotation.y))
				Sapling.plant(v.global_position + ahead * 0.9)
				v.clear_job()
		"food":
			v.gather("food", food_rate() / 60.0 * delta * tool_bonus("food") * Balance.num("farmer_speed"))
		"tend":
			# Working the growing wheat (weeding, watering) hurries it on.
			var tended := v.job_target as CropField
			if tended == null or tended.needs_work():
				v.clear_job()
			else:
				tended.tend(delta * Balance.num("farmer_speed"))
		"farm":
			var field := v.job_target as CropField
			# (Only farmers sow.)
			if field == null or not field.needs_work() or (v.pin != "food" and not field.is_ripe()):
				v.clear_job()
			else:
				var reaped := field.add_work(delta * tool_bonus("food") * Balance.num("farmer_speed"))
				if reaped > 0.0:
					v.gather("food", reaped)
		"lumber":
			var gained: float = Game.settings.lumber_rate / 60.0 * delta * tool_bonus("lumber")
			v.gather("lumber", gained)
			var tree := v.job_target as Destructible
			if tree and not tree.destroyed:
				var left: float = tree.get_meta("wood", TREE_WOOD if tree.footprint > 1.6 else BUSH_WOOD) - gained
				tree.set_meta("wood", left)
				if left <= 0.0:
					tree.fell()
		"stone":
			var gained: float = Game.settings.stone_rate / 60.0 * delta * tool_bonus("stone")
			v.gather("stone", gained)
			var rock := v.job_target as Node3D
			if rock and rock.is_in_group("rocks"):
				var left: float = rock.get_meta("stone", Balance.num("rock_stone") * rock.scale.x) - gained
				rock.set_meta("stone", left)
				if left <= 0.0:
					_break_rock(rock)


func _break_rock(rock: Node3D) -> void:
	rock.remove_from_group("rocks")
	rock.remove_from_group("grounded")
	Game.effects.spawn_dust(rock.global_position, clampf(rock.scale.x, 0.5, 2.0))
	# What is left of it crumbles away slowly.
	var tw := rock.create_tween()
	tw.tween_property(rock, "scale", rock.scale * 0.05, maxf(Balance.num("rock_crumble_seconds"), 0.1)).set_ease(Tween.EASE_IN)
	tw.tween_callback(rock.queue_free)


func _assign_jobs() -> void:
	var workers: Array[Villager] = []
	for v in people():
		if v.can_work() and v.job != "train":
			workers.append(v)
	quota = {"lumber": 0, "stone": 0, "food": 0, "build": 0}
	if workers.is_empty():
		gatherers = {"lumber": 0, "stone": 0, "food": 0}
		return
	for v in workers:
		if quota.has(v.pin):
			quota[v.pin] += 1
	# Building: each site takes up to `most` villagers, builders first, then
	# unassigned workers; the oldest site is manned first.
	var most := maxi(1, roundi(Balance.num("builders_per_building")))
	var sites := construction_sites()
	var crew := {}
	for v in workers:
		if v.job != "build":
			continue
		# Only Builders and unassigned Workers build.
		if v.pin != "" and v.pin != "build":
			v.clear_job()
			continue
		if is_instance_valid(v.job_target) and sites.has(v.job_target) and crew.get(v.job_target, 0) < most:
			crew[v.job_target] = crew.get(v.job_target, 0) + 1
		else:
			v.clear_job()
	for node in sites:
		var site := node as ConstructionSite
		var have: int = crew.get(site, 0)
		while have < most:
			var v := _next_builder(workers, site.global_position, have == 0)
			if v == null:
				break
			v.assign_job("build", site.work_spot(have, most), site)
			have += 1

	var counts := {"lumber": 0, "stone": 0, "food": 0}
	var per_target := {}
	var farmers := {}
	var farming := 0
	for v in workers:
		if v.pin == "build" and v.job != "build" and v.job != "":
			# A builder with nothing to build waits for the next building.
			v.clear_job()
		elif counts.has(v.job):
			counts[v.job] += 1
			if is_instance_valid(v.job_target):
				per_target[v.job_target] = per_target.get(v.job_target, 0) + 1
		elif v.job == "farm" and is_instance_valid(v.job_target):
			farmers[v.job_target] = farmers.get(v.job_target, 0) + 1
			per_target[v.job_target] = per_target.get(v.job_target, 0) + 1
			farming += 1
		elif v.job == "tend" and is_instance_valid(v.job_target):
			per_target[v.job_target] = per_target.get(v.job_target, 0) + 1
			farming += 1
	var fields_want_hands := false
	for node in fields():
		fields_want_hands = fields_want_hands or (node as CropField).needs_work()
	# The villagers the player set to a job keep to it.
	for v in workers:
		# (A farmer working the growing wheat keeps at it until a field
		# wants sowing or reaping: harvesting comes first.)
		if v.job == "build" or v.job == "plant" or v.job == "tryst" or not counts.has(v.pin) or v.job == v.pin or (v.pin == "food" and v.job == "farm") \
				or (v.pin == "food" and v.job == "tend" and not fields_want_hands):
			continue
		var was := v.job
		if _give_job(v, v.pin, per_target):
			if counts.has(was):
				counts[was] -= 1
			counts[v.pin] += 1
	# The farmers go to the fields: ripe ones first (they reap before they
	# sow), and every field gets one before any gets a second.
	var fields: Array[CropField] = []
	for node in fields():
		var field := node as CropField
		if field != null and field.needs_work():
			fields.append(field)
	fields.sort_custom(func(a: CropField, b: CropField) -> bool: return a.is_ripe() and not b.is_ripe())
	for pass_k in 2:
		for field in fields:
			var want := 1 if pass_k == 0 else field.wanted_workers()
			var have: int = farmers.get(field, 0)
			while have < want:
				var v := _spare_farmer(workers, field, farmers)
				if v == null:
					break
				if counts.has(v.job):
					counts[v.job] -= 1
				elif v.job == "farm" and is_instance_valid(v.job_target):
					farmers[v.job_target] = maxi(0, farmers.get(v.job_target, 1) - 1)
					per_target[v.job_target] = maxi(0, per_target.get(v.job_target, 1) - 1)
					farming -= 1
				v.assign_job("farm", field.work_spot(), field)
				farming += 1
				have += 1
				farmers[field] = have
				per_target[field] = per_target.get(field, 0) + 1
	# Unassigned workers go after whatever the village has least of.
	var kinds: Array = ["lumber", "stone", "food"]
	kinds.sort_custom(func(a: String, b: String) -> bool: return resources.get(a, 0.0) < resources.get(b, 0.0))
	for v in workers:
		if v.job != "" or v.pin != "":
			continue
		for kind: String in kinds:
			if _give_job(v, kind, per_target):
				counts[kind] += 1
				break
	gatherers = {"lumber": counts.lumber, "stone": counts.stone, "food": counts.food + farming}


## The next villager to send to a building site at `at`: a builder with
## nothing to build, else the nearest unassigned worker. (Lumberjacks,
## miners and farmers never build.) `_desperate` is no longer used.
func _next_builder(workers: Array[Villager], at: Vector3, _desperate: bool) -> Villager:
	for wanted: String in ["build", ""]:
		var best: Villager = null
		var best_d := INF
		for v in workers:
			# (Someone kneeling to plant a sapling finishes it first.)
			if v.job == "build" or v.job == "plant" or v.job == "tryst" or (wanted != "any" and v.pin != wanted):
				continue
			var d := v.global_position.distance_to(at)
			if d < best_d:
				best_d = d
				best = v
		if best:
			return best
	return null


## A farmer that can be moved to `field`: one with nothing to do (or
## foraging), or, for ripe wheat, one sowing a field that has another
## farmer on it (reaping comes first). Null if there is none.
func _spare_farmer(workers: Array[Villager], field: CropField, farmers: Dictionary) -> Villager:
	for v in workers:
		if v.pin == "food" and (v.job == "" or v.job == "food"):
			return v
	if not field.is_ripe():
		return null
	for v in workers:
		var sowing: CropField = (v.job_target as CropField) if v.job == "farm" else null
		if v.pin == "food" and sowing != null and sowing != field and not sowing.is_ripe() and farmers.get(sowing, 0) > 1:
			return v
	for v in workers:
		var sowing: CropField = (v.job_target as CropField) if v.job == "farm" else null
		if v.pin == "food" and sowing != null and sowing != field and not sowing.is_ripe():
			return v
	return null


## How many standing buildings with `role` the village has.
func _role_count(role: String) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		if b != null and not b.destroyed and BuildingCatalog.role(b.get_meta("kind", "")) == role:
			n += 1
	return n


## The village's standing Storm Spires.
func storm_spires() -> Array[Destructible]:
	var out: Array[Destructible] = []
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		if BuildingCatalog.role(b.get_meta("kind", "")) == "storm" and not b.destroyed:
			out.append(b)
	return out


## Each Storm Spire makes Storm Essence, and strikes the nearest enemy
## that comes within Balance "storm_lightning_range" with chain lightning
## (no more often than "storm_lightning_seconds"), for
## "storm_lightning_cost" Storm Essence.
func _update_storm_spires(delta: float) -> void:
	var spires := storm_spires()
	if spires.is_empty():
		return
	give("storm_essence", spires.size() * Balance.num("storm_essence_per_minute") / 60.0 * delta)
	var cost := Balance.num("storm_lightning_cost")
	for b in spires:
		if Game.now < float(_spire_ready.get(b, 0.0)) or float(resources.get("storm_essence", 0.0)) < cost:
			continue
		# (Looked for twice a second.)
		_spire_ready[b] = Game.now + 0.5
		var foe := _storm_target(b.global_position)
		if foe == null:
			continue
		give("storm_essence", -cost, false)
		_spire_ready[b] = Game.now + Balance.num("storm_lightning_seconds")
		ChainLightning.cast(foe.global_position, 0.0)


## The nearest enemy within the Storm Spire's reach of `at`: a goblin (not
## charmed), an ogre, a giant bat or the Balrog. Null if none.
func _storm_target(at: Vector3) -> Node3D:
	var reach := Balance.num("storm_lightning_range")
	var best: Node3D = null
	var best_d := reach
	var tree := get_tree()
	for node in tree.get_nodes_in_group("goblins"):
		var g := node as Villager
		if g == null or not g.is_alive() or g.charmed():
			continue
		var d := Vector2(g.global_position.x - at.x, g.global_position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = g
	for node in tree.get_nodes_in_group("bats") + tree.get_nodes_in_group("balrogs"):
		var n := node as Node3D
		if n is Creature and (n as Creature).knocked_out:
			continue
		if n is GiantBat and not (n as GiantBat).is_alive():
			continue
		var d := Vector2(n.global_position.x - at.x, n.global_position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


func _training_buildings(role: String) -> Array[Destructible]:
	var out: Array[Destructible] = []
	for node in get_tree().get_nodes_in_group(buildings_group):
		var b := node as Destructible
		if BuildingCatalog.role(b.get_meta("kind", "")) == ARMY[role][0] and not b.destroyed:
			out.append(b)
	return out


## Trains or stands down warriors and wizards until each matches what the
## player asked for. Each training building takes one recruit at a time.
func _manage_army() -> void:
	# Forget recruits who died, were stood down or lost their building.
	for b in _training.keys():
		var entry: Dictionary = _training[b]
		var v: Villager = entry.v
		if not is_instance_valid(b) or (b as Destructible).destroyed or not is_instance_valid(v) \
				or not v.is_alive() or v.job != "train" or v.job_target != b:
			if is_instance_valid(v) and v.is_alive() and v.job == "train":
				v.clear_job()
			_training.erase(b)
	for role: String in ARMY:
		wanted[role] = mini(wanted[role], max_count(role))
		var training := training_progress(role).size()
		var have := count(role)
		# Too many: stop training first, then send the rest back to work.
		while have + training > wanted[role]:
			if training > 0:
				for b in _training.keys():
					if _training[b].role == role:
						(_training[b].v as Villager).clear_job()
						_training.erase(b)
						break
				training -= 1
			else:
				for v in people():
					if (v.soldier and role == "warrior") or (v.wizard and not v.necromancer and v.job != "train" and role == "wizard") \
							or (v.fey_archer and role == "fey_archer") or (v.banshee and role == "banshee") \
							or (v.archer and not v.fey_archer and role == "archer") or (v.necromancer and role == "necromancer"):
						v.become_worker()
						break
				have -= 1
		if have + training >= wanted[role]:
			continue
		# Too few: each free training building with room takes a recruit.
		for b in _training_buildings(role):
			if have + training >= wanted[role]:
				break
			if _training.has(b):
				continue
			var recruit := _nearest_wizard(b.global_position) if role == "necromancer" else _nearest_worker(b.global_position, role == "fey_archer")
			if recruit == null:
				break
			var out := recruit.global_position - b.global_position
			out.y = 0.0
			out = out.normalized() if out.length_squared() > 0.01 else Vector3.RIGHT
			recruit.assign_job("train", b.global_position + out * (b.footprint + 0.8), b)
			_training[b] = {"v": recruit, "t": 0.0, "role": role}
			training += 1


## The nearest unassigned worker (lumberjacks, miners, farmers and
## builders keep to their jobs).
func _nearest_worker(to: Vector3, fey_only := false) -> Villager:
	var best: Villager = null
	var best_d := INF
	for v in people():
		if not v.can_work() or v.job == "train" or v.job == "tryst" or v.pin != "" or (fey_only and not v.fey):
			continue
		var d := v.global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = v
	return best


## The nearest wizard that is not already a necromancer or training to be one.
func _nearest_wizard(to: Vector3) -> Villager:
	var best: Villager = null
	var best_d := INF
	for v in people():
		if not v.wizard or v.necromancer or v.job == "train" or not v.is_alive():
			continue
		var d := v.global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = v
	return best


func _give_job(v: Villager, kind: String, per_target: Dictionary) -> bool:
	match kind:
		"food":
			# Food comes only from crop fields: ripe wheat first, the field
			# with the fewest hands on it (then the nearest). Only farmers
			# sow; nothing while all are growing.
			var best: CropField = null
			var best_score := INF
			for node in fields():
				var field := node as CropField
				if field == null or not field.needs_work() or (not field.is_ripe() and v.pin != "food"):
					continue
				var on: int = per_target.get(field, 0)
				var score := (0.0 if field.is_ripe() else 1.0e6) + on * 1.0e3 + field.global_position.distance_to(v.global_position)
				if score < best_score:
					best_score = score
					best = field
			if best == null:
				# Nothing to sow or reap: a farmer works the growing fields
				# instead, which hurries them on (CropField.tend()).
				return v.pin == "food" and _tend_field(v, per_target)
			v.assign_job("farm", best.work_spot(), best)
			per_target[best] = per_target.get(best, 0) + 1
			return true
		"lumber", "stone":
			var target := _nearest_free(v.global_position, "trees" if kind == "lumber" else "rocks", per_target)
			if target == null:
				return false
			var to_center := center - target.global_position
			to_center.y = 0.0
			var dir := to_center.normalized() if to_center.length_squared() > 0.01 else Vector3.RIGHT
			var reach := 1.1 if kind == "lumber" else 1.3 * target.scale.x + 0.5
			v.assign_job(kind, target.global_position + dir * reach, target)
			per_target[target] = per_target.get(target, 0) + 1
			return true
	return false


## Sends farmer `v` to work the growing field with the fewest hands on it.
func _tend_field(v: Villager, per_target: Dictionary) -> bool:
	var best: CropField = null
	var fewest := 1 << 30
	for node in fields():
		var field := node as CropField
		if field == null or field.stage != CropField.Stage.GROWING:
			continue
		var on: int = per_target.get(field, 0)
		if on < fewest:
			fewest = on
			best = field
	if best == null:
		return false
	v.assign_job("tend", best.work_spot(), best)
	per_target[best] = fewest + 1
	return true


func _nearest_free(from: Vector3, group: String, per_target: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(group):
		var n := node as Node3D
		if per_target.get(n, 0) >= MAX_PER_TARGET:
			continue
		var d := Vector2(n.global_position.x - center.x, n.global_position.z - center.z).length()
		# (Lumberjacks go as far as it takes for wood; stone is mined nearer home.)
		if d > WORK_REACH and group != "trees":
			continue
		var tree := n as Destructible
		if tree and (tree.burning or tree.destroyed):
			continue
		# (Somewhere a villager could not get to lately.)
		if Game.now < float(n.get_meta("blocked_until", -INF)):
			continue
		var score := n.global_position.distance_to(from) + d * 0.5
		if score < best_d:
			best_d = score
			best = n
	return best
