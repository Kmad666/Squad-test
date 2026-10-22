extends SceneTree
## T-pose turnaround of the soldier for design review (not part of the suite):
## arms straight out, legs straight, rifle hidden; front / 3-4 / side / back,
## HD and RETRO, with a measured height grid behind.
##   xvfb-run -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 600x900 -s tests/tools/render_tpose.gd -- <out_dir> [role] [side]
## Writes tpose_<look>_<view>.png.

const SoldierModel = preload("res://scripts/soldier_model.gd")

const VIEWS := [["front", Vector3(0, 0, -1)], ["34", Vector3(-0.7, 0, -0.7)], ["side", Vector3(-1, 0, 0)], ["back", Vector3(0, 0, 1)]]


func _initialize() -> void:
	_run.call_deferred()


func _tpose(m: Node3D) -> void:
	# arms straight out from the shoulders, palms down; rifle away
	m._rifle.visible = false
	m._left_target = SoldierModel.SHOULDER * Vector3(-1, 1, 1) + Vector3(-0.585, 0, 0)
	m._grip = SoldierModel.SHOULDER + Vector3(0.585, 0, 0)
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var sh: Vector3 = SoldierModel.SHOULDER * Vector3(sx, 1, 1)
		var hand: Vector3 = sh + Vector3(0.585 * sx, 0, 0)
		var elbow: Vector3 = sh + Vector3(SoldierModel.UPPER_ARM * sx, 0, 0)
		SoldierModel._aim_bone(m._arms[s]["upper"], sh, elbow, Vector3(0, 0, -sx))
		SoldierModel._aim_bone(m._arms[s]["fore"], elbow, hand, Vector3(0, 0, -sx))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://tpose"
	var role: String = args[1] if args.size() > 1 else "rifleman"
	var side: String = args[2] if args.size() > 2 else "friendly"
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.78, 0.78, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment.ambient_light_energy = 0.75
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.7, 0.5, 0)
	key.light_energy = 1.0
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.6, 0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.2
	world.add_child(cam)
	cam.current = true
	for look in ["hd", "retro"]:
		SoldierModel.retro = look == "retro"
		var m: Node3D = SoldierModel.new()
		world.add_child(m)
		m.build(role, side, 0)
		_tpose(m)
		for v in VIEWS:
			var d: Vector3 = v[1]
			cam.position = Vector3(0, 0.98, 0) + d * 5.0
			cam.look_at(Vector3(0, 0.98, 0))
			for i in 4:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png(out.path_join("tpose_%s_%s.png" % [look, v[0]]))
		m.queue_free()
		await process_frame
	print("t-pose renders done")
	quit()
