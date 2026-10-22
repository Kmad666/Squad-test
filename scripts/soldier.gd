extends CharacterBody3D
## One soldier: static block model (standing / crouched pose, no animation),
## pathfinds to its slot or cover spot, picks its own target and fires on its
## own rhythm. In cover it stays crouched and pops up to shoot over the box.
##
## Roles (see weapons.gd): rifleman, grenadier (rifle + grenade launcher),
## anti_armor (burst rifle + rocket launcher). Specialists fire their
## secondary weapon while the squad's "specials" order (right mouse) is held.
## Soldiers not yet recruited stand at their post until the squad reaches them.
##
## Health 100: below 50 he's wounded (slower, less accurate), at 0 he's down.
## Suppression 0..1 builds from enemy rounds snapping past: suppressed
## soldiers peek less and shoot worse; pinned (>0.85) they stay down in cover.

const Weapons = preload("res://scripts/weapons.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")

enum State { FOLLOW, TO_COVER, IN_COVER }

const BASE_SPEED := 5.6
const EYE_HEIGHT := 1.45
const RAY_MASK := 1 | 4     # world + targets (soldiers are layer 2)
const FIRE_HOLD := 0       # must match squad.gd
const FIRE_AT_WILL := 1
const FIRE_FOCUS := 2
const MAX_HP := 100.0

static var _mats := {}

var squad: Node3D
var main: Node3D
var index := 0
var role := "rifleman"
var recruited := true
var home_pos := Vector3.ZERO
var state := State.FOLLOW
var move_target := Vector3.ZERO
var cover_pos := Vector3.ZERO
var has_real_cover := false
var target: Node3D = null
var peeks: Array = []          # lean-out spots when behind tall cover
var peek_pos := Vector3.ZERO
var shots := 0
var specials_fired := 0
var primary: Dictionary
var secondary: Dictionary
var secondary_cd := 0.0        # reload countdown for the secondary weapon
var hp := MAX_HP
var dead := false
var suppression := 0.0

var _agent: NavigationAgent3D
var _upper: Node3D
var _legs: Node3D
var _flash: MeshInstance3D
var _launch_tip: Node3D
var _rng := RandomNumberGenerator.new()
var _speed_mul := 1.0
var _moving := false
var _crouched := false
var _path_timer := 0.0
var _retarget_timer := 0.0
var _fire_timer := 0.0
var _burst_left := 0
var _burst_idx := 0
var _peeking := false
var _peek_timer := 0.0
var _peek_age := 0.0
var _flash_timer := 0.0
var _cover_timer := 0.0
var _since_incoming := 99.0
var _hurt_t := 0.0
var _cap: CapsuleShape3D
var _col: CollisionShape3D
var _torso: MeshInstance3D
var _model: Node3D


func _ready() -> void:
	_rng.seed = 1000 + index * 7919
	_speed_mul = _rng.randf_range(0.92, 1.08)
	_fire_timer = _rng.randf_range(0.2, 1.0)
	primary = Weapons.ROLES[role][0]
	secondary = Weapons.ROLES[role][1]
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3

	_col = CollisionShape3D.new()
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.32
	_cap.height = 1.8
	_col.shape = _cap
	_col.position.y = 0.9
	add_child(_col)

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
		m.roughness = 0.28 if Atmosphere.NIGHT else 0.75   # rain-soaked at night
		m.metallic_specular = 0.7
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		elif key != "dead":
			# A touch of self-light + rim so your own men read in the dark.
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 0.22 if Atmosphere.NIGHT else 0.06
			m.rim_enabled = Atmosphere.NIGHT   # edge highlight only needed in the dark
			m.rim = 0.5
			m.rim_tint = 0.6
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


func _tube(radius: float, length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 10
	return c


func _build_model() -> void:
	var anti_armor := role == "anti_armor"
	# Anti-armor team wears a lighter tan-khaki so you can tell them apart.
	var uniform := _mat("tan", Color(0.44, 0.40, 0.28)) if anti_armor else _mat("olive", Color(0.36, 0.40, 0.24))
	var dark := _mat("dark", Color(0.22, 0.25, 0.16))
	var skin := _mat("skin", Color(0.80, 0.64, 0.50))
	var black := _mat("black", Color(0.08, 0.08, 0.08))
	var drab := _mat("drab", Color(0.30, 0.33, 0.20))
	var flash := _mat("flash", Color(1.0, 0.9, 0.4), true)

	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	_model = model

	_legs = Node3D.new()
	model.add_child(_legs)
	for side in [-1.0, 1.0]:
		_part(_legs, _box(Vector3(0.16, 0.86, 0.18)), dark, Vector3(0.11 * side, 0.43, 0))

	_upper = Node3D.new()
	model.add_child(_upper)
	_torso = _part(_upper, _box(Vector3(0.48, 0.62, 0.28)), uniform, Vector3(0, 1.16, 0))  # torso
	_part(_upper, _box(Vector3(0.34, 0.42, 0.16)), dark, Vector3(0, 1.20, 0.2))          # backpack
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	_part(_upper, head, skin, Vector3(0, 1.6, -0.01))
	var helmet := SphereMesh.new()
	helmet.radius = 0.165
	helmet.height = 0.33
	_part(_upper, helmet, dark, Vector3(0, 1.66, 0), Vector3.ZERO, Vector3(1, 0.72, 1))
	_part(_upper, _box(Vector3(0.11, 0.11, 0.40)), uniform, Vector3(0.27, 1.28, -0.16))  # right arm
	_part(_upper, _box(Vector3(0.11, 0.11, 0.46)), uniform, Vector3(-0.17, 1.25, -0.24), Vector3(0, -0.5, 0))

	var rifle_len := 0.7 if anti_armor else 0.85     # burst rifle is a shorter carbine
	_part(_upper, _box(Vector3(0.07, 0.10, rifle_len)), black, Vector3(0.12, 1.27, -0.38 + (0.85 - rifle_len) * 0.5))

	match role:
		"grenadier":
			# Fat under-barrel launcher + grenade bandolier across the chest.
			_part(_upper, _tube(0.05, 0.32), drab, Vector3(0.12, 1.18, -0.52), Vector3(PI / 2.0, 0, 0))
			_part(_upper, _box(Vector3(0.5, 0.08, 0.3)), drab, Vector3(0, 1.3, -0.01), Vector3(0, 0, 0.6))
			_launch_tip = Node3D.new()
			_launch_tip.position = Vector3(0.12, 1.18, -0.7)
			_upper.add_child(_launch_tip)
		"anti_armor":
			# Launcher tube carried on the right shoulder.
			_part(_upper, _tube(0.075, 1.2), drab, Vector3(0.3, 1.52, -0.12), Vector3(PI / 2.0, 0, 0))
			_part(_upper, _tube(0.09, 0.12), black, Vector3(0.3, 1.52, -0.7), Vector3(PI / 2.0, 0, 0))
			_launch_tip = Node3D.new()
			_launch_tip.position = Vector3(0.3, 1.52, -0.8)
			_upper.add_child(_launch_tip)

	var fm := SphereMesh.new()
	fm.radius = 0.09
	fm.height = 0.18
	_flash = _part(_upper, fm, flash, Vector3(0.12, 1.27, -0.86))
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false


func _set_crouch(on: bool) -> void:
	if on == _crouched:
		return
	_crouched = on
	_legs.scale.y = 0.5 if on else 1.0
	_upper.position.y = -0.45 if on else 0.0
	# Shrink the hitbox too, so a crouched man really is hidden behind a crate.
	_cap.height = 1.25 if on else 1.8
	_col.position.y = 0.625 if on else 0.9


# ---------------------------------------------------------------- health & suppression

## The part of him an enemy can see and aim at.
func exposed_point() -> Vector3:
	return global_position + Vector3(0, 0.95 if _crouched else 1.35, 0)


func is_moving() -> bool:
	return _moving


func is_in_cover() -> bool:
	return state == State.IN_COVER


func pinned() -> bool:
	return suppression > 0.85


func add_suppression(amount: float) -> void:
	if dead or not recruited:
		return
	suppression = minf(1.0, suppression + amount)
	_since_incoming = 0.0


func take_damage(dmg: float, _from: Vector3) -> bool:
	if dead or not recruited:
		return false
	hp -= dmg
	add_suppression(0.35)
	_hurt_t = 0.12
	_torso.material_override = _mat("hurt", Color(1.0, 0.15, 0.1), true)
	main.on_soldier_hit(self)
	if hp <= 0.0:
		_die()
	return true


func role_name() -> String:
	return {"rifleman": "RIFLEMAN", "grenadier": "GRENADIER", "anti_armor": "ROCKETMAN"}.get(role, "SOLDIER")


## Static "down" pose: lies flat where he fell, no collision, no glow.
func _die() -> void:
	dead = true
	hp = 0.0
	target = null
	_set_crouch(false)
	collision_layer = 0
	_flash.visible = false
	_model.rotation.x = -PI / 2.0
	_model.position.y = 0.2
	var dead_mat := _mat("dead", Color(0.12, 0.13, 0.09))
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = dead_mat
	set_physics_process(false)
	squad.on_soldier_killed(self)


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
	if not recruited:
		_idle(delta)
		return
	_since_incoming += delta
	if _since_incoming > 1.5:
		suppression = maxf(0.0, suppression - 0.2 * delta)
	if _hurt_t > 0.0:
		_hurt_t -= delta
		if _hurt_t <= 0.0:
			_torso.material_override = _mat("tan", Color(0.44, 0.40, 0.28)) if role == "anti_armor" else _mat("olive", Color(0.36, 0.40, 0.24))
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
		if hp < MAX_HP * 0.5:
			spd *= 0.75        # wounded
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


## Waiting to be picked up: stand guard, facing down-range.
func _idle(delta: float) -> void:
	velocity = Vector3(0, -4.0, 0)
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, 0.0, clampf(4.0 * delta, 0.0, 1.0))


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
# Primary fire modes come from the squad: HOLD, AT_WILL (any visible target)
# and FOCUS (only targets inside the reticle; with none there, saturate the
# spot under it). While specials are ordered, specialists use their
# secondary weapon on the reticle instead.

var _aim_point := Vector3.ZERO
var _has_aim := false
var _mode := 0
var _using_secondary := false


func _eye() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func _weapon() -> Dictionary:
	return secondary if _using_secondary else primary


## Where this soldier shoots from: his lean-out spot behind tall cover, else where he stands.
func _spot() -> Vector3:
	return peek_pos if (state != State.FOLLOW and _is_tall()) else global_position


func _has_los(t: Node3D, from_ground := Vector3.INF) -> bool:
	var origin: Vector3 = global_position if from_ground == Vector3.INF else from_ground
	var q := PhysicsRayQueryParameters3D.create(origin + Vector3(0, EYE_HEIGHT, 0), t.aim_point(), RAY_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == t


func _point_los(from_ground: Vector3, p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from_ground + Vector3(0, EYE_HEIGHT, 0), p, RAY_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.6


## Grenades are lobbed, so they don't need a straight line of sight.
func _needs_los() -> bool:
	return _weapon()["kind"] != "grenade"


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
	var w := _weapon()
	var best: Node3D = null
	var best_score := INF
	for t in main.targets:
		if not t.alive:
			continue
		if focus_only and not main.in_reticle(t.aim_point()):
			continue
		var dist: float = global_position.distance_to(t.global_position)
		if dist > w["max"]:
			continue
		if _needs_los() and not _has_los(t, origin):
			continue
		var score: float = dist + _rng.randf_range(0.0, 8.0)   # each picks their own
		# Weapon-appropriate targets first: rockets hunt armor, bullets and
		# grenades go for infantry and only ping vehicles if nothing else.
		if t.kind == "vehicle":
			score += -200.0 if w["kind"] == "rocket" else 120.0
		if score < best_score:
			best_score = score
			best = t
	return best


## Focus fire with no target in the reticle: pick a random spot inside the
## reticle's footprint in the world and saturate it.
func _pick_focus_point() -> void:
	_aim_point = main.reticle_world_point(_rng)
	_has_aim = false
	if not _needs_los():
		_has_aim = global_position.distance_to(_aim_point) <= _weapon()["max"]
		return
	if state != State.FOLLOW and _is_tall():
		for p in peeks:
			if _point_los(p, _aim_point):
				peek_pos = p
				_has_aim = true
				return
	else:
		_has_aim = _point_los(global_position, _aim_point)


func _choose_aim() -> void:
	if _using_secondary:
		if target and not (target.alive and main.in_reticle(target.aim_point())):
			target = null
		if target == null:
			target = _find_target(true)
		if target:
			_has_aim = false
		else:
			_pick_focus_point()
		return
	match _mode:
		FIRE_HOLD:
			target = null
			_has_aim = false
		FIRE_AT_WILL:
			_has_aim = false
			if target == null or not _has_los(target, _spot()) or _rng.randf() < 0.15:
				target = _find_target(false)
		FIRE_FOCUS:
			if target and not (main.in_reticle(target.aim_point()) and _has_los(target, _spot())):
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
	secondary_cd = maxf(0.0, secondary_cd - delta)

	if target and not target.alive:
		target = null
	var mode: int = squad.fire_mode()
	var use_sec: bool = squad.specials_active() and not secondary.is_empty()
	_retarget_timer -= delta
	if mode != _mode or use_sec != _using_secondary or _retarget_timer <= 0.0:
		_mode = mode
		_using_secondary = use_sec
		_retarget_timer = _rng.randf_range(0.2, 0.4) if (_mode == FIRE_FOCUS or use_sec) else _rng.randf_range(0.35, 0.7)
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
			if not has_shot or pinned():
				_peeking = false          # pinned: keep your head down
				_peek_timer = maxf(minf(_peek_timer, 0.5), 0.3 if pinned() else 0.0)
			_peek_timer -= delta
			if _peek_timer <= 0.0 and has_shot and not pinned():
				_peeking = not _peeking
				# Under fire: shorter looks, longer time ducked.
				var up_time := (_rng.randf_range(1.0, 1.8) + (1.0 if _is_tall() else 0.0)) * (1.0 - 0.5 * suppression)
				var down_time := _rng.randf_range(0.8, 2.0) * (1.0 + 1.5 * suppression)
				_peek_timer = up_time if _peeking else down_time
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

	if _using_secondary:
		if can_fire and secondary_cd <= 0.0:
			_fire_secondary()
			secondary_cd = secondary["reload"]
		return

	_fire_timer -= delta
	if can_fire and _fire_timer <= 0.0:
		if _burst_left <= 0:
			_burst_left = _rng.randi_range(primary["burst_min"], primary["burst_max"])
			_burst_idx = 0
		_shoot()
		_burst_left -= 1
		_burst_idx += 1
		var pause: float = _rng.randf_range(primary["pause_min"], primary["pause_max"])
		if _mode == FIRE_FOCUS:
			pause *= 0.5
		_fire_timer = primary["cycle"] if _burst_left > 0 else pause


## Suppressed or wounded soldiers shoot worse.
func _fight_mod() -> float:
	var m := 1.0 - 0.5 * suppression
	if hp < MAX_HP * 0.5:
		m *= 0.85
	return m


## Where a deliberate miss lands: just off the target, sideways or high/low.
func _miss_point(t: Node3D, from: Vector3) -> Vector3:
	var c: Vector3 = t.aim_point()
	var dir := (c - from).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var off := side * _rng.randf_range(-1.0, 1.0) + Vector3.UP * _rng.randf_range(-0.5, 0.9)
	if off.length() < 0.2:
		off = side
	return c + off.normalized() * (t.radius + _rng.randf_range(0.3, 1.4))


func _shoot() -> void:
	var from := _eye() - Vector3(0, 0.15, 0)
	var aim: Vector3
	if target:
		var c: Vector3 = target.aim_point()
		var chance := Weapons.hit_chance(primary, target, from.distance_to(c), _moving, _mode == FIRE_FOCUS, _burst_idx > 0) * _fight_mod()
		if _rng.randf() < chance:
			aim = c + Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.12, 0.12))
		else:
			aim = _miss_point(target, from)
	else:
		aim = _aim_point
		var spread := 0.02 * from.distance_to(aim) + (0.3 if _moving else 0.0)
		aim += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * spread * 0.5
	var dir := (aim - from).normalized()
	var to := from + dir * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var c: Object = hit["collider"]
		var spark := false
		if c.has_method("take_damage"):
			spark = true
			if c.take_damage(primary["soft"], primary["armor"]):
				main.hits += 1   # only hits that hurt (ricochets off armor don't count)
		main.spawn_impact(end, hit["normal"], spark)
	main.suppress_enemies(from, end, 0.08)
	shots += 1
	main.spawn_tracer(_flash.global_position, end)
	main.on_shot(_flash.global_position)
	_flash.visible = true
	_flash_timer = 0.05


## Launch a grenade or rocket. The hit roll decides whether it's sent at the
## target or deliberately off to the side (where splash may still catch it).
func _fire_secondary() -> void:
	var from: Vector3 = _launch_tip.global_position if _launch_tip else _flash.global_position
	var to: Vector3
	var grenade: bool = secondary["kind"] == "grenade"
	if target:
		var c: Vector3 = target.aim_point()
		if grenade:
			c = target.global_position + Vector3(0, 0.3, 0)
		var chance := Weapons.hit_chance(secondary, target, from.distance_to(c), _moving, true, false) * _fight_mod()
		if _rng.randf() < chance:
			to = c
		else:
			var side := (c - from).cross(Vector3.UP).normalized()
			var off := side * _rng.randf_range(-1.0, 1.0) + (c - from).normalized() * _rng.randf_range(-1.0, 1.0)
			off.y = 0
			to = c + off.normalized() * (target.radius + _rng.randf_range(1.5, 4.0))
			to.y = maxf(0.2, c.y - 0.8)
	else:
		to = _aim_point + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	var p: Node3D = ProjectileScript.new()
	p.setup(main, secondary, from, to, _rng)
	main.add_child(p)
	specials_fired += 1
	main.on_launch(from, secondary)
