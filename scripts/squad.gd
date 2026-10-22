extends Node3D
## The squad as one unit: WASD moves an anchor point, soldiers hold a loose
## cluster around it, and the cover order sends each soldier to its own nearby
## cover spot on the far side of a box from the threat.
## Teams waiting in the field join the squad when it walks up to them.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SoldierScript = preload("res://scripts/soldier.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")

const MOVE_SPEED := 5.0
const CLUSTER_RADIUS := 2.8      # loose cluster spread around the anchor
const COVER_SEARCH := 14.0       # how far from the squad a cover spot may be
const COHESION_WEIGHT := 0.7     # how much cover choice favours staying grouped
const MIN_COVER_GAP := 0.95      # two soldiers never share a spot
const JOIN_DISTANCE := 7.0       # how close the squad must get to pick up a team

## Starting squad: five riflemen and a grenadier.
const START_ROLES := ["rifleman", "rifleman", "rifleman", "grenadier", "rifleman", "rifleman"]

var main: Node3D
var soldiers: Array = []
var anchor := Vector3.ZERO
var slot_offsets: Array = []
var in_cover := false
var auto_fire := false            # F: permanent fire at will
var forced_mode := -1              # tests can force a fire mode
var forced_specials := false       # tests can force the specials order
var pending_teams: Array = []      # [{members, center, label, name}]
var kia := 0
var order_target: Variant = null   # E: point the squad is moving to
var _ping: MeshInstance3D
var _ping_t := 0.0

enum { HOLD, AT_WILL, FOCUS }
var threat_dir := Vector3.FORWARD



func setup(m: Node3D, start: Vector3) -> void:
	main = m
	anchor = start
	_make_offsets(START_ROLES.size())
	for i in START_ROLES.size():
		var s := _new_soldier(START_ROLES[i], i)
		s.global_position = anchor + slot_offsets[i]
		s.move_target = s.global_position
		soldiers.append(s)


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
		if anchor.distance_to(team["center"]) > JOIN_DISTANCE:
			continue
		for s in team["members"]:
			s.recruited = true
			s.index = soldiers.size()
			soldiers.append(s)
		team["label"].queue_free()
		pending_teams.erase(team)
		_make_offsets(soldiers.size())
		if in_cover:
			take_cover()
		main.notify("%s JOINED THE SQUAD  (+%d)" % [team["name"], team["members"].size()])


## Loose cluster: sunflower spiral with a little per-soldier jitter so it
## doesn't look like a parade-ground pattern.
func _make_offsets(count: int) -> void:
	slot_offsets.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var radius := CLUSTER_RADIUS * sqrt(maxf(1.0, float(count) / 6.0))  # bigger squad, wider cluster
	for i in count:
		var r: float = radius * sqrt((float(i) + 0.6) / float(count))
		var a: float = float(i) * 2.39996 + 0.4
		var jitter := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		slot_offsets.append(Vector3(cos(a) * r, 0, sin(a) * r) + jitter)


## Primary weapons: left mouse held = focus fire on the reticle, otherwise
## fire at will if auto fire (F) is on, else hold fire.
func fire_mode() -> int:
	if forced_mode >= 0:
		return forced_mode
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return FOCUS
	return AT_WILL if auto_fire else HOLD


## Right mouse held = specialists use grenade launchers / rockets on the reticle.
func specials_active() -> bool:
	if forced_specials:
		return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func fire_mode_text() -> String:
	var t := "HOLD FIRE"
	match fire_mode():
		FOCUS:
			t = "FOCUS FIRE"
		AT_WILL:
			t = "FIRE AT WILL"
	if specials_active():
		t += " + SPECIALS"
	return t


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
	var sp: Array = []
	if gl[1] > 0:
		sp.append("GL %d/%d READY" % gl)
	if rk[1] > 0:
		sp.append("ROCKETS %d/%d READY" % rk)
	if sp.is_empty():
		sp.append("NONE")
	return t + "\nSPECIAL " + "   ".join(sp)


func get_focus() -> Vector3:
	return anchor


func centroid() -> Vector3:
	var c := Vector3.ZERO
	for s in soldiers:
		c += s.global_position
	return c / float(maxi(1, soldiers.size()))


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


## Send the squad to a point. They break cover and move as a group;
## WASD cancels the order.
func move_to(p: Vector3) -> void:
	var lim: float = main.NAV_HALF - 2.0
	order_target = Vector3(clampf(p.x, -lim, lim), 0, clampf(p.z, -lim, lim))
	if in_cover:
		leave_cover()
	_show_ping(order_target)


## Brief fading ring where the move order lands.
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


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() > 0.05:
		order_target = null
		if in_cover:
			leave_cover()
		var dir: Vector3 = main.cam_rig.get_yaw_basis() * Vector3(input.x, 0, input.y)
		dir.y = 0
		# Slow the anchor down if the squad is lagging so the group stays tight.
		var lag := anchor.distance_to(centroid())
		var speed := MOVE_SPEED * clampf(1.0 - (lag - 3.0) / 4.0, 0.3, 1.0)
		anchor += dir.normalized() * minf(input.length(), 1.0) * speed * delta
		var lim: float = main.NAV_HALF - 2.0
		anchor.x = clampf(anchor.x, -lim, lim)
		anchor.z = clampf(anchor.z, -lim, lim)
		# The anchor is a ghost point with no collision: it passes straight
		# through crates, and each soldier finds his own way around.

	elif order_target != null:
		var to: Vector3 = order_target - anchor
		to.y = 0
		if to.length() < 0.4:
			order_target = null
		else:
			var lag := anchor.distance_to(centroid())
			var speed := MOVE_SPEED * clampf(1.0 - (lag - 3.0) / 4.0, 0.3, 1.0)
			anchor += to.normalized() * minf(speed * delta, to.length())

	if _ping and _ping.visible:
		_ping_t -= delta
		(_ping.material_override as StandardMaterial3D).albedo_color.a = clampf(_ping_t / 1.5, 0.0, 1.0) * 0.8
		if _ping_t <= 0.0:
			_ping.visible = false

	if not in_cover:
		for i in soldiers.size():
			var p: Vector3 = anchor + slot_offsets[i]
			soldiers[i].move_target = CoverUtil.push_out(main.cover_defs, p, 0.6)

	_check_joins()


## Every soldier scrambles to the closest free cover spot that shields it from
## the threat, with a pull toward the squad so nobody runs off alone.
func take_cover() -> void:
	in_cover = true
	threat_dir = main.camera_forward()   # hide from whatever the camera faces

	var candidates: Array = []
	for cp in main.cover_points:
		if cp["pos"].distance_to(anchor) > COVER_SEARCH:
			continue
		if cp["normal"].dot(threat_dir) > -0.3:
			continue  # box isn't between this spot and the threat
		candidates.append(cp)

	var pairs: Array = []
	for s in soldiers:
		for ci in candidates.size():
			var cpos: Vector3 = candidates[ci]["pos"]
			var score: float = s.global_position.distance_to(cpos) + COHESION_WEIGHT * cpos.distance_to(anchor)
			pairs.append([score, s.index, ci])
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var assigned := {}
	var claimed: Array = []
	for p in pairs:
		if assigned.has(p[1]):
			continue
		var cpos: Vector3 = candidates[p[2]]["pos"]
		var free := true
		for c in claimed:
			if c.distance_to(cpos) < MIN_COVER_GAP:
				free = false
				break
		if not free:
			continue
		assigned[p[1]] = candidates[p[2]]
		claimed.append(cpos)
		if assigned.size() == soldiers.size():
			break

	for s in soldiers:
		if assigned.has(s.index):
			s.go_to_cover(assigned[s.index]["pos"], true, assigned[s.index]["peeks"])
		else:
			s.go_to_cover(s.global_position, false)  # no spot: get low where you are


func on_soldier_killed(s: Node3D) -> void:
	soldiers.erase(s)
	kia += 1
	for i in soldiers.size():
		soldiers[i].index = i
	_make_offsets(maxi(1, soldiers.size()))
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


func leave_cover() -> void:
	in_cover = false
	for s in soldiers:
		s.leave_cover()


func status_text() -> String:
	if not in_cover:
		return "MOVING (loose cluster)"
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
	return txt + ")"
