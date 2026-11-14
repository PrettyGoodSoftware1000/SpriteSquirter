class_name BuildingCatalog
extends RefCounted
## The buildings the player can order from the build menu (B / Backspace):
## what they cost and how many villagers they house. The look of each one
## comes from BuildingFactory.

## Housing every village has before it builds anything.
const BASE_HOUSING := 10

const BUILDINGS := [
	{"kind": "tall_house", "name": "Tall house", "cost": {"lumber": 40, "stone": 15}, "housing": 6},
	{"kind": "mushroom_house", "name": "Mushroom house", "cost": {"lumber": 15, "stone": 5, "food": 30}, "housing": 6},
	{"kind": "store", "name": "Store tree", "cost": {"lumber": 35, "stone": 10, "food": 20}, "housing": 4},
	{"kind": "windmill", "name": "Windmill", "cost": {"lumber": 45, "stone": 20}, "housing": 3},
	{"kind": "crystal_tower", "name": "Crystal tower", "cost": {"lumber": 20, "stone": 45}, "housing": 3},
	{"kind": "moon_tower", "name": "Moon tower", "cost": {"lumber": 25, "stone": 35}, "housing": 3},
	{"kind": "singing_rocks", "name": "Singing rocks", "cost": {"stone": 50}, "housing": 2},
]


static func find(kind: String) -> Dictionary:
	for b in BUILDINGS:
		if b.kind == kind:
			return b
	return {}


static func housing(kind: String) -> int:
	var b := find(kind)
	return b.get("housing", 3)


## "40 lumber  15 stone"
static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in PlayerVillage.RESOURCES:
		if cost.has(res):
			parts.append("%d %s" % [cost[res], res])
	return "  ".join(parts)
