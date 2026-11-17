class_name Texts
extends RefCounted
## Every line the game announces: the messages in the middle of the
## screen, the lines that float up from the creature, and the sentences
## Bless and Curse judge it by. They are read from Announcements.txt in the
## project folder when the game starts (Game calls load_file()), so they
## can be rewritten with a text editor. Texts.line("raid_ended") returns
## one; words in {braces} are filled in by the game, for example
## Texts.line("research_done", {"research": "bows"}).
## A line missing from the file falls back to the default here.

const PATH := "res://Announcements.txt"
const DEFAULTS := {
	# Messages in the middle of the screen.
	"choose_start": "{map}: choose where your village begins. Click a banner.",
	"raid_started": "Midnight: {goblins} goblins are marching on your village!",
	"raid_started_ogre": "Midnight: {goblins} goblins and an ogre are marching on your village!",
	"raid_started_ogres": "Midnight: {goblins} goblins and {ogres} ogres are marching on your village!",
	"raid_ended": "Morning: the goblins go home.",
	"bat_took": "A giant bat has snatched one of your villagers!",
	"raid_started_balrog": "The balrog marches with them!",
	"balrog_came": "A balrog has hatched at a goblin cave. It will guard the cave until it is full grown.",
	"balrog_grown": "The balrog is full grown. It will march with the next raid.",
	"balrog_died": "The balrog is dead!",
	"research_done": "The Blacksmith has finished: {research}.",
	"creature_knocked_out": "The {creature} is knocked out and shrinks! It will get up in {seconds} seconds.",
	"creature_got_up": "The {creature} is back on its feet.",
	# Bless and Curse, at the top of the screen.
	"judge_prompt": "{action}  ({ago} s ago)  Press {key} again to {spell}.",
	"judge_hover": "{action}  ({ago} s ago)",
	"judge_judged": "{action}  ({ago} s ago)  It has been blessed or cursed for that already.",
	"judge_nothing": "The {creature} has done nothing in the last {seconds} seconds.",
	"bless_result": "Blessed: {action}  Keenness {value} (from -100 to 100).",
	"curse_result": "Cursed: {action}  Keenness {value} (from -100 to 100).",
	# Lines that float up from the creature.
	"creature_blessed": "Blessed! ({value})",
	"creature_cursed": "Cursed! ({value})",
	"creature_confused": "The creature does not know what that was for",
	"watched_spell": "The creature watched you cast {spell} ({have}/{need})",
	"watched_store": "The creature watched the villagers store {amount} {resource} ({have}/{need})",
	"learned_fireball": "The creature learned to cast fireball!",
	"learned_rain": "The creature learned to cast rain!",
	"learned_roots": "The creature learned to cast roots!",
	"learned_lightning": "The creature learned to cast chain lightning!",
	"learned_blood": "The creature learned blood sacrifice!",
	"learned_lumber": "The creature learned to fetch trees!",
	"learned_stone": "The creature learned to fetch boulders!",
	"learned_food": "The creature learned to fetch food!",
	"cast_fireball": "The creature cast fireball",
	"cast_rain": "The creature cast rain",
	"cast_roots": "The creature cast roots",
	"cast_lightning": "The creature cast chain lightning",
	"cast_blood": "The creature blood sacrificed a villager",
	"brought_lumber": "The creature brought a tree to the storehouse: +{amount} lumber",
	"brought_stone": "The creature brought a boulder to the storehouse: +{amount} stone",
	"brought_food": "The creature brought food to the storehouse: +{amount} food",
	"stomped": "The creature stomped {them}",
	"threw": "The creature threw {them}",
	"ate": "The creature ate {them}",
	"fled": "The creature ran from the battle!",
	"cast_water": "The creature cast rain on the crops",
	"hid_in_shell": "The {creature} hid in its shell ({health}% health)",
	"stat_grew": "The {creature}'s {stat} grew! Level {level}",
	# What the creature did, as Bless and Curse judge it. Each one has its
	# own keenness, from -100 to 100.
	"action_stomp": "The creature stomped on enemies.",
	"action_water": "The creature cast rain on the crops.",
	"action_run": "The creature ran on all fours.",
	"action_fly": "The creature flew.",
	"action_shell_unharmed": "The creature hid in its shell when it was unharmed.",
	"action_shell_slightly": "The creature hid in its shell when it was slightly injured.",
	"action_shell_badly": "The creature hid in its shell when it was badly injured.",
	"action_shell_near_death": "The creature hid in its shell when it was near death.",
	"action_throw": "The creature threw enemies.",
	"action_eat": "The creature ate enemies.",
	"action_fireball": "The creature cast fireball.",
	"action_rain": "The creature cast rain.",
	"action_roots": "The creature cast roots.",
	"action_lightning": "The creature cast chain lightning.",
	"action_blood": "The creature made a blood sacrifice.",
	"action_explore": "The creature explored.",
	"action_lumber_battle": "The creature gathered lumber when battle raged.",
	"action_lumber_none": "The creature gathered lumber when there was none.",
	"action_lumber_plenty": "The creature gathered lumber when there was plenty.",
	"action_lumber_day": "The creature gathered lumber during the day.",
	"action_lumber_night": "The creature gathered lumber at night.",
	"action_stone_battle": "The creature gathered stone when battle raged.",
	"action_stone_none": "The creature gathered stone when there was none.",
	"action_stone_plenty": "The creature gathered stone when there was plenty.",
	"action_stone_day": "The creature gathered stone during the day.",
	"action_stone_night": "The creature gathered stone at night.",
	"action_food_battle": "The creature gathered food when battle raged.",
	"action_food_none": "The creature gathered food when there was none.",
	"action_food_plenty": "The creature gathered food when there was plenty.",
	"action_food_day": "The creature gathered food during the day.",
	"action_food_night": "The creature gathered food at night.",
	"action_flee_unharmed": "The creature ran from battle when it was unharmed.",
	"action_flee_slightly": "The creature ran from battle when it was slightly injured.",
	"action_flee_badly": "The creature ran from battle when it was badly injured.",
	"action_flee_near_death": "The creature ran from battle when it was near death.",
}

static var values := {}


## The line called `key`, with each {word} in it replaced from `fill`.
static func line(key: String, fill := {}) -> String:
	var text: String = values.get(key, DEFAULTS.get(key, key))
	return text.format(fill) if not fill.is_empty() else text


## Reads Announcements.txt. Lines look like "raid_ended = Morning: the goblins go home."
static func load_file() -> void:
	values = DEFAULTS.duplicate()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Announcements.txt not found: using the built-in text")
		return
	while not file.eof_reached():
		var raw := file.get_line().strip_edges()
		if raw == "" or raw.begins_with("#"):
			continue
		var at := raw.find("=")
		if at < 0:
			push_warning("Announcements.txt: '%s' needs an = sign" % raw)
			continue
		var key := raw.substr(0, at).strip_edges()
		if not DEFAULTS.has(key):
			push_warning("Announcements.txt: there is no line called '%s'" % key)
			continue
		values[key] = raw.substr(at + 1).strip_edges()
