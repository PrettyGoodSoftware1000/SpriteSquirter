class_name Hud
extends CanvasLayer
## On-screen tool bar, hints and stats. Emits signals; Main does the work.

signal mode_selected(mode: int)
signal regenerate_requested

const MODE_NAMES := ["Command", "Fireball", "Raise", "Lower", "Flatten", "Smooth", "Build"]
const MODE_HINTS := [
	"Click or right-click the ground to walk the creature there.",
	"Click to hurl a fireball. (F casts at the cursor in any mode.)",
	"Hold left mouse to raise the ground.  [ ] change brush size.",
	"Hold left mouse to dig the ground down.  [ ] change brush size.",
	"Hold left mouse to flatten to the height where you first clicked.",
	"Hold left mouse to smooth bumps.  [ ] change brush size.",
	"Click to place the building. R = new random design. Esc = cancel.",
]
const HELP := "WASD pan   Q/E rotate   Wheel zoom   Middle-drag tilt   Space find creature\nRight-click move   F fireball   1-7 tools   N new world"

var _buttons: Array[Button] = []
var _hint: Label
var _brush: Label
var _stats: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

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

	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	var group := ButtonGroup.new()
	for k in MODE_NAMES.size():
		var b := Button.new()
		b.text = "%d %s" % [k + 1, MODE_NAMES[k]]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: mode_selected.emit(k))
		grid.add_child(b)
		_buttons.append(b)

	_hint = Label.new()
	_hint.custom_minimum_size = Vector2(420, 0)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)

	var row := HBoxContainer.new()
	box.add_child(row)
	_brush = Label.new()
	_brush.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_brush)
	var regen := Button.new()
	regen.text = "New world (N)"
	regen.focus_mode = Control.FOCUS_NONE
	regen.pressed.connect(func() -> void: regenerate_requested.emit())
	row.add_child(regen)

	_stats = Label.new()
	_stats.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_stats)

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


func set_mode(mode: int) -> void:
	for k in _buttons.size():
		_buttons[k].set_pressed_no_signal(k == mode)
	_hint.text = MODE_HINTS[mode]


func set_brush(radius: float) -> void:
	_brush.text = "Brush radius: %d m" % roundi(radius)


func set_stats(text: String) -> void:
	_stats.text = text
