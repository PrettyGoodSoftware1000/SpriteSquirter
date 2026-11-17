class_name PlayMode
extends Node3D
## The game. First the player picks one of the map's start locations; the
## village is founded there. Then mouse and keyboard input becomes spells,
## building orders and tortoise moves, while the PlayerVillage gathers,
## builds and grows and the DayCycle turns day into night.
##
## Spells are cast by their number key, where the mouse points: there is
## no spell in hand. Bless and Curse take two taps: the first shows what the
## creature last did, the second casts. A spell cast in the last Balance
## "spell_recent_seconds" costs "spell_recent_extra" more for each time
## (the soft cooldown); the spell bar sparkles blue as it gets dearer.

enum Mode { COMMAND, PLACE, SCULPT, FIELD, BRIDGE }

const BRUSH_MIN := 3.0
const BRUSH_MAX := 30.0
const ROTATE_STEP := PI / 8.0
## How close the cursor must be to a start banner to pick it.
const PICK_RADIUS := 9.0
const BRIDGE_HINT := "The treehouses a rope bridge can join are lit up. Click one, then another.  Right-click or Esc to stop."
const FIELD_HINT := "Hold the left mouse button and drag to draw the field, then let go. Villagers sow and reap it.  Shift keeps drawing,  right-click or Esc to stop."

## How long after the first tap of Bless or Curse the second tap casts it.
## The shortest time between two casts of the same spell.
const SPELL_DEBOUNCE := 0.25

var mode: Mode = Mode.COMMAND
var sculpt_brush := Terrain.Brush.RAISE
var brush_radius := 8.0

var village: PlayerVillage
var day_cycle: DayCycle
var raids: GoblinRaids
var pause_menu: PauseMenu
var hud: Hud
var creature: Creature

var _info := {}
var _atmosphere: Atmosphere
var _choosing := true
var _markers: Array[StartMarker] = []
var _hover: StartMarker
var _cooldowns: Array = []
## For each spell, when it was cast in the last Balance "spell_recent_seconds".
var _recent: Array = []
## The spell in hand (see _spell_key), or -1.
var _armed := -1
## The spell button under the mouse, or -1.
var _hover_spell := -1
var _cursor_hit: Variant = null
var _painting := false
var _flatten_height := 0.0
var _ui_timer := 0.0
var _ring: GroundRing
## The edge of the village's influence, shown while placing a building or
## with the mouse over a Storehouse.
var _wall: InfluenceWall

var _place_kind := ""
var _place_seed := 0
var _place_rotation := 0.0
var _ghost: Destructible
var _ghost_valid := false
var _ghost_problem := ""
var _ghost_material := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()
## Seconds the influence wall stays up after a spell was aimed outside it.
var _wall_flash := 0.0

# The wheat field being drawn: dragged out from one corner to the other.
var _field_dragging := false
var _field_from := Vector3.ZERO
var _field_yaw := 0.0
var _field_center := Vector3.ZERO
var _field_size := Vector2.ZERO
var _field_problem_text := ""
var _prompt_timer := 0.0
## True while the prompt shows the creature's last action (Bless / Curse).
var _judge_prompt := false
## See-through copies of the treehouses a rope bridge can join.
var _bridge_ghosts: Node3D
var _bridge_ghost_materials: Array[StandardMaterial3D] = []
## Hanging a rope bridge: the Home clicked first, and the one under the cursor.
var _bridge_from: Destructible
var _bridge_hover: Destructible
var _bridge_problem_text := ""


## `info` comes from Main: name, starts, caves and whether it is a saved map.
func setup(info: Dictionary, atmosphere: Atmosphere) -> void:
	_info = info
	_atmosphere = atmosphere


func _ready() -> void:
	_rng.seed = Game.world_seed + 99
	for s in SpellBook.SPELLS:
		_cooldowns.append(0.0)
		_recent.append([])
	village = PlayerVillage.new()
	village.name = "Village"
	add_child(village)
	Game.village = village

	day_cycle = DayCycle.new()
	day_cycle.atmosphere = _atmosphere
	Game.day_cycle = day_cycle
	day_cycle.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(day_cycle)

	raids = GoblinRaids.new()
	add_child(raids)
	raids.setup(day_cycle)
	raids.paths = _info.get("paths", [])
	raids.raid_started.connect(func(count: int, ogres: int) -> void:
		var key := "raid_started" if ogres == 0 else ("raid_started_ogre" if ogres == 1 else "raid_started_ogres")
		var text := Texts.line(key, {"goblins": count, "ogres": ogres})
		if raids.marching > 0:
			text += " " + Texts.line("raid_started_balrog")
		_announce(text))
	raids.balrog_came.connect(func() -> void: _announce(Texts.line("balrog_came")))
	raids.balrog_grown.connect(func() -> void: _announce(Texts.line("balrog_grown")))
	raids.balrog_died.connect(func() -> void: _announce(Texts.line("balrog_died")))
	raids.raid_ended.connect(func() -> void: _announce(Texts.line("raid_ended")))
	raids.bat_took.connect(func() -> void: _announce(Texts.line("bat_took")))

	_ring = GroundRing.new()
	add_child(_ring)
	_wall = InfluenceWall.new()
	add_child(_wall)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	hud = Hud.new()
	add_child(hud)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.menu_requested.connect(func() -> void: Game.start("menu", "", Terrain.SIZE))
	hud.quota_changed.connect(func(kind: String, change: int) -> void: village.change_quota(kind, change))
	hud.sculpt_selected.connect(_on_sculpt_selected)
	hud.spell_selected.connect(_on_spell_button)
	hud.spell_hovered.connect(_on_spell_hovered)
	hud.resurrect_requested.connect(resurrect)
	hud.build_selected.connect(_start_placing)
	hud.build_menu_requested.connect(_toggle_build_menu)
	hud.research_menu_requested.connect(_toggle_research_menu)
	hud.research_selected.connect(_on_research_selected)
	village.research_done.connect(func(id: String) -> void:
		_announce(Texts.line("research_done", {"research": (Research.find(id).name as String).to_lower()})))
	hud.regenerate_requested.connect(_regenerate)
	hud.mood_selected.connect(_set_mood)
	hud.palette_selected.connect(_set_palette)
	hud.grass_requested.connect(_cycle_grass)
	hud.setting_changed.connect(func(key: String, value: float) -> void: Game.settings[key] = value)
	hud.jobs_changed.connect(func(role: String, change: int) -> void:
		village.set_wanted(role, village.wanted[role] + change))
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
		hud.set_prompt(Texts.line("choose_start", {"map": _info.name}))
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
	_update_wall()
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
	if button and button.pressed and button.ctrl_pressed and mode == Mode.SCULPT \
			and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		# Ctrl + wheel changes the brush size instead of zooming.
		var grow := 1.5 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.5
		brush_radius = clampf(brush_radius + grow, BRUSH_MIN, BRUSH_MAX)
		hud.set_brush(brush_radius)
		get_viewport().set_input_as_handled()
		return
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if _armed >= 0 and not _choosing:
				_click_spell()
			else:
				_on_left_click()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if _armed >= 0:
				_disarm()
				_set_mode(mode)
			elif mode == Mode.PLACE or mode == Mode.FIELD or mode == Mode.BRIDGE:
				_set_mode(Mode.COMMAND)
			elif _cursor_hit != null and not _choosing:
				_command_move(_cursor_hit)


func _on_key(key: InputEventKey) -> void:
	var code := key.physical_keycode
	if code == KEY_QUOTELEFT:
		_toggle_dev_menu()
		return
	if code == KEY_ESCAPE:
		# Esc backs out of a menu or a tool first; with nothing to back
		# out of, it pauses the game.
		if hud.is_build_menu_open() or hud.is_research_menu_open():
			hud.show_build_menu(false)
			hud.show_research_menu(false)
		elif _armed >= 0:
			_disarm()
			_set_mode(mode)
		elif mode != Mode.COMMAND:
			_set_mode(Mode.COMMAND)
		else:
			pause_menu.open()
		return
	if Game.dev_menu and _dev_key(code):
		return
	if _choosing:
		return
	var number := code - KEY_1
	if hud.is_build_menu_open():
		if number >= 0 and number < mini(9, BuildingCatalog.BUILDINGS.size()):
			_start_placing(BuildingCatalog.BUILDINGS[number].kind)
			return
	elif number >= 0 and number < SpellBook.SPELLS.size():
		_spell_key(number)
		return
	match code:
		KEY_B, KEY_BACKSPACE:
			_toggle_build_menu()
		KEY_U:
			_toggle_research_menu()
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
	creature.kind = Game.creature_kind
	Game.world_root.add_child(creature)
	creature.knocked_down.connect(func() -> void:
		_announce(Texts.line("creature_died", {"creature": creature.species_name().to_lower(), "animus": roundi(Balance.num("resurrect_animus"))})))
	creature.got_up.connect(func() -> void: _announce(Texts.line("creature_resurrected", {"creature": creature.species_name().to_lower()})))
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
	_bridge_from = null
	_disarm()
	_refresh_bridge_ghosts()
	if m != Mode.PLACE and _ghost != null:
		_ghost.queue_free()
		_ghost = null
	hud.set_sculpt(sculpt_brush if m == Mode.SCULPT else -1)
	match m:
		Mode.COMMAND:
			hud.set_hint("Click or right-click the ground to walk the %s there. Keys 1-%d take a spell in hand. B or Backspace opens the build menu." \
				% [(Creature.SPECIES[Game.creature_kind].name as String).to_lower(), SpellBook.SPELLS.size()])
		Mode.PLACE:
			hud.set_hint(_place_hint())
		Mode.SCULPT:
			hud.set_hint("Hold left mouse to %s the ground.  Ctrl + wheel or [ ] change brush size." % Hud.SCULPT_NAMES[sculpt_brush].to_lower())
		Mode.FIELD:
			hud.set_hint(FIELD_HINT)
		Mode.BRIDGE:
			hud.set_hint(BRIDGE_HINT)


func _place_hint() -> String:
	return "Click to place the %s outline.  R / Shift+R rotate,  T another look,  Shift+click keeps placing,  right-click or Esc to cancel." \
		% BuildingCatalog.find(_place_kind).name


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
	hud.show_research_menu(false)
	hud.show_build_menu(open)
	if open:
		hud.update_build_menu(village)


func _toggle_research_menu() -> void:
	if _choosing:
		return
	var open := not hud.is_research_menu_open()
	hud.show_build_menu(false)
	hud.show_research_menu(open)
	if open:
		hud.update_research(village)


func _on_research_selected(id: String) -> void:
	var problem := village.start_research(id)
	if problem != "":
		hud.set_hint(problem)
	else:
		var item := Research.find(id)
		hud.set_hint("Researching %s: %s minutes." % [(item.name as String).to_lower(), Hud._number(item.seconds / 60.0)])
	hud.update_research(village)


func _on_left_click() -> void:
	if _choosing:
		if _hover:
			_found(_hover.global_position, _hover.index)
		return
	# (Bridges are aimed at treehouses, not at the ground.)
	if mode == Mode.BRIDGE:
		_bridge_click()
		return
	if _cursor_hit == null:
		return
	match mode:
		Mode.COMMAND:
			_command_move(_cursor_hit)
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


## The Resurrect button: brings the dead creature back to life at the
## nearest Shrine, for Balance "resurrect_animus" animus.
func resurrect() -> void:
	if creature == null or not creature.knocked_out:
		return
	var who := creature.species_name().to_lower()
	var cost := roundi(Balance.num("resurrect_animus"))
	var shrines := village.shrines()
	if shrines.is_empty():
		_announce(Texts.line("resurrect_no_shrine", {"creature": who}))
		return
	if village.amount("animus") < cost:
		_announce(Texts.line("resurrect_no_animus", {"creature": who, "animus": cost, "have": village.amount("animus")}))
		return
	village.give("animus", -cost)
	var shrine := shrines[0]
	for s in shrines:
		if s.global_position.distance_to(creature.global_position) < shrine.global_position.distance_to(creature.global_position):
			shrine = s
	# Beside the Shrine, on the side facing the village.
	var out := village.center - shrine.global_position
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 1.0 else Vector3.RIGHT
	creature.resurrect(shrine.global_position + out * (shrine.footprint + 4.0 + 3.0 * creature.size))
	Game.camera_rig.focus_on(creature.global_position)


func _command_move(pos: Vector3) -> void:
	if creature == null or not Game.terrain.is_inside(pos.x, pos.z):
		return
	creature.move_to(pos)
	Game.effects.spawn_marker(pos)


# --- Spells -------------------------------------------------------------------

func _is_judgement(index: int) -> bool:
	var id: String = SpellBook.SPELLS[index].id
	return id == "bless" or id == "curse"


## The extra share a spell costs now, for being cast recently: Balance
## "spell_recent_extra" for each cast in the last "spell_recent_seconds".
func recent_extra(index: int) -> float:
	var recent: Array = _recent[index]
	var since := Game.now - Balance.num("spell_recent_seconds")
	while not recent.is_empty() and float(recent[0]) < since:
		recent.pop_front()
	return recent.size() * Balance.num("spell_recent_extra")


## What a spell costs in magicko right now.
func spell_cost(index: int) -> int:
	var base: int = SpellBook.SPELLS[index].cost
	return ceili(base * (1.0 + recent_extra(index)) - 0.001)


## Pays for a spell, if there is magicko enough. Returns false if not.
func _pay_for(index: int) -> bool:
	var spell: Dictionary = SpellBook.SPELLS[index]
	var cost := spell_cost(index)
	if village.amount("magicko") < cost:
		hud.set_hint("Not enough magicko for %s: it costs %d now." % [spell.name, cost])
		return false
	village.give("magicko", -cost)
	(_recent[index] as Array).append(Game.now)
	_cooldowns[index] = SPELL_DEBOUNCE
	return true


## A spell's number key (or its button): takes the spell in hand, and the
## mouse pointer turns into its sign. A click then casts it (Bless and
## Curse: a click anywhere). Pressing the same key again puts it away.
func _spell_key(index: int) -> void:
	if _choosing or index < 0 or index >= SpellBook.SPELLS.size():
		return
	if _armed == index:
		_disarm()
		hud.set_hint("")
		_set_mode(mode)
		return
	if mode != Mode.COMMAND:
		_set_mode(Mode.COMMAND)
	_armed = index
	hud.set_spell(index)
	var spell: Dictionary = SpellBook.SPELLS[index]
	Input.set_custom_mouse_cursor(SpellCursors.image(spell.id), Input.CURSOR_ARROW, SpellCursors.hotspot())
	if _is_judgement(index):
		_show_last_action(index, true)
		hud.set_hint("Click anywhere to %s the %s for what it last did.  Press %d again to cancel." % [
			(spell.name as String).to_lower(), creature.species_name().to_lower() if creature else "creature", index + 1])
	else:
		hud.set_hint("Click to cast %s inside your village's influence.  Shift+click keeps it in hand.  Press %d again, right-click or Esc to cancel." % [
			spell.name, index + 1])


func _on_spell_button(index: int) -> void:
	_spell_key(index)


## The mouse went over a spell button (-1: off it). Over Bless or Curse,
## the top of the screen says what the creature last did.
func _on_spell_hovered(index: int) -> void:
	_hover_spell = index
	if _armed >= 0:
		return
	if index >= 0 and _is_judgement(index) and not _choosing:
		_show_last_action(index, false)
	elif _judge_prompt:
		_judge_prompt = false
		hud.set_prompt("")


## Puts the spell in hand away.
func _disarm() -> void:
	if _armed >= 0:
		Input.set_custom_mouse_cursor(null)
		hud.set_spell(-1)
	_armed = -1
	if _judge_prompt:
		_judge_prompt = false
		hud.set_prompt("")


## A click with a spell in hand.
func _click_spell() -> void:
	var index := _armed
	if _is_judgement(index):
		_disarm()
		_judge(index)
		_set_mode(mode)
		return
	_cast(index)
	if not Input.is_key_pressed(KEY_SHIFT):
		_disarm()
		_set_mode(mode)


## The top of the screen says what the creature last did, which is what
## Bless or Curse would judge. `armed`: the spell is in hand.
func _show_last_action(index: int, armed: bool) -> void:
	if creature == null:
		return
	var mind := creature.mind
	var spell: Dictionary = SpellBook.SPELLS[index]
	var ago := Game.now - mind.last_action_time
	var text := ""
	if mind.last_action == "" or ago > CreatureMind.JUDGE_SECONDS:
		text = Texts.line("judge_nothing", {"creature": creature.species_name().to_lower(), "seconds": int(CreatureMind.JUDGE_SECONDS)})
	else:
		var fill := {"action": CreatureMind.describe(mind.last_action), "ago": int(ago), "key": index + 1,
			"spell": (spell.name as String).to_lower(), "creature": creature.species_name().to_lower()}
		text = Texts.line("judge_judged" if mind.last_judged else ("judge_prompt" if armed else "judge_hover"), fill)
	hud.set_prompt(text)
	_prompt_timer = 0.0
	_judge_prompt = true


## Casts Bless or Curse on the creature, for what it last did. Each thing
## it does can be blessed or cursed only once.
func _judge(index: int) -> void:
	if _choosing or creature == null or _cooldowns[index] > 0.0:
		return
	if not creature.mind.can_judge():
		hud.set_hint(creature.mind.judge(1))
		return
	if not _pay_for(index):
		return
	var blessing: bool = SpellBook.SPELLS[index].id == "bless"
	Game.effects.spawn_judgement(creature.global_position + Vector3.UP * 4.0 * creature.size, creature.size, blessing)
	hud.set_hint(creature.mind.judge(1 if blessing else -1))


## Casts a spell where the mouse points.
func _cast(index: int) -> void:
	if _choosing or index < 0 or _cooldowns[index] > 0.0:
		return
	var spell: Dictionary = SpellBook.SPELLS[index]
	if _cursor_hit == null:
		hud.set_hint("Point at the island to cast %s." % spell.name)
		return
	var target: Vector3 = _cursor_hit
	if not village.in_territory(target):
		hud.set_hint("Spells can only be cast inside your village's influence (the wall of light).")
		_wall_flash = 1.5
		return
	if spell.id == "blood" and village.amount("magicko") >= spell_cost(index) and not village.sacrifice(target):
		hud.set_hint("Blood Sacrifice needs one of your villagers within %d m of the mouse." % int(PlayerVillage.BLOOD_REACH))
		return
	if not _pay_for(index):
		return
	if creature:
		creature.mind.watch_spell(spell.id)
	match spell.id:
		"fireball":
			var mouse := get_viewport().get_mouse_position()
			var cam := Game.camera_rig.camera
			var from := cam.project_ray_origin(mouse) + cam.project_ray_normal(mouse) * 5.0
			var fb := Fireball.new()
			fb.limit_center = village.center
			fb.limit_radius = village.influence()
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
		"lightning":
			ChainLightning.cast(target)
	if creature:
		creature.watch(target)


# --- Influence ------------------------------------------------------------------

## Shows the wall at the edge of the village's influence while a building
## is being placed (or a field drawn, or a bridge hung), while the mouse is
## over a Storehouse, and for a moment after a spell is cast outside it.
func _update_wall() -> void:
	if _choosing or not village.founded:
		return
	_wall_flash = maxf(0.0, _wall_flash - get_process_delta_time())
	var show := mode == Mode.PLACE or mode == Mode.FIELD or mode == Mode.BRIDGE or _wall_flash > 0.0 or _store_at_mouse()
	if show:
		_wall.show_at(village.center, village.influence())


## True with the mouse over one of the village's Storehouses.
func _store_at_mouse() -> bool:
	if _cursor_hit == null:
		return false
	var p: Vector3 = _cursor_hit
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if BuildingCatalog.role(b.get_meta("kind", "")) == "store" \
				and Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < b.footprint * 1.3 + 1.0:
			return true
	return false


# --- Building placement -------------------------------------------------------

func _start_placing(kind: String) -> void:
	hud.show_build_menu(false)
	if kind == "field":
		_set_mode(Mode.FIELD)
		return
	if kind == "bridge":
		_set_mode(Mode.BRIDGE)
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
	if not terrain.is_dry(p.x, p.z):
		return "Buildings need dry land."
	if not village.in_territory(p):
		return "Outside your village's influence (the wall of light)."
	for group in ["buildings", "construction_sites", "goblin_sites"]:
		for node in get_tree().get_nodes_in_group(group):
			var b := node as Node3D
			if b.get("kind") == "bridge":
				continue
			var other: float = b.get("footprint")
			if Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() < other + footprint + 1.0:
				return "Too close to another building."
	for node in get_tree().get_nodes_in_group("bridges"):
		var bridge := node as RopeBridge
		var along := bridge.global_transform.affine_inverse() * p
		if absf(along.x) < bridge.length * 0.5 and absf(along.z) < footprint + 1.0:
			return "There is a rope bridge overhead."
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
	var h := terrain.average_height(p, footprint)
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


# --- Rope bridges -----------------------------------------------------------------

## The village's finished treehouses: the buildings a bridge can join.
func _treehouses() -> Array[Destructible]:
	var out: Array[Destructible] = []
	for node in get_tree().get_nodes_in_group("player_buildings"):
		var b := node as Destructible
		if b.has_meta("deck_h") and not b.destroyed:
			out.append(b)
	return out


## The treehouse under the mouse, if any. The mouse may be on any part of
## it (trunk, deck, house or leaves), so this goes by where the treehouse
## is on the screen, not by the ground behind it.
func _home_at_mouse() -> Destructible:
	var cam := Game.camera_rig.camera
	var mouse := get_viewport().get_mouse_position()
	var best: Destructible = null
	var best_d := INF
	for b in _treehouses():
		for up: float in [0.5, b.get_meta("deck_h", 4.7), b.height * 0.8]:
			var p := b.global_position + Vector3.UP * up
			if cam.is_position_behind(p):
				continue
			# About the treehouse's own width on the screen.
			var reach := 30.0 + 600.0 * b.footprint / maxf(cam.global_position.distance_to(p), 1.0)
			var d := cam.unproject_position(p).distance_to(mouse)
			if d < reach and d < best_d:
				best_d = d
				best = b
	return best


## Lights up the treehouses a bridge can join: all of them at first, then
## (once one end is chosen) that one in yellow and those in reach in green.
func _refresh_bridge_ghosts() -> void:
	if _bridge_ghosts != null:
		_bridge_ghosts.queue_free()
		_bridge_ghosts = null
	if mode != Mode.BRIDGE:
		return
	if _bridge_ghost_materials.is_empty():
		for color: Color in [Color(0.3, 1.0, 0.5, 0.38), Color(1.0, 0.9, 0.25, 0.45)]:
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = color
			mat.no_depth_test = true
			_bridge_ghost_materials.append(mat)
	_bridge_ghosts = Node3D.new()
	add_child(_bridge_ghosts)
	var from_ok := _bridge_from != null and is_instance_valid(_bridge_from)
	for b in _treehouses():
		if from_ok and b != _bridge_from and _bridge_problem(_bridge_from, b, false) != "":
			continue
		_add_ghost(b, b, _bridge_ghost_materials[1 if from_ok and b == _bridge_from else 0])


func _add_ghost(node: Node, top: Node3D, material: Material) -> void:
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi and mi.mesh:
			var copy := MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.material_override = material
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_bridge_ghosts.add_child(copy)
			copy.global_transform = mi.global_transform
		if not child is CPUParticles3D:
			_add_ghost(child, top, material)


## How long a bridge between two Homes would be.
func _bridge_length(a: Destructible, b: Destructible) -> float:
	var ea := RopeBridge.deck_edge(a, b.global_position)
	var eb := RopeBridge.deck_edge(b, a.global_position)
	return Vector2(eb.x - ea.x, eb.z - ea.z).length()


## Why a bridge can't join these two treehouses, or "" if it can.
## `with_cost` also checks that the village can pay for it.
func _bridge_problem(a: Destructible, b: Destructible, with_cost := true) -> String:
	if a == b:
		return "Pick a different treehouse for the other end."
	var centres := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z).length()
	var length := _bridge_length(a, b)
	if centres < 9.5:
		return "Those two treehouses are too close together for a bridge."
	if length > Balance.num("bridge_max_length"):
		return "Too far: a rope bridge reaches %d m and that is %d m." % [roundi(Balance.num("bridge_max_length")), roundi(length)]
	for node in get_tree().get_nodes_in_group("bridges"):
		if (node as RopeBridge).joins(a, b):
			return "Those two treehouses already have a bridge."
	for node in get_tree().get_nodes_in_group("construction_sites"):
		var site := node as ConstructionSite
		if site.kind == "bridge" and ((site.ends[0] == a and site.ends[1] == b) or (site.ends[0] == b and site.ends[1] == a)):
			return "Those two treehouses already have a bridge."
	if not with_cost:
		return ""
	var short := village.shortfall(BuildingCatalog.bridge_cost(length))
	if short != "":
		return "Need %s more." % short
	return ""


## A click with the bridge tool, on `home` (or on whatever treehouse is
## under the mouse).
func _bridge_click(home: Destructible = null) -> void:
	if home == null:
		home = _home_at_mouse()
	if home == null:
		hud.set_hint("Click one of the lit-up treehouses." if not _treehouses().is_empty() else "A rope bridge joins two treehouses: build some first.")
		return
	if _bridge_from == null or not is_instance_valid(_bridge_from):
		_bridge_from = home
		_refresh_bridge_ghosts()
		hud.set_hint("Now click the treehouse at the other end (the ones in reach are green).")
		return
	var problem := _bridge_problem(_bridge_from, home)
	if problem != "":
		hud.set_hint(problem)
		return
	var a := _bridge_from
	var ea := RopeBridge.deck_edge(a, home.global_position)
	var eb := RopeBridge.deck_edge(home, a.global_position)
	var length := Vector2(eb.x - ea.x, eb.z - ea.z).length()
	var cost := BuildingCatalog.bridge_cost(length)
	if not village.spend(cost):
		return
	var base := minf(a.global_position.y, home.global_position.y)
	var site := ConstructionSite.new()
	site.spec = {"length": length, "ya": ea.y - base, "yb": eb.y - base}
	site.ends = [a, home]
	site.setup("bridge", 0, cost)
	Game.world_root.add_child(site)
	site.global_position = Vector3((ea.x + eb.x) * 0.5, base, (ea.z + eb.z) * 0.5)
	# The bridge is modelled along its own X axis, from the first Home.
	site.rotation.y = atan2(-(eb.z - ea.z), eb.x - ea.x)
	if Input.is_key_pressed(KEY_SHIFT):
		# Carry on from the second treehouse.
		_bridge_from = home
		_refresh_bridge_ghosts()
		hud.set_hint("Bridge marked out. Click the next treehouse to carry on from here.")
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
		if not terrain.is_dry(p.x, p.z):
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
	Game.palette_index = Art.palette_index
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
	elif mode == Mode.FIELD and _field_dragging:
		_ring.draw_loop(CropField.rect_corners(_field_center, _field_size, _field_yaw),
			Color(0.4, 1.0, 0.5) if _field_problem_text == "" else Color(1.0, 0.35, 0.3))
	elif mode == Mode.FIELD:
		_ring.draw(c, [0.6], Color(0.4, 1.0, 0.5))
	elif mode == Mode.BRIDGE:
		_bridge_hover = _home_at_mouse()
		var from_ok := _bridge_from != null and is_instance_valid(_bridge_from)
		if from_ok and _bridge_hover != null and _bridge_hover != _bridge_from:
			# A strip on the ground under where the bridge would hang.
			_bridge_problem_text = _bridge_problem(_bridge_from, _bridge_hover)
			var ea := RopeBridge.deck_edge(_bridge_from, _bridge_hover.global_position)
			var eb := RopeBridge.deck_edge(_bridge_hover, _bridge_from.global_position)
			var side := (eb - ea).cross(Vector3.UP).normalized() * 0.7
			_ring.draw_loop(PackedVector3Array([ea - side, eb - side, eb + side, ea + side]),
				Color(0.4, 1.0, 0.5) if _bridge_problem_text == "" else Color(1.0, 0.35, 0.3))
		elif _bridge_hover != null:
			_ring.draw(_bridge_hover.global_position, [_bridge_hover.footprint + 0.5], Color(0.4, 1.0, 0.5))
		elif from_ok:
			_ring.draw(_bridge_from.global_position, [_bridge_from.footprint + 0.5], Color(1.0, 0.9, 0.3))
		else:
			_ring.draw(c, [0.6], Color(0.4, 1.0, 0.5))
	else:
		_ring.clear()


func _update_ui() -> void:
	hud.set_resources(village, day_cycle.clock_text() if not _choosing else "")
	var costs: Array[int] = []
	var extras: Array[float] = []
	for k in SpellBook.SPELLS.size():
		costs.append(spell_cost(k))
		extras.append(recent_extra(k))
	hud.update_spells(village.amount("magicko"), costs, extras, not _choosing)
	hud.update_creature(creature)
	hud.set_blood(village.blood_active())
	if hud.is_build_menu_open():
		hud.update_build_menu(village)
	if hud.is_research_menu_open():
		hud.update_research(village)
	if mode == Mode.FIELD and _field_dragging:
		var cost: int = CropField.cost_for(_field_size).lumber
		hud.set_hint("Field %d x %d m: %d lumber.  %s" % [roundi(_field_size.x), roundi(_field_size.y), cost,
			_field_problem_text if _field_problem_text != "" else "Let go to plant it."])
	if _armed >= 0 and _is_judgement(_armed):
		_show_last_action(_armed, true)
	elif _hover_spell >= 0 and _is_judgement(_hover_spell) and not _choosing:
		_show_last_action(_hover_spell, false)
	if mode == Mode.BRIDGE and _bridge_from != null and is_instance_valid(_bridge_from) and _bridge_hover != null and _bridge_hover != _bridge_from:
		var length := _bridge_length(_bridge_from, _bridge_hover)
		hud.set_hint("Rope bridge %d m: %d lumber.  %s" % [roundi(length), BuildingCatalog.bridge_cost(length).lumber,
			_bridge_problem_text if _bridge_problem_text != "" else "Click to hang it.  Shift+click carries on from there."])
	if mode == Mode.PLACE and _ghost != null and _cursor_hit != null:
		hud.set_hint(_place_hint() if _ghost_valid else _ghost_problem + "  R rotate,  T another look,  Esc cancel.")
	if Game.dev_menu:
		var tree := get_tree()
		var goblins := tree.get_nodes_in_group("goblins").size()
		hud.set_stats("Villagers %d (yours %d, soldiers %d)   Goblins %d   Buildings %d\nTrees %d   Rocks %d   Fires %d   FPS %d" % [
			tree.get_nodes_in_group("villagers").size() - goblins, village.population(), village.soldiers(), goblins,
			tree.get_nodes_in_group("buildings").size(), tree.get_nodes_in_group("trees").size(),
			tree.get_nodes_in_group("rocks").size(), Game.fire.count(), Engine.get_frames_per_second()])
