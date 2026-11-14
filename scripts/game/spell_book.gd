class_name SpellBook
extends RefCounted
## The player's spells, in spell-bar order. Each one costs magicko and has
## a cooldown. Keys 1, 2, ... pick a spell; F always throws a fireball.

const SPELLS := [
	{"id": "fireball", "name": "Fireball", "cost": 5, "cooldown": 0.25,
		"hint": "Click to throw a fireball from the cursor. (F works any time.)"},
	{"id": "rain", "name": "Rain", "cost": 15, "cooldown": 3.0,
		"hint": "Click to make it rain there. Rain puts out fires and soaks the ground."},
	{"id": "roots", "name": "Roots", "cost": 20, "cooldown": 6.0,
		"hint": "Click to grow roots there. Everything in the circle is held fast for a minute."},
	{"id": "blood", "name": "Blood Sacrifice", "cost": 0, "cooldown": 2.0,
		"hint": "Click near one of your villagers to sacrifice them: magicko comes in twice as fast for 30 seconds."},
]


static func index_of(id: String) -> int:
	for k in SPELLS.size():
		if SPELLS[k].id == id:
			return k
	return -1
