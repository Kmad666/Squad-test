extends SceneTree
## Ad hoc: play a map on rails with fire at will and print what the enemy's
## tactics decide.  MAP=4 (default): up the road behind the LAV.
var main
var f := 0
var legs := []
var leg := 0

func _initialize() -> void:
	var map := int(OS.get_environment("MAP")) if OS.has_environment("MAP") else 4
	load("res://scripts/main.gd").forced_map = map
	load("res://scripts/enemy_tactics.gd").verbose = true
	legs = {4: [Vector3(2, 0, 30), Vector3(-6, 0, -20), Vector3(-9, 0, -52)], 3: [Vector3(0, 0, 20), Vector3(0, 0, -10), Vector3(0, 0, -36)], 0: [Vector3(0, 0, 14), Vector3(0, 0, -8), Vector3(-2, 0, -26)], 1: [Vector3(2, 0, 12), Vector3(4, 0, -12), Vector3(20, 0, -24)]}[map]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	if f == 60:
		sq.auto_fire = true
		sq.move_to(legs[0])
	if f > 60 and f % 60 == 0 and leg < legs.size() and sq.teams[0]["order_target"] == null and not main.any_area_alerted() or (f % 1500 == 0 and leg < legs.size()):
		leg += 1
		if leg < legs.size():
			sq.move_to(legs[leg])
	if f % 600 == 0:
		print("t %3ds  men %d kia %d  kills %d  %s  %s%s" % [f / 60, sq.soldiers.size(), sq.kia, main.kills, main.areas_text(), sq.status_text(), ("  LAV hp %.0f" % sq.lav.hp) if sq.lav else ""])
	if f > 60 * 150 or sq.soldiers.is_empty():
		quit()
	return false
