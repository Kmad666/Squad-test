extends Node3D
## Squad Test - builds the practice field (ground, cover boxes, target dummies),
## the squad, the camera, the HUD and a shared pool of bullet tracers.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SquadScript = preload("res://scripts/squad.gd")
const DummyScript = preload("res://scripts/dummy.gd")
const VehicleScript = preload("res://scripts/vehicle.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const ReticleScript = preload("res://scripts/reticle.gd")
const ReticlePanelScript = preload("res://scripts/reticle_panel.gd")
const AtmosphereScript = preload("res://scripts/atmosphere.gd")
const PostFxScript = preload("res://scripts/postfx.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")
const NEON := Color(0.45, 1.0, 0.30)

const NAV_HALF := 50.0          # playable half-size of the field (metres)
const VEHICLE_SPOT := Vector3(3, 0, -45)
const AT_TEAM_SPOT := Vector3(-26, 0, 14)   # anti-armor team waiting to link up
const TRACER_COUNT := 48
const TRACER_LIFE := 0.06
const TALL_COVER := 1.6         # boxes taller than this need a lean-out to shoot

## Cover boxes: [ground position, size, yaw]. Low crates (1.1 m) can be shot over,
## tall crates (2.4 m) are hard cover.
const BOX_LAYOUT := [
	[Vector3(-6, 0, 10), Vector3(3.0, 1.1, 1.0), 0.0],
	[Vector3(2, 0, 8), Vector3(2.5, 1.1, 1.0), 0.2],
	[Vector3(8, 0, 11), Vector3(1.6, 2.4, 1.6), 0.4],
	[Vector3(0, 0, 16), Vector3(1.2, 1.1, 1.2), 0.0],
	[Vector3(-2, 0, 2), Vector3(4.0, 1.1, 1.0), 0.0],
	[Vector3(-11, 0, 3), Vector3(1.6, 2.4, 1.6), 0.0],
	[Vector3(6, 0, 0), Vector3(3.0, 1.1, 1.0), -0.3],
	[Vector3(12, 0, -2), Vector3(1.0, 1.1, 3.0), 0.0],
	[Vector3(-7, 0, -5), Vector3(2.5, 1.1, 1.0), 0.5],
	[Vector3(0, 0, -8), Vector3(1.6, 2.4, 1.6), 0.8],
	[Vector3(4, 0, -12), Vector3(4.0, 1.1, 1.0), 0.0],
	[Vector3(-4, 0, -14), Vector3(2.0, 1.1, 1.0), -0.2],
	[Vector3(-14, 0, -10), Vector3(3.0, 1.1, 1.0), 0.3],
	[Vector3(14, 0, -14), Vector3(1.6, 2.4, 1.6), 0.2],
	[Vector3(-16, 0, 14), Vector3(3.0, 1.1, 1.0), 1.2],
	[Vector3(17, 0, 6), Vector3(2.5, 1.1, 1.0), -1.0],
]

const DUMMY_SPOTS := [
	Vector3(-10, 0, -30), Vector3(-3, 0, -34), Vector3(4, 0, -31),
	Vector3(11, 0, -36), Vector3(0, 0, -42), Vector3(-17, 0, -38),
]

var cover_defs: Array = []      # [{xform, size}] used by CoverUtil
var cover_points: Array = []    # [{pos, normal, height}]
var dummies: Array = []
var targets: Array = []         # everything the squad can shoot: dummies + vehicles
var vehicles: Array = []
var squad: Node3D
var cam_rig: Node3D
var nav_region: NavigationRegion3D
var hud_label: Label
var reticle: Control
var reticle_panel: PanelContainer
var hits := 0
var fire_heat := 0.0          # 0..1, how hard the squad is firing right now
var flash := 0.0              # 0..1, muzzle-flash wash on screen
var ui_root: Control
var atmosphere: Node3D
var postfx: CanvasLayer
var _muzzle_light: OmniLight3D
var _impacts: Array = []
var _impact_idx := 0
var _flicker_t := 0.0
var _explosions: Array = []
var _explosion_idx := 0
var _notice := ""
var _notice_t := 0.0
var hurt := 0.0               # red screen-edge flash when a soldier is hit
var _friendly_tracer_mat: StandardMaterial3D
var _enemy_tracer_mat: StandardMaterial3D
var kills := 0

var _tracers: Array = []
var _tracer_life: Array = []
var _tracer_idx := 0


func _ready() -> void:
	_setup_input()
	atmosphere = AtmosphereScript.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	_build_ground()
	_build_boxes()
	_bake_nav()
	_build_cover_points()
	_build_dummies()
	var v: StaticBody3D = VehicleScript.new()
	v.main = self
	add_child(v)
	v.global_position = VEHICLE_SPOT
	vehicles.append(v)
	targets.append(v)
	_build_tracers()
	_build_impacts()
	_build_explosions()
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.68, 0.32)
	_muzzle_light.omni_range = 9.0
	_muzzle_light.visible = false
	add_child(_muzzle_light)

	squad = SquadScript.new()
	squad.name = "Squad"
	add_child(squad)
	squad.setup(self, Vector3(0, 0, 30))   # just outside enemy rifle range
	squad.spawn_waiting_team("ANTI-ARMOR TEAM", AT_TEAM_SPOT, ["anti_armor", "anti_armor", "anti_armor"])

	cam_rig = CameraRigScript.new()
	cam_rig.name = "CameraRig"
	cam_rig.target = squad
	cam_rig.main = self
	add_child(cam_rig)
	atmosphere.cam_rig = cam_rig

	postfx = PostFxScript.new()
	add_child(postfx)

	_build_hud()


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("take_cover", [KEY_C, KEY_SPACE])
	_bind("auto_fire", [KEY_F])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- world

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	nav_region.add_child(body)

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	mesh.mesh = plane
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
// Rain-soaked field: dark wet grass and glossy puddles.
uniform vec3 grass_col : source_color = vec3(0.10, 0.17, 0.08);
uniform vec3 line_col : source_color = vec3(0.07, 0.12, 0.06);
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 g = abs(fract(wpos.xz / 4.0 - 0.5) - 0.5) * 4.0;
	float l = 1.0 - smoothstep(0.0, 0.06, min(g.x, g.y));
	float puddle = smoothstep(0.52, 0.62, noise(wpos.xz * 0.22) * 0.7 + noise(wpos.xz * 0.9) * 0.3);
	vec3 c = mix(grass_col, line_col, l * 0.6);
	c = mix(c, c * 0.35, puddle);
	bool outside = abs(wpos.x) > 50.0 || abs(wpos.z) > 50.0;
	ALBEDO = outside ? c * 0.7 : c;

	ROUGHNESS = mix(0.32, 0.03, puddle);
	SPECULAR = 0.65;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(240, 1, 240)
	col.shape = shape
	col.position.y = -0.5
	body.add_child(col)

	# Invisible walls keep everyone on the practice field.
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = Vector3(1, 6, NAV_HALF * 2 + 2) if side.x != 0 else Vector3(NAV_HALF * 2 + 2, 6, 1)
		wall.shape = ws
		wall.position = side * (NAV_HALF + 0.5) + Vector3(0, 3, 0)
		body.add_child(wall)


func _build_boxes() -> void:
	# Rain-soaked wood: dark and glossy.
	var low_mat := StandardMaterial3D.new()
	low_mat.albedo_color = Color(0.36, 0.27, 0.16)
	low_mat.roughness = 0.18
	low_mat.metallic_specular = 0.8
	var tall_mat := StandardMaterial3D.new()
	tall_mat.albedo_color = Color(0.26, 0.19, 0.12)
	tall_mat.roughness = 0.18
	tall_mat.metallic_specular = 0.8

	for entry in BOX_LAYOUT:
		var pos: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		var yaw: float = entry[2]
		var xform := Transform3D(Basis(Vector3.UP, yaw), pos)
		cover_defs.append({"xform": xform, "size": size})

		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.transform = Transform3D(xform.basis, pos + Vector3(0, size.y * 0.5, 0))
		nav_region.add_child(body)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = tall_mat if size.y > 2.0 else low_mat
		body.add_child(mi)

		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		body.add_child(col)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.filter_baking_aabb = AABB(Vector3(-NAV_HALF, -1, -NAV_HALF), Vector3(NAV_HALF * 2, 4, NAV_HALF * 2))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


## Spots around every box where a soldier can crouch. Each has an outward
## normal; a spot gives cover when its normal points away from the threat.
func _build_cover_points() -> void:
	for def in cover_defs:
		var xf: Transform3D = def["xform"]
		var size: Vector3 = def["size"]
		for face in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var along_x: bool = absf(face.x) > 0.0
			var half_n: float = size.x * 0.5 if along_x else size.z * 0.5
			var span: float = size.z if along_x else size.x
			var tangent: Vector3 = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
			var count: int = maxi(1, int(floor(span / 1.0)))
			for i in count:
				var t: float = (float(i) + 0.5) / float(count) - 0.5
				var local: Vector3 = face * (half_n + 0.6) + tangent * (t * span)
				# Tall crates can't be shot over, so give the spot two lean-out
				# positions just past each edge of the face (nearest edge first).
				var peeks: Array = []
				if size.y > TALL_COVER:
					var first: float = 1.0 if t >= 0.0 else -1.0
					for side in [first, -first]:
						var lp: Vector3 = face * (half_n + 0.6) + tangent * (side * (span * 0.5 + 0.45))
						peeks.append(CoverUtil.push_out(cover_defs, xf * lp, 0.5))
				cover_points.append({
					"pos": xf * local,
					"normal": (xf.basis * face).normalized(),
					"height": size.y,
					"peeks": peeks,
				})


func _build_dummies() -> void:
	for p in DUMMY_SPOTS:
		var d: StaticBody3D = DummyScript.new()
		d.main = self
		add_child(d)
		d.global_position = p
		dummies.append(d)
		targets.append(d)


func _build_tracers() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.4)
	mat.disable_fog = true
	_friendly_tracer_mat = mat
	_enemy_tracer_mat = mat.duplicate()
	_enemy_tracer_mat.albedo_color = Color(1.3, 0.25, 0.15)   # enemy rounds burn red
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.04, 1.0)
	for i in TRACER_COUNT:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append(mi)
		_tracer_life.append(0.0)


func spawn_tracer(from: Vector3, to: Vector3, hostile := false) -> void:
	var v := to - from
	var length := v.length()
	if length < 0.05:
		return
	var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT
	var t: MeshInstance3D = _tracers[_tracer_idx]
	t.material_override = _enemy_tracer_mat if hostile else _friendly_tracer_mat
	t.global_transform = Transform3D(Basis.looking_at(v, up), (from + to) * 0.5)
	t.scale = Vector3(1, 1, length)
	t.visible = true
	_tracer_life[_tracer_idx] = TRACER_LIFE
	_tracer_idx = (_tracer_idx + 1) % _tracers.size()


## Pool of one-shot spark/splash bursts for bullet impacts.
func _build_impacts() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	mesh.material = mat
	for i in 16:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 10
		p.lifetime = 0.3
		p.explosiveness = 1.0
		p.local_coords = false
		p.mesh = mesh
		p.spread = 40.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0, -12, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		add_child(p)
		_impacts.append(p)


func spawn_impact(pos: Vector3, normal: Vector3, on_target: bool, tint := Color(0, 0, 0, 0)) -> void:
	var p: CPUParticles3D = _impacts[_impact_idx]
	_impact_idx = (_impact_idx + 1) % _impacts.size()
	p.global_position = pos + normal * 0.03
	p.direction = normal
	p.color = Color(1.6, 0.9, 0.35) if on_target else Color(0.75, 0.82, 0.95)  # sparks vs wet splash
	if tint.a > 0.0:
		p.color = tint
	p.restart()
	p.emitting = true


## Pool of explosion effects: fireball, sparks/debris, smoke and a light flash.
func _build_explosions() -> void:
	for i in 5:
		var root := Node3D.new()
		add_child(root)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 16
		sm.rings = 8
		ball.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bm.disable_fog = true
		bm.albedo_color = Color(1.0, 0.6, 0.2, 1.0)
		ball.material_override = bm
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.visible = false
		root.add_child(ball)

		var debris := _burst(Color(1.5, 0.75, 0.3), 36, 0.6, 0.06, 8.0, 16.0, Vector3(0, -12, 0), false)
		root.add_child(debris)
		var smoke := _burst(Color(0.12, 0.12, 0.12, 0.55), 16, 2.2, 0.9, 0.8, 2.5, Vector3(0, 0.8, 0), true)
		root.add_child(smoke)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.25)
		light.omni_range = 14.0
		light.visible = false
		light.position.y = 1.0
		root.add_child(light)
		_explosions.append({"root": root, "ball": ball, "debris": debris, "smoke": smoke, "light": light, "tween": null})


func _burst(color: Color, amount: int, life: float, size: float, vmin: float, vmax: float, grav: Vector3, billboard: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	if billboard:
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		q.material = mat
		p.mesh = q
		p.scale_amount_min = 1.0
		p.scale_amount_max = 3.0
	else:
		var b := BoxMesh.new()
		b.size = Vector3(size, size, size)
		mat.disable_fog = true
		b.material = mat
		p.mesh = b
	p.color = color
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = grav
	return p


## Blast: splash damage with falloff to every target in the radius (a direct
## hit always takes full damage), plus the big screen and light effects.
func spawn_explosion(pos: Vector3, w: Dictionary, direct: Node3D, hostile := false) -> void:
	var radius: float = w["radius"]
	if hostile:
		_blast_soldiers(pos, w, direct)
	else:
		for t in targets:
			if not t.alive or not ("gunners" in t):
				continue
			var sd: float = t.aim_point().distance_to(pos)
			if sd < radius * 2.5:
				for g in t.gunners:
					g.add_suppression(0.6 * (1.0 - sd / (radius * 2.5)))
	for t in ([] if hostile else targets):
		if not t.alive:
			continue
		var f := 1.0
		if t != direct:
			var d: float = maxf(0.0, t.aim_point().distance_to(pos) - t.radius * 0.5)
			if d > radius:
				continue
			f = lerpf(1.0, 0.25, d / radius)
		t.take_damage(w["soft"] * f, w["armor"] * f)

	var big: bool = w["kind"] != "grenade"
	var e: Dictionary = _explosions[_explosion_idx]
	_explosion_idx = (_explosion_idx + 1) % _explosions.size()
	e["root"].global_position = pos
	var ball: MeshInstance3D = e["ball"]
	var light: OmniLight3D = e["light"]
	ball.visible = true
	ball.scale = Vector3.ONE * 0.3
	(ball.material_override as StandardMaterial3D).albedo_color.a = 1.0
	light.visible = true
	light.light_energy = 9.0 if big else 6.0
	for k in ["debris", "smoke"]:
		e[k].restart()
		e[k].emitting = true
	if e["tween"]:
		e["tween"].kill()
	var tw := create_tween().set_parallel(true)
	var size := radius * (0.9 if big else 0.7)
	tw.tween_property(ball, "scale", Vector3.ONE * size * 2.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(ball.material_override, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(func():
		ball.visible = false
		light.visible = false)
	e["tween"] = tw

	# Shake harder the closer the blast is to the camera.
	var cam_d: float = cam_rig.cam.global_position.distance_to(pos)
	fire_heat = minf(1.0, fire_heat + (0.6 if big else 0.4) * clampf(40.0 / maxf(cam_d, 1.0), 0.4, 1.0))
	flash = 1.0


## Enemy shell landing: damage with falloff, cut to 30% if a crate is between
## the blast and the soldier, and heavy suppression around it.
func _blast_soldiers(pos: Vector3, w: Dictionary, direct: Node3D) -> void:
	var radius: float = w["radius"]
	var space := get_world_3d().direct_space_state
	for s in squad.soldiers.duplicate():
		var p: Vector3 = s.exposed_point()
		var d: float = p.distance_to(pos)
		if d < radius * 2.5:
			s.add_suppression(w["suppress"] * (1.0 - d / (radius * 2.5)))
		if s != direct and d > radius:
			continue
		var f := 1.0 if s == direct else lerpf(1.0, 0.2, d / radius)
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), p, 1)
		if not space.intersect_ray(q).is_empty():
			f *= 0.3
		s.take_damage(w["soft"] * f, pos)


## Distance from point p to the segment a-b.
func _seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Our rounds snapping past enemies pin them down.
func suppress_enemies(from: Vector3, end: Vector3, amount: float) -> void:
	for t in targets:
		if not t.alive or not ("gunners" in t):
			continue
		var reach: float = 2.5 + t.radius
		var d := _seg_dist(from, end, t.aim_point())
		if d < reach:
			for g in t.gunners:
				g.add_suppression(amount * (1.0 - d / reach))


## Enemy rounds snapping past soldiers rattle them.
func suppress_squad(from: Vector3, end: Vector3, amount: float) -> void:
	for s in squad.soldiers:
		var d := _seg_dist(from, end, s.global_position + Vector3(0, 1.1, 0))
		if d < 2.0:
			s.add_suppression(amount * (1.0 - d / 2.0))


func on_soldier_hit(_s: Node3D) -> void:
	hurt = 1.0
	fire_heat = minf(1.0, fire_heat + 0.15)


func on_enemy_cannon(at: Vector3) -> void:
	var d: float = cam_rig.cam.global_position.distance_to(at)
	fire_heat = minf(1.0, fire_heat + clampf(20.0 / maxf(d, 1.0), 0.05, 0.3))


## Backblast / thump when a launcher fires.
func on_launch(at: Vector3, w: Dictionary) -> void:
	fire_heat = minf(1.0, fire_heat + (0.3 if w["kind"] == "rocket" else 0.15))
	flash = minf(1.0, flash + 0.6)
	_muzzle_light.global_position = at


func on_vehicle_destroyed(v: Node3D) -> void:
	notify("ENEMY %s DESTROYED" % v.vehicle_name)


func notify(text: String) -> void:
	_notice = text
	_notice_t = 4.0


## Every shot heats up the screen effects; many at once = shake, blur, flash.
func on_shot(at: Vector3) -> void:
	fire_heat = minf(1.0, fire_heat + 0.06)
	flash = minf(1.0, flash + 0.3)
	_muzzle_light.global_position = _muzzle_light.global_position.lerp(at, 0.5) if _muzzle_light.visible else at


# ---------------------------------------------------------------- queries

## The reticle box in screen pixels.
func reticle_rect() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var w: float = reticle.p["width"]
	var h: float = reticle.p["height"]
	var c := vs * 0.5 + Vector2(0, reticle.p["offset_y"])
	return Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))


## True if a world point shows up inside the reticle on screen.
func in_reticle(world_pos: Vector3) -> bool:
	var cam: Camera3D = cam_rig.cam
	if cam.is_position_behind(world_pos):
		return false
	return reticle_rect().has_point(cam.unproject_position(world_pos))


## A random world point under the reticle (what the squad hits when focus
## firing with no target inside it).
func reticle_world_point(rng: RandomNumberGenerator) -> Vector3:
	var cam: Camera3D = cam_rig.cam
	var r := reticle_rect()
	var sp := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
	var origin := cam.project_ray_origin(sp)
	var dir := cam.project_ray_normal(sp)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 150.0, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else origin + dir * 80.0


## Flat direction the camera is looking. Cover orders shield the squad from
## this direction (the box ends up between each soldier and where you look).
func camera_forward() -> Vector3:
	var dir: Vector3 = cam_rig.get_yaw_basis() * Vector3.FORWARD
	dir.y = 0
	return dir.normalized()


func on_dummy_down() -> void:
	kills += 1


# ---------------------------------------------------------------- HUD

func _neon_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UI_FONT
	t.default_font_size = 15
	var glow := Color(NEON, 0.28)
	for type in ["Label", "Button", "CheckBox"]:
		t.set_color("font_color", type, NEON)
		t.set_color("font_outline_color", type, glow)
		t.set_constant("outline_size", type, 5)
	for type in ["Button", "CheckBox"]:
		t.set_color("font_hover_color", type, Color(0.75, 1.0, 0.6))
		t.set_color("font_pressed_color", type, Color(0.75, 1.0, 0.6))
		t.set_color("font_focus_color", type, NEON)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.03, 0.1, 0.03, 0.9)
	btn.border_color = Color(NEON, 0.5)
	btn.set_border_width_all(1)
	btn.set_content_margin_all(5)
	t.set_stylebox("normal", "Button", btn)
	var btn_h := btn.duplicate()
	btn_h.bg_color = Color(0.06, 0.18, 0.05, 0.95)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_h)
	return t


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = _neon_theme()
	layer.add_child(ui_root)

	reticle = ReticleScript.new()
	ui_root.add_child(reticle)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.05, 0.0, 0.55)
	sb.border_color = Color(NEON, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(panel)
	hud_label = Label.new()
	panel.add_child(hud_label)

	reticle_panel = ReticlePanelScript.new()
	reticle_panel.reticle = reticle
	ui_root.add_child(reticle_panel)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		reticle_panel.toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	for i in _tracers.size():
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= delta
			if _tracer_life[i] <= 0.0:
				_tracers[i].visible = false

	# Firing intensity decays when the guns go quiet.
	fire_heat = move_toward(fire_heat, 0.0, delta * 1.1)
	flash = move_toward(flash, 0.0, delta * 9.0)
	_muzzle_light.light_energy = flash * 5.0
	_muzzle_light.visible = flash > 0.03
	hurt = move_toward(hurt, 0.0, delta * 2.5)
	if postfx:
		postfx.set_fx(fire_heat, flash, squad.avg_suppression(), hurt)
	if reticle:
		reticle.marks = _target_marks()

	# Neon tube flicker on all UI: a steady hum plus the odd brown-out.
	_flicker_t += delta
	if ui_root:
		var hum := 0.93 + 0.05 * sin(_flicker_t * 61.0) * sin(_flicker_t * 3.7)
		if fmod(_flicker_t * 1.37, 4.1) < 0.06:
			hum *= 0.55
		ui_root.modulate = Color(1, 1, 1, hum)
		reticle.focus_active = squad.fire_mode() == squad.FOCUS

	if hud_label:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		_notice_t = maxf(0.0, _notice_t - delta)
		hud_label.text = "SQUAD TEST // FIELD TRIAL\n" \
			+ "WASD  move squad     MOUSE  aim%s     WHEEL  zoom\n" % ("" if captured else " (click to grab)") \
			+ "HOLD LMB  focus fire on reticle     HOLD RMB  specialists fire GL / rockets\n" \
			+ "C / SPACE  cover vs camera facing     F  auto fire (at will)     TAB  reticle     R  restart\n\n" \
			+ "SQUAD   %s\n" % squad.status_text() \
			+ "UNIT    %s\n" % squad.roster_text() \
			+ "FIRE    %s%s\n" % [squad.fire_mode_text(), "   (auto fire ON)" if squad.auto_fire else ""] \
			+ "UNDER FIRE  %s\n" % _supp_bar(squad.avg_suppression()) \
			+ "HITS    %d     DROPPED  %d" % [hits, kills] \
			+ ("\n\n>> %s" % _notice if _notice_t > 0.0 else "")


func _supp_bar(v: float) -> String:
	var n := roundi(v * 10.0)
	var tag := "  PINNED" if v > 0.85 else ("  SUPPRESSED" if v > 0.4 else "")
	return "[" + "#".repeat(n) + "-".repeat(10 - n) + "]" + tag


## Empty squares over every live enemy inside the reticle, sized to the
## enemy on screen, with their suppression level. Thicker = being engaged.
func _target_marks() -> Array:
	var marks: Array = []
	var cam: Camera3D = cam_rig.cam
	var rr := reticle_rect()
	var engaged := {}
	for s in squad.soldiers:
		if s.target:
			engaged[s.target] = true
	for t in targets:
		if not t.alive:
			continue
		var c: Vector3 = t.aim_point()
		if cam.is_position_behind(c) or not rr.has_point(cam.unproject_position(c)):
			continue
		var top := cam.unproject_position(t.global_position + Vector3(0, t.mark_height, 0))
		var bottom := cam.unproject_position(t.global_position)
		var side := clampf(absf(bottom.y - top.y) * 1.15, 14.0, 220.0)
		var centre := (top + bottom) * 0.5
		marks.append({
			"rect": Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side)),
			"supp": t.suppression_level(),
			"engaged": engaged.has(t),
			"vehicle": t.kind == "vehicle",
		})
	return marks
