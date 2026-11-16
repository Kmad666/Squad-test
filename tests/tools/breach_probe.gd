extends SceneTree
## Ad hoc balance run (not part of the test suite): OPERATION GORDIAN for
## real, no cheats. The squad goes through the east gateway and the
## courtyard to the back door of the EAST HOUSE and clears it room by room
## with fire at will. Prints each step and what it cost.
var main
var f := 0
var step := 0
var t0 := 0
# [what, arg]: "move" to a point, "breach" a door (index into main.doors)
var plan := [["move", Vector3(0, 0, 66)], ["move", Vector3(8, 0, 57)], ["move", Vector3(30, 0, 57)], ["move", Vector3(28, 0, 37.5)],
	["breach", 1], ["breach", 2], ["breach", 4], ["breach", 3], ["breach", 5]]
var going := false

func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 5
	load("res://scripts/enemy_tactics.gd").verbose = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _say(text: String) -> void:
	var sq = main.squad
	var hp := 0.0
	var low := 100.0
	for m in sq.soldiers:
		hp += m.hp
		low = minf(low, m.hp)
	var house := ""
	for a in main.areas:
		if a["name"] == "EAST HOUSE":
			for m in a["members"]:
				if m.alive:
					house += " r%d(%s%s)" % [main.room_at(m.global_position, 0.3), "blind " if m._gun.blind_t > 0.0 else "", "pinned" if m._gun.pinned() else "up"]
	print("t %3ds  %-34s men %d kia %d  hp %3.0f (lowest %3.0f)  kills %d  rooms %d  house:%s" % [f / 60, text, sq.soldiers.size(), sq.kia, hp, low, main.kills, main.rooms_cleared, house if house != "" else " empty"])

func _physics_process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	if f < 60:
		return false
	if f == 60:
		sq.auto_fire = true
	if sq.soldiers.is_empty() or step >= plan.size() or f > 60 * 300:
		_say("END" if step >= plan.size() else "STOPPED at step %d" % step)
		quit()
		return false
	var e: int = f - t0
	var what: String = plan[step][0]
	if what == "move":
		if not going:
			sq.move_to(plan[step][1])
			going = true
			t0 = f
		elif sq.centroid().distance_to(plan[step][1]) < 4.0 or e > 60 * 40:
			_say("at %s" % plan[step][1])
			going = false
			step += 1
	else:
		var br: Variant = sq.teams[0].get("breach")
		if not going:
			sq.breach_order(plan[step][1])
			going = sq.teams[0].get("breach") != null
			t0 = f
			if not going:
				_say("door %d: %s" % [plan[step][1], main._notice])
				step += 1
		elif br != null and br["phase"] == "stack" and (sq.stack_ready(0) >= mini(4, sq.soldiers.size()) or e > 60 * 10):
			_say("GO door %d into room %d (%d in it)" % [plan[step][1], br["room"], main.enemies_in_room(br["room"]).size()])
			sq.breach_order()
		elif br == null or e > 60 * 40:
			_say("door %d -> room cleared in %.0f s" % [plan[step][1], e / 60.0] if br == null else "door %d: gave up" % plan[step][1])
			sq.cancel_breach(0)
			going = false
			step += 1
	return false
