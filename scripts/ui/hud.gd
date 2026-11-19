class_name Hud
extends CanvasLayer
## On-screen interface while playing.
##   top left      the village: people and the next birth, the day, each
##                 resource and what came in over the last minute, the
##                 workers set to gather it, builders, warriors and wizards
##   bottom centre hint for the current tool, Build and Research buttons,
##                 the spell bar, and the creature's health, stamina and
##                 magicko (with a Resurrect button while it is dead)
##   centre        the build menu (B / Backspace) and the start-location prompt
##   right         the dev menu (~): terrain tools, weather, palettes, grass,
##                 gameplay settings and stats
## The HUD only emits signals and shows what it is told; PlayMode does the work.

signal sculpt_selected(index: int)
signal spell_selected(index: int)
## The mouse went over spell button `index`, or off the spell buttons (-1).
signal spell_hovered(index: int)
signal build_selected(kind: String)
signal build_menu_requested
signal regenerate_requested
signal mood_selected(index: int)
signal palette_selected(index: int)
signal grass_requested
signal ruler_requested
signal sliders_save_requested
signal sliders_load_requested
signal setting_changed(key: String, value: float)
signal resources_requested
signal jobs_changed(role: String, change: int)
signal quota_changed(kind: String, change: int)
signal research_menu_requested
signal research_selected(id: String)
## Spell `index` was dragged onto spell `onto` on the spell bar.
signal spell_moved(index: int, onto: int)
## A spell picked in the Shrine's research menu.
signal spell_research_selected(id: String)
## The dev menu's "Learn all spells".
signal spells_requested
signal resurrect_requested
## The creature's portrait was clicked (to pay for its growth).
signal grow_requested
## One of the creature's bars was double-clicked (to find it).
signal creature_focus_requested

const SCULPT_NAMES := ["Raise", "Lower", "Flatten", "Smooth"]
const RESOURCE_COLORS := {
	"lumber": Color(0.95, 0.7, 0.42), "stone": Color(0.8, 0.82, 0.86), "food": Color(0.7, 0.92, 0.4),
	"people": Color(1.0, 0.95, 0.85), "magicko": Color(0.8, 0.6, 1.0), "bones": Color(0.95, 0.92, 0.8),
	"animus": Color(1.0, 0.88, 0.35),
}
## Resource icons in the village panel, and the spell squares (half of 3 times as big).
const ICON_SIZE := 24
## The size of all the HUD's text.
const FONT_SIZE := 12
const SPELL_SIZE := 36  # half of three resource icons
## gathering job -> what one worker on it is called
const JOB_NAMES := {"lumber": "lumberjack", "stone": "miner", "food": "farmer", "build": "builder"}
## key, label, min, max, step, unit
const SETTING_SLIDERS := [
	["day_minutes", "Day length", 1.0, 30.0, 0.5, "min"],
	["lumber_rate", "Lumber rate", 0.0, 60.0, 1.0, "/worker/min"],
	["stone_rate", "Stone rate", 0.0, 60.0, 1.0, "/worker/min"],
	["food_rate", "Food rate", 0.0, 60.0, 1.0, "/worker/min"],
	["birth_seconds", "Birth timer", 5.0, 300.0, 5.0, "s"],
	["magicko_rate", "Magicko rate", 0.0, 30.0, 0.5, "/villager/min"],
	["goblin_rate", "Goblin spawn", 0.0, 20.0, 0.5, "/cave/min"],
	["creature_food", "Creature food", 0.0, 100.0, 1.0, "/min full grown"],
	["creature_grow_minutes", "Creature grows in", 0.5, 60.0, 0.5, "min"],
	["goblin_build_speed", "Goblin build speed", 0.25, 10.0, 0.25, "x"],
	["sapling_rate", "Saplings planted", 0.0, 20.0, 0.5, "a minute"],
	["villager_detail", "Villager detail within", 0.0, 300.0, 10.0, "m"],
	["construction_rate", "Construction rate", 0.25, 10.0, 0.25, "x"],
	["training_time", "Training time", 0.1, 3.0, 0.1, "x"],
	["influence_start", "Starting influence", 10.0, 150.0, 5.0, "m"],
	["influence_per_person", "Influence per person", 0.0, 5.0, 0.25, "m"],
	["night_darkness", "Night darkness", -150.0, 90.0, 5.0, "%"],
]
const BAR_COLORS := {"health": Color(0.78, 0.2, 0.18), "stamina": Color(0.3, 0.66, 0.26), "magicko": Color(0.5, 0.34, 0.86)}
## role -> [name in the jobs row, the building that trains it]
## role -> [name in the panel, the building that trains it, one of them]
const ROLES := {
	"warrior": ["Warriors", "guard", "warrior"],
	"archer": ["Archers", "guard", "archer"],
	"wizard": ["Wizards", "wizard", "wizard"],
	"necromancer": ["Necromancers", "necro", "necromancer"],
	"fey_archer": ["Fey Archers", "guard", "fey archer"],
}

var _hint: Label
var _resource_labels := {}
var _rate_labels := {}
var _warning: Label
var _workers_count: Label
var _resurrect: Button
var _clock: Label
var _jobs := {}
var _gather := {}
var _research_panel: PanelContainer
var _research_rows := {}
var _workers: Label
var _spell_buttons: Array[Button] = []
var _spell_costs: Array[Label] = []
var _spell_sparkles: Array[SpellSparkles] = []
## Each spell's square and cost (shown only once it is known, in
## the village's order), and the key number in its corner.
var _spell_slots: Array[Control] = []
var _spell_keys: Array[Label] = []
## Each spell's slot on the bar (-1: not on it); the slots, and the rows.
var _spell_slot_of: Array[int] = []
var _slot_holders: Array[SlotHolder] = []
var _spell_lines: Array[HBoxContainer] = []
var _add_row_button: Button
var _remove_row_button: Button
## The highest slot with a spell in it (so its row is shown).
var _last_used_slot := -1
var _spell_research_panel: PanelContainer
var _spell_research_title: Label
var _spell_research_rows := {}
## The creature's bars: stat -> [bar, label]
var _creature_bars := {}
## Its portrait: its model seen three-quarters on, drawn once in a little
## world of its own, which sparkles yellow when it can grow on (click to
## pay the animus).
var _portrait: SubViewportContainer
var _portrait_view: SubViewport
var _portrait_kind := ""
var _portrait_sparkles: SpellSparkles
## Beside the portrait: how far the creature has grown (yellow, rising),
## with what it cannot grow into without more animus in grey.
var _growth_bar: GrowthBar
var _build_panel: PanelContainer
var _build_buttons := {}
var _build_previews: Array[BuildingPreview] = []
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


## Spells not on the bar are kept out of the tree: free them with the HUD.
func _exit_tree() -> void:
	for spell in _spell_slots:
		if is_instance_valid(spell) and spell.get_parent() == null:
			spell.free()


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root
	# Every piece of text on the HUD is one size (the size of "Warriors").
	var look := UiTheme.get_theme().duplicate() as Theme
	look.default_font_size = FONT_SIZE
	root.theme = look
	_build_status_panel(root)
	_build_spell_bar(root)
	_build_build_menu(root)
	_build_research_menu(root)
	_build_spell_research_menu(root)
	_build_prompt(root)
	_build_dev_menu(root)


# --- Layout -------------------------------------------------------------------

## The village panel in the top left corner: people (the bar behind the
## count fills towards the next birth) and the day; the unassigned
## Workers and the Builders; each resource with what came in (or went out)
## over the last minute, and beside lumber, stone and food the workers set
## to gather it; then warriors, archers, wizards and necromancers.
func _build_status_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(10, 10)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	top.add_child(ResourceIcon.make("people", ICON_SIZE))
	var people := _text("", 12)
	people.add_theme_color_override("font_color", RESOURCE_COLORS.people)
	people.custom_minimum_size = Vector2(84, 28)
	people.mouse_filter = Control.MOUSE_FILTER_STOP
	people.tooltip_text = "Villagers / room for them. The bar fills towards the next birth."
	people.add_child(_fill_bar(Color(1.0, 0.95, 0.85, 0.3)))
	top.add_child(people)
	_resource_labels.people = people
	_clock = _text("", 12)
	_clock.modulate = Color(1.0, 0.9, 0.6)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_clock)
	_warning = _text("", 12)
	_warning.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_warning.visible = false
	box.add_child(_warning)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	box.add_child(grid)
	_workers = _text("Workers", 12)
	_workers.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_workers.mouse_filter = Control.MOUSE_FILTER_STOP
	_workers.tooltip_text = "Villagers you have not set to a job. They gather whatever is most needed and help on building sites."
	grid.add_child(_workers)
	_workers_count = _text("", 12)
	grid.add_child(_workers_count)
	var builders := _text("Builders", 12)
	builders.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	builders.mouse_filter = Control.MOUSE_FILTER_STOP
	builders.tooltip_text = "Builders only build: they are first onto every building site, and wait when there is nothing to build."
	grid.add_child(builders)
	grid.add_child(_quota_controls("build"))
	for res: String in PlayerVillage.RESOURCES:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.tooltip_text = res.capitalize()
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.add_child(ResourceIcon.make(res, ICON_SIZE))
		var amount := _text("", 12)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		amount.add_theme_color_override("font_color", RESOURCE_COLORS[res])
		amount.custom_minimum_size.x = 46
		item.add_child(amount)
		var rate := _text("", 12)
		rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rate.add_theme_color_override("font_color", RESOURCE_COLORS[res])
		rate.custom_minimum_size.x = 40
		item.add_child(rate)
		_resource_labels[res] = amount
		_rate_labels[res] = rate
		grid.add_child(item)
		if JOB_NAMES.has(res):
			grid.add_child(_quota_controls(res))
		else:
			grid.add_child(Control.new())
	var army := GridContainer.new()
	army.columns = 2
	army.add_theme_constant_override("h_separation", 10)
	army.add_theme_constant_override("v_separation", 1)
	box.add_child(army)
	for role: String in ROLES:
		var role_label := _text(ROLES[role][0], 12)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		army.add_child(role_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		army.add_child(row)
		var singular: String = ROLES[role][2]
		var less := _button("-")
		less.custom_minimum_size = Vector2(20, 18)
		less.add_theme_font_size_override("font_size", 12)
		less.tooltip_text = "Remove %s" % singular
		less.pressed.connect(func() -> void: jobs_changed.emit(role, -1))
		row.add_child(less)
		var count := _text("", 12)
		count.custom_minimum_size = Vector2(40, 18)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_STOP
		var bar := _fill_bar(Color(0.7, 0.7, 0.72, 0.45))
		count.add_child(bar)
		row.add_child(count)
		var more := _button("+")
		more.custom_minimum_size = Vector2(20, 18)
		more.add_theme_font_size_override("font_size", 12)
		more.tooltip_text = "Add %s" % singular
		more.pressed.connect(func() -> void: jobs_changed.emit(role, 1))
		row.add_child(more)
		_jobs[role] = {"count": count, "bar": bar, "less": less, "more": more, "label": role_label, "row": row}


## - count + for one gathering job (or the builders).
func _quota_controls(kind: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var singular: String = JOB_NAMES[kind]
	var less := _button("-")
	less.custom_minimum_size.x = 28
	less.tooltip_text = "Remove %s" % singular
	less.pressed.connect(func() -> void: quota_changed.emit(kind, -1))
	row.add_child(less)
	var count := _text("0", 12)
	count.custom_minimum_size.x = 34
	count.mouse_filter = Control.MOUSE_FILTER_STOP
	count.tooltip_text = "Villagers you have set to gather this. + takes one of the unassigned Workers, - sends one back." if kind != "build" \
		else "Builders only build: they are first onto every building site, and wait when there is nothing to build."
	row.add_child(count)
	var more := _button("+")
	more.custom_minimum_size.x = 28
	more.tooltip_text = "Add %s" % singular
	more.pressed.connect(func() -> void: quota_changed.emit(kind, 1))
	row.add_child(more)
	_gather[kind] = {"count": count, "less": less, "more": more}
	return row


## A bar that fills from the left behind a label.
func _fill_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.show_behind_parent = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build_spell_bar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position.y = -12
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	# What the tool in hand does, and why something can't be done.
	_hint = Label.new()
	_hint.custom_minimum_size = Vector2(700, 0)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var menus := VBoxContainer.new()
	menus.add_theme_constant_override("separation", 2)
	menus.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(menus)
	# The build menu: a hammer. (Research: click a Blacksmith, or U.)
	var build := _button("")
	build.icon = spell_icon("hammer")
	build.expand_icon = true
	build.custom_minimum_size = Vector2(SPELL_SIZE, SPELL_SIZE)
	build.tooltip_text = "Build (B or Backspace)"
	build.pressed.connect(func() -> void: build_menu_requested.emit())
	menus.add_child(build)
	# The spell bar: rows of SpellLayout.PER_ROW slots (room for 10 spells
	# whatever is known), one row to begin with; the + in its corner adds a
	# second (Ctrl + number) above it and a third (Shift + number) above
	# that, and the - takes them away again. Each spell is a
	# square with its sign (the one the mouse pointer turns into when it is
	# in hand), its key in the corner and its cost underneath; drag it onto
	# another slot to move it there.
	var spell_area := VBoxContainer.new()
	spell_area.add_theme_constant_override("separation", 2)
	spell_area.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(spell_area)
	var row_buttons := HBoxContainer.new()
	row_buttons.add_theme_constant_override("separation", 2)
	spell_area.add_child(row_buttons)
	_add_row_button = _button("+")
	_add_row_button.custom_minimum_size = Vector2(16, 16)
	_add_row_button.add_theme_font_size_override("font_size", 12)
	_add_row_button.pressed.connect(func() -> void:
		SpellLayout.set_rows(_spell_row_count() + 1)
		_show_spell_rows())
	row_buttons.add_child(_add_row_button)
	_remove_row_button = _button("-")
	_remove_row_button.custom_minimum_size = Vector2(16, 16)
	_remove_row_button.add_theme_font_size_override("font_size", 12)
	_remove_row_button.pressed.connect(func() -> void:
		SpellLayout.set_rows(_spell_row_count() - 1)
		_show_spell_rows())
	row_buttons.add_child(_remove_row_button)
	for r in SpellLayout.ROWS_MOST:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		# (Each row goes above the one before: the first stays at the bottom.)
		spell_area.add_child(line)
		spell_area.move_child(line, 1)
		var prefix := _text(["", "Ctrl", "Shift"][r], 12)
		prefix.custom_minimum_size.x = 30
		prefix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(prefix)
		for c in SpellLayout.PER_ROW:
			var holder := SlotHolder.new()
			holder.slot = r * SpellLayout.PER_ROW + c
			holder.custom_minimum_size = Vector2(SPELL_SIZE, SPELL_SIZE + 16)
			holder.on_drop = func(from: int, onto_slot: int) -> void: spell_moved.emit(from, onto_slot)
			line.add_child(holder)
			_slot_holders.append(holder)
		_spell_lines.append(line)
	for k in SpellBook.SPELLS.size():
		var spell: Dictionary = SpellBook.SPELLS[k]
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 1)
		slot.set_anchors_preset(Control.PRESET_FULL_RECT)
		var b := SpellButton.new()
		b.spell_index = k
		b.on_drop = func(from: int, onto: int) -> void: spell_moved.emit(from, _spell_slot_of[onto])
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(SPELL_SIZE, SPELL_SIZE)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var icon := TextureRect.new()
		icon.texture = spell_icon(spell.id)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var key := _text("", 12)
		key.position = Vector2(2, -3)
		key.modulate = Color(1, 1, 1, 0.75)
		key.add_theme_color_override("font_outline_color", Color.BLACK)
		key.add_theme_constant_override("outline_size", 3)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(key)
		var sparkles := SpellSparkles.new()
		b.add_child(sparkles)
		b.pressed.connect(func() -> void: spell_selected.emit(k))
		b.mouse_entered.connect(func() -> void: spell_hovered.emit(k))
		b.mouse_exited.connect(func() -> void: spell_hovered.emit(-1))
		slot.add_child(b)
		var cost_label: Label = null
		if SpellBook.cost(spell.id) > 0:
			var cost_row := ResourceIcon.cost_row({"magicko": SpellBook.cost(spell.id)}, 12)
			cost_label = cost_row.get_child(0) as Label
			slot.add_child(cost_row)
		else:
			slot.add_child(_text("free", 12))
		_spell_buttons.append(b)
		_spell_costs.append(cost_label)
		_spell_sparkles.append(sparkles)
		_spell_slots.append(slot)
		_spell_keys.append(key)
		_spell_slot_of.append(-1)
	_show_spell_rows()
	# The creature's growth bar, its portrait, then its health, stamina and
	# magicko.
	_growth_bar = GrowthBar.new()
	_growth_bar.custom_minimum_size = Vector2(7, 64)
	_growth_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_growth_bar)
	_portrait = SubViewportContainer.new()
	_portrait.custom_minimum_size = Vector2(64, 64)
	_portrait.stretch = true
	_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_END
	_portrait.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			grow_requested.emit())
	row.add_child(_portrait)
	_portrait_view = SubViewport.new()
	_portrait_view.size = Vector2i(64, 64)
	_portrait_view.own_world_3d = true
	_portrait_view.transparent_bg = true
	_portrait_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_portrait.add_child(_portrait_view)
	_portrait_sparkles = SpellSparkles.new()
	_portrait_sparkles.wash = Color(1.0, 0.8, 0.15)
	_portrait_sparkles.glint = Color(1.0, 0.92, 0.45)
	_portrait.add_child(_portrait_sparkles)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 3)
	stats.alignment = BoxContainer.ALIGNMENT_END
	# (At the bottom, where it stays however tall the spell bar grows.)
	stats.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(stats)
	_resurrect = _button("Resurrect at the %s (%d animus)" % [BuildingCatalog.role_name("shrine"), roundi(Balance.num("resurrect_animus"))])
	_resurrect.tooltip_text = "Your creature is dead. Bring it back to life beside the %s." % BuildingCatalog.role_name("shrine")
	_resurrect.add_theme_color_override("font_color", RESOURCE_COLORS.animus)
	_resurrect.pressed.connect(func() -> void: resurrect_requested.emit())
	_resurrect.visible = false
	stats.add_child(_resurrect)
	for stat: String in ["health", "stamina", "magicko"]:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(190, 19)
		bar.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_COLORS[stat]
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.08, 0.07, 0.1, 0.85)
		back.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", back)
		var label := _text("", 12)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		bar.add_child(label)
		stats.add_child(bar)
		_creature_bars[stat] = [bar, label]
		# A double click on any of them finds the creature.
		bar.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.gui_input.connect(func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click and click.pressed and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
				creature_focus_requested.emit())


## The creature's bars, each with its level and how much of it has been
## used towards the next. While the creature is dead, the Resurrect button.
func update_creature(beast: Creature) -> void:
	if not is_instance_valid(beast):
		return
	_resurrect.visible = beast.knocked_out
	var values := {"health": [beast.hp, beast.max_hp], "stamina": [beast.stamina, beast.max_stamina], "magicko": [beast.magicko, beast.max_magicko]}
	for stat: String in values:
		var now: float = values[stat][0]
		var most: float = maxf(values[stat][1], 1.0)
		(_creature_bars[stat][0] as ProgressBar).value = clampf(now / most, 0.0, 1.0)
		var text := "%s %d / %d   Lv %d (%d/%d)" % [stat.capitalize(), roundi(now), roundi(most), int(beast.levels[stat]) + 1,
			floori(beast.used[stat]), roundi(beast.level_cost(stat))]
		if stat == "health" and beast.knocked_out:
			text = "Dead"
		(_creature_bars[stat][1] as Label).text = text
	_update_portrait(beast)


## Points the portrait's camera at the creature's face and redraws it now
## and then; sparkles when it can grow on; says how it is growing.
func _update_portrait(beast: Creature) -> void:
	_portrait_sparkles.set_extra(SpellSparkles.FULL * 0.6 if beast.can_grow() else 0.0)
	_growth_bar.set_values(beast.grown(), float(beast.growth_paid) / 10.0)
	var village := Game.village
	var have: int = village.amount("animus") if is_instance_valid(village) else 0
	if beast.growth_paid >= 10:
		_portrait.tooltip_text = "%s: grown %d%%. Fully paid for." % [beast.species_name(), roundi(beast.grown() * 100.0)]
	else:
		_portrait.tooltip_text = "%s: grown %d%%, step %d of 10 paid for.\nThe next step costs %d animus (you have %d).%s" % [
			beast.species_name(), roundi(beast.grown() * 100.0), beast.growth_paid, beast.growth_cost(), have,
			"\nClick to grow." if beast.can_grow() else ""]
	if _portrait_kind != beast.kind:
		_portrait_kind = beast.kind
		_pose_portrait(Creature.SPECIES[beast.kind].model)


## Puts the creature's model (`model`, a scene) in the portrait's little
## world, three-quarters on, lit from the side, and draws it once.
func _pose_portrait(model: String) -> void:
	for child in _portrait_view.get_children():
		child.queue_free()
	var body := (load(model) as PackedScene).instantiate() as Node3D
	var hide := ShaderMaterial.new()
	hide.shader = Art.shader("creature")
	hide.set_shader_parameter("detail_tex", Art.tex("hide_detail"))
	hide.next_pass = Art.outline(1.0)
	for node in body.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = hide
	body.rotation.y = deg_to_rad(35.0)
	_portrait_view.add_child(body)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	_portrait_view.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(-40.0), 0.0)
	sun.light_energy = 1.2
	_portrait_view.add_child(sun)
	# Framed on the whole model.
	var box := AABB()
	var first := true
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b := mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var cam := Camera3D.new()
	cam.fov = 30.0
	var middle := box.get_center()
	var reach := maxf(box.size.y, maxf(box.size.x, box.size.z)) * 0.5 / tan(deg_to_rad(15.0)) * 1.15
	_portrait_view.add_child(cam)
	cam.look_at_from_position(middle + Vector3(0.0, 0.15, 1.0).normalized() * reach, middle)
	_portrait_view.render_target_update_mode = SubViewport.UPDATE_ONCE


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
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for k in BuildingCatalog.BUILDINGS.size():
		var info: Dictionary = BuildingCatalog.BUILDINGS[k]
		var b := _button("")
		b.custom_minimum_size = Vector2(330, 100)
		var title: String = "%d  %s" % [k + 1, info.title] if k < 9 else (info.title as String)
		var lines: Array[Control] = [_text(title, 12), _text(info.desc, 12)]
		if not (info.cost as Dictionary).is_empty():
			lines.append(ResourceIcon.cost_row(info.cost, 12))
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 4
		row.offset_right = -4
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		# A picture of the model (the field and the bridge have none).
		if info.role != "field" and info.role != "bridge":
			var picture := BuildingPreview.make(info.kind, Vector2i(120, 92))
			picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(picture)
			_build_previews.append(picture)
		var text := _stacked(lines)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var kind: String = info.kind
		b.pressed.connect(func() -> void: build_selected.emit(kind))
		grid.add_child(b)
		_build_buttons[kind] = b


## Research at the Blacksmith or the Wizardry tower: one button for each
## thing to learn there, with what it costs, how long it takes and how far
## along it is.
var _research_place := "smith"
var _research_heading: Label


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
	_research_heading = _heading("")
	box.add_child(_research_heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for item in Research.ITEMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		grid.add_child(row)
		var b := _button("")
		b.custom_minimum_size = Vector2(330, 62)
		var minutes: float = item.seconds / 60.0
		var lines: Array[Control] = [_text(item.name, 12), _text("%s.  Takes %s min" % [item.desc, _number(minutes)], 12),
			ResourceIcon.cost_row(item.cost, 12)]
		b.add_child(_stacked(lines))
		var id: String = item.id
		b.pressed.connect(func() -> void: research_selected.emit(id))
		row.add_child(b)
		var state := VBoxContainer.new()
		state.alignment = BoxContainer.ALIGNMENT_CENTER
		state.custom_minimum_size.x = 130
		row.add_child(state)
		var status := _text("", 12)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state.add_child(status)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(130, 8)
		state.add_child(bar)
		_research_rows[id] = {"button": b, "status": status, "bar": bar, "row": row}


## Opens (or closes) the research of `place`: "smith" (the Blacksmith) or
## "wizard" (the Wizardry tower).
func show_research_menu(shown: bool, place := "") -> void:
	_research_panel.visible = shown
	if place != "":
		_research_place = place
	_research_heading.text = "%s: research, one thing at a time  (Esc to close)" % BuildingCatalog.role_name(_research_place)
	for item in Research.ITEMS:
		(_research_rows[item.id].row as Control).visible = item.place == _research_place


func is_research_menu_open() -> bool:
	return _research_panel.visible


func update_research(village: PlayerVillage) -> void:
	for item in Research.ITEMS:
		if item.place != _research_place:
			continue
		var row: Dictionary = _research_rows[item.id]
		var b := row.button as Button
		var done := village.has_research(item.id)
		var running: bool = village.research_at(item.place).get("id", "") == item.id
		var waiting: bool = item.has("needs") and not village.has_research(item.needs)
		var progress := village.research_progress(item.id)
		(row.bar as ProgressBar).value = progress
		(row.bar as ProgressBar).visible = running
		var status := row.status as Label
		if done:
			status.text = "Done"
		elif running:
			status.text = "%d%%" % floori(progress * 100.0)
		elif not village.has_role(item.place):
			status.text = "No %s" % BuildingCatalog.role_name(item.place)
		elif waiting:
			status.text = "Needs %s" % Research.find(item.needs).name
		else:
			status.text = ""
		b.disabled = done or running or waiting
		b.modulate = Color.WHITE if done or running or village.can_afford(item.cost) else Color(1.0, 0.6, 0.6, 0.8)


## The Shrine's menu (the Singing rocks; opened by clicking one): one
## button for each spell to research, with what it costs, how long it
## takes and how far along it is.
func _build_spell_research_menu(root: Control) -> void:
	_spell_research_panel = PanelContainer.new()
	_spell_research_panel.set_anchors_preset(Control.PRESET_CENTER)
	_spell_research_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_spell_research_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_spell_research_panel.visible = false
	root.add_child(_spell_research_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_spell_research_panel.add_child(box)
	_spell_research_title = _heading("")
	box.add_child(_spell_research_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for spell in SpellBook.SPELLS:
		if not SpellBook.needs_research(spell.id):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		grid.add_child(row)
		var icon := TextureRect.new()
		icon.texture = spell_icon(spell.id)
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var b := _button("")
		b.custom_minimum_size = Vector2(300, 70)
		var lines: Array[Control] = [_text(spell.name, 12), _text("Takes %s min" % _number(SpellBook.research_seconds(spell.id) / 60.0), 12)]
		b.add_child(_stacked(lines))
		b.tooltip_text = spell.hint
		var id: String = spell.id
		b.pressed.connect(func() -> void: spell_research_selected.emit(id))
		row.add_child(b)
		var state := VBoxContainer.new()
		state.alignment = BoxContainer.ALIGNMENT_CENTER
		state.custom_minimum_size.x = 90
		row.add_child(state)
		var status := _text("", 12)
		state.add_child(status)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(90, 8)
		state.add_child(bar)
		_spell_research_rows[id] = {"button": b, "status": status, "bar": bar}
	var note := Label.new()
	note.text = "Every spell is researched here, one at a time, before it appears on the spell bar.\nEach costs 1 animus more than the last. Drag the spells on the bar to put them where you like."
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.75)
	box.add_child(note)


## Opens (or closes) the Shrine's menu; `title` is what the building is called.
func show_spell_research(shown: bool, title := "") -> void:
	_spell_research_panel.visible = shown
	if title != "":
		_spell_research_place = title


var _spell_research_place := "Shrine"


func is_spell_research_open() -> bool:
	return _spell_research_panel.visible


func update_spell_research(village: PlayerVillage) -> void:
	var cost: int = village.spell_research_cost().get("animus", 0)
	_spell_research_title.text = "%s: research spells. The next costs %d animus (you have %d)." % [_spell_research_place, cost, village.amount("animus")]
	for id: String in _spell_research_rows:
		var row: Dictionary = _spell_research_rows[id]
		var b := row.button as Button
		var done := village.knows_spell(id)
		var running: bool = village.spell_research.get("id", "") == id
		var progress := village.spell_research_progress(id)
		(row.bar as ProgressBar).value = progress
		(row.bar as ProgressBar).visible = running
		var status := row.status as Label
		status.text = "Known" if done else ("%d%%" % floori(progress * 100.0) if running else "")
		b.disabled = done or running
		b.modulate = Color.WHITE if done or running or village.can_afford(village.spell_research_cost()) else Color(1.0, 0.6, 0.6, 0.8)


## The sign of spell `id`, as a texture (the mouse pointer's, see SpellCursors).
static func spell_icon(id: String) -> Texture2D:
	return ImageTexture.create_from_image(SpellCursors.image(id))


func _build_prompt(root: Control) -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.position.y = 132
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	root.add_child(_prompt_panel)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 17)
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
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	dev.add_child(top)
	top.add_child(_heading("Dev menu  (~ to hide)"))
	var version := _heading("Version %s" % ProjectSettings.get_setting("application/config/version", "?"))
	version.modulate = Color(1, 1, 1, 0.85)
	top.add_child(version)

	dev.add_child(_heading("Gameplay"))
	for s in SETTING_SLIDERS:
		dev.add_child(_setting_row(s))
	var files := HBoxContainer.new()
	dev.add_child(files)
	var save := _button("Save sliders as simple human readable .txt file")
	save.tooltip_text = "Writes every slider above to a text file, one per line (Day length = 8 min), so you can keep track of settings."
	save.pressed.connect(func() -> void: sliders_save_requested.emit())
	files.add_child(save)
	var load := _button("Load sliders")
	load.tooltip_text = "Reads a sliders .txt file and sets the sliders from it."
	load.pressed.connect(func() -> void: sliders_load_requested.emit())
	files.add_child(load)
	var cheats := HBoxContainer.new()
	dev.add_child(cheats)
	var cheat := _button("Give 100 of everything")
	cheat.pressed.connect(func() -> void: resources_requested.emit())
	cheats.add_child(cheat)
	var spells := _button("Learn all spells")
	spells.tooltip_text = "Researches every spell at once."
	spells.pressed.connect(func() -> void: spells_requested.emit())
	cheats.add_child(spells)

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

	var ruler := _button("Ruler: measure a distance")
	ruler.tooltip_text = "Click a point, then move the mouse: the line shows the distance. Click again to keep it; right-click or Esc to put the ruler away."
	ruler.pressed.connect(func() -> void: ruler_requested.emit())
	dev.add_child(ruler)
	_grass_button = _button("Grass")
	_grass_button.pressed.connect(func() -> void: grass_requested.emit())
	dev.add_child(_grass_button)

	_stats = Label.new()
	_stats.modulate = Color(1, 1, 1, 0.8)
	_stats.add_theme_font_size_override("font_size", 12)
	dev.add_child(_stats)


func _setting_row(s: Array) -> Control:
	var key: String = s[0]
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size.x = 230
	label.add_theme_font_size_override("font_size", 12)
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
		if key == "villager_detail" and value >= Villager.ALWAYS_DETAILED:
			label.text = "Villager detail: always"
		else:
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
	label.add_theme_font_size_override("font_size", 12)
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
		var label: Label = _resource_labels[res]
		label.text = str(village.amount(res))
		if village.capacity(res) < INF:
			label.tooltip_text = "%s: %d of %d the village can store" % [res.capitalize(), village.amount(res), roundi(village.capacity(res))]
		var change := village.last_minute(res)
		(_rate_labels[res] as Label).text = ("+%d" % change) if change >= 0 else str(change)
	if village.blood_active():
		_resource_labels.magicko.text += " x2"
	var people: Label = _resource_labels.people
	people.text = "%d/%d" % [village.population(), village.housing()]
	(people.get_child(0) as ProgressBar).value = village.birth_share()
	_update_jobs(village)
	_clock.text = clock
	var warning := ""
	if village.founded:
		if village.amount("food") <= 0:
			warning = "Out of food! No births, and people will starve" if village.hungry_for < PlayerVillage.STARVE_AFTER else "Starving!"
		elif village.population() >= village.housing():
			warning = "No room for more villagers: build a %s" % BuildingCatalog.role_name("home")
	_warning.text = warning
	_warning.visible = warning != ""


func _update_jobs(village: PlayerVillage) -> void:
	_workers_count.text = str(village.unassigned())
	for kind: String in _gather:
		var set_by_player: int = village.quota[kind]
		(_gather[kind].count as Label).text = str(set_by_player)
		(_gather[kind].less as Button).disabled = set_by_player <= 0
		(_gather[kind].more as Button).disabled = village.free_workers() <= 0
	for role: String in _jobs:
		var w: Dictionary = _jobs[role]
		var top := village.max_count(role)
		var want: int = village.wanted[role]
		# Trained or training (counted the moment one is asked for) / the
		# most the buildings allow (0 without one).
		var asked := maxi(want, village.count(role) + village.training_progress(role).size())
		(w.count as Label).text = "%d/%d" % [asked, top]
		(w.count as Label).tooltip_text = "%d trained, %d in training, of the %d your %s buildings allow. + trains one more, while %s free to train." % [
			village.count(role), maxi(0, asked - village.count(role)), top, BuildingCatalog.role_name(ROLES[role][1]),
			"a wizard is" if role == "necromancer" else "an unassigned worker is"]
		# Each shows once there is a building to train it (archers: once
		# bows are researched too).
		var known := top > 0 or village.count(role) > 0
		for part: String in ["label", "row"]:
			(w[part] as Control).visible = known
		var free_now := village.free_wizards() if role == "necromancer" else village.free_workers()
		(w.more as Button).disabled = want >= top or free_now <= 0
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


## `costs`: what each spell costs now. `extras`: the share more than usual
## it costs for being cast recently, shown as blue sparkles.
## Shows spell `index` as the one in hand (-1: none).
func set_spell(index: int) -> void:
	for k in _spell_buttons.size():
		_spell_buttons[k].set_pressed_no_signal(k == index)


func update_spells(magicko: int, costs: Array[int], extras: Array[float], enabled: bool) -> void:
	for k in _spell_buttons.size():
		var ready_now: bool = enabled and magicko >= costs[k]
		_spell_buttons[k].modulate = Color.WHITE if ready_now else Color(1.0, 0.6, 0.6, 0.75)
		if _spell_costs[k] != null:
			_spell_costs[k].text = str(costs[k])
		_spell_sparkles[k].set_extra(extras[k])


## Puts each spell in its slot on the bar (`bar`: each slot's spell id, or
## ""), with its key (1-9, 0) in the corner; spells not on it are hidden.
func set_spell_slots(bar: Array[String]) -> void:
	_last_used_slot = -1
	for k in SpellBook.SPELLS.size():
		var at := bar.find(SpellBook.SPELLS[k].id)
		_spell_slot_of[k] = at
		var spell := _spell_slots[k]
		if spell.get_parent() != null:
			spell.get_parent().remove_child(spell)
		if at >= 0:
			_slot_holders[at].add_child(spell)
			_spell_keys[k].text = str((at % SpellLayout.PER_ROW + 1) % 10)
			_last_used_slot = maxi(_last_used_slot, at)
	_show_spell_rows()


## How many rows the bar shows (spells in a hidden row can still be cast
## with Ctrl or Shift and the number).
func _spell_row_count() -> int:
	return clampi(SpellLayout.row_count(), 1, SpellLayout.ROWS_MOST)


func _show_spell_rows() -> void:
	var rows := _spell_row_count()
	for r in _spell_lines.size():
		_spell_lines[r].visible = r < rows
	_add_row_button.visible = rows < SpellLayout.ROWS_MOST
	_remove_row_button.visible = rows > 1


## The creature's growth: yellow up to how far it has grown, dark up to how
## far the animus paid for lets it grow, grey above that.
class GrowthBar extends Control:
	var grown := 0.0
	var paid := 0.0

	func set_values(now: float, allowed: float) -> void:
		if not is_equal_approx(now, grown) or not is_equal_approx(allowed, paid):
			grown = clampf(now, 0.0, 1.0)
			paid = clampf(allowed, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.45, 0.48, 0.9))
		draw_rect(Rect2(0.0, h * (1.0 - paid), size.x, h * paid), Color(0.1, 0.09, 0.05, 0.9))
		draw_rect(Rect2(0.0, h * (1.0 - grown), size.x, h * grown), Color(1.0, 0.82, 0.2))


## A place on the spell bar: a faint square when empty, and somewhere to
## drop a spell.
class SlotHolder extends Panel:
	var slot := 0
	var on_drop: Callable

	func _ready() -> void:
		var look := StyleBoxFlat.new()
		look.bg_color = Color(1, 1, 1, 0.05)
		look.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", look)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("spell")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		on_drop.call(int((data as Dictionary).spell), slot)


## A spell's square: drag it onto another slot to move it there.
class SpellButton extends Button:
	var spell_index := -1
	var on_drop: Callable

	func _get_drag_data(_at: Vector2) -> Variant:
		var icon := TextureRect.new()
		icon.texture = Hud.spell_icon(SpellBook.SPELLS[spell_index].id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size = Vector2(56, 56)
		icon.modulate = Color(1, 1, 1, 0.8)
		set_drag_preview(icon)
		return {"spell": spell_index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("spell")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var from := int((data as Dictionary).spell)
		if from != spell_index:
			on_drop.call(from, spell_index)


func show_build_menu(shown: bool) -> void:
	_build_panel.visible = shown
	if shown:
		for picture in _build_previews:
			picture.draw_once()
		_update_build_tooltips()


## The asset names (the models') show only while the dev menu is open.
func _update_build_tooltips() -> void:
	for info in BuildingCatalog.BUILDINGS:
		var b: Button = _build_buttons[info.kind]
		b.tooltip_text = "Model: %s" % info.asset if Game.dev_menu and info.role != "field" and info.role != "bridge" else ""


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
	_update_build_tooltips()


func set_sculpt(index: int) -> void:
	for k in _sculpt_buttons.size():
		_sculpt_buttons[k].set_pressed_no_signal(k == index)


func set_brush(radius: float) -> void:
	_brush.text = "Brush radius: %d m   ( Ctrl + wheel,  [ ] )" % roundi(radius)


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
