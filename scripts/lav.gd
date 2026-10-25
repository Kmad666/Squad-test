extends AnimatableBody3D
## Friendly LAV-25: eight wheels, a turret with a 25mm chain gun. Part of the
## unit. While it's WITH the unit it drives to the unit's point (the front),
## and the infantry stack up behind it in a tight group, on the side away from
## the enemy, leaning out past the hull to shoot (squad.gd places them).
## Z sends it to hold where it is (overwatch) or calls it back.
##
## Small arms bounce off it; enemy cannon shells hurt it. It blocks bullets
## and sight lines both ways, so the men behind it are safe until they lean out.
## Front faces local +Z. Drives on its own navigation map (sized for a vehicle).

const Weapons = preload("res://scripts/weapons.gd")

const HALF_W := 1.3            # hull half-width (m)
const HALF_L := 3.2            # hull half-length
const MAX_HP := 300.0
const SPEED_WITH := 4.6        # with the infantry: walking pace, they keep up
const SPEED_ALONE := 8.0
const REVERSE := 2.8
const ACCEL := 2.6
const BRAKE := 6.0
const PIVOT := 0.5             # rad/s it can swing round at a crawl
const TURN_RADIUS := 6.0
const ARRIVE := 1.6
const WHEEL_R := 0.55

var main: Node3D
var squad: Node3D
var kind := "lav"
var alive := true
var dead: bool:
	get: return not alive
var hp := MAX_HP
var together := true           # with the unit (Z toggles)
var goal := Vector3.ZERO       # where it drives (set by the squad every frame)
var speed_cap := 1.0           # the squad slows it if the men fall behind
var speed := 0.0               # signed: < 0 reversing
var nav_map := RID()
var target: Node3D = null
var shots := 0
var hits := 0

var _rng := RandomNumberGenerator.new()
var _path := PackedVector3Array()
var _path_t := 0.0
var _visual: Node3D
var _turret: Node3D
var _gun: Node3D               # elevation pivot
var _barrel: Node3D
var _muzzle: Node3D
var _flash: MeshInstance3D
var _wheels: Array = []
var _steer: Array = []          # pivots of the front four wheels
var _parts: Array = []          # every hull mesh (turned to the wreck colour)
var _wreck_mat: StandardMaterial3D
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
var _fire_light: OmniLight3D
var _fire_t := 0.0
var _burst_left := 0
var _retarget := 0.0
var _flash_t := 0.0
var _recoil := 0.0
var _aim_point := Vector3.INF
var _last_speed := 0.0
var _t := 0.0


func _ready() -> void:
	_rng.randomize()
	collision_layer = 1        # world: blocks bullets, sight and people like a wall
	collision_mask = 1
	sync_to_physics = false
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_W * 2.0, 2.2, HALF_L * 2.0)
	col.shape = shape
	col.position.y = 0.45 + 1.1         # clear of the ground: the wheels don't collide
	add_child(col)
	var tcol := CollisionShape3D.new()   # turret
	var ts := BoxShape3D.new()
	ts.size = Vector3(1.7, 0.6, 1.8)
	tcol.shape = ts
	tcol.position = Vector3(0, 2.95, 0.2)
	add_child(tcol)
	_build_model()


# ---------------------------------------------------------------- model

const CAMO_SHADER := """
shader_type spatial;
// USMC woodland: green base, brown and black blotches, a little grime.
uniform float scale = 1.5;
varying vec3 lpos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
vec3 to_lin(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#endif
}
void vertex() { lpos = VERTEX; }
void fragment() {
	vec3 p = lpos * scale;
	float a = noise(p) * 0.65 + noise(p * 2.3) * 0.35;
	float b = noise(p + 17.3) * 0.65 + noise(p * 2.1 + 4.0) * 0.35;
	vec3 c = vec3(0.24, 0.29, 0.17);                         // green
	c = mix(c, vec3(0.30, 0.23, 0.14), smoothstep(0.55, 0.58, a));   // brown
	c = mix(c, vec3(0.07, 0.075, 0.06), smoothstep(0.66, 0.69, b));  // black
	c *= 0.9 + 0.15 * noise(lpos * 6.0);
	ALBEDO = to_lin(c);
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
"""


func _build_model() -> void:
	var camo := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CAMO_SHADER
	camo.shader = sh
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.1, 0.08)
	dark.roughness = 0.7
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.035, 0.035, 0.035)
	rubber.roughness = 0.9
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.08, 0.09)
	glass.roughness = 0.1
	glass.metallic_specular = 0.9
	var panel := StandardMaterial3D.new()        # VS-17 air recognition panel: friendly
	panel.albedo_color = Color(1.0, 0.38, 0.22)
	panel.roughness = 0.9
	_wreck_mat = StandardMaterial3D.new()
	_wreck_mat.albedo_color = Color(0.05, 0.045, 0.04)
	_wreck_mat.roughness = 0.7

	_visual = Node3D.new()
	add_child(_visual)
	var v := _visual
	# Hull: belly, sides, deck, the long sloped nose and the boxy rear.
	_box(v, Vector3(2.2, 0.5, 5.8), Vector3(0, 0.82, -0.05), camo)
	_box(v, Vector3(2.6, 0.75, 5.5), Vector3(0, 1.38, -0.35), camo)
	_box(v, Vector3(2.25, 0.36, 4.7), Vector3(0, 1.9, -0.7), camo)
	_box(v, Vector3(2.5, 0.22, 2.15), Vector3(0, 1.52, 2.55), camo, Vector3(0.42, 0, 0))     # glacis
	_box(v, Vector3(2.2, 0.2, 1.2), Vector3(0, 0.92, 3.05), camo, Vector3(-0.75, 0, 0))     # lower nose
	_box(v, Vector3(2.3, 0.08, 0.55), Vector3(0, 1.02, 3.42), dark, Vector3(-0.2, 0, 0))     # trim vane
	for s in [-1.0, 1.0]:
		_box(v, Vector3(0.25, 0.42, 4.6), Vector3(s * 1.24, 1.92, -0.7), camo, Vector3(0, 0, s * 0.35))   # sloped upper sides
		_box(v, Vector3(0.3, 0.32, 1.4), Vector3(s * 1.43, 1.55, -1.6), dark)          # stowage bins
		_box(v, Vector3(0.22, 0.14, 0.12), Vector3(s * 0.85, 1.4, 3.42), glass)         # headlights
		_box(v, Vector3(0.95, 1.05, 0.08), Vector3(s * 0.55, 1.42, -3.12), camo)        # rear doors
		_box(v, Vector3(0.1, 0.18, 0.06), Vector3(s * 0.55, 1.42, -3.18), dark)         # door handles
		_box(v, Vector3(0.12, 0.6, 0.6), Vector3(s * 1.36, 0.95, -3.0), rubber)         # mud flaps
	_box(v, Vector3(0.5, 0.25, 0.6), Vector3(0.75, 2.12, 2.1), dark)       # driver's hatch
	_box(v, Vector3(0.3, 0.12, 0.12), Vector3(0.75, 2.22, 2.42), glass)    # periscopes
	_box(v, Vector3(0.18, 0.18, 0.7), Vector3(-1.05, 1.95, -2.2), dark)    # exhaust
	_box(v, Vector3(1.4, 0.03, 1.0), Vector3(0, 2.1, -2.3), panel)         # VS-17 panel on the rear deck
	# Wheels: four axles, the front two steer.
	for z in [2.05, 0.95, -0.95, -2.05]:
		for s in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(s * 1.28, WHEEL_R, z)
			v.add_child(pivot)
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = WHEEL_R
			wm.bottom_radius = WHEEL_R
			wm.height = 0.42
			wm.radial_segments = 14
			w.mesh = wm
			w.material_override = rubber
			w.rotation.z = PI / 2.0
			pivot.add_child(w)
			var hub := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.24
			hm.bottom_radius = 0.24
			hm.height = 0.44
			hm.radial_segments = 6
			hub.mesh = hm
			hub.material_override = dark
			w.add_child(hub)
			_wheels.append(w)
			if z > 0.0:
				_steer.append(pivot)
	# Turret: base, sloped cheeks, mantlet, the 25mm and a coax, smoke dischargers.
	_turret = Node3D.new()
	_turret.position = Vector3(0, 2.08, 0.2)
	v.add_child(_turret)
	_box(_turret, Vector3(1.75, 0.5, 1.9), Vector3(0, 0.25, -0.1), camo)
	_box(_turret, Vector3(1.4, 0.3, 1.5), Vector3(0, 0.62, -0.15), camo)
	_box(_turret, Vector3(1.6, 0.3, 0.5), Vector3(0, 0.38, 0.95), camo, Vector3(-0.5, 0, 0))
	_box(_turret, Vector3(0.45, 0.3, 0.5), Vector3(-0.42, 0.9, -0.45), dark)    # commander's hatch / sight
	_box(_turret, Vector3(0.35, 0.28, 0.35), Vector3(0.45, 0.88, 0.25), dark)   # gunner's sight
	_box(_turret, Vector3(0.4, 0.15, 0.06), Vector3(0.45, 0.92, 0.43), glass)
	for s in [-1.0, 1.0]:
		for k in 4:
			var tube := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.055
			tm.bottom_radius = 0.055
			tm.height = 0.3
			tm.radial_segments = 6
			tube.mesh = tm
			tube.material_override = dark
			tube.position = Vector3(s * (0.75 + 0.02 * k), 0.45 + 0.1 * (k % 2), 0.75 - 0.12 * (k / 2))
			tube.rotation = Vector3(-1.0, 0, s * -0.5)
			_turret.add_child(tube)
	_gun = Node3D.new()
	_gun.position = Vector3(0.0, 0.42, 1.05)
	_turret.add_child(_gun)
	_box(_gun, Vector3(0.36, 0.3, 0.45), Vector3(0, 0, 0.1), dark)              # mantlet
	_barrel = Node3D.new()
	_gun.add_child(_barrel)
	_cyl(_barrel, 0.075, 0.6, Vector3(0, 0, 0.55), dark)                          # barrel shroud
	_cyl(_barrel, 0.045, 2.0, Vector3(0, 0, 1.6), dark)                           # 25mm barrel
	_cyl(_barrel, 0.06, 0.2, Vector3(0, 0, 2.55), dark)                           # muzzle brake
	_cyl(_gun, 0.03, 0.6, Vector3(0.28, -0.05, 0.5), dark)                        # coax MG
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, 2.75)
	_barrel.add_child(_muzzle)
	_flash = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.22
	fm.height = 0.44
	_flash.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.7, 0.3)
	fmat.disable_fog = true
	_flash.material_override = fmat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_muzzle.add_child(_flash)
	# Antenna whips at the back.
	for s in [-1.0, 1.0]:
		var a := MeshInstance3D.new()
		var am := CylinderMesh.new()
		am.top_radius = 0.008
		am.bottom_radius = 0.015
		am.height = 2.6
		am.radial_segments = 4
		a.mesh = am
		a.material_override = dark
		a.position = Vector3(s * 0.95, 3.4, -2.75)
		a.rotation.x = -0.12
		v.add_child(a)

	_fire = _emitter(Color(1.4, 0.55, 0.15), 40, 0.7, 0.45, Vector3(0, 3.5, 0))
	_smoke = _emitter(Color(0.08, 0.08, 0.08, 0.6), 30, 2.4, 0.9, Vector3(0, 1.6, 0))
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.5, 0.2)
	_fire_light.omni_range = 12.0
	_fire_light.position = Vector3(0, 2.6, 0)
	_fire_light.visible = false
	add_child(_fire_light)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	_parts.append(mi)
	return mi


func _cyl(parent: Node3D, r: float, length: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = PI / 2.0
	parent.add_child(mi)
	_parts.append(mi)


func _emitter(color: Color, amount: int, life: float, size: float, gravity: Vector3) -> CPUParticles3D:
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
	p.emission_box_extents = Vector3(1.0, 0.3, 2.2)
	p.position = Vector3(0, 2.2, 0)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = gravity
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.2
	add_child(p)
	return p


# ---------------------------------------------------------------- queries

func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


## Enemy gunners treat it like a soldier: something to see and shoot at.
func exposed_point() -> Vector3:
	return global_position + Vector3(0, 1.6, 0)


func aim_point() -> Vector3:
	return exposed_point()


func is_moving() -> bool:
	return absf(speed) > 0.5


func is_in_cover() -> bool:
	return false


func is_settled() -> bool:
	return absf(speed) < 0.3


## Hull corners and faces in its own frame, grown by `pad`.
func local_rect(pad: float) -> Rect2:
	return Rect2(-HALF_W - pad, -HALF_L - pad, (HALF_W + pad) * 2.0, (HALF_L + pad) * 2.0)


# ---------------------------------------------------------------- driving

func _physics_process(delta: float) -> void:
	_t += delta
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	if not alive:
		if _fire_light.visible:
			_fire_light.light_energy = 2.2 + sin(_t * 23.0) * 0.6 + sin(_t * 7.0) * 0.4
		return
	_drive(delta)
	_fight(delta)


func _waypoint() -> Vector3:
	_path_t -= get_physics_process_delta_time()
	if _path_t <= 0.0:
		_path_t = 0.5
		_path = PackedVector3Array()
		if nav_map.is_valid():
			_path = NavigationServer3D.map_get_path(nav_map, global_position, goal, true)
	var pos := global_position
	for p in _path:
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d > 2.0:
			return Vector3(p.x, 0, p.z)
	return goal


func _drive(delta: float) -> void:
	var pos := global_position
	var to_goal := goal - pos
	to_goal.y = 0
	var d := to_goal.length()
	var want := 0.0
	var heading := rotation.y
	if d > ARRIVE:
		var wp := _waypoint()
		var v := wp - pos
		v.y = 0
		if v.length() < 0.1:
			v = to_goal
		var want_yaw := atan2(v.x, v.z)
		var off := angle_difference(rotation.y, want_yaw)
		var top := (SPEED_WITH if together else SPEED_ALONE) * speed_cap
		if absf(off) > 1.9 and d < 14.0:
			# Close and behind: back up rather than turn round.
			heading = atan2(-v.x, -v.z)
			var back := angle_difference(rotation.y, heading)
			want = -REVERSE * clampf(d / 3.0, 0.3, 1.0) * maxf(0.0, cos(back)) * speed_cap
		else:
			heading = want_yaw
			var align := maxf(0.0, cos(off))
			want = top * clampf(d / 4.0, 0.25, 1.0) * align * align
	var rate := maxf(PIVOT, absf(speed) / TURN_RADIUS)
	var turn := clampf(angle_difference(rotation.y, heading), -rate * delta, rate * delta)
	rotation.y += turn
	var acc := ACCEL if absf(want) > absf(speed) and signf(want) == signf(speed) or speed == 0.0 else BRAKE
	speed = move_toward(speed, want, acc * delta)
	if absf(speed) > 0.001:
		var motion := forward() * speed * delta
		var hit := move_and_collide(motion)
		if hit:
			var rest := hit.get_remainder().slide(hit.get_normal())
			rest.y = 0
			move_and_collide(rest)
			speed *= 0.6
	global_position.y = 0.0
	# Wheels roll, the front ones steer, the body pitches a little on the throttle.
	for w in _wheels:
		w.rotation.x += speed * delta / WHEEL_R
	var steer := clampf(turn / maxf(delta, 0.0001) * 0.9, -0.45, 0.45) * signf(speed if absf(speed) > 0.1 else 1.0)
	for i in _steer.size():
		_steer[i].rotation.y = lerp_angle(_steer[i].rotation.y, steer * (1.0 if i < 2 else 0.55), clampf(8.0 * delta, 0.0, 1.0))
	var accel := (speed - _last_speed) / maxf(delta, 0.0001)
	_last_speed = speed
	_visual.rotation.x = lerpf(_visual.rotation.x, clampf(-accel * 0.012, -0.04, 0.04), clampf(4.0 * delta, 0.0, 1.0))


# ---------------------------------------------------------------- gunnery

func _fight(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 1.5)
	_barrel.position.z = -_recoil
	var mode: int = squad.lav_fire_mode() if squad else 0
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = _rng.randf_range(0.3, 0.6)
		_choose(mode)
	var look := Vector3.INF
	if target:
		look = target.aim_point()
	elif _aim_point != Vector3.INF:
		look = _aim_point
	var aligned := _lay_gun(look, delta)
	_fire_t -= delta
	if look == Vector3.INF or not aligned or _fire_t > 0.0:
		return
	if _burst_left <= 0:
		_burst_left = _rng.randi_range(Weapons.LAV_25MM["burst_min"], Weapons.LAV_25MM["burst_max"])
	_shoot(look)
	_burst_left -= 1
	var w: Dictionary = Weapons.LAV_25MM
	_fire_t = w["cycle"] if _burst_left > 0 else _rng.randf_range(w["pause_min"], w["pause_max"]) * (0.7 if mode == 2 else 1.0)


## HOLD (0): nothing. AT WILL (1): the nearest thing it can see, armor first.
## FOCUS (2): what's inside the reticle, else hose the spot under it.
func _choose(mode: int) -> void:
	_aim_point = Vector3.INF
	if mode == 0:
		target = null
		return
	if target and (not target.alive or not _can_see(target) or (mode == 2 and not main.in_reticle(target.aim_point()))):
		target = null
	if target and _rng.randf() > 0.15:
		return
	var w: Dictionary = Weapons.LAV_25MM
	var best: Node3D = null
	var best_s := INF
	for t in main.targets:
		if not t.alive:
			continue
		if mode == 2 and not main.in_reticle(t.aim_point()):
			continue
		var dist := global_position.distance_to(t.global_position)
		if dist > w["max"] or not _can_see(t):
			continue
		var s := dist + _rng.randf_range(0.0, 10.0) + (-40.0 if t.kind == "vehicle" else 0.0)
		if s < best_s:
			best_s = s
			best = t
	target = best
	if target == null and mode == 2:
		var p: Vector3 = main.reticle_world_point(_rng)
		if global_position.distance_to(p) <= w["max"] and _point_clear(p):
			_aim_point = p


func _gun_origin() -> Vector3:
	return _turret.global_position + Vector3(0, 0.45, 0)


func _can_see(t: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_gun_origin(), t.aim_point(), 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == t


func _point_clear(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_gun_origin(), p, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 1.0


## Traverse the turret and elevate the gun toward `p` (or back to the
## threat side when there's nothing). True once it's laid on.
func _lay_gun(p: Vector3, delta: float) -> bool:
	var want_yaw := 0.0
	var want_el := 0.0
	if p == Vector3.INF:
		var tdir: Vector3 = squad.lav_watch_dir() if squad else forward()
		var l := global_transform.basis.inverse() * tdir
		want_yaw = atan2(l.x, l.z)
	else:
		var l := global_transform.affine_inverse() * p - _turret.position
		want_yaw = atan2(l.x, l.z)
		var flat := Vector2(l.x, l.z).length()
		want_el = clampf(atan2(l.y - 0.42, flat), -0.15, 0.9)
	var dy := angle_difference(_turret.rotation.y, want_yaw)
	_turret.rotation.y += clampf(dy, -1.4 * delta, 1.4 * delta)
	_gun.rotation.x = move_toward(_gun.rotation.x, -want_el, 0.8 * delta)
	return absf(angle_difference(_turret.rotation.y, want_yaw)) < 0.06 and absf(_gun.rotation.x + want_el) < 0.05


func _shoot(look: Vector3) -> void:
	var w: Dictionary = Weapons.LAV_25MM
	var from := _muzzle.global_position
	var aim := look
	if target:
		var chance := Weapons.hit_chance(w, target, from.distance_to(look), false, squad.lav_fire_mode() == 2, _burst_left < w["burst_max"])
		if _rng.randf() >= chance:
			var dir := (look - from).normalized()
			var side := dir.cross(Vector3.UP).normalized()
			aim = look + (side * _rng.randf_range(-1.0, 1.0) + Vector3.UP * _rng.randf_range(-0.4, 0.8)).normalized() * (target.radius + _rng.randf_range(0.6, 2.2))
	else:
		aim += Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	var to := from + (aim - from).normalized() * 160.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var c: Object = hit["collider"]
		if c.has_method("take_damage") and c.take_damage(w["soft"], w["armor"]):
			hits += 1
			main.hits += 1
		_burst_at(end, c as Node3D, hit["normal"])
	main.suppress_enemies(from, end, w["suppress"])
	main.spawn_tracer(from, end)
	main.on_shot(from)
	shots += 1
	_flash.visible = true
	_flash_t = 0.06
	_recoil = 0.18


## 25mm HE: a small burst that catches anyone right next to the strike.
func _burst_at(p: Vector3, direct: Node3D, n: Vector3) -> void:
	var w: Dictionary = Weapons.LAV_25MM
	main.spawn_impact(p, n, true)
	main.spawn_impact(p + Vector3(0, 0.2, 0), Vector3.UP, true, Color(1.2, 0.6, 0.2))
	for t in main.targets:
		if t == direct or not t.alive or t.kind == "vehicle":
			continue
		var d: float = t.aim_point().distance_to(p)
		if d < w["radius"]:
			t.take_damage(w["soft"] * 0.5 * (1.0 - d / w["radius"]), 0.0)


# ---------------------------------------------------------------- damage

## Enemy cannon shells (squad soldiers' and enemy small arms only spark off it).
func armor_hit(dmg: float) -> void:
	if not alive or dmg <= 0.0:
		return
	hp -= dmg
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	alive = false
	hp = 0.0
	together = false
	target = null
	speed = 0.0
	for p in _parts:
		p.material_override = _wreck_mat
	_fire.emitting = true
	_smoke.emitting = true
	_fire_light.visible = true
	if main:
		main.on_lav_destroyed(self)
