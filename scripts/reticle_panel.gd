extends PanelContainer
## Tuning panel for the reticle (Tab to open/close). One slider per
## dimension with its live value, a "show dimensions" switch and a reset.

var reticle: Control
var _sliders := {}
var _values := {}
var _dims_check: CheckBox


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-330, 12)
	custom_minimum_size = Vector2(318, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.02, 0.85)
	sb.border_color = Color(0.45, 1.0, 0.30, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var title := Label.new()
	title.text = "RETICLE SETTINGS  (Tab to close)"
	title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.30))
	box.add_child(title)

	for key in reticle.PARAMS:
		var def: Array = reticle.PARAMS[key]
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = def[4]
		name_l.custom_minimum_size = Vector2(150, 0)
		name_l.add_theme_font_size_override("font_size", 13)
		row.add_child(name_l)
		var val_l := Label.new()
		val_l.custom_minimum_size = Vector2(46, 0)
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_l.add_theme_font_size_override("font_size", 13)
		row.add_child(val_l)
		box.add_child(row)

		var s := HSlider.new()
		s.min_value = def[1]
		s.max_value = def[2]
		s.step = def[3]
		s.focus_mode = Control.FOCUS_NONE   # keep Space/arrows for the game
		s.value_changed.connect(_on_slider.bind(key))
		box.add_child(s)
		_sliders[key] = s
		_values[key] = val_l

	_dims_check = CheckBox.new()
	_dims_check.text = "Show dimensions"
	_dims_check.focus_mode = Control.FOCUS_NONE
	_dims_check.toggled.connect(func(on): reticle.set_show_dims(on))
	box.add_child(_dims_check)

	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func():
		reticle.reset_defaults()
		_sync())
	box.add_child(reset)

	_sync()


func _sync() -> void:
	for key in _sliders:
		_sliders[key].set_value_no_signal(reticle.p[key])
		_show_value(key)
	_dims_check.set_pressed_no_signal(reticle.show_dims)


func _on_slider(v: float, key: String) -> void:
	reticle.set_param(key, v)
	_show_value(key)


func _show_value(key: String) -> void:
	var v: float = reticle.p[key]
	_values[key].text = ("%d" % roundi(v)) if reticle.PARAMS[key][3] >= 1.0 else ("%.2f" % v)


func toggle() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
