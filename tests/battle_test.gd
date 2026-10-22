extends SceneTree
## Scripted advance: link up with the anti-armor team, take the midfield wall,
## fight ALPHA, then push BRAVO and flank CHARLIE. Prints squad health and
## each enemy area every 10 s.
var main
var frame := 0
var plan := [
	[60, Vector3(-34, 0, 31), -1],      # link up with AT team, hold fire
	[600, Vector3(-14, 0, 21), -1],     # midfield wall
	[900, null, 1],                     # cover + fire at will on ALPHA
	[2100, Vector3(-12, 0, 0), 1],      # bound forward
	[2400, null, 1],
	[3600, Vector3(2, 0, 6), 1],        # shift toward BRAVO
	[3900, null, 1],
	[5100, Vector3(16, 0, -4), 1],      # flank toward CHARLIE
	[5400, null, 1],
]
func _initialize():
	load("res://scripts/main.gd").forced_map = int(OS.get_environment("MAP")) if OS.get_environment("MAP") != "" else 1
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
	var hps = []
	for s in sq.soldiers: hps.append(int(s.hp))
	var line = "t=%3ds squad %d kia %d supp %.2f hp %s kills %d | " % [frame/60, sq.soldiers.size(), sq.kia, sq.avg_suppression(), hps, main.kills]
	for a in main.areas: line += "%s%s %s  " % [a["name"], "!" if a["alerted"] else "", _states(a)]
	print(line)
func _physics_process(_d):
	frame += 1
	var sq = main.squad
	if frame == 2: main.debug_reticle_all = true
	for p in plan:
		if frame == p[0]:
			if p[1] == null: sq.take_cover()
			else: sq.move_to(p[1])
			sq.forced_mode = 1 if p[2] == 1 else 0
			sq.forced_specials = frame >= 2100
			if frame == 5100: sq.select_special(3)   # rockets for CHARLIE
	if frame % 600 == 0: _report()
	if frame == 7200:
		print(main._notice)
		quit()
	return false
