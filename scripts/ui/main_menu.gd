class_name MainMenu
extends CanvasLayer
## The title menu, shown over a slowly turning random island. Start a game
## on a random island of any size or on a saved map, open the map editor,
## or look at the giants in the test environment. The version is under the
## title. How many neutral villages there will be is set here (and again
## while picking a start). The dev menu (~, or its button) has the
## gameplay sliders, so they can be set before a game starts; they carry
## over into it.

var _size := Terrain.DEFAULT_SIZE
var _maps: Array[Dictionary] = []
var _list: ItemList
var _play_map: Button
var _edit_map: Button
var _dev_panel: PanelContainer
var _neutral_label: Label
## The dev menu's sliders: key -> [slider, label updater].
var _sliders := {}
var _dev_hint: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = UiTheme.get_theme()
	# The version, in the corner. It goes up with every update (see README).
	var version := Label.new()
	version.text = "Version %s" % ProjectSettings.get_setting("application/config/version", "?")
	version.add_theme_font_size_override("font_size", 16)
	version.modulate = Color(1, 1, 1, 0.8)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position = Vector2(-14, -10)
	root.add_child(version)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 460
	margin.add_child(box)

	var title := Label.new()
	title.text = "SpriteSquirter"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var version_line := Label.new()
	version_line.text = "Version %s" % ProjectSettings.get_setting("application/config/version", "?")
	version_line.add_theme_font_size_override("font_size", 18)
	version_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_line.modulate = Color(1.0, 0.9, 0.6)
	box.add_child(version_line)
	var tagline := Label.new()
	tagline.text = "Grow a village on a floating island. Mind your creature."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.modulate = Color(1, 1, 1, 0.75)
	box.add_child(tagline)

	box.add_child(_heading("Map size"))
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 6)
	box.add_child(sizes)
	var group := ButtonGroup.new()
	for k in Terrain.SIZES.size():
		var size: int = Terrain.SIZES[k]
		var b := _button("%s  %d m" % [Terrain.SIZE_NAMES[k], size])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = size == _size
		b.pressed.connect(func() -> void: _size = size)
		sizes.add_child(b)
	box.add_child(_heading("Your creature"))
	var beasts := HBoxContainer.new()
	beasts.add_theme_constant_override("separation", 6)
	box.add_child(beasts)
	var beast_group := ButtonGroup.new()
	var blurbs := {"tortoise": "gloomy, slow, twice as tough", "squirrel": "nervous, 30% faster, half as tough",
		"raven": "flies long journeys and out of battles"}
	for kind: String in Creature.SPECIES:
		var b := _button("%s\n%s" % [Creature.SPECIES[kind].name, blurbs.get(kind, "")])
		b.toggle_mode = true
		b.button_group = beast_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = kind == Game.creature_kind
		b.pressed.connect(func() -> void: Game.creature_kind = kind)
		beasts.add_child(b)
	box.add_child(_heading("Neutral villages"))
	var neutral_row := HBoxContainer.new()
	neutral_row.add_theme_constant_override("separation", 6)
	box.add_child(neutral_row)
	var fewer := _button("  -  ")
	fewer.pressed.connect(func() -> void: _set_neutral(Game.neutral_villages - 1))
	neutral_row.add_child(fewer)
	_neutral_label = Label.new()
	_neutral_label.custom_minimum_size.x = 30
	_neutral_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	neutral_row.add_child(_neutral_label)
	var more := _button("  +  ")
	more.pressed.connect(func() -> void: _set_neutral(Game.neutral_villages + 1))
	neutral_row.add_child(more)
	var neutral_note := Label.new()
	neutral_note.text = "on other start locations (at most one fewer than there are)"
	neutral_note.modulate = Color(1, 1, 1, 0.6)
	neutral_note.add_theme_font_size_override("font_size", 13)
	neutral_row.add_child(neutral_note)
	_set_neutral(Game.neutral_villages)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var random := _button("Play a random island")
	random.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random.pressed.connect(func() -> void: Game.start("play", "", _size))
	row.add_child(random)
	var new_map := _button("New map in the editor")
	new_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_map.pressed.connect(func() -> void: Game.start("editor", "", _size))
	row.add_child(new_map)

	box.add_child(_heading("Saved maps"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(460, 170)
	_list.item_selected.connect(func(_i: int) -> void: _update_buttons())
	_list.item_activated.connect(func(_i: int) -> void: _open_selected("play"))
	box.add_child(_list)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 6)
	box.add_child(map_row)
	_play_map = _button("Play map")
	_play_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_map.pressed.connect(_open_selected.bind("play"))
	map_row.add_child(_play_map)
	_edit_map = _button("Edit map")
	_edit_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_map.pressed.connect(_open_selected.bind("editor"))
	map_row.add_child(_edit_map)
	var folder := _button("Open maps folder")
	folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(MapData.DIR)
		OS.shell_open(ProjectSettings.globalize_path(MapData.DIR)))
	map_row.add_child(folder)

	var load := _button("Load game")
	load.pressed.connect(_load_dialog)
	box.add_child(load)

	var test := _button("Test environment")
	test.pressed.connect(func() -> void: Game.start("test"))
	box.add_child(test)

	var dev := _button("Dev menu (~): gameplay sliders")
	dev.pressed.connect(_toggle_dev)
	box.add_child(dev)

	var quit := _button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	_build_dev_menu(root)
	_refresh_maps()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_QUOTELEFT:
		_toggle_dev()
		get_viewport().set_input_as_handled()


func _set_neutral(count: int) -> void:
	Game.neutral_villages = clampi(count, 0, NeutralVillage.MOST)
	_neutral_label.text = str(Game.neutral_villages)


func _toggle_dev() -> void:
	Game.dev_menu = not Game.dev_menu
	_dev_panel.visible = Game.dev_menu


## The dev menu's gameplay sliders (Hud.SETTING_SLIDERS), to set before a
## game starts, and saving and loading them (SliderFile).
func _build_dev_menu(root: Control) -> void:
	_dev_panel = PanelContainer.new()
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dev_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_panel.position = Vector2(-12, 12)
	_dev_panel.visible = Game.dev_menu
	root.add_child(_dev_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_dev_panel.add_child(margin)
	var dev := VBoxContainer.new()
	dev.add_theme_constant_override("separation", 4)
	margin.add_child(dev)
	dev.add_child(_heading("Dev menu  (~ to hide)     Version %s" % ProjectSettings.get_setting("application/config/version", "?")))
	dev.add_child(_heading("Gameplay"))
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	dev.add_child(grid)
	for s: Array in Hud.SETTING_SLIDERS:
		grid.add_child(_setting_row(s))
	var files := HBoxContainer.new()
	files.add_theme_constant_override("separation", 6)
	dev.add_child(files)
	var save := _button("Save sliders")
	save.pressed.connect(_slider_dialog.bind(true))
	files.add_child(save)
	var load := _button("Load sliders")
	load.pressed.connect(_slider_dialog.bind(false))
	files.add_child(load)
	var reset := _button("Defaults")
	reset.tooltip_text = "Puts every slider back to the game's defaults."
	reset.pressed.connect(func() -> void:
		Game.settings = Game.DEFAULT_SETTINGS.duplicate()
		Game.settings.sapling_rate = Balance.num("saplings_per_minute")
		_show_settings())
	files.add_child(reset)
	_dev_hint = Label.new()
	_dev_hint.modulate = Color(1, 1, 1, 0.7)
	_dev_hint.add_theme_font_size_override("font_size", 12)
	dev.add_child(_dev_hint)
	_show_settings()


func _setting_row(s: Array) -> Control:
	var key: String = s[0]
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size.x = 215
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = s[2]
	slider.max_value = s[3]
	slider.step = s[4]
	slider.custom_minimum_size = Vector2(120, 20)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var update := func(value: float) -> void:
		if key == "villager_detail" and value >= Villager.ALWAYS_DETAILED:
			label.text = "Villager detail: always"
		else:
			label.text = "%s: %s %s" % [s[1], Hud._number(value), s[5]]
	slider.value_changed.connect(func(value: float) -> void:
		update.call(value)
		Game.settings[key] = value)
	_sliders[key] = [slider, update]
	return row


func _show_settings() -> void:
	for key: String in _sliders:
		var entry: Array = _sliders[key]
		(entry[0] as HSlider).set_value_no_signal(Game.settings[key])
		(entry[1] as Callable).call(Game.settings[key])


## Opens a file box to save the sliders to a .txt file, or load them.
func _slider_dialog(saving: bool) -> void:
	var box := FileDialog.new()
	box.access = FileDialog.ACCESS_FILESYSTEM
	box.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	box.filters = PackedStringArray(["*.txt ; Text files"])
	box.title = "Save sliders" if saving else "Load sliders"
	box.use_native_dialog = true
	box.current_dir = ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	if saving:
		box.current_file = "sliders %s.txt" % Time.get_datetime_string_from_system(false, true).replace(":", "-")
	box.file_selected.connect(func(path: String) -> void:
		if saving:
			var problem := SliderFile.save(path, Game.settings)
			_dev_hint.text = problem if problem != "" else "Sliders saved to %s" % path
		else:
			var loaded := SliderFile.load_values(path)
			for key: String in loaded:
				Game.settings[key] = loaded[key]
			_show_settings()
			_dev_hint.text = "Loaded %d sliders from %s" % [loaded.size(), path] if not loaded.is_empty() else "No sliders found in %s" % path
		box.queue_free())
	box.canceled.connect(box.queue_free)
	add_child(box)
	box.popup_centered_ratio(0.6)


func _refresh_maps() -> void:
	_maps = MapData.list_maps()
	_list.clear()
	for m in _maps:
		_list.add_item("%s     %s, %d start%s" % [m.name, MapData.size_name(m.size), m.starts, "" if m.starts == 1 else "s"])
	if _maps.is_empty():
		_list.add_item("No saved maps yet: make one with the map editor.")
		_list.set_item_disabled(0, true)
		_list.set_item_selectable(0, false)
	elif _list.item_count > 0:
		_list.select(0)
	_update_buttons()


func _update_buttons() -> void:
	var none := _list.get_selected_items().is_empty() or _maps.is_empty()
	_play_map.disabled = none
	_edit_map.disabled = none


func _open_selected(mode: String) -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or _maps.is_empty():
		return
	var m: Dictionary = _maps[selected[0]]
	Game.start(mode, m.path, m.size, false)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(1.0, 0.9, 0.6)
	return label


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	return b


## Opens a file box to pick a saved game (see SaveGame) and starts it.
func _load_dialog() -> void:
	var box := FileDialog.new()
	box.access = FileDialog.ACCESS_FILESYSTEM
	box.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	box.filters = PackedStringArray(["*.txt ; Saved games"])
	box.title = "Load game"
	box.use_native_dialog = true
	DirAccess.make_dir_recursive_absolute(SaveGame.default_dir())
	box.current_dir = SaveGame.default_dir()
	box.file_selected.connect(func(path: String) -> void:
		box.queue_free()
		var problem := SaveGame.load_game(path)
		if problem != "":
			push_warning(problem))
	box.canceled.connect(box.queue_free)
	add_child(box)
	box.popup_centered_ratio(0.6)
