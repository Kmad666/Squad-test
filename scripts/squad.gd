extends Node3D
## The squad as one unit: WASD moves an anchor point, soldiers hold a loose
## cluster around it, and the cover order sends each soldier to its own nearby
## cover spot on the far side of a box from the threat.

const CoverUtil = preload("res://scripts/cover_util.gd")
const SoldierScript = preload("res://scripts/soldier.gd")

const MOVE_SPEED := 5.0
const CLUSTER_RADIUS := 2.8      # loose cluster spread around the anchor
const COVER_SEARCH := 14.0       # how far from the squad a cover spot may be
const COHESION_WEIGHT := 0.7     # how much cover choice favours staying grouped
const MIN_COVER_GAP := 0.95      # two soldiers never share a spot

var main: Node3D
var soldiers: Array = []
var anchor := Vector3.ZERO
var slot_offsets: Array = []
var in_cover := false
var hold_fire := false
var threat_dir := Vector3.FORWARD

var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D


func setup(m: Node3D, start: Vector3, count: int) -> void:
	main = m
	anchor = start
	_make_offsets(count)
	for i in count:
		var s: CharacterBody3D = SoldierScript.new()
		s.squad = self
		s.main = main
		s.index = i
		add_child(s)
		s.global_position = anchor + slot_offsets[i]
		s.move_target = s.global_position
		soldiers.append(s)
	_build_marker()


## Loose cluster: sunflower spiral with a little per-soldier jitter so it
## doesn't look like a parade-ground pattern.
func _make_offsets(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in count:
		var r: float = CLUSTER_RADIUS * sqrt((float(i) + 0.6) / float(count))
		var a: float = float(i) * 2.39996 + 0.4
		var jitter := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		slot_offsets.append(Vector3(cos(a) * r, 0, sin(a) * r) + jitter)


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.6
	_marker.mesh = torus
	_marker.scale = Vector3(1, 0.15, 1)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = Color(1.0, 0.85, 0.2)
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)


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
	elif event.is_action_pressed("hold_fire"):
		hold_fire = not hold_fire


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() > 0.05:
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
		anchor = CoverUtil.push_out(main.cover_defs, anchor, 0.7)

	if not in_cover:
		for i in soldiers.size():
			var p: Vector3 = anchor + slot_offsets[i]
			soldiers[i].move_target = CoverUtil.push_out(main.cover_defs, p, 0.6)

	_marker.global_position = anchor + Vector3(0, 0.03, 0)
	_marker_mat.albedo_color = Color(0.3, 0.8, 1.0) if in_cover else Color(1.0, 0.85, 0.2)


## Every soldier scrambles to the closest free cover spot that shields it from
## the threat, with a pull toward the squad so nobody runs off alone.
func take_cover() -> void:
	in_cover = true
	threat_dir = main.threat_direction(anchor)

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
			s.go_to_cover(assigned[s.index]["pos"], true)
		else:
			s.go_to_cover(s.global_position, false)  # no spot: get low where you are


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
