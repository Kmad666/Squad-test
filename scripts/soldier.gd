extends CharacterBody3D
## One soldier: static block model (standing / crouched pose, no animation),
## pathfinds to its slot or cover spot, picks its own target and fires on its
## own rhythm. In cover it stays crouched and pops up to shoot over the box.

enum State { FOLLOW, TO_COVER, IN_COVER }

const BASE_SPEED := 5.6
const RANGE := 45.0
const EYE_HEIGHT := 1.45
const RAY_MASK := 1 | 4     # world + dummies (soldiers are layer 2)
const FIRE_HOLD := 0       # must match squad.gd
const FIRE_AT_WILL := 1
const FIRE_FOCUS := 2

static var _mats := {}

var squad: Node3D
var main: Node3D
var index := 0
var state := State.FOLLOW
var move_target := Vector3.ZERO
var cover_pos := Vector3.ZERO
var has_real_cover := false
var target: Node3D = null
var peeks: Array = []          # lean-out spots when behind tall cover
var peek_pos := Vector3.ZERO
var shots := 0

var _agent: NavigationAgent3D
var _upper: Node3D
var _legs: Node3D
var _flash: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _speed_mul := 1.0
var _moving := false
var _crouched := false
var _path_timer := 0.0
var _retarget_timer := 0.0
var _fire_timer := 0.0
var _burst_left := 0
var _peeking := false
var _peek_timer := 0.0
var _peek_age := 0.0
var _flash_timer := 0.0
var _cover_timer := 0.0


func _ready() -> void:
	_rng.seed = 1000 + index * 7919
	_speed_mul = _rng.randf_range(0.92, 1.08)
	_fire_timer = _rng.randf_range(0.2, 1.0)
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	_build_model()

	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.25
	_agent.radius = 0.35
	_agent.height = 1.8
	_agent.avoidance_enabled = false
	add_child(_agent)


# ---------------------------------------------------------------- model

static func _mat(key: String, color: Color, unshaded := false) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.28   # rain-soaked
		m.metallic_specular = 0.7
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = m
	return _mats[key]


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_model() -> void:
	var olive := _mat("olive", Color(0.36, 0.40, 0.24))
	var dark := _mat("dark", Color(0.22, 0.25, 0.16))
	var skin := _mat("skin", Color(0.80, 0.64, 0.50))
	var black := _mat("black", Color(0.08, 0.08, 0.08))
	var ring := _mat("ring", Color(0.06, 0.28, 0.36), true)
	var flash := _mat("flash", Color(1.0, 0.9, 0.4), true)

	var model := Node3D.new()
	model.name = "Model"
	add_child(model)

	_legs = Node3D.new()
	model.add_child(_legs)
	for side in [-1.0, 1.0]:
		_part(_legs, _box(Vector3(0.16, 0.86, 0.18)), dark, Vector3(0.11 * side, 0.43, 0))

	_upper = Node3D.new()
	model.add_child(_upper)
	_part(_upper, _box(Vector3(0.48, 0.62, 0.28)), olive, Vector3(0, 1.16, 0))          # torso
	_part(_upper, _box(Vector3(0.34, 0.42, 0.16)), dark, Vector3(0, 1.20, 0.2))          # backpack
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	_part(_upper, head, skin, Vector3(0, 1.6, -0.01))
	var helmet := SphereMesh.new()
	helmet.radius = 0.165
	helmet.height = 0.33
	_part(_upper, helmet, dark, Vector3(0, 1.66, 0), Vector3.ZERO, Vector3(1, 0.72, 1))
	_part(_upper, _box(Vector3(0.11, 0.11, 0.40)), olive, Vector3(0.27, 1.28, -0.16))   # right arm
	_part(_upper, _box(Vector3(0.11, 0.11, 0.46)), olive, Vector3(-0.17, 1.25, -0.24), Vector3(0, -0.5, 0))
	_part(_upper, _box(Vector3(0.07, 0.10, 0.85)), black, Vector3(0.12, 1.27, -0.38))   # rifle
	var fm := SphereMesh.new()
	fm.radius = 0.09
	fm.height = 0.18
	_flash = _part(_upper, fm, flash, Vector3(0.12, 1.27, -0.86))
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false

	var disc := CylinderMesh.new()
	disc.top_radius = 0.38
	disc.bottom_radius = 0.38
	disc.height = 0.02
	var d := _part(model, disc, ring, Vector3(0, 0.015, 0))
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _set_crouch(on: bool) -> void:
	if on == _crouched:
		return
	_crouched = on
	_legs.scale.y = 0.5 if on else 1.0
	_upper.position.y = -0.45 if on else 0.0


# ---------------------------------------------------------------- orders

func go_to_cover(pos: Vector3, real: bool, lean_spots: Array = []) -> void:
	cover_pos = pos
	peeks = lean_spots
	if not peeks.is_empty():
		peek_pos = peeks[0]
	has_real_cover = real
	state = State.TO_COVER
	_cover_timer = 0.0
	_peeking = false
	_path_timer = 0.0


func leave_cover() -> void:
	state = State.FOLLOW
	peeks = []
	_peeking = false
	_path_timer = 0.0


func _is_tall() -> bool:
	return not peeks.is_empty()


func is_settled() -> bool:
	return state == State.IN_COVER


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	var dest: Vector3 = move_target if state == State.FOLLOW else cover_pos
	if state == State.IN_COVER and _peeking and _is_tall():
		dest = peek_pos   # lean out past the edge of the crate
	_path_timer -= delta
	if _path_timer <= 0.0:
		_agent.target_position = dest
		_path_timer = 0.25

	var to_dest := dest - global_position
	to_dest.y = 0
	var dist := to_dest.length()

	# Hysteresis so soldiers settle instead of jittering on their spot.
	if state == State.FOLLOW:
		if _moving and dist < 0.3:
			_moving = false
		elif not _moving and dist > 0.7:
			_moving = true
	elif state == State.TO_COVER:
		_moving = true
		_cover_timer += delta
		if dist < 0.2 or _cover_timer > 7.0:
			state = State.IN_COVER
			_moving = false
			_peek_timer = _rng.randf_range(0.6, 1.6)
	else:
		_moving = dist > 0.2

	var vel := Vector3.ZERO
	if _moving:
		var next := _agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0
		if dir.length() < 0.05 or _agent.is_navigation_finished():
			dir = to_dest
		dir = dir.normalized()
		var spd := BASE_SPEED * _speed_mul
		if state == State.TO_COVER:
			spd *= 1.35        # scramble!
		elif dist > 5.0:
			spd *= 1.3         # catch up with the group
		spd *= clampf(dist / 1.0, 0.35, 1.0)
		vel = dir * spd

	if state != State.IN_COVER:
		vel += _separation() * 2.5

	velocity = Vector3(vel.x, -4.0, vel.z)
	move_and_slide()

	_update_combat(delta)
	_update_facing(delta, vel)


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for s in squad.soldiers:
		if s == self:
			continue
		var off: Vector3 = global_position - s.global_position
		off.y = 0
		var d := off.length()
		if d < 0.9 and d > 0.001:
			push += off / d * (1.0 - d / 0.9)
	return push


func _update_facing(delta: float, vel: Vector3) -> void:
	var look := Vector3.ZERO
	if target and is_instance_valid(target):
		look = target.global_position - global_position
	elif _has_aim:
		look = _aim_point - global_position
	elif state == State.IN_COVER:
		look = squad.threat_dir
	elif Vector2(vel.x, vel.z).length() > 0.4:
		look = vel
	look.y = 0
	if look.length() > 0.01:
		var yaw := atan2(-look.x, -look.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(10.0 * delta, 0.0, 1.0))


# ---------------------------------------------------------------- combat
# Fire modes come from the squad: HOLD (no fire), AT_WILL (each soldier picks
# any target he can see) and FOCUS (only targets inside the reticle; with none
# there, the squad pours fire into the spot under the reticle).

var _aim_point := Vector3.ZERO
var _has_aim := false
var _mode := 0


func _eye() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


## Where this soldier shoots from: his lean-out spot behind tall cover, else where he stands.
func _spot() -> Vector3:
	return peek_pos if (state != State.FOLLOW and _is_tall()) else global_position


func _has_los(d: Node3D, from_ground := Vector3.INF) -> bool:
	var origin: Vector3 = global_position if from_ground == Vector3.INF else from_ground
	var q := PhysicsRayQueryParameters3D.create(origin + Vector3(0, EYE_HEIGHT, 0), d.global_position + Vector3(0, 1.25, 0), RAY_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == d


func _point_los(from_ground: Vector3, p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from_ground + Vector3(0, EYE_HEIGHT, 0), p, RAY_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.6


## Behind tall cover, look for targets from each lean-out spot and remember
## the first side that has a shot.
func _find_target(focus_only: bool) -> Node3D:
	if state != State.FOLLOW and _is_tall():
		for p in peeks:
			var t := _find_target_from(p, focus_only)
			if t:
				peek_pos = p
				return t
		return null
	return _find_target_from(global_position, focus_only)


func _find_target_from(origin: Vector3, focus_only: bool) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for d in main.dummies:
		if not d.alive:
			continue
		if focus_only and not main.in_reticle(d.global_position + Vector3(0, 1.25, 0)):
			continue
		var dist: float = global_position.distance_to(d.global_position)
		if dist > RANGE or not _has_los(d, origin):
			continue
		var score: float = dist + _rng.randf_range(0.0, 8.0)   # each picks their own
		if score < best_score:
			best_score = score
			best = d
	return best


## Focus fire with no target in the reticle: pick a random spot inside the
## reticle's footprint in the world and saturate it.
func _pick_focus_point() -> void:
	_aim_point = main.reticle_world_point(_rng)
	_has_aim = false
	if state != State.FOLLOW and _is_tall():
		for p in peeks:
			if _point_los(p, _aim_point):
				peek_pos = p
				_has_aim = true
				return
	else:
		_has_aim = _point_los(global_position, _aim_point)


func _choose_aim() -> void:
	match _mode:
		FIRE_HOLD:
			target = null
			_has_aim = false
		FIRE_AT_WILL:
			_has_aim = false
			if target == null or not _has_los(target, _spot()) or _rng.randf() < 0.15:
				target = _find_target(false)
		FIRE_FOCUS:
			if target and not (main.in_reticle(target.global_position + Vector3(0, 1.25, 0)) and _has_los(target, _spot())):
				target = null
			if target == null:
				target = _find_target(true)
			if target:
				_has_aim = false
			else:
				_pick_focus_point()


func _update_combat(delta: float) -> void:
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash.visible = false

	if target and not target.alive:
		target = null
	var mode: int = squad.fire_mode()
	_retarget_timer -= delta
	if mode != _mode or _retarget_timer <= 0.0:
		_mode = mode
		_retarget_timer = _rng.randf_range(0.2, 0.4) if _mode == FIRE_FOCUS else _rng.randf_range(0.35, 0.7)
		_choose_aim()

	var has_shot := target != null or _has_aim
	var can_fire := false
	match state:
		State.FOLLOW:
			_set_crouch(false)
			can_fire = true
		State.TO_COVER:
			_set_crouch(false)
		State.IN_COVER:
			if not has_shot:
				_peeking = false
				_peek_timer = minf(_peek_timer, 0.5)
			_peek_timer -= delta
			if _peek_timer <= 0.0 and has_shot:
				_peeking = not _peeking
				var up_time := _rng.randf_range(1.0, 1.8) + (1.0 if _is_tall() else 0.0)  # leaning takes travel time
				_peek_timer = up_time if _peeking else _rng.randf_range(0.8, 2.0)
				_peek_age = 0.0
			_peek_age += delta
			_set_crouch(not _peeking)
			if _is_tall():
				var off := peek_pos - global_position
				off.y = 0
				can_fire = _peeking and off.length() < 0.3
			else:
				can_fire = _peeking and _peek_age > 0.25

	if not has_shot:
		can_fire = false

	_fire_timer -= delta
	if can_fire and _fire_timer <= 0.0:
		if _burst_left <= 0:
			_burst_left = _rng.randi_range(2, 4) if _mode == FIRE_AT_WILL else _rng.randi_range(3, 6)
		_shoot()
		_burst_left -= 1
		var pause := _rng.randf_range(0.5, 1.1) if _mode == FIRE_AT_WILL else _rng.randf_range(0.25, 0.55)
		_fire_timer = 0.1 if _burst_left > 0 else pause


func _shoot() -> void:
	var from := _eye() - Vector3(0, 0.15, 0)
	var aim: Vector3 = target.global_position + Vector3(0, 1.25, 0) if target else _aim_point
	var tight := 0.012 if _mode == FIRE_FOCUS else 0.02
	var spread := tight * from.distance_to(aim) + (0.3 if _moving else 0.0)
	aim += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.7, 0.7), _rng.randf_range(-1, 1)) * spread * 0.5
	var dir := (aim - from).normalized()
	var to := from + dir * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var c: Object = hit["collider"]
		var hit_dummy := c.has_method("take_hit")
		if hit_dummy:
			c.take_hit()
			main.hits += 1
		main.spawn_impact(end, hit["normal"], hit_dummy)
	shots += 1
	main.spawn_tracer(_flash.global_position, end)
	main.on_shot(_flash.global_position)
	_flash.visible = true
	_flash_timer = 0.05
