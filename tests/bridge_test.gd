extends SceneTree
## OPERATION BIFROST (map 3) played by script: link up with the rocket team,
## bound up the bridge firing at will, then onto the north bank. Fails if
## anyone ends up in the river, if the squad never gets across, or on any
## script error. Prints squad and enemy state every 10 s.

var main
var f := 0
var fails := 0
var wet := 0


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 3
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)


func _physics_process(_d) -> bool:
	f += 1
	var sq = main.squad
	match f:
		10:
			_check(main.cover_points.size() > 100, "bridge map has too few cover spots")
			for cp in main.cover_points:
				var p: Vector3 = cp["pos"]
				if absf(p.z) < 28.0 and absf(p.x) > 7.6:
					_check(false, "cover spot in the river at %s" % p)
			sq.forced_mode = 1
			sq.move_to(Vector3(-16, 0, 36))          # pick up the rocket team
		600:
			sq.start_bound(Vector3(0, 0, 4))         # up the bridge, team by team
		3000:
			sq.start_bound(Vector3(0, 0, -16))
		5400:
			sq.move_to(Vector3(0, 0, -36))           # onto the north bank
		7800:
			sq.move_to(Vector3(0, 0, -42))
	for s in sq.soldiers:
		var p: Vector3 = s.global_position
		if absf(p.z) < 27.8 and absf(p.x) > 7.5:
			wet += 1
	for a in main.areas:
		for e in a["members"]:
			if "alive" in e and e.alive and e is CharacterBody3D:
				var p: Vector3 = e.global_position
				if absf(p.z) < 27.8 and absf(p.x) > 7.5:
					wet += 1
	if f % 600 == 0:
		var parts := []
		for a in main.areas:
			var alive := 0
			for e in a["members"]:
				alive += int(e.alive)
			parts.append("%s %d" % [a["name"], alive])
		print("t=%3ds %d men (kia %d) centroid z %.1f | %s" % [f / 60, sq.soldiers.size(), sq.kia, sq.centroid().z, "  ".join(parts)])
	if f == 10800:
		var left := 0
		for t in main.targets:
			left += int(t.alive)
		print("final: enemies left %d, squad %d, in the river %d frames" % [left, sq.soldiers.size(), wet])
		_check(wet == 0, "someone walked into the river (%d soldier-frames)" % wet)
		_check(sq.soldiers.is_empty() or sq.centroid().z < -10.0, "squad never got across the bridge (z %.1f)" % sq.centroid().z)
		print("bridge test failures: ", fails)
		quit(1 if fails > 0 else 0)
	return false
