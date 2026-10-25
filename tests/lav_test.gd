extends SceneTree
## Combined arms on OPERATION SLEIPNIR (map 4):
##  1. at the start the LAV is in front and the infantry stack up tight
##     behind it (the rear face, every man within a few metres of the hull)
##  2. holding W: the LAV drives north at the front, the men keep behind it
##     the whole way, nobody gets left, nobody stands in front of it
##  3. contact at the OUTPOST with fire at will: the LAV's 25mm and the men
##     (leaning out past the hull) both shoot, and enemies go down
##  4. Z: the LAV holds (overwatch) and the men get up and move on their own;
##     Z again: they stack on it again
##  5. the LAV destroyed: the men carry on as normal infantry
## Prints FAIL lines and exits 1 on any failure.

const LavScript = preload("res://scripts/lav.gd")

var main
var f := 0
var phase := 0
var t0 := 0
var fails := 0
var checks := 0
var lav_start := Vector3.ZERO
var worst_behind := 0.0         # how far any man got ahead of the LAV's rear (m), while driving
var worst_gap := 0.0            # furthest any man got from the hull while driving
var peeked := false
var men_shots0 := 0
var max_z := 0.0


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 4
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _men_shots() -> int:
	var n := 0
	for s in main.squad.soldiers:
		n += s.shots
	return n


## A man's place in the LAV's frame (x across, z along; front is +z).
func _local(s: Node3D) -> Vector3:
	return main.squad.lav.global_transform.affine_inverse() * s.global_position


func _hull_gap(s: Node3D) -> float:
	var l := _local(s)
	return Vector2(maxf(absf(l.x) - LavScript.HALF_W, 0.0), maxf(absf(l.z) - LavScript.HALF_L, 0.0)).length()


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	var lav = sq.lav
	match phase:
		0:
			if f == 2:
				_check(lav != null, "the LAV is part of the unit on this map")
				_check(main.nav_half > 100.0, "the map is big (half size %.0f)" % main.nav_half)
				_check(main.vehicle_nav_map.is_valid(), "vehicle navigation map baked")
				lav_start = lav.global_position
			if f == 300:
				var stacked: int = sq.stacked_count(0)
				_check(stacked == sq.soldiers.size(), "at the start every man is stacked on the LAV (%d/%d)" % [stacked, sq.soldiers.size()])
				_check(sq._stack_face == 0, "the stack is behind the LAV (face %s)" % sq.STACK_FACES[maxi(sq._stack_face, 0)])
				for s in sq.soldiers:
					var l := _local(s)
					_check(l.z < -LavScript.HALF_L + 0.3, "man %d behind the hull (local z %.1f)" % [s.index, l.z])
					_check(_hull_gap(s) < 5.0, "man %d tight on the hull (%.1f m)" % [s.index, _hull_gap(s)])
				_check(main.status_panel.cover_text().contains("LAV"), "status panel says they're behind the LAV")
				phase = 1
				t0 = f
				Input.action_press("move_forward")
		1:
			# Driving north. Watch the formation every frame once it's rolling.
			if f - t0 > 120:
				for s in sq.soldiers:
					var l := _local(s)
					worst_behind = maxf(worst_behind, l.z + LavScript.HALF_L)
					worst_gap = maxf(worst_gap, _hull_gap(s))
			if f - t0 == 900:
				Input.action_release("move_forward")
				var moved: float = lav_start.z - lav.global_position.z
				_check(moved > 25.0, "the LAV drove north (%.1f m)" % moved)
				_check(worst_behind < 0.5, "nobody got in front of the LAV's rear while driving (worst %.2f m)" % worst_behind)
				_check(worst_gap < 7.0, "nobody fell far behind the LAV (worst %.1f m from the hull)" % worst_gap)
				_check(lav.global_position.z < sq.centroid().z, "the LAV leads the unit")
				print("drive: %.1f m, worst ahead of rear %.2f, worst gap %.1f" % [moved, worst_behind, worst_gap])
				phase = 2
				t0 = f
		2:
			if f - t0 == 240:
				_check(sq.stacked_count(0) == sq.soldiers.size(), "stopped: everyone settles in the stack (%d/%d)" % [sq.stacked_count(0), sq.soldiers.size()])
				# Fight: fire at will, push up to the outpost.
				sq.auto_fire = true
				men_shots0 = _men_shots()
				Input.action_press("move_forward")
				phase = 3
				t0 = f
		3:
			for s in sq.soldiers:
				if s._peeking:
					peeked = true
			if lav.global_position.z < 42.0 and Input.is_action_pressed("move_forward"):
				Input.action_release("move_forward")
			if f - t0 == 1800:
				Input.action_release("move_forward")
				var area: Dictionary = main.areas[0]
				var alive := 0
				for m in area["members"]:
					if m.alive:
						alive += 1
				_check(area["alerted"], "the outpost saw us coming")
				_check(lav.shots > 0, "the LAV's 25mm fired (%d rounds)" % lav.shots)
				_check(_men_shots() > men_shots0, "the infantry fired too (%d rounds)" % (_men_shots() - men_shots0))
				_check(peeked, "men leaned out past the hull to shoot")
				_check(alive < area["members"].size(), "outpost took casualties (%d of %d left)" % [alive, area["members"].size()])
				# The stack keeps the hull between it and the nearest live enemy that has spotted us.
				var near: Node3D = null
				for a in main.areas:
					if a["alerted"]:
						for m in a["members"]:
							if m.alive and (near == null or lav.global_position.distance_to(m.global_position) < lav.global_position.distance_to(near.global_position)):
								near = m
				if near and lav.global_position.distance_to(near.global_position) < 110.0:
					var to_enemy: Vector3 = near.global_position - lav.global_position
					to_enemy.y = 0
					_check(sq._stack_threat.dot(to_enemy.normalized()) > 0.95, "the stack shelters from the nearest spotted enemy")
					var lt: Vector3 = lav.global_transform.basis.inverse() * to_enemy.normalized()
					var face: Vector3 = [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)][sq._stack_face]
					_check(face.dot(lt) < 0.0, "the men are on the far side of the hull from it (%s)" % sq.STACK_FACES[sq._stack_face])
				_check(lav.alive and sq.soldiers.size() >= 4, "the unit survived the contact (LAV hp %.0f, %d men)" % [lav.hp, sq.soldiers.size()])
				print("contact: LAV %d rounds %d hits, men %d rounds, outpost %d/%d left, LAV hp %.0f, men %d" % [lav.shots, lav.hits, _men_shots() - men_shots0, alive, area["members"].size(), lav.hp, sq.soldiers.size()])
				sq.auto_fire = false
				# Z: LAV to overwatch.
				_key(KEY_Z)
				phase = 4
				t0 = f
				lav_start = lav.global_position
		4:
			if f - t0 == 5:
				_check(not lav.together, "Z: the LAV holds on overwatch")
				Input.action_press("move_left")
			if f - t0 == 300:
				Input.action_release("move_left")
				var stacked := 0
				for s in sq.soldiers:
					if s.stacked:
						stacked += 1
				_check(stacked == 0, "on their own: nobody's stacked any more (%d)" % stacked)
				_check(lav.global_position.distance_to(lav_start) < 1.5, "the LAV stayed put (%.1f m)" % lav.global_position.distance_to(lav_start))
				_check(sq.centroid().distance_to(lav.global_position) > 6.0, "the men moved off without it")
				_key(KEY_Z)
			if f - t0 == 900:
				_check(lav.together, "Z again: LAV with us")
				_check(sq.stacked_count(0) >= sq.soldiers.size() - 1, "men stacked on it again (%d/%d)" % [sq.stacked_count(0), sq.soldiers.size()])
				lav.armor_hit(10000.0)
				phase = 5
				t0 = f
		5:
			if f - t0 == 5:
				_check(not lav.alive, "the LAV can be destroyed")
				_check(main.unit_label.text.contains("DESTROYED") or main._unit_text().contains("DESTROYED"), "the unit panel says so")
				Input.action_press("move_right")
			if f - t0 == 300:
				Input.action_release("move_right")
				var stacked := 0
				for s in sq.soldiers:
					if s.stacked:
						stacked += 1
				_check(stacked == 0, "LAV gone: nobody's stacked on the wreck")
				_check(not sq.status_text().contains("LAV"), "status no longer mentions the LAV stack")
				print("lav_test: %d checks, %d failures" % [checks, fails])
				quit(1 if fails > 0 else 0)
	return false
