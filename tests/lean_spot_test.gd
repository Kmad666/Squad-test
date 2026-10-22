extends SceneTree
## Puts the squad (with the anti-armor team) behind tall crates at several
## camera angles and checks no two soldiers share a lean-out spot.
var main
var f := 0
var spots := [Vector3(-6, 0, 25), Vector3(-6, 0, 14), Vector3(17, 0, 3), Vector3(4, 0, -21), Vector3(-34, 0, 9)]
var yaws := [0.0, 0.6, -0.6, PI]
var idx := 0
var clashes := 0
var checks := 0
func _initialize():
	load("res://scripts/main.gd").forced_map = int(OS.get_environment("MAP")) if OS.get_environment("MAP") != "" else 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _physics_process(_d):
	f += 1
	var sq = main.squad
	if f == 5:
		sq.anchor = Vector3(-34, 0, 31)   # pick up AT team: 9 men
	if f >= 30 and (f - 30) % 240 == 0:
		if idx >= spots.size() * yaws.size():
			print("tall-cover cases checked: ", checks, "  lean spots too close to another man's spot/lean: ", clashes)
			quit()
			return false
		var sp = spots[idx / yaws.size()]
		main.cam_rig.yaw = yaws[idx % yaws.size()]
		sq.leave_cover()
		sq.anchor = sp
		for s in sq.soldiers: s.global_position = sp + sq.slot_offsets[s.index]
		sq.take_cover()
		idx += 1
	if f >= 30 and (f - 30) % 240 == 200:
		# compare every tall-cover soldier's lean spot to every other soldier's cover + lean spot
		for a in sq.soldiers:
			if a.peeks.is_empty(): continue
			for b in sq.soldiers:
				if a == b: continue
				for lp in a.peeks:
					checks += 1
					var others = [b.cover_pos] + b.peeks
					for o in others:
						if lp.distance_to(o) < 0.8:
							clashes += 1
							print("  clash: soldier ", a.index, " lean ", lp.snapped(Vector3(0.1,0.1,0.1)), " vs soldier ", b.index, " spot ", o.snapped(Vector3(0.1,0.1,0.1)))
	return false
