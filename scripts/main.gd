extends Node3D
## Squad Test - builds the practice field (ground, cover boxes, target dummies),
## the squad, the camera, the HUD and a shared pool of bullet tracers.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SquadScript = preload("res://scripts/squad.gd")
const DummyScript = preload("res://scripts/dummy.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const ReticleScript = preload("res://scripts/reticle.gd")
const ReticlePanelScript = preload("res://scripts/reticle_panel.gd")
const AtmosphereScript = preload("res://scripts/atmosphere.gd")
const PostFxScript = preload("res://scripts/postfx.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")
const NEON := Color(0.45, 1.0, 0.30)

const NAV_HALF := 50.0          # playable half-size of the field (metres)
const SQUAD_SIZE := 6
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
	_build_tracers()
	_build_impacts()
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.68, 0.32)
	_muzzle_light.omni_range = 9.0
	_muzzle_light.visible = false
	add_child(_muzzle_light)

	squad = SquadScript.new()
	squad.name = "Squad"
	add_child(squad)
	squad.setup(self, Vector3(0, 0, 24), SQUAD_SIZE)

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
// Rain-soaked field: dark wet grass, glossy puddles with rain ripples.
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

	// Rain ripples: expanding rings in a jittered grid of cells.
	vec2 cell = floor(wpos.xz / 0.7);
	vec2 local = fract(wpos.xz / 0.7) - 0.5;
	float ph = hash(cell);
	vec2 ctr = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	vec2 dv = local - ctr * 0.5;
	float t = fract(TIME * 1.3 + ph);
	float ring = 1.0 - smoothstep(0.0, 0.05, abs(length(dv) - t * 0.45));
	vec2 n = normalize(dv + 1e-4) * ring * (1.0 - t) * 0.9;
	NORMAL_MAP = normalize(vec3(n * 0.5 + 0.5, 1.0));
	NORMAL_MAP_DEPTH = mix(0.4, 1.0, puddle);

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


func _build_tracers() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.4)
	mat.disable_fog = true
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


func spawn_tracer(from: Vector3, to: Vector3) -> void:
	var v := to - from
	var length := v.length()
	if length < 0.05:
		return
	var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT
	var t: MeshInstance3D = _tracers[_tracer_idx]
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


func spawn_impact(pos: Vector3, normal: Vector3, on_target: bool) -> void:
	var p: CPUParticles3D = _impacts[_impact_idx]
	_impact_idx = (_impact_idx + 1) % _impacts.size()
	p.global_position = pos + normal * 0.03
	p.direction = normal
	p.color = Color(1.6, 0.9, 0.35) if on_target else Color(0.75, 0.82, 0.95)  # sparks vs wet splash
	p.restart()
	p.emitting = true


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
	if postfx:
		postfx.set_fx(fire_heat, flash)

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
		hud_label.text = "SQUAD TEST // FIELD TRIAL\n" \
			+ "WASD  move squad     MOUSE  aim%s     WHEEL  zoom\n" % ("" if captured else " (click to grab)") \
			+ "HOLD LMB  focus fire on reticle     HOLD RMB  fire at will\n" \
			+ "C / SPACE  cover vs camera facing     F  auto fire     TAB  reticle\n\n" \
			+ "SQUAD   %s\n" % squad.status_text() \
			+ "FIRE    %s%s\n" % [squad.fire_mode_text(), "   (auto fire ON)" if squad.auto_fire else ""] \
			+ "HITS    %d     DROPPED  %d" % [hits, kills]
