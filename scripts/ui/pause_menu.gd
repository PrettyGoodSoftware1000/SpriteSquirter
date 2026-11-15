class_name PauseMenu
extends CanvasLayer
## The pause screen. PlayMode opens it when Esc is pressed with nothing to
## cancel; it stops the whole game (this node keeps running) until Esc or
## Resume is pressed.

signal menu_requested


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
	var menu := Button.new()
	menu.text = "Main menu"
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func() -> void:
		close()
		menu_requested.emit())
	box.add_child(menu)


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# Never leave the game frozen when the world is thrown away.
	get_tree().paused = false
