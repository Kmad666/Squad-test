extends Node3D
## The squad: one unit, or two fire teams.
##
## Joined: WASD moves an anchor point, soldiers hold a loose cluster around
## it, and the cover order sends each soldier to his own cover spot on the far
## side of a crate from where the camera faces.
##
## Cover is a state the unit stays in until you call it off (C again). Moving
## while in cover (WASD or a move order) goes cover to cover: each man heads
## where you're sending the unit and makes for the nearest cover to get
## behind there, running low from spot to spot. Where there's no cover, he
## goes prone and crawls.
##
## Split (T): two fire teams, A and B (coloured helmet patches). You command
## the active team (Q switches); the other team holds where it is and gives
## covering fire at will. B: bounding advance to the point under the reticle,
## teams leapfrog (one moves, the other covers). H: hold position, WASD then
## scouts ahead with the camera instead of moving anyone.
##
## Teams waiting in the field join when either fire team walks up to them.
##
## Orders go through the sergeant: he gives a hand signal (move out, halt,
## take cover, open fire) and each man reacts after a delay that grows with
## his distance from his team leader, so the unit moves with some weight.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SoldierScript = preload("res://scripts/soldier.gd")
const LavScript = preload("res://scripts/lav.gd")
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
const COVER_REACH := 4.5         # cover move: a spot counts if it's this close to where he's headed
const COVER_SWITCH := 1.5        # ...and must beat the spot he holds by this much
const COVER_LEAD := 6.0          # cover move: the unit's point stays this close to the men
const SHIFT_EVERY := 0.4         # cover move: how often the men re-pick their spots
const COVER_SPREAD := 4.5        # cover move: furthest a man keeps from the unit's point
const TEAM_NAMES := ["A", "B"]
const STACK_ROW := 0.95          # LAV stack: spacing between men in a file
const STACK_FACES := ["REAR", "FRONT", "RIGHT", "LEFT"]

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

var _was_moving := [false, false]   # per team, for move / halt signals
var _last_fire_mode := HOLD
var fire_log: Array = []           # last fire orders, newest first: {text, t, n}
var lav: Node3D = null             # the unit's LAV (maps with LAV := true)
var _stack_face := -1              # which side of the LAV the infantry stack on (STACK_FACES)
var _stack_slot := {}              # soldier -> slot index in the stack
var _stack_ids: Array = []
var _stack_threat := Vector3.FORWARD
var move_vel := Vector3.ZERO       # how the unit you command is moving (smoothed, m/s)
var _prev_anchor := Vector3.ZERO
var _prev_active := -1
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
		teams.append({"anchor": Vector3.ZERO, "in_cover": false, "order_target": null, "threat_dir": Vector3.FORWARD,
			"order_id": 0, "move_id": 0,    # ids: a man's delayed reaction is dropped if a newer order replaced it
			"shift_t": 0.0, "shifted": false})   # cover move: next re-pick, and one last re-pick owed on stopping


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
	soldiers[0].set_sergeant(true)


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


# ---------------------------------------------------------------- command chain

func sergeant() -> Node3D:
	for s in soldiers:
		if s.is_sergeant:
			return s
	return null


## Who signals for a team: the sergeant if he's in it, else its first man.
func leader_of(t: int) -> Node3D:
	var members := team_members(t if split else 0)
	if members.is_empty():
		return null
	var sgt := sergeant()
	if sgt and sgt in members:
		return sgt
	return members[0]


## How long a man takes to react to an order: the leader almost at once,
## everyone else a beat later, more the further they are from him.
func reaction_delay(s: Node3D) -> float:
	var lead := leader_of(s.team if split else 0)
	if lead == null or lead == s:
		return 0.12
	return 0.22 + 0.065 * s.global_position.distance_to(lead.global_position) + randf() * 0.15


func _signal(t: int, kind: String, callout: String, toward := Vector3.ZERO) -> void:
	var lead := leader_of(t)
	if lead:
		lead.signal_hand(kind, toward)
	main.sgt_callout(("SGT: " if lead and lead.is_sergeant else "TEAM %s: " % TEAM_NAMES[t]) + callout)


func _on_move_start(t: int) -> void:
	_signal(t, "move", "COVER TO COVER, MOVE" if teams[t]["in_cover"] else "MOVE OUT")
	teams[t]["move_id"] += 1
	for s in team_members(t):
		s.hold_here()
		s.schedule(reaction_delay(s), _react_move.bind(s, t, teams[t]["move_id"]))


func _on_halt(t: int) -> void:
	_signal(t, "halt", "HALT")
	teams[t]["move_id"] += 1
	for s in team_members(t):
		s.schedule(reaction_delay(s), _react_halt.bind(s, t, teams[t]["move_id"]))


func _current(t: int, key: String, id: int) -> bool:
	return teams[t][key] == id


func _react_move(s: Node3D, t: int, id: int) -> void:
	if _current(t, "move_id", id) and not s.dead:
		s.release_hold()


func _react_halt(s: Node3D, t: int, id: int) -> void:
	if _current(t, "move_id", id) and not s.dead:
		s.halt_here()


func _react_cover(s: Node3D, t: int, id: int, pos: Vector3, real: bool, leans: Array) -> void:
	if _current(t, "order_id", id) and not s.dead:
		s.go_to_cover(pos, real, leans)


func _react_prone(s: Node3D, t: int, id: int) -> void:
	if _current(t, "order_id", id) and not s.dead:
		s.go_prone(s.global_position)


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
		s.update_light()          # LOW graphics lights every third man, by index


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
	var users := _special_users()
	var from := Vector3.ZERO
	for u in users:
		from += u.global_position
	from /= float(maxi(1, users.size()))
	var aim: Dictionary = main.special_target(kind, from, w["max"])
	var point: Vector3 = aim["point"]
	var tgt: Node3D = aim["target"]
	# The nearest ready man carrying this kind throws / fires.
	var best: Node3D = null
	var best_d := INF
	for s in users:
		if s.special_kind != kind or not s.special_ready():
			continue
		var d: float = s.global_position.distance_to(point)
		# Rockets fly straight: prefer a man with a clear line to the target.
		if kind == "rocket" and not _clear_shot(s, tgt, point):
			d += 100.0
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		main.special_msg("%s RELOADING" % Weapons.SPECIALS[kind][1], 1.2)
		return
	# Aimed further than he can throw / lob: it goes as far as it can that way.
	var reach: float = best.global_position.distance_to(point)
	if kind != "rocket" and reach > w["max"]:
		var dir := point - best.global_position
		dir.y = 0
		point = best.global_position + dir.normalized() * w["max"] * 0.95
		tgt = null
	best.order_special(tgt, point)
	main.on_special_used(kind, best)
	log_fire("%s  %dm" % [{"frag": "FRAG OUT", "flash": "FLASHBANG", "gl": "40MM AWAY", "rocket": "ROCKET AWAY"}.get(kind, kind), roundi(best.global_position.distance_to(point))])


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
	elif event.is_action_pressed("lav_toggle"):
		toggle_lav()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
		select_special(event.physical_keycode - KEY_1)



## Send the active team to a point; WASD cancels the order. In cover, they
## go there cover to cover (crawling where there's none); otherwise they move
## as a group. A bound (`t` given) always breaks cover and runs.
func move_to(p: Vector3, t := -1) -> void:
	var ordered := t < 0
	if ordered:
		t = active
		bound = {}
		set_holding(false)
	var lim: float = main.nav_half - 2.0
	teams[t]["order_target"] = CoverUtil.push_out(main.solid_defs, Vector3(clampf(p.x, -lim, lim), 0, clampf(p.z, -lim, lim)), 1.0)
	if teams[t]["in_cover"] and not ordered:
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
		teams[t]["shifted"] = false
		if was_in_cover:
			# each team keeps its men's spread, measured from its own middle
			var at := {}
			for s in members:
				at[s.index] = s.cover_pos if s.state != 0 else s.global_position
			_set_cover_offsets(t, at)
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
	var a: Vector3 = teams[active]["anchor"]
	if lav_with(active) and not team_members(active).is_empty():
		a = lav.global_position.lerp(centroid(active), 0.5)    # the LAV and the men behind it
		a.y = 0
	elif teams[active]["in_cover"] and not team_members(active).is_empty():
		a = a.lerp(centroid(active), 0.5)    # cover move: the point runs ahead, keep the men in view
	return a + scout_offset


func centroid(t := -1) -> Vector3:
	var list: Array = soldiers if t < 0 else team_members(t)
	var c := Vector3.ZERO
	for s in list:
		c += s.global_position
	return c / float(maxi(1, list.size()))


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var lim: float = main.nav_half - 2.0
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
			# Slow the anchor down if the team is lagging so the group stays tight.
			var speed := MOVE_SPEED * _lag_factor(active)
			if in_cover:
				speed = MOVE_SPEED   # held to the men by _lead() instead
			# The anchor is a ghost point with no collision: it passes straight
			# through crates, and each soldier finds his own way around.
			var a: Vector3 = _lead(active, anchor + dir * speed * delta)
			# ...but buildings and compound walls stop it, like a real street.
			anchor = CoverUtil.push_out(main.solid_defs, Vector3(clampf(a.x, -lim, lim), 0, clampf(a.z, -lim, lim)), 1.0)
	if not bound.is_empty():
		_update_bound(delta)

	# Men who were stacked on the LAV but aren't any more (it left, was hit,
	# or their team split off) get up and rejoin their team.
	for s in soldiers:
		if s.stacked and not lav_with(s.team):
			s.stacked = false
			if not teams[s.team]["in_cover"]:
				s.leave_cover()
	if lav and lav.alive and not lav.together:
		lav.speed_cap = 1.0

	# Move-out / halt signals when a team starts or stops moving.
	var pushing := input.length() > 0.05 and not holding
	for t in (2 if split else 1):
		var moving: bool = teams[t]["order_target"] != null or (t == active and pushing)
		if moving and not _was_moving[t]:
			_on_move_start(t)
		elif not moving and _was_moving[t] and not teams[t]["in_cover"]:
			_on_halt(t)
		_was_moving[t] = moving

	# Open fire: the leader points at the reticle; the men follow after their
	# reaction delays (handled per soldier).
	var fm := fire_mode()
	if fm != _last_fire_mode:
		if fm != HOLD and _last_fire_mode == HOLD:
			_signal(active, "fire", "OPEN FIRE" if fm == FOCUS else "FIRE AT WILL", main.camera_forward())
		elif fm == HOLD:
			main.sgt_callout(("SGT: " if leader_of(active) and leader_of(active).is_sergeant else "") + "CEASE FIRE")
		log_fire(["HOLD FIRE", "FIRE AT WILL", "FOCUS FIRE"][fm])
		_last_fire_mode = fm

	for t in (2 if split else 1):
		var team: Dictionary = teams[t]
		var ot: Variant = team["order_target"]
		if ot != null and not (t == active and input.length() > 0.05 and not holding):
			var to: Vector3 = ot - team["anchor"]
			to.y = 0
			if to.length() < 0.4:
				team["order_target"] = null
			else:
				var speed := MOVE_SPEED * _lag_factor(t)
				if team["in_cover"]:
					speed = MOVE_SPEED
				team["anchor"] = _lead(t, team["anchor"] + to.normalized() * minf(speed * delta, to.length()))
		if lav_with(t):
			_lav_stack(t)
		elif not team["in_cover"]:
			for s in team_members(t):
				s.move_target = CoverUtil.push_out(main.cover_defs, team["anchor"] + s.slot_offset, 0.6)
		elif _was_moving[t]:
			# Cover move: re-pick spots as the unit's point moves on.
			team["shift_t"] -= delta
			if team["shift_t"] <= 0.0:
				team["shift_t"] = SHIFT_EVERY
				_cover_shift(t)
			team["shifted"] = true
		elif team["shifted"]:
			team["shifted"] = false          # stopped: one last pick for where he ended up
			team["shift_t"] = 0.0
			_cover_shift(t)

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
	_track_motion(delta)


## Smoothed velocity of the unit you command, for the HUD's direction arrow.
func _track_motion(delta: float) -> void:
	var a: Vector3 = anchor
	if _prev_active != active or delta <= 0.0:
		_prev_active = active
		_prev_anchor = a
		return
	var v := (a - _prev_anchor) / delta
	v.y = 0
	_prev_anchor = a
	move_vel = move_vel.lerp(v, 1.0 - exp(-6.0 * delta))


## Fire orders for the HUD log. A repeat of the newest order within a couple
## of seconds counts up instead of filling the log.
func log_fire(text: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not fire_log.is_empty() and fire_log[0]["text"] == text and now - fire_log[0]["t"] < 2.5:
		fire_log[0]["n"] += 1
		fire_log[0]["t"] = now
		return
	fire_log.push_front({"text": text, "t": now, "n": 1})
	if fire_log.size() > 3:
		fire_log.resize(3)


# ---------------------------------------------------------------- cover

## Every soldier in the team scrambles to the closest free cover spot that
## shields him from `facing` (default: where the camera looks), with a pull
## toward his team so nobody runs off alone.
func take_cover(t := -1, facing := Vector3.ZERO) -> void:
	if t < 0:
		t = active
	if lav_with(t):
		main.notify("ALREADY IN COVER BEHIND THE LAV  -  Z SENDS IT TO OVERWATCH")
		return
	var team: Dictionary = teams[t]
	team["in_cover"] = true
	team["order_target"] = null
	team["shifted"] = false
	team["threat_dir"] = facing if facing != Vector3.ZERO else main.camera_forward()
	var tdir: Vector3 = team["threat_dir"]
	var members := team_members(t)
	_signal(t, "cover", "TAKE COVER")
	team["order_id"] += 1
	var oid: int = team["order_id"]
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
	var at := {}
	for s in members:
		at[s.index] = assigned[s.index]["pos"] if assigned.has(s.index) else s.global_position
	_set_cover_offsets(t, at)
	for s in members:
		if not assigned.has(s.index):
			# no spot: get down flat where you are (after seeing the signal)
			s.schedule(0.3 + reaction_delay(s), _react_prone.bind(s, t, oid))
			continue
		var cp: Dictionary = assigned[s.index]
		var leans := _leans_for(cp, all_spots, taken_leans)
		taken_leans.append_array(leans)
		s.schedule(0.3 + reaction_delay(s), _react_cover.bind(s, t, oid, cp["pos"], true, leans))


## The unit's point moves to the middle of where its men are taking cover
## (`at`: soldier index -> his spot), and each man remembers where he is in
## that spread (within COVER_SPREAD). A cover move keeps that shape:
## left-hand men stay on the left, and so on.
func _set_cover_offsets(t: int, at: Dictionary) -> void:
	var members := team_members(t)
	if members.is_empty():
		return
	var c := Vector3.ZERO
	for s in members:
		c += at[s.index]
	c /= float(members.size())
	c.y = 0
	teams[t]["anchor"] = c
	for s in members:
		var off: Vector3 = at[s.index] - c
		off.y = 0
		s.cover_off = off.limit_length(COVER_SPREAD)


## Lean-out spots for a man behind tall cover `cp`, clear of everyone else's
## spots and of lean spots already handed out.
func _leans_for(cp: Dictionary, all_spots: Array, taken_leans: Array) -> Array:
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
	return leans


## Cover move: the unit's point may run ahead of the men, but no further
## than COVER_LEAD from them, so it waits while they work their way up.
func _lead(t: int, p: Vector3) -> Vector3:
	if not teams[t]["in_cover"]:
		return p
	var c := centroid(t)
	var off := p - c
	off.y = 0
	if off.length() <= COVER_LEAD:
		return p
	return Vector3(c.x, p.y, c.z) + off.normalized() * COVER_LEAD


## Cover move: every man in team `t` looks at where the unit is sending him
## (its point plus his place in the spread) and takes the nearest free cover
## spot within COVER_REACH of there that shields him from the threat (the
## way the camera faces). He keeps the spot he has unless a new one is
## clearly better, so a short nudge doesn't shuffle everyone. No such spot:
## he goes prone and crawls to where he's headed.
func _cover_shift(t: int) -> void:
	var team: Dictionary = teams[t]
	team["order_id"] += 1              # this supersedes any reaction still pending
	if t == active:
		team["threat_dir"] = main.camera_forward()
	var tdir: Vector3 = team["threat_dir"]
	var members := team_members(t)
	var centre: Vector3 = team["anchor"]
	var claimed: Array = []
	for s in soldiers:
		if split and s.team != t and s.state != 0:   # 0 = FOLLOW
			claimed.append(s.cover_pos)
	var want := {}
	for s in members:
		want[s.index] = CoverUtil.push_out(main.cover_defs, centre + s.cover_off, 0.6)
	var candidates: Array = []
	for cp in main.cover_points:
		if cp["normal"].dot(tdir) <= -0.3 and cp["pos"].distance_to(centre) < COVER_SEARCH:
			candidates.append(cp)
	var pairs: Array = []
	for s in members:
		var w: Vector3 = want[s.index]
		var holding_spot: bool = s.state != 0 and s.has_real_cover
		for ci in candidates.size():
			var cpos: Vector3 = candidates[ci]["pos"]
			var d := cpos.distance_to(w)
			if d > COVER_REACH:
				continue
			var cost: float = d + 0.25 * s.global_position.distance_to(cpos)
			if holding_spot and s.cover_pos.distance_to(cpos) < 0.3:
				cost -= COVER_SWITCH       # staying put beats a marginal move
			pairs.append([cost, s.index, ci])
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
		if free:
			assigned[p[1]] = candidates[p[2]]
			mine.append(cpos)
	var all_spots: Array = claimed + mine
	var taken_leans: Array = []
	var flat: Array = []         # where the men going prone will lie
	for s in members:
		if assigned.has(s.index):
			var cp: Dictionary = assigned[s.index]
			if s.state != 0 and s.has_real_cover and s.cover_pos.distance_to(cp["pos"]) < 0.3:
				taken_leans.append_array(s.peeks)
				continue                   # already there, or on his way
			var leans := _leans_for(cp, all_spots, taken_leans)
			taken_leans.append_array(leans)
			s.go_to_cover(cp["pos"], true, leans, true)
	for s in members:
		if assigned.has(s.index):
			continue
		var spot := _crawl_spot(want[s.index], tdir, flat + all_spots)
		flat.append(spot)
		if s.is_prone() and s.cover_pos.distance_to(spot) < 1.0:
			continue                       # close enough: keep crawling where he was
		s.go_prone(spot)


## Where a prone man lies: near `p`, but not on top of anyone (bodies are
## long, so men lying one behind the other need more room than side by side).
func _crawl_spot(p: Vector3, tdir: Vector3, taken: Array) -> Vector3:
	var across := tdir.cross(Vector3.UP).normalized()
	for k in [0, 1, -1, 2, -2, 3, -3]:
		var q := CoverUtil.push_out(main.cover_defs, p + across * 1.1 * k, 0.6)
		var clear := true
		for o in taken:
			var off: Vector3 = q - o
			var along := off.dot(tdir) / 2.0
			var side := off.dot(across) / 1.0
			if along * along + side * side < 1.0:
				clear = false
				break
		if clear:
			return q
	return p


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
	teams[t]["shifted"] = false
	teams[t]["order_id"] += 1
	for s in team_members(t):
		s.schedule(reaction_delay(s), _break_cover.bind(s, t, teams[t]["order_id"]))


## One man leaves cover: low and slow for ~2 s, covering the reticle.
func _break_cover(s: Node3D, t: int, id: int) -> void:
	if s.dead or not _current(t, "order_id", id):
		return
	s.leave_cover()
	s.release_hold()
	s.start_low(1.8 + randf() * 0.4)


# ---------------------------------------------------------------- casualties & status

func on_soldier_killed(s: Node3D) -> void:
	soldiers.erase(s)
	kia += 1
	if s.is_sergeant and not soldiers.is_empty():
		var heir: Node3D = soldiers[0]
		for c in soldiers:
			if c.role == "rifleman":
				heir = c
				break
		heir.set_sergeant(true)
		main.sgt_callout("SERGEANT DOWN  -  %s TAKES COMMAND" % heir.role_name().replace("SERGEANT", "RIFLEMAN"))
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
	if lav_with(t):
		return "BEHIND LAV %d/%d" % [stacked_count(t), members.size()]
	if not teams[t]["in_cover"]:
		if teams[t]["order_target"] != null:
			return "MOVING"
		return "HOLDING" if holding else "READY"
	var settled := 0
	var flat := 0
	for s in members:
		if s.is_settled():
			settled += 1
		if s.is_prone():
			flat += 1
	var txt := "COVER MOVE" if _was_moving[t] else ("IN COVER" if settled == members.size() else "TAKING COVER")
	txt += " %d/%d" % [settled, members.size()]
	if flat > 0:
		txt += " %d PRONE" % flat
	return txt


func status_text() -> String:
	var tag := ""
	if holding:
		tag = "  [HOLD - SCOUTING]"
	elif not bound.is_empty():
		tag = "  [BOUNDING]"
	if not split:
		if lav_with(0):
			return "STACKED BEHIND THE LAV (%s)  (%d/%d in position)" % [STACK_FACES[maxi(_stack_face, 0)], stacked_count(0), soldiers.size()] + tag
		if not in_cover:
			return ("HOLDING POSITION" if holding else "MOVING (loose cluster)") + tag
		var settled := 0
		var flat := 0
		for s in soldiers:
			if s.is_settled():
				settled += 1
			if s.is_prone():
				flat += 1
		var txt := "IN COVER" if settled == soldiers.size() else "TAKING COVER"
		if _was_moving[0]:
			txt = "MOVING COVER TO COVER"
		txt += "  (%d/%d in position" % [settled, soldiers.size()]
		if flat > 0:
			txt += ", %d prone" % flat
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


# ---------------------------------------------------------------- the LAV (combined arms)
# With the LAV, the vehicle leads: it drives to the unit's point and the
# infantry stack up close behind it, on the side away from the enemy, in two
# tight files. Each man leans out past the hull to fire and ducks back. Z
# sends it to hold where it is (overwatch, fires at will once a fight is on)
# and calls it back.

func spawn_lav(at: Vector3, yaw: float) -> void:
	lav = LavScript.new()
	lav.name = "LAV"
	lav.main = main
	lav.squad = self
	lav.nav_map = main.vehicle_nav_map
	add_child(lav)
	lav.global_position = at
	lav.rotation.y = yaw
	lav.goal = at
	teams[0]["anchor"] = Vector3(at.x, 0, at.z)    # the LAV is the front of the unit
	_stack_threat = lav.forward()


## The fire team the LAV works with (A, unless A is gone).
func lav_team() -> int:
	if split and team_members(0).is_empty():
		return 1
	return 0


func lav_with(t: int) -> bool:
	return lav != null and lav.alive and lav.together and t == (lav_team() if split else 0)


func lav_fire_mode() -> int:
	if lav == null or not lav.alive:
		return HOLD
	var fight_on: bool = main.any_area_alerted() or fire_mode() != HOLD
	if lav.together and (not split or lav_team() == active):
		return fire_mode()
	return AT_WILL if fight_on else HOLD


## Where the turret watches when it has nothing to shoot.
func lav_watch_dir() -> Vector3:
	return _stack_threat if lav and lav.together else main.camera_forward()


func stacked_count(t: int) -> int:
	var n := 0
	for s in team_members(t):
		if s.stacked and s.is_settled():
			n += 1
	return n


## Z: LAV with us / LAV holds here.
func toggle_lav() -> void:
	if lav == null:
		main.notify("NO VEHICLE ON THIS OPERATION")
		return
	if not lav.alive:
		main.notify("THE LAV IS DOWN")
		return
	lav.together = not lav.together
	var t := lav_team() if split else 0
	if lav.together:
		if teams[t]["in_cover"]:
			teams[t]["in_cover"] = false
			teams[t]["shifted"] = false
		teams[t]["order_target"] = null
		teams[t]["anchor"] = Vector3(lav.global_position.x, 0, lav.global_position.z)
		_stack_face = -1
		main.notify("LAV WITH US  -  STACK UP BEHIND THE VEHICLE")
		main.sgt_callout("SGT: ON THE LAV, STACK UP")
	else:
		lav.goal = Vector3(lav.global_position.x, 0, lav.global_position.z)
		teams[t]["anchor"] = centroid(t)
		teams[t]["anchor"].y = 0
		main.notify("LAV HOLDING  -  OVERWATCH  (Z TO CALL IT BACK)")


## How fast the unit's point may go: it waits for the men (or, with the LAV,
## for the vehicle).
func _lag_factor(t: int) -> float:
	if lav_with(t):
		var d: float = Vector2(teams[t]["anchor"].x - lav.global_position.x, teams[t]["anchor"].z - lav.global_position.z).length()
		return clampf(1.0 - (d - 3.0) / 4.0, 0.2, 1.0)
	var lag: float = teams[t]["anchor"].distance_to(centroid(t))
	return clampf(1.0 - (lag - 3.0) / 4.0, 0.3, 1.0)


## Where the threat is for the stack: the nearest live enemy of any area
## that's been alerted; else the way the unit is moving; else unchanged.
func _stack_threat_dir(t: int) -> Vector3:
	var best := INF
	var dir := Vector3.ZERO
	var from: Vector3 = lav.global_position
	for a in main.areas:
		if not a["alerted"]:
			continue
		for m in a["members"]:
			if not m.alive:
				continue
			var d := from.distance_to(m.global_position)
			if d < best and d < 110.0:
				best = d
				dir = m.global_position - from
	dir.y = 0
	if dir.length() > 0.1:
		return dir.normalized()
	var v: Vector3 = move_vel if t == active else Vector3.ZERO
	if v.length() > 0.8:
		return v.normalized()
	return _stack_threat


## Stack slots on one side of the hull, in the LAV's frame:
## [[spot, lean-out spot], ...]. Rear / front: two files behind the hull,
## leaning out past its sides. Sides: two deep along the hull, leaning out
## past the nearer end.
func _stack_slots(face: int, n: int) -> Array:
	var W: float = LavScript.HALF_W
	var L: float = LavScript.HALF_L
	var out: Array = []
	for i in n:
		if face <= 1:
			var sz := -1.0 if face == 0 else 1.0
			var file := -1.0 if i % 2 == 0 else 1.0
			var row := float(i / 2)
			var spot := Vector3(file * 0.6, 0, sz * (L + 0.75 + row * STACK_ROW))
			var peek := Vector3(file * (W + 0.8), 0, sz * (L + 0.3 + row * STACK_ROW * 0.6))
			out.append([spot, peek])
		else:
			var sx := 1.0 if face == 2 else -1.0
			var col := float(i / 2)
			var z := -1.8 + col * 1.6
			var spot := Vector3(sx * (W + 0.7 + float(i % 2) * 0.8), 0, z)
			var peek := Vector3(sx * (W + 0.4), 0, (L + 0.7) * (1.0 if z > 0.0 else -1.0))
			out.append([spot, peek])
	return out


## Keep the stack behind the LAV: pick the sheltered side (sticky, so it
## doesn't flip-flop), give each man a slot, and slow the LAV if anyone is
## falling behind.
func _lav_stack(t: int) -> void:
	var members := team_members(t)
	lav.goal = Vector3(teams[t]["anchor"].x, 0, teams[t]["anchor"].z)
	_stack_threat = _stack_threat_dir(t)
	teams[t]["threat_dir"] = _stack_threat
	if members.is_empty():
		return
	var xf: Transform3D = lav.global_transform
	var lt: Vector3 = xf.basis.inverse() * _stack_threat
	lt.y = 0
	lt = lt.normalized()
	var rolling: bool = lav.speed > 0.3
	var normals := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	var best := 0
	var best_s := -INF
	var cur_s := -INF
	for i in 4:
		var sc: float = (normals[i] as Vector3).dot(-lt)
		if i == 0:
			sc += 0.3                      # behind it is home
		elif i == 1:
			sc -= 5.0 if rolling else 0.4  # never in front of a moving vehicle
		if i == _stack_face:
			cur_s = sc
		if sc > best_s:
			best_s = sc
			best = i
	if _stack_face < 0 or best_s > cur_s + 0.35 or (rolling and _stack_face == 1):
		_stack_face = best
		_stack_slot = {}
	var ids: Array = members.map(func(m): return m.get_instance_id())
	if ids != _stack_ids:
		_stack_ids = ids
		_stack_slot = {}
	var slots := _stack_slots(_stack_face, members.size())
	if _stack_slot.is_empty():
		# Nearest man to each slot, front slots first.
		var free: Array = members.duplicate()
		for i in slots.size():
			var wp: Vector3 = xf * (slots[i][0] as Vector3)
			var pick: Node3D = null
			var pd := INF
			for m in free:
				var d: float = m.global_position.distance_to(wp)
				if d < pd:
					pd = d
					pick = m
			free.erase(pick)
			_stack_slot[pick] = i
	var worst := 0.0
	for m in members:
		var sl: Array = slots[_stack_slot.get(m, 0)]
		var spot: Vector3 = CoverUtil.push_out(main.cover_defs, xf * (sl[0] as Vector3), 0.5)
		var peek: Vector3 = CoverUtil.push_out(main.cover_defs, xf * (sl[1] as Vector3), 0.5)
		spot.y = 0
		peek.y = 0
		m.stack_on(_around_hull(m.global_position, spot, xf), [peek])
		if not m._peeking:
			worst = maxf(worst, Vector2(m.global_position.x - spot.x, m.global_position.z - spot.z).length())
	lav.speed_cap = clampf(1.0 - (worst - 2.0) / 4.0, 0.15, 1.0)


## A man on the wrong side of the LAV walks round its nearest corner instead
## of into it.
func _around_hull(from: Vector3, to: Vector3, xf: Transform3D) -> Vector3:
	var inv := xf.affine_inverse()
	var a3: Vector3 = inv * from
	var b3: Vector3 = inv * to
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var W: float = LavScript.HALF_W
	var L: float = LavScript.HALF_L
	var r := Rect2(-W - 0.45, -L - 0.45, (W + 0.45) * 2.0, (L + 0.45) * 2.0)
	if not _seg_hits(a, b, r):
		return to
	var best := to
	var best_d := INF
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var c := Vector2(cx * (W + 1.0), cz * (L + 1.0))
			if _seg_hits(a, c, r):
				continue
			var d := a.distance_to(c) + c.distance_to(b)
			if d < best_d:
				best_d = d
				best = xf * Vector3(c.x, 0, c.y)
	best.y = 0
	return best


static func _seg_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	for k in range(1, 10):
		if r.has_point(a.lerp(b, float(k) / 10.0)):
			return true
	return false
