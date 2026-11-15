class_name BuildingCatalog
extends RefCounted
## The things the player can order from the build menu (B / Backspace):
## their names, what they cost and what they are for. The look of each
## building comes from BuildingFactory. The costs are read from
## balancing.txt (cost_<id>_<resource>), so `cost` is filled in by
## apply_balance(), which Game calls when it starts.
##
## Roles:
##   home   adds housing, so more villagers can be born
##   store  the Storehouse: villagers carry what they gather to it
##   guard  the Town guard: trains warriors (soldiers in the code) and archers
##   smith  the Blacksmith: wheelbarrows for the workers, and research
##   wizard the Singing rocks: trains wizards
##   necro  the Necromancer tower: turns wizards into necromancers
##   field  a wheat field, drawn on the ground instead of placed (CropField)
##   bridge a rope bridge, hung between two Homes instead of placed (RopeBridge)

## Housing every village has before it builds anything.
const BASE_HOUSING := 10

const LIST := [
	{"kind": "treehouse", "id": "home", "name": "Home", "role": "home", "housing": 6,
		"desc": "A treehouse: room for 6 more villagers"},
	{"kind": "bridge", "id": "bridge", "name": "Rope bridge", "role": "bridge",
		"desc": "Click two Homes to join them. 1 lumber a metre"},
	{"kind": "store", "id": "storehouse", "name": "Storehouse", "role": "store",
		"desc": "Villagers carry resources here"},
	{"kind": "moon_tower", "id": "town_guard", "name": "Town guard", "role": "guard",
		"desc": "Trains 4 warriors, 1 min each"},
	{"kind": "blacksmith", "id": "blacksmith", "name": "Blacksmith", "role": "smith",
		"desc": "Wheelbarrows, and research (U)"},
	{"kind": "field", "id": "field", "name": "Wheat field", "role": "field",
		"desc": "Drag out a square. 1 lumber per 10 m2"},
	{"kind": "mushroom_house", "id": "mushroom_cottage", "name": "Mushroom cottage", "role": "home", "housing": 3,
		"desc": "Room for 3 more villagers"},
	{"kind": "singing_rocks", "id": "singing_rocks", "name": "Singing rocks", "role": "wizard",
		"desc": "Trains 2 wizards, 3 min each"},
	{"kind": "necro_tower", "id": "necromancer_tower", "name": "Necromancer tower", "role": "necro",
		"desc": "Turns wizards into necromancers, who raise the dead"},
	{"kind": "windmill", "id": "windmill", "name": "Windmill", "role": "",
		"desc": "No use yet"},
	{"kind": "crystal_tower", "id": "crystal_tower", "name": "Crystal tower", "role": "",
		"desc": "No use yet"},
]
## Buildings that are not in the menu: the tall houses of older maps, and
## what the goblins put up (see GoblinRaids).
const OTHERS := [
	{"kind": "tall_house", "id": "home", "name": "Tall house", "role": "home", "housing": 6, "desc": ""},
	{"kind": "goblin_hut", "id": "", "name": "Goblin hut", "role": "", "desc": ""},
	{"kind": "goblin_tent", "id": "", "name": "Goblin tent", "role": "", "desc": ""},
	{"kind": "goblin_war_hut", "id": "", "name": "Goblin war hut", "role": "", "desc": ""},
	{"kind": "goblin_forge", "id": "", "name": "Goblin forge", "role": "", "desc": ""},
	{"kind": "goblin_potion_hut", "id": "", "name": "Goblin potion hut", "role": "", "desc": ""},
	{"kind": "goblin_watchtower", "id": "", "name": "Goblin watchtower", "role": "", "desc": ""},
]
const COST_RESOURCES := ["lumber", "stone", "food", "bones"]

## The build menu, in order: LIST with each entry's `cost` filled in.
static var BUILDINGS: Array = []
static var _others: Array = []


## Reads the costs from Balance. Call again after changing them.
static func apply_balance() -> void:
	BUILDINGS = _with_costs(LIST)
	_others = _with_costs(OTHERS)


static func _with_costs(list: Array) -> Array:
	var out := []
	for entry: Dictionary in list:
		var b := entry.duplicate()
		var cost := {}
		for res: String in COST_RESOURCES:
			var n := roundi(Balance.num("cost_%s_%s" % [b.id, res]))
			if n > 0:
				cost[res] = n
		b["cost"] = cost
		out.append(b)
	return out


static func find(kind: String) -> Dictionary:
	if BUILDINGS.is_empty():
		apply_balance()
	for b: Dictionary in BUILDINGS + _others:
		if b.kind == kind:
			return b
	return {}


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
