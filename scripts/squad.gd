extends Node3D
## The squad: one unit, or two fire teams.
##
## Joined: WASD moves an anchor point, soldiers hold a loose cluster around
## it, and the cover order sends each soldier to his own cover spot on the far
## side of a crate from where the camera faces.
##
## Split (T): two fire teams, A and B (coloured helmet patches). You command
## the active team (Q switches); the other team holds where it is and gives
## covering fire at will. B: bounding advance to the point under the reticle,
## teams leapfrog (one moves, the other covers). H: hold position, WASD then
## scouts ahead with the camera instead of moving anyone.
##
## Teams waiting in the field join when either fire team walks up to them.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SoldierScript = preload("res://scripts/soldier.gd")
const Weapons = preload("res://scripts/weapons.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")

const MOVE_SPEED := 5.0
const CLUSTER_RADIUS := 2.8      # loose cluster spread around the anchor
const COVER_SEARCH := 14.0       # how far from the team a cover spot may be
const COHESION_WEIGHT := 0.7     # how much cover choice favours staying grouped
const MIN_COVER_GAP := 0.95      # two soldiers never share a spot
const JOIN_DISTANCE := 7.0       # how close the squad must get to pick up a team
const BOUND_STEP := 9.0          # how far each bound goes past the covering team
const SCOUT_RANGE := 30.0        # how far the camera may scout while holding
const TEAM_NAMES := ["A", "B"]

## Starting squad: five riflemen and a grenadier.
const START_ROLES := ["rifleman", "rifleman", "rifleman", "grenadier", "rifleman", "rifleman"]

enum { HOLD, AT_WILL, FOCUS }

var main: Node3D
var soldiers: Array = []
var slot_offsets: Array = []       # by soldier index (kept for tests / tools)
var auto_fire := false             # F: permanent fire at will
var forced_mode := -1              # tests can force a fire mode
var forced_specials := false       # tests: use a special every 1.5 s automatically
var selected_special := 0          # index into Weapons.SPECIAL_ORDER (keys 1-4, X)
var _forced_special_t := 0.0
var pending_teams: Array = []      # [{members, center, label, name}]
var kia := 0

var teams: Array = []              # 2 x {anchor, in_cover, order_target, threat_dir}
var split := false
var active := 0
var holding := false
var scout_offset := Vector3.ZERO
var bound: Dictionary = {}         # {target, mover, phase, timer} while bounding

var _ping: MeshInstance3D
var _ping_t := 0.0

# The active team's state, so everything that used the single squad still works.
var anchor: Vector3:
	get: return teams[active]["anchor"]
	set(v): teams[active]["anchor"] = v
var in_cover: bool:
	get: return teams[active]["in_cover"]
	set(v): teams[active]["in_cover"] = v
var order_target: Variant:
	get: return teams[active]["order_target"]
	set(v): teams[active]["order_target"] = v
var threat_dir: Vector3:
	get: return teams[active]["threat_dir"]
	set(v): teams[active]["threat_dir"] = v


func _init() -> void:
	for i in 2:
		teams.append({"anchor": Vector3.ZERO, "in_cover": false, "order_target": null, "threat_dir": Vector3.FORWARD})


func setup(m: Node3D, start: Vector3) -> void:
	main = m
	teams[0]["anchor"] = start
	var rifle_n := 0
	for i in START_ROLES.size():
		var s := _new_soldier(START_ROLES[i], i)
		if s.role == "rifleman":
			# Riflemen carry one hand grenade each: frags and flashbangs, mixed.
			s.set_special("flash" if rifle_n % 3 == 1 else "frag", 1)
			rifle_n += 1
		soldiers.append(s)
	_make_offsets()
	for s in soldiers:
		s.global_position = start + s.slot_offset
		s.move_target = s.global_position


func _new_soldier(role: String, idx: int) -> CharacterBody3D:
	var s: CharacterBody3D = SoldierScript.new()
	s.squad = self
	s.main = main
	s.index = idx
	s.role = role
	add_child(s)
	return s


## A team standing at `center`, waiting to be picked up by the squad.
func spawn_waiting_team(team_name: String, center: Vector3, roles: Array) -> void:
	var members: Array = []
	for i in roles.size():
		var a := float(i) / float(roles.size()) * TAU
		var s := _new_soldier(roles[i], 100 + pending_teams.size() * 10 + i)
		s.recruited = false
		s.global_position = center + Vector3(cos(a), 0, sin(a)) * 1.2
		s.home_pos = s.global_position
		members.append(s)
	var label := Label3D.new()
	label.font = UI_FONT
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.45, 1.0, 0.3)
	label.outline_modulate = Color(0, 0.08, 0, 0.8)
	label.text = "%s\n%d x BURST RIFLE + ROCKETS\nMOVE UP TO LINK UP" % [team_name, roles.size()]
	label.position = center + Vector3(0, 2.8, 0)
	add_child(label)
	pending_teams.append({"members": members, "center": center, "label": label, "name": team_name})


func _check_joins() -> void:
	for team in pending_teams.duplicate():
		var joiner := -1
		for t in (2 if split else 1):
			if teams[t]["anchor"].distance_to(team["center"]) <= JOIN_DISTANCE:
				joiner = t
		if joiner < 0:
			continue
		for s in team["members"]:
			s.recruited = true
			s.index = soldiers.size()
			s.team = joiner
			soldiers.append(s)
		team["label"].queue_free()
		pending_teams.erase(team)
		_make_offsets()
		if teams[joiner]["in_cover"]:
			take_cover(joiner)
		main.notify("%s JOINED %s  (+%d)" % [team["name"], ("TEAM " + TEAM_NAMES[joiner]) if split else "THE SQUAD", team["members"].size()])


func team_members(t: int) -> Array:
	if not split:
		return soldiers if t == 0 else []
	return soldiers.filter(func(s): return s.team == t)


## Loose cluster per team: sunflower spiral with a little per-soldier jitter
## so it doesn't look like a parade-ground pattern.
func _make_offsets() -> void:
	slot_offsets.resize(soldiers.size())
	for t in 2:
		var members := team_members(t)
		var count := members.size()
		if count == 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242 + t
		var radius := CLUSTER_RADIUS * sqrt(maxf(1.0, float(count) / 6.0))  # bigger team, wider cluster
		for i in count:
			var r: float = radius * sqrt((float(i) + 0.6) / float(count))
			var a: float = float(i) * 2.39996 + 0.4
			var jitter := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
			var off := Vector3(cos(a) * r, 0, sin(a) * r) + jitter
			members[i].slot_offset = off
			slot_offsets[members[i].index] = off
	for s in soldiers:
		s.set_team_patch(s.team if split else -1)


# ---------------------------------------------------------------- fire control

## Primary weapons for the team you command: left mouse held = focus fire on
## the reticle, otherwise fire at will if auto fire (F) is on, else hold fire.
func fire_mode() -> int:
	if forced_mode >= 0:
		return forced_mode
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return FOCUS
	return AT_WILL if auto_fire else HOLD


## The team you're not commanding is the base of fire: once a fight is on
## (any enemy area alerted, or you're shooting), it fires at will. It won't
## start a fight on its own.
func fire_mode_for(s: Node3D) -> int:
	if split and s.team != active:
		return AT_WILL if (main.any_area_alerted() or fire_mode() != HOLD) else HOLD
	return fire_mode()


# ---------------------------------------------------------------- specials
# One right click = one man uses one special of the selected kind on the
# reticle. 1-4 pick the kind, X jumps to the next kind that still has ammo.
# If the selected kind is empty the click switches to the next one with ammo
# and uses it, so a click in a pinch is never wasted.

## Men whose specials you can call on: your active team (or everyone, joined).
func _special_users() -> Array:
	return soldiers if not split else team_members(active)


func special_count(kind: String) -> int:
	var n := 0
	for s in _special_users():
		if s.special_kind == kind:
			n += s.special_ammo
	return n


func total_specials() -> int:
	var n := 0
	for k in Weapons.SPECIAL_ORDER:
		n += special_count(k)
	return n


func selected_kind() -> String:
	return Weapons.SPECIAL_ORDER[selected_special]


func _clear_shot(s: Node3D, t: Node3D, point: Vector3) -> bool:
	var from: Vector3 = s.global_position + Vector3(0, 1.55, 0)
	var to: Vector3 = t.aim_point() if t else point + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == t or (hit["position"] as Vector3).distance_to(to) < 1.0


func select_special(idx: int) -> void:
	selected_special = clampi(idx, 0, Weapons.SPECIAL_ORDER.size() - 1)
	var k := selected_kind()
	main.on_special_selected(k, special_count(k))


## X: next kind that still has ammo.
func cycle_special() -> void:
	for step in range(1, Weapons.SPECIAL_ORDER.size() + 1):
		var idx := (selected_special + step) % Weapons.SPECIAL_ORDER.size()
		if special_count(Weapons.SPECIAL_ORDER[idx]) > 0:
			select_special(idx)
			return
	main.on_no_explosives()


func use_special() -> void:
	print("[debug] use_special total=", total_specials(), " kind=", selected_kind(), " count=", special_count(selected_kind()), " users=", _special_users().size())
	if total_specials() == 0:
		main.on_no_explosives()
		return
	var kind := selected_kind()
	if special_count(kind) == 0:
		for step in range(1, Weapons.SPECIAL_ORDER.size()):
			var idx := (selected_special + step) % Weapons.SPECIAL_ORDER.size()
			if special_count(Weapons.SPECIAL_ORDER[idx]) > 0:
				main.special_msg("%s OUT  -  SWITCHED TO %s" % [Weapons.SPECIALS[kind][1], Weapons.SPECIALS[Weapons.SPECIAL_ORDER[idx]][1]], 2.0)
				selected_special = idx
				kind = Weapons.SPECIAL_ORDER[idx]
				break
	var w: Dictionary = Weapons.SPECIALS[kind][0]
	var aim: Dictionary = main.special_target(kind)
	var point: Vector3 = aim["point"]
	print("[debug] aim target=", aim["target"], " point=", point)
	# The nearest ready man carrying this kind who can reach the spot throws.
	var best: Node3D = null
	var best_d := INF
	var any_ready := false
	for s in _special_users():
		if s.special_kind != kind or not s.special_ready():
			continue
		any_ready = true
		var d: float = s.global_position.distance_to(point)
		if d > w["max"]:
			continue
		# Rockets fly straight: prefer a man with a clear line to the target.
		if kind == "rocket" and not _clear_shot(s, aim["target"], point):
			d += 100.0
		if d < best_d:
			best_d = d
			best = s
	print("[debug] best=", best, " any_ready=", any_ready)
	if best == null:
		main.special_msg(("TOO FAR FOR %s  (%d m)" % [Weapons.SPECIALS[kind][1], int(w["max"])]) if any_ready else "%s RELOADING" % Weapons.SPECIALS[kind][1], 1.5)
		return
	best.order_special(aim["target"], point)
	main.on_special_used(kind, best)


func threat_dir_for(t: int) -> Vector3:
	return teams[t if split else 0]["threat_dir"]


func fire_mode_text() -> String:
	var t := "HOLD FIRE"
	match fire_mode():
		FOCUS:
			t = "FOCUS FIRE"
		AT_WILL:
			t = "FIRE AT WILL"
	if split:
		t += "   (TEAM %s COVERING)" % TEAM_NAMES[1 - active]
	return t


# ---------------------------------------------------------------- orders

## Right click = one special. Caught in _input (before any UI), so a click
## is never swallowed or missed, even at a low frame rate. The click that
## grabs the mouse doesn't count.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		print("[debug] RMB pressed=", event.pressed, " captured=", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			use_special()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("take_cover"):
		if in_cover:
			leave_cover()
		else:
			take_cover()
	elif event.is_action_pressed("auto_fire"):
		auto_fire = not auto_fire
	elif event.is_action_pressed("move_order"):
		var p: Variant = main.reticle_ground_point()
		if p != null:
			move_to(p)
	elif event.is_action_pressed("split_teams"):
		join_teams() if split else split_teams()
	elif event.is_action_pressed("switch_team"):
		switch_team()
	elif event.is_action_pressed("bound"):
		var p: Variant = main.reticle_ground_point()
		if p != null:
			start_bound(p)
	elif event.is_action_pressed("hold_position"):
		set_holding(not holding)
	elif event.is_action_pressed("cycle_special"):
		cycle_special()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
		select_special(event.physical_keycode - KEY_1)



## Send the active team to a point. They break cover and move as a group;
## WASD cancels the order.
func move_to(p: Vector3, t := -1) -> void:
	if t < 0:
		t = active
		bound = {}
		set_holding(false)
	var lim: float = main.NAV_HALF - 2.0
	teams[t]["order_target"] = CoverUtil.push_out(main.solid_defs, Vector3(clampf(p.x, -lim, lim), 0, clampf(p.z, -lim, lim)), 1.0)
	if teams[t]["in_cover"]:
		leave_cover(t)
	_show_ping(teams[t]["order_target"])


## T: split into fire teams A and B, side by side (B to the right).
func split_teams() -> void:
	if soldiers.size() < 2:
		main.notify("NOT ENOUGH MEN TO SPLIT")
		return
	var base: Vector3 = teams[0]["anchor"]
	var was_in_cover: bool = teams[0]["in_cover"]
	# Spread specialists across both teams, then alternate riflemen.
	var order := soldiers.duplicate()
	order.sort_custom(func(a, b): return _role_rank(a.role) < _role_rank(b.role))
	for i in order.size():
		order[i].team = i % 2
	split = true
	active = 0
	var right: Vector3 = main.cam_rig.get_yaw_basis() * Vector3.RIGHT
	for t in 2:
		var members := team_members(t)
		var c := Vector3.ZERO
		for s in members:
			c += s.global_position
		c /= float(maxi(1, members.size()))
		c.y = 0
		var side := -1.0 if t == 0 else 1.0
		teams[t]["anchor"] = c if was_in_cover else CoverUtil.push_out(main.cover_defs, base + right * 2.5 * side, 0.7)
		teams[t]["in_cover"] = was_in_cover
		teams[t]["order_target"] = null
		teams[t]["threat_dir"] = teams[0]["threat_dir"]
	_make_offsets()
	main.notify("SPLIT INTO FIRE TEAMS A + B  -  Q SWITCHES TEAM")


func _role_rank(role: String) -> int:
	return {"anti_armor": 0, "grenadier": 1}.get(role, 2)


## T again: everyone regroups on the team you're commanding.
func join_teams() -> void:
	var base: Vector3 = teams[active]["anchor"]
	bound = {}
	split = false
	for s in soldiers:
		s.team = 0
	teams[0]["anchor"] = base
	teams[0]["order_target"] = null
	active = 0
	leave_cover(0)
	_make_offsets()
	main.notify("TEAMS JOINED")


## Q: command the other fire team.
func switch_team() -> void:
	if not split:
		return
	active = 1 - active
	scout_offset = Vector3.ZERO
	main.notify("COMMANDING TEAM %s" % TEAM_NAMES[active])


## H: hold position. Nobody moves; WASD scouts ahead with the camera.
func set_holding(on: bool) -> void:
	if on == holding:
		return
	holding = on
	scout_offset = Vector3.ZERO
	if on:
		for t in 2:
			teams[t]["order_target"] = null
		bound = {}
		main.notify("HOLDING POSITION  -  WASD SCOUTS, H TO RELEASE")
	else:
		main.notify("RELEASED HOLD")


## B: bounding advance to `target`. Splits if needed. The team further from
## the target moves first while the other covers from where it is.
func start_bound(target: Vector3) -> void:
	if soldiers.size() < 2:
		move_to(target)
		return
	set_holding(false)
	if not split:
		split_teams()
	var d0: float = teams[0]["anchor"].distance_to(target)
	var d1: float = teams[1]["anchor"].distance_to(target)
	bound = {"target": target, "mover": 0 if d0 > d1 else 1, "phase": "start", "timer": 0.0}
	_show_ping(target)
	main.notify("BOUNDING  -  ONE TEAM MOVES, ONE COVERS")


func _update_bound(delta: float) -> void:
	var target: Vector3 = bound["target"]
	var mover: int = bound["mover"]
	var cover_t := 1 - mover
	match bound["phase"]:
		"start":
			# The covering team gets down; the moving team jumps ahead of it.
			if not teams[cover_t]["in_cover"]:
				_take_cover_facing(cover_t, target)
			var from: Vector3 = teams[cover_t]["anchor"]
			var to_t := target - from
			to_t.y = 0
			var dist := to_t.length()
			var dir := to_t.normalized() if dist > 0.1 else Vector3.ZERO
			var lateral := dir.cross(Vector3.UP) * (3.0 if mover == 1 else -3.0)
			var dest: Vector3 = target + lateral * 0.6 if dist < BOUND_STEP + 3.0 else from + dir * BOUND_STEP + lateral
			move_to(CoverUtil.push_out(main.cover_defs, dest, 0.7), mover)
			bound["phase"] = "moving"
		"moving":
			if teams[mover]["order_target"] == null:
				_take_cover_facing(mover, target)
				bound["phase"] = "settle"
				bound["timer"] = 1.5
		"settle":
			bound["timer"] -= delta
			if bound["timer"] <= 0.0:
				if teams[0]["anchor"].distance_to(target) < 6.5 and teams[1]["anchor"].distance_to(target) < 6.5:
					bound = {}
					main.notify("BOUND COMPLETE  -  BOTH TEAMS IN COVER")
					return
				bound["mover"] = cover_t
				bound["phase"] = "start"


func _take_cover_facing(t: int, target: Vector3) -> void:
	var dir: Vector3 = target - teams[t]["anchor"]
	dir.y = 0
	take_cover(t, dir.normalized() if dir.length() > 1.0 else main.camera_forward())


## Brief fading ring where a move order lands.
func _show_ping(p: Vector3) -> void:
	if _ping == null:
		_ping = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.8
		t.outer_radius = 1.0
		_ping.mesh = t
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.45, 1.0, 0.3, 0.8)
		_ping.material_override = m
		_ping.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ping)
	_ping.global_position = p + Vector3(0, 0.05, 0)
	_ping.scale = Vector3(1, 0.1, 1)
	_ping.visible = true
	_ping_t = 1.5


# ---------------------------------------------------------------- movement

func get_focus() -> Vector3:
	return teams[active]["anchor"] + scout_offset


func centroid(t := -1) -> Vector3:
	var list: Array = soldiers if t < 0 else team_members(t)
	var c := Vector3.ZERO
	for s in list:
		c += s.global_position
	return c / float(maxi(1, list.size()))


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var lim: float = main.NAV_HALF - 2.0
	if input.length() > 0.05:
		var dir: Vector3 = main.cam_rig.get_yaw_basis() * Vector3(input.x, 0, input.y)
		dir.y = 0
		dir = dir.normalized() * minf(input.length(), 1.0)
		if holding:
			scout_offset += dir * MOVE_SPEED * 1.6 * delta
			if scout_offset.length() > SCOUT_RANGE:
				scout_offset = scout_offset.normalized() * SCOUT_RANGE
		else:
			bound = {}
			order_target = null
			if in_cover:
				leave_cover()
			# Slow the anchor down if the team is lagging so the group stays tight.
			var lag: float = anchor.distance_to(centroid(active))
			var speed := MOVE_SPEED * clampf(1.0 - (lag - 3.0) / 4.0, 0.3, 1.0)
			# The anchor is a ghost point with no collision: it passes straight
			# through crates, and each soldier finds his own way around.
			var a: Vector3 = anchor + dir * speed * delta
			# ...but buildings and compound walls stop it, like a real street.
			anchor = CoverUtil.push_out(main.solid_defs, Vector3(clampf(a.x, -lim, lim), 0, clampf(a.z, -lim, lim)), 1.0)
	if not bound.is_empty():
		_update_bound(delta)

	for t in (2 if split else 1):
		var team: Dictionary = teams[t]
		var ot: Variant = team["order_target"]
		if ot != null and not (t == active and input.length() > 0.05 and not holding):
			var to: Vector3 = ot - team["anchor"]
			to.y = 0
			if to.length() < 0.4:
				team["order_target"] = null
			else:
				var lag: float = team["anchor"].distance_to(centroid(t))
				var speed := MOVE_SPEED * clampf(1.0 - (lag - 3.0) / 4.0, 0.3, 1.0)
				team["anchor"] += to.normalized() * minf(speed * delta, to.length())
		if not team["in_cover"]:
			for s in team_members(t):
				s.move_target = CoverUtil.push_out(main.cover_defs, team["anchor"] + s.slot_offset, 0.6)

	if _ping and _ping.visible:
		_ping_t -= delta
		(_ping.material_override as StandardMaterial3D).albedo_color.a = clampf(_ping_t / 1.5, 0.0, 1.0) * 0.8
		if _ping_t <= 0.0:
			_ping.visible = false

	if forced_specials:
		_forced_special_t -= delta
		if _forced_special_t <= 0.0:
			_forced_special_t = 1.5
			use_special()

	_check_joins()


# ---------------------------------------------------------------- cover

## Every soldier in the team scrambles to the closest free cover spot that
## shields him from `facing` (default: where the camera looks), with a pull
## toward his team so nobody runs off alone.
func take_cover(t := -1, facing := Vector3.ZERO) -> void:
	if t < 0:
		t = active
	var team: Dictionary = teams[t]
	team["in_cover"] = true
	team["order_target"] = null
	team["threat_dir"] = facing if facing != Vector3.ZERO else main.camera_forward()
	var tdir: Vector3 = team["threat_dir"]
	var members := team_members(t)
	var centre: Vector3 = team["anchor"]

	# Spots the other team already holds are off limits.
	var claimed: Array = []
	for s in soldiers:
		if split and s.team != t and s.state != 0:   # 0 = FOLLOW
			claimed.append(s.cover_pos)

	var candidates: Array = []
	for cp in main.cover_points:
		if cp["pos"].distance_to(centre) > COVER_SEARCH:
			continue
		if cp["normal"].dot(tdir) > -0.3:
			continue  # box isn't between this spot and the threat
		candidates.append(cp)

	var pairs: Array = []
	for s in members:
		for ci in candidates.size():
			var cpos: Vector3 = candidates[ci]["pos"]
			var score: float = s.global_position.distance_to(cpos) + COHESION_WEIGHT * cpos.distance_to(centre)
			pairs.append([score, s.index, ci])
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var assigned := {}
	var mine: Array = []
	for p in pairs:
		if assigned.has(p[1]):
			continue
		var cpos: Vector3 = candidates[p[2]]["pos"]
		var free := true
		for c in claimed + mine:
			if c.distance_to(cpos) < MIN_COVER_GAP:
				free = false
				break
		if not free:
			continue
		assigned[p[1]] = candidates[p[2]]
		mine.append(cpos)
		if assigned.size() == members.size():
			break

	# Lean-out spots: two men on neighbouring sides of a tall crate would
	# otherwise lean out at the same corner. Each man claims his own.
	var all_spots: Array = claimed + mine
	var taken_leans: Array = []
	for s in members:
		if not assigned.has(s.index):
			s.go_to_cover(s.global_position, false)  # no spot: get low where you are
			continue
		var cp: Dictionary = assigned[s.index]
		var leans: Array = []
		for lp in cp["peeks"]:
			var clear := true
			for c in all_spots:
				if c != cp["pos"] and c.distance_to(lp) < 1.0:
					clear = false
			for x in taken_leans:
				if x.distance_to(lp) < 1.0:
					clear = false
			if clear:
				leans.append(lp)
		if leans.is_empty() and not cp["peeks"].is_empty():
			leans = [_least_crowded(cp["peeks"], all_spots + taken_leans, cp["pos"])]
		taken_leans.append_array(leans)
		s.go_to_cover(cp["pos"], true, leans)


## The lean spot furthest from everyone else's spots.
func _least_crowded(options: Array, others: Array, own: Vector3) -> Vector3:
	var best: Vector3 = options[0]
	var best_d := -1.0
	for o in options:
		var d := INF
		for x in others:
			if x != own:
				d = minf(d, o.distance_to(x))
		if d > best_d:
			best_d = d
			best = o
	return best


func leave_cover(t := -1) -> void:
	if t < 0:
		t = active
	teams[t]["in_cover"] = false
	for s in team_members(t):
		s.leave_cover()


# ---------------------------------------------------------------- casualties & status

func on_soldier_killed(s: Node3D) -> void:
	soldiers.erase(s)
	kia += 1
	for i in soldiers.size():
		soldiers[i].index = i
	if split and (team_members(0).is_empty() or team_members(1).is_empty()):
		join_teams()   # a team was wiped out: survivors regroup
	_make_offsets()
	if soldiers.is_empty():
		main.notify("SQUAD WIPED OUT  -  PRESS R TO RESTART")
	else:
		main.notify("%s DOWN" % s.role_name())


func avg_suppression() -> float:
	if soldiers.is_empty():
		return 0.0
	var t := 0.0
	for s in soldiers:
		t += s.suppression
	return t / float(soldiers.size())


func _team_status(t: int) -> String:
	var members := team_members(t)
	if teams[t]["order_target"] != null:
		return "MOVING"
	if not teams[t]["in_cover"]:
		return "HOLDING" if holding else "READY"
	var settled := 0
	for s in members:
		if s.is_settled():
			settled += 1
	return ("IN COVER" if settled == members.size() else "TAKING COVER") + " %d/%d" % [settled, members.size()]


func status_text() -> String:
	var tag := ""
	if holding:
		tag = "  [HOLD - SCOUTING]"
	elif not bound.is_empty():
		tag = "  [BOUNDING]"
	if not split:
		if not in_cover:
			return ("HOLDING POSITION" if holding else "MOVING (loose cluster)") + tag
		var settled := 0
		var exposed := 0
		for s in soldiers:
			if s.is_settled():
				settled += 1
			if not s.has_real_cover:
				exposed += 1
		var txt := "IN COVER" if settled == soldiers.size() else "TAKING COVER"
		txt += "  (%d/%d in position" % [settled, soldiers.size()]
		if exposed > 0:
			txt += ", %d with no cover" % exposed
		return txt + ")" + tag
	var parts: Array = []
	for t in 2:
		var mark := ">" if t == active else " "
		parts.append("%sTEAM %s (%d) %s" % [mark, TEAM_NAMES[t], team_members(t).size(), _team_status(t)])
	return "   ".join(parts) + tag


## Squad make-up plus the state of every special weapon.
func roster_text() -> String:
	var counts := {}
	var gl := [0, 0]
	var rk := [0, 0]
	for s in soldiers:
		counts[s.role] = counts.get(s.role, 0) + 1
		if s.role == "grenadier":
			gl[1] += 1
			if s.secondary_cd <= 0.0:
				gl[0] += 1
		elif s.role == "anti_armor":
			rk[1] += 1
			if s.secondary_cd <= 0.0:
				rk[0] += 1
	var parts: Array = []
	for r in [["rifleman", "RIFLE"], ["grenadier", "GREN"], ["anti_armor", "AT"]]:
		if counts.has(r[0]):
			parts.append("%d %s" % [counts[r[0]], r[1]])
	var wounded := 0
	for s in soldiers:
		if s.hp < s.MAX_HP * 0.5:
			wounded += 1
	var t := "%d MEN  (%s)" % [soldiers.size(), ", ".join(parts)]
	if wounded > 0:
		t += "   %d WOUNDED" % wounded
	if kia > 0:
		t += "   %d KIA" % kia
	return t
