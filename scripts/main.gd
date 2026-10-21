extends Node3D
## Squad Test - builds the practice field (ground, cover boxes, target dummies),
## the squad, the camera, the HUD and a shared pool of bullet tracers.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SquadScript = preload("res://scripts/squad.gd")
const DummyScript = preload("res://scripts/dummy.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")

const NAV_HALF := 50.0          # playable half-size of the field (metres)
const SQUAD_SIZE := 6
const TRACER_COUNT := 48
const TRACER_LIFE := 0.06

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
var hits := 0
var kills := 0

var _tracers: Array = []
var _tracer_life: Array = []
var _tracer_idx := 0


func _ready() -> void:
	_setup_input()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	_build_ground()
	_build_boxes()
	_bake_nav()
	_build_cover_points()
	_build_dummies()
	_build_tracers()

	squad = SquadScript.new()
	squad.name = "Squad"
	add_child(squad)
	squad.setup(self, Vector3(0, 0, 24), SQUAD_SIZE)

	cam_rig = CameraRigScript.new()
	cam_rig.name = "CameraRig"
	cam_rig.target = squad
	add_child(cam_rig)

	_build_hud()


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("take_cover", [KEY_C, KEY_SPACE])
	_bind("hold_fire", [KEY_F])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.58, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.88)
	sky_mat.ground_horizon_color = Color(0.55, 0.62, 0.55)
	sky_mat.ground_bottom_color = Color(0.25, 0.32, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


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
render_mode specular_disabled;
uniform vec3 base_col : source_color = vec3(0.32, 0.55, 0.25);
uniform vec3 line_col : source_color = vec3(0.27, 0.47, 0.21);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wpos.xz / 4.0 - 0.5) - 0.5) * 4.0;
	float l = 1.0 - smoothstep(0.0, 0.07, min(g.x, g.y));
	bool outside = abs(wpos.x) > 50.0 || abs(wpos.z) > 50.0;
	vec3 c = mix(base_col, line_col, l);
	ALBEDO = outside ? c * 0.8 : c;
	ROUGHNESS = 1.0;
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
	var low_mat := StandardMaterial3D.new()
	low_mat.albedo_color = Color(0.70, 0.58, 0.38)
	var tall_mat := StandardMaterial3D.new()
	tall_mat.albedo_color = Color(0.50, 0.38, 0.24)

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
				cover_points.append({
					"pos": xf * local,
					"normal": (xf.basis * face).normalized(),
					"height": size.y,
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
	mat.albedo_color = Color(1.0, 0.85, 0.35)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, 1.0)
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


# ---------------------------------------------------------------- queries

## Flat direction the squad should take cover against: toward the nearest
## standing dummy, or where the camera looks if none are close.
func threat_direction(from: Vector3) -> Vector3:
	var best: Node3D = null
	var best_d := 70.0
	for d in dummies:
		if not d.alive:
			continue
		var dist: float = from.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	var dir: Vector3
	if best:
		dir = best.global_position - from
	else:
		dir = cam_rig.get_yaw_basis() * Vector3.FORWARD
	dir.y = 0
	return dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD


func on_dummy_down() -> void:
	kills += 1


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(hud_label)


func _process(delta: float) -> void:
	for i in _tracers.size():
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= delta
			if _tracer_life[i] <= 0.0:
				_tracers[i].visible = false

	if hud_label:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		hud_label.text = "SQUAD TEST\n" \
			+ "WASD  move squad     Mouse  look%s     Wheel  zoom\n" % ("" if captured else " (click to grab)") \
			+ "C / Space  take cover / leave cover     F  hold fire\n\n" \
			+ "Squad: %s\n" % squad.status_text() \
			+ "Fire: %s     Hits: %d     Targets dropped: %d" % ["HOLD" if squad.hold_fire else "FREE", hits, kills]
