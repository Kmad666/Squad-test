extends SceneTree
## Randomised long soak: random move orders, WASD bursts (in and out of
## cover), cover toggles, fire modes, specials, quality toggles and restarts.
## Watches for errors.
var main
var f := 0
var rng := RandomNumberGenerator.new()
var restarts := 0
var held := ""                  # WASD action being held, released at release_f
var release_f := 0
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
	if held != "" and f >= release_f:
		Input.action_release(held)
		held = ""
	if f % 90 == 0:
		match rng.randi_range(0, 12):
			0, 1: sq.move_to(Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45)))
			2: sq.take_cover() if not sq.in_cover else sq.leave_cover()
			3: sq.forced_mode = rng.randi_range(0, 2)
			4: sq.forced_specials = not sq.forced_specials
			5: main.cam_rig.yaw = rng.randf_range(-PI, PI)
			6:
				match rng.randi_range(0, 4):
					0: main.toggle_quality()
					1: main.toggle_retro()
					2: main.toggle_lights()
					3: main.toggle_night_vision()
					4: main.toggle_thermal()
			7: sq.anchor = Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45))
			8: sq.join_teams() if sq.split else sq.split_teams()
			9: sq.switch_team()
			10: sq.start_bound(Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-45, 45)))
			11: sq.set_holding(not sq.holding)
			12:
				if held == "":
					held = ["move_forward", "move_back", "move_left", "move_right"][rng.randi_range(0, 3)]
					Input.action_press(held)
					release_f = f + rng.randi_range(30, 300)
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
