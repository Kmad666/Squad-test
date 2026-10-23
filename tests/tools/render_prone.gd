extends SceneTree
## Prone pose and crawl review shots (not part of the test suite).
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 640x400 -s tests/tools/render_prone.gd -- <out_dir> [hd|retro]
## Writes prone_<view>.png (lying still, rifle up), crawl_<k>.png (side, eight
## points of the crawl cycle) and drop_<k>.png (going down, standing to flat).

const SoldierModel = preload("res://scripts/soldier_model.gd")

const VIEWS := [["side", Vector3(1, 0.25, 0)], ["front", Vector3(0, 0.3, -1)], ["34", Vector3(0.8, 0.6, -0.7)],
		["top", Vector3(0.01, 1, 0.0)], ["back", Vector3(-0.3, 0.5, 1)]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://prone"
	SoldierModel.retro = args.size() > 1 and args[1] == "retro"
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred(out)


func _shot(out: String, name: String) -> void:
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _run(out: String) -> void:
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

	# The soldier node stands in for soldier.gd: the model is its child.
	var body := Node3D.new()
	world.add_child(body)
	var m: Node3D = SoldierModel.new()
	body.add_child(m)
	m.build("rifleman", "friendly", 0)
	var look := Vector3(0, 0.3, -0.1)

	# Going down, from standing.
	cam.position = look + Vector3(1, 0.35, 0).normalized() * 3.4
	cam.look_at(look + Vector3(0, 0.3, 0))
	m.animate_local(Vector3.ZERO, 1.0 / 60.0)
	m.set_prone(true)
	for k in 6:
		_shot_pending = true
		await _shot(out, "drop_%d" % k)
		for i in 6:
			m.animate_local(Vector3.ZERO, 1.0 / 60.0)
	for i in 60:
		m.animate_local(Vector3.ZERO, 1.0 / 60.0)

	for v in VIEWS:
		cam.position = look + (v[1] as Vector3).normalized() * 3.0
		cam.look_at(look, Vector3.FORWARD if v[0] == "top" else Vector3.UP)
		await _shot(out, "prone_" + v[0])

	# Crawl cycle, side on.
	for i in 120:
		m.animate_local(Vector3(0, 0, -0.85), 1.0 / 60.0)
	for v in [["side", Vector3(1, 0.3, 0)], ["top", Vector3(0.01, 1, 0)]]:
		cam.position = look + (v[1] as Vector3).normalized() * 3.0
		cam.look_at(look, Vector3.FORWARD if v[0] == "top" else Vector3.UP)
		for k in 8:
			m._phase = float(k) / 8.0
			m._apply_pose()
			m._solve_arms()
			await _shot(out, "crawl_%s_%d" % [v[0], k])
	print("prone renders done")
	quit()


var _shot_pending := false
