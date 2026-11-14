class_name PlayMode
extends Node3D
## The game. First the player picks one of the map's start locations; the
## village is founded there. Then mouse and keyboard input becomes spells,
## building orders and tortoise moves, while the PlayerVillage gathers,
## builds and grows and the DayCycle turns day into night.

enum Mode { COMMAND, SPELL, PLACE, SCULPT, FIELD }

const BRUSH_MIN := 3.0
const BRUSH_MAX := 30.0
const ROTATE_STEP := PI / 8.0
## How close the cursor must be to a start banner to pick it.
const PICK_RADIUS := 9.0
const FIELD_HINT := "Hold the left mouse button and drag to draw the field, then let go. Villagers sow and reap it.  Shift keeps drawing,  right-click or Esc to stop."

var mode: Mode = Mode.COMMAND
var spell_index := -1
var sculpt_brush := Terrain.Brush.RAISE
var brush_radius := 8.0

var village: PlayerVillage
var day_cycle: DayCycle
var raids: GoblinRaids
var hud: Hud
var creature: Creature

var _info := {}
var _atmosphere: Atmosphere
var _choosing := true
var _markers: Array[StartMarker] = []
var _hover: StartMarker
var _cooldowns: Array = []
var _cursor_hit: Variant = null
var _painting := false
var _flatten_height := 0.0
var _ui_timer := 0.0
var _ring: GroundRing

var _place_kind := ""
var _place_seed := 0
var _place_rotation := 0.0
var _ghost: Destructible
var _ghost_valid := false
var _ghost_problem := ""
var _ghost_material := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()

# The wheat field being drawn: dragged out from one corner to the other.
var _field_dragging := false
var _field_from := Vector3.ZERO
var _field_yaw := 0.0
var _field_center := Vector3.ZERO
var _field_size := Vector2.ZERO
var _field_problem_text := ""
var _prompt_timer := 0.0


## `info` comes from Main: name, starts, caves and whether it is a saved map.
func setup(info: Dictionary, atmosphere: Atmosphere) -> void:
	_info = info
	_atmosphere = atmosphere


func _ready() -> void:
	_rng.seed = Game.world_seed + 99
	for s in SpellBook.SPELLS:
		_cooldowns.append(0.0)
	village = PlayerVillage.new()
	village.name = "Village"
	add_child(village)
	Game.village = village

	day_cycle = DayCycle.new()
	day_cycle.atmosphere = _atmosphere
	day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(day_cycle)

	raids = GoblinRaids.new()
	add_child(raids)
	raids.setup(day_cycle)
	raids.raid_started.connect(func(count: int, ogres: int) -> void:
		var extra := "" if ogres == 0 else (" and an ogre" if ogres == 1 else " and %d ogres" % ogres)
		_announce("Midnight: %d goblins%s are marching on your village!" % [count, extra]))
	raids.raid_ended.connect(func() -> void: _announce("Morning: the goblins go home."))

	_ring = GroundRing.new()
	add_child(_ring)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	hud = Hud.new()
	add_child(hud)
	hud.sculpt_selected.connect(_on_sculpt_selected)
	hud.spell_selected.connect(_select_spell)
	hud.build_selected.connect(_start_placing)
	hud.build_menu_requested.connect(_toggle_build_menu)
	hud.menu_requested.connect(func() -> void: Game.start("menu", "", Terrain.SIZE))
	hud.regenerate_requested.connect(_regenerate)
	hud.mood_selected.connect(_set_mood)
	hud.palette_selected.connect(_set_palette)
	hud.grass_requested.connect(_cycle_grass)
	hud.setting_changed.connect(func(key: String, value: float) -> void: Game.settings[key] = value)
	hud.resources_requested.connect(func() -> void:
		for res in PlayerVillage.RESOURCES:
			village.give(res, 100.0))
	day_cycle.phase_changed.connect(func(mood: int) -> void:
		Game.mood_index = mood
		hud.set_mood(mood))
	hud.set_brush(brush_radius)
	hud.set_mood(_atmosphere.mood_index)
	hud.set_palette(Art.palette_index)
	hud.set_grass(Grass.DENSITY_NAMES[Game.grass_level])
	hud.set_settings(Game.settings)
	hud.set_dev_visible(Game.dev_menu)

	var starts: PackedVector2Array = _info.starts
	for k in starts.size():
		var m := StartMarker.new()
		m.index = k
		add_child(m)
		var p := starts[k]
		m.global_position = Vector3(p.x, Game.terrain.get_height(p.x, p.y), p.y)
		_markers.append(m)
	if _markers.is_empty():
		# A map without start locations: begin in the middle of the island.
		_found(Vector3(0.0, Game.terrain.get_height(0.0, 0.0), 0.0), -1)
	else:
		Game.camera_rig.set_zoom(170.0 * Terrain.SCALE, true)
		hud.set_prompt("%s: choose where your village begins. Click a banner." % _info.name)
	_set_mode(Mode.COMMAND)


func _process(delta: float) -> void:
	for k in _cooldowns.size():
		_cooldowns[k] = maxf(0.0, _cooldowns[k] - delta)
	_cursor_hit = Game.pick_ground(get_viewport().get_mouse_position())
	if _choosing:
		_update_hover()
	if _prompt_timer > 0.0:
		_prompt_timer -= delta
		if _prompt_timer <= 0.0:
			hud.set_prompt("")
	if _field_dragging:
		_update_field()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_field()
	_painting = _painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _painting and _cursor_hit != null:
		Game.terrain.sculpt(sculpt_brush, _cursor_hit, brush_radius, delta, _flatten_height)
	_update_ring()
	_update_ghost()
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = 0.2
		_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		_on_key(key)
		return
	var button := event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if mode == Mode.PLACE or mode == Mode.SPELL or mode == Mode.FIELD:
				_set_mode(Mode.COMMAND)
			elif _cursor_hit != null and not _choosing:
				_command_move(_cursor_hit)


func _on_key(key: InputEventKey) -> void:
	var code := key.physical_keycode
	if code == KEY_QUOTELEFT:
		_toggle_dev_menu()
		return
	if code == KEY_ESCAPE:
		if hud.is_build_menu_open():
			hud.show_build_menu(false)
		else:
			_set_mode(Mode.COMMAND)
		return
	if Game.dev_menu and _dev_key(code):
		return
	if _choosing:
		return
	var number := code - KEY_1
	if hud.is_build_menu_open():
		if number >= 0 and number < BuildingCatalog.BUILDINGS.size():
			_start_placing(BuildingCatalog.BUILDINGS[number].kind)
			return
	elif number >= 0 and number < SpellBook.SPELLS.size():
		_select_spell(number)
		return
	match code:
		KEY_B, KEY_BACKSPACE:
			_toggle_build_menu()
		KEY_F:
			_cast(SpellBook.index_of("fireball"))
		KEY_SPACE:
			if creature:
				Game.camera_rig.focus_on(creature.global_position)
		KEY_R:
			if mode == Mode.PLACE:
				_place_rotation += -ROTATE_STEP if key.shift_pressed else ROTATE_STEP
		KEY_T:
			if mode == Mode.PLACE:
				_place_seed = _rng.randi()
				_make_ghost()


## Shortcuts that only work while the dev menu is open. Returns true if used.
func _dev_key(code: int) -> bool:
	var number := code - KEY_4
	if number >= 0 and number < Hud.SCULPT_NAMES.size():
		_on_sculpt_selected(number)
		return true
	match code:
		KEY_BRACKETLEFT:
			brush_radius = clampf(brush_radius - 1.5, BRUSH_MIN, BRUSH_MAX)
			hud.set_brush(brush_radius)
		KEY_BRACKETRIGHT:
			brush_radius = clampf(brush_radius + 1.5, BRUSH_MIN, BRUSH_MAX)
			hud.set_brush(brush_radius)
		KEY_L:
			_set_mood((_atmosphere.mood_index + 1) % Atmosphere.MOODS.size())
		KEY_P:
			_set_palette(Art.palette_index + 1)
		KEY_G:
			_cycle_grass()
		KEY_N:
			_regenerate()
		_:
			return false
	return true


# --- Start location -----------------------------------------------------------

func _update_hover() -> void:
	var best: StartMarker = null
	if _cursor_hit != null:
		var p: Vector3 = _cursor_hit
		var best_d := INF
		for m in _markers:
			var d := Vector2(m.global_position.x - p.x, m.global_position.z - p.z).length()
			if d < PICK_RADIUS * m.scale.x and d < best_d:
				best_d = d
				best = m
	if best != _hover:
		if _hover:
			_hover.set_highlight(false)
		_hover = best
		if _hover:
			_hover.set_highlight(true)


## Founds the village at a start location. In a random world each start is
## a village site, whose buildings and villagers become the player's.
func _found(pos: Vector3, start_index: int) -> void:
	_choosing = false
	for m in _markers:
		m.queue_free()
	_markers.clear()
	_hover = null
	hud.set_prompt("")
	var site := start_index if not _info.from_map else -1
	village.found(pos, site)
	day_cycle.process_mode = Node.PROCESS_MODE_INHERIT

	creature = Creature.new()
	creature.name = "Creature"
	Game.world_root.add_child(creature)
	var out := Vector2(pos.x, pos.z)
	var dir := (-out).normalized() if out.length() > 1.0 else Vector2.RIGHT
	var spot := out + dir * (PlayerVillage.HOME_RADIUS + 12.0)
	creature.place(Vector3(spot.x, 0.0, spot.y), atan2(dir.x, dir.y))
	Game.creature = creature
	Game.camera_rig.focus_on(pos)
	Game.camera_rig.set_zoom(75.0)


# --- Modes --------------------------------------------------------------------

func _set_mode(m: Mode) -> void:
	mode = m
	_painting = false
	_field_dragging = false
	if m != Mode.SPELL:
		spell_index = -1
	if m != Mode.PLACE and _ghost != null:
		_ghost.queue_free()
		_ghost = null
	hud.set_spell(spell_index)
	hud.set_sculpt(sculpt_brush if m == Mode.SCULPT else -1)
	match m:
		Mode.COMMAND:
			hud.set_hint("Click or right-click the ground to walk the tortoise there. B or Backspace opens the build menu.")
		Mode.SPELL:
			hud.set_hint(SpellBook.SPELLS[spell_index].hint + "  Right-click or Esc to stop.")
		Mode.PLACE:
			hud.set_hint(_place_hint())
		Mode.SCULPT:
			hud.set_hint("Hold left mouse to %s the ground.  [ ] change brush size." % Hud.SCULPT_NAMES[sculpt_brush].to_lower())
		Mode.FIELD:
			hud.set_hint(FIELD_HINT)


func _place_hint() -> String:
	return "Click to place the %s outline.  R / Shift+R rotate,  T another look,  Shift+click keeps placing,  right-click or Esc to cancel." \
		% BuildingCatalog.find(_place_kind).name


func _select_spell(index: int) -> void:
	if _choosing:
		hud.set_spell(-1)
		return
	if mode == Mode.SPELL and spell_index == index:
		_set_mode(Mode.COMMAND)
		return
	spell_index = index
	_set_mode(Mode.SPELL)


func _on_sculpt_selected(index: int) -> void:
	if mode == Mode.SCULPT and sculpt_brush == index:
		_set_mode(Mode.COMMAND)
		return
	sculpt_brush = index as Terrain.Brush
	_set_mode(Mode.SCULPT)


func _toggle_dev_menu() -> void:
	Game.dev_menu = not Game.dev_menu
	hud.set_dev_visible(Game.dev_menu)
	if not Game.dev_menu and mode == Mode.SCULPT:
		_set_mode(Mode.COMMAND)


func _toggle_build_menu() -> void:
	if _choosing:
		return
	var open := not hud.is_build_menu_open()
	hud.show_build_menu(open)
	if open:
		hud.update_build_menu(village)


func _on_left_click() -> void:
	if _choosing:
		if _hover:
			_found(_hover.global_position, _hover.index)
		return
	if _cursor_hit == null:
		return
	match mode:
		Mode.COMMAND:
			_command_move(_cursor_hit)
		Mode.SPELL:
			_cast(spell_index)
		Mode.SCULPT:
			_painting = true
			_flatten_height = (_cursor_hit as Vector3).y
		Mode.PLACE:
			_place_building(Input.is_key_pressed(KEY_SHIFT))
		Mode.FIELD:
			_field_dragging = true
			_field_from = _cursor_hit
			# Line the field up with the screen.
			_field_yaw = Game.camera_rig.yaw
			_update_field()


func _command_move(pos: Vector3) -> void:
	if creature == null or not Game.terrain.is_inside(pos.x, pos.z):
		return
	creature.move_to(pos)
	Game.effects.spawn_marker(pos)


# --- Spells -------------------------------------------------------------------

func _cast(index: int) -> void:
	if _choosing or index < 0 or _cursor_hit == null or _cooldowns[index] > 0.0:
		return
	var spell: Dictionary = SpellBook.SPELLS[index]
	if village.amount("magicko") < spell.cost:
		hud.set_hint("Not enough magicko for %s: it costs %d." % [spell.name, spell.cost])
		return
	var target: Vector3 = _cursor_hit
	if spell.id == "blood" and not village.sacrifice(target):
		hud.set_hint("Blood Sacrifice needs one of your villagers within %d m of the click." % int(PlayerVillage.BLOOD_REACH))
		return
	village.give("magicko", -spell.cost)
	_cooldowns[index] = spell.cooldown
	match spell.id:
		"fireball":
			var mouse := get_viewport().get_mouse_position()
			var cam := Game.camera_rig.camera
			var from := cam.project_ray_origin(mouse) + cam.project_ray_normal(mouse) * 5.0
			var fb := Fireball.new()
			Game.world_root.add_child(fb)
			fb.launch(from, target)
		"rain":
			var cloud := RainCloud.new()
			Game.world_root.add_child(cloud)
			cloud.cast(target)
		"roots":
			var patch := RootPatch.new()
			Game.world_root.add_child(patch)
			patch.cast(target)
	if creature:
		creature.watch(target)


# --- Building placement -------------------------------------------------------

func _start_placing(kind: String) -> void:
	hud.show_build_menu(false)
	if kind == "field":
		_set_mode(Mode.FIELD)
		return
	_place_kind = kind
	_place_seed = _rng.randi()
	_set_mode(Mode.PLACE)
	_make_ghost()


func _make_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = _place_seed
	_ghost = BuildingFactory.create(_place_kind, rng)
	_ghost.is_ghost = true
	add_child(_ghost)
	BuildingFactory.make_ghost(_ghost, _ghost_material)


func _update_ghost() -> void:
	if _ghost == null:
		return
	if _cursor_hit == null:
		_ghost.visible = false
		return
	var p: Vector3 = _cursor_hit
	_ghost.visible = true
	_ghost.global_position = p
	_ghost.rotation.y = _place_rotation
	_ghost_problem = _placement_problem(p, _ghost.footprint)
	_ghost_valid = _ghost_problem == ""
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.5, 0.4) if _ghost_valid else Color(1.0, 0.3, 0.3, 0.4)


## Why a building can't go at `p`, or "" if it can.
func _placement_problem(p: Vector3, footprint: float) -> String:
	var terrain := Game.terrain
	if not terrain.is_inside(p.x, p.z) or terrain.get_height(p.x, p.z) < Terrain.WATER_LEVEL + 0.4:
		return "Buildings need dry land."
	if not village.in_territory(p):
		return "Too far from your village."
	for group in ["buildings", "construction_sites"]:
		for node in get_tree().get_nodes_in_group(group):
			var b := node as Node3D
			var other: float = b.get("footprint")
			if Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < other + footprint + 1.0:
				return "Too close to another building."
	for node in get_tree().get_nodes_in_group("caves"):
		var c := node as Node3D
		if Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < 14.0 + footprint:
			return "Too close to the goblin cave."
	for node in get_tree().get_nodes_in_group("fields"):
		if (node as CropField).contains(p, footprint):
			return "There is a field in the way."
	var short := village.shortfall(BuildingCatalog.find(_place_kind).cost)
	if short != "":
		return "Need %s more." % short
	return ""


func _place_building(keep_placing: bool) -> void:
	if _cursor_hit == null:
		return
	if not _ghost_valid:
		hud.set_hint(_ghost_problem)
		return
	var info := BuildingCatalog.find(_place_kind)
	if not village.spend(info.cost):
		return
	var p: Vector3 = _cursor_hit
	var footprint := _ghost.footprint
	var terrain := Game.terrain
	var h := maxf(terrain.average_height(p, footprint), Terrain.WATER_LEVEL + 0.5)
	# Level a pad for the building, blending out into the surrounding ground.
	terrain.apply_brush(Vector3(p.x, h, p.z), footprint + 3.0, Terrain.Brush.FLATTEN, 1.0, h, footprint / (footprint + 3.0))
	for node in get_tree().get_nodes_in_group("trees"):
		var t := node as Destructible
		if Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length() < footprint + 1.5:
			t.fell()
	var site := ConstructionSite.new()
	site.setup(_place_kind, _place_seed, info.cost)
	Game.world_root.add_child(site)
	site.global_position = Vector3(p.x, h, p.z)
	site.rotation.y = _place_rotation
	Game.effects.spawn_dust(site.global_position, clampf(footprint * 0.4, 0.6, 1.8))
	if keep_placing and village.can_afford(info.cost):
		_place_seed = _rng.randi()
		_make_ghost()
	else:
		_set_mode(Mode.COMMAND)


# --- Wheat fields ---------------------------------------------------------------

## Works out the rectangle between where the drag began and the cursor.
func _update_field() -> void:
	if _cursor_hit == null:
		return
	var right := Vector3(cos(_field_yaw), 0.0, -sin(_field_yaw))
	var forward := Vector3(sin(_field_yaw), 0.0, cos(_field_yaw))
	var drag: Vector3 = (_cursor_hit as Vector3) - _field_from
	var w := clampf(drag.dot(right), -CropField.MAX_SIDE, CropField.MAX_SIDE)
	var d := clampf(drag.dot(forward), -CropField.MAX_SIDE, CropField.MAX_SIDE)
	_field_center = _field_from + right * w * 0.5 + forward * d * 0.5
	_field_center.y = Game.terrain.get_height(_field_center.x, _field_center.z)
	_field_size = Vector2(absf(w), absf(d))
	_field_problem_text = _field_problem()


## Why the field being drawn can't be planted, or "" if it can.
func _field_problem() -> String:
	if _field_size.x < CropField.MIN_SIDE or _field_size.y < CropField.MIN_SIDE:
		return "Keep dragging: a field is at least %d m on each side." % int(CropField.MIN_SIDE)
	var terrain := Game.terrain
	var points := CropField.rect_corners(_field_center, _field_size, _field_yaw)
	points.append(_field_center)
	for k in 4:
		points.append(points[k].lerp(points[(k + 1) % 4], 0.5))
	for p in points:
		if not terrain.is_inside(p.x, p.z) or terrain.get_height(p.x, p.z) < Terrain.WATER_LEVEL + 0.4:
			return "Fields need dry land."
	if not village.in_territory(_field_center):
		return "Too far from your village."
	for group in ["buildings", "construction_sites", "caves"]:
		for node in get_tree().get_nodes_in_group(group):
			var b := node as Node3D
			var reach: float = 12.0 if group == "caves" else b.get("footprint")
			if CropField.in_rect(b.global_position, _field_center, _field_size, _field_yaw, reach + 0.5):
				return "There is a building in the way."
	for node in get_tree().get_nodes_in_group("fields"):
		var other := node as CropField
		for p in points:
			if other.contains(p, 0.5):
				return "There is another field in the way."
		if CropField.in_rect(other.global_position, _field_center, _field_size, _field_yaw):
			return "There is another field in the way."
	var short := village.shortfall(CropField.cost_for(_field_size))
	if short != "":
		return "Need %s more." % short
	return ""


func _finish_field() -> void:
	_field_dragging = false
	if _field_problem_text != "":
		hud.set_hint(_field_problem_text + "  Drag again, or right-click to stop.")
		return
	if not village.spend(CropField.cost_for(_field_size)):
		return
	for node in get_tree().get_nodes_in_group("trees"):
		var t := node as Destructible
		if CropField.in_rect(t.global_position, _field_center, _field_size, _field_yaw, 1.0):
			t.fell()
	var field := CropField.new()
	field.setup(_field_size)
	field.position = _field_center
	field.rotation.y = _field_yaw
	Game.world_root.add_child(field)
	Game.effects.spawn_dust(_field_center, 1.5)
	if Input.is_key_pressed(KEY_SHIFT):
		hud.set_hint(FIELD_HINT)
	else:
		_set_mode(Mode.COMMAND)


## Shows a message in the middle of the screen for a few seconds.
func _announce(text: String) -> void:
	hud.set_prompt(text)
	_prompt_timer = 7.0


# --- Dev menu actions -----------------------------------------------------------

func _set_mood(index: int) -> void:
	_atmosphere.set_mood(index)
	Game.mood_index = index
	hud.set_mood(index)


func _set_palette(index: int) -> void:
	Art.set_palette(index)
	hud.set_palette(Art.palette_index)


func _cycle_grass() -> void:
	Game.grass_level = (Game.grass_level + 1) % Grass.DENSITY_LEVELS.size()
	Grass.density = Grass.DENSITY_LEVELS[Game.grass_level]
	Game.terrain.grass.rebuild()
	hud.set_grass(Grass.DENSITY_NAMES[Game.grass_level])


func _regenerate() -> void:
	Game.start("play", "", Terrain.SIZE)


# --- Display ------------------------------------------------------------------

func _update_ring() -> void:
	if _cursor_hit == null:
		_ring.clear()
		return
	var c: Vector3 = _cursor_hit
	if mode == Mode.SCULPT:
		_ring.draw(c, [brush_radius, brush_radius * 0.4], Color(1.0, 0.9, 0.3))
	elif mode == Mode.PLACE and _ghost != null:
		_ring.draw(c, [_ghost.footprint + 0.5], Color(0.4, 1.0, 0.5) if _ghost_valid else Color(1.0, 0.35, 0.3))
	elif mode == Mode.SPELL and SpellBook.SPELLS[spell_index].id == "rain":
		_ring.draw(c, [RainCloud.RADIUS], Color(0.55, 0.75, 1.0))
	elif mode == Mode.SPELL and SpellBook.SPELLS[spell_index].id == "roots":
		_ring.draw(c, [RootPatch.RADIUS], Color(0.45, 1.0, 0.5))
	elif mode == Mode.SPELL and SpellBook.SPELLS[spell_index].id == "blood":
		_ring.draw(c, [PlayerVillage.BLOOD_REACH], Color(0.9, 0.1, 0.1))
	elif mode == Mode.FIELD and _field_dragging:
		_ring.draw_loop(CropField.rect_corners(_field_center, _field_size, _field_yaw),
			Color(0.4, 1.0, 0.5) if _field_problem_text == "" else Color(1.0, 0.35, 0.3))
	elif mode == Mode.FIELD:
		_ring.draw(c, [0.6], Color(0.4, 1.0, 0.5))
	else:
		_ring.clear()


func _update_ui() -> void:
	hud.set_resources(village, day_cycle.clock_text() if not _choosing else "")
	hud.update_spells(village.amount("magicko"), _cooldowns, not _choosing)
	hud.set_blood(village.blood_active())
	if hud.is_build_menu_open():
		hud.update_build_menu(village)
	if mode == Mode.FIELD and _field_dragging:
		var cost: int = CropField.cost_for(_field_size).lumber
		hud.set_hint("Field %d x %d m: %d lumber.  %s" % [roundi(_field_size.x), roundi(_field_size.y), cost,
			_field_problem_text if _field_problem_text != "" else "Let go to plant it."])
	if mode == Mode.PLACE and _ghost != null and _cursor_hit != null:
		hud.set_hint(_place_hint() if _ghost_valid else _ghost_problem + "  R rotate,  T another look,  Esc cancel.")
	if Game.dev_menu:
		var tree := get_tree()
		var goblins := tree.get_nodes_in_group("goblins").size()
		hud.set_stats("Villagers %d (yours %d, soldiers %d)   Goblins %d   Buildings %d\nTrees %d   Rocks %d   Fires %d   FPS %d" % [
			tree.get_nodes_in_group("villagers").size() - goblins, village.population(), village.soldiers(), goblins,
			tree.get_nodes_in_group("buildings").size(), tree.get_nodes_in_group("trees").size(),
			tree.get_nodes_in_group("rocks").size(), Game.fire.count(), Engine.get_frames_per_second()])
