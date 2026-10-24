extends SceneTree
## Vision modes for visual review (not part of the suite): weapon lights,
## night vision, thermal inside the reticle, both together. The squad is
## placed facing the ROADBLOCK (MAP=0, night, default), ALPHA (MAP=1, day) or the
## bridge (MAP=3, day). GFX=high|low forces the graphics setting.
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 960x540 -s tests/tools/capture_vision.gd -- <out_dir>
## Writes vision_<mode>.png.
var main
var out := "user://vision"
var i := 0
## [physics frame, action, shot name]
const PLAN := [[20, "place", ""], [90, "", "lights"], [92, "lights", ""], [110, "", "nolights"], [112, "lights", ""], [100, "nvg", ""], [140, "", "nvg"],
		[150, "nvg ir", ""], [190, "", "thermal"], [200, "nvg", ""], [240, "", "nvg_thermal"]]

func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var mp := OS.get_environment("MAP")
	load("res://scripts/main.gd").forced_map = int(mp) if mp != "" else 0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d) -> bool:
	if i >= PLAN.size():
		quit()
		return false
	var e: Array = PLAN[i]
	if Engine.get_physics_frames() < e[0]:
		return false
	i += 1
	for a in String(e[1]).split(" ", false):
		match a:
			"place":
				if main.retro != (OS.get_environment("RETRO") == "1"):
					main.toggle_retro()
				var gfx := OS.get_environment("GFX")
				if gfx != "" and main.low_quality != (gfx == "low"):
					main.toggle_quality()
				var at: Vector3 = {0: Vector3(0, 0, 26), 1: Vector3(-24, 0, 12), 3: Vector3(0, 0, 30)}.get(main.map_index, Vector3(0, 0, 26))
				var look: Vector3 = {0: Vector3(0, 0, 2), 1: Vector3(-24, 0, -18), 3: Vector3(0, 0, -20)}.get(main.map_index, Vector3.ZERO)
				main.squad.anchor = at
				for s in main.squad.soldiers:
					s.global_position = at + s.slot_offset
				main.cam_rig.yaw = atan2(-(look.x - at.x), -(look.z - at.z))
				main.cam_rig.dist = 5.0
				main.squad.set_holding(true)      # stand still, so frames compare
				main.reticle.p["width"] = 420.0
				main.reticle.p["height"] = 240.0
			"nvg": main.toggle_night_vision()
			"ir": main.toggle_thermal()
			"lights": main.toggle_lights()
	if e[2] != "":
		root.get_viewport().get_texture().get_image().save_png(out.path_join("vision_%s.png" % e[2]))
		print("shot ", e[2])
	return false
