class_name SliderFile
extends RefCounted
## The dev menu's gameplay sliders, saved to and loaded from a plain text
## file a person can read and edit, one slider a line:
##
##   # SpriteSquirter sliders, version 0.20, saved 2026-11-18 14:05
##   Day length = 8 min
##   Lumber rate = 6 /worker/min
##
## Loading matches each line by the slider's name (or by its key, such as
## day_minutes) and takes the first number after the =. Lines it does not
## know, and lines starting with #, are skipped.


## Writes `settings` to `path`. Returns "" or what went wrong.
static func save(path: String, settings: Dictionary) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write %s (%s)." % [path, error_string(FileAccess.get_open_error())]
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var when := Time.get_datetime_string_from_system(false, true)
	file.store_line("# SpriteSquirter sliders, version %s, saved %s" % [version, when])
	file.store_line("# One slider a line: name = value. Edit the numbers if you like; Load sliders reads them back.")
	for s: Array in Hud.SETTING_SLIDERS:
		var key: String = s[0]
		if settings.has(key):
			file.store_line("%s = %s %s" % [s[1], String.num(float(settings[key]), 3), s[5]])
	file.close()
	return ""


## Reads `path`: slider key -> value, for every line it understood, kept
## within each slider's range.
static func load_values(path: String) -> Dictionary:
	var out := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var by_name := {}
	for s: Array in Hud.SETTING_SLIDERS:
		by_name[(s[1] as String).to_lower()] = s
		by_name[(s[0] as String).to_lower()] = s
	var number := RegEx.create_from_string("-?\\d+(\\.\\d+)?")
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "" or line.begins_with("#") or not "=" in line:
			continue
		var name := line.get_slice("=", 0).strip_edges().to_lower()
		if not by_name.has(name):
			continue
		var found := number.search(line.get_slice("=", 1))
		if found == null:
			continue
		var s: Array = by_name[name]
		out[s[0]] = clampf(found.get_string().to_float(), s[2], s[3])
	return out
