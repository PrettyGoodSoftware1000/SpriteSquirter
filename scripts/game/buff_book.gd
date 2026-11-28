class_name BuffBook
extends RefCounted
## Creature buffs: researched at the Shrines (the Singing rocks) like the
## spells, then cast from the buff bar over the creature's health bar.
## A buff lasts Balance "buff_seconds_<id>", costs "buff_cost_<id>" animus,
## cannot be cast while it is on, and after it wears off waits
## "buff_cooldown_<id>" seconds before it can be cast again (one cooldown
## for the village, however many Shrines it has). The first buff costs
## "buff_research_first" animus to research and each one after
## "buff_research_step" more; each takes "buff_research_seconds".
## The effects live in Creature (start_buff(), buff_on()).
##
## A "toggle" buff (Flag Bearer) is on until it is clicked off: raising it
## costs "buff_cost_<id>" animus every time, and keeping it up costs
## "buff_upkeep_<id>" animus every "buff_upkeep_seconds_<id>" (PlayMode).

const BUFFS := [
	{"id": "growth", "name": "Creature Growth",
		"hint": "Your creature grows twice as fast for 2 minutes, shedding yellow sparkles."},
	{"id": "aura", "name": "Flaming Aura",
		"hint": "Flames fall from your creature for 30 seconds, burning every enemy within 10 metres."},
	{"id": "flag", "name": "Flag Bearer", "toggle": true,
		"hint": "Your fighters march on the nearest gooblin cave, fighting every gooblin and gooblin building on the way. 5 animus to raise the flag, then 1 every 5 minutes; click again to lower it."},
]
## How many buttons the buff bar has room for.
const SLOTS := 5


static func find(id: String) -> Dictionary:
	for buff in BUFFS:
		if buff.id == id:
			return buff
	return {}


static func index_of(id: String) -> int:
	for k in BUFFS.size():
		if BUFFS[k].id == id:
			return k
	return -1


## True for a buff that stays on until it is turned off (see the top).
static func is_toggle(id: String) -> bool:
	return bool(find(id).get("toggle", false))


static func cost(id: String) -> int:
	return roundi(Balance.num("buff_cost_" + id))


static func seconds(id: String) -> float:
	return Balance.num("buff_seconds_" + id)


static func cooldown(id: String) -> float:
	return Balance.num("buff_cooldown_" + id)


## What the next buff costs to research, with `known` already researched
## (or being researched).
static func research_cost(known: int) -> Dictionary:
	return {"animus": roundi(Balance.num("buff_research_first") + Balance.num("buff_research_step") * known)}
