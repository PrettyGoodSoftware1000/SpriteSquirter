class_name ActionTable
extends RefCounted
## The things the creature can be blessed or condemned for, read from
## Actions.csv in the project folder (the owner's spreadsheet, saved as
## CSV). Row 1 names each category; under it are its actions, the most
## specific at the top and the most general at the bottom. Each cell is
## the sentence the player sees, with what must have been true for it in
## square brackets at the end:
##
##   Gathering wood
##   The creature gathered some wood. That was the lowest resource in stock. [Gathered wood when it was the lowest stocked resource]
##   The creature gathered some wood.
##
## A cell with no brackets is the category's general action: it always
## applies. In the sentence, [enemy name] becomes the enemy's name (goblin,
## ogre, giant bat, balrog) and [a or an] the right word before it.
##
## The game reads each bracket by its key words (see _parse_condition());
## numbers in it are used as they are written ("over 250 in storage",
## "less than 25% health", "magicko was under 25 points"). A bracket with
## no words the game knows is reported in the Output panel and never
## applies, rather than being guessed at.
##
## The category comes from the words in its title in row 1 (wood, stone,
## food, stomp, throw, eat, fireball, lightning, roots, rain, sacrifice,
## exploring, running, shell).
##
## Each action is given an id from its category and its condition
## (lumber_lowest, flee_health_under_25, fireball_villager, ...), which is
## what its affinity is kept under.

const PATH := "res://Actions.csv"
## Category id -> words in a column title that mean it (first match wins).
const CATEGORY_WORDS := [
	["lumber", ["wood", "lumber"]], ["stone", ["stone"]], ["food", ["food"]],
	["stomp", ["stomp"]], ["throw", ["throw"]], ["eat", ["eat"]],
	["fireball", ["fireball"]], ["lightning", ["lightning"]], ["roots", ["root"]],
	["rain", ["rain"]], ["blood", ["sacrific", "blood"]], ["seed", ["seeding", "acorn"]], ["explore", ["explor"]],
	["flee", ["running", "flee", "ran from"]], ["shell", ["shell", "hid"]],
]
## Placeholders in a sentence that are not conditions.
const PLACEHOLDERS := ["enemy name", "a or an"]
## Categories whose rows are about how hurt the creature was, what it aimed
## at, or how much of a resource there was.
const HEALTH := ["flee", "shell"]
const TARGETED := ["fireball", "lightning", "roots", "rain"]
const GATHERING := ["lumber", "stone", "food"]

## category id -> its actions, top to bottom: each {id, sentence,
## condition (the bracket's words), tests}. A test is an Array: its name,
## then any numbers (see CreatureMind.passes()).
static var columns := {}
## category id -> its title from row 1.
static var names := {}
## Brackets the game could not read: the text of each.
static var unknown: Array[String] = []


static func load_file(path := PATH) -> void:
	columns = {}
	names = {}
	unknown.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Actions.csv not found: the creature has one general action in each category")
		for pair: Array in CATEGORY_WORDS:
			columns[pair[0]] = [{"id": pair[0], "sentence": "", "condition": "", "tests": []}]
			names[pair[0]] = pair[0]
		return
	var header := file.get_csv_line()
	var cells: Array = []
	for k in header.size():
		cells.append([])
	while not file.eof_reached():
		var row := file.get_csv_line()
		for k in mini(row.size(), header.size()):
			if row[k].strip_edges() != "":
				(cells[k] as Array).append(row[k].strip_edges())
	for k in header.size():
		var category := category_of(header[k])
		if category == "":
			if header[k].strip_edges() != "":
				push_warning("Actions.csv: no category for the column '%s'" % header[k])
			continue
		names[category] = header[k].strip_edges()
		var actions: Array = []
		var used := {}
		for text: String in cells[k]:
			var action := _parse_cell(category, text)
			var id: String = action.id
			if used.has(id):
				id += "_%d" % (actions.size() + 2)
				action.id = id
			used[id] = true
			actions.append(action)
		columns[category] = actions
	for text in unknown:
		push_warning("Actions.csv: the game does not know what this condition means, so it never applies: [%s]" % text)


## The category a column title stands for, or "".
static func category_of(title: String) -> String:
	var t := title.to_lower()
	for pair: Array in CATEGORY_WORDS:
		for word: String in pair[1]:
			if word in t:
				return pair[0]
	return ""


## A cell: the sentence, and the condition in the brackets at its end.
## Line breaks in the cell (a new line in the Google Sheet, or \n written
## out) are line breaks in what the game shows.
static func _parse_cell(category: String, raw: String) -> Dictionary:
	var text := raw.replace("\r\n", "\n").replace("\r", "\n").replace("\\n", "\n")
	var sentence := text
	var condition := ""
	var re := RegEx.create_from_string("\\[([^\\]]*)\\]\\s*$")
	var found := re.search(text)
	if found != null and not PLACEHOLDERS.has(found.get_string(1).strip_edges().to_lower()):
		condition = found.get_string(1).strip_edges()
		sentence = text.substr(0, found.get_start()).strip_edges()
	var action := {"id": category, "sentence": sentence, "condition": condition, "tests": []}
	if condition == "":
		return action
	var parsed := _parse_condition(category, condition)
	action.tests = parsed.tests
	action.id = category + "_" + parsed.slug
	if (parsed.tests as Array).is_empty():
		action.tests = [["never"]]
		action.id = category + "_unknown"
		unknown.append(condition)
	return action


## The tests a condition stands for, and a short name for it.
static func _parse_condition(category: String, condition: String) -> Dictionary:
	var c := " " + condition.to_lower() + " "
	var tests: Array = []
	var slug: PackedStringArray = []
	if GATHERING.has(category):
		if "highest" in c:
			tests.append(["highest"])
			slug.append("highest")
		if "lowest" in c:
			tests.append(["lowest"])
			slug.append("lowest")
		if "zero" in c or _number_after(c, ["at ", "was "]) == 0.0:
			tests.append(["stock_at_most", 0.0])
			slug.append("none")
		var over := _number_after(c, ["over "])
		if over > 0.0:
			tests.append(["stock_above", over])
			slug.append("plenty")
	if HEALTH.has(category):
		var range_match := RegEx.create_from_string("(\\d+)\\s*%\\s*to\\s*(\\d+)\\s*%").search(c)
		if "full health" in c:
			tests.append(["health_at_least", 0.99])
			slug.append("health_full")
		elif range_match != null:
			var a := range_match.get_string(1).to_float() / 100.0
			var b := range_match.get_string(2).to_float() / 100.0
			tests.append(["health_between", minf(a, b), maxf(a, b)])
			slug.append("health_%d_%d" % [roundi(minf(a, b) * 100.0), roundi(maxf(a, b) * 100.0)])
		else:
			var below := _number_after(c, ["less than ", "under ", "below "])
			var above := _number_after(c, ["over ", "more than ", "above "])
			if below >= 0.0:
				tests.append(["health_below", below / 100.0])
				slug.append("health_under_%d" % roundi(below))
			elif above >= 0.0:
				tests.append(["health_above", above / 100.0])
				slug.append("health_over_%d" % roundi(above))
	if category == "blood":
		if "magicko" in c:
			var under := _number_after(c, ["magicko was under ", "magicko under ", "magicko was below "])
			var over := _number_after(c, ["magicko was over ", "magicko over ", "magicko was above "])
			if under >= 0.0:
				tests.append(["magicko_below", under])
				slug.append("magicko_under_%d" % roundi(under))
			if over >= 0.0:
				tests.append(["magicko_above", over])
				slug.append("magicko_over_%d" % roundi(over))
		if "no housing" in c or "housing was full" in c:
			tests.append(["housing_full"])
			slug.append("no_housing")
		elif "housing" in c:
			tests.append(["housing_free"])
			slug.append("housing")
	if TARGETED.has(category):
		var target := ""
		if "nothing" in c or "nobody" in c or "no target" in c or "no fire" in c:
			target = "nothing"
		elif "enemy building" in c or "goblin building" in c:
			target = "enemy_building"
		elif "friendly building" in c or "our building" in c or "our own building" in c:
			target = "our_building"
		elif "villager" in c:
			target = "villager"
		elif "tree" in c:
			target = "tree"
		elif "crops" in c:
			target = "crops"
		elif RegEx.create_from_string("\\bfire\\b").search(c) != null:
			target = "fire"
		elif "enem" in c:
			target = "enemy"
		if target != "":
			tests.append(["target", target])
			slug.append(target)
		if "wet" in c:
			tests.append(["wet"])
			slug.append("wet")
		var crowd := _number_before(c, " or more")
		if crowd > 0.0:
			tests.append(["hits_at_least", crowd])
			slug.append("crowd_%d" % roundi(crowd))
	if "battle" in c or "combat" in c or "invad" in c:
		tests.append(["battle"])
		slug.append("battle")
	return {"tests": tests, "slug": "_".join(slug)}


## The number written straight after one of `words` in `text`, or -1.
static func _number_after(text: String, words: Array) -> float:
	for word: String in words:
		var at := text.find(word)
		if at < 0:
			continue
		var m := RegEx.create_from_string("^\\s*(\\d+(?:\\.\\d+)?)").search(text.substr(at + word.length()))
		if m != null:
			return m.get_string(1).to_float()
	return -1.0


## The number written straight before `word` in `text`, or -1.
static func _number_before(text: String, word: String) -> float:
	var at := text.find(word)
	if at < 0:
		return -1.0
	var m := RegEx.create_from_string("(\\d+)\\s*$").search(text.substr(0, at))
	return m.get_string(1).to_float() if m != null else -1.0


## The actions of `category`, top to bottom (see columns).
static func column(category: String) -> Array:
	if columns.is_empty():
		load_file()
	return columns.get(category, [{"id": category, "sentence": "", "condition": "", "tests": []}])


## The action with id `id`, or {}.
static func find(id: String) -> Dictionary:
	if columns.is_empty():
		load_file()
	for category: String in columns:
		for action: Dictionary in columns[category]:
			if action.id == id:
				return action
	return {}


## Every action's id.
static func all() -> Array[String]:
	if columns.is_empty():
		load_file()
	var out: Array[String] = []
	for category: String in columns:
		for action: Dictionary in columns[category]:
			out.append(action.id)
	return out


## `sentence` with [enemy name] and [a or an] filled in.
static func fill(sentence: String, enemy: String) -> String:
	var text := sentence.replace("[enemy name]", enemy if enemy != "" else "enemy")
	var re := RegEx.create_from_string("\\[a or an\\]\\s+(\\S)")
	var m := re.search(text)
	while m != null:
		var first := m.get_string(1).to_lower()
		var word := "an " if "aeiou".contains(first) else "a "
		text = text.substr(0, m.get_start()) + word + m.get_string(1) + text.substr(m.get_end())
		m = re.search(text)
	return text.replace("[a or an]", "a")
