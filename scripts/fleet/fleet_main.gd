extends Node3D
## ARMORED FLEET (prototype): a separate game mode. You command a fleet of
## five armored vehicles over a big hilly countryside; in the middle stands a
## big box to shoot at.
##   WASD           move the fleet (it keeps a wedge, turned the way it's going)
##   SHIFT (hold)   faster
##   MOUSE          aim (every turret tracks the reticle); WHEEL zoom
##   LMB (hold)     coaxial machine guns
##   RMB            main guns (each vehicle fires when loaded and on target)
##   R              reset   BACKSPACE level select   ESC let go of the mouse
##
## Everything is analytic (no physics): the ground is a height function, the
## mesh is built from it, and shots march along their line against the
## ground and the box.

const VehicleScript = preload("res://scripts/fleet/fleet_vehicle.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")

const HALF := 420.0             # the countryside is 840 m across
const CELL := 4.0               # terrain grid (m)
const HILLS := 26.0             # tallest hills (m) above the lowest dips
const FLAT_R := 70.0            # flattened around the target...
const START := Vector3(0, 0, 250)
const TARGET_SIZE := Vector3(26, 16, 26)
const TARGET_HP := 4000.0
const MAIN_DMG := 90.0          # a main gun hit on the box
const MAIN_SPLASH := 8.0        # ... and blast radius on the ground
const MG_DMG := 1.5             # a machine gun round on the box
const SHELL_SPEED := 320.0      # m/s, straight line (prototype: no drop)
const SPEED := 11.0             # fleet speed (m/s); SHIFT x1.6
const N_VEHICLES := 5
const SLOTS := [Vector3(0, 0, -14), Vector3(-12, 0, -2), Vector3(12, 0, -2), Vector3(-24, 0, 10), Vector3(24, 0, 10)]   # wedge
const NEON := Color(0.45, 1.0, 0.30)
const C_OK := "#73ff4d"
const C_WARN := "#ffbf33"
const C_BAD := "#ff4d33"
const C_DIM := "#3f6b35"

var vehicles: Array = []
var anchor := START             # the fleet's point (WASD moves it)
var heading := 0.0              # the formation's facing (yaw)
var target_hp := TARGET_HP
var target_dead := false
var hits_main := 0
var hits_mg := 0
var aim := Vector3.ZERO         # where the reticle is on the ground / box
var mg_firing := false

var cam_yaw := 0.0
var cam_pitch := -0.28
var cam_dist := 34.0
var cam: Camera3D

var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _target: MeshInstance3D
var _target_mat: StandardMaterial3D
var _flash_t := 0.0
var _shells: Array = []         # [{pos, dir, from (vehicle), life}]
var _fx: Array = []             # [{node, t, life, kind}]
var _hud: RichTextLabel
var _units: RichTextLabel
var _banner: Label
var _game_t := 0.0
var _prev_anchor := START
var forced_input := {}          # tests: {"mg": bool, "main": bool, "move": Vector2, "aim": Vector3}


func _ready() -> void:
	# WASD (the infantry game registers these itself; this scene can be first).
	for pair in [["move_forward", [KEY_W, KEY_UP]], ["move_back", [KEY_S, KEY_DOWN]], ["move_left", [KEY_A, KEY_LEFT]], ["move_right", [KEY_D, KEY_RIGHT]]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			for k in pair[1]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(pair[0], ev)
	_noise.seed = 1307
	_noise.frequency = 0.0042
	_noise.fractal_octaves = 4
	_noise2.seed = 77
	_noise2.frequency = 0.02
	_environment()
	_terrain()
	_build_target()
	for i in N_VEHICLES:
		var v: Node3D = VehicleScript.new()
		v.fleet = self
		v.index = i
		v.slot = SLOTS[i]
		add_child(v)
		v.build([Color(0.33, 0.37, 0.26), Color(0.31, 0.35, 0.25), Color(0.35, 0.37, 0.27)][i % 3])
		var p: Vector3 = START + SLOTS[i]
		p.y = height(p.x, p.z)
		v.global_position = p
		vehicles.append(v)
	cam = Camera3D.new()
	cam.far = 1600.0
	cam.fov = 70.0
	add_child(cam)
	cam.current = true
	_hud_build()
	if not DisplayServer.get_name() == "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- ground

## Ground height at (x, z): rolling hills, flattened around the target box
## and at the start, rising a little toward the map edge.
func height(x: float, z: float) -> float:
	var h := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * HILLS + _noise2.get_noise_2d(x, z) * 1.2
	var d := Vector2(x, z).length()
	var flat := smoothstep(FLAT_R, FLAT_R + 60.0, d)        # 0 near the target
	var ds := Vector2(x - START.x, z - START.z).length()
	flat *= smoothstep(30.0, 80.0, ds) * 0.6 + 0.4
	var base := (_noise.get_noise_2d(0, 0) * 0.5 + 0.5) * HILLS
	return lerpf(base, h, flat) + smoothstep(HALF - 80.0, HALF, maxf(absf(x), absf(z))) * 30.0


func normal(x: float, z: float) -> Vector3:
	var e := 2.5
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func _terrain() -> void:
	var n := int(HALF * 2.0 / CELL) + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	cols.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var h := height(x, z)
			verts[j * n + i] = Vector3(x, h, z)
			var nn := normal(x, z)
			norms[j * n + i] = nn
			var grass := Color(0.27, 0.37, 0.17).lerp(Color(0.4, 0.45, 0.24), clampf(h / HILLS, 0.0, 1.0))
			grass = grass.lerp(Color(0.38, 0.33, 0.22), clampf((1.0 - nn.y) * 6.0, 0.0, 0.6))      # steep: bare earth
			grass = grass.darkened(0.08 * (_noise2.get_noise_2d(x * 3.0, z * 3.0) + 1.0))
			cols[j * n + i] = grass
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	mi.material_override = m
	mi.name = "Terrain"
	add_child(mi)


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.55, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.82)
	sm.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# (the infantry operations' daylight: ACES, gentle ambient; thinner haze
	# for the long views out here)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_hdr_threshold = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.75, 0.84)
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 0.55, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)


# ---------------------------------------------------------------- target

func _build_target() -> void:
	_target = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = TARGET_SIZE
	_target.mesh = bm
	_target_mat = StandardMaterial3D.new()
	_target_mat.albedo_color = Color(0.52, 0.5, 0.46)
	_target.material_override = _target_mat
	_target.position = Vector3(0, height(0, 0) + TARGET_SIZE.y / 2.0 - 0.5, 0)
	_target.name = "Target"
	add_child(_target)


func target_box() -> AABB:
	var size := TARGET_SIZE * _target.scale         # (flattened when destroyed)
	return AABB(_target.position - size / 2.0, size)


## Pushes a ground point out of the target's footprint (plus `margin`).
func keep_out_of_target(p: Vector3, margin: float) -> Vector3:
	var hx := TARGET_SIZE.x / 2.0 + margin
	var hz := TARGET_SIZE.z / 2.0 + margin
	if target_dead or absf(p.x) >= hx or absf(p.z) >= hz:
		return p
	if hx - absf(p.x) < hz - absf(p.z):
		p.x = hx * signf(p.x if p.x != 0.0 else 1.0)
	else:
		p.z = hz * signf(p.z if p.z != 0.0 else 1.0)
	return p


func damage_target(dmg: float) -> void:
	if target_dead:
		return
	target_hp = maxf(0.0, target_hp - dmg)
	_flash_t = 0.12
	if target_hp <= 0.0:
		target_dead = true
		_target_mat.albedo_color = Color(0.12, 0.11, 0.1)
		_target.scale = Vector3(1.0, 0.35, 1.0)
		_target.position.y = height(0, 0) + TARGET_SIZE.y * 0.35 / 2.0 - 0.5
		for i in 6:
			_explosion(_target.position + Vector3(randf_range(-10, 10), randf_range(0, 6), randf_range(-10, 10)), 9.0)
		_banner.text = "TARGET DESTROYED  -  R TO RESET"
		_banner.visible = true


# ---------------------------------------------------------------- shots

## Where the line from `from` along `dir` first meets the ground or the box
## (within `max_d`): {pos, box: bool} or {} if nothing.
func trace(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var box_t := INF
	var hit: Variant = target_box().intersects_ray(from, dir)
	if hit != null:
		box_t = from.distance_to(hit)
	var step := 2.0
	var t := 0.0
	while t < minf(max_d, box_t):
		var p := from + dir * t
		if p.y < height(p.x, p.z):
			# refine between t - step and t
			var lo := maxf(0.0, t - step)
			var hi := t
			for k in 6:
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				if q.y < height(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return {"pos": from + dir * hi, "box": false}
		t += step
	if box_t < max_d:
		return {"pos": from + dir * box_t, "box": true}
	return {}


func _fire_mg(v: Node3D) -> void:
	var from: Vector3 = v.mg_muzzle.global_position
	var dir: Vector3 = (aim - from).normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.006).normalized()
	var hit := trace(from, dir, 900.0)
	var end: Vector3 = hit["pos"] if not hit.is_empty() else from + dir * 900.0
	if not hit.is_empty():
		if hit["box"]:
			damage_target(MG_DMG)
			hits_mg += 1
		_puff(end, 0.6 if hit["box"] else 0.9, Color(0.9, 0.85, 0.6) if hit["box"] else Color(0.55, 0.48, 0.36))
	v.shots_mg += 1
	if v.shots_mg % 3 == 0:
		_tracer(from, end, Color(1.0, 0.75, 0.3), 0.06)
	_muzzle(v.mg_muzzle.global_position, 0.25)


func _fire_main(v: Node3D) -> void:
	v.reload = v.MAIN_RELOAD
	v.shots_main += 1
	var from: Vector3 = v.muzzle.global_position
	_shells.append({"pos": from, "dir": v.gun_dir(), "life": 3.0})
	_muzzle(from, 1.1)
	_puff(from + v.gun_dir() * 1.5, 2.2, Color(0.75, 0.72, 0.68))


func _shells_tick(delta: float) -> void:
	for s in _shells.duplicate():
		var step: float = SHELL_SPEED * delta
		var hit := trace(s["pos"], s["dir"], step)
		if not hit.is_empty():
			_shells.erase(s)
			if hit["box"]:
				damage_target(MAIN_DMG)
				hits_main += 1
			elif (hit["pos"] as Vector3).distance_to(_target.position) < TARGET_SIZE.x * 0.7 + MAIN_SPLASH:
				damage_target(MAIN_DMG * 0.25)          # a near miss at its foot still shakes it
			_explosion(hit["pos"], 5.0)
			continue
		var p0: Vector3 = s["pos"]
		s["pos"] = p0 + s["dir"] * step
		s["life"] -= delta
		_tracer(p0, s["pos"], Color(1.0, 0.9, 0.6), 0.05, 0.22)
		if s["life"] <= 0.0:
			_shells.erase(s)


# ---------------------------------------------------------------- effects

func _fx_mesh(mesh: Mesh, col: Color, at: Vector3, life: float, kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	_fx.append({"node": mi, "t": 0.0, "life": life, "kind": kind, "col": col})
	return mi


func _tracer(a: Vector3, b: Vector3, col: Color, life: float, w := 0.12) -> void:
	var len := a.distance_to(b)
	if len < 0.1:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(w, w, len)
	var mi := _fx_mesh(bm, col, (a + b) * 0.5, life, "fade")
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)


func _muzzle(at: Vector3, size: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	_fx_mesh(sm, Color(1.0, 0.8, 0.4, 0.9), at, 0.06, "fade")


func _puff(at: Vector3, size: float, col: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius = size * 0.5
	sm.height = size
	_fx_mesh(sm, Color(col.r, col.g, col.b, 0.7), at, 0.5, "grow")


func _explosion(at: Vector3, size: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = size * 0.5
	sm.height = size
	_fx_mesh(sm, Color(1.0, 0.6, 0.2, 0.95), at, 0.35, "grow")
	var sm2 := SphereMesh.new()
	sm2.radius = size * 0.6
	sm2.height = size * 1.2
	_fx_mesh(sm2, Color(0.3, 0.28, 0.25, 0.75), at + Vector3(0, size * 0.3, 0), 1.6, "grow")


func _fx_tick(delta: float) -> void:
	for e in _fx.duplicate():
		e["t"] += delta
		var k: float = e["t"] / e["life"]
		var mi: MeshInstance3D = e["node"]
		if k >= 1.0:
			mi.queue_free()
			_fx.erase(e)
			continue
		var c: Color = e["col"]
		(mi.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, c.a * (1.0 - k))
		if e["kind"] == "grow":
			mi.scale = Vector3.ONE * (1.0 + 1.8 * k)


# ---------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	_game_t += delta
	# Fleet movement: WASD relative to the camera.
	var inp: Vector2 = forced_input.get("move", Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
	var speed := SPEED * (1.6 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	var move := Basis(Vector3.UP, cam_yaw) * Vector3(inp.x, 0, inp.y)
	if move.length() > 1.0:
		move = move.normalized()
	# Don't run off from the vehicles: the point waits for the slowest.
	var lag := 0.0
	for v in vehicles:
		lag = maxf(lag, v.global_position.distance_to(_slot_world(v)))
	var lag_k := clampf(1.0 - (lag - 8.0) / 20.0, 0.25, 1.0)
	anchor += move * speed * lag_k * delta
	anchor.x = clampf(anchor.x, -HALF + 40.0, HALF - 40.0)
	anchor.z = clampf(anchor.z, -HALF + 40.0, HALF - 40.0)
	anchor = keep_out_of_target(anchor, 26.0)
	anchor.y = height(anchor.x, anchor.z)
	var mv := anchor - _prev_anchor
	mv.y = 0.0
	if mv.length() / maxf(delta, 0.001) > 1.0:
		heading += clampf(wrapf(atan2(-mv.x, -mv.z) - heading, -PI, PI), -1.2 * delta, 1.2 * delta)
	_prev_anchor = anchor
	# Aim: where the camera's centre line meets the ground or the box.
	var cf := -cam.global_basis.z
	var hit := trace(cam.global_position, cf, 1500.0)
	aim = hit["pos"] if not hit.is_empty() else cam.global_position + cf * 1500.0
	if forced_input.has("aim"):
		aim = forced_input["aim"]
	for v in vehicles:
		v.drive(_slot_world(v), aim, delta)
	# Weapons.
	mg_firing = forced_input.get("mg", Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	var main_pressed: bool = forced_input.get("main", Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	for v in vehicles:
		var on: bool = v.aim_error(aim) < v.ON_TARGET
		if mg_firing and on and v.mg_t <= 0.0:
			v.mg_t = v.MG_RATE * randf_range(0.9, 1.15)
			_fire_mg(v)
		if main_pressed and on and v.reload <= 0.0:
			_fire_main(v)
	_shells_tick(delta)
	_fx_tick(delta)
	if _flash_t > 0.0:
		_flash_t -= delta
		_target_mat.emission_enabled = _flash_t > 0.0
		_target_mat.emission = Color(1.0, 0.7, 0.4)
		_target_mat.emission_energy_multiplier = 0.6


func _process(delta: float) -> void:
	# Camera: orbit the middle of the fleet, never inside a hill.
	var c := Vector3.ZERO
	for v in vehicles:
		c += v.global_position
	c /= float(vehicles.size())
	var focus := c + Vector3(0, 4.0, 0)
	var b := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var p := focus + b * Vector3(0, 0, cam_dist)
	p.y = maxf(p.y, height(p.x, p.z) + 2.5)
	cam.global_position = p
	cam.global_basis = b * Basis(Vector3.RIGHT, 0.12)       # looking a little above the fleet, at the field
	_hud_update()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * 0.003
		cam_pitch = clampf(cam_pitch - event.relative.y * 0.003, -1.2, 0.25)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(12.0, cam_dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(90.0, cam_dist * 1.1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_R:
				get_tree().reload_current_scene()
			KEY_BACKSPACE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				get_tree().change_scene_to_file("res://menu.tscn")


func _slot_world(v: Node3D) -> Vector3:
	var p: Vector3 = anchor + Basis(Vector3.UP, heading) * v.slot
	p = keep_out_of_target(p, 6.0)
	p.y = height(p.x, p.z)
	return p


# ---------------------------------------------------------------- HUD

func _panel(anchor_preset: int) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.05, 0.0, 0.55)
	sb.border_color = Color(NEON, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_and_offsets_preset(anchor_preset, Control.PRESET_MODE_MINSIZE, 12)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", UI_FONT)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", NEON)
	return r


func _hud_build() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var tl := _panel(Control.PRESET_TOP_LEFT)
	_hud = _rich(16)
	tl.add_child(_hud)
	ui.add_child(tl)
	var tr := _panel(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var help := _rich(14)
	help.text = "WASD move fleet   SHIFT faster   MOUSE aim   WHEEL zoom\nLMB machine guns   RMB main guns\nR reset   BACKSPACE level select   ESC free mouse"
	tr.add_child(help)
	ui.add_child(tr)
	var br := _panel(Control.PRESET_BOTTOM_RIGHT)
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_units = _rich(15)
	br.add_child(_units)
	ui.add_child(br)
	# Reticle.
	var ret := Control.new()
	ret.set_anchors_preset(Control.PRESET_CENTER)
	ret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ret.draw.connect(func() -> void:
		var c := Color(NEON, 0.9)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			ret.draw_line(d * 7.0, d * 20.0, c, 2.0)
		ret.draw_arc(Vector2.ZERO, 30.0, 0, TAU, 40, Color(NEON, 0.35), 1.0))
	ui.add_child(ret)
	_banner = Label.new()
	_banner.add_theme_font_override("font", UI_FONT)
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.add_theme_color_override("font_color", NEON)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 150
	_banner.visible = false
	ui.add_child(_banner)


func _bar(k: float, n := 12) -> String:
	var full := int(round(clampf(k, 0.0, 1.0) * n))
	return "#".repeat(full) + "-".repeat(n - full)


func _hud_update() -> void:
	var loaded := 0
	for v in vehicles:
		if v.reload <= 0.0:
			loaded += 1
	var hp_k := target_hp / TARGET_HP
	var hp_col := C_OK if hp_k > 0.5 else (C_WARN if hp_k > 0.2 else C_BAD)
	var spd := 0.0
	for v in vehicles:
		spd += v.vel.length()
	spd /= float(vehicles.size())
	_hud.text = "ARMORED FLEET   [color=%s](PROTOTYPE)[/color]%s\n" % [C_DIM, "" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "   (CLICK TO AIM)"] \
		+ "FLEET      %d VEHICLES   %3.0f km/h\n" % [vehicles.size(), spd * 3.6] \
		+ "MG         %s\n" % ("[color=%s]FIRING[/color]" % C_WARN if mg_firing else "READY") \
		+ "MAIN GUNS  %d / %d LOADED\n" % [loaded, vehicles.size()] \
		+ "TARGET     [color=%s][%s] %d%%[/color]   %.0f m\n" % [hp_col, _bar(hp_k), int(ceil(hp_k * 100.0)), Vector2(anchor.x, anchor.z).length()] \
		+ "HITS       MAIN %d   MG %d" % [hits_main, hits_mg]
	var lines: Array = ["FLEET  %d / %d" % [vehicles.size(), N_VEHICLES]]
	for v in vehicles:
		var r: String = ("[color=%s]LOADED[/color]" % C_OK) if v.reload <= 0.0 else ("[color=%s]%s[/color]" % [C_WARN, _bar(1.0 - v.reload / v.MAIN_RELOAD, 8)])
		lines.append("V%d  %s  %s" % [v.index + 1, ["LEAD", "LEFT", "RIGHT", "L WING", "R WING"][v.index], r])
	_units.text = "\n".join(lines)
