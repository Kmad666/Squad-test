extends SceneTree
## Scripted run of OPERATION LAMPLIGHTER using the squad orders: link up,
## bound up the road, split a team down the alley, bound into the compound.
var main
var frame := 0
func _initialize():
	load("res://scripts/main.gd").forced_map = 0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _states(area):
	var st = []
	for m in area["members"]:
		if not m.alive: st.append("X"); continue
		if "state" in m: st.append(["POST","MOV","COV"][m.state] + ("/P" if m.suppression_level() > 0.85 else ""))
		else: st.append("APC hp%d" % m.hp)
	return st
func _report():
	var sq = main.squad
	var line = "t=%3ds %d men kia %d | %s | " % [frame/60, sq.soldiers.size(), sq.kia, sq.status_text()]
	for a in main.areas: line += "%s%s %s  " % [a["name"], "!" if a["alerted"] else "", _states(a)]
	print(line)
func _physics_process(_d):
	frame += 1
	var sq = main.squad
	match frame:
		2: main.debug_reticle_all = true
		60: sq.move_to(Vector3(-12, 0, 31))
		600:
			sq.forced_mode = 1
			sq.start_bound(Vector3(0, 0, 13))
		2400: sq.start_bound(Vector3(0, 0, -3))
		3600:
			# Team B flanks down the alley while team A holds the road.
			sq.active = 1
			sq.move_to(Vector3(-19.5, 0, 6))
		4200: sq.move_to(Vector3(-19.5, 0, -14))
		4800:
			sq.active = 0
			sq.start_bound(Vector3(0, 0, -30))
		6600: sq.join_teams()
		6700: sq.move_to(Vector3(-7, 0, -29))   # clear line past the tall crate
		7200:
			sq.select_special(3)          # rockets on the APC from inside the gate
			sq.forced_specials = true
	if frame % 600 == 0: _report()
	if frame == 10200:
		var left := 0
		for t in main.targets: left += int(t.alive)
		print("final: enemies left ", left, ", squad ", sq.soldiers.size(), "/", sq.soldiers.size() + sq.kia, (" - MISSION COMPLETE" if left == 0 else " - NOT CLEARED"))
		quit()
	return false
