class_name Texts
extends RefCounted
## Every line the game announces: the messages in the middle of the
## screen, the lines that float up from the creature, and what Bless and
## Condemn say. (The sentence for each thing the creature did is in
## Actions.csv.) They are read from Announcements.txt in the
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
	"research_done": "The {place} has finished: {research}.",
	"spell_researched": "The {place} has taught you a new spell: {spell}.",
	"spell_unlocked": "Your {creature} has grown: you can now cast {spell}.",
	# Floats up over the Storehouse (no oftener than Balance "food_warning_seconds").
	"out_of_food": "Out of food! No births, and people will starve",
	"starving": "Starving!",
	"villager_stuck": "Villager stuck!",
	"creature_defends": "To the defence of the village!",
	"buff_researched": "The Shrine has found a new creature buff: {buff}.",
	"fey_birthing": "The fey are about: children come twice as fast, and every one is born a girl with wings.",
	"creature_died": "The {creature} has died! Bring it back to life at a Shrine for {animus} animus.",
	"creature_resurrected": "The {creature} lives again!",
	"resurrect_no_shrine": "The {creature} can only be brought back to life at a Shrine. Build one first.",
	"resurrect_no_animus": "Bringing the {creature} back to life takes {animus} animus. You have {have}.",
	# Bless and Condemn, at the top of the screen.
	"judge_prompt": "{action}  ({ago} s ago)  Click anywhere to {spell}, or press {key} again to cancel.",
	"judge_hover": "{action}  ({ago} s ago)",
	"judge_cooling": "{action}  The {creature} was blessed or condemned for that too lately: it can be again in {seconds} s.",
	"judge_nothing": "The {creature} has done nothing in the last {seconds} seconds.",
	"bless_result": "Blessed: {action}  Affinity {value} (from -100 to 100). Again in {seconds} s.",
	"condemn_result": "Condemned: {action}  Affinity {value} (from -100 to 100). Again in {seconds} s.",
	# Lines that float up from the creature.
	"creature_blessed": "Blessed! ({value})",
	"creature_condemned": "Condemned! ({value})",
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
	"forest_seeded": "The creature tossed a magic acorn!",
	"ate": "The creature ate {them}",
	"fled": "The creature ran from the battle!",
	"cast_water": "The creature cast rain on the crops",
	"hid_in_shell": "The {creature} hid in its shell ({health}% health)",
	"gnomes_came": "Gnomish Subcontractors are on their way!",
	"gnomes_dont_stack": "Gnomish Subcontractors don't stack. Gnomes are union workers, and it's in all their contracts.",
	"stat_grew": "The {creature}'s {stat} grew! Level {level}",
	# (The sentence for each thing the creature did is in Actions.csv:
	# see ActionTable.)
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
		# (Write \n for a line break.)
		values[key] = raw.substr(at + 1).strip_edges().replace("\\n", "\n")
