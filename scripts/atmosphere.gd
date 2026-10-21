extends Node3D
## Night mood: dark, foggy, raining, with harsh light sources that bloom and
## glare like they're blinding the lens. Builds:
##   - dark environment with fog, ACES tonemap and strong bloom (glow)
##   - a floodlight on a pole aimed at the target dummies
##   - a sodium street lamp over the cover area
##   - glare sprites + anamorphic streaks on each light, plus visible beams
##   - rain streaks and ground splashes that follow the camera

var cam_rig: Node3D
var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _glares: Array = []   # [{node, dir, base}] for view-dependent glare


func _ready() -> void:
	_build_environment()
	# Floodlight beside the range, aimed at the middle of the dummies.
	_build_light_pole(Vector3(14, 0, -21), 7.5, Vector3(-3, 0.8, -36),
		Color(0.85, 0.92, 1.0), 16.0, 30.0, 45.0, true, 3.2)
	# Street lamp hanging over the cover crates.
	_build_light_pole(Vector3(-4.5, 0, 6.5), 5.5, Vector3(-1.5, 0, 5.5),
		Color(1.0, 0.68, 0.36), 9.0, 62.0, 16.0, true, 2.2)
	_build_rain()


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.13, 0.18)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1

	# Bloom: anything bright bleeds light across the screen.
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_strength = 1.15
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4, 5] else 0.0)

	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.09, 0.12)
	env.fog_density = 0.022
	env.fog_sky_affect = 1.0

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Faint cold moonlight so silhouettes still read.
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.12
	moon.shadow_enabled = false
	add_child(moon)


# ---------------------------------------------------------------- lights

func _metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.13, 0.14)
	m.roughness = 0.2
	m.metallic = 0.6
	return m


## A pole with a lamp head at `height`, a SpotLight aimed at `aim`, a glowing
## lens, a glare sprite and a soft visible beam.
func _build_light_pole(base: Vector3, height: float, aim: Vector3, color: Color,
		energy: float, angle_deg: float, light_range: float, shadows: bool, glare_size: float) -> void:
	var metal := _metal()

	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.1
	pm.height = height
	pole.mesh = pm
	pole.material_override = metal
	pole.position = base + Vector3(0, height * 0.5, 0)
	add_child(pole)

	var body := StaticBody3D.new()  # so the squad can't walk through the pole
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.15
	cyl.height = height
	cs.shape = cyl
	body.position = pole.position
	body.add_child(cs)
	add_child(body)

	var head_pos := base + Vector3(0, height, 0)
	var dir := (aim - head_pos).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	var head_basis := Basis.looking_at(dir, up)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.7, 0.4, 0.45)
	head.mesh = hm
	head.material_override = metal
	head.global_transform = Transform3D(head_basis, head_pos)
	add_child(head)

	# Blown-out lens: emissive well above the bloom threshold.
	var lens := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.6, 0.32, 0.04)
	lens.mesh = lm
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = Color.BLACK
	lens_mat.emission_enabled = true
	lens_mat.emission = color
	lens_mat.emission_energy_multiplier = 9.0
	lens.material_override = lens_mat
	lens.global_transform = Transform3D(head_basis, head_pos + dir * 0.24)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lens)

	var spot := SpotLight3D.new()
	spot.light_color = color
	spot.light_energy = energy
	spot.spot_angle = angle_deg
	spot.spot_range = light_range
	spot.spot_attenuation = 0.8
	spot.light_specular = 1.6       # strong highlights on the wet surfaces
	spot.shadow_enabled = shadows
	spot.global_transform = Transform3D(head_basis, head_pos + dir * 0.3)
	add_child(spot)

	# Soft fill so the light "gives off" ambient light around its pool.
	var fill := OmniLight3D.new()
	fill.light_color = color
	fill.light_energy = energy * 0.06
	fill.omni_range = light_range * 0.6
	fill.position = head_pos + dir * 1.0
	fill.shadow_enabled = false
	add_child(fill)

	_build_beam(head_pos + dir * 0.3, dir, color, minf(light_range * 0.8, 18.0), angle_deg)
	_build_glare(head_pos + dir * 0.35, dir, color, glare_size)


func _build_beam(origin: Vector3, dir: Vector3, color: Color, length: float, angle_deg: float) -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 beam_col : source_color;
uniform float strength = 0.08;
uniform float half_len = 5.0;
varying float h;
void vertex() { h = VERTEX.y; }
void fragment() {
	float t = clamp(0.5 - h / (2.0 * half_len), 0.0, 1.0);   // 0 at the lamp, 1 at the end
	float facing = abs(dot(NORMAL, VIEW));                     // soft edges
	ALBEDO = beam_col;
	ALPHA = strength * (1.0 - t) * (1.0 - t) * pow(facing, 1.5);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("beam_col", color)
	mat.set_shader_parameter("half_len", length * 0.5)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 0.2 + tan(deg_to_rad(angle_deg) * 0.85) * length
	cone.height = length
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false

	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := -dir
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, z), origin + dir * length * 0.5)
	add_child(mi)


func _glare_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.08, Color(1, 1, 1, 0.85))
	g.add_point(0.3, Color(1, 1, 1, 0.18))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _glare_mat(color: Color, tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	m.no_depth_test = false
	m.albedo_texture = tex
	m.albedo_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 1.0)
	m.render_priority = 10
	return m


## Glare halo + horizontal anamorphic streak at the lamp. Brightens when the
## lamp points toward the camera.
func _build_glare(pos: Vector3, dir: Vector3, color: Color, size: float) -> void:
	var tex := _glare_texture()
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	halo.mesh = q
	halo.material_override = _glare_mat(color, tex)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)

	var streak := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(size * 4.5, size * 0.12)
	streak.mesh = sq
	streak.material_override = _glare_mat(color, tex)
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(streak)

	_glares.append({"halo": halo, "streak": streak, "dir": dir, "pos": pos, "color": color})


# ---------------------------------------------------------------- rain

func _build_rain() -> void:
	# Falling streaks.
	_rain = GPUParticles3D.new()
	_rain.amount = 2600
	_rain.lifetime = 1.0
	_rain.preprocess = 1.0
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 0.5, 24)
	pm.direction = Vector3(0.06, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -4, 0)
	_rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.022, 0.75)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rm.albedo_color = Color(0.72, 0.8, 0.9, 0.22)
	streak.material = rm
	_rain.draw_pass_1 = streak
	add_child(_rain)

	# Little splashes popping off the ground.
	_splash = GPUParticles3D.new()
	_splash.amount = 600
	_splash.lifetime = 0.3
	_splash.local_coords = false
	_splash.visibility_aabb = AABB(Vector3(-25, -2, -25), Vector3(50, 4, 50))
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(18, 0.0, 18)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 35.0
	sm.initial_velocity_min = 1.2
	sm.initial_velocity_max = 2.4
	sm.gravity = Vector3(0, -12, 0)
	sm.scale_min = 0.5
	sm.scale_max = 1.0
	_splash.process_material = sm
	var dot := QuadMesh.new()
	dot.size = Vector2(0.05, 0.05)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_color = Color(0.8, 0.88, 1.0, 0.45)
	dot.material = dm
	_splash.draw_pass_1 = dot
	add_child(_splash)


func _process(_delta: float) -> void:
	if cam_rig == null or cam_rig.cam == null:
		return
	var cam: Camera3D = cam_rig.cam
	var cpos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized() * 10.0
	_rain.global_position = Vector3(cpos.x + fwd.x, cpos.y + 10.0, cpos.z + fwd.z)
	_splash.global_position = Vector3(cpos.x + fwd.x, 0.03, cpos.z + fwd.z)

	# Glare gets harsher the more directly a lamp points at the camera.
	for g in _glares:
		var to_cam: Vector3 = (cpos - g["pos"]).normalized()
		var facing: float = clampf(to_cam.dot(g["dir"]), 0.0, 1.0)
		var k: float = 0.45 + 1.4 * facing * facing
		var col: Color = g["color"]
		g["halo"].material_override.albedo_color = Color(col.r * 1.6 * k, col.g * 1.6 * k, col.b * 1.6 * k, 1.0)
		g["streak"].material_override.albedo_color = Color(col.r * k, col.g * k, col.b * k, 1.0)
