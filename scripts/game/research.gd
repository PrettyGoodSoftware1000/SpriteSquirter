class_name Research
extends RefCounted
## What the village can research, and where: at a Blacksmith ("smith") or
## at a Wizardry tower ("wizard"); click the building for its menu. Each
## building researches one thing at a time; it is paid for up front and
## takes `seconds` while such a building stands. An item with `needs`
## waits until that one is done (the tool tiers go 1, 2, 3).
## The effects live where they apply: PlayerVillage (gathering rates,
## wheelbarrows, archers), Villager (sword damage) and PlayMode (Overcast).

const ITEMS := [
	{"id": "swords", "place": "smith", "name": "Sharper swords", "seconds": 300.0, "cost": {"lumber": 30, "stone": 60},
		"desc": "Warriors do 50% more damage"},
	{"id": "bows", "place": "smith", "name": "Bows", "seconds": 180.0, "cost": {"lumber": 80, "stone": 10},
		"desc": "Each guard building can train 2 archers"},
	{"id": "wheelbarrows", "place": "smith", "name": "Wheelbarrows", "seconds": 120.0, "cost": {"lumber": 60, "stone": 20},
		"desc": "Workers carry three times as much home"},
	{"id": "pitchforks_1", "place": "smith", "name": "Pitchforks I", "seconds": 60.0, "cost": {"lumber": 15, "stone": 5},
		"desc": "Food gathered faster (+50% after III)"},
	{"id": "pitchforks_2", "place": "smith", "name": "Pitchforks II", "seconds": 80.0, "cost": {"lumber": 25, "stone": 10}, "needs": "pitchforks_1",
		"desc": "Food gathered faster still"},
	{"id": "pitchforks_3", "place": "smith", "name": "Pitchforks III", "seconds": 100.0, "cost": {"lumber": 35, "stone": 15}, "needs": "pitchforks_2",
		"desc": "Food gathered 50% faster in all"},
	{"id": "picks_1", "place": "smith", "name": "Mining picks I", "seconds": 60.0, "cost": {"lumber": 10, "stone": 10},
		"desc": "Stone mined faster (+50% after III)"},
	{"id": "picks_2", "place": "smith", "name": "Mining picks II", "seconds": 80.0, "cost": {"lumber": 15, "stone": 20}, "needs": "picks_1",
		"desc": "Stone mined faster still"},
	{"id": "picks_3", "place": "smith", "name": "Mining picks III", "seconds": 100.0, "cost": {"lumber": 20, "stone": 30}, "needs": "picks_2",
		"desc": "Stone mined 50% faster in all"},
	{"id": "axes_1", "place": "smith", "name": "Axes I", "seconds": 60.0, "cost": {"lumber": 10, "stone": 10},
		"desc": "Lumber cut faster (+50% after III)"},
	{"id": "axes_2", "place": "smith", "name": "Axes II", "seconds": 80.0, "cost": {"lumber": 15, "stone": 20}, "needs": "axes_1",
		"desc": "Lumber cut faster still"},
	{"id": "axes_3", "place": "smith", "name": "Axes III", "seconds": 100.0, "cost": {"lumber": 20, "stone": 30}, "needs": "axes_2",
		"desc": "Lumber cut 50% faster in all"},
	{"id": "overcast", "place": "wizard", "name": "Overcast", "seconds": 60.0, "cost": {"animus": 10},
		"desc": "Cast a spell once while it cools down, for twice the magicko"},
]
## Which research speeds up which resource (in tiers: "<name>_1", "_2", "_3").
const TOOLS := {"food": "pitchforks", "stone": "picks", "lumber": "axes"}
const TIERS := 3


static func find(id: String) -> Dictionary:
	for item in ITEMS:
		if item.id == id:
			return item
	return {}
