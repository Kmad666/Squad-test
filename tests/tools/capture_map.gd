extends SceneTree
## Still shots of a map from fixed cameras (not part of the test suite).
##   MAP=5 xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility --resolution 1280x720 -s tests/tools/capture_map.gd -- <out_dir>
## Shots: an overhead of the whole map, then eye-level views (edit SHOTS).

const SHOTS := {
	5: [["overhead", Vector3(0, 230, 1), Vector3(0, 0, 0)], ["crossing_from_south", Vector3(0, 9, 62), Vector3(0, 2, 0)],
		["tram_street_east", Vector3(-6, 6, 4), Vector3(60, 2, -2)], ["gateway", Vector3(-3, 2.2, 52), Vector3(24, 2.5, 57.5)],
		["se_yard", Vector3(27, 12, 30), Vector3(50, 0, 50)], ["vacant_lot", Vector3(-40, 7, -6), Vector3(-58, 1, 20)],
		["north_strongpoint", Vector3(0, 7, -18), Vector3(0, 1, -60)]],
}

var main
var out := "user://shots"
var cam: Camera3D
var i := 0
var wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var map := int(OS.get_environment("MAP")) if OS.has_environment("MAP") else 5
	load("res://scripts/main.gd").forced_map = map
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	if main.cam_rig == null:
		return false
	if cam == null:
		cam = Camera3D.new()
		cam.far = 600.0
		cam.fov = 60.0
		main.add_child(cam)
		cam.current = true
		main.ui_root.visible = false
	var shots: Array = SHOTS[main.map_index]
	if i >= shots.size():
		quit()
		return false
	if wait == 0:
		cam.global_position = shots[i][1]
		cam.look_at(shots[i][2], Vector3.FORWARD if shots[i][0] == "overhead" else Vector3.UP)
		cam.fov = 50.0 if shots[i][0] == "overhead" else 60.0
	wait += 1
	if wait > 6:
		root.get_viewport().get_texture().get_image().save_png(out.path_join("%s.png" % shots[i][0]))
		i += 1
		wait = 0
	return false
