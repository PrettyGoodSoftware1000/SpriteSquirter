class_name BuildingCatalog
extends RefCounted
## The things the player can order from the build menu (B / Backspace):
## their names, what they cost and what they are for. The look of each
## building comes from BuildingFactory.
##
## Roles:
##   home   adds housing, so more villagers can be born
##   store  the Storehouse: villagers carry what they gather to it
##   guard  the Town guard: turns villagers into soldiers
##   field  a wheat field, drawn on the ground instead of placed (CropField)

## Housing every village has before it builds anything.
const BASE_HOUSING := 10

const BUILDINGS := [
	{"kind": "tall_house", "name": "Home", "role": "home", "housing": 6,
		"cost": {"lumber": 40, "stone": 15}, "desc": "Room for 6 more villagers"},
	{"kind": "store", "name": "Storehouse", "role": "store",
		"cost": {"lumber": 35, "stone": 10}, "desc": "Villagers carry resources here"},
	{"kind": "moon_tower", "name": "Town guard", "role": "guard",
		"cost": {"lumber": 30, "stone": 40, "food": 20}, "desc": "Trains 4 villagers as soldiers"},
	{"kind": "field", "name": "Wheat field", "role": "field",
		"cost": {}, "desc": "Drag out a square. 1 lumber per 10 m2"},
	{"kind": "mushroom_house", "name": "Mushroom cottage", "role": "home", "housing": 3,
		"cost": {"lumber": 15, "stone": 5, "food": 30}, "desc": "Room for 3 more villagers"},
	{"kind": "windmill", "name": "Windmill", "role": "",
		"cost": {"lumber": 45, "stone": 20}, "desc": "No use yet"},
	{"kind": "crystal_tower", "name": "Crystal tower", "role": "",
		"cost": {"lumber": 20, "stone": 45}, "desc": "No use yet"},
	{"kind": "singing_rocks", "name": "Singing rocks", "role": "",
		"cost": {"stone": 50}, "desc": "No use yet"},
]


static func find(kind: String) -> Dictionary:
	for b in BUILDINGS:
		if b.kind == kind:
			return b
	return {}


static func housing(kind: String) -> int:
	return find(kind).get("housing", 0)


static func role(kind: String) -> String:
	return find(kind).get("role", "")


## "40 lumber  15 stone"
static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in PlayerVillage.RESOURCES:
		if cost.has(res):
			parts.append("%d %s" % [cost[res], res])
	return "  ".join(parts)
