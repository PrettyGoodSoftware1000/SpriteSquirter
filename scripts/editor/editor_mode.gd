class_name EditorMode
extends Node3D
## The map editor. Shape the island (sculpt it, grow new land, paint sand,
## grass and water), place start locations and goblin caves, plant or clear
## trees and rocks, then save the map for play.
## Maps never get buildings: villagers build those during the game.
##
## A new map starts from a random island of the chosen size without
## villages; a saved map is loaded as it was left. The map also keeps the
## nature palette chosen here, and is played in it.
##
## Ctrl + mouse wheel changes the brush size, and Ctrl+Z undoes the last
## change (each click or stroke is one change; see _begin_undo()).

enum Tool { RAISE, LOWER, FLATTEN, SMOOTH, LAND, SAND, GRASS, WATER, START, CAVE, TREES, ROCKS, ERASE, CUT, PATH }

## Keys 1-9 and 0 pick the first ten tools.
const TOOL_NAMES := ["Raise", "Lower", "Flatten", "Smooth", "Expand island", "Sand", "Grass", "Water",
	"Start location", "Gooblin cave", "Trees", "Rocks", "Erase", "Cut cliff", "Gooblin path"]
const TOOL_HINTS := [
	"Hold left mouse to raise the ground.",
	"Hold left mouse to dig the ground down. Water next to it flows in.",
	"Hold left mouse to flatten to the height where you first clicked.",
	"Hold left mouse to smooth bumps.",
	"Hold left mouse and draw out over the sky to grow the island any shape you like, at the height where you started (2.4 m when you start in the sky). At the edge of the map you are asked about making the map bigger.",
	"Hold left mouse to paint sand.",
	"Hold left mouse to paint grass. It clears sand, stone and dirt, and fills in water.",
	"Hold left mouse to flood the ground with water at the height where you first clicked. The ground is flattened under it, with a bank round it.",
	"Click to place a start location (up to 8). Players pick one when the game begins.",
	"Click to place a gooblin cave. R / Shift+R turn it. Gooblins live there.",
	"Hold left mouse to plant trees inside the brush. Trees give lumber.",
	"Click or hold to place rocks. Rocks give stone.",
	"Hold left mouse to remove trees, rocks, start locations and caves inside the brush.",
	"Click on low ground and drag into a hill: everything under the brush is sliced down to the height where you clicked, leaving a sheer cliff nobody can climb.",
	"Draw the way the gooblins take: hold left mouse from a gooblin cave and drag to a start location (or the other way). A cave and a start can have several paths. Right-click (or Shift+click) a path to remove it.",
]
## The colours of the goblin paths, in turn.
const PATH_COLORS := [Color(1.0, 0.3, 0.25), Color(0.3, 0.7, 1.0), Color(1.0, 0.85, 0.2), Color(0.5, 1.0, 0.4), Color(1.0, 0.45, 0.9),
	Color(0.3, 1.0, 0.9), Color(1.0, 0.6, 0.2), Color(0.7, 0.5, 1.0)]
## A path's ends must be this near a cave and a start location.
const PATH_SNAP := 30.0
const BRUSH_MIN := 3.0
const BRUSH_MAX := 30.0
const START_SPACING := 14.0
const CAVE_SPACING := 30.0
## Metres of sky added on each side when the map square grows.
const GROW_BY := 64
## Undo keeps a copy of the whole map for each change, as many as fit in
## about this much memory (between 5 and 30 of them).
const UNDO_MEMORY := 160 * 1024 * 1024

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
var _water_level := 0.0
var _land_height := 2.4
var _asked_edge := false
var _paint_timer := 0.0
var _ring: GroundRing
var _cave_ghost: Node3D
var _ghost_material := StandardMaterial3D.new()
var _dirty := false
var _confirm := ""
var _rng := RandomNumberGenerator.new()
## The goblin paths: each runs from a cave to a start location.
var _paths: Array[PackedVector2Array] = []
## The path being drawn.
var _stroke := PackedVector2Array()
var _drawing := false
var _path_mesh := ImmediateMesh.new()
var _path_view: MeshInstance3D
## Copies of the map from before each change, oldest first.
var _undo: Array[Dictionary] = []
## The map as it was when the mouse went down: kept once it changes.
var _pending_undo := {}
## True while an undo puts the map back (which is not itself a change).
var _restoring := false


func setup(info: Dictionary) -> void:
	_info = info


func _ready() -> void:
	_rng.randomize()
	_map_name = _info.name if _info.name != "" else "My island"
	_loaded_path = _info.get("path", "")
	var starts: PackedVector2Array = _info.starts
	for p in starts:
		_add_start(p)
	for path: PackedVector2Array in _info.get("paths", []):
		_paths.append(path)
	_ring = GroundRing.new()
	add_child(_ring)
	_path_view = MeshInstance3D.new()
	_path_view.mesh = _path_mesh
	var path_material := StandardMaterial3D.new()
	path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	path_material.vertex_color_use_as_albedo = true
	path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	path_material.no_depth_test = true
	_path_view.material_override = path_material
	_path_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_path_view.visible = false
	add_child(_path_view)
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
	hud.expand_requested.connect(_expand)
	hud.palette_selected.connect(_set_palette)
	# A map grown in memory (see _expand) has not been saved yet.
	_dirty = _info.get("unsaved", false)
	hud.set_map(_map_name, Terrain.SIZE)
	hud.set_brush(brush_radius)
	hud.set_palette(Art.palette_index)
	Game.terrain.changed.connect(func(_c: Vector3, _r: float) -> void:
		if not _restoring:
			_dirty = true
			_keep_undo())
	Game.camera_rig.set_zoom(150.0 * Terrain.SCALE, true)
	_set_tool(Tool.START)
	_update_counts()


func _process(delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	_cursor_hit = Game.pick_ground(mouse)
	if tool == Tool.LAND and (_cursor_hit == null or not Game.terrain._land((_cursor_hit as Vector3).x, (_cursor_hit as Vector3).z)):
		_cursor_hit = _sky_hit(mouse, _land_height)
	_painting = _painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _drawing and not _painting:
		_finish_path()
	if _painting and _cursor_hit != null:
		_paint(_cursor_hit, delta)
	_update_preview()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var number := key.physical_keycode - KEY_1
		if key.physical_keycode == KEY_0:
			number = 9
		if number >= 0 and number < 10:
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
			KEY_Z:
				if key.ctrl_pressed:
					undo()
		return
	var button := event as InputEventMouseButton
	if button and button.pressed and button.ctrl_pressed \
			and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		# Ctrl + wheel changes the brush size (the camera leaves it alone).
		var grow := 1.5 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.5
		brush_radius = clampf(brush_radius + grow, BRUSH_MIN, BRUSH_MAX)
		hud.set_brush(brush_radius)
		get_viewport().set_input_as_handled()
		return
	if button and button.pressed:
		# Clicking the world leaves the name box, so WASD moves the camera again.
		get_viewport().gui_release_focus()
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT and _cursor_hit != null:
		_on_click(_cursor_hit)
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT and tool == Tool.PATH and _cursor_hit != null:
		# Right-click a goblin path to remove it.
		_begin_undo()
		_remove_path(_cursor_hit)


func _set_tool(t: Tool) -> void:
	tool = t
	_painting = false
	_drawing = false
	_path_view.visible = t == Tool.PATH
	if t == Tool.PATH:
		_draw_paths()
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
	_begin_undo()
	match tool:
		Tool.START:
			_place_start(p)
		Tool.CAVE:
			_place_cave(p)
		_:
			_painting = true
			_flatten_height = p.y
			_paint_timer = 0.0
			match tool:
				Tool.ROCKS:
					_plant_rock(p)
				Tool.PATH:
					if Input.is_key_pressed(KEY_SHIFT):
						_painting = false
						_remove_path(p)
					else:
						_drawing = true
						_stroke = PackedVector2Array([Vector2(p.x, p.z)])
				Tool.WATER:
					var level := Game.terrain.water_level_at(p.x, p.z)
					_water_level = level if level != Terrain.NO_WATER else p.y
				Tool.LAND:
					_asked_edge = false
					_land_height = p.y if Game.terrain._land(p.x, p.z) else 2.4


# --- Tools --------------------------------------------------------------------

func _paint(p: Vector3, delta: float) -> void:
	match tool:
		Tool.RAISE, Tool.LOWER, Tool.FLATTEN, Tool.SMOOTH:
			Game.terrain.sculpt(int(tool) as Terrain.Brush, p, brush_radius, delta, _flatten_height)
		Tool.SAND:
			Game.terrain.paint_sand(p, brush_radius, 3.0 * delta)
			_changed()
		Tool.GRASS:
			Game.terrain.paint_grass(p, brush_radius, 3.0 * delta)
			_changed()
		Tool.WATER:
			Game.terrain.paint_water(p, brush_radius, _water_level)
		Tool.LAND:
			var limit := Terrain.HALF - Terrain.EDGE_MARGIN
			var hit_edge := absf(p.x) > limit or absf(p.z) > limit
			hit_edge = Game.terrain.paint_land(p, brush_radius, _land_height) or hit_edge
			if hit_edge and not _asked_edge:
				_asked_edge = true
				_painting = false
				_ask_expand()
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
		Tool.CUT:
			Game.terrain.apply_brush(p, brush_radius, Terrain.Brush.CUT, 1.0, _flatten_height)
		Tool.PATH:
			var at := Vector2(p.x, p.z)
			if _drawing and at.distance_to(_stroke[_stroke.size() - 1]) > 4.0:
				_stroke.append(at)
				_draw_paths()


# --- Goblin paths ---------------------------------------------------------------

## The mouse was let go: keep the stroke if it joins a cave and a start.
func _finish_path() -> void:
	_drawing = false
	var stroke := _stroke
	_stroke = PackedVector2Array()
	if stroke.size() >= 2:
		var cave_a: Variant = _near(stroke[0], "caves")
		var start_a: Variant = _near(stroke[0], "start_markers")
		var cave_b: Variant = _near(stroke[stroke.size() - 1], "caves")
		var start_b: Variant = _near(stroke[stroke.size() - 1], "start_markers")
		if cave_a == null and cave_b != null and start_a != null:
			# Drawn from the start to the cave: turn it round.
			stroke.reverse()
			cave_a = cave_b
			start_b = start_a
		if cave_a != null and start_b != null:
			stroke[0] = cave_a
			stroke[stroke.size() - 1] = start_b
			_paths.append(stroke)
			_changed()
			hud.set_status("Gooblin path %d added. Gooblins from that cave follow it to that start location." % _paths.size())
		else:
			hud.set_status("A gooblin path must run between a gooblin cave and a start location (within %d m of each)." % int(PATH_SNAP))
	_draw_paths()


## The nearest member of `group` to `p` (as its ground position), if it is
## within PATH_SNAP.
func _near(p: Vector2, group: String) -> Variant:
	var best: Variant = null
	var best_d := PATH_SNAP
	for node in get_tree().get_nodes_in_group(group):
		var q := Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z)
		if q.distance_to(p) < best_d:
			best_d = q.distance_to(p)
			best = q
	return best


func _remove_path(p: Vector3) -> void:
	var at := Vector2(p.x, p.z)
	for k in _paths.size():
		var path := _paths[k]
		for j in path.size() - 1:
			if Geometry2D.get_closest_point_to_segment(at, path[j], path[j + 1]).distance_to(at) < 5.0:
				_paths.remove_at(k)
				_changed()
				_draw_paths()
				hud.set_status("Gooblin path removed.")
				return


## The paths that still have a cave at one end and a start at the other.
func _valid_paths() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for path in _paths:
		if _near(path[0], "caves") != null and _near(path[path.size() - 1], "start_markers") != null:
			out.append(path)
	return out


## Draws every path as a ribbon on the ground, each in its own colour.
func _draw_paths() -> void:
	_path_mesh.clear_surfaces()
	var all: Array[PackedVector2Array] = _paths.duplicate()
	if _stroke.size() >= 2:
		all.append(_stroke)
	var terrain := Game.terrain
	for k in all.size():
		var path := all[k]
		var color: Color = PATH_COLORS[k % PATH_COLORS.size()] if k < _paths.size() else Color(1, 1, 1)
		color.a = 0.85
		_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for j in path.size():
			var along := (path[mini(j + 1, path.size() - 1)] - path[maxi(j - 1, 0)]).normalized()
			var side := Vector2(-along.y, along.x) * 0.9
			for s: float in [-1.0, 1.0]:
				var q := path[j] + side * s
				_path_mesh.surface_set_color(color)
				_path_mesh.surface_add_vertex(Vector3(q.x, terrain.surface_height(q.x, q.y) + 0.5, q.y))
		_path_mesh.surface_end()


## Where the mouse ray meets the flat plane at `height`, for growing land
## out over the sky.
func _sky_hit(mouse: Vector2, height: float) -> Variant:
	var cam := Game.camera_rig.camera
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if dir.y > -0.01:
		return null
	return from + dir * ((height - from.y) / dir.y)


func _ask_expand() -> void:
	var bigger := Terrain.SIZE + GROW_BY * 2
	if bigger > Terrain.MAX_SIZE:
		hud.set_status("The island has reached the edge of the map, and the map is already as big as it can be (%d m)." % Terrain.SIZE)
		return
	hud.ask_expand(Terrain.SIZE, bigger)


## Rebuilds the editor with the map square grown on every side.
func _expand() -> void:
	var data := map_data()
	data["version"] = MapData.VERSION
	var bigger := MapData.expand(data, GROW_BY)
	Game.start("editor", _loaded_path, int(bigger.size), false, bigger)


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
	if not t.is_dry(p.x, p.z):
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
	if not _restoring:
		_keep_undo()
	_dirty = true
	_confirm = ""
	_update_counts()


# --- Undo -----------------------------------------------------------------------

## Copies the map as it is now, for undo: it is kept only if something
## then changes (_keep_undo()), so a click that does nothing is not a step.
func _begin_undo() -> void:
	var data := map_data()
	data["paths"] = _paths.duplicate()
	_pending_undo = data


func _keep_undo() -> void:
	if _pending_undo.is_empty():
		return
	_undo.append(_pending_undo)
	_pending_undo = {}
	var per_copy := maxi(1, Terrain.N * Terrain.N * 21)
	while _undo.size() > clampi(int(float(UNDO_MEMORY) / per_copy), 5, 30):
		_undo.pop_front()


## Puts the map back as it was before the last change.
func undo() -> void:
	_painting = false
	_drawing = false
	_stroke = PackedVector2Array()
	if _undo.is_empty():
		hud.set_status("Nothing to undo.")
		return
	_pending_undo = {}
	var data: Dictionary = _undo.pop_back()
	_restoring = true
	Game.terrain.restore_layers(data)
	for group in ["trees", "rocks", "start_markers", "caves"]:
		for node in get_tree().get_nodes_in_group(group):
			_remove(node)
	var root := Game.world_root
	for t in data.trees:
		WorldPopulator.spawn_tree(root, Game.terrain, t[0], t[1], t[2], t[3])
	for r in data.rocks:
		var rock := WorldPopulator.spawn_rock(root, Game.terrain, r[0], r[1], r[2])
		rock.scale = Vector3(r[3], r[3] * rock.scale.y / rock.scale.x, r[3])
	for c in data.caves:
		WorldPopulator.place_cave(root, Game.terrain, c.pos, c.facing, _rng, false, false)
	for p: Vector2 in data.starts:
		_add_start(p)
	_paths.clear()
	for path: PackedVector2Array in data.paths:
		_paths.append(path)
	Art.set_palette(int(data.get("palette", Art.palette_index)))
	hud.set_palette(Art.palette_index)
	_restoring = false
	_dirty = true
	_confirm = ""
	_update_counts()
	_draw_paths()
	hud.set_status("Undone (%d more step%s can be undone)." % [_undo.size(), "" if _undo.size() == 1 else "s"])


## The nature palette the map is played in.
func _set_palette(index: int) -> void:
	_begin_undo()
	Art.set_palette(index)
	hud.set_palette(Art.palette_index)
	_changed()


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
		Tool.LAND:
			_ring.draw(c, [brush_radius], Color(0.6, 1.0, 0.5), c.y + 0.3)
		Tool.WATER:
			_ring.draw(c, [brush_radius, brush_radius + 2.5], Color(0.45, 0.75, 1.0))
		Tool.SAND:
			_ring.draw(c, [brush_radius], Color(1.0, 0.85, 0.5))
		Tool.GRASS:
			_ring.draw(c, [brush_radius], Color(0.5, 1.0, 0.4))
		Tool.ROCKS:
			_ring.draw(c, [1.5], Color(0.85, 0.85, 0.9))
		Tool.CUT:
			_ring.draw(c, [brush_radius], Color(1.0, 0.5, 0.2))
		Tool.PATH:
			_ring.draw(c, [1.2, PATH_SNAP], Color(1.0, 0.4, 0.3))
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
		rocks.append([n.global_position.x, n.global_position.z, n.get_meta("seed", 0), n.scale.x])
	data["rocks"] = rocks
	data["paths"] = _valid_paths()
	data["palette"] = Art.palette_index
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
