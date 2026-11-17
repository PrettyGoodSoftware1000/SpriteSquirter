class_name ActionTable
extends RefCounted
## The things the creature can be blessed or condemned for, read from
## Actions.csv in the project folder (a spreadsheet saved as CSV). The
## first row names each category; under it, from row 2 down, are the
## actions in that category, one id per cell, most general first:
##
##   Gathering wood ,Running from battle
##   lumber         ,flee
##   lumber_highest ,flee_unharmed
##   lumber_lowest  ,flee_slightly
##
## The first action in a column is the category itself (what the creature
## did); each one under it is that same thing done under a condition,
## written as <first action>_<condition>. Announcements.txt has the
## sentence for each (action_<id>). The conditions the game knows:
##
##   gathering (lumber, stone, food): highest (it was the resource the
##     village had most of), lowest (the one it had least of), none (the
##     village had none), plenty (over CreatureMind.PLENTY), battle (a
##     battle was on), day, night
##   running from battle, hiding in shell: unharmed, slightly (slightly
##     injured), badly (badly injured), near_death
##   rain: fire (cast on a fire), crops (cast on growing wheat)
##
## Bless and Condemn judge what the creature last did: the first action in
## its column whose condition held and that is not cooling down (see
## CreatureMind.judge_target()).

const PATH := "res://Actions.csv"
## Used when Actions.csv is missing: the same columns as the one shipped.
const DEFAULT := [
	["Gathering wood", ["lumber", "lumber_highest", "lumber_lowest", "lumber_none", "lumber_plenty", "lumber_battle", "lumber_day", "lumber_night"]],
	["Gathering stone", ["stone", "stone_highest", "stone_lowest", "stone_none", "stone_plenty", "stone_battle", "stone_day", "stone_night"]],
	["Gathering food", ["food", "food_highest", "food_lowest", "food_none", "food_plenty", "food_battle", "food_day", "food_night"]],
	["Stomping", ["stomp"]], ["Throwing", ["throw"]], ["Eating", ["eat"]],
	["Fireball", ["fireball"]], ["Chain lightning", ["lightning"]], ["Roots", ["roots"]],
	["Rain", ["rain", "rain_fire", "rain_crops"]], ["Blood sacrifice", ["blood"]], ["Exploring", ["explore"]],
	["Running from battle", ["flee", "flee_unharmed", "flee_slightly", "flee_badly", "flee_near_death"]],
	["Hiding in shell", ["shell", "shell_unharmed", "shell_slightly", "shell_badly", "shell_near_death"]],
]

## first action (the category's id) -> the actions in its column, in order.
static var columns := {}
## first action -> the category's name from row 1.
static var names := {}


static func load_file() -> void:
	columns = {}
	names = {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Actions.csv not found: using the built-in actions")
		for entry: Array in DEFAULT:
			_add(entry[0], entry[1])
		return
	var header := file.get_csv_line()
	var cells: Array = []
	for k in header.size():
		cells.append([])
	while not file.eof_reached():
		var row := file.get_csv_line()
		for k in mini(row.size(), header.size()):
			var id := row[k].strip_edges().to_lower()
			if id != "":
				(cells[k] as Array).append(id)
	for k in header.size():
		if not (cells[k] as Array).is_empty():
			_add(header[k].strip_edges(), cells[k])


static func _add(title: String, ids: Array) -> void:
	var list: Array[String] = []
	for id: String in ids:
		list.append(id)
	columns[list[0]] = list
	names[list[0]] = title


## The actions in `category`'s column (just the category if it has none).
static func column(category: String) -> Array[String]:
	if columns.is_empty():
		load_file()
	var list: Array[String] = [category]
	if columns.has(category):
		list.assign(columns[category])
	return list


## Every action in the table.
static func all() -> Array[String]:
	if columns.is_empty():
		load_file()
	var out: Array[String] = []
	for category: String in columns:
		out.append_array(columns[category])
	return out


## The condition an action in `category` stands for ("" for the category
## itself).
static func condition(category: String, action: String) -> String:
	if action == category:
		return ""
	return action.trim_prefix(category + "_")
