class_name EditorHud
extends CanvasLayer
## The map editor's panel: map name, tools, save / play / leave, and a
## status line. Emits signals only; EditorMode does the work.

signal tool_selected(tool: int)
signal save_requested
signal play_requested
signal menu_requested
signal new_requested(size: int)
signal name_changed(text: String)
signal expand_requested

const HELP := "WASD pan   Q/E rotate   Wheel zoom   Middle-drag tilt   1-9, 0 tools   [ ] brush size   R turn cave   Ctrl+S save"

var _name_edit: LineEdit
var _size_label: Label
var _tool_buttons: Array[Button] = []
var _hint: Label
var _brush: Label
var _counts: Label
var _status: Label
var _expand_panel: PanelContainer
var _expand_label: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = UiTheme.get_theme()

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size.x = 380
	panel.add_child(box)
	var title := Label.new()
	title.text = "Map editor"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name"
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 40
	_name_edit.text_changed.connect(func(t: String) -> void: name_changed.emit(t))
	_name_edit.text_submitted.connect(func(_t: String) -> void: _name_edit.release_focus())
	name_row.add_child(_name_edit)
	_size_label = Label.new()
	_size_label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_size_label)

	box.add_child(_heading("Tools"))
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	var group := ButtonGroup.new()
	for k in EditorMode.TOOL_NAMES.size():
		var b := _button(("%d %s" % [(k + 1) % 10, EditorMode.TOOL_NAMES[k]]) if k < 10 else EditorMode.TOOL_NAMES[k])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: tool_selected.emit(k))
		grid.add_child(b)
		_tool_buttons.append(b)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(380, 44)
	box.add_child(_hint)
	_brush = Label.new()
	box.add_child(_brush)
	_counts = Label.new()
	_counts.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_counts)

	var actions := HBoxContainer.new()
	box.add_child(actions)
	var save := _button("Save")
	save.pressed.connect(func() -> void: save_requested.emit())
	actions.add_child(save)
	var play := _button("Save and play")
	play.pressed.connect(func() -> void: play_requested.emit())
	actions.add_child(play)
	var menu := _button("Main menu")
	menu.pressed.connect(func() -> void: menu_requested.emit())
	actions.add_child(menu)

	box.add_child(_heading("Start a new blank map"))
	var sizes := HBoxContainer.new()
	box.add_child(sizes)
	for k in Terrain.SIZES.size():
		var size: int = Terrain.SIZES[k]
		var b := _button("%s %d m" % [Terrain.SIZE_NAMES[k], size])
		b.pressed.connect(func() -> void: new_requested.emit(size))
		sizes.add_child(b)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 380
	_status.modulate = Color(1.0, 0.9, 0.6)
	box.add_child(_status)

	# Asked when the land brush reaches the edge of the map square.
	_expand_panel = PanelContainer.new()
	_expand_panel.set_anchors_preset(Control.PRESET_CENTER)
	_expand_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_expand_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_expand_panel.visible = false
	root.add_child(_expand_panel)
	var ask := VBoxContainer.new()
	ask.add_theme_constant_override("separation", 10)
	_expand_panel.add_child(ask)
	_expand_label = Label.new()
	_expand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.add_child(_expand_label)
	var answers := HBoxContainer.new()
	answers.alignment = BoxContainer.ALIGNMENT_CENTER
	answers.add_theme_constant_override("separation", 10)
	ask.add_child(answers)
	var yes := _button("Make the map bigger")
	yes.pressed.connect(func() -> void:
		_expand_panel.visible = false
		expand_requested.emit())
	answers.add_child(yes)
	var no := _button("Not now")
	no.pressed.connect(func() -> void: _expand_panel.visible = false)
	answers.add_child(no)

	var help_panel := PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_panel.position = Vector2(12, -12)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_panel)
	var help := Label.new()
	help.text = HELP
	help.add_theme_font_size_override("font_size", 13)
	help_panel.add_child(help)


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


func set_map(map_name: String, size: int) -> void:
	_name_edit.text = map_name
	_size_label.text = "Size: %s   (no buildings: villagers build them in the game)" % MapData.size_name(size)


func set_tool(tool: int, hint: String) -> void:
	for k in _tool_buttons.size():
		_tool_buttons[k].set_pressed_no_signal(k == tool)
	_hint.text = hint


func set_brush(radius: float) -> void:
	_brush.text = "Brush radius: %d m   ( [ ] )" % roundi(radius)


func set_counts(starts: int, caves: int, trees: int, rocks: int) -> void:
	_counts.text = "Start locations %d/%d   Caves %d   Trees %d   Rocks %d" % [starts, MapData.MAX_STARTS, caves, trees, rocks]


func ask_expand(size: int, bigger: int) -> void:
	_expand_label.text = "The island has reached the edge of the map (%d m square).\nMake the map %d m square? Nothing on it moves." % [size, bigger]
	_expand_panel.visible = true


func set_status(text: String) -> void:
	_status.text = text
