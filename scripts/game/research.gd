class_name Research
extends RefCounted
## What the village can research at a Blacksmith. One thing at a time; it
## is paid for up front and takes `seconds` while a Blacksmith stands.
## The effects live where they apply: PlayerVillage (gathering rates,
## archers) and Villager (sword damage).

const ITEMS := [
	{"id": "swords", "name": "Sharper swords", "seconds": 300.0, "cost": {"lumber": 30, "stone": 60},
		"desc": "Warriors do 50% more damage"},
	{"id": "bows", "name": "Bows", "seconds": 180.0, "cost": {"lumber": 80, "stone": 10},
		"desc": "Each guard building can train 2 archers"},
	{"id": "pitchforks", "name": "Pitchforks", "seconds": 120.0, "cost": {"lumber": 40, "stone": 15},
		"desc": "Food is gathered and reaped twice as fast"},
	{"id": "picks", "name": "Mining picks", "seconds": 120.0, "cost": {"lumber": 30, "stone": 30},
		"desc": "Stone is mined twice as fast"},
	{"id": "axes", "name": "Axes", "seconds": 120.0, "cost": {"lumber": 30, "stone": 30},
		"desc": "Lumber is cut twice as fast"},
]
## Which research speeds up which resource.
const TOOLS := {"food": "pitchforks", "stone": "picks", "lumber": "axes"}
const TOOL_BONUS := 2.0


static func find(id: String) -> Dictionary:
	for item in ITEMS:
		if item.id == id:
			return item
	return {}
