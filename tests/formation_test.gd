extends SceneTree
## Formations and pace, on open ground between the start and the first cover
## on the TEST FIELD:
##  1. WEDGE heading east: a point man out front, the rest spread across behind
##  2. turn round, heading west: the formation turns with it and the man now
##     out front takes the point (nobody walks back through the group)
##  3. Y: FILE (long and thin along the way), Y: LINE (wide, shallow)
##  4. J: WALK is half speed, SHIFT: RUSH is faster, and the men keep up
##  5. a 4.4 m gap between two walls: the wedge closes into a file to get
##     through, everybody gets through, and it opens out again after
## Prints FAIL lines and exits 1 on any failure.

const Squad = preload("res://scripts/squad.gd")

var main
var f := 0
var fails := 0
var checks := 0
var phase := 0
var t0 := 0
var speeds: Array = []
var prev_anchor := Vector3.ZERO
var saw_file := false
var lag_max := 0.0


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _teleport(p: Vector3) -> void:
	var sq = main.squad
	sq.teams[0]["anchor"] = p
	sq.teams[0]["order_target"] = null
	for s in sq.soldiers:
		s.global_position = p + s.slot_offset
		s.move_target = s.global_position
	prev_anchor = p


## Spread of the men along and across `fwd`, and who is furthest out front.
func _shape(fwd: Vector3) -> Dictionary:
	var sq = main.squad
	var c: Vector3 = sq.centroid()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var al := []
	var ac := []
	var front: Node3D = null
	for s in sq.soldiers:
		var d: Vector3 = s.global_position - c
		al.append(d.dot(fwd))
		ac.append(d.dot(right))
		if front == null or d.dot(fwd) > (front.global_position - c).dot(fwd):
			front = s
	return {"along": al.max() - al.min(), "across": ac.max() - ac.min(), "front": front}


func _walk(action: String, frames: int) -> void:
	Input.action_press(action)
	t0 = f
	speeds = []
	lag_max = 0.0
	phase_frames = frames
	walking = action


var phase_frames := 0
var walking := ""


func _physics_process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	if walking != "":
		var a: Vector3 = sq.anchor
		if f - t0 > phase_frames - 60:
			speeds.append(a.distance_to(prev_anchor) * 60.0)
		prev_anchor = a
		if f - t0 > phase_frames - 90:     # settled into it (the last 1.5 s)
			for s in sq.soldiers:
				lag_max = maxf(lag_max, s.global_position.distance_to(a + s.slot_offset))
		if sq.formation_now() == Squad.FILE and sq.formation_of() != Squad.FILE:
			saw_file = true
		if f - t0 < phase_frames:
			return false
		Input.action_release(walking)
		walking = ""
	var avg := 0.0
	for v in speeds:
		avg += v
	avg /= maxf(1.0, speeds.size())
	match phase:
		0:
			if f == 20:
				_teleport(Vector3(-20, 0, 30))
				_check(sq.formation_of() == Squad.WEDGE, "a wedge to start with")
			if f == 140:                  # formed up at the halt, facing north: now set off east
				_walk("move_right", 360)
				phase = 1
		1:
			var sh := _shape(Vector3(1, 0, 0))
			print("wedge east: along %.1f across %.1f  speed %.1f  worst lag %.1f" % [sh["along"], sh["across"], avg, lag_max])
			_check(sh["front"].slot_index == 0, "the point man is out in front (front man has place %d)" % sh["front"].slot_index)
			_check(sh["across"] > 4.0 and sh["along"] > 2.0, "a wedge: spread across, staggered back (%.1f x %.1f)" % [sh["across"], sh["along"]])
			_check(absf(avg - Squad.MOVE_SPEED) < 0.8, "MOVE at the usual speed (%.1f m/s)" % avg)
			_check(lag_max < 3.0, "a few seconds after turning, the men are in their places (worst %.1f m off)" % lag_max)
			_walk("move_left", 300)
			phase = 2
		2:
			var sh := _shape(Vector3(-1, 0, 0))
			print("wedge west: along %.1f across %.1f" % [sh["along"], sh["across"]])
			_check(sh["front"].slot_index == 0, "turned round: whoever is out front now has the point")
			_check(sh["across"] > 4.0, "still a wedge across the new heading (%.1f)" % sh["across"])
			sq.cycle_formation()
			_check(sq.formation_of() == Squad.FILE, "Y: FILE")
			_walk("move_right", 300)
			phase = 3
		3:
			var sh := _shape(Vector3(1, 0, 0))
			print("file east: along %.1f across %.1f" % [sh["along"], sh["across"]])
			_check(sh["across"] < 1.8 and sh["along"] > 6.0, "a file: long and thin (%.1f along, %.1f across)" % [sh["along"], sh["across"]])
			sq.cycle_formation()
			_check(sq.formation_of() == Squad.LINE, "Y: LINE")
			_walk("move_left", 300)
			phase = 4
		4:
			var sh := _shape(Vector3(-1, 0, 0))
			print("line west: along %.1f across %.1f" % [sh["along"], sh["across"]])
			_check(sh["across"] > 7.0 and sh["along"] < 2.5, "a line: wide and shallow (%.1f across, %.1f along)" % [sh["across"], sh["along"]])
			sq.cycle_formation()
			_check(sq.formation_of() == Squad.WEDGE, "Y: back to WEDGE")
			sq.toggle_walk()
			_teleport(Vector3(-20, 0, 30))
			_walk("move_right", 240)
			phase = 5
		5:
			print("walk: %.1f m/s" % avg)
			_check(sq.pace_of() == Squad.WALK and sq.soldiers[0].pace == Squad.WALK, "J: walking")
			_check(absf(avg - Squad.MOVE_SPEED * 0.5) < 0.6, "walking is half speed (%.1f m/s)" % avg)
			sq.toggle_walk()
			Input.action_press("rush")
			_walk("move_right", 240)
			phase = 6
		6:
			print("rush: %.1f m/s, worst lag %.1f" % [avg, lag_max])
			_check(sq.pace_of() == Squad.RUSH, "SHIFT: rushing")
			_check(avg > Squad.MOVE_SPEED * 1.25, "rushing is faster (%.1f m/s)" % avg)
			_check(lag_max < 5.0, "the men keep up with a rush (worst %.1f m off)" % lag_max)
			Input.action_release("rush")
			_walls()
			_teleport(Vector3(-14, 0, 30))
			saw_file = false
			_walk("move_right", 600)
			phase = 7
		7:
			var behind := 0
			for s in sq.soldiers:
				if s.global_position.x < 19.0:
					behind += 1
			print("gap: squeezed into a file %s, %d men short of the far side, formation now %s" % [saw_file, behind, sq.formation_text()])
			_check(saw_file, "the wedge closed into a file for the gap")
			_check(behind == 0, "everybody got through the gap (%d short)" % behind)
			_check(sq.formation_now() == Squad.WEDGE, "and opened out again after (%s)" % sq.formation_text())
			print("formation_test: %d checks, %d failures" % [checks, fails])
			quit(1 if fails > 0 else 0)
	return false


## Two walls 4.4 m apart either side of the way east, x 8 to 18.
func _walls() -> void:
	for z in [30.0 - 2.4, 30.0 + 2.4]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10, 3, 0.4)
		cs.shape = box
		b.add_child(cs)
		main.add_child(b)
		b.global_position = Vector3(13, 1.5, z)
