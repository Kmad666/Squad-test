extends SceneTree
## Screenshots of the real game for visual review (not part of the suite):
## TEST FIELD, the squad ordered forward, frames captured mid-move.
##   xvfb-run -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 960x540 -s tests/tools/capture_game.gd -- <out_dir>
var main
var frame := 0
var out := "user://capture"

func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").forced_map = 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d) -> bool:
	frame += 1
	if frame == 20:
		main.cam_rig.dist = 4.0
	if frame == 30:
		main.squad.move_to(main.squad.soldiers[0].global_position + Vector3(0, 0, -25))
	if frame in [44, 47, 50, 53, 56, 59]:
		root.get_viewport().get_texture().get_image().save_png(out.path_join("f%03d.png" % frame))
		print(frame, " paused=", paused, " sgt at ", main.squad.soldiers[0].global_position)
	if frame == 60:
		quit()
	return false
