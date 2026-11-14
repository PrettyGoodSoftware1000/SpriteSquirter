class_name MapData
extends RefCounted
## Saving and loading maps made in the map editor.
##
## A map is one compressed file in user://maps/ holding a Dictionary:
##   version, name, size, seed       (the seed rebuilds the island outline)
##   heights, bare, rivers           (the terrain, from Terrain.export_map)
##   starts: PackedVector2Array      (start locations the player picks from)
##   caves:  [{pos: Vector2, facing: float}]
##   trees:  [[x, z, rotation, seed]]  rocks: [[x, z, seed]]
## Maps never contain buildings: the player's villagers build those.

const DIR := "user://maps/"
const EXT := ".map"
const VERSION := 1
const MAX_STARTS := 8


static func path_for(map_name: String) -> String:
	var slug := ""
	for c in map_name.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			slug += c
		elif not slug.ends_with("_"):
			slug += "_"
	slug = slug.trim_prefix("_").trim_suffix("_")
	if slug.is_empty():
		slug = "untitled"
	return DIR + slug + EXT


static func save(data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := path_for(data.get("name", ""))
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return FileAccess.get_open_error()
	data["version"] = VERSION
	file.store_var(data)
	file.close()
	return OK


## Returns the map, or an empty Dictionary if the file is missing or broken.
static func load_map(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_warning("Could not open map %s" % path)
		return {}
	var data: Variant = file.get_var()
	file.close()
	if not data is Dictionary or not _is_valid(data):
		push_warning("Map %s is damaged or from an unknown version" % path)
		return {}
	return data


## Name, size and start count of every saved map, sorted by name.
static func list_maps() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return maps
	for file_name in dir.get_files():
		if not file_name.ends_with(EXT):
			continue
		var path := DIR + file_name
		var data := load_map(path)
		if data.is_empty():
			continue
		maps.append({"name": data.name, "path": path, "size": data.size, "starts": (data.starts as PackedVector2Array).size()})
	maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).nocasecmp_to(b.name) < 0)
	return maps


static func size_name(size: int) -> String:
	var k := Terrain.SIZES.find(size)
	return "%s (%d m)" % [Terrain.SIZE_NAMES[k] if k >= 0 else "Custom", size]


static func _is_valid(d: Dictionary) -> bool:
	for key in ["version", "name", "size", "seed", "heights", "bare", "rivers", "starts", "caves", "trees", "rocks"]:
		if not d.has(key):
			return false
	if int(d.version) > VERSION or not int(d.size) in Terrain.SIZES:
		return false
	var n: int = int(d.size) + 1
	return d.heights is PackedFloat32Array and (d.heights as PackedFloat32Array).size() == n * n \
		and d.bare is PackedFloat32Array and (d.bare as PackedFloat32Array).size() == n * n \
		and d.starts is PackedVector2Array
