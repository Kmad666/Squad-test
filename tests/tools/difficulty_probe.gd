extends SceneTree
## Plays an operation on rails in one of two styles and reports what it cost
## (balance tuning; not part of the test suite).
##   MAP=0|3|4|5  STYLE=frontal|careful  [DIFF=0|1]  godot --headless --fixed-fps 60 -s tests/tools/difficulty_probe.gd
## Both styles pick up the rocket team first, then go for the nearest position
## that still has enemies, with fire at will and a special every 6 s.
##   frontal: walks straight at it. No cover, no stopping.
##   careful: stops 30 m short, takes cover, fights from there, and closes in
##            cover to cover only when the fight stalls; houses are entered by
##            stacking on a door and breaching, room by room.
## Prints one RESULT line: time, men lost, kills, positions cleared.

const Weapons = preload("res://scripts/weapons.gd")
const LIMIT := 60 * 360
var main
var f := 0
var style := "frontal"
var joined := false
var target: Dictionary = {}
var stall_t := 0.0
var last_alive := -1
var in_contact := false
var breach_wait := 0
var visited := {}
var start_men := 0
var _dead := {}
var _kia := 0


func _initialize() -> void:
	style = OS.get_environment("STYLE") if OS.has_environment("STYLE") else "frontal"
	var M = load("res://scripts/main.gd")
	M.forced_map = int(OS.get_environment("MAP")) if OS.has_environment("MAP") else 0
	if OS.has_environment("DIFF"):
		load("res://scripts/weapons.gd").difficulty = int(OS.get_environment("DIFF"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _alive(a: Dictionary) -> int:
	var n := 0
	for m in a["members"]:
		if m.alive:
			n += 1
	return n


func _nearest_area(from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for a in main.areas:
		if _alive(a) == 0:
			continue
		var d: float = from.distance_to(a["center"])
		if d < bd:
			bd = d
			best = a
	return best


func _finish(why: String) -> void:
	var sq = main.squad
	var cleared := 0
	for a in main.areas:
		if _alive(a) == 0:
			cleared += 1
	var total: int = main.targets.size()
	print("RESULT map %d %-8s diff %d  %-9s t %3ds  lost %d of %d  kills %d of %d  positions %d of %d%s" % [main.map_index, style, load("res://scripts/weapons.gd").difficulty, why, f / 60,
		sq.kia, sq.soldiers.size() + sq.kia, main.kills, total, cleared, main.areas.size(), ("  LAV %s" % ("alive" if sq.lav.alive else "LOST")) if sq.lav else ""])
	quit()


func _physics_process(delta: float) -> bool:
	f += 1
	var sq = main.squad
	if f < 30:
		return false
	if f == 30:
		sq.auto_fire = true
		main.debug_reticle_all = true
	if sq.soldiers.is_empty():
		_finish("WIPED OUT")
		return false
	if f >= LIMIT:
		_finish("TIME UP")
		return false
	var c: Vector3 = sq.centroid()
	if OS.has_environment("LOG"):
		for t in main.targets:
			if not t.alive and not _dead.has(t):
				_dead[t] = true
				print("  t %3ds kill: %s %s at %2.0f m from the squad (he was %s)  squad %d men, hp %d" % [f / 60, t.kind, t.area["name"] if t.get("area") != null else "", t.global_position.distance_to(c),
					["at his post", "running", "in cover"][t.state] if t.kind == "infantry" else "-", sq.soldiers.size(), int(sq.soldiers.reduce(func(a, m): return a + m.hp, 0.0))])
		if sq.kia != _kia:
			_kia = sq.kia
			print("  t %3ds LOST a man (%d left)" % [f / 60, sq.soldiers.size()])
	if f % 30 != 0:
		return false
	# A grenade (or, with a vehicle about, a rocket) every 6 s once a fight is
	# on: what a player who uses his specials manages, not a machine gun of them.
	if f % 360 == 0 and main.any_area_alerted() and sq.total_specials() > 0:
		var armor := false       # a vehicle some rocket man can actually see
		for t in main.targets:
			if t.alive and t.kind == "vehicle" and t.global_position.distance_to(c) < 50.0:
				for s in sq.soldiers:
					if s.special_kind == "rocket" and s.special_ammo > 0 and main.get_world_3d().direct_space_state.intersect_ray(
							PhysicsRayQueryParameters3D.create(s.global_position + Vector3(0, 1.5, 0), t.aim_point(), 1)).is_empty():
						armor = true
		var want := "rocket" if armor else "frag"
		if sq.special_count(want) == 0 and not armor:
			want = "gl"
		if sq.special_count(want) > 0:
			sq.selected_special = Weapons.SPECIAL_ORDER.find(want)
			sq.use_special()
	# 1. The rocket team.
	if not sq.pending_teams.is_empty():
		if sq.teams[0]["order_target"] == null and sq.teams[0].get("breach") == null:
			sq.move_to(sq.pending_teams[0]["center"])
		return false
	# 2. The nearest position that still has enemies.
	if target.is_empty() or _alive(target) == 0:
		if not target.is_empty() and sq.in_cover:
			sq.leave_cover()
		target = _nearest_area(c)
		in_contact = false
		stall_t = 0.0
		last_alive = -1
		visited = {}
		if target.is_empty():
			_finish("WON")
			return false
	var tc: Vector3 = target["center"]
	if style == "frontal":
		sq.move_to(tc)
		return false
	if target.get("rect") != null and _house(sq, c):
		return false
	# Only a vehicle left there: get the rocket men a line to it.
	var foot := 0
	var veh: Node3D = null
	for m in target["members"]:
		if m.alive and m.kind == "infantry":
			foot += 1
		elif m.alive:
			veh = m
	if foot == 0 and veh != null:
		if OS.has_environment("LOG") and f % 600 == 0:
			var los := 0
			for m in sq.soldiers:
				if m.special_kind == "rocket" and main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(m.global_position + Vector3(0, 1.5, 0), veh.aim_point(), 1)).is_empty():
					los += 1
			print("  t %3ds APC hp %d at %s, squad at %s (%.0f m), rockets %d, rocket men with a line %d, in cover %s, order %s" % [f / 60, int(veh.hp), veh.global_position.snapped(Vector3.ONE), c.snapped(Vector3.ONE), c.distance_to(veh.global_position), sq.special_count("rocket"), los, sq.in_cover, sq.teams[0]["order_target"]])
		if sq.in_cover:
			sq.leave_cover()
		if c.distance_to(veh.global_position) > 28.0:
			sq.move_to(veh.global_position + (c - veh.global_position).normalized() * 24.0)
		return false
	# careful: close to 30 m, then fight from cover, creeping up when it stalls.
	var d := c.distance_to(tc)
	var contact: bool = target["alerted"] or d < 34.0
	if not contact:
		if sq.teams[0]["order_target"] == null:
			sq.move_to(tc + (c - tc).normalized() * 30.0)
		return false
	if not in_contact:
		in_contact = true
		sq.take_cover()
		last_alive = _alive(target)
		stall_t = 0.0
		return false
	if not sq.in_cover and sq.teams[0]["order_target"] == null:
		sq.take_cover()
	var n := _alive(target)
	if n < last_alive:
		last_alive = n
		stall_t = 0.0
	else:
		stall_t += 0.5
	if stall_t >= 12.0 and d > 8.0:
		stall_t = 0.0
		sq.move_to(c + (tc - c).normalized() * minf(8.0, d - 6.0))     # in cover this is a cover-to-cover move
	return false


## A garrisoned house: stack on a door and breach, room by room. True while
## it's handling the house (false: nothing to do here, fight from outside).
func _house(sq, c: Vector3) -> bool:
	var br: Variant = sq.teams[0].get("breach")
	if br != null:
		breach_wait += 1
		if br["phase"] == "stack" and (sq.stack_ready(0) >= mini(4, sq.soldiers.size()) or breach_wait > 24):
			sq.breach_order()
			breach_wait = 0
		elif br["phase"] == "go" and breach_wait > 60:
			sq.cancel_breach(0)                 # stuck in a room fight for 30 s: back off and try again
			breach_wait = 0
		return true
	breach_wait = 0
	var here: int = main.room_at(c, 0.3)
	var hi: int = -1
	for i in main.houses.size():
		if main.houses[i]["name"] == target["name"]:
			hi = i
	if hi < 0:
		return false
	if here >= 0:
		visited[here] = true
	# Doors from where we are into a room of this house: enemies inside first, then unvisited.
	var best := -1
	var best_s := INF
	for i in main.doors.size():
		var dd: Dictionary = main.doors[i]
		var into := -2
		if here >= 0:
			if dd["a"] == here:
				into = dd["b"]
			elif dd["b"] == here:
				into = dd["a"]
		elif dd["a"] == -1:
			into = dd["b"]
		elif dd["b"] == -1:
			into = dd["a"]
		if into < 0 or main.rooms[into]["house"] != hi:
			continue
		var sc: float = (dd["pos"] as Vector3).distance_to(c)
		if main.enemies_in_room(into).is_empty():
			sc += 40.0 if not visited.has(into) else 200.0
		if sc < best_s:
			best_s = sc
			best = i
	if best < 0:
		return false
	var dp: Vector3 = main.doors[best]["pos"]
	if here < 0 and c.distance_to(dp) > 6.0:
		if sq.in_cover:
			sq.leave_cover()
		if sq.teams[0]["order_target"] == null:
			# Stand off to the outside of the door, not in front of it.
			var n: Vector3 = main.doors[best]["normal"]
			var out: Vector3 = -n if main.doors[best]["a"] == -1 else n
			sq.move_to(dp + out * 3.0)
		return true
	sq.breach_order(best)
	return sq.teams[0].get("breach") != null
