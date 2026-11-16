extends SceneTree
## Audit a map's static data (not part of the test suite; MAP=n):
##  - cover spots and lean-out spots that are off the navigation mesh or
##    can't be walked to from the start
##  - enemy posts, the rocket team and the start inside a box or off the mesh
##  - doors whose rooms don't match where they are
var main
var f := 0

func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = int(OS.get_environment("MAP")) if OS.has_environment("MAP") else 0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _reach(a: Vector3, b: Vector3) -> bool:
	var nav: RID = main.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(nav, a, b, true)
	if path.size() < 1:
		return false
	var end: Vector3 = path[path.size() - 1]
	return Vector2(end.x - b.x, end.z - b.z).length() < 0.8

func _process(_d: float) -> bool:
	f += 1
	if f < 20 or (main.cover_pruned < 0 and f < 400):
		return false
	var nav: RID = main.get_world_3d().navigation_map
	var start: Vector3 = main.map.START
	var bad_cp := 0
	var bad_peek := 0
	var shown := 0
	for cp in main.cover_points:
		var p: Vector3 = cp["pos"]
		var near := NavigationServer3D.map_get_closest_point(nav, p)
		var off := Vector2(near.x - p.x, near.z - p.z).length()
		if off > 0.6 or not _reach(start, p):
			bad_cp += 1
			if shown < 6:
				shown += 1
				print("  cover spot %s: %.1f m off the mesh, reachable %s" % [p.snapped(Vector3(0.1, 0.1, 0.1)), off, _reach(start, p)])
		for q in cp["peeks"]:
			var nq := NavigationServer3D.map_get_closest_point(nav, q)
			if Vector2(nq.x - q.x, nq.z - q.z).length() > 0.6:
				bad_peek += 1
	print("%s: %d cover spots (%d pruned at start), %d unreachable or off the mesh, %d lean-out spots off the mesh" % [main.map.NAME, main.cover_points.size(), main.cover_pruned, bad_cp, bad_peek])
	for a in main.areas:
		for m in a["members"]:
			if m.kind == "infantry" and m.alive and (main.CoverUtil.inside_any(main.cover_defs, m.global_position, 0.2) or not _reach(start, m.global_position)):
				print("  POST PROBLEM: %s man at %s (in a box %s, reachable %s)" % [a["name"], m.post, main.CoverUtil.inside_any(main.cover_defs, m.post, 0.2), _reach(start, m.post)])
	if not _reach(start, main.map.AT_TEAM):
		print("  ROCKET TEAM unreachable at ", main.map.AT_TEAM)
	for i in main.doors.size():
		var d: Dictionary = main.doors[i]
		for side in [["a", -1.2], ["b", 1.2]]:
			var want: int = d[side[0]]
			var got: int = main.room_at(d["pos"] + d["normal"] * side[1])
			if want != got:
				print("  DOOR %d: room on side %s should be %d, is %d" % [i, side[0], want, got])
	quit()
	return false
