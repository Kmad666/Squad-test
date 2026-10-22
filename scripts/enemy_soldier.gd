extends CharacterBody3D
## Enemy rifleman that moves and fights from cover.
##
## Belongs to an area (a defended position). Until the area is alerted it
## stands at its post. It alerts when it spots the squad, takes fire or gets
## hit, and then the whole area alerts. Alerted, each man:
##   - runs to a cover spot inside his area that shields him from the squad
##     (no two men share a spot; he avoids spots right next to your soldiers)
##   - crouches, then peeks to shoot (leaning out past tall crates)
##   - stays down while pinned, peeks less while suppressed
##   - moves to new cover when the squad flanks his spot, and now and then
##     shifts position anyway; wounded men fall back to cover further away
## His rifle is an enemy_gunner mounted on his upper body, so when he
## crouches behind a crate he can't see or be seen.

const EnemyGunner = preload("res://scripts/enemy_gunner.gd")
const Weapons = preload("res://scripts/weapons.gd")
const CoverUtil = preload("res://scripts/cover_util.gd")

enum State { POST, MOVING, IN_COVER }

const MAX_HP := 6.0
const SPEED := 4.6

static var _mats := {}

var main: Node3D
var area: Dictionary          # shared with the other men in his area
var post := Vector3.ZERO
var kind := "infantry"
var size_factor := 1.0
var radius := 0.35
var mark_height := 1.9
var alive := true
var hp := MAX_HP
var gunners: Array = []
var state := State.POST

var _gun: Node3D
var _agent: NavigationAgent3D
var _model: Node3D
var _upper: Node3D
var _legs: Node3D
var _torso: MeshInstance3D
var _cap: CapsuleShape3D
var _col: CollisionShape3D
var _rng := RandomNumberGenerator.new()
var _cover: Dictionary = {}
var _dest := Vector3.ZERO
var _crouched := false
var _peeking := false
var _peek_timer := 0.0
var _reposition_timer := 0.0
var _check_timer := 0.0
var _path_timer := 0.0
var _hurt_t := 0.0
var _peek_spot := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	collision_layer = 4      # "targets": your squad's rounds hit it
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
	add_child(_agent)

	_gun = EnemyGunner.new()
	_gun.main = main
	_gun.host = self
	_gun.weapon = Weapons.ENEMY_RIFLE
	_gun.reaction_min = 0.35
	_gun.reaction_max = 0.8
	_gun.position = Vector3(0.12, 1.3, -0.9)
	_upper.add_child(_gun)
	gunners = [_gun]
	_dest = post   # post is set by main before the man is added
	rotation.y = PI    # model front (-Z) turned to face +Z, where the squad comes from


# ---------------------------------------------------------------- model

static func _mat(key: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.7
		_mats[key] = m
	return _mats[key]


func _part(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Same block soldier as yours, in slate grey with a red armband so you can
## tell friend from foe at a glance.
func _build_model() -> void:
	var uniform := _mat("slate", Color(0.27, 0.28, 0.30))
	var dark := _mat("dark", Color(0.14, 0.14, 0.16))
	var skin := _mat("skin", Color(0.78, 0.62, 0.48))
	var black := _mat("black", Color(0.06, 0.06, 0.06))
	var red := _mat("red", Color(0.75, 0.08, 0.06))

	_model = Node3D.new()
	add_child(_model)
	_legs = Node3D.new()
	_model.add_child(_legs)
	for side in [-1.0, 1.0]:
		_part(_legs, Vector3(0.16, 0.86, 0.18), dark, Vector3(0.11 * side, 0.43, 0))
	_upper = Node3D.new()
	_model.add_child(_upper)
	_torso = _part(_upper, Vector3(0.48, 0.62, 0.28), uniform, Vector3(0, 1.16, 0))
	_part(_upper, Vector3(0.34, 0.42, 0.16), dark, Vector3(0, 1.20, 0.2))
	_part(_upper, Vector3(0.13, 0.12, 0.13), red, Vector3(-0.31, 1.33, 0))         # armband
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.26
	head.mesh = hm
	head.material_override = skin
	head.position = Vector3(0, 1.6, -0.01)
	_upper.add_child(head)
	var helmet := MeshInstance3D.new()
	var hel := SphereMesh.new()
	hel.radius = 0.165
	hel.height = 0.33
	helmet.mesh = hel
	helmet.material_override = black
	helmet.position = Vector3(0, 1.66, 0)
	helmet.scale = Vector3(1, 0.72, 1)
	_upper.add_child(helmet)
	_part(_upper, Vector3(0.11, 0.11, 0.40), uniform, Vector3(0.27, 1.28, -0.16))
	_part(_upper, Vector3(0.11, 0.11, 0.46), uniform, Vector3(-0.17, 1.25, -0.24), Vector3(0, -0.5, 0))
	_part(_upper, Vector3(0.07, 0.10, 0.85), black, Vector3(0.12, 1.27, -0.38))


func _set_crouch(on: bool) -> void:
	if on == _crouched:
		return
	_crouched = on
	_legs.scale.y = 0.5 if on else 1.0
	_upper.position.y = -0.45 if on else 0.0
	_cap.height = 1.25 if on else 1.8
	_col.position.y = 0.625 if on else 0.9


# ---------------------------------------------------------------- target interface

func aim_point() -> Vector3:
	return global_position + Vector3(0, 0.9 if _crouched else 1.3, 0)


func suppression_level() -> float:
	return _gun.suppression if _gun else 0.0


## The gunner only shoots while he's up (standing or leaning out), not while
## running between cover.
func can_fire() -> bool:
	return alive and not _crouched and state != State.MOVING


func on_spotted() -> void:
	_alert_area()


func take_damage(soft_dmg: float, _armor_dmg: float) -> bool:
	if not alive or soft_dmg <= 0.0:
		return false
	hp -= soft_dmg
	_gun.add_suppression(0.2)
	_torso.material_override = _mat("hit", Color(1.0, 0.3, 0.2))
	_hurt_t = 0.1
	_alert_area()
	if hp <= 0.0:
		_die()
	elif hp < MAX_HP * 0.5:
		_reposition_timer = 0.0     # wounded: fall back now
	return true


func _alert_area() -> void:
	if not area.get("alerted", false):
		area["alerted"] = true
		if main:
			main.on_area_alerted(area)


func _die() -> void:
	alive = false
	hp = 0.0
	_release_cover()
	_set_crouch(false)
	collision_layer = 0
	_model.rotation.x = PI / 2.0
	_model.position.y = 0.2
	var dead := _mat("dead", Color(0.16, 0.16, 0.17))
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = dead
	set_physics_process(false)
	main.on_enemy_killed(self)


# ---------------------------------------------------------------- behaviour

func _threat() -> Vector3:
	if main.squad.soldiers.is_empty():
		return global_position + Vector3(0, 0, 30)
	return main.squad.centroid()


func _release_cover() -> void:
	if not _cover.is_empty():
		area["claimed"].erase(_cover["pos"])
	_cover = {}


## Best cover spot in the area that puts a crate between him and the squad.
func _pick_cover() -> void:
	var threat := _threat()
	var wounded := hp < MAX_HP * 0.5
	var best: Dictionary = {}
	var best_score := INF
	for cp in main.cover_points:
		var p: Vector3 = cp["pos"]
		if p.distance_to(area["center"]) > area["radius"]:
			continue
		if area["claimed"].has(p) and (_cover.is_empty() or _cover["pos"] != p):
			continue
		var to_threat := threat - p
		to_threat.y = 0
		if cp["normal"].dot(to_threat.normalized()) > -0.3:
			continue          # crate isn't between this spot and the squad
		var too_close := false
		for s in main.squad.soldiers:
			if s.global_position.distance_to(p) < 6.0:
				too_close = true
				break
		if too_close:
			continue
		var score := global_position.distance_to(p) + _rng.randf_range(0.0, 5.0)
		# Healthy men like a fighting distance; wounded men want distance.
		score += -0.5 * to_threat.length() if wounded else 0.1 * absf(to_threat.length() - 30.0)
		if score < best_score:
			best_score = score
			best = cp
	if best.is_empty():
		return
	_release_cover()
	_cover = best
	area["claimed"][best["pos"]] = true
	_dest = best["pos"]
	state = State.MOVING
	_peeking = false
	_path_timer = 0.0


## Is his current spot still shielding him from the squad?
func _cover_still_good() -> bool:
	if _cover.is_empty():
		return false
	var to_threat: Vector3 = _threat() - _cover["pos"]
	to_threat.y = 0
	return _cover["normal"].dot(to_threat.normalized()) < -0.1


func _physics_process(delta: float) -> void:
	if _hurt_t > 0.0:
		_hurt_t -= delta
		if _hurt_t <= 0.0:
			_torso.material_override = _mat("slate", Color(0.27, 0.28, 0.30))

	if _gun.suppression > 0.05:
		_alert_area()

	var alerted: bool = area.get("alerted", false)
	if alerted:
		_check_timer -= delta
		_reposition_timer -= delta
		if state == State.POST:
			_pick_cover()
			_reposition_timer = _rng.randf_range(9.0, 15.0)
		elif _check_timer <= 0.0:
			_check_timer = 1.0
			# Flanked (or just time to shift), and not pinned: move.
			if not _gun.pinned() and (not _cover_still_good() or _reposition_timer <= 0.0):
				_pick_cover()
				_reposition_timer = _rng.randf_range(9.0, 15.0)

	_update_stance(delta)
	_move(delta)


func _update_stance(delta: float) -> void:
	match state:
		State.POST:
			_set_crouch(false)
		State.MOVING:
			_set_crouch(false)
		State.IN_COVER:
			var supp: float = _gun.suppression
			if _gun.pinned():
				_peeking = false
				_peek_timer = maxf(_peek_timer, 0.4)
			_peek_timer -= delta
			if _peek_timer <= 0.0 and not _gun.pinned():
				_peeking = not _peeking
				if _peeking:
					_peek_timer = _rng.randf_range(1.6, 2.6) * (1.0 - 0.5 * supp) + (1.0 if _tall() else 0.0)
				else:
					_peek_timer = _rng.randf_range(1.0, 2.2) * (1.0 + 1.5 * supp)
			_set_crouch(not _peeking)


## Lean-out corner for tall cover: one a mate isn't already using.
func _choose_peek_spot() -> void:
	if not _tall():
		return
	_peek_spot = _cover["peeks"][0]
	for lp in _cover["peeks"]:
		var free := true
		for m in area["members"]:
			if m == self or not m.alive or not ("_peek_spot" in m) or not m._tall():
				continue
			if m._peek_spot.distance_to(lp) < 1.0 or m._cover["pos"].distance_to(lp) < 1.0:
				free = false
		if free:
			_peek_spot = lp
			return


func _tall() -> bool:
	return not _cover.is_empty() and not _cover["peeks"].is_empty()


func _move(delta: float) -> void:
	var dest := _dest
	if state == State.IN_COVER and _peeking and _tall():
		dest = _peek_spot
	elif state == State.POST:
		dest = post
	_path_timer -= delta
	if _path_timer <= 0.0:
		_agent.target_position = dest
		_path_timer = 0.3

	var to_dest := dest - global_position
	to_dest.y = 0
	var dist := to_dest.length()
	var vel := Vector3.ZERO
	if dist > 0.2:
		var next := _agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0
		if dir.length() < 0.05 or _agent.is_navigation_finished():
			dir = to_dest
		var spd := SPEED * (1.25 if state == State.MOVING else 1.0)
		if hp < MAX_HP * 0.5:
			spd *= 0.75
		vel = dir.normalized() * spd * clampf(dist, 0.35, 1.0)
	elif state == State.MOVING:
		state = State.IN_COVER
		_peek_timer = _rng.randf_range(0.6, 1.4)
		_choose_peek_spot()

	# Keep a little space from his mates.
	for m in area["members"]:
		if m == self or not m.alive:
			continue
		var off: Vector3 = global_position - m.global_position
		off.y = 0
		var d := off.length()
		if d < 0.9 and d > 0.001 and state != State.IN_COVER:
			vel += off / d * (1.0 - d / 0.9) * 2.5

	velocity = Vector3(vel.x, -4.0, vel.z)
	move_and_slide()

	# Face whoever he's shooting, else the squad when alerted, else his travel.
	var look := Vector3.ZERO
	if _gun.target and is_instance_valid(_gun.target):
		look = _gun.target.global_position - global_position
	elif area.get("alerted", false) and state != State.MOVING:
		look = _threat() - global_position
	elif vel.length() > 0.4:
		look = vel
	look.y = 0
	if look.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), clampf(8.0 * delta, 0.0, 1.0))
