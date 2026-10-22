extends SceneTree
## Screenshots of the real game for visual review (not part of the suite).
##   xvfb-run -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 960x540 -s tests/tools/capture_game.gd -- <out_dir> [run|fight]
## run:   TEST FIELD, the squad ordered forward, frames mid-move.
## fight: TEST FIELD, the squad advances on ALPHA at fire-at-will, frames of
##        the firefight (shouldered rifles, recoil).
var main
var frame := 0
var out := "user://capture"
var mode := "run"
var shots: Array = [44, 47, 50, 53, 56, 59]

func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		mode = args[1]
	if mode == "fight":
		shots = [70, 76, 82, 88, 94, 100]
	elif mode == "idle":
		shots = [40]
	DirAccess.make_dir_recursive_absolute(out)
	var mp := OS.get_environment("MAP")
	load("res://scripts/main.gd").forced_map = int(mp) if mp != "" else 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d) -> bool:
	frame += 1
	if frame == 20:
		main.cam_rig.dist = 4.0 if mode == "run" else 5.0
		if mode == "idle":
			main.cam_rig.dist = 3.2
			main.cam_rig.yaw = PI * 0.85
	if frame == 30 and mode != "idle":
		main.squad.forced_mode = 1
		if mode == "fight" and OS.get_environment("MAP") == "0":
			main.squad.move_to(Vector3(-3, 0, 18))       # up the street toward the roadblock
		elif mode == "fight":
			main.squad.move_to(Vector3(-12, 0, 8))
		else:
			main.squad.move_to(main.squad.soldiers[0].global_position + Vector3(0, 0, -25))
	if frame in shots:
		root.get_viewport().get_texture().get_image().save_png(out.path_join("f%03d.png" % frame))
		var up := 0
		for s in main.squad.soldiers:
			if s._model.is_shouldered():
				up += 1
		print(frame, " shouldered ", up, "/", main.squad.soldiers.size(), " sgt at ", main.squad.soldiers[0].global_position.snapped(Vector3.ONE * 0.1))
	if frame == shots[-1] + 1:
		quit()
	return false
