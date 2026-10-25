extends PanelContainer
## Bottom-right unit status: a compass showing which way the unit you command
## is moving (the top of the dial is where the camera looks), whether it's in
## cover, and the last three fire orders.

const NEON := Color(0.45, 1.0, 0.30)
const AMBER := Color(1.0, 0.75, 0.2)
const RED := Color(1.0, 0.35, 0.3)
const DIAL := 84.0
const POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var squad: Node
var cam_rig: Node3D
var _dial: Control
var _text: RichTextLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_dial = Control.new()
	_dial.custom_minimum_size = Vector2(DIAL, DIAL)
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dial.draw.connect(_draw_dial)
	row.add_child(_dial)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size = Vector2(204, 0)
	_text.add_theme_font_size_override("normal_font_size", 13)
	row.add_child(_text)


func _process(_delta: float) -> void:
	if squad == null or cam_rig == null:
		return
	_text.text = "[color=#8fbf80]MOVE[/color]   %s\n[color=#8fbf80]COVER[/color]  %s\n[color=#8fbf80]LAST FIRE ORDERS[/color]\n%s" \
		% [move_text(), cover_text(), orders_text()]
	_dial.queue_redraw()


## World compass bearing (0 = north = -Z, 90 = east = +X) of a flat direction.
static func bearing(dir: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)


static func point_name(deg: float) -> String:
	return POINTS[int(round(deg / 45.0)) % 8]


func moving() -> bool:
	return squad.move_vel.length() > 0.35


func move_text() -> String:
	if squad.holding:
		return "[color=#ffbf33]HOLDING[/color] (scouting)"
	if not moving():
		return "HALTED"
	var v: Vector3 = squad.move_vel
	var tag := "BOUNDING " if not squad.bound.is_empty() else ""
	return "[color=#ffbf33]%s%s[/color]  %03d°  %.1f m/s" % [tag, point_name(bearing(v)), roundi(bearing(v)) % 360, v.length()]


func cover_text() -> String:
	var t: int = squad.active
	var members: Array = squad.team_members(t)
	if squad.lav_with(t):
		var lav_txt := "[color=#73ff4d]BEHIND LAV[/color] %d/%d" % [squad.stacked_count(t), members.size()]
		return lav_txt + "  [color=#a8c8a0]%s[/color]" % squad.STACK_FACES[maxi(squad._stack_face, 0)]
	if not squad.teams[t]["in_cover"]:
		return "[color=#ff5a4d]NO COVER[/color]"
	var settled := 0
	var flat := 0
	for s in members:
		if s.is_settled():
			settled += 1
		if s.is_prone():
			flat += 1
	var word := "IN COVER"
	if squad._was_moving[t]:
		word = "COVER MOVE"
	elif settled < members.size():
		word = "TAKING COVER"
	var txt := "[color=#73ff4d]%s[/color] %d/%d" % [word, settled, members.size()]
	if flat > 0:
		txt += "  [color=#ffbf33]%d PRONE[/color]" % flat
	return txt


func orders_text() -> String:
	var entries: Array = squad.fire_log
	if entries.is_empty():
		return "  [color=#5f7f55]none yet[/color]"
	var now := Time.get_ticks_msec() / 1000.0
	var lines: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		var col := "#ffffff" if i == 0 else "#a8c8a0"
		var n := (" x%d" % e["n"]) if e["n"] > 1 else ""
		lines.append("  [color=%s]%s%s[/color]  [color=#5f7f55]%s[/color]" % [col, e["text"], n, _ago(now - e["t"])])
	return "\n".join(lines)


static func _ago(s: float) -> String:
	if s < 1.0:
		return "now"
	if s < 60.0:
		return "%ds ago" % int(s)
	return "%dm ago" % int(s / 60.0)


## The dial turns with the camera: up is where you're looking, the letters
## show where north is, the amber arrow is where the unit is going.
func _draw_dial() -> void:
	var c := Vector2(DIAL, DIAL) * 0.5
	var r := DIAL * 0.5 - 3.0
	var cam_yaw: Basis = cam_rig.get_yaw_basis().inverse()
	_dial.draw_circle(c, r, Color(0.0, 0.08, 0.0, 0.5))
	_dial.draw_arc(c, r, 0.0, TAU, 48, Color(NEON, 0.6), 1.5, true)
	# Ticks every 45 degrees, letters on the four cardinal points.
	var font := get_theme_default_font()
	for k in 8:
		var world := Basis(Vector3.UP, -k * PI / 4.0) * Vector3.FORWARD
		var l := cam_yaw * world
		var d := Vector2(l.x, l.z).normalized()
		if k % 2 == 0:
			var letter: String = POINTS[k]
			var col := RED if k == 0 else Color(NEON, 0.85)
			var sz := 12
			var tw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
			_dial.draw_string(font, c + d * (r - 9.0) - Vector2(tw.x * 0.5, -sz * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		else:
			_dial.draw_line(c + d * (r - 5.0), c + d * r, Color(NEON, 0.5), 1.0)
	# Where the camera looks: a small notch at the top.
	_dial.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 1), c + Vector2(-4, -r + 6), c + Vector2(4, -r + 6)]), Color(NEON, 0.9))
	# Movement arrow, longer the faster the unit goes.
	if not moving():
		_dial.draw_circle(c, 3.0, Color(AMBER, 0.8))
		return
	var lv: Vector3 = cam_yaw * squad.move_vel
	var dir := Vector2(lv.x, lv.z).normalized()
	var arm := (r - 16.0) * clampf(squad.move_vel.length() / squad.MOVE_SPEED, 0.45, 1.0)
	var tip := c + dir * arm
	var side := Vector2(-dir.y, dir.x)
	_dial.draw_line(c - dir * 6.0, tip - dir * 6.0, AMBER, 3.0, true)
	_dial.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 10.0 + side * 6.0, tip - dir * 10.0 - side * 6.0]), AMBER)
