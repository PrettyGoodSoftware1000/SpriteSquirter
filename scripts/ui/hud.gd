class_name Hud
extends CanvasLayer
## On-screen interface while playing.
##   top centre    resource counter, people, the day, the next birth and
##                 the jobs row (workers, warriors and wizards)
##   top left      title, hint for the current tool, Build and Menu buttons
##   bottom centre the spell bar
##   centre        the build menu (B / Backspace) and the start-location prompt
##   right         the dev menu (~): terrain tools, weather, palettes, grass,
##                 gameplay settings and stats
## The HUD only emits signals and shows what it is told; PlayMode does the work.

signal sculpt_selected(index: int)
signal spell_selected(index: int)
signal build_selected(kind: String)
signal build_menu_requested
signal menu_requested
signal regenerate_requested
signal mood_selected(index: int)
signal palette_selected(index: int)
signal grass_requested
signal setting_changed(key: String, value: float)
signal resources_requested
signal jobs_changed(role: String, change: int)
signal quota_changed(kind: String, change: int)
signal research_menu_requested
signal research_selected(id: String)

const SCULPT_NAMES := ["Raise", "Lower", "Flatten", "Smooth"]
const RESOURCE_COLORS := {
	"lumber": Color(0.95, 0.7, 0.42), "stone": Color(0.8, 0.82, 0.86), "food": Color(0.7, 0.92, 0.4),
	"people": Color(1.0, 0.95, 0.85), "magicko": Color(0.8, 0.6, 1.0), "bones": Color(0.95, 0.92, 0.8),
}
## key, label, min, max, step, unit
const SETTING_SLIDERS := [
	["day_minutes", "Day length", 1.0, 30.0, 0.5, "min"],
	["lumber_rate", "Lumber rate", 0.0, 60.0, 1.0, "/worker/min"],
	["stone_rate", "Stone rate", 0.0, 60.0, 1.0, "/worker/min"],
	["food_rate", "Food rate", 0.0, 60.0, 1.0, "/worker/min"],
	["birth_seconds", "Birth timer", 5.0, 300.0, 5.0, "s"],
	["magicko_rate", "Magicko rate", 0.0, 30.0, 0.5, "/villager/min"],
	["goblin_rate", "Goblin spawn", 0.0, 20.0, 0.5, "/cave/min"],
	["goblin_rate_growth", "Goblin spawn rise", 0.0, 10.0, 0.5, "/night"],
	["creature_food", "Creature food", 0.0, 100.0, 1.0, "/min full grown"],
	["creature_grow_minutes", "Creature grows in", 0.5, 60.0, 0.5, "min"],
]
const HELP := "WASD pan   Q/E rotate   Wheel zoom   Middle-drag tilt   Space find %s\nRight-click move %s   1-6 spells   B build   U research   Esc cancel / pause   ~ dev menu"
## role -> [name in the jobs row, the building that trains it]
const ROLES := {
	"warrior": ["Warriors", "Town guard"],
	"archer": ["Archers", "Town guard"],
	"wizard": ["Wizards", "Singing rocks"],
	"necromancer": ["Necromancers", "Necromancer tower"],
}

var _hint: Label
var _resource_labels := {}
var _sub_label: Label
var _clock: Label
var _jobs := {}
var _gather := {}
var _research_panel: PanelContainer
var _research_rows := {}
var _workers: Label
var _spell_buttons: Array[Button] = []
var _spell_bars: Array[ProgressBar] = []
var _build_panel: PanelContainer
var _build_buttons := {}
var _prompt_panel: PanelContainer
var _prompt: Label
var _sculpt_buttons: Array[Button] = []
var _mood_buttons: Array[Button] = []
var _palette_buttons: Array[Button] = []
var _setting_sliders := {}
var _grass_button: Button
var _brush: Label
var _stats: Label
var _dev_panel: PanelContainer
var _root: Control
var _blood := false
var _drop_timer := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root
	root.theme = UiTheme.get_theme()
	_build_player_panel(root)
	_build_resource_bar(root)
	_build_spell_bar(root)
	_build_build_menu(root)
	_build_research_menu(root)
	_build_prompt(root)
	_build_dev_menu(root)

	var help_panel := PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_panel.position = Vector2(-12, -12)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.modulate = Color(1, 1, 1, 0.75)
	root.add_child(help_panel)
	var help := Label.new()
	var beast: String = (Creature.SPECIES[Game.creature_kind].name as String).to_lower()
	help.text = HELP % [beast, beast]
	help.add_theme_font_size_override("font_size", 12)
	help_panel.add_child(help)


# --- Layout -------------------------------------------------------------------

func _build_player_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "SpriteSquirter"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var build := _button("Build (B)")
	build.pressed.connect(func() -> void: build_menu_requested.emit())
	buttons.add_child(build)
	var research := _button("Research (U)")
	research.pressed.connect(func() -> void: research_menu_requested.emit())
	buttons.add_child(research)
	var menu := _button("Menu")
	menu.pressed.connect(func() -> void: menu_requested.emit())
	buttons.add_child(menu)
	_hint = Label.new()
	_hint.custom_minimum_size = Vector2(320, 0)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)


func _build_resource_bar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 10
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for key in ["lumber", "stone", "food", "bones", "people", "magicko"]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.tooltip_text = key.capitalize()
		row.add_child(item)
		item.add_child(ResourceIcon.make(key, 24))
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", RESOURCE_COLORS[key])
		label.custom_minimum_size.x = 56 if key != "people" else 70
		item.add_child(label)
		_resource_labels[key] = label
	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", 16)
	_clock.modulate = Color(1.0, 0.9, 0.6)
	row.add_child(_clock)
	_sub_label = Label.new()
	_sub_label.add_theme_font_size_override("font_size", 13)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_sub_label)
	box.add_child(_build_jobs_row())
	box.add_child(_build_gather_row())


## Workers, and the number of warriors and wizards the player wants, with
## a grey bar filling over the count while recruits train.
func _build_jobs_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var title := _heading("Jobs")
	row.add_child(title)
	_workers = Label.new()
	_workers.add_theme_font_size_override("font_size", 15)
	row.add_child(_workers)
	for role: String in ROLES:
		var role_label := Label.new()
		role_label.text = ROLES[role][0]
		role_label.add_theme_font_size_override("font_size", 15)
		row.add_child(role_label)
		var less := _button("-")
		less.custom_minimum_size.x = 28
		less.pressed.connect(func() -> void: jobs_changed.emit(role, -1))
		row.add_child(less)
		var count := Label.new()
		count.add_theme_font_size_override("font_size", 15)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.custom_minimum_size = Vector2(56, 26)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(count)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		var empty := StyleBoxEmpty.new()
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.7, 0.7, 0.72, 0.45)
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", empty)
		bar.add_theme_stylebox_override("fill", fill)
		count.add_child(bar)
		var more := _button("+")
		more.custom_minimum_size.x = 28
		more.pressed.connect(func() -> void: jobs_changed.emit(role, 1))
		row.add_child(more)
		_jobs[role] = {"count": count, "bar": bar, "less": less, "more": more, "label": role_label}
	return row


## How many workers are felling, mining and getting food, with + and - to
## set workers to a job yourself.
func _build_gather_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.add_child(_heading("Gather"))
	var names := {"lumber": "Lumberjacks", "stone": "Miners", "food": "Farmers"}
	for kind: String in names:
		row.add_child(ResourceIcon.make(kind, 18))
		var label := _text(names[kind], 15)
		row.add_child(label)
		var less := _button("-")
		less.custom_minimum_size.x = 28
		less.pressed.connect(func() -> void: quota_changed.emit(kind, -1))
		row.add_child(less)
		var count := _text("0", 15)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.custom_minimum_size.x = 64
		count.mouse_filter = Control.MOUSE_FILTER_STOP
		count.tooltip_text = "Workers on this job (the number you set). The rest of your workers are shared out by themselves."
		row.add_child(count)
		var more := _button("+")
		more.custom_minimum_size.x = 28
		more.pressed.connect(func() -> void: quota_changed.emit(kind, 1))
		row.add_child(more)
		_gather[kind] = {"count": count, "less": less}
	return row


func _build_spell_bar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position.y = -12
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_heading("Spells"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for k in SpellBook.SPELLS.size():
		var spell: Dictionary = SpellBook.SPELLS[k]
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 2)
		row.add_child(slot)
		var b := _button("")
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(140, 58)
		var price: Control = ResourceIcon.cost_row({"magicko": spell.cost}, 15) if spell.cost > 0 else _text("a villager", 15)
		b.add_child(_stacked([_text("%d  %s" % [k + 1, spell.name], 16), price]))
		b.pressed.connect(func() -> void: spell_selected.emit(k))
		slot.add_child(b)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(140, 5)
		bar.max_value = 1.0
		bar.value = 0.0
		slot.add_child(bar)
		_spell_buttons.append(b)
		_spell_bars.append(bar)


func _build_build_menu(root: Control) -> void:
	_build_panel = PanelContainer.new()
	_build_panel.set_anchors_preset(Control.PRESET_CENTER)
	_build_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_build_panel.visible = false
	root.add_child(_build_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_build_panel.add_child(box)
	box.add_child(_heading("Build  (pick one, then place its outline or draw the field;  B / Esc to close)"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for k in BuildingCatalog.BUILDINGS.size():
		var info: Dictionary = BuildingCatalog.BUILDINGS[k]
		var b := _button("")
		b.custom_minimum_size = Vector2(250, 84)
		var title: String = "%d  %s" % [k + 1, info.name] if k < 9 else info.name
		var lines: Array[Control] = [_text(title, 16), _text(info.desc, 13)]
		if not (info.cost as Dictionary).is_empty():
			lines.append(ResourceIcon.cost_row(info.cost, 14))
		b.add_child(_stacked(lines))
		var kind: String = info.kind
		b.pressed.connect(func() -> void: build_selected.emit(kind))
		grid.add_child(b)
		_build_buttons[kind] = b
	var note := Label.new()
	note.text = "Villagers build it: all your workers help. The more a building costs, the longer it takes (a Home: under a minute for 10 villagers).\nWith no Storehouse, villagers carry what they gather to the middle of the village."
	note.add_theme_font_size_override("font_size", 13)
	note.modulate = Color(1, 1, 1, 0.75)
	box.add_child(note)


## The Blacksmith's research: one button for each thing to learn, with what
## it costs, how long it takes and how far along it is.
func _build_research_menu(root: Control) -> void:
	_research_panel = PanelContainer.new()
	_research_panel.set_anchors_preset(Control.PRESET_CENTER)
	_research_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_research_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_research_panel.visible = false
	root.add_child(_research_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_research_panel.add_child(box)
	box.add_child(_heading("Research  (needs a Blacksmith; one thing at a time;  U / Esc to close)"))
	for item in Research.ITEMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var b := _button("")
		b.custom_minimum_size = Vector2(430, 78)
		var minutes: float = item.seconds / 60.0
		var lines: Array[Control] = [_text(item.name, 16), _text("%s.  Takes %s min" % [item.desc, _number(minutes)], 13),
			ResourceIcon.cost_row(item.cost, 14)]
		b.add_child(_stacked(lines))
		var id: String = item.id
		b.pressed.connect(func() -> void: research_selected.emit(id))
		row.add_child(b)
		var state := VBoxContainer.new()
		state.alignment = BoxContainer.ALIGNMENT_CENTER
		state.custom_minimum_size.x = 130
		row.add_child(state)
		var status := _text("", 15)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state.add_child(status)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(130, 8)
		state.add_child(bar)
		_research_rows[id] = {"button": b, "status": status, "bar": bar}
	var note := Label.new()
	note.text = "The Blacksmith also gives your workers wheelbarrows, which carry three times as much."
	note.add_theme_font_size_override("font_size", 13)
	note.modulate = Color(1, 1, 1, 0.75)
	box.add_child(note)


func show_research_menu(shown: bool) -> void:
	_research_panel.visible = shown


func is_research_menu_open() -> bool:
	return _research_panel.visible


func update_research(village: PlayerVillage) -> void:
	var smith := village.has_blacksmith()
	for item in Research.ITEMS:
		var row: Dictionary = _research_rows[item.id]
		var b := row.button as Button
		var done := village.has_research(item.id)
		var running: bool = village.research.get("id", "") == item.id
		var progress := village.research_progress(item.id)
		(row.bar as ProgressBar).value = progress
		(row.bar as ProgressBar).visible = running
		var status := row.status as Label
		if done:
			status.text = "Done"
		elif running:
			status.text = "%d%%" % floori(progress * 100.0)
		elif not smith:
			status.text = "No Blacksmith"
		else:
			status.text = ""
		b.disabled = done or running
		b.modulate = Color.WHITE if done or running or village.can_afford(item.cost) else Color(1.0, 0.6, 0.6, 0.8)


func _build_prompt(root: Control) -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.position.y = 132
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	root.add_child(_prompt_panel)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt)


func _build_dev_menu(root: Control) -> void:
	_dev_panel = PanelContainer.new()
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dev_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_panel.position = Vector2(-12, 132)
	root.add_child(_dev_panel)
	var dev := VBoxContainer.new()
	dev.add_theme_constant_override("separation", 4)
	_dev_panel.add_child(dev)
	dev.add_child(_heading("Dev menu  (~ to hide)"))

	dev.add_child(_heading("Gameplay"))
	for s in SETTING_SLIDERS:
		dev.add_child(_setting_row(s))
	var cheat := _button("Give 100 of everything")
	cheat.pressed.connect(func() -> void: resources_requested.emit())
	dev.add_child(cheat)

	dev.add_child(_heading("Terrain tools"))
	var sculpt := HBoxContainer.new()
	dev.add_child(sculpt)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for k in SCULPT_NAMES.size():
		var b := _button("%d %s" % [k + 4, SCULPT_NAMES[k]])
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void: sculpt_selected.emit(k))
		sculpt.add_child(b)
		_sculpt_buttons.append(b)
	_brush = Label.new()
	dev.add_child(_brush)
	var regen := _button("New random world (N)")
	regen.pressed.connect(func() -> void: regenerate_requested.emit())
	dev.add_child(regen)

	dev.add_child(_heading("Weather (L)"))
	var moods := GridContainer.new()
	moods.columns = 4
	dev.add_child(moods)
	var mood_group := ButtonGroup.new()
	for k in Atmosphere.MOODS.size():
		var b := _button(Atmosphere.MOODS[k].name)
		b.toggle_mode = true
		b.button_group = mood_group
		b.pressed.connect(func() -> void: mood_selected.emit(k))
		moods.add_child(b)
		_mood_buttons.append(b)

	dev.add_child(_heading("Nature palette (P)"))
	var palettes := GridContainer.new()
	palettes.columns = 6
	dev.add_child(palettes)
	var palette_group := ButtonGroup.new()
	for k in Art.PALETTES.size():
		var b := _button(Art.PALETTES[k].name)
		b.toggle_mode = true
		b.button_group = palette_group
		b.pressed.connect(func() -> void: palette_selected.emit(k))
		palettes.add_child(b)
		_palette_buttons.append(b)

	_grass_button = _button("Grass")
	_grass_button.pressed.connect(func() -> void: grass_requested.emit())
	dev.add_child(_grass_button)

	_stats = Label.new()
	_stats.modulate = Color(1, 1, 1, 0.8)
	_stats.add_theme_font_size_override("font_size", 13)
	dev.add_child(_stats)


func _setting_row(s: Array) -> Control:
	var key: String = s[0]
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size.x = 230
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = s[2]
	slider.max_value = s[3]
	slider.step = s[4]
	slider.custom_minimum_size = Vector2(150, 20)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var update := func(value: float) -> void:
		label.text = "%s: %s %s" % [s[1], _number(value), s[5]]
	slider.value_changed.connect(func(value: float) -> void:
		update.call(value)
		setting_changed.emit(key, value))
	_setting_sliders[key] = [slider, update]
	return row


## Lines stacked in the middle of a button; clicks pass through to it.
func _stacked(lines: Array[Control]) -> Control:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in lines:
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(line)
	return box


func _text(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(1.0, 0.9, 0.6)
	return label


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	return b


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


# --- Updates from PlayMode ----------------------------------------------------

func set_hint(text: String) -> void:
	_hint.text = text


func set_prompt(text: String) -> void:
	_prompt_panel.visible = text != ""
	_prompt.text = text


func set_resources(village: PlayerVillage, clock: String) -> void:
	for res in PlayerVillage.RESOURCES:
		_resource_labels[res].text = str(village.amount(res))
	if village.blood_active():
		_resource_labels.magicko.text += " x2"
	var pop := village.population()
	var cap := village.housing()
	_resource_labels.people.text = "%d/%d" % [pop, cap]
	_update_jobs(village)
	_clock.text = clock
	_sub_label.visible = village.founded
	if not village.founded:
		return
	var kids := pop - village.adults()
	var parts: PackedStringArray = []
	var next := village.next_birth_in()
	if village.amount("food") <= 0:
		parts.append("Out of food! No births, and people will starve" if village.hungry_for < PlayerVillage.STARVE_AFTER else "Starving!")
	else:
		parts.append("Next villager in %d s" % ceili(next) if next >= 0.0 else "No room for more villagers: build a Home")
	parts.append("Eating %d food/min" % roundi(village.food_upkeep()))
	var beast := Game.creature
	if is_instance_valid(beast):
		var state := "%s %d%% grown" % [beast.species_name(), roundi(beast.grown() * 100.0)] if beast.grown() < 0.995 else beast.species_name()
		state += ", knocked out" if beast.knocked_out else ", health %d%%" % roundi(100.0 * beast.hp / maxf(beast.max_hp, 1.0))
		parts.append(state)
	if kids > 0:
		parts.append("%d growing up" % kids)
	var sites := get_tree().get_nodes_in_group("construction_sites").size()
	if sites > 0:
		parts.append("%d building%s under construction" % [sites, "" if sites == 1 else "s"])
	_sub_label.text = "   ".join(parts)


func _update_jobs(village: PlayerVillage) -> void:
	_workers.text = "Workers %d" % village.workers()
	for kind: String in _gather:
		var set_by_player: int = village.quota[kind]
		(_gather[kind].count as Label).text = str(village.gatherers[kind]) if set_by_player == 0 else "%d (%d set)" % [village.gatherers[kind], set_by_player]
		(_gather[kind].less as Button).disabled = set_by_player <= 0
	for role: String in _jobs:
		var w: Dictionary = _jobs[role]
		var top := village.max_count(role)
		var want: int = village.wanted[role]
		(w.count as Label).text = "%d/%d" % [village.count(role), want]
		(w.count as Label).tooltip_text = "Trained / wanted. Up to %d with your %s buildings." % [top, ROLES[role][1]]
		# Archers appear once bows have been researched, and necromancers
		# once there is a tower for them.
		var known := role != "archer" or village.has_research("bows")
		if role == "necromancer":
			known = top > 0 or village.count(role) > 0
		for part: String in ["count", "less", "more", "label"]:
			(w[part] as Control).visible = known
		(w.more as Button).disabled = want >= top
		(w.less as Button).disabled = want <= 0
		var progress := village.training_progress(role)
		var bar := w.bar as ProgressBar
		bar.visible = not progress.is_empty()
		if bar.visible:
			var total := 0.0
			for t in progress:
				total += t
			bar.value = total / progress.size()


## Blood Sacrifice is running: the magicko counter turns red and bleeds.
func set_blood(active: bool) -> void:
	if active == _blood:
		return
	_blood = active
	var label: Label = _resource_labels.magicko
	label.add_theme_color_override("font_color", Color(1.0, 0.12, 0.12) if active else RESOURCE_COLORS.magicko)


func _process(delta: float) -> void:
	if not _blood:
		return
	_drop_timer -= delta
	if _drop_timer > 0.0:
		return
	_drop_timer = randf_range(0.1, 0.28)
	# A little drop of blood falls from the magicko counter and fades.
	var label: Label = _resource_labels.magicko
	var drop := Panel.new()
	var shape := StyleBoxFlat.new()
	shape.bg_color = Color(0.85, 0.04, 0.06)
	shape.corner_radius_top_left = 1
	shape.corner_radius_top_right = 1
	shape.corner_radius_bottom_left = 4
	shape.corner_radius_bottom_right = 4
	drop.add_theme_stylebox_override("panel", shape)
	drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop.size = Vector2(5, 9) * randf_range(0.7, 1.2)
	drop.position = label.global_position + Vector2(randf_range(0.0, 0.75) * label.size.x, label.size.y - 4.0)
	_root.add_child(drop)
	var fall := drop.create_tween().set_parallel(true)
	fall.tween_property(drop, "position:y", drop.position.y + randf_range(34.0, 60.0), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(drop, "modulate:a", 0.0, 0.75).set_ease(Tween.EASE_IN)
	fall.chain().tween_callback(drop.queue_free)


func set_spell(index: int) -> void:
	for k in _spell_buttons.size():
		_spell_buttons[k].set_pressed_no_signal(k == index)


## `cooldowns` holds the seconds left for each spell.
func update_spells(magicko: int, cooldowns: Array, enabled: bool) -> void:
	for k in _spell_buttons.size():
		var spell: Dictionary = SpellBook.SPELLS[k]
		var cool: float = cooldowns[k]
		var ready_now: bool = enabled and magicko >= spell.cost and cool <= 0.0
		_spell_buttons[k].modulate = Color.WHITE if ready_now else Color(1.0, 0.6, 0.6, 0.75)
		_spell_bars[k].value = clampf(cool / maxf(spell.cooldown, 0.01), 0.0, 1.0)


func show_build_menu(shown: bool) -> void:
	_build_panel.visible = shown


func is_build_menu_open() -> bool:
	return _build_panel.visible


func update_build_menu(village: PlayerVillage) -> void:
	for info in BuildingCatalog.BUILDINGS:
		var b: Button = _build_buttons[info.kind]
		b.modulate = Color.WHITE if village.can_afford(info.cost) else Color(1.0, 0.6, 0.6, 0.8)


func set_settings(values: Dictionary) -> void:
	for key in _setting_sliders:
		var entry: Array = _setting_sliders[key]
		(entry[0] as HSlider).set_value_no_signal(values[key])
		(entry[1] as Callable).call(values[key])


func set_dev_visible(shown: bool) -> void:
	_dev_panel.visible = shown


func set_sculpt(index: int) -> void:
	for k in _sculpt_buttons.size():
		_sculpt_buttons[k].set_pressed_no_signal(k == index)


func set_brush(radius: float) -> void:
	_brush.text = "Brush radius: %d m   ( [ ] )" % roundi(radius)


func set_mood(index: int) -> void:
	for k in _mood_buttons.size():
		_mood_buttons[k].set_pressed_no_signal(k == index)


func set_palette(index: int) -> void:
	for k in _palette_buttons.size():
		_palette_buttons[k].set_pressed_no_signal(k == index)


func set_grass(level_name: String) -> void:
	_grass_button.text = "Grass detail (G): %s" % level_name


func set_stats(text: String) -> void:
	_stats.text = text
