extends SceneTree
## OPERATION GORDIAN (map 5), the Berlin crossroads from design/berlin:
##  - the navigation mesh connects the start to every enemy post and the
##    rocket team
##  - each of the five carriage gateways and the break in the vacant lot's
##    hoarding really is a way through (the walk is about the straight line,
##    not a detour round the block)
##  - the closed north-west block can't be entered
##  - the squad marches from the start through the Gordianstraße gateway
##    into the south-east courtyard and links up with the rocket team there
##    (nobody left behind in the tunnel)
## Prints FAIL lines and exits 1 on any failure.

var main
var f := 0
var fails := 0
var checks := 0
var leg := 0
const ROUTE := [Vector3(0, 0, 66), Vector3(8, 0, 57), Vector3(30, 0, 57), Vector3(38, 0, 46)]
# [from, to, what]: straight hops through a gateway
const WAYS := [
	[Vector3(8, 0, 57), Vector3(27, 0, 57), "Gordianstrasse -> south-east yard (z 57)"],
	[Vector3(58, 0, 29), Vector3(58, 0, 10), "south-east yard -> Kettenstrasse (x 58)"],
	[Vector3(-8, 0, 63), Vector3(-27, 0, 63), "Gordianstrasse -> south-west yard (z 63)"],
	[Vector3(-57.3, 0, 30), Vector3(-57.3, 0, 10), "south-west yard -> vacant lot -> Kettenstrasse"],
	[Vector3(42, 0, -10), Vector3(42, 0, -29), "Kettenstrasse -> north-east yard (x 42)"],
	[Vector3(27, 0, -63), Vector3(8, 0, -63), "north-east yard -> Gordianstrasse (z -63)"],
]


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 5
	load("res://scripts/enemy_tactics.gd").flanking = false     # a quiet walk: the tactics have their own test
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _walk(a: Vector3, b: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(main.get_world_3d().navigation_map, a, b, true)
	if path.size() < 2:
		return INF
	var end: Vector3 = path[path.size() - 1]
	if Vector2(end.x - b.x, end.z - b.z).length() > 1.5:
		return INF                 # can't get there: the path stops short
	var n := 0.0
	for i in path.size() - 1:
		n += path[i].distance_to(path[i + 1])
	return n


func _physics_process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	if f == 30:
		var start: Vector3 = main.map.START
		_check(main.nav_half == 96.0, "map is the district's size (half %.0f)" % main.nav_half)
		for a in main.areas:
			for m in a["members"]:
				if m.kind == "infantry":
					_check(_walk(start, m.global_position) < 400.0, "can walk from the start to %s post at %s" % [a["name"], m.global_position])
		_check(_walk(start, main.map.AT_TEAM) < 120.0, "rocket team reachable (%.0f m walk)" % _walk(start, main.map.AT_TEAM))
		for w in WAYS:
			var direct: float = (w[0] as Vector3).distance_to(w[1])
			var walk := _walk(w[0], w[1])
			_check(walk < direct + 6.0, "%s is a way through (%.0f m walk for %.0f m)" % [w[2], walk, direct])
		_check(_walk(start, Vector3(-60, 0, -60)) == INF, "the north-west block is closed")
		_check(_walk(start, Vector3(75, 0, 80)) == INF, "no way into the rear houses of the south-east block")
		# Nothing spawned inside a wall.
		for a in main.areas:
			for m in a["members"]:
				_check(not main.CoverUtil.inside_any(main.cover_defs, m.global_position, 0.1), "%s man at %s is clear of every box" % [a["name"], m.global_position])
		main.areas[0]["alerted"] = false
	# March: up the street, through the gateway, to the rocket team. The
	# south barricade is asleep for it (spotting off, men unhurt).
	if f >= 30:
		for s in sq.soldiers:
			s.hp = s.MAX_HP
		for a in main.areas:
			for m in a["members"]:
				if m.kind == "infantry":
					m._gun.blind_t = 2.0
		if leg < ROUTE.size() and sq.teams[0]["order_target"] == null and (f == 30 or sq.centroid().distance_to(ROUTE[maxi(leg - 1, 0)]) < 5.0 or leg == 0):
			sq.move_to(ROUTE[leg])
			leg += 1
	if f == 60 * 75:
		var n: int = sq.soldiers.size()
		_check(n == 9, "the rocket team joined in the courtyard (%d men)" % n)
		var worst := 0.0
		for s in sq.soldiers:
			worst = maxf(worst, s.global_position.distance_to(sq.centroid()))
		_check(sq.centroid().distance_to(main.map.AT_TEAM) < 12.0, "the squad is in the south-east courtyard (%.0f m from the link-up)" % sq.centroid().distance_to(main.map.AT_TEAM))
		_check(worst < 9.0, "nobody left behind on the way (furthest man %.1f m from the group)" % worst)
		print("berlin_test: %d checks, %d failures" % [checks, fails])
		quit(1 if fails > 0 else 0)
	return false
