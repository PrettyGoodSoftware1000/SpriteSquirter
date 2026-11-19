class_name SpellLayout
extends RefCounted
## Remembers, from one game to the next, where the player put each spell on
## the spell bar (its slot: 0-9 the first row, 10-19 the second, 20-29 the
## third) and how many rows the bar had. Kept in a small file in the
## player's user folder, written whenever the bar changes.

const ROWS_MOST := 3
const PER_ROW := 10

## Where the file is (the smoke test points this elsewhere).
static var path := "user://spell_bar.cfg"
## spell id -> slot, and how many rows the bar shows.
static var slots := {}
static var rows := 1
static var _loaded := ""


static func _load() -> void:
	if _loaded == path:
		return
	_loaded = path
	slots = {}
	rows = 1
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	rows = clampi(int(file.get_value("bar", "rows", 1)), 1, ROWS_MOST)
	for id: String in file.get_section_keys("slots") if file.has_section("slots") else PackedStringArray():
		slots[id] = int(file.get_value("slots", id, -1))


static func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("bar", "rows", rows)
	for id: String in slots:
		file.set_value("slots", id, slots[id])
	file.save(path)


## The slot spell `id` was in last time, or -1.
static func slot_of(id: String) -> int:
	_load()
	return slots.get(id, -1)


## How many rows the bar had last time.
static func row_count() -> int:
	_load()
	return rows


## Remembers where the spells on the bar are now (`bar`: each slot's spell
## id, or ""). Spells not on it keep where they were last time.
static func remember(bar: Array[String]) -> void:
	_load()
	for k in bar.size():
		if bar[k] != "":
			slots[bar[k]] = k
	_save()


static func set_rows(count: int) -> void:
	_load()
	rows = clampi(count, 1, ROWS_MOST)
	_save()
