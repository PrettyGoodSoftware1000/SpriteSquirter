class_name SpellBook
extends RefCounted
## The player's spells, in spell-bar order. Each one costs magicko and has
## a cooldown. Keys 1, 2, ... pick a spell, then a click casts it.
## The creature can learn the first four by watching (see CreatureMind).
## Bless and Curse are cast on the creature itself and cannot be learned.

const SPELLS := [
	{"id": "fireball", "name": "Fireball", "cost": 5, "cooldown": 0.25,
		"hint": "Click to throw a fireball from the cursor."},
	{"id": "rain", "name": "Rain", "cost": 15, "cooldown": 3.0,
		"hint": "Click to make it rain there. Rain puts out fires and soaks the ground."},
	{"id": "roots", "name": "Roots", "cost": 20, "cooldown": 6.0,
		"hint": "Click to grow roots there for 20 seconds. Goblins and the tortoise are held fast; your own people wade through at a quarter of their speed."},
	{"id": "blood", "name": "Blood Sacrifice", "cost": 0, "cooldown": 2.0,
		"hint": "Click near one of your villagers to sacrifice them: magicko comes in twice as fast for 30 seconds."},
	{"id": "bless", "name": "Bless", "cost": 10, "cooldown": 1.0,
		"hint": "Click your creature just after it has done something you like: it will be keener to do it again."},
	{"id": "curse", "name": "Curse", "cost": 10, "cooldown": 1.0,
		"hint": "Click your creature just after it has done something you dislike: it will be less keen to do it again."},
]


static func index_of(id: String) -> int:
	for k in SPELLS.size():
		if SPELLS[k].id == id:
			return k
	return -1
