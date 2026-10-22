extends Node3D
## Squad Test - builds the test field (ground, cover, three defended enemy
## areas), the squad, the camera, the HUD and the shared effect pools.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SquadScript = preload("res://scripts/squad.gd")
const EnemySoldierScript = preload("res://scripts/enemy_soldier.gd")
const VehicleScript = preload("res://scripts/vehicle.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const Weapons = preload("res://scripts/weapons.gd")
const ReticleScript = preload("res://scripts/reticle.gd")
const ReticlePanelScript = preload("res://scripts/reticle_panel.gd")
const AtmosphereScript = preload("res://scripts/atmosphere.gd")
const PostFxScript = preload("res://scripts/postfx.gd")
const FieldManualScript = preload("res://scripts/field_manual.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")
const StreetMission = preload("res://scripts/maps/street_mission.gd")
const TestField = preload("res://scripts/maps/test_field.gd")
const ModelViewer = preload("res://scripts/maps/model_viewer.gd")
const MAPS := [StreetMission, TestField, ModelViewer]     # M cycles through these
const NEON := Color(0.45, 1.0, 0.30)

const NAV_HALF := 50.0          # playable half-size of the field (metres)
const TRACER_COUNT := 48
const TRACER_LIFE := 0.06
const TALL_COVER := 1.6         # boxes taller than this need a lean-out to shoot

var map: GDScript              # the map being played (scripts/maps/*)
static var forced_map := -1    # tests: pick a map regardless of saved settings
var map_index := 0
var cover_defs: Array = []      # [{xform, size}] used by CoverUtil
var solid_defs: Array = []      # buildings and compound walls: the squad's anchor can't pass these
var cover_points: Array = []    # [{pos, normal, height}]
var targets: Array = []         # everything the squad can shoot: enemy soldiers + vehicles
var areas: Array = []           # [{name, center, radius, members, alerted, claimed, label}]
var vehicles: Array = []
var squad: Node3D
var cam_rig: Node3D
var nav_region: NavigationRegion3D
var hud_label: Label
var unit_label: RichTextLabel     # squad health panel (bottom right)
var special_label: RichTextLabel  # special-weapon selector bar (bottom centre)
var _no_explosives_t := 0.0
var _special_msg := ""          # special callouts / warnings, shown under the special bar
var _special_msg_t := 0.0
var help_label: Label
var help_panel: PanelContainer
var manual: CanvasLayer          # Esc: field manual + pause
var _help_t := 25.0            # controls panel auto-hides after this; F1 toggles it
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
var low_quality := false     # G: LOW graphics for weaker machines (remembered)
const SETTINGS_PATH := "user://settings.cfg"
var debug_reticle_all := false   # headless tests: treat everything as inside the reticle

var _tracers: Array = []
var _tracer_life: Array = []
var _tracer_idx := 0


func _ready() -> void:
	_setup_input()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		low_quality = bool(cfg.get_value("graphics", "low", false))
		map_index = clampi(int(cfg.get_value("game", "map", 0)), 0, MAPS.size() - 1)
	if forced_map >= 0:
		map_index = forced_map
	map = MAPS[map_index]
	AtmosphereScript.night = map.NIGHT
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
	_build_areas()
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
	squad.setup(self, map.START)
	squad.spawn_waiting_team("ANTI-ARMOR TEAM", map.AT_TEAM, ["anti_armor", "anti_armor", "anti_armor"])

	cam_rig = CameraRigScript.new()
	cam_rig.name = "CameraRig"
	cam_rig.target = squad
	cam_rig.main = self
	add_child(cam_rig)
	atmosphere.cam_rig = cam_rig

	postfx = PostFxScript.new()
	add_child(postfx)

	map.build_extras(self)
	_build_hud()
	_apply_quality()
	notify(map.OBJECTIVE, 7.0)


## LOW: no shadows, no bloom, no MSAA, 3D drawn at 70% resolution, cheap
## screen effects. HIGH: everything on.
func _apply_quality() -> void:
	atmosphere.set_low_quality(low_quality)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if low_quality else Viewport.MSAA_2X
	vp.scaling_3d_scale = 0.7 if low_quality else 1.0
	postfx.set_cheap(low_quality)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "low", low_quality)
	cfg.set_value("game", "map", map_index)
	cfg.save(SETTINGS_PATH)


## M: next map (remembered), then restart.
func next_map() -> void:
	map_index = (map_index + 1) % MAPS.size()
	_save_settings()
	get_tree().reload_current_scene()


func toggle_quality() -> void:
	low_quality = not low_quality
	_apply_quality()
	_save_settings()
	notify("GRAPHICS: %s" % ("LOW" if low_quality else "HIGH"))


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("take_cover", [KEY_C, KEY_SPACE])
	_bind("auto_fire", [KEY_F])
	_bind("move_order", [KEY_E])
	_bind("split_teams", [KEY_T])
	_bind("switch_team", [KEY_Q])
	_bind("bound", [KEY_B])
	_bind("hold_position", [KEY_H])
	_bind("cycle_special", [KEY_X])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- world

## Ground in 10 m tiles (so each tile only gathers the lights near it) plus
## invisible walls around the playable area. "field": grass. "street":
## asphalt road with lane markings, concrete sidewalks, a concrete compound
## yard; wet and glossy at night.
const GROUND_SHADER := """
shader_type spatial;
uniform float wet = 0.0;      // 1 at night: dark, glossy, puddles
uniform float street = 0.0;   // 1: street map surfaces, 0: grass field
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float patch = noise(wpos.xz * 0.22) * 0.7 + noise(wpos.xz * 0.9) * 0.3;
	vec3 c;
	float rough;
	if (street > 0.5) {
		float ax = abs(wpos.x);
		bool road = ax < 5.0 && wpos.z > -24.0;
		bool walk = ax >= 5.0 && ax < 7.0 && wpos.z > -24.0;
		bool yard = wpos.z < -24.0 && abs(wpos.x) < 22.0;
		c = vec3(0.075, 0.075, 0.08) * (0.85 + 0.3 * noise(wpos.xz * 1.7));       // asphalt
		if (road) {
			if (ax < 0.08 && fract(wpos.z / 6.0) < 0.5) c = vec3(0.55, 0.45, 0.15);  // centre dashes
			if (abs(ax - 4.75) < 0.06) c = vec3(0.4);                                // edge lines
		}
		if (walk) {
			c = vec3(0.2, 0.2, 0.19) * (0.9 + 0.2 * noise(wpos.xz * 3.0));
			float seam = 1.0 - smoothstep(0.0, 0.04, abs(fract(wpos.z / 1.5) - 0.5) - 0.46);
			c *= 1.0 - 0.25 * (1.0 - seam);
			if (abs(ax - 5.0) < 0.12) c = vec3(0.3);                                  // kerb
		}
		if (yard) c = vec3(0.16, 0.16, 0.15) * (0.85 + 0.3 * noise(wpos.xz * 0.8));
		rough = 0.75;
	} else {
		vec2 g = abs(fract(wpos.xz / 4.0 - 0.5) - 0.5) * 4.0;
		float l = 1.0 - smoothstep(0.0, 0.06, min(g.x, g.y));
		c = mix(vec3(0.20, 0.28, 0.12), vec3(0.30, 0.31, 0.16), smoothstep(0.35, 0.75, patch));
		c = mix(c, c * 0.85, l * 0.5);
		if (wet > 0.5) c = mix(vec3(0.10, 0.17, 0.08), vec3(0.07, 0.12, 0.06), l * 0.6);
		rough = 0.95;
	}
	float puddle = smoothstep(0.52, 0.62, patch) * wet;
	c = mix(c, c * 0.4, puddle);
	bool outside = abs(wpos.x) > 50.0 || abs(wpos.z) > 50.0;
	ALBEDO = outside ? c * 0.7 : c;
	ROUGHNESS = mix(rough, mix(0.3, 0.03, puddle), wet);
	SPECULAR = mix(0.2, 0.7, wet);
}
"""

const BUILDING_SHADER := """
shader_type spatial;
// Facade with a window grid. At night some windows are lit (warm or TV-blue).
uniform vec3 wall_col : source_color = vec3(0.2, 0.19, 0.18);
uniform float seed = 0.0;
uniform float night = 1.0;
varying vec3 wpos;
varying vec3 wn;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = wall_col * (0.9 + 0.2 * hash(floor(wpos.xz * 0.5) + seed));
	float rough = 0.85;
	vec3 emit = vec3(0.0);
	if (abs(wn.y) < 0.5 && wpos.y > 1.2) {
		float u = abs(wn.x) > 0.5 ? wpos.z : wpos.x;
		vec2 cell = vec2(floor(u / 3.0), floor((wpos.y - 1.2) / 3.2));
		vec2 f = vec2(fract(u / 3.0), fract((wpos.y - 1.2) / 3.2));
		if (f.x > 0.25 && f.x < 0.75 && f.y > 0.3 && f.y < 0.8) {
			float h = hash(cell + vec2(seed, seed * 1.7) + wn.xz * 13.0);
			c = vec3(0.03, 0.035, 0.04);
			rough = 0.08;
			if (night > 0.5 && h > 0.74)
				emit = mix(vec3(1.0, 0.68, 0.32), vec3(0.55, 0.7, 1.0), step(0.93, h)) * (0.9 + h);
		}
	}
	if (wpos.y < 1.0) c *= 0.65;      // grimy ground floor
	ALBEDO = c;
	ROUGHNESS = rough;
	EMISSION = emit;
}
"""


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	nav_region.add_child(body)

	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("wet", 1.0 if AtmosphereScript.night else 0.0)
	mat.set_shader_parameter("street", 1.0 if map.GROUND == "street" else 0.0)
	var tile := PlaneMesh.new()
	tile.size = Vector2(10, 10)
	for ix in range(-6, 6):
		for iz in range(-6, 6):
			var mi := MeshInstance3D.new()
			mi.mesh = tile
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(ix * 10 + 5, 0, iz * 10 + 5)
			body.add_child(mi)
	var outer := MeshInstance3D.new()        # far ground beyond the tiles
	var big := PlaneMesh.new()
	big.size = Vector2(400, 400)
	outer.mesh = big
	outer.material_override = mat
	outer.position.y = -0.02
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(outer)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(240, 1, 240)
	col.shape = shape
	col.position.y = -0.5
	body.add_child(col)

	# Invisible walls keep everyone on the playable area.
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = Vector3(1, 6, NAV_HALF * 2 + 2) if side.x != 0 else Vector3(NAV_HALF * 2 + 2, 6, 1)
		wall.shape = ws
		wall.position = side * (NAV_HALF + 0.5) + Vector3(0, 3, 0)
		body.add_child(wall)



## Every cover object / building from the map. Low cover and tall crates go
## in cover_defs; buildings and compound walls also go in solid_defs.
func _build_boxes() -> void:
	var night: bool = AtmosphereScript.night
	var mats := {
		"crate": _surface(Color(0.36, 0.27, 0.16) if night else Color(0.55, 0.42, 0.26), night),
		"tall": _surface(Color(0.26, 0.19, 0.12) if night else Color(0.42, 0.31, 0.19), night),
		"wall": _surface(Color(0.30, 0.30, 0.29) if night else Color(0.58, 0.57, 0.53), night),
		"barrier": _surface(Color(0.42, 0.41, 0.38), night),
		"cwall": _surface(Color(0.24, 0.23, 0.21), night),
		"sandbag": _surface(Color(0.40, 0.36, 0.26), false),
		"dumpster": _surface(Color(0.10, 0.22, 0.14), night),
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for entry in map.BOXES:
		var pos: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		var yaw: float = entry[2]
		var type: String = entry[3]
		var xform := Transform3D(Basis(Vector3.UP, yaw), pos)
		var def := {"xform": xform, "size": size, "type": type}
		cover_defs.append(def)
		if type in ["building", "cwall"]:
			solid_defs.append(def)

		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.transform = Transform3D(xform.basis, pos + Vector3(0, size.y * 0.5, 0))
		nav_region.add_child(body)

		match type:
			"car":
				_build_car(body, size, rng)
			"building":
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = size
				mi.mesh = bm
				var sh := Shader.new()
				sh.code = BUILDING_SHADER
				var m := ShaderMaterial.new()
				m.shader = sh
				var tones := [Color(0.2, 0.19, 0.18), Color(0.17, 0.17, 0.19), Color(0.23, 0.2, 0.17), Color(0.15, 0.15, 0.14)]
				m.set_shader_parameter("wall_col", tones[rng.randi() % tones.size()] * (1.0 if night else 2.2))
				m.set_shader_parameter("seed", rng.randf() * 100.0)
				m.set_shader_parameter("night", 1.0 if night else 0.0)
				mi.material_override = m
				body.add_child(mi)
			_:
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = size
				mi.mesh = bm
				mi.material_override = mats.get(type, mats["crate"])
				body.add_child(mi)

		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		body.add_child(col)

		# Big hollow boxes would otherwise leave walkable "floor" inside them
		# in the navigation mesh; an obstacle footprint blocks that out.
		if size.x * size.z > 6.0:
			var ob := NavigationObstacle3D.new()
			var hx := size.x * 0.5
			var hz := size.z * 0.5
			var verts := PackedVector3Array()
			for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
				verts.append(xform.basis * c)
			ob.vertices = verts
			ob.height = size.y
			ob.affect_navigation_mesh = true
			ob.avoidance_enabled = false
			ob.position = pos
			nav_region.add_child(ob)


## Low-poly car: body, cabin with dark glass, wheels; some still have their
## tail lights on. Length runs along local x.
func _build_car(body: Node3D, size: Vector3, rng: RandomNumberGenerator) -> void:
	var paints := [Color(0.35, 0.05, 0.05), Color(0.25, 0.27, 0.3), Color(0.08, 0.1, 0.2), Color(0.55, 0.55, 0.52), Color(0.1, 0.1, 0.1), Color(0.3, 0.25, 0.12)]
	var paint := StandardMaterial3D.new()
	paint.albedo_color = paints[rng.randi() % paints.size()]
	paint.roughness = 0.15
	paint.metallic = 0.4
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.02, 0.025, 0.03)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var tyre := StandardMaterial3D.new()
	tyre.albedo_color = Color(0.03, 0.03, 0.03)
	var bottom := -size.y * 0.5
	var lower := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(size.x, 0.7, size.z)
	lower.mesh = lm
	lower.material_override = paint
	lower.position = Vector3(0, bottom + 0.3 + 0.35, 0)
	body.add_child(lower)
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(size.x * 0.5, 0.55, size.z * 0.9)
	cabin.mesh = cm
	cabin.material_override = glass
	cabin.position = Vector3(-size.x * 0.05, bottom + 1.0 + 0.27, 0)
	body.add_child(cabin)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.33
			wm.bottom_radius = 0.33
			wm.height = 0.24
			wm.radial_segments = 10
			w.mesh = wm
			w.material_override = tyre
			w.position = Vector3(x * size.x * 0.32, bottom + 0.33, z * (size.z * 0.5 - 0.08))
			w.rotation.x = PI / 2.0
			body.add_child(w)
	if AtmosphereScript.night and rng.randf() < 0.35:
		var tail := StandardMaterial3D.new()
		tail.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tail.albedo_color = Color(1.4, 0.08, 0.05)
		for z in [-1.0, 1.0]:
			var t := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.05, 0.12, 0.3)
			t.mesh = tm
			t.material_override = tail
			t.position = Vector3(-size.x * 0.5 - 0.02, bottom + 0.85, z * size.z * 0.33)
			body.add_child(t)

## Glossy and wet at night, dry and matte in daylight.
func _surface(color: Color, wet: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.18 if wet else 0.85
	m.metallic_specular = 0.8 if wet else 0.4
	return m


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.filter_baking_aabb = AABB(Vector3(-NAV_HALF, -1, -NAV_HALF), Vector3(NAV_HALF * 2, 16, NAV_HALF * 2))   # tall enough to include whole buildings
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


## Spots around every box where a soldier can crouch. Each has an outward
## normal; a spot gives cover when its normal points away from the threat.
## Buildings and compound walls only give cover at their corners and gate
## edges, where you can lean out around them.
func _build_cover_points() -> void:
	for def in cover_defs:
		var xf: Transform3D = def["xform"]
		var size: Vector3 = def["size"]
		var corners_only: bool = def.get("type", "") in ["building", "cwall"]
		for face in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var along_x: bool = absf(face.x) > 0.0
			var half_n: float = size.x * 0.5 if along_x else size.z * 0.5
			var span: float = size.z if along_x else size.x
			var tangent: Vector3 = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
			if corners_only:
				if span < 0.9:
					continue          # wall ends are handled by the long faces
				for side in [-1.0, 1.0]:
					var local: Vector3 = face * (half_n + 0.6) + tangent * side * maxf(span * 0.5 - 0.6, 0.0)
					var lp: Vector3 = face * (half_n + 0.6) + tangent * side * (span * 0.5 + 0.5)
					cover_points.append({
						"pos": xf * local,
						"normal": (xf.basis * face).normalized(),
						"height": size.y,
						"peeks": [CoverUtil.push_out(cover_defs, xf * lp, 0.5)],
					})
				continue
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

## Spawn each defended area: its riflemen, the APC for CHARLIE, and a
## floating label with how many hostiles are left.
func _build_areas() -> void:
	for def in map.AREAS:
		var area := {
			"name": def["name"], "center": def["center"], "radius": def["radius"],
			"members": [], "alerted": false, "claimed": {},
		}
		for p in def["men"]:
			var e: CharacterBody3D = EnemySoldierScript.new()
			e.main = self
			e.area = area
			e.post = p
			e.position = p
			add_child(e)
			area["members"].append(e)
			targets.append(e)
		if def.has("apc"):
			var v: StaticBody3D = VehicleScript.new()
			v.main = self
			v.area = area
			v.respawns = false
			v.waypoints = def["apc"]
			add_child(v)
			v.global_position = def["apc"][0]
			v.rotation.y = PI / 2.0
			area["members"].append(v)
			vehicles.append(v)
			targets.append(v)
		var label := Label3D.new()
		label.font = UI_FONT
		label.font_size = 48
		label.outline_size = 10
		label.pixel_size = 0.008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(1.0, 0.75, 0.25)
		label.outline_modulate = Color(0.1, 0.05, 0.0, 0.8)
		label.position = def["center"] + Vector3(0, 5.5, 0)
		add_child(label)
		area["label"] = label
		areas.append(area)
		_update_area_label(area)


func _alive_in(area: Dictionary) -> int:
	var n := 0
	for m in area["members"]:
		if m.alive:
			n += 1
	return n


func _update_area_label(area: Dictionary) -> void:
	var n := _alive_in(area)
	var lbl: Label3D = area["label"]
	if n == 0:
		lbl.text = "AREA %s\nCLEARED" % area["name"]
		lbl.modulate = Color(0.45, 1.0, 0.3)
	else:
		lbl.text = "AREA %s\n%d HOSTILE%s%s" % [area["name"], n, "" if n == 1 else "S", "  [ALERT]" if area["alerted"] else ""]


func on_area_alerted(area: Dictionary) -> void:
	_update_area_label(area)
	notify("CONTACT  -  AREA %s" % area["name"])


func on_enemy_killed(e: Node3D) -> void:
	kills += 1
	for area in areas:
		if e in area["members"]:
			_update_area_label(area)
			if _alive_in(area) == 0:
				var all_clear := true
				for a in areas:
					if _alive_in(a) > 0:
						all_clear = false
				notify(map.COMPLETE if all_clear else "AREA %s CLEARED" % area["name"], 8.0 if all_clear else 4.0)


func any_area_alerted() -> bool:
	for a in areas:
		if a["alerted"] and _alive_in(a) > 0:
			return true
	return false


func areas_text() -> String:
	var parts: Array = []
	for a in areas:
		var n := _alive_in(a)
		parts.append("%s %s" % [a["name"], "CLEAR" if n == 0 else str(n)])
	return "   ".join(parts)


## Ground point under the centre of the reticle (for the move order).
func reticle_ground_point() -> Variant:
	var cam: Camera3D = cam_rig.cam
	var r := reticle_rect()
	var c := r.get_center()
	var origin := cam.project_ray_origin(c)
	var dir := cam.project_ray_normal(c)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 200.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var p: Vector3 = hit["position"]
	p.y = 0.0
	return p


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
	if w["kind"] == "flash":
		_flashbang(pos, w)
		return
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


## Our rounds snapping past enemies pin them down. Fire from far away is
## much less frightening than fire from close up.
func suppress_enemies(from: Vector3, end: Vector3, amount: float) -> void:
	for t in targets:
		if not t.alive or not ("gunners" in t):
			continue
		var reach: float = 2.5 + t.radius
		var d := _seg_dist(from, end, t.aim_point())
		if d < reach:
			var range_f := clampf(1.3 - from.distance_to(t.aim_point()) / 50.0, 0.25, 1.0)
			for g in t.gunners:
				g.add_suppression(amount * range_f * (1.0 - d / reach))


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


## Flashbang: no damage. Every enemy in the radius who isn't shielded by a
## wall is blinded (can't shoot) and pinned; your own men too close get
## rattled. A blinding white flash fills the street.
func _flashbang(pos: Vector3, w: Dictionary) -> void:
	var radius: float = w["radius"]
	var space := get_world_3d().direct_space_state
	for t in targets:
		if not t.alive or not ("gunners" in t) or t.kind == "vehicle":
			continue
		var p: Vector3 = t.aim_point()
		if p.distance_to(pos) > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.4, 0), p, 1)
		if not space.intersect_ray(q).is_empty():
			continue   # behind solid cover: spared
		for g in t.gunners:
			g.add_suppression(1.0)
			g.blind(w["blind"])
	for s in squad.soldiers:
		var d: float = s.global_position.distance_to(pos)
		if d < 5.0:
			s.add_suppression(0.6 * (1.0 - d / 5.0))
	var e: Dictionary = _explosions[_explosion_idx]
	_explosion_idx = (_explosion_idx + 1) % _explosions.size()
	e["root"].global_position = pos
	var light: OmniLight3D = e["light"]
	light.visible = true
	light.light_color = Color(0.9, 0.95, 1.0)
	light.light_energy = 16.0
	if e["tween"]:
		e["tween"].kill()
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		light.visible = false
		light.light_color = Color(1.0, 0.6, 0.25))
	e["tween"] = tw
	var cam_d: float = cam_rig.cam.global_position.distance_to(pos)
	flash = 1.0
	fire_heat = minf(1.0, fire_heat + clampf(25.0 / maxf(cam_d, 1.0), 0.1, 0.5))


# ---------------------------------------------------------------- specials

## What a special goes at: the best enemy inside the reticle that the special
## can reach (rockets: vehicles first; grenades and flashbangs: infantry
## first), nearest the reticle centre; otherwise the ground under the reticle.
func special_target(kind: String, from := Vector3.INF, reach := INF) -> Dictionary:
	var cam: Camera3D = cam_rig.cam
	var centre := reticle_rect().get_center()
	var best: Node3D = null
	var best_score := INF
	for t in targets:
		if not t.alive or not in_reticle(t.aim_point()):
			continue
		if from != Vector3.INF and from.distance_to(t.global_position) > reach + 2.0:
			continue   # out of range for this special: don't pick it
		var score := 0.0
		if not debug_reticle_all and not cam.is_position_behind(t.aim_point()):
			score = cam.unproject_position(t.aim_point()).distance_to(centre)
		if t.kind == "vehicle":
			score += -10000.0 if kind == "rocket" else 10000.0
		if score < best_score:
			best_score = score
			best = t
	if kind == "flash" and best and best.kind == "vehicle":
		best = null
	if best:
		return {"target": best, "point": best.global_position}
	var p: Variant = reticle_ground_point()
	if p == null:
		var rng := RandomNumberGenerator.new()
		p = reticle_world_point(rng)
	return {"target": null, "point": p}


## Short special-weapon messages appear right under the special bar.
func special_msg(text: String, seconds := 1.2) -> void:
	_special_msg = text
	_special_msg_t = seconds
	_notice = text          # also kept as the last notice (tests read it)


func on_special_selected(kind: String, count: int) -> void:
	special_msg("%s SELECTED  -  %d LEFT" % [Weapons.SPECIALS[kind][1], count], 1.0)


func on_special_used(kind: String, _who: Node3D) -> void:
	var callout := {"frag": "FRAG OUT!", "flash": "FLASHBANG OUT!", "gl": "GRENADE AWAY!", "rocket": "ROCKET AWAY!"}
	special_msg(callout.get(kind, ""), 1.0)


func on_no_explosives() -> void:
	_no_explosives_t = 1.6
	special_msg("NO EXPLOSIVES LEFT", 1.6)


## Backblast / thump when a launcher fires.
func on_launch(at: Vector3, w: Dictionary) -> void:
	fire_heat = minf(1.0, fire_heat + (0.3 if w["kind"] == "rocket" else 0.15))
	flash = minf(1.0, flash + 0.6)
	_muzzle_light.global_position = at


func on_vehicle_destroyed(v: Node3D) -> void:
	notify("ENEMY %s DESTROYED" % v.vehicle_name)


## The sergeant's spoken order, shown with his hand signal.
func sgt_callout(text: String) -> void:
	notify(text, 1.4)


func notify(text: String, seconds := 4.0) -> void:
	_notice = text
	_notice_t = seconds


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
	if debug_reticle_all:
		return true
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




# ---------------------------------------------------------------- HUD

func _neon_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UI_FONT
	t.default_font_size = 15
	var glow := Color(NEON, 0.28)
	t.set_color("default_color", "RichTextLabel", NEON)
	t.set_color("font_outline_color", "RichTextLabel", Color(NEON, 0.22))
	t.set_constant("outline_size", "RichTextLabel", 4)
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
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # HUD never swallows clicks
	ui_root.add_child(panel)
	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(hud_label)

	# Controls reference, top-right. Hides itself after a while (F1 toggles)
	# so the screen stays clear for the fight.
	help_panel = PanelContainer.new()
	help_panel.add_theme_stylebox_override("panel", sb)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help_panel.offset_right = -12
	help_panel.offset_top = 12
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(help_panel)
	help_label = Label.new()
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.text = "WASD move   MOUSE aim   WHEEL zoom   E move to reticle   C / SPACE cover\n" \
		+ "LMB focus fire   RMB throw / fire special   1-4 pick special   X next special\n" \
		+ "F auto fire   T split / join teams   Q switch team   B bound   H hold + scout\n" \
		+ "ESC field manual (pause)   TAB reticle   G graphics   M map   R restart   F1 help"
	help_panel.add_child(help_label)

	# Squad health: one line per man (bottom right).
	var unit_panel := PanelContainer.new()
	unit_panel.add_theme_stylebox_override("panel", sb)
	unit_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	unit_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	unit_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	unit_panel.offset_right = -12
	unit_panel.offset_bottom = -12
	unit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(unit_panel)
	unit_label = _rich(13)
	unit_label.custom_minimum_size = Vector2(300, 0)
	unit_panel.add_child(unit_label)

	# Special-weapon selector, FPS style (bottom centre).
	var bar := PanelContainer.new()
	var bsb := sb.duplicate()
	bsb.bg_color = Color(0.0, 0.04, 0.0, 0.45)
	bar.add_theme_stylebox_override("panel", bsb)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -12
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bar)
	special_label = _rich(15)
	special_label.custom_minimum_size = Vector2(440, 0)
	bar.add_child(special_label)

	reticle_panel = ReticlePanelScript.new()
	reticle_panel.reticle = reticle
	ui_root.add_child(reticle_panel)

	manual = FieldManualScript.new()
	manual.ui_theme = ui_root.theme
	add_child(manual)


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", size)
	return r


const C_OK := "#73ff4d"
const C_WARN := "#ffbf33"
const C_BAD := "#ff4d33"
const C_DIM := "#3f6b35"


## Squad health panel: team, role, health bar, special and ammo for each man.
func _unit_text() -> String:
	var role_short := {"rifleman": "RIF ", "grenadier": "GREN", "anti_armor": "AT  "}
	var total: int = squad.soldiers.size() + squad.kia
	var lines: Array = ["UNIT  %d / %d%s" % [squad.soldiers.size(), total, ("   KIA %d" % squad.kia) if squad.kia > 0 else ""]]
	for s in squad.soldiers:
		var frac: float = clampf(s.hp / s.MAX_HP, 0.0, 1.0)
		var col := C_OK if frac > 0.6 else (C_WARN if frac > 0.3 else C_BAD)
		var n := ceili(frac * 10.0)
		var bar := "[color=%s]%s[/color][color=%s]%s[/color]" % [col, "#".repeat(n), C_DIM, "-".repeat(10 - n)]
		var team := ("ABCD"[s.team] + " ") if squad.split else ""
		var sp_name: String = Weapons.SPECIALS[s.special_kind][1]
		var sp := "[color=%s]%-5s %d[/color]" % [C_OK if s.special_ammo > 0 else C_DIM, sp_name, s.special_ammo]
		var flag := ""
		if s.pinned():
			flag = "  [color=%s]PINNED[/color]" % C_WARN
		elif s.hp < s.MAX_HP * 0.5:
			flag = "  [color=%s]WOUNDED[/color]" % C_WARN
		var rname: String = "SGT " if s.is_sergeant else role_short.get(s.role, "?   ")
		lines.append("%s%s %s  %s%s" % [team, rname, bar, sp, flag])
	return "\n".join(lines)


## Special selector: [1] FRAG 3   [2] FLASH 2 ... with the selected one lit.
func _special_text() -> String:
	var parts: Array = []
	for i in Weapons.SPECIAL_ORDER.size():
		var k: String = Weapons.SPECIAL_ORDER[i]
		var n: int = squad.special_count(k)
		var label := "%d %s %d" % [i + 1, Weapons.SPECIALS[k][1], n]
		if i == squad.selected_special:
			parts.append("[color=%s]> %s <[/color]" % ["#ffffff" if n > 0 else C_BAD, label])
		else:
			parts.append("[color=%s]  %s  [/color]" % [C_OK if n > 0 else C_DIM, label])
	var t := "[center]" + "  ".join(parts)
	if squad.total_specials() == 0:
		var blink := _no_explosives_t <= 0.0 or fmod(_no_explosives_t, 0.3) < 0.18
		t += "\n[color=%s]%s[/color]" % [C_BAD, "NO EXPLOSIVES LEFT" if blink else " "]
	elif _special_msg_t > 0.0:
		var warn := _special_msg.begins_with("TOO FAR") or _special_msg.ends_with("RELOADING") or _special_msg.contains("OUT  -")
		t += "\n[color=%s]%s[/color]" % [C_WARN if warn else "#ffffff", _special_msg]
	return t + "[/center]"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			help_panel.visible = not help_panel.visible
			_help_t = -1.0
		elif event.physical_keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.physical_keycode == KEY_G:
			toggle_quality()
		elif event.physical_keycode == KEY_M:
			next_map()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		if not reticle_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			manual.allow_release()     # opening the reticle panel frees the mouse on purpose
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

	_no_explosives_t = maxf(0.0, _no_explosives_t - delta)
	_special_msg_t = maxf(0.0, _special_msg_t - delta)
	if _help_t > 0.0:
		_help_t -= delta
		if _help_t <= 0.0:
			help_panel.visible = false
	if unit_label:
		unit_label.text = _unit_text()
		special_label.text = _special_text()
	if hud_label:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		_notice_t = maxf(0.0, _notice_t - delta)
		hud_label.text = "%s%s\n" % [map.NAME, "" if captured else "   (CLICK TO GRAB MOUSE)"] \
			+ "SQUAD   %s\n" % squad.status_text() \
			+ "UNIT    %s\n" % squad.roster_text() \
			+ "FIRE    %s%s\n" % [squad.fire_mode_text(), "   (auto fire ON)" if squad.auto_fire else ""] \
			+ "FIRE ON US  %s\n" % _supp_bar(squad.avg_suppression()) \
			+ "ENEMY   %s\n" % areas_text() \
			+ "HITS    %d     KILLS  %d     GFX %s" % [hits, kills, "LOW" if low_quality else "HIGH"] \
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
