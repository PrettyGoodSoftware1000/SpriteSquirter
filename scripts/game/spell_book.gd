class_name SpellBook
extends RefCounted
## The player's spells, in spell-bar order. Each one costs magicko. Key 1,
## 2, ... casts a spell where the mouse points; there is no spell in hand.
## A spell costs more for a while after it is cast (see PlayMode.spell_cost).
## The creature can learn the first five by watching (see CreatureMind).
## Bless and Condemn are cast on the creature itself and cannot be learned:
## the first tap of the key shows what the creature last did, the second
## blesses or condemns it for that.

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
]


static func index_of(id: String) -> int:
	for k in SPELLS.size():
		if SPELLS[k].id == id:
			return k
	return -1
