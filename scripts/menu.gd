extends Control
## Level select: the first screen. Two operations (day and night) and two
## training grounds. 1-4 or a click deploys; BACKSPACE in game comes back
## here. The last map played is marked.

const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")
const MainScript = preload("res://scripts/main.gd")
const SETTINGS_PATH := "user://settings.cfg"

const GREEN := Color(0.45, 1.0, 0.3)
const DIM := Color(0.45, 1.0, 0.3, 0.55)
const DAY := Color(1.0, 0.78, 0.3)
const NIGHT := Color(0.5, 0.72, 1.0)

## [map index in main.MAPS, title, day?, blurb, big card?]
const ENTRIES := [
	[3, "OPERATION BIFROST", true, "Force a river bridge choked with abandoned cars, a bus and trucks. The enemy holds the far bank: a sandbag line on the bridge, a checkpoint at its foot, a depot with an APC behind.", true],
	[0, "OPERATION LAMPLIGHTER", false, "A rain-soaked street at night. Get past the roadblock and the alley ambush, link up with the rocket team and take the walled compound.", true],
	[1, "TEST FIELD", true, "Open ground and three small enemy positions, for trying out orders.", false],
	[2, "MODEL VIEWER", true, "Every soldier, pose, gait and firing position on a turntable.", false],
]

var _last := -1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_last = int(cfg.get_value("game", "map", -1))
	_build()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	vec3 c = mix(vec3(0.035, 0.07, 0.04), vec3(0.0, 0.01, 0.0), length(uv) * 1.4);
	c *= 0.92 + 0.08 * sin(FRAGCOORD.y * 1.6);                 // scan lines
	float grid = step(0.985, fract(FRAGCOORD.x / 48.0)) + step(0.985, fract(FRAGCOORD.y / 48.0));
	c += vec3(0.02, 0.06, 0.02) * min(grid, 1.0);
	c += vec3(0.0, 0.03, 0.0) * step(0.997, fract(UV.y * 3.0 - TIME * 0.05));   // slow sweep
	COLOR = vec4(c, 1.0);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	bg.material = sm
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(940, 0)
	center.add_child(col)

	col.add_child(_label("SQUAD TEST", 56, GREEN))
	col.add_child(_label("SELECT OPERATION", 20, DIM))
	col.add_child(HSeparator.new())
	var big := HBoxContainer.new()
	big.add_theme_constant_override("separation", 16)
	col.add_child(big)
	col.add_child(_label("TRAINING", 18, DIM))
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 16)
	col.add_child(small)
	for i in ENTRIES.size():
		var e: Array = ENTRIES[i]
		(big if e[4] else small).add_child(_card(i + 1, e))
	col.add_child(HSeparator.new())
	col.add_child(_label("1-4 OR CLICK TO DEPLOY      IN GAME: BACKSPACE = THIS MENU   ESC = FIELD MANUAL", 15, DIM))


func _card(key: int, e: Array) -> Button:
	var b := Button.new()
	b.name = "Map%d" % e[0]
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 190 if e[4] else 84)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.08, 0.03, 0.85)
	normal.border_color = GREEN if e[0] == _last else Color(0.45, 1.0, 0.3, 0.35)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(3)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.06, 0.2, 0.07, 0.95)
	hover.border_color = GREEN
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(_deploy.bind(e[0]))

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(_label("[%d] " % key, 20 if e[4] else 16, DIM))
	head.add_child(_label(e[1], 24 if e[4] else 18, GREEN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if e[0] == _last:
		head.add_child(_label("LAST PLAYED  ", 13, DIM))
	head.add_child(_label("DAY" if e[2] else "NIGHT", 18 if e[4] else 14, DAY if e[2] else NIGHT))
	var blurb := _label(e[3], 16 if e[4] else 13, Color(0.75, 0.9, 0.72))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	for c in [head, blurb] + head.get_children() + v.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode - KEY_1
		if k >= 0 and k < ENTRIES.size():
			_deploy(ENTRIES[k][0])


func _deploy(map_index: int) -> void:
	MainScript.picked_map = map_index
	get_tree().change_scene_to_file("res://main.tscn")
