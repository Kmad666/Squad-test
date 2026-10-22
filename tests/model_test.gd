extends SceneTree
## Geometry checks on the universal soldier model in every pose and gait:
##  - torso stays attached to the hips (no gap at the waist)
##  - feet never sink below the ground, legs never over-stretch
##  - feet never cross / collide while strafing
##  - hands actually reach the rifle (IK targets reachable)
##  - dead bodies rest on the ground: nothing sinks, nothing floats,
##    rifle lies on the ground
## Prints FAIL lines and exits 1 on any failure.

const SoldierModel = preload("res://scripts/soldier_model.gd")

var fails := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		if fails <= 4000:
			print("FAIL ", what)


func _hand(m: Node3D, s: String) -> Vector3:
	var fa: Node3D = m._arms[s]["fore"]
	return fa.transform * Vector3(0, -SoldierModel.FOREARM, 0)     # upper space


func _pose_checks(m: Node3D, label: String, hands := true) -> void:
	var waist: Vector3 = m.upper.global_transform * Vector3(0, SoldierModel.WAIST_Y, 0)
	var hips: Vector3 = m._hips.global_position
	_check(waist.distance_to(hips) < 0.13, "%s: torso detached from hips (%.3f m)" % [label, waist.distance_to(hips)])
	var ankles := {}
	for s in ["L", "R"]:
		var foot: Node3D = m._legs[s]["foot"]
		var thigh: Node3D = m._legs[s]["thigh"]
		var shin: Node3D = m._legs[s]["shin"]
		ankles[s] = foot.global_position
		# sole: the lowest corner of the foot box must not dip below ground
		var low := INF
		for mi in foot.get_children():
			if mi is MeshInstance3D:
				var bb: AABB = mi.get_aabb()
				for c in 8:
					low = minf(low, (mi.global_transform * bb.get_endpoint(c)).y)
		_check(low > -0.035, "%s: %s foot below ground (%.3f)" % [label, s, low])
		var knee_gap: float = (thigh.global_transform * Vector3(0, -SoldierModel.THIGH, 0)).distance_to(shin.global_position)
		_check(knee_gap < 0.02, "%s: %s knee disjointed (%.3f)" % [label, s, knee_gap])
		var ankle_gap: float = (shin.global_transform * Vector3(0, -SoldierModel.SHIN, 0)).distance_to(foot.global_position)
		_check(ankle_gap < 0.03, "%s: %s leg over-stretched, foot off the shin (%.3f)" % [label, s, ankle_gap])
	var apart: float = Vector2(ankles["L"].x - ankles["R"].x, ankles["L"].z - ankles["R"].z).length()
	_check(apart > 0.13, "%s: feet colliding (%.3f m apart)" % [label, apart])
	if hands:
		_check(_hand(m, "R").distance_to(m._grip) < 0.02, "%s: right hand off the grip (%.3f)" % [label, _hand(m, "R").distance_to(m._grip)])
		_check(_hand(m, "L").distance_to(m._guard) < 0.02, "%s: left hand off the handguard (%.3f)" % [label, _hand(m, "L").distance_to(m._guard)])


func _run() -> void:
	var gaits := [
		["idle", Vector3.ZERO, false],
		["crouch", Vector3.ZERO, true],
		["walk", Vector3(0, 0, -1.6), false],
		["jog", Vector3(0, 0, -4.4), false],
		["run", Vector3(0, 0, -7.0), false],
		["crouchwalk", Vector3(0, 0, -2.5), true],
		["strafe_r", Vector3(3.5, 0, 0), false],
		["strafe_l", Vector3(-4.5, 0, 0), false],
		["diag_back", Vector3(2.5, 0, 2.5), false],
		["backpedal", Vector3(0, 0, 3.0), false],
		["crouch_strafe", Vector3(-2.2, 0, 0), true],
	]
	for role in ["rifleman", "grenadier", "anti_armor"]:
		for side in ["friendly", "enemy"]:
			for g in gaits:
				var m: Node3D = SoldierModel.new()
				root.add_child(m)
				m.build(role, side, 1)
				m.set_crouch(g[2])
				for i in 90:
					m.animate_local(g[1], 1.0 / 60.0)
				for k in 12:
					m._phase = k / 12.0
					m._apply_pose()
					m._solve_arms()
					_pose_checks(m, "%s/%s/%s@%d" % [role, side, g[0], k])
				m.free()
	# Stopping, crouch toggling and a gesture mid-run: hand returns to the rifle.
	var m2: Node3D = SoldierModel.new()
	root.add_child(m2)
	m2.build("rifleman", "friendly", 0)
	m2.gesture("move")
	for i in 30:
		m2.animate_local(Vector3(0, 0, -5), 1.0 / 60.0)
	m2.set_crouch(true)
	for i in 30:
		m2.animate_local(Vector3(0, 0, -2), 1.0 / 60.0)
	m2.set_crouch(false)
	for i in 120:
		m2.animate_local(Vector3.ZERO, 1.0 / 60.0)
		await process_frame
	_pose_checks(m2, "after gesture + crouch toggle + stop")
	_check(m2._gait_w == 0.0, "gait never settled after stopping")
	m2.free()

	# Corpses.
	for role in ["rifleman", "grenadier", "anti_armor"]:
		for face_up in [false, true]:
			if face_up and role == "anti_armor":
				continue        # only enemies fall face up, and they carry no rocket tube
			for crouched in [false, true]:
				for moving in [false, true]:
					var d: Node3D = SoldierModel.new()
					root.add_child(d)
					d.build(role, "enemy" if face_up else "friendly", 2)
					d.set_crouch(crouched)
					for i in 40:
						d.animate_local(Vector3(0, 0, -5) if moving else Vector3.ZERO, 1.0 / 60.0)
					d.rotation.y = 0.7
					d.position = Vector3(3, 0, -2)
					d.lay_down(face_up)
					var label := "dead %s face_up=%s crouched=%s moving=%s" % [role, face_up, crouched, moving]
					var low := INF
					for mi in d._meshes:
						if mi.get_parent() == d._rifle:
							continue
						var bb: AABB = mi.get_aabb()
						for c in 8:
							low = minf(low, (mi.global_transform * bb.get_endpoint(c)).y)
					_check(absf(low) < 0.02, "%s: body not on the ground (lowest %.3f)" % [label, low])
					var hips_y: float = d._hips.global_position.y
					_check(hips_y < 0.35, "%s: body floating (hips at %.2f)" % [label, hips_y])
					var ry: float = d._rifle.global_position.y
					_check(ry > 0.0 and ry < 0.08, "%s: rifle not on the ground (%.3f)" % [label, ry])
					d.free()
	print("model checks: %d, failures: %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
