class_name BuildOrder
extends RefCounted
## What a neutral village builds, read from one of the owner's files in
## the NeutralVillages folder: Neutral_Build_Order_1.txt, _2.txt and so on
## (pick() chooses one at random). A file has two parts:
##
##   Treehouse (Home) = 2          every building it may build, and the most
##   Wheat field = 3               of each; the gameplay name in brackets is
##                                 only a reminder (Names.txt decides it)
##   [Build order]
##   Wheat field                   then what it builds first, one a line,
##   Tall house                    in order (by asset name)
##
## Lines starting with # are notes. A building not in the first part, or
## set to 0 there, is never built. Wheat fields are "Wheat field".

const DIR := "res://NeutralVillages/"
const PREFIX := "Neutral_Build_Order_"

## kind (BuildingCatalog) or "field" -> the most the village builds.
var limits := {}
## Kinds, in the order they are built.
var steps: Array[String] = []
## Which file it came from.
var path := ""


## The most of `kind` the village builds (0 if the file leaves it out).
func most(kind: String) -> int:
	return int(limits.get(kind, 0))


## Every build order file in DIR.
static func files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.begins_with(PREFIX) and name.ends_with(".txt"):
			out.append(DIR + name)
	out.sort()
	return out


## One of the build order files, at random (an empty order if there are none).
static func pick(rng: RandomNumberGenerator) -> BuildOrder:
	var all := files()
	if all.is_empty():
		push_warning("No %s*.txt in %s: neutral villages will build nothing" % [PREFIX, DIR])
		return BuildOrder.new()
	return read(all[rng.randi() % all.size()])


static func read(file_path: String) -> BuildOrder:
	var order := BuildOrder.new()
	order.path = file_path
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("Could not read %s" % file_path)
		return order
	var in_order := false
	var line_no := 0
	while not file.eof_reached():
		# (A note after # on a line is left out.)
		var line := file.get_line().get_slice("#", 0).strip_edges()
		line_no += 1
		if line == "":
			continue
		if line.begins_with("[") and line.to_lower().contains("build order"):
			in_order = true
			continue
		var name := line.get_slice("=", 0) if not in_order else line
		var kind := kind_of(name)
		if kind == "":
			push_warning("%s line %d: no building called '%s'" % [file_path.get_file(), line_no, name.strip_edges()])
			continue
		if in_order:
			order.steps.append(kind)
		elif "=" in line:
			order.limits[kind] = maxi(0, line.get_slice("=", 1).strip_edges().to_int())
	return order


## The kind for an asset name ("Tall house", "Tall house (Town guard)"),
## or "field" for a wheat field. "" if there is none.
static func kind_of(text: String) -> String:
	var name := text.get_slice("(", 0).strip_edges().to_lower()
	if name == "wheat field" or name == "field":
		return "field"
	for pair: Array in BuildingCatalog.ASSETS:
		if (pair[1] as String).to_lower() == name:
			return pair[0]
	return ""
