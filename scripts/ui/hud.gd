class_name Hud
extends CanvasLayer
## On-screen interface. The small panel on the left holds the player's
## tools; the dev menu on the right (toggled with ~) holds the terrain
## tools, weather, palettes, grass detail, world generation and stats.
## The HUD only emits signals; Main does the work.

signal mode_selected(mode: int)
signal regenerate_requested
signal mood_selected(index: int)
signal palette_selected(index: int)
signal grass_requested

const MODE_NAMES := ["Command", "Fireball", "Build", "Raise", "Lower", "Flatten", "Smooth"]
const PLAYER_MODES := 3
const MODE_HINTS := [
	"Click or right-click the ground to walk the tortoise there.",
	"Click to throw a fireball from the cursor. (F works in any mode.)",
	"Click to place the building. R = another design. Esc = cancel.",
	"Hold left mouse to raise the ground.  [ ] change brush size.",
	"Hold left mouse to dig the ground down.  [ ] change brush size.",
	"Hold left mouse to flatten to the height where you first clicked.",
	"Hold left mouse to smooth bumps.  [ ] change brush size.",
]
const HELP := "WASD pan   Q/E rotate   Wheel zoom   Middle-drag tilt   Space find tortoise\nRight-click move   F fireball   1-3 tools   ~ dev menu"

var _mode_buttons: Array[Button] = []
var _mood_buttons: Array[Button] = []
var _palette_buttons: Array[Button] = []
var _grass_button: Button
var _hint: Label
var _brush: Label
var _stats: Label
var _dev_panel: PanelContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var mode_group := ButtonGroup.new()

	# Player panel.
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SpriteSquirter"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var tools := HBoxContainer.new()
	box.add_child(tools)
	for k in PLAYER_MODES:
		tools.add_child(_mode_button(k, "%d %s" % [k + 1, MODE_NAMES[k]], mode_group))
	_hint = Label.new()
	_hint.custom_minimum_size = Vector2(340, 0)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)

	# Dev menu.
	_dev_panel = PanelContainer.new()
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dev_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_panel.position = Vector2(-12, 12)
	root.add_child(_dev_panel)
	var dev := VBoxContainer.new()
	dev.add_theme_constant_override("separation", 5)
	_dev_panel.add_child(dev)
	dev.add_child(_heading("Dev menu  (~ to hide)"))

	dev.add_child(_heading("Terrain tools"))
	var sculpt := HBoxContainer.new()
	dev.add_child(sculpt)
	for k in range(PLAYER_MODES, MODE_NAMES.size()):
		sculpt.add_child(_mode_button(k, "%d %s" % [k + 1, MODE_NAMES[k]], mode_group))
	_brush = Label.new()
	dev.add_child(_brush)
	var regen := _button("New world (N)")
	regen.pressed.connect(func() -> void: regenerate_requested.emit())
	dev.add_child(regen)

	dev.add_child(_heading("Weather (L)"))
	var moods := GridContainer.new()
	moods.columns = 2
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
	palettes.columns = 3
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
	dev.add_child(_stats)

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


func _mode_button(mode: int, text: String, group: ButtonGroup) -> Button:
	var b := _button(text)
	b.toggle_mode = true
	b.button_group = group
	b.pressed.connect(func() -> void: mode_selected.emit(mode))
	_mode_buttons.append(b)
	return b


func set_dev_visible(shown: bool) -> void:
	_dev_panel.visible = shown


func set_mode(mode: int) -> void:
	for k in _mode_buttons.size():
		_mode_buttons[k].set_pressed_no_signal(k == mode)
	_hint.text = MODE_HINTS[mode]


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
