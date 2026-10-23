extends SceneTree
## Turnaround of the static PS2-era soldier (scripts/models/ps2_soldier.gd)
## for design review (not part of the suite): eight views plus close-ups.
##   xvfb-run -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 700x900 -s tests/tools/render_static.gd -- <out_dir>

const PS2Soldier = preload("res://scripts/models/ps2_soldier.gd")

const SHOTS := [
	["front", Vector3(0, 0.05, -1), 0.95, 2.9], ["34", Vector3(-0.7, 0.08, -0.7), 0.95, 2.9],
	["side", Vector3(-1, 0.05, 0), 0.95, 2.9], ["back34", Vector3(0.7, 0.1, 0.7), 0.95, 2.9],
	["back", Vector3(0, 0.08, 1), 0.95, 2.9], ["right", Vector3(1, 0.05, -0.15), 0.95, 2.9],
	["head", Vector3(-0.35, 0.05, -1), 1.68, 0.75], ["chest", Vector3(-0.3, 0.1, -1), 1.2, 1.3],
	["legs", Vector3(-0.6, 0.15, -0.8), 0.45, 1.5], ["rifle", Vector3(0.2, 0.4, -1), 1.1, 1.0],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://ps2"
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.74, 0.75, 0.76)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.68, 0.7, 0.74)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.75, 0.55, 0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.5, 0)
	fill.light_energy = 0.45
	world.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.6, 0.6, 0.6)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	var mi := PS2Soldier.build()
	world.add_child(mi)
	print("triangles: ", PS2Soldier.triangles)
	var cam := Camera3D.new()
	cam.fov = 35
	world.add_child(cam)
	cam.current = true
	for s in SHOTS:
		var look := Vector3(0, s[2], 0)
		cam.position = look + (s[1] as Vector3).normalized() * s[3]
		cam.look_at(look)
		for i in 4:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out.path_join("ps2_%s.png" % s[0]))
	quit()
