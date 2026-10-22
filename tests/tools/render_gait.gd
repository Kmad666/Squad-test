extends SceneTree
## Gait strips for visual review (not part of the test suite): each gait at
## six points of its cycle. Usage as render_models.gd:
##   xvfb-run -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 480x480 -s tests/tools/render_gait.gd -- <out_dir> [cam: side|front|34]
## Writes <gait>_<k>.png.

const SoldierModel = preload("res://scripts/soldier_model.gd")

## [name, role, model-space velocity, crouched]
const GAITS := [
	["walk", "rifleman", Vector3(0, 0, -1.6), false],
	["jog", "rifleman", Vector3(0, 0, -4.2), false],
	["run", "rifleman", Vector3(0, 0, -6.3), false],
	["sprint", "anti_armor", Vector3(0, 0, -7.0), false],
	["crouchwalk", "rifleman", Vector3(0, 0, -2.5), true],
	["strafe", "rifleman", Vector3(3.5, 0, 0), false],
	["backpedal", "rifleman", Vector3(0, 0, 2.2), false],
]
const FRAMES := 6


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://gait"
	var cam_mode: String = args[1] if args.size() > 1 else "side"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred(out, cam_mode)


func _run(out: String, cam_mode: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.65)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.42, 0.3)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.current = true
	var dir := Vector3(1, 0.0, 0)
	if cam_mode == "front":
		dir = Vector3(0, 0, -1)
	elif cam_mode == "34":
		dir = Vector3(0.8, 0, -0.6)
	cam.position = Vector3(0, 0.95, 0) + dir.normalized() * 3.2
	cam.look_at(Vector3(0, 0.85, 0))

	for g in GAITS:
		var m: Node3D = SoldierModel.new()
		world.add_child(m)
		m.build(g[1], "friendly", 0)
		if g[3]:
			m.set_crouch(true)
		for i in 120:                     # warm up: ease into the gait
			m.animate_local(g[2], 1.0 / 60.0)
		for k in FRAMES:
			m._phase = float(k) / FRAMES
			m._apply_pose()
			m._solve_arms()
			for i in 3:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png(out.path_join("%s_%d.png" % [g[0], k]))
		m.queue_free()
		await process_frame
	print("gait strips: ", GAITS.size(), " x ", FRAMES)
	quit()
