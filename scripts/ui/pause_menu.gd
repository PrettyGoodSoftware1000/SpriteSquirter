class_name PauseMenu
extends CanvasLayer
## The pause screen. PlayMode opens it when Esc is pressed with nothing to
## cancel; it stops the whole game (this node keeps running) until Esc or
## Resume is pressed. "Show controls" opens a window listing the keys.

signal menu_requested

const CONTROLS := [
	["W A S D", "Move the camera"],
	["Q / E", "Turn the camera"],
	["Mouse wheel", "Zoom"],
	["Middle mouse drag", "Tilt the camera"],
	["Space", "Find your creature"],
	["Left or right click", "Send your creature there"],
	["1 - 7 (or a spell's square)", "Take the spell in hand; click to cast it, press again to put it away"],
	["Shift + click", "Cast and keep the spell in hand"],
	["Bless / Curse", "Shows what your creature last did; click anywhere to bless or curse it"],
	["B or Backspace", "Build menu"],
	["R / Shift+R, T", "Turn a building's outline, try another look"],
	["Shift + click", "Keep placing"],
	["U", "Research (needs a Blacksmith)"],
	["Esc", "Cancel, or pause"],
	["~", "Dev menu"],
]

var _controls: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	dim.theme = UiTheme.get_theme()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 280
	panel.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume (Esc)"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(close)
	box.add_child(resume)
	var controls := Button.new()
	controls.text = "Show controls"
	controls.focus_mode = Control.FOCUS_NONE
	controls.pressed.connect(func() -> void: _controls.visible = true)
	box.add_child(controls)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func() -> void:
		close()
		menu_requested.emit())
	box.add_child(menu)

	# The controls window, over the pause panel.
	_controls = PanelContainer.new()
	_controls.set_anchors_preset(Control.PRESET_CENTER)
	_controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_controls.grow_vertical = Control.GROW_DIRECTION_BOTH
	_controls.visible = false
	dim.add_child(_controls)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	_controls.add_child(list)
	var heading := Label.new()
	heading.text = "Controls"
	heading.add_theme_font_size_override("font_size", 26)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 5)
	list.add_child(grid)
	for line: Array in CONTROLS:
		var key_label := Label.new()
		key_label.text = line[0]
		key_label.modulate = Color(1.0, 0.9, 0.6)
		grid.add_child(key_label)
		var what := Label.new()
		what.text = line[1]
		grid.add_child(what)
	var shut := Button.new()
	shut.text = "Close"
	shut.focus_mode = Control.FOCUS_NONE
	shut.pressed.connect(func() -> void: _controls.visible = false)
	list.add_child(shut)


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	_controls.visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		# Esc shuts the controls window first, then the pause menu.
		if _controls.visible:
			_controls.visible = false
		else:
			close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# Never leave the game frozen when the world is thrown away.
	get_tree().paused = false
