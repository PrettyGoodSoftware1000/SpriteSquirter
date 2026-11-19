class_name SpellBook
extends RefCounted
## The player's spells. Each one costs magicko (Balance "spell_cost_<id>"). Key 1,
## 2, ... casts a spell where the mouse points; there is no spell in hand.
## A spell costs more for a while after it is cast (see PlayMode.spell_cost).
## The creature can learn the first five by watching (see CreatureMind).
## Bless and Condemn are cast on the creature itself and cannot be learned:
## the first tap of the key shows what the creature last did, the second
## blesses or condemns it for that.
##
## Every spell must first be researched at the Shrine (the Singing rocks):
## click it for its menu. The first costs Balance "spell_research_animus"
## animus, and each after "spell_research_animus_step" more; each takes
## "spell_research_seconds". The spell bar shows the spells the
## village knows, in the order it learned them (PlayerVillage.spell_order),
## and the player can drag them about.

const SPELLS := [
	{"id": "fireball", "name": "Fireball",
		"hint": "Throws a fireball where the mouse points."},
	{"id": "rain", "name": "Rain",
		"hint": "Makes it rain where the mouse points. Rain puts out fires and soaks the ground."},
	{"id": "roots", "name": "Roots",
		"hint": "Grows roots where the mouse points, for 20 seconds. Goblins and the tortoise are held fast; your own people wade through at a quarter of their speed."},
	{"id": "lightning", "name": "Chain Lightning",
		"hint": "Strikes near the mouse and jumps from one to the next. Anything wet from rain or standing in water takes double. It does not spare your own people."},
	{"id": "blood", "name": "Blood Sacrifice",
		"hint": "Sacrifices the villager of yours nearest the mouse: magicko comes in twice as fast for 30 seconds."},
	{"id": "bless", "name": "Bless",
		"hint": "Take it in hand to see what your creature last did; click anywhere to bless it: its affinity for that goes up 10."},
	{"id": "condemn", "name": "Condemn",
		"hint": "Take it in hand to see what your creature last did; click anywhere to condemn it: its affinity for that goes down 10."},
	{"id": "gnomes", "name": "Gnomish Subcontractors",
		"hint": "Click a building under construction: five gnomes come running from 50 m away and help build it."},
	{"id": "fey", "name": "Kinky Fey Stuff",
		"hint": "Click near a villager at work: a pixie flies from the nearest tree, and off they go into a building for 2 minutes. Then births come twice as fast for 2 minutes, and every child born is a winged fey girl."},
	{"id": "charm", "name": "Charm Offensive",
		"hint": "Pink hearts fill the spot: about half the goblins caught in it are charmed for 60 seconds and fight their own kind."},
]


## Spells that come with the creature's growth instead of research: id ->
## the growth level (tenths paid for) that unlocks it.
const GROWTH_SPELLS := {"bless": 1, "condemn": 2}


## True for a spell that must be researched at the Shrine before it is
## cast: all but Bless and Condemn, which come as the creature grows.
static func needs_research(id: String) -> bool:
	return index_of(id) >= 0 and not GROWTH_SPELLS.has(id)


## What researching a spell costs (in animus), when the village already
## knows `known` spells: 1 for the first, 2 for the second, and so on.
static func research_cost(known: int) -> Dictionary:
	var n := roundi(Balance.num("spell_research_animus") + known * Balance.num("spell_research_animus_step"))
	return {"animus": n} if n > 0 else {}


static func research_seconds(_id: String) -> float:
	return Balance.num("spell_research_seconds")


static func find(id: String) -> Dictionary:
	var k := index_of(id)
	return SPELLS[k] if k >= 0 else {}


## What spell `id` costs to cast, in magicko (Balance "spell_cost_<id>";
## more for a while after it is cast, see PlayMode.spell_cost()).
static func cost(id: String) -> int:
	return roundi(Balance.num("spell_cost_" + id))


## How long spell `id` cools down after it is cast (Balance
## "spell_cooldown_<id>"), in seconds.
static func cooldown(id: String) -> float:
	return Balance.num("spell_cooldown_" + id)


static func index_of(id: String) -> int:
	for k in SPELLS.size():
		if SPELLS[k].id == id:
			return k
	return -1
