class_name EditorMode
extends Node3D
## The map editor. Shape the island, place start locations and goblin
## caves, plant or clear trees and rocks, then save the map for play.
## Maps never get buildings: villagers build those during the game.
##
## A new map starts from a random island of the chosen size without
## villages; a saved map is loaded as it was left.

enum Tool { RAISE, LOWER, FLATTEN, SMOOTH, START, CAVE, TREES, ROCKS, ERASE }

const TOOL_NAMES := ["Raise", "Lower", "Flatten", "Smooth", "Start location", "Goblin cave", "Trees", "Rocks", "Erase"]
const TOOL_HINTS := [
	"Hold left mouse to raise the ground.",
	"Hold left mouse to dig the ground down.",
	"Hold left mouse to flatten to the height where you first clicked.",
	"Hold left mouse to smooth bumps.",
	"Click to place a start location (up to 8). Players pick one when the game begins.",
	"Click to place a goblin cave. R / Shift+R turn it. Goblins live there.",
	"Hold left mouse to plant trees inside the brush. Trees give lumber.",
	"Click or hold to place rocks. Rocks give stone.",
	"Hold left mouse to remove trees, rocks, start locations and caves inside the brush.",
]
const BRUSH_MIN := 3.0
const BRUSH_MAX := 30.0
const START_SPACING := 14.0
const CAVE_SPACING := 30.0

var tool: Tool = Tool.START
var brush_radius := 8.0
var hud: EditorHud

var _info := {}
var _map_name := ""
var _loaded_path := ""
var _cave_facing := 0.0
var _cursor_hit: Variant = null
var _painting := false
var _flatten_height := 0.0
var _paint_timer := 0.0
var _ring: GroundRing
var _cave_ghost: Node3D
var _ghost_material := StandardMaterial3D.new()
var _dirty := false
var _confirm := ""
var _rng := RandomNumberGenerator.new()


func setup(info: Dictionary) -> void:
	_info = info


func _ready() -> void:
	_rng.randomize()
	_map_name = _info.name if _info.name != "" else "My island"
	_loaded_path = _info.get("path", "")
	var starts: PackedVector2Array = _info.starts
	for p in starts:
		_add_start(p)
	_ring = GroundRing.new()
	add_child(_ring)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.albedo_color = Color(0.4, 1.0, 0.5, 0.4)

	hud = EditorHud.new()
	add_child(hud)
	hud.tool_selected.connect(func(t: int) -> void: _set_tool(t as Tool))
	hud.save_requested.connect(_save)
	hud.play_requested.connect(_play)
	hud.menu_requested.connect(_leave.bind("menu", Terrain.SIZE))
	hud.new_requested.connect(func(size: int) -> void: _leave("editor", size))
	hud.name_changed.connect(func(text: String) -> void:
		_map_name = text
		_confirm = "")
	hud.set_map(_map_name, Terrain.SIZE)
	hud.set_brush(brush_radius)
	Game.terrain.changed.connect(func(_c: Vector3, _r: float) -> void: _dirty = true)
	Game.camera_rig.set_zoom(150.0 * Terrain.SCALE, true)
	_set_tool(Tool.START)
	_update_counts()


func _process(delta: float) -> void:
	_cursor_hit = Game.pick_ground(get_viewport().get_mouse_position())
	_painting = _painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _painting and _cursor_hit != null:
		_paint(_cursor_hit, delta)
	_update_preview()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var number := key.physical_keycode - KEY_1
		if number >= 0 and number < Tool.size():
			_set_tool(number as Tool)
			return
		match key.physical_keycode:
			KEY_BRACKETLEFT:
				brush_radius = clampf(brush_radius - 1.5, BRUSH_MIN, BRUSH_MAX)
				hud.set_brush(brush_radius)
			KEY_BRACKETRIGHT:
				brush_radius = clampf(brush_radius + 1.5, BRUSH_MIN, BRUSH_MAX)
				hud.set_brush(brush_radius)
			KEY_R:
				_cave_facing += (-PI if key.shift_pressed else PI) / 8.0
			KEY_S:
				if key.ctrl_pressed:
					_save()
		return
	var button := event as InputEventMouseButton
	if button and button.pressed:
		# Clicking the world leaves the name box, so WASD moves the camera again.
		get_viewport().gui_release_focus()
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT and _cursor_hit != null:
		_on_click(_cursor_hit)


func _set_tool(t: Tool) -> void:
	tool = t
	_painting = false
	hud.set_tool(t, TOOL_HINTS[t])
	if t == Tool.CAVE and _cave_ghost == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		_cave_ghost = BuildingFactory.create_cave(rng)
		_cave_ghost.remove_from_group("grounded")
		add_child(_cave_ghost)
		BuildingFactory.make_ghost(_cave_ghost, _ghost_material)
		for child in _cave_ghost.get_children():
			if child is FireEmitter:
				child.queue_free()
	elif t != Tool.CAVE and _cave_ghost != null:
		_cave_ghost.queue_free()
		_cave_ghost = null


func _on_click(p: Vector3) -> void:
	match tool:
		Tool.START:
			_place_start(p)
		Tool.CAVE:
			_place_cave(p)
		_:
			_painting = true
			_flatten_height = p.y
			_paint_timer = 0.0
			if tool == Tool.ROCKS:
				_plant_rock(p)


# --- Tools --------------------------------------------------------------------

func _paint(p: Vector3, delta: float) -> void:
	match tool:
		Tool.RAISE, Tool.LOWER, Tool.FLATTEN, Tool.SMOOTH:
			Game.terrain.sculpt(int(tool) as Terrain.Brush, p, brush_radius, delta, _flatten_height)
		Tool.TREES:
			_paint_timer -= delta
			while _paint_timer <= 0.0:
				_paint_timer += 0.05
				_plant_tree(p)
		Tool.ROCKS:
			_paint_timer -= delta
			if _paint_timer <= -0.3:
				_paint_timer = 0.0
				_plant_rock(p)
		Tool.ERASE:
			_erase(p)


func _place_start(p: Vector3) -> void:
	var problem := _spot_problem(p)
	var markers := get_tree().get_nodes_in_group("start_markers")
	if markers.size() >= MapData.MAX_STARTS:
		problem = "A map can have up to %d start locations." % MapData.MAX_STARTS
	for m in markers:
		if _flat(m.global_position, p) < START_SPACING:
			problem = "Too close to another start location."
	if problem != "":
		hud.set_status(problem)
		return
	_clear_flora(p, WorldPopulator.START_CLEARING)
	_add_start(Vector2(p.x, p.z))
	_changed()


func _add_start(p: Vector2) -> void:
	var m := StartMarker.new()
	m.index = get_tree().get_nodes_in_group("start_markers").size()
	add_child(m)
	m.global_position = Vector3(p.x, Game.terrain.get_height(p.x, p.y), p.y)


func _place_cave(p: Vector3) -> void:
	var problem := _spot_problem(p)
	for c in get_tree().get_nodes_in_group("caves"):
		if _flat(c.global_position, p) < CAVE_SPACING:
			problem = "Too close to another cave."
	if problem != "":
		hud.set_status(problem)
		return
	_clear_flora(p, WorldPopulator.CAVE_CLEARING * 0.7)
	WorldPopulator.place_cave(Game.world_root, Game.terrain, Vector2(p.x, p.z), _cave_facing, _rng, false, false)
	_changed()


func _spot_problem(p: Vector3) -> String:
	var t := Game.terrain
	if not t.is_inside(p.x, p.z) or t.get_height(p.x, p.z) < Terrain.WATER_LEVEL + 0.4:
		return "That needs dry land on the island."
	return ""


func _plant_tree(center: Vector3) -> void:
	var a := _rng.randf() * TAU
	var d := sqrt(_rng.randf()) * brush_radius
	var x := center.x + cos(a) * d
	var z := center.z + sin(a) * d
	if not WorldPopulator.good_tree_spot(Game.terrain, x, z):
		return
	for node in get_tree().get_nodes_in_group("trees"):
		if _flat((node as Node3D).global_position, Vector3(x, 0, z)) < 2.6:
			return
	WorldPopulator.spawn_tree(Game.world_root, Game.terrain, x, z, _rng.randf() * TAU, _rng.randi())
	_changed()


func _plant_rock(p: Vector3) -> void:
	# Rocks may sit on shores and riverbeds, but not out in the void.
	if not Game.terrain.is_inside(p.x, p.z) or Game.terrain.get_height(p.x, p.z) < -0.5:
		return
	WorldPopulator.spawn_rock(Game.world_root, Game.terrain, p.x, p.z, _rng.randi())
	_changed()


func _erase(p: Vector3) -> void:
	var removed := false
	for group in ["trees", "rocks", "start_markers", "caves"]:
		for node in get_tree().get_nodes_in_group(group):
			var n := node as Node3D
			if _flat(n.global_position, p) < brush_radius:
				_remove(n)
				removed = true
	if removed:
		_renumber_starts()
		_changed()


func _clear_flora(p: Vector3, radius: float) -> void:
	for group in ["trees", "rocks"]:
		for node in get_tree().get_nodes_in_group(group):
			if _flat((node as Node3D).global_position, p) < radius:
				_remove(node)


func _remove(n: Node) -> void:
	for group in n.get_groups():
		n.remove_from_group(group)
	n.queue_free()


func _renumber_starts() -> void:
	var k := 0
	for m in get_tree().get_nodes_in_group("start_markers"):
		(m as StartMarker).set_index(k)
		k += 1


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _changed() -> void:
	_dirty = true
	_confirm = ""
	_update_counts()


func _update_counts() -> void:
	var tree := get_tree()
	hud.set_counts(tree.get_nodes_in_group("start_markers").size(), tree.get_nodes_in_group("caves").size(),
		tree.get_nodes_in_group("trees").size(), tree.get_nodes_in_group("rocks").size())


func _update_preview() -> void:
	if _cave_ghost:
		_cave_ghost.visible = _cursor_hit != null
		if _cursor_hit != null:
			_cave_ghost.global_position = _cursor_hit
			_cave_ghost.rotation.y = _cave_facing
	if _cursor_hit == null:
		_ring.clear()
		return
	var c: Vector3 = _cursor_hit
	match tool:
		Tool.START:
			_ring.draw(c, [3.0, WorldPopulator.START_CLEARING], Color(1.0, 0.85, 0.3))
		Tool.CAVE:
			_ring.clear()
		Tool.ERASE:
			_ring.draw(c, [brush_radius], Color(1.0, 0.4, 0.35))
		Tool.ROCKS:
			_ring.draw(c, [1.5], Color(0.85, 0.85, 0.9))
		_:
			_ring.draw(c, [brush_radius, brush_radius * 0.4], Color(1.0, 0.9, 0.3))


# --- Saving -------------------------------------------------------------------

func map_data() -> Dictionary:
	var data := Game.terrain.export_map()
	data["name"] = _map_name.strip_edges()
	var starts := PackedVector2Array()
	for m in get_tree().get_nodes_in_group("start_markers"):
		var n := m as Node3D
		starts.append(Vector2(n.global_position.x, n.global_position.z))
	data["starts"] = starts
	var caves: Array = []
	for c in get_tree().get_nodes_in_group("caves"):
		var n := c as Node3D
		caves.append({"pos": Vector2(n.global_position.x, n.global_position.z), "facing": n.get_meta("facing", n.rotation.y)})
	data["caves"] = caves
	var trees: Array = []
	for t in get_tree().get_nodes_in_group("trees"):
		var n := t as Node3D
		trees.append([n.global_position.x, n.global_position.z, n.rotation.y, n.get_meta("seed", 0)])
	data["trees"] = trees
	var rocks: Array = []
	for r in get_tree().get_nodes_in_group("rocks"):
		var n := r as Node3D
		rocks.append([n.global_position.x, n.global_position.z, n.get_meta("seed", 0)])
	data["rocks"] = rocks
	return data


## Saves the map. Returns its path, or "" if it was not saved.
func _save() -> String:
	var map_name := _map_name.strip_edges()
	if map_name == "":
		hud.set_status("Give the map a name first.")
		return ""
	if get_tree().get_nodes_in_group("start_markers").is_empty():
		hud.set_status("Place at least one start location (tool 5) before saving.")
		return ""
	var path := MapData.path_for(map_name)
	if FileAccess.file_exists(path) and path != _loaded_path and _confirm != "overwrite":
		_confirm = "overwrite"
		hud.set_status("A map called \"%s\" already exists. Save again to replace it." % map_name)
		return ""
	var err := MapData.save(map_data())
	if err != OK:
		hud.set_status("Could not save: %s" % error_string(err))
		return ""
	_loaded_path = path
	_dirty = false
	_confirm = ""
	hud.set_status("Saved to %s" % ProjectSettings.globalize_path(path))
	return path


func _play() -> void:
	var path := _save()
	if path != "":
		Game.start("play", path, Terrain.SIZE, false)


## Leaves the editor, asking first when there are unsaved changes.
func _leave(mode: String, size: int) -> void:
	if _dirty and _confirm != "leave":
		_confirm = "leave"
		hud.set_status("You have unsaved changes. Click again to leave without saving.")
		return
	Game.start(mode, "", size)
