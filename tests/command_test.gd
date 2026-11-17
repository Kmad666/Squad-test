extends SceneTree
## Command mode (Tab), on the TEST FIELD and then SLEIPNIR:
##  1. the camera lifts for an overview and WASD moves it, not the squad
##  2. RMB on the ground with nothing selected: the team moves there
##  3. LMB picks a man, SHIFT adds one; a box round the whole team is the team
##  4. RMB with two men selected: they go to hold that spot (cover there),
##     the unit panel says DETACHED, and when the team moves on they stay
##  5. U: they rejoin and catch up with the team
##  6. RMB on an enemy marks him: fire at will, and he's the marked target
##  7. SLEIPNIR: a man detached from the LAV stack leaves it, the rest stay
##     stacked; U puts him back on the hull
## Prints FAIL lines and exits 1 on any failure.

var main
var f := 0
var fails := 0
var checks := 0
var phase := 0
var t0 := 0
var anchor0 := Vector3.ZERO
var pair: Array = []
var goal := Vector3.ZERO


func _initialize() -> void:
	_load(1)


func _load(map: int) -> void:
	if main:
		root.remove_child(main)
		main.queue_free()
	load("res://scripts/main.gd").forced_map = map
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _screen(p: Vector3) -> Vector2:
	return main.cam_rig.cam.unproject_position(p)


func _command_on() -> void:
	main.cam_rig.free_mouse = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_d: float) -> bool:
	f += 1
	if root.size != Vector2i(1280, 720):
		root.size = Vector2i(1280, 720)   # the headless window snaps back to 64 px
	var sq = main.squad
	var cmd = main.command
	match phase:
		0:
			if f == 30:
				_command_on()
				anchor0 = sq.anchor
			if f == 150:
				_check(cmd.active(), "Tab: command mode")
				_check(main.cam_rig.rotation.x < -0.8, "the camera looks down over the field (pitch %.2f)" % main.cam_rig.rotation.x)
				Input.action_press("move_forward")
			if f == 210:
				Input.action_release("move_forward")
				_check(main.cam_rig.pan.length() > 5.0, "WASD moves the camera (%.1f m)" % main.cam_rig.pan.length())
				_check(sq.anchor.distance_to(anchor0) < 0.5, "...and not the squad (%.1f m)" % sq.anchor.distance_to(anchor0))
				main.cam_rig.pan = Vector3.ZERO
			if f == 300:
				# A spot a little left of and below the middle of the screen.
				var mid: Vector2 = main.get_viewport().get_visible_rect().size / 2.0
				goal = cmd.ground_at(mid + Vector2(-380, 140))
				_check(cmd.enemy_at(mid + Vector2(-380, 140)) == null, "(no enemy under the test click)")
				cmd.right_click(mid + Vector2(-380, 140))
				t0 = f
				phase = 1
		1:
			if f - t0 == 480:
				_check(sq.anchor.distance_to(goal) < 1.5 and goal.distance_to(anchor0) > 5.0, "RMB on the ground: the team went there (%.1f m off, %.1f m moved)" % [sq.anchor.distance_to(goal), goal.distance_to(anchor0)])
				var a: Node3D = sq.soldiers[1]
				var b: Node3D = sq.soldiers[2]
				cmd._click_select(_screen(a.global_position + Vector3(0, 1, 0)), false)
				_check(cmd.selection == [a], "LMB picks a man")
				cmd._click_select(_screen(b.global_position + Vector3(0, 1, 0)), true)
				_check(cmd.selection.size() == 2 and cmd.selection.has(b), "SHIFT+LMB adds one")
				_check(cmd.selected_men().size() == 2, "two men selected: orders go to them")
				var r := Rect2(Vector2.ZERO, main.get_viewport().get_visible_rect().size)
				cmd._box_select(r, false)
				_check(cmd.selection.size() == sq.soldiers.size() and cmd.selected_men().is_empty(), "a box round everyone is the whole team (%d of %d boxed: %s)" % [cmd.selection.size(), sq.soldiers.size(), sq.soldiers.map(func(s): return _screen(s.global_position + Vector3(0, 1, 0)).round())])
				cmd.selection = [a, b]
				pair = [a, b]
				cmd.right_click(_screen(Vector3(-4, 0, 38.5)))      # behind the crate south of the start
				t0 = f
				phase = 2
		2:
			if f - t0 == 480:
				var ok := true
				for s in pair:
					ok = ok and s.detached and not sq.team_members(0).has(s)
				_check(ok, "RMB with men selected: they're detached from the team")
				var at := 0.0
				for s in pair:
					at = maxf(at, Vector2(s.global_position.x - s.hold_spot.x, s.global_position.z - s.hold_spot.z).length())
				_check(at < 1.2, "...and reached their spots (worst %.1f m off)" % at)
				_check(pair.all(func(s): return s.state != 0), "...in cover there")
				_check(main._unit_text().contains("DETACHED"), "the unit panel says DETACHED")
				cmd.selection = []
				var mid: Vector2 = main.get_viewport().get_visible_rect().size / 2.0
				goal = cmd.ground_at(mid + Vector2(-420, -60))
				cmd.right_click(mid + Vector2(-420, -60))            # the team moves on
				t0 = f
				phase = 3
		3:
			if f - t0 == 480:
				var at := 0.0
				for s in pair:
					at = maxf(at, s.global_position.distance_to(s.hold_spot))
				_check(sq.anchor.distance_to(goal) < 2.0 and goal.distance_to(pair[0].hold_spot) > 6.0, "the team moved on (%.1f m off its goal, %.1f m from the detached men)" % [sq.anchor.distance_to(goal), goal.distance_to(pair[0].hold_spot)])
				_check(at < 1.2, "the detached men held their spots (worst %.1f m off)" % at)
				cmd.rejoin_selected()                               # U, nothing selected: everybody back
				t0 = f
				phase = 4
		4:
			if f - t0 == 600:
				var far := 0.0
				for s in pair:
					far = maxf(far, s.global_position.distance_to(sq.anchor))
				_check(pair.all(func(s): return not s.detached), "U: rejoined")
				_check(far < 6.0, "...and back with the team (furthest %.1f m)" % far)
				# Mark an enemy: put him on screen first.
				var e: Node3D = null
				for t in main.targets:
					if t.alive and t.kind == "infantry" and (e == null or t.global_position.distance_to(sq.anchor) < e.global_position.distance_to(sq.anchor)):
						e = t
				main.cam_rig.pan = e.global_position - sq.get_focus()
				pair = [e]
				t0 = f
				phase = 5
		5:
			if f - t0 == 120:
				var e: Node3D = pair[0]
				cmd.right_click(_screen(e.global_position + Vector3(0, 1, 0)))
				_check(sq.marked == e, "RMB on an enemy marks him")
				_check(sq.auto_fire, "...and the squad fires at will")
				_load(4)
				f = 0
				phase = 6
		6:
			if f == 300:
				_command_on()
				var stacked: int = sq.stacked_count(0)
				_check(stacked == sq.soldiers.size(), "SLEIPNIR: all stacked on the LAV (%d)" % stacked)
				var m: Node3D = sq.soldiers[3]
				pair = [m]
				sq.detach([m], sq.lav.global_position + Vector3(8, 0, 0))
				t0 = f
				phase = 7
		7:
			if f - t0 == 300:
				var m: Node3D = pair[0]
				_check(not m.stacked and m.detached, "detached from the LAV stack: he leaves it")
				_check(sq.stacked_count(0) == sq.soldiers.size() - 1, "the rest stay stacked (%d of %d)" % [sq.stacked_count(0), sq.soldiers.size() - 1])
				sq.rejoin()
			if f - t0 == 700:
				var m: Node3D = pair[0]
				_check(m.stacked, "U: back on the hull")
				print("command_test: %d checks, %d failures" % [checks, fails])
				quit(1 if fails > 0 else 0)
	return false
