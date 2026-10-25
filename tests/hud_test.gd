extends SceneTree
## Bottom-right unit status and the Tab free-mouse mode, on the TEST FIELD:
##  - at rest: HALTED, NO COVER, no fire orders yet
##  - holding W: the arrow / heading match the way the camera faces
##  - fire orders are logged newest first, three at most; specials log too
##  - in cover the panel says so
##  - free mouse: right-drag pans the camera, plain motion doesn't;
##    O opens the reticle settings, Tab closes them
## Prints FAIL lines and exits 1 on any failure.

const StatusPanel = preload("res://scripts/status_panel.gd")

var main
var f := 0
var fails := 0
var checks := 0


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
	main._input(ev)


func _process(_delta: float) -> bool:
	f += 1
	var sq = main.squad
	var sp = main.status_panel
	match f:
		30:
			_check(sp != null and sp.is_inside_tree(), "status panel in the HUD")
			_check(sp.move_text() == "HALTED", "at rest: HALTED (got %s)" % sp.move_text())
			_check(sp.cover_text().contains("NO COVER"), "at rest: NO COVER")
			_check(sp.orders_text().contains("none yet"), "no fire orders yet")
			_check(StatusPanel.point_name(StatusPanel.bearing(Vector3(1, 0, 0))) == "E", "bearing: +X is east")
			_check(StatusPanel.point_name(StatusPanel.bearing(Vector3(-1, 0, -1))) == "NW", "bearing: -X-Z is north-west")
			Input.action_press("move_forward")
		120:
			_check(sp.moving(), "holding W: moving")
			var want: String = StatusPanel.point_name(StatusPanel.bearing(main.camera_forward()))
			var got: String = StatusPanel.point_name(StatusPanel.bearing(sq.move_vel))
			_check(got == want, "heading %s matches the camera's %s" % [got, want])
			_check(sp.move_text().contains(want), "move text shows the heading (%s)" % sp.move_text())
			Input.action_release("move_forward")
		200:
			_check(not sp.moving(), "released W: halted again")
			sq.forced_mode = sq.FOCUS
		210:
			sq.forced_mode = sq.HOLD
		220:
			sq.forced_mode = sq.AT_WILL
		230:
			var texts: Array = sq.fire_log.map(func(e): return e["text"])
			_check(texts == ["FIRE AT WILL", "HOLD FIRE", "FOCUS FIRE"], "fire log newest first (got %s)" % [texts])
			sq.forced_mode = sq.HOLD
		240:
			_check(sq.fire_log.size() == 3, "fire log keeps three")
			_check(sq.fire_log[0]["text"] == "HOLD FIRE", "newest is HOLD FIRE")
			sq.use_special()
		245:
			_check(sq.fire_log[0]["text"].ends_with("m") and sq.fire_log.size() == 3, "special logged with range (got %s)" % sq.fire_log[0]["text"])
			_check(sp.orders_text().contains(sq.fire_log[0]["text"]), "panel lists the special")
			sq.take_cover()
		500:
			var ct: String = sp.cover_text()
			_check(ct.contains("COVER") and not ct.contains("NO COVER"), "in cover: panel says so (got %s)" % ct)
			# Free mouse: right-drag pans, bare motion doesn't.
			var rig = main.cam_rig
			rig.free_mouse = true
			var yaw0: float = rig.yaw
			var mv := InputEventMouseMotion.new()
			mv.relative = Vector2(80, 0)
			rig._unhandled_input(mv)
			_check(is_equal_approx(rig.yaw, yaw0), "free mouse: moving the cursor doesn't turn the camera")
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_RIGHT
			down.pressed = true
			rig._unhandled_input(down)
			rig._unhandled_input(mv)
			_check(rig.yaw < yaw0 - 0.1, "free mouse: right-drag pans the camera")
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_RIGHT
			up.pressed = false
			rig._unhandled_input(up)
			var yaw1: float = rig.yaw
			rig._unhandled_input(mv)
			_check(is_equal_approx(rig.yaw, yaw1), "free mouse: let go of RMB, panning stops")
			_check(not rig._panning, "pan ended")
			# O opens the reticle settings, Tab closes them (and switches aim).
			_key(KEY_O)
			_check(main.reticle_panel.visible, "O opens reticle settings")
			_key(KEY_TAB)
			_check(not main.reticle_panel.visible, "Tab closes reticle settings")
			_check(not rig.free_mouse, "Tab from a free mouse goes back to aiming")
		510:
			print("hud_test: %d checks, %d failures" % [checks, fails])
			quit(1 if fails > 0 else 0)
	return false
