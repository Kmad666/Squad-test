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
## On top of that his area's tactics (scripts/enemy_tactics.gd) can give him a
## role: "flank" (go fight from cover off to the squad's side), "assault"
## (close in), or move him to another area (falling back, reinforcing). A
## role is just a different place to look for cover (his "scope"). Caught
## moving in the open by heavy fire he goes to ground where he is; warned of
## a grenade he dives away from it.
## His rifle is an enemy_gunner mounted on his upper body, so when he
## crouches behind a crate he can't see or be seen.

const EnemyGunner = preload("res://scripts/enemy_gunner.gd")
const Weapons = preload("res://scripts/weapons.gd")
const CoverUtil = preload("res://scripts/cover_util.gd")
const SoldierModel = preload("res://scripts/soldier_model.gd")

enum State { POST, MOVING, IN_COVER }

const MAX_HP := 6.0
const SPEED := 4.6


var main: Node3D
var area: Dictionary          # shared with the other men in his area
var post := Vector3.ZERO
var kind := "infantry"
var size_factor := 1.0
var radius := 0.35
var mark_height := 1.9
var rpg := false              # anti-tank gunner: an RPG for our LAV as well as his rifle
var alive := true
var hp := MAX_HP
var gunners: Array = []
var state := State.POST
var role := "hold"            # hold (his area) / flank / assault: set by the area's tactics
var covering := false         # a mate is on the move: stay up and shoot more

var _gun: Node3D
var _rpg: Node3D = null
var _agent: NavigationAgent3D
var _model: Node3D
var _upper: Node3D
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
var _scope_c := Vector3.ZERO    # where he looks for cover: centre, radius,
var _scope_r := 0.0             # and the fighting distance he likes
var _pref := 30.0
var _hasty := false             # no cover to be had: crouched in the open
var _dive_t := 0.0              # sprinting clear of a grenade
var _in_range := true           # something of ours is close enough to shoot at


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
	_model.muzzle.add_child(_gun)        # fires from the rifle's muzzle
	gunners = [_gun]
	if rpg:
		_rpg = EnemyGunner.new()
		_rpg.main = main
		_rpg.host = self
		_rpg.weapon = Weapons.ENEMY_RPG
		_rpg.armor_only = true
		_rpg.reaction_min = 1.0
		_rpg.reaction_max = 2.0
		(_model.launch_tip if _model.launch_tip else _model.muzzle).add_child(_rpg)
		gunners.append(_rpg)
	_dest = post   # post is set by main before the man is added
	hold()
	rotation.y = PI    # model front (-Z) turned to face +Z, where the squad comes from


# ---------------------------------------------------------------- model

## The same universal soldier as yours (scripts/soldier_model.gd), in slate
## grey with a black vest and a red armband so you can tell friend from foe.
func _build_model() -> void:
	_model = SoldierModel.new()
	_model.name = "Model"
	add_child(_model)
	_model.build("anti_armor" if rpg else "rifleman", "enemy", _rng.randi())
	_upper = _model.upper


func _set_crouch(on: bool) -> void:
	if on == _crouched:
		return
	_crouched = on
	_model.set_crouch(on)
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


## Called by his gunner on every shot.
func on_fired() -> void:
	_model.recoil()


func on_spotted() -> void:
	_alert_area()


func take_damage(soft_dmg: float, _armor_dmg: float) -> bool:
	if not alive or soft_dmg <= 0.0:
		return false
	hp -= soft_dmg
	_model.wounded = hp < MAX_HP * 0.5     # limps
	_gun.add_suppression(0.2)
	_model.set_tint("hurt")
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
	_model.lay_down(true)
	_model.set_tint("dead")
	set_physics_process(false)
	main.on_enemy_killed(self)


# ---------------------------------------------------------------- behaviour

## The squad as he sees it: the middle of whichever fire team is nearer.
func _threat() -> Vector3:
	var sq: Node3D = main.squad
	if sq.soldiers.is_empty():
		return global_position + Vector3(0, 0, 30)
	if not sq.split:
		return sq.centroid()
	var best: Vector3 = sq.centroid()
	var bd := INF
	for t in 2:
		if sq.team_members(t).is_empty():
			continue
		var c: Vector3 = sq.centroid(t)
		var d := global_position.distance_to(c)
		if d < bd:
			bd = d
			best = c
	return best


# ---------------------------------------------------------------- roles (set by enemy_tactics.gd)

## Where he looks for cover from now on, and how far from the squad he
## likes to fight. He moves there at his next check.
func set_scope(center: Vector3, radius: float, pref: float) -> void:
	_scope_c = center
	_scope_r = radius
	_pref = pref


## Back to defending his own area.
func hold() -> void:
	role = "hold"
	set_scope(area["center"], area["radius"], 30.0)


## New orders: act on them now rather than at the next shift.
func hurry() -> void:
	_check_timer = 0.0
	_reposition_timer = 0.0


## Leave his area for another (falling back, or sent to reinforce).
func join_area(a: Dictionary) -> void:
	_release_cover()
	area["members"].erase(self)
	area = a
	a["members"].append(self)
	post = a["center"]
	hold()
	hurry()


func _in_scope() -> bool:
	var at: Vector3 = _dest if state != State.POST else global_position
	return Vector2(at.x - _scope_c.x, at.z - _scope_c.z).length() <= _scope_r + 0.5


## "GRENADE!": if he isn't pinned and has his wits about him he sprints
## clear of it (out of his cover, which is the point of throwing it).
func grenade_warning(at: Vector3, blast: float, flight: float) -> void:
	if not alive or not area.get("alerted", false) or _gun.pinned():
		return
	var off := global_position - at
	off.y = 0
	if off.length() > blast + 1.0 or flight < 0.7 or _rng.randf() > 0.7:
		return
	var away := off.normalized() if off.length() > 0.2 else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	_release_cover()
	_hasty = true
	_dest = CoverUtil.push_out(main.cover_defs, at + away * (blast + 2.5), 0.6)
	_dest.y = 0
	state = State.MOVING
	_peeking = false
	_path_timer = 0.0
	_dive_t = flight + 0.6
	_check_timer = flight + 1.5        # then he looks for proper cover again


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
		if Vector2(p.x - _scope_c.x, p.z - _scope_c.z).length() > _scope_r:
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
		if wounded and role == "hold":
			score += -0.5 * to_threat.length()
		else:
			score += (0.1 if role == "hold" else 0.5) * absf(to_threat.length() - _pref)
		if score < best_score:
			best_score = score
			best = cp
	if best.is_empty():
		_take_hasty_position()
		return
	_release_cover()
	_hasty = false
	_cover = best
	area["claimed"][best["pos"]] = true
	_dest = best["pos"]
	state = State.MOVING
	_peeking = false
	_path_timer = 0.0


## Nothing to hide behind where he's been told to fight: he gets down in
## the open there (crouched, popping up to shoot) and keeps looking.
func _take_hasty_position() -> void:
	if _hasty and _in_scope() and state != State.POST:
		return
	_release_cover()
	_hasty = true
	var r := minf(_scope_r, 6.0)
	_dest = CoverUtil.push_out(main.cover_defs, _scope_c + Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r)), 0.6)
	_dest.y = 0
	state = State.MOVING
	_peeking = false
	_path_timer = 0.0


## Is his current spot still shielding him from the squad?
func _cover_still_good() -> bool:
	if _cover.is_empty():
		return _hasty
	var to_threat: Vector3 = _threat() - _cover["pos"]
	to_threat.y = 0
	return _cover["normal"].dot(to_threat.normalized()) < -0.1


func _physics_process(delta: float) -> void:
	if _hurt_t > 0.0:
		_hurt_t -= delta
		if _hurt_t <= 0.0:
			_model.set_tint("normal")

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
			_in_range = _anything_in_range()
			# Flanked, sent somewhere else, or just time to shift; and not pinned: move.
			if not _gun.pinned() and (not _cover_still_good() or not _in_scope() or _reposition_timer <= 0.0):
				_pick_cover()
				_reposition_timer = _rng.randf_range(9.0, 15.0)
		# Caught in the open by heavy fire on a long move: go to ground right here.
		if state == State.MOVING and _dive_t <= 0.0 and _gun.pinned() and global_position.distance_to(_dest) > 4.0:
			_release_cover()
			_hasty = true
			_dest = global_position
			_check_timer = 1.5
	_dive_t = maxf(0.0, _dive_t - delta)

	_update_stance(delta)
	_move(delta)
	# Shoulder the rifle while he has a target and is up to fire.
	var aim_at := Vector3.INF
	if _gun.target and is_instance_valid(_gun.target) and can_fire():
		aim_at = _gun.target.exposed_point()
	elif _rpg and _rpg.target and is_instance_valid(_rpg.target) and can_fire():
		aim_at = _rpg.target.exposed_point()
	_model.set_aim_point(aim_at)


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
				if not _in_range:
					# Nothing he can reach: stay hidden, with a quick look now and then.
					_peek_timer = (0.7 + (0.8 if _tall() else 0.0)) if _peeking else _rng.randf_range(5.0, 9.0)
				elif _peeking:
					_peek_timer = _rng.randf_range(1.6, 2.6) * (1.0 - 0.5 * supp) * (1.5 if covering else 1.0) + (1.0 if _tall() else 0.0)
				else:
					_peek_timer = _rng.randf_range(1.0, 2.2) * (1.0 + 1.5 * supp) * (0.5 if covering else 1.0)
			_set_crouch(not _peeking)


## Is anything of ours close enough to be worth getting up for? (His rifle's
## reach, or his RPG's against the LAV.) If not he keeps his head down
## instead of popping up to be shot from out of his range.
func _anything_in_range() -> bool:
	var reach: float = _gun.weapon["max"] + 4.0
	for s in main.squad.soldiers:
		if s.global_position.distance_to(global_position) <= reach:
			return true
	var lav: Node3D = main.squad.lav
	if lav and lav.alive:
		var lav_reach: float = (Weapons.ENEMY_RPG["max"] if rpg else _gun.weapon["max"]) + 4.0
		if lav.global_position.distance_to(global_position) <= lav_reach:
			return true
	return false


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
		var spd := SPEED * (1.25 if state == State.MOVING else 1.0) * (1.25 if _dive_t > 0.0 else 1.0)
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
	_model.animate(get_real_velocity(), delta)

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
