extends CanvasLayer
## DEVELOPER MODE (F4): sliders for the game's tuning numbers, changed live
## while the game runs (it doesn't pause). Saved between sessions
## (settings.cfg, [dev]); RESET puts one back, RESET ALL all of them, COPY
## VALUES puts the changed ones on the clipboard as text (to paste to whoever
## makes them the new defaults). While anything differs from the defaults, a
## small "DEV TUNING" tag stays on screen.
##
## mode "infantry" (main.gd) or "fleet" (fleet_main.gd).

const Squad = preload("res://scripts/squad.gd")
const Soldier = preload("res://scripts/soldier.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Lav = preload("res://scripts/lav.gd")
const Fleet = preload("res://scripts/fleet/fleet_main.gd")
const FleetVehicle = preload("res://scripts/fleet/fleet_vehicle.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")
const NEON := Color(0.45, 1.0, 0.30)
const AMBER := Color(1.0, 0.75, 0.2)

static var _defaults := {}       # id -> value as the game shipped it (first seen)

var mode := "infantry"
var is_open := false
var on_open: Callable            # host: free the mouse without triggering its pause
var on_close: Callable
var _panel: PanelContainer
var _tag: Label
var _rows := {}                  # id -> {slider, value}
var _syncing := false
var last_copy := ""             # what COPY VALUES produced last


# ---------------------------------------------------------------- the list

## [id, group, label, min, max, step, getter, setter, saved]
static func entries(for_mode: String) -> Array:
	var d: int = Weapons.difficulty
	var dn: String = Weapons.DIFFICULTY_NAMES[d]
	var out: Array = [
		["time_scale", "GAME", "Game speed (slow motion < 1)", 0.1, 2.0, 0.05,
			func(): return Engine.time_scale, func(v): Engine.time_scale = v, false],
	]
	if for_mode == "fleet":
		out.append_array([
			["fleet_speed", "FLEET MOVEMENT", "Fleet speed (m/s)", 3.0, 30.0, 0.5,
				func(): return Fleet.SPEED, func(v): Fleet.SPEED = v, true],
			["veh_max", "FLEET MOVEMENT", "Vehicle top speed (m/s)", 4.0, 40.0, 0.5,
				func(): return FleetVehicle.MAX_SPEED, func(v): FleetVehicle.MAX_SPEED = v, true],
			["veh_accel", "FLEET MOVEMENT", "Vehicle acceleration (m/s2)", 1.0, 30.0, 0.5,
				func(): return FleetVehicle.ACCEL, func(v): FleetVehicle.ACCEL = v, true],
			["turret_turn", "FLEET WEAPONS", "Turret turn speed (rad/s)", 0.2, 5.0, 0.05,
				func(): return FleetVehicle.TURRET_TURN, func(v): FleetVehicle.TURRET_TURN = v, true],
			["main_reload", "FLEET WEAPONS", "Main gun reload (s)", 0.3, 15.0, 0.1,
				func(): return FleetVehicle.MAIN_RELOAD, func(v): FleetVehicle.MAIN_RELOAD = v, true],
			["main_dmg", "FLEET WEAPONS", "Main gun damage", 5.0, 500.0, 5.0,
				func(): return Fleet.MAIN_DMG, func(v): Fleet.MAIN_DMG = v, true],
			["shell_speed", "FLEET WEAPONS", "Shell speed (m/s)", 50.0, 1200.0, 10.0,
				func(): return Fleet.SHELL_SPEED, func(v): Fleet.SHELL_SPEED = v, true],
			["mg_rate", "FLEET WEAPONS", "MG time between rounds (s)", 0.02, 0.5, 0.01,
				func(): return FleetVehicle.MG_RATE, func(v): FleetVehicle.MG_RATE = v, true],
			["mg_dmg", "FLEET WEAPONS", "MG damage per round", 0.1, 20.0, 0.1,
				func(): return Fleet.MG_DMG, func(v): Fleet.MG_DMG = v, true],
		])
		return out
	out.append_array([
		["move_speed", "SQUAD MOVEMENT", "Squad speed (m/s)", 1.0, 16.0, 0.1,
			func(): return Squad.MOVE_SPEED, func(v): Squad.MOVE_SPEED = v, true],
		["man_speed", "SQUAD MOVEMENT", "Men's top speed (m/s)", 1.0, 20.0, 0.1,
			func(): return Soldier.BASE_SPEED, func(v): Soldier.BASE_SPEED = v, true],
		["walk_k", "SQUAD MOVEMENT", "Walk pace (x squad speed)", 0.1, 1.0, 0.05,
			func(): return Squad.PACE_SPEED[0], func(v): _set_pace(0, v), true],
		["rush_k", "SQUAD MOVEMENT", "Rush pace (x squad speed)", 1.0, 3.0, 0.05,
			func(): return Squad.PACE_SPEED[2], func(v): _set_pace(2, v), true],
		["crawl", "SQUAD MOVEMENT", "Crawl speed (m/s)", 0.2, 5.0, 0.1,
			func(): return Soldier.CRAWL_SPEED, func(v): Soldier.CRAWL_SPEED = v, true],
		["accel", "SQUAD MOVEMENT", "Men's acceleration (m/s2)", 2.0, 60.0, 1.0,
			func(): return Soldier.ACCEL, func(v): Soldier.ACCEL = v, true],
		["turn_rate", "SQUAD MOVEMENT", "Formation turn rate (rad/s)", 0.5, 12.0, 0.1,
			func(): return Squad.TURN_RATE, func(v): Squad.TURN_RATE = v, true],
		["wedge_x", "FORMATIONS", "Wedge: spacing across (m)", 0.8, 5.0, 0.1,
			func(): return Squad.WEDGE_GAP.x, func(v): Squad.WEDGE_GAP.x = v, true],
		["wedge_z", "FORMATIONS", "Wedge: spacing back (m)", 0.5, 5.0, 0.1,
			func(): return Squad.WEDGE_GAP.y, func(v): Squad.WEDGE_GAP.y = v, true],
		["file_gap", "FORMATIONS", "File: spacing (m)", 0.8, 5.0, 0.1,
			func(): return Squad.FILE_GAP, func(v): Squad.FILE_GAP = v, true],
		["line_gap", "FORMATIONS", "Line: spacing (m)", 0.8, 5.0, 0.1,
			func(): return Squad.LINE_GAP, func(v): Squad.LINE_GAP = v, true],
		["our_acc", "SQUAD FIRE", "Squad accuracy (x)", 0.1, 3.0, 0.05,
			func(): return Weapons.our_acc, func(v): Weapons.our_acc = v, true],
		["our_dmg", "SQUAD FIRE", "Squad rifle damage (x)", 0.1, 5.0, 0.05,
			func(): return Weapons.our_dmg, func(v): Weapons.our_dmg = v, true],
		["walk_acc", "SQUAD FIRE", "Accuracy while walking (x)", 0.1, 1.0, 0.05,
			func(): return Soldier.WALK_ACC, func(v): Soldier.WALK_ACC = v, true],
		["miss_short", "SQUAD FIRE", "Misses that land short (share)", 0.0, 1.0, 0.05,
			func(): return Soldier.MISS_SHORT, func(v): Soldier.MISS_SHORT = v, true],
		["miss_far", "SQUAD FIRE", "Widest miss past the body (m)", 0.2, 3.0, 0.05,
			func(): return Soldier.MISS_GAP.y, func(v): Soldier.MISS_GAP.y = maxf(v, Soldier.MISS_GAP.x + 0.05), true],
		["rush_evade", "SQUAD FIRE", "Enemy hit chance on rushing men (x)", 0.1, 1.0, 0.05,
			func(): return Weapons.RUSH_EVADE, func(v): Weapons.RUSH_EVADE = v, true],
	])
	for k in [["acc", "Enemy accuracy (x)", 0.1, 4.0], ["dmg", "Enemy damage (x)", 0.1, 4.0], ["react", "Enemy reaction time (x)", 0.2, 3.0],
			["pause", "Enemy pause between bursts (x)", 0.2, 3.0], ["our_move", "Our hit chance on the move (x)", 0.05, 1.0],
			["behind", "Our hit chance vs enemy in cover (x)", 0.1, 1.0], ["close_hit", "Enemy close-range accuracy (x)", 1.0, 4.0]]:
		var key: String = k[0]
		out.append(["%s_%d" % [key, d], "ENEMY (%s)" % dn, k[1], k[2], k[3], 0.05,
			func(): return Weapons.TUNING[Weapons.difficulty][key], func(v): Weapons.TUNING[Weapons.difficulty][key] = v, true])
	out.append_array([
		["lav_with", "LAV", "LAV speed with the infantry (m/s)", 1.0, 15.0, 0.1,
			func(): return Lav.SPEED_WITH, func(v): Lav.SPEED_WITH = v, true],
		["lav_alone", "LAV", "LAV speed on its own (m/s)", 1.0, 25.0, 0.1,
			func(): return Lav.SPEED_ALONE, func(v): Lav.SPEED_ALONE = v, true],
	])
	return out


## The squad and each man keep their own copy of the pace multipliers.
static func _set_pace(i: int, v: float) -> void:
	Squad.PACE_SPEED[i] = v
	Soldier.PACE_SPEED[i] = v


## Note every value as shipped (first time only), then apply the saved ones.
## Call once at the start of a scene, before anything else changes them.
static func apply_saved(for_mode: String, load_cfg := true) -> void:
	var cfg := ConfigFile.new()
	if load_cfg:
		cfg.load("user://settings.cfg")
	for e in entries(for_mode):
		if not _defaults.has(e[0]):
			_defaults[e[0]] = e[6].call()
		if e[8] and cfg.has_section_key("dev", e[0]):
			e[7].call(float(cfg.get_value("dev", e[0])))


static func _save(id: String, v: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	if v == null:
		if cfg.has_section_key("dev", id):
			cfg.erase_section_key("dev", id)
	else:
		cfg.set_value("dev", id, v)
	cfg.save("user://settings.cfg")


## The tuned values that differ from the defaults: [[id, label, value, default]].
func changed() -> Array:
	var out: Array = []
	for e in entries(mode):
		var v: float = e[6].call()
		if _defaults.has(e[0]) and not is_equal_approx(v, _defaults[e[0]]):
			out.append([e[0], e[2], v, _defaults[e[0]]])
	return out


# ---------------------------------------------------------------- UI

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false
	_refresh_tag()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	_sync()
	_panel.visible = true
	if on_open.is_valid():
		on_open.call()
	_refresh_tag()


func close() -> void:
	is_open = false
	_panel.visible = false
	if on_close.is_valid():
		on_close.call()
	_refresh_tag()


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.04, 0.0, 0.93)
	sb.border_color = Color(AMBER, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -470
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = -10
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	box.add_child(_label("DEVELOPER MODE  (F4 to close)", 18, AMBER))
	box.add_child(_label("Live: the game keeps running. Saved between sessions.", 12, Color(NEON, 0.7)))
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	buttons.add_child(_button("RESET ALL", _reset_all))
	buttons.add_child(_button("COPY VALUES", _copy))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var group := ""
	for e in entries(mode):
		if e[1] != group:
			group = e[1]
			var h := _label(group, 14, AMBER)
			h.custom_minimum_size.y = 26
			h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			list.add_child(h)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		var name_l := _label(e[2], 12, NEON)
		name_l.custom_minimum_size.x = 200
		name_l.clip_text = true
		row.add_child(name_l)
		var s := HSlider.new()
		s.min_value = e[3]
		s.max_value = e[4]
		s.step = e[5]
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.focus_mode = Control.FOCUS_NONE
		s.name = e[0]
		row.add_child(s)
		var val := _label("", 12, Color.WHITE)
		val.custom_minimum_size.x = 52
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		var id: String = e[0]
		var setter: Callable = e[7]
		var saved: bool = e[8]
		s.value_changed.connect(func(v: float) -> void:
			if _syncing:
				return
			setter.call(v)
			val.text = _fmt(v)
			if saved:
				_save(id, v if not is_equal_approx(v, _defaults.get(id, v)) else null)
			_mark(id)
			_refresh_tag())
		row.add_child(_button("R", func() -> void: _reset(id), 26))
		_rows[id] = {"slider": s, "value": val, "name": name_l}
	_tag = _label("DEV TUNING ON  (F4)", 13, AMBER)
	_tag.position = Vector2(12, 0)
	_tag.anchor_top = 1.0
	_tag.anchor_bottom = 1.0
	_tag.offset_top = -26
	_tag.offset_left = 12
	add_child(_tag)


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UI_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(t: String, cb: Callable, w := 0) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UI_FONT)
	b.add_theme_font_size_override("font_size", 13)
	if w > 0:
		b.custom_minimum_size.x = w
	b.pressed.connect(cb)
	return b


static func _fmt(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".") if absf(v) < 100.0 else "%.0f" % v


## Sliders to the live values (something else may have changed them).
func _sync() -> void:
	_syncing = true
	for e in entries(mode):
		if _rows.has(e[0]):
			var v: float = e[6].call()
			_rows[e[0]]["slider"].value = v
			_rows[e[0]]["value"].text = _fmt(v)
			_mark(e[0])
	_syncing = false


## A changed value's name shows amber.
func _mark(id: String) -> void:
	for e in entries(mode):
		if e[0] == id:
			var on: bool = _defaults.has(id) and not is_equal_approx(e[6].call(), _defaults[id])
			_rows[id]["name"].add_theme_color_override("font_color", AMBER if on else NEON)


func _reset(id: String) -> void:
	for e in entries(mode):
		if e[0] == id and _defaults.has(id):
			e[7].call(_defaults[id])
			_save(id, null)
	_sync()
	_refresh_tag()


func _reset_all() -> void:
	for e in entries(mode):
		_reset(e[0])


## The changed values as text, on the clipboard.
func _copy() -> void:
	var lines: Array = ["Squad Test developer tuning (%s):" % mode]
	for c in changed():
		lines.append("  %s: %s  (default %s)" % [c[1], _fmt(c[2]), _fmt(c[3])])
	if lines.size() == 1:
		lines.append("  (everything at its default)")
	last_copy = "\n".join(lines)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(last_copy)
	else:
		print(last_copy)                   # (no clipboard here: the console has it)


func _refresh_tag() -> void:
	if _tag:
		_tag.visible = not is_open and not changed().is_empty()
