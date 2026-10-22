extends SceneTree
## Close-up renders of the soldier model for visual review (not part of the
## test suite). Needs a real renderer, e.g.:
##   xvfb-run -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
##     --resolution 640x640 -s tests/tools/render_models.gd -- <out_dir>
## Writes one PNG per shot into out_dir.

const SoldierModel = preload("res://scripts/soldier_model.gd")

## [name, role, side, sergeant, crouched, gesture, yaw (model), cam_dir, cam_height, dist, look_y]
var SHOTS := [
	["head_front", "rifleman", "friendly", false, false, "", 0.0, Vector3(0, 0, -1), 1.78, 0.75, 1.74],
	["head_34", "rifleman", "friendly", false, false, "", 0.0, Vector3(-0.7, 0, -0.7), 1.8, 0.75, 1.74],
	["head_side", "rifleman", "friendly", false, false, "", 0.0, Vector3(1, 0, 0), 1.76, 0.75, 1.74],
	["head_back", "rifleman", "friendly", true, false, "", 0.0, Vector3(0.4, 0, 1), 1.85, 0.8, 1.74],
	["chest_front", "rifleman", "friendly", false, false, "", 0.0, Vector3(-0.25, 0, -1), 1.35, 1.2, 1.25],
	["rifle_close", "rifleman", "friendly", false, false, "", 0.0, Vector3(0.4, 0.0, -1), 1.15, 0.9, 1.05],
	["enemy_head", "rifleman", "enemy", false, false, "", 0.0, Vector3(-0.6, 0, -0.8), 1.78, 0.8, 1.72],
	["legs_34", "rifleman", "friendly", false, false, "", 0.0, Vector3(-0.7, 0, -0.7), 0.6, 1.5, 0.45],
	["rifle_front", "rifleman", "friendly", false, false, "", 0.0, Vector3(0, 0, -1), 1.2, 2.6, 1.0],
	["rifle_34", "rifleman", "friendly", false, false, "", 0.0, Vector3(-0.7, 0, -0.7), 1.2, 2.6, 1.0],
	["rifle_side", "rifleman", "friendly", false, false, "", 0.0, Vector3(1, 0, 0), 1.1, 2.6, 1.0],
	["rifle_back", "rifleman", "friendly", false, false, "", 0.0, Vector3(0.3, 0, 1), 1.3, 2.6, 1.0],
	["rifle_top", "rifleman", "friendly", false, false, "", 0.0, Vector3(-0.2, 0, -0.4), 3.0, 1.6, 1.1],
	["crouch_side", "rifleman", "friendly", false, true, "", 0.0, Vector3(1, 0, 0), 0.9, 2.4, 0.7],
	["crouch_34", "rifleman", "friendly", false, true, "", 0.0, Vector3(-0.7, 0, -0.7), 1.0, 2.4, 0.7],
	["crouch_back", "rifleman", "friendly", false, true, "", 0.0, Vector3(-0.6, 0, 1), 1.1, 2.4, 0.7],
	["crouch_front", "rifleman", "friendly", false, true, "", 0.0, Vector3(0, 0, -1), 0.9, 2.4, 0.7],
	["gren_34", "grenadier", "friendly", false, false, "", 0.0, Vector3(0.7, 0, -0.7), 1.2, 2.4, 1.0],
	["at_34", "anti_armor", "friendly", false, false, "", 0.0, Vector3(-0.7, 0, -0.7), 1.4, 2.6, 1.2],
	["at_side", "anti_armor", "friendly", false, false, "", 0.0, Vector3(1, 0, 0), 1.4, 2.6, 1.2],
	["at_crouch", "anti_armor", "friendly", false, true, "", 0.0, Vector3(1, 0, -0.4), 1.0, 2.6, 0.8],
	["enemy_34", "rifleman", "enemy", false, false, "", 0.0, Vector3(-0.7, 0, -0.7), 1.2, 2.6, 1.0],
	["sgt_back", "rifleman", "friendly", true, false, "", 0.0, Vector3(-0.6, 0, 1), 1.6, 3.0, 1.3],
	["sig_halt", "rifleman", "friendly", true, false, "halt", 0.0, Vector3(-0.7, 0, -0.7), 1.4, 2.8, 1.2],
	["sig_move", "rifleman", "friendly", true, false, "move", 0.0, Vector3(1, 0, -0.3), 1.4, 2.8, 1.2],
	["sig_cover", "rifleman", "friendly", true, false, "cover", 0.0, Vector3(-0.7, 0, -0.7), 1.4, 2.8, 1.2],
	["sig_fire", "rifleman", "friendly", true, false, "fire", 0.0, Vector3(-0.3, 0, -1), 1.4, 2.8, 1.2],
	["sig_halt_crouch", "rifleman", "friendly", true, true, "halt", 0.0, Vector3(-0.7, 0, -0.7), 1.1, 2.8, 0.9],
	["aim_34", "rifleman", "friendly", false, false, "aim", 0.0, Vector3(-0.7, 0, -0.7), 1.5, 2.6, 1.3],
	["aim_side", "rifleman", "friendly", false, false, "aim", 0.0, Vector3(1, 0, 0), 1.4, 2.6, 1.2],
	["aim_front", "rifleman", "enemy", false, false, "aim", 0.0, Vector3(0.15, 0, -1), 1.5, 2.6, 1.3],
	["aim_back", "grenadier", "friendly", true, false, "aim", 0.0, Vector3(0.5, 0, 1), 1.7, 2.6, 1.3],
	["aim_crouch", "rifleman", "friendly", false, true, "aim", 0.0, Vector3(-0.8, 0, -0.5), 1.2, 2.4, 0.9],
	["aim_recoil", "rifleman", "friendly", false, false, "aim_recoil", 0.0, Vector3(1, 0, -0.2), 1.4, 2.6, 1.2],
	["aim_left", "anti_armor", "friendly", false, false, "aim_left", 0.0, Vector3(-0.5, 0, -1), 1.5, 2.6, 1.3],
	["aim_walk", "rifleman", "friendly", false, false, "aim_walk", 0.0, Vector3(1, 0, -0.4), 1.3, 2.6, 1.1],
	["dead_down", "rifleman", "friendly", false, false, "dead_down", 0.0, Vector3(1, 0, 0.3), 1.0, 3.0, 0.1],
	["dead_down_low", "grenadier", "friendly", false, true, "dead_down", 0.0, Vector3(1, 0, -0.5), 0.35, 3.2, 0.15],
	["dead_up", "rifleman", "enemy", false, false, "dead_up", 0.0, Vector3(1, 0, -0.3), 1.0, 3.0, 0.1],
	["dead_at", "anti_armor", "friendly", false, false, "dead_down", 0.0, Vector3(-1, 0, -0.4), 0.35, 3.2, 0.15],
]

## Where the left hand sits mid-gesture (sampled after this many seconds).
const GESTURE_T := {"halt": 0.4, "move": 0.12, "cover": 0.2, "fire": 0.4}


func _initialize() -> void:
	var out := "user://renders"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if OS.get_environment("RETRO") == "1":
		SoldierModel.retro = true          # render the RETRO soldiers
	_run.call_deferred(out)


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
	var fill := DirectionalLight3D.new()       # soft fill from the front-left
	fill.rotation = Vector3(-0.35, -2.4, 0)
	fill.light_energy = 0.45
	world.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.42, 0.3)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.current = true

	for s in SHOTS:
		var m: Node3D = SoldierModel.new()
		world.add_child(m)
		m.build(s[1], s[2], 0)
		m.rotation.y = s[6]
		if s[3]:
			m.set_sergeant(true)
		if s[4]:
			m.set_crouch(true)
		if s[5].begins_with("aim"):
			var tgt := Vector3(-8, 1.3, -14) if s[5] == "aim_left" else Vector3(0, 1.3, -20)
			var vel := Vector3(0, 0, -1.6) if s[5] == "aim_walk" else Vector3.ZERO
			for i in 60:
				m.set_aim_point(tgt)
				m.animate_local(vel, 1.0 / 60.0)
			if s[5] == "aim_recoil":
				m._recoil = 1.0
				m._apply_pose()
				m._solve_arms()
		elif s[5].begins_with("dead"):
			m.lay_down(s[5] == "dead_up")
			m.set_tint("dead")
		elif s[5] != "":
			m.gesture(s[5], 0.6)
		var look := Vector3(0, s[10], 0)
		if s[5] == "dead_down":
			look.z = -0.9                  # face down: head toward -Z
		elif s[5] == "dead_up":
			look.z = 0.9
		var d: Vector3 = (s[7] as Vector3).normalized()
		cam.position = look + d * s[9] + Vector3(0, s[8] - s[10], 0)
		cam.look_at(look)
		var wait: float = GESTURE_T.get(s[5], 0.0)
		if wait > 0.0:
			await create_timer(wait).timeout
		for i in 4:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out.path_join(s[0] + ".png"))
		m.queue_free()
		await process_frame
	print("rendered ", SHOTS.size(), " shots to ", out)
	quit()
