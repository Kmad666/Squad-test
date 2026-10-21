extends StaticBody3D
## Enemy test vehicle: low-poly armored personnel carrier.
## Heavy armor: small arms ricochet, grenades scratch it, rockets kill it.
## Burns when destroyed, then rebuilds after a while for more testing.

const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")

const MAX_HP := 360.0
const RESPAWN_TIME := 20.0

var main: Node3D
var kind := "vehicle"
var vehicle_name := "APC"
var armor_class := "HEAVY"
var size_factor := 1.7     # big target: easier to hit
var radius := 2.2          # how far a deliberate miss must land from the centre
var alive := true
var hp := MAX_HP

var _hull_mat: StandardMaterial3D
var _wreck_mat: StandardMaterial3D
var _hit_mat: StandardMaterial3D
var _parts: Array = []
var _label: Label3D
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
var _fire_light: OmniLight3D
var _flash_timer := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = 4      # same "targets" layer as the dummies
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.4, 6.0)
	col.shape = shape
	col.position.y = 1.2
	add_child(col)

	_hull_mat = StandardMaterial3D.new()
	_hull_mat.albedo_color = Color(0.22, 0.25, 0.2)
	_hull_mat.roughness = 0.22
	_hull_mat.metallic = 0.35
	_wreck_mat = StandardMaterial3D.new()
	_wreck_mat.albedo_color = Color(0.05, 0.045, 0.04)
	_wreck_mat.roughness = 0.6
	_hit_mat = StandardMaterial3D.new()
	_hit_mat.albedo_color = Color(1.0, 0.45, 0.2)
	_hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.04, 0.04, 0.04)
	tire.roughness = 0.35

	_add_box(Vector3(3.0, 1.3, 6.0), Vector3(0, 1.15, 0))            # hull
	_add_box(Vector3(2.6, 0.5, 1.2), Vector3(0, 1.55, 2.6), -0.5)     # sloped glacis (front faces +Z)
	_add_box(Vector3(1.6, 0.65, 1.9), Vector3(0, 2.12, -0.3))        # turret
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.07
	bm.bottom_radius = 0.09
	bm.height = 2.0
	barrel.mesh = bm
	barrel.material_override = _hull_mat
	barrel.position = Vector3(0, 2.15, 1.5)
	barrel.rotation.x = PI / 2.0
	add_child(barrel)
	_parts.append(barrel)
	for x in [-1.55, 1.55]:
		for z in [-2.0, 0.0, 2.0]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.5
			wm.bottom_radius = 0.5
			wm.height = 0.35
			w.mesh = wm
			w.material_override = tire
			w.position = Vector3(x, 0.5, z)
			w.rotation.z = PI / 2.0
			add_child(w)

	_label = Label3D.new()
	_label.font = UI_FONT
	_label.font_size = 44
	_label.outline_size = 10
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.42, 0.25)
	_label.outline_modulate = Color(0.1, 0.02, 0.0, 0.8)
	_label.position = Vector3(0, 4.0, 0)
	_label.no_depth_test = true
	add_child(_label)
	_update_label()

	_fire = _make_emitter(Color(1.4, 0.55, 0.15), 40, 0.7, 0.45, Vector3(0, 3.5, 0))
	_smoke = _make_emitter(Color(0.08, 0.08, 0.08, 0.6), 30, 2.4, 0.9, Vector3(0, 1.6, 0))
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.5, 0.2)
	_fire_light.omni_range = 12.0
	_fire_light.position = Vector3(0, 2.6, 0)
	_fire_light.visible = false
	add_child(_fire_light)


func _add_box(size: Vector3, pos: Vector3, tilt := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _hull_mat
	mi.position = pos
	mi.rotation.x = tilt
	add_child(mi)
	_parts.append(mi)


func _make_emitter(color: Color, amount: int, life: float, size: float, gravity: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.color = color
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.0, 0.3, 2.0)
	p.position = Vector3(0, 2.0, 0)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = gravity
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.2
	add_child(p)
	return p


func aim_point() -> Vector3:
	return global_position + Vector3(0, 1.3, 0)


func _update_label() -> void:
	if alive:
		_label.text = "ENEMY VEHICLE\n%s  ARMOR: %s\nHP %d / %d\nWEAK TO: ROCKETS" % [vehicle_name, armor_class, ceili(hp), int(MAX_HP)]
	else:
		_label.text = "ENEMY VEHICLE\n%s  DESTROYED" % vehicle_name


## Returns true if the hit actually hurt (false = ricochet off the armor).
func take_damage(_soft: float, armor_dmg: float) -> bool:
	if not alive:
		return false
	if armor_dmg <= 0.0:
		return false
	hp -= armor_dmg
	_flash(true)
	if hp <= 0.0:
		_destroy()
	_update_label()
	return true


func _flash(on: bool) -> void:
	for p in _parts:
		p.material_override = _hit_mat if on else (_hull_mat if alive else _wreck_mat)
	if on:
		_flash_timer = 0.07


func _destroy() -> void:
	alive = false
	hp = 0.0
	for p in _parts:
		p.material_override = _wreck_mat
	_fire.emitting = true
	_smoke.emitting = true
	_fire_light.visible = true
	if main:
		main.on_vehicle_destroyed(self)
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_rebuild)


func _rebuild() -> void:
	alive = true
	hp = MAX_HP
	for p in _parts:
		p.material_override = _hull_mat
	_fire.emitting = false
	_smoke.emitting = false
	_fire_light.visible = false
	_update_label()


func _process(delta: float) -> void:
	_t += delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash(false)
	if _fire_light.visible:
		_fire_light.light_energy = 2.2 + sin(_t * 23.0) * 0.6 + sin(_t * 7.0) * 0.4
