class_name SpellBook
extends RefCounted
## The player's spells, in spell-bar order. Each one costs magicko. Key 1,
## 2, ... casts a spell where the mouse points; there is no spell in hand.
## A spell costs more for a while after it is cast (see PlayMode.spell_cost).
## The creature can learn the first five by watching (see CreatureMind).
## Bless and Condemn are cast on the creature itself and cannot be learned:
## the first tap of the key shows what the creature last did, the second
## blesses or condemns it for that.
##
## Every spell must first be researched at the Shrine (the Singing rocks):
## click it for its menu. Each costs Balance "spell_research_magicko" and
## takes "spell_research_seconds". The spell bar shows the spells the
## village knows, in the order it learned them (PlayerVillage.spell_order),
## and the player can drag them about.

const SPELLS := [
	{"id": "fireball", "name": "Fireball", "cost": 5,
		"hint": "Throws a fireball where the mouse points."},
	{"id": "rain", "name": "Rain", "cost": 15,
		"hint": "Makes it rain where the mouse points. Rain puts out fires and soaks the ground."},
	{"id": "roots", "name": "Roots", "cost": 20,
		"hint": "Grows roots where the mouse points, for 20 seconds. Goblins and the tortoise are held fast; your own people wade through at a quarter of their speed."},
	{"id": "lightning", "name": "Chain Lightning", "cost": 20,
		"hint": "Strikes near the mouse and jumps from one to the next. Anything wet from rain or standing in water takes double. It does not spare your own people."},
	{"id": "blood", "name": "Blood Sacrifice", "cost": 0,
		"hint": "Sacrifices the villager of yours nearest the mouse: magicko comes in twice as fast for 30 seconds."},
	{"id": "bless", "name": "Bless", "cost": 10,
		"hint": "Take it in hand to see what your creature last did; click anywhere to bless it: its affinity for that goes up 10."},
	{"id": "condemn", "name": "Condemn", "cost": 10,
		"hint": "Take it in hand to see what your creature last did; click anywhere to condemn it: its affinity for that goes down 10."},
	{"id": "gnomes", "name": "Gnomish Subcontractors", "cost": 20,
		"hint": "Click a building under construction: five gnomes come running from 50 m away and help build it."},
	{"id": "charm", "name": "Charm Offensive", "cost": 25,
		"hint": "Pink hearts fill the spot: about half the goblins caught in it are charmed for 60 seconds and fight their own kind."},
]


## True for a spell that must be researched at the Shrine before it is
## cast: all of them.
static func needs_research(id: String) -> bool:
	return index_of(id) >= 0


## What researching a spell costs (in magicko).
static func research_cost(_id: String) -> Dictionary:
	var n := roundi(Balance.num("spell_research_magicko"))
	return {"magicko": n} if n > 0 else {}


static func research_seconds(_id: String) -> float:
	return Balance.num("spell_research_seconds")


static func find(id: String) -> Dictionary:
	var k := index_of(id)
	return SPELLS[k] if k >= 0 else {}


static func index_of(id: String) -> int:
	for k in SPELLS.size():
		if SPELLS[k].id == id:
			return k
	return -1
