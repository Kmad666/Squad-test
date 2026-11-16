extends SceneTree
## Houses you can go into, and clearing them (OPERATION GORDIAN, map 5):
##  - four houses, their rooms and doors are registered; every door can be
##    walked through, both ways
##  - a window is an opening at chest height (a shot passes) over a sill
##    (a low shot doesn't) under a lintel (a high one doesn't)
##  - the EAST HOUSE garrison stays inside its house with the squad outside
##  - G at the front door: the team stacks beside it, against the wall,
##    nobody in the doorway, nobody inside yet
##  - G again: a flashbang goes in (the room is defended), four men enter
##    and reach their corners, the rest hold the door, the defender dies,
##    ROOM CLEAR; the storeys above lift off and the camera looks down
##  - then the same through an inside door into the back room
##  - a move order calls a stack off; leaving the house puts the roof back
## Prints FAIL lines and exits 1 on any failure.

const Tactics = preload("res://scripts/enemy_tactics.gd")

var main
var f := 0
var phase := 0
var t0 := 0
var fails := 0
var checks := 0
var flashed := false
var blinded := false


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 5
	Tactics.flanking = false
	Tactics.falling_back = false
	Tactics.reinforcing = false
	Tactics.assaulting = false
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _next() -> void:
	phase += 1
	t0 = f


func _walk(a: Vector3, b: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(main.get_world_3d().navigation_map, a, b, true)
	if path.size() < 2:
		return INF
	var end: Vector3 = path[path.size() - 1]
	if Vector2(end.x - b.x, end.z - b.z).length() > 1.0:
		return INF
	var n := 0.0
	for i in path.size() - 1:
		n += path[i].distance_to(path[i + 1])
	return n


func _clear_shot(a: Vector3, b: Vector3) -> bool:
	return main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1)).is_empty()


func _area(name: String) -> Dictionary:
	for a in main.areas:
		if a["name"] == name:
			return a
	return {}


func _door(at: Vector3) -> int:
	for i in main.doors.size():
		if main.doors[i]["pos"].distance_to(at) < 0.5:
			return i
	return -1


func _in_rect(p: Vector3, r: Rect2, grow := 0.0) -> bool:
	return r.grow(grow).has_point(Vector2(p.x, p.z))


func _physics_process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	if f < 20:
		return false
	var e: int = f - t0
	var east: Dictionary = _area("EAST HOUSE")
	# The squad can't be hurt and holds its fire unless it's going through a
	# door; everyone but the house's own garrison is kept blind.
	sq.forced_mode = 0
	for s in sq.soldiers:
		s.hp = s.MAX_HP
	for a in main.areas:
		if a != east:
			for m in a["members"]:
				if m.kind == "infantry":
					m._gun.blind_t = 2.0
	var br: Variant = sq.teams[0].get("breach")
	if br != null and br.get("flash_t", 0.0) > 0.0:
		flashed = true
	for m in east["members"]:
		if m.alive and m._gun.blind_t > 1.0:
			blinded = true
	match phase:
		0:
			if f == 20:
				_check(main.houses.size() == 4 and main.rooms.size() == 20 and main.doors.size() == 29, "4 houses, 20 rooms, 29 doors (%d, %d, %d)" % [main.houses.size(), main.rooms.size(), main.doors.size()])
				for d in main.doors:
					var p: Vector3 = d["pos"]
					var n: Vector3 = d["normal"]
					var a: Vector3 = main.room_center(d["a"]) if d["a"] >= 0 else p - n * 2.5
					var b: Vector3 = main.room_center(d["b"]) if d["b"] >= 0 else p + n * 2.5
					var direct := a.distance_to(p) + p.distance_to(b)
					_check(_walk(a, b) < direct + 3.0 and _walk(b, a) < direct + 3.0, "door at %s can be walked through (%.1f m for %.1f)" % [p, _walk(a, b), direct])
					_check(_clear_shot(p - n * 1.5 + Vector3(0, 1.4, 0), p + n * 1.5 + Vector3(0, 1.4, 0)), "door at %s is open to a shot" % p)
					_check(not _clear_shot(p - n * 1.5 + Vector3(0, 3.0, 0), p + n * 1.5 + Vector3(0, 3.0, 0)), "wall above the door at %s" % p)
				# The EAST HOUSE's front window (bay 0, facing Gordianstrasse at x = 11).
				var r0: Rect2 = main.rooms[0]["rect"]
				var wz: float = r0.get_center().y + 0.2
				var out := Vector3(8.5, 0, wz)
				var inn := Vector3(13.5, 0, wz)
				_check(_clear_shot(out + Vector3(0, 1.5, 0), inn + Vector3(0, 1.5, 0)), "window: a chest-high shot goes through")
				_check(not _clear_shot(out + Vector3(0, 0.5, 0), inn + Vector3(0, 0.5, 0)), "window: the sill stops a low shot")
				_check(not _clear_shot(out + Vector3(0, 2.9, 0), inn + Vector3(0, 2.9, 0)), "window: the wall above stops a high shot")
				_check(_walk(out, inn) > 8.0, "window: you can't walk through it (%.1f m round)" % _walk(out, inn))
				_check(east["members"].size() == 3, "EAST HOUSE has its garrison (%d)" % east["members"].size())
				for m in east["members"]:
					_check(main.house_at(m.global_position) == 0, "garrison man starts inside the house")
				_check(main.houses[0]["roof"].visible and not main.cam_rig.indoors, "outside: the house has its upper storeys")
				# Up the street to the front door of the EAST HOUSE.
				east["alerted"] = true
				sq.anchor = Vector3(6.5, 0, 46.5)
				for s in sq.soldiers:
					s.global_position = sq.anchor + s.slot_offset * 0.6
			if f == 20 + 60 * 14:
				for m in east["members"]:
					_check(m.alive and main.house_at(m.global_position) == 0, "14 s of contact: the garrison is still inside its house (%s)" % m.global_position)
				sq.breach_order()
				br = sq.teams[0].get("breach")
				_check(br != null and br["phase"] == "stack", "G: the team stacks on a door (%s, centroid %s)" % [main._notice, sq.centroid()])
				if br != null:
					_check(main.doors[br["door"]]["pos"].distance_to(Vector3(11.2, 0, 43.97)) < 0.5 and br["room"] == 1, "it's the front door, going into the hall (room %d)" % br["room"])
				_next()
		1:
			if e == 60 * 6:
				_check(br != null and sq.stack_ready(0) >= 5, "the stack is in place (%d of %d)" % [sq.stack_ready(0), sq.soldiers.size()])
				var door: Vector3 = main.doors[br["door"]]["pos"]
				for s in sq.soldiers:
					var off: Vector3 = s.global_position - door
					_check(off.x < -0.3, "#%d stacked outside the wall (%.2f m)" % [s.index, off.x])
					_check(absf(off.z) > 0.85, "#%d clear of the doorway (%.2f m to the side)" % [s.index, absf(off.z)])
					_check(absf(off.x) < 2.2, "#%d against the wall (%.2f m off it)" % [s.index, absf(off.x)])
				_check(sq.status_text().contains("STACKED ON THE DOOR"), "status says so (%s)" % sq.status_text())
				# One defender in the hall, in the open by the window, whatever the garrison has been up to.
				if true:
					for m in east["members"]:
						if m.alive:
							m._release_cover()
							m.global_position = Vector3(12.4, 0, 46.3)
							m._dest = m.global_position
							m._hasty = true
							m.state = 2
							m._check_timer = 30.0
							break
				_check(main.enemies_in_room(1).size() >= 1, "the hall is defended (%d inside)" % main.enemies_in_room(1).size())
				sq.breach_order()
				_next()
		2:
			if e == 2:
				_check(br != null and br["phase"] == "go", "G again: going in")
			if br == null and e > 10:
				print("room 1 cleared %.1f s after GO (flashbang %s, defenders blinded %s)" % [e / 60.0, flashed, blinded])
				_check(flashed, "a flashbang went in first")
				_check(blinded, "it blinded the defenders")
				_check(main.rooms_cleared == 1 and main.enemies_in_room(1).is_empty(), "ROOM CLEAR, nothing alive in it")
				var inside := 0
				var held := 0
				for s in sq.soldiers:
					if _in_rect(s.global_position, main.rooms[1]["rect"], 0.2):
						inside += 1
					elif main.house_at(s.global_position) < 0:
						held += 1
				_check(inside == 4, "four men went in (%d)" % inside)
				_check(held == sq.soldiers.size() - 4, "the rest held the door outside (%d)" % held)
				_check(sq.fire_log[0]["text"] == "BREACH AND CLEAR", "it's in the fire order log")
				_next()
			elif e > 60 * 20:
				_check(false, "the room wasn't cleared in 20 s (%d enemies left in it)" % main.enemies_in_room(1).size())
				_next()
		3:
			if e == 60 * 4:
				_check(main.inside_house == 0 and not main.houses[0]["roof"].visible, "inside: the storeys above are lifted off")
				_check(main.cam_rig.indoors and main.cam_rig.rotation.x < -0.9, "inside: the camera looks down into the rooms (pitch %.2f)" % main.cam_rig.rotation.x)
				_check(main.houses[1]["roof"].visible, "the other houses keep theirs")
				# On through the inside door to the back room.
				sq.breach_order(_door(Vector3(17.5, 0, 42.37)))
				br = sq.teams[0].get("breach")
				_check(br != null and br["room"] == 3, "G inside: stacking on the door to the back room (room %s)" % (str(br["room"]) if br != null else "none"))
			if e == 60 * 10:
				_check(sq.stack_ready(0) >= 4, "stacked inside (%d)" % sq.stack_ready(0))
				for s in sq.soldiers:
					_check(not _in_rect(s.global_position, main.rooms[3]["rect"]), "#%d not in the back room yet" % s.index)
				sq.breach_order()
			if e > 60 * 10 + 10 and sq.teams[0].get("breach") == null:
				var inside := 0
				for s in sq.soldiers:
					if _in_rect(s.global_position, main.rooms[3]["rect"], 0.2):
						inside += 1
				_check(inside == 4 and main.rooms_cleared == 2, "back room cleared by four men (%d in, %d rooms cleared)" % [inside, main.rooms_cleared])
				_next()
			elif e > 60 * 30:
				_check(false, "the back room wasn't cleared")
				_next()
		4:
			if e == 30:
				sq.breach_order(_door(Vector3(21.35, 0, 40.15)))
				_check(sq.teams[0].get("breach") != null, "a third stack (%s)" % main._notice)
			if e == 90:
				sq.move_to(Vector3(5, 0, 50))
				_check(sq.teams[0].get("breach") == null, "a move order calls the stack off")
			if e == 60 * 16:
				_check(main.house_at(sq.centroid()) < 0, "the squad walked back out to the street (%s)" % sq.centroid())
				_check(main.inside_house < 0 and main.houses[0]["roof"].visible and not main.cam_rig.indoors, "outside again: roof back, camera back")
				print("breach_test: %d checks, %d failures" % [checks, fails])
				quit(1 if fails > 0 else 0)
	return false
