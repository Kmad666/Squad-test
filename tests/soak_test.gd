extends SceneTree
## Randomised long soak: random move orders, cover toggles, fire modes,
## specials, quality toggles and restarts. Watches for errors.
var main
var f := 0
var rng := RandomNumberGenerator.new()
var restarts := 0
var duration := 60 * 60 * int(OS.get_environment("MINUTES") if OS.get_environment("MINUTES") != "" else "5")
func _initialize():
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	load("res://scripts/main.gd").forced_map = int(OS.get_environment("MAP")) if OS.get_environment("MAP") != "" else 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _physics_process(_d):
	f += 1
	if main == null or not is_instance_valid(main):
		return false
	var sq = main.squad
	if f % 3 == 0: main.debug_reticle_all = rng.randf() < 0.5
	if f % 90 == 0:
		match rng.randi_range(0, 11):
			0, 1: sq.move_to(Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45)))
			2: sq.take_cover() if not sq.in_cover else sq.leave_cover()
			3: sq.forced_mode = rng.randi_range(0, 2)
			4: sq.forced_specials = not sq.forced_specials
			5: main.cam_rig.yaw = rng.randf_range(-PI, PI)
			6: main.toggle_quality() if rng.randf() < 0.5 else main.toggle_retro()
			7: sq.anchor = Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45))
			8: sq.join_teams() if sq.split else sq.split_teams()
			9: sq.switch_team()
			10: sq.start_bound(Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-45, 45)))
			11: sq.set_holding(not sq.holding)
	if f % 1800 == 0:
		var alive = 0
		for t in main.targets: alive += int(t.alive)
		print("t=", f / 60, "s squad ", sq.soldiers.size(), " kia ", sq.kia, " enemies alive ", alive, " kills ", main.kills, " nodes ", root.get_child_count(), " objs ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		if sq.soldiers.is_empty() or alive == 0:
			restarts += 1
			print("  reload (", restarts, ")")
			main.queue_free()
			main = load("res://main.tscn").instantiate()
			root.add_child(main)
	if f >= duration:
		print("done, restarts ", restarts)
		quit()
	return false
