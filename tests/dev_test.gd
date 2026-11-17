extends SceneTree
## Developer mode (F4) and the level list in the pause menus:
##  1. TEST FIELD: F4 opens the dev panel without pausing; dragging "Squad
##     speed" to 12 makes the squad move at about 12 m/s; the name turns amber
##     and COPY VALUES lists it; R puts it back (and it moves at 6.5 again)
##  2. an enemy slider changes the current difficulty's numbers; RESET ALL
##     puts everything back
##  3. Esc menu: a LEVELS tab with a button per level; ARMORED FLEET goes there
##  4. the fleet: F4 dev panel with the fleet's sliders (fleet speed works);
##     Esc pauses it with the same level list; BIFROST goes there
## Prints FAIL lines and exits 1 on any failure.

const Squad = preload("res://scripts/squad.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Fleet = preload("res://scripts/fleet/fleet_main.gd")

var main
var f := 0
var fails := 0
var checks := 0
var phase := 0
var t0 := 0
var a0 := Vector3.ZERO


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find(c, name)
		if r:
			return r
	return null


func _scene_with(prop: String) -> Node:
	for c in root.get_children():
		if c.get(prop) != null:
			return c
	return null


func _physics_process(_d: float) -> bool:
	f += 1
	match phase:
		0:
			if f == 30:
				_key(KEY_F4)
			if f == 40:
				var dev = main.dev
				_check(dev.is_open and dev._panel.visible, "F4 opens the developer panel")
				_check(not paused, "...and the game keeps running")
				_check(dev._rows.size() > 20, "...with the tuning sliders (%d)" % dev._rows.size())
				a0 = main.squad.anchor
				Input.action_press("move_left")
				t0 = f
				phase = 1
		1:
			if f - t0 == 150:
				var v1: float = main.squad.anchor.distance_to(a0) / 2.5
				var s: HSlider = main.dev._rows["move_speed"]["slider"]
				s.value = 12.0
				_check(is_equal_approx(Squad.MOVE_SPEED, 12.0), "the slider sets the squad speed (%.1f)" % Squad.MOVE_SPEED)
				print("speed at default: %.1f m/s" % v1)
				a0 = main.squad.anchor
				Input.action_release("move_left")
				Input.action_press("move_right")
				t0 = f
				phase = 2
		2:
			if f - t0 == 150:
				a0 = main.squad.anchor
			if f - t0 == 240:
				var v2: float = main.squad.anchor.distance_to(a0) / 1.5
				print("speed at 12: %.1f m/s" % v2)
				_check(v2 > 9.0, "the squad really moves faster (%.1f m/s)" % v2)
				var dev = main.dev
				_check(dev._rows["move_speed"]["name"].get_theme_color("font_color") == dev.AMBER, "a changed value shows amber")
				dev._copy()
				_check(dev.last_copy.contains("Squad speed (m/s): 12  (default 6.5)"), "COPY VALUES lists it")
				_check(dev.changed().size() == 1, "one value changed (%d)" % dev.changed().size())
				dev._reset("move_speed")
				_check(is_equal_approx(Squad.MOVE_SPEED, 6.5), "R puts it back (%.1f)" % Squad.MOVE_SPEED)
				# An enemy number.
				var es: HSlider = dev._rows["acc_%d" % Weapons.difficulty]["slider"]
				es.value = 2.5
				_check(is_equal_approx(Weapons.tune("acc"), 2.5), "the enemy accuracy slider changes the difficulty's number")
				dev._reset_all()
				_check(dev.changed().is_empty() and is_equal_approx(Weapons.tune("acc"), 1.0), "RESET ALL: everything back to the defaults")
				Input.action_release("move_right")
				dev.close()
				main.manual.open()
				t0 = f
				phase = 3
		3:
			if f - t0 == 5:
				var tabs: TabContainer = main.manual._tabs
				var has := false
				for i in tabs.get_tab_count():
					has = has or tabs.get_tab_title(i) == "LEVELS"
				_check(has, "the Esc menu has a LEVELS tab")
				var b: Button = _find(main.manual, "Level100")
				var n := 0
				for e in load("res://scripts/menu.gd").ENTRIES:
					if _find(main.manual, "Level%d" % e[0]) != null:
						n += 1
				_check(n == 7, "...with a button for every level (%d)" % n)
				_check(_find(main.manual, "Level1").text.contains("HERE NOW"), "...the current one marked")
				b.emit_signal("pressed")
				t0 = f
				phase = 4
		4:
			if f - t0 == 30:
				var fl := _scene_with("forced_input")
				_check(fl != null, "LEVELS > ARMORED FLEET: the fleet is up")
				_check(not paused, "...not paused")
				main.queue_free()
				main = fl
				main.forced_input = {"move": Vector2(0, -1)}
				t0 = f
				phase = 5
		5:
			if f - t0 == 60:
				_key(KEY_F4)
			if f - t0 == 70:
				_check(main.dev.is_open and main.dev._rows.has("fleet_speed"), "fleet: F4 dev panel with the fleet's sliders")
				main.dev._rows["fleet_speed"]["slider"].value = 22.0
			if f - t0 == 250:
				a0 = main.anchor
			if f - t0 == 370:
				var v: float = main.anchor.distance_to(a0) / 2.0
				print("fleet speed at 22: %.1f m/s" % v)
				_check(v > 14.0, "fleet speed slider works (%.1f m/s)" % v)
				main.dev._reset_all()
				_check(is_equal_approx(Fleet.SPEED, 11.0), "fleet reset")
				main.dev.close()
				main.set_paused(true)
			if f - t0 == 380:
				_check(paused and main.is_paused(), "fleet: Esc pauses")
				var b: Button = _find(main, "Level3")
				_check(b != null, "...with the level list")
				load("res://scripts/main.gd").forced_map = -1     # (this test forced the test field)
				b.emit_signal("pressed")
				t0 = f
				phase = 6
		6:
			if f - t0 == 40:
				var m: Node = null
				for c in root.get_children():
					if c.get("squad") != null and c.get("map_index") != null:
						m = c
				_check(m != null and m.map_index == 3, "fleet pause > BIFROST: there")
				_check(not paused, "...not paused")
				print("dev_test: %d checks, %d failures" % [checks, fails])
				quit(1 if fails > 0 else 0)
	return false
