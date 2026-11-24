class_name BuildingCatalog
extends RefCounted
## The things the player can order from the build menu (B / Backspace):
## their names, what they cost and what they are for.
##
## Every building has an asset name (the model, built by BuildingFactory
## from its `kind`), a gameplay name (what it does) and an in-game name
## (what players see it called). Names.txt in the project folder pairs
## them up, one "Asset name = Gameplay name = In-game name" per line, so
## the owner can change what any model is used for and what it is called.
## The asset names never change, and players only see them in the build
## menu's tooltips while the dev menu is open. A building with no in-game
## name is shown as MISSING_NAME. Costs are read from balancing.txt and go with the
## gameplay name (cost_<gameplay name>_<resource>).
##
## Roles (what the code asks about):
##   home   adds housing, so more villagers can be born
##   store  the Storehouse: villagers carry what they gather to it, and it
##          holds Balance "storehouse_holds" of each (and houses people)
##   granary the Granary: holds "granary_holds" more food; farmers take food to it
##   shrine the Shrine: makes animus, and the creature is brought back to life there
##   guard  the Town guard: trains warriors (soldiers in the code) and archers
##   smith  the Blacksmith: wheelbarrows for the workers, and research
##   wizard the Wizardry tower: trains wizards
##   necro  the Necromancer tower: turns wizards into necromancers
##   field  a wheat field, drawn on the ground instead of placed (CropField)
##   bridge a rope bridge, hung between two treehouses instead of placed (RopeBridge)

const NAMES_PATH := "res://Names.txt"
## What a building with no in-game name is called.
const MISSING_NAME := "Name missing"
## Housing every village has before it builds anything.
const BASE_HOUSING := 0

## kind -> asset name, in the order of Names.txt.
const ASSETS := [
	["treehouse", "Treehouse"],
	["lookout_treehouse", "Lookout treehouse"],
	["twin_treehouse", "Twin treehouse"],
	["great_treehouse", "Great treehouse"],
	["store", "Stacked houses"],
	["store_house", "Store house"],
	["moon_tower", "Moon tower"],
	["blacksmith", "Blacksmith"],
	["mushroom_house", "Mushroom cottage"],
	["singing_rocks", "Singing rocks"],
	["necro_tower", "Skull tower"],
	["windmill", "Windmill"],
	["crystal_tower", "Crystal tower"],
	["tall_house", "Tall house"],
]
## The gameplay names used when Names.txt is missing or leaves an asset out.
const DEFAULT_GAMEPLAY := {
	"treehouse": "Home", "lookout_treehouse": "Home", "twin_treehouse": "Home", "great_treehouse": "Home",
	"store": "Storehouse", "store_house": "Storehouse", "moon_tower": "Wizardry tower", "blacksmith": "Blacksmith", "mushroom_house": "Cottage",
	"singing_rocks": "Shrine", "necro_tower": "Necromancer tower", "windmill": "Granary",
	"crystal_tower": "Decoration", "tall_house": "Town guard",
}
## gameplay effect (lower case) -> [name, role, cost id, what the menu says].
## Players never see the gameplay effect: the game shows in-game names.
const GAMEPLAY := {
	"home": ["Home", "home", "home", "Room for %d villagers"],
	"cottage": ["Cottage", "home", "cottage", "Room for %d villagers"],
	"storehouse": ["Storehouse", "store", "storehouse", "Stores goods, houses %d"],
	"granary": ["Granary", "granary", "granary", "Stores food"],
	"shrine": ["Shrine", "shrine", "shrine", "Makes animus; research spells, revive the creature"],
	"town guard": ["Town guard", "guard", "town_guard", "Trains warriors"],
	"blacksmith": ["Blacksmith", "smith", "blacksmith", "Wheelbarrows; research"],
	"wizardry tower": ["Wizardry tower", "wizard", "wizardry_tower", "Trains wizards"],
	"necromancer tower": ["Necromancer tower", "necro", "necromancer_tower", "Turns wizards into necromancers"],
	"decoration": ["Decoration", "", "decoration", "No use yet"],
}
## Menu entries that are not placed like buildings.
const SPECIAL := [
	{"kind": "field", "name": "Wheat field", "asset": "Wheat field", "title": "Wheat field", "gameplay": "", "role": "field", "cost": {},
		"desc": "Drag a square. 1 lumber per 10 m2"},
	{"kind": "bridge", "name": "Rope bridge", "asset": "Rope bridge", "title": "Rope bridge", "gameplay": "", "role": "bridge", "cost": {},
		"desc": "Joins 2 treehouses. 1 lumber a metre"},
]
## What the goblins put up (see GoblinRaids).
const GOBLIN_NAMES := {
	"goblin_hut": "Goblin hut", "goblin_tent": "Goblin tent", "goblin_war_hut": "Goblin war hut",
	"goblin_forge": "Goblin forge", "goblin_potion_hut": "Goblin potion hut", "goblin_watchtower": "Goblin watchtower",
}
const COST_RESOURCES := ["lumber", "stone", "food", "bones"]

## The build menu, in order: the special entries, then every asset that has
## a gameplay name. Each is a Dictionary with kind, name (the asset name),
## asset, title (the in-game name), gameplay, role, housing, desc and cost.
static var BUILDINGS: Array = []
## Every asset, in the menu or not: kind -> its entry.
static var _all := {}


## Reads Names.txt and the costs in Balance. Call again after changing them.
static func apply_balance() -> void:
	var wanted := _read_names()
	BUILDINGS = SPECIAL.duplicate(true)
	_all = {}
	for pair: Array in ASSETS:
		var kind: String = pair[0]
		var names: Array = wanted.get((pair[1] as String).to_lower(), [DEFAULT_GAMEPLAY[kind], ""])
		var gameplay: String = names[0]
		var title: String = names[1] if names[1] != "" else MISSING_NAME
		var entry := {"kind": kind, "name": pair[1], "asset": pair[1], "title": title, "gameplay": "", "role": "", "housing": 0, "desc": "", "cost": {}}
		var key := gameplay.strip_edges().to_lower()
		if key != "" and not GAMEPLAY.has(key):
			push_warning("Names.txt: there is no gameplay name '%s' (for %s), so it is a Decoration" % [gameplay, pair[1]])
			key = "decoration"
		if key != "":
			var info: Array = GAMEPLAY[key]
			entry.gameplay = info[0]
			entry.role = info[1]
			entry.housing = roundi(Balance.num(info[2] + "_housing"))
			entry.desc = (info[3] as String) % entry.housing if "%d" in info[3] else info[3]
			for res: String in COST_RESOURCES:
				var n := roundi(Balance.num("cost_%s_%s" % [info[2], res]))
				if n > 0:
					entry.cost[res] = n
			BUILDINGS.append(entry)
		_all[kind] = entry
	for entry: Dictionary in SPECIAL:
		_all[entry.kind] = entry
	for kind: String in GOBLIN_NAMES:
		_all[kind] = {"kind": kind, "name": GOBLIN_NAMES[kind], "asset": GOBLIN_NAMES[kind], "title": GOBLIN_NAMES[kind],
			"gameplay": "", "role": "", "housing": 0, "desc": "", "cost": {}}


## Asset name (lower case) -> [gameplay name, in-game name] as written
## beside it in Names.txt (either can be empty).
static func _read_names() -> Dictionary:
	var out := {}
	var file := FileAccess.open(NAMES_PATH, FileAccess.READ)
	if file == null:
		push_warning("Names.txt not found: using the built-in building names")
		return out
	var known := {}
	for pair: Array in ASSETS:
		known[(pair[1] as String).to_lower()] = true
	while not file.eof_reached():
		var line := file.get_line().split("#")[0].strip_edges()
		if line == "" or not "=" in line:
			continue
		var asset := line.get_slice("=", 0).strip_edges().to_lower()
		if not known.has(asset):
			push_warning("Names.txt: there is no asset called '%s'" % line.get_slice("=", 0).strip_edges())
			continue
		out[asset] = [line.get_slice("=", 1).strip_edges(), line.get_slice("=", 2).strip_edges() if line.count("=") >= 2 else ""]
	return out


static func find(kind: String) -> Dictionary:
	if _all.is_empty():
		apply_balance()
	return _all.get(kind, {})


## What players see building `kind` called (its in-game name).
static func title(kind: String) -> String:
	return find(kind).get("title", MISSING_NAME)


## What players call the building with `role` (its in-game name: the
## first one in Names.txt with that gameplay effect).
static func role_name(role: String) -> String:
	if _all.is_empty():
		apply_balance()
	for pair: Array in ASSETS:
		var entry: Dictionary = _all.get(pair[0], {})
		if entry.get("role", "") == role:
			return entry.title
	return MISSING_NAME


## The kind of the first building in Names.txt with `role` (as role_name),
## or `fallback` if none has it.
static func kind_for_role(role: String, fallback: String) -> String:
	if _all.is_empty():
		apply_balance()
	for pair: Array in ASSETS:
		if (_all.get(pair[0], {}) as Dictionary).get("role", "") == role:
			return pair[0]
	return fallback


static func housing(kind: String) -> int:
	return find(kind).get("housing", 0)


static func role(kind: String) -> String:
	return find(kind).get("role", "")


## What a rope bridge `length` metres long costs.
static func bridge_cost(length: float) -> Dictionary:
	return {"lumber": maxi(1, ceili(length * Balance.num("cost_bridge_lumber_per_metre")))}


## "40 lumber  15 stone"
static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in PlayerVillage.RESOURCES:
		if cost.has(res):
			parts.append("%d %s" % [cost[res], res])
	return "  ".join(parts)
