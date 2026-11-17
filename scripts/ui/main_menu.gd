class_name MainMenu
extends CanvasLayer
## The title menu, shown over a slowly turning random island. Start a game
## on a random island of any size or on a saved map, or open the map editor.

var _size := Terrain.DEFAULT_SIZE
var _maps: Array[Dictionary] = []
var _list: ItemList
var _play_map: Button
var _edit_map: Button


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

	var quit := _button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	_refresh_maps()


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
