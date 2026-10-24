extends SceneTree
## Geometry checks on the universal soldier model in every pose and gait:
##  - torso stays attached to the hips (no gap at the waist)
##  - feet never sink below the ground, legs never over-stretch
##  - feet never cross / collide while strafing
##  - hands actually reach the rifle (IK targets reachable)
##  - dead bodies rest on the ground: nothing sinks, nothing floats,
##    rifle lies on the ground
##  - prone and crawling (HD and RETRO): lying on the ground, nothing sunk
##    into it, hands on the rifle, rifle pointed where he aims; the drop to
##    prone and getting back up never put a foot through the ground
## Prints FAIL lines and exits 1 on any failure.

const SoldierModel = preload("res://scripts/soldier_model.gd")

var fails := 0
var checks := 0
var worst := {"grip": 0.0, "guard": 0.0, "ankle": INF}


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


## The detailed soldier (soldier_skin.gd) worn over the rig: his hands on
## the rifle (grip and handguard), his ankles above the ground.
func _skin_checks(m: Node3D, label: String, hands := true) -> void:
	var skin = m._skin
	if skin == null or not skin.is_visible_in_tree():
		return
	var sk: Skeleton3D = skin.skeleton
	var gt := sk.global_transform
	if hands:
		for s in ["R", "L"]:
			var hand_i: int = skin.bone(s + ("_Hand_081" if s == "R" else "_Hand_055"))
			var fore_i: int = skin.bone(s + ("_Forearm_077" if s == "R" else "_Forearm_051"))
			var wrist: Vector3 = gt * sk.get_bone_global_pose(hand_i).origin
			var elbow: Vector3 = gt * sk.get_bone_global_pose(fore_i).origin
			var palm: Vector3 = wrist + (wrist - elbow).normalized() * skin.PALM
			var want: Vector3 = m._rifle.global_position if s == "R" else m.upper.global_transform * (m._guard + skin._rifle_shift)
			var d := palm.distance_to(want)
			var key := "grip" if s == "R" else "guard"
			worst[key] = maxf(worst[key], d)
			_check(d < 0.07, "%s: detailed soldier's %s hand off the rifle (%.3f)" % [label, s, d])
	for s in ["L", "R"]:
		var foot_i: int = skin.bone(s + ("_Foot_05" if s == "L" else "_Foot_022"))
		var ay: float = (gt * sk.get_bone_global_pose(foot_i).origin).y
		worst["ankle"] = minf(worst["ankle"], ay)
		_check(ay > 0.04, "%s: detailed soldier's %s ankle in the ground (%.3f)" % [label, s, ay])


func _pose_checks(m: Node3D, label: String, hands := true) -> void:
	_skin_checks(m, label, hands)
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
		["wounded_walk", Vector3(0, 0, -1.6), false],
		["wounded_run", Vector3(0, 0, -4.8), false],
		["wounded_strafe", Vector3(3.0, 0, 0), false],
	]
	for role in ["rifleman", "grenadier", "anti_armor"]:
		for side in ["friendly", "enemy"]:
			for g in gaits:
				var m: Node3D = SoldierModel.new()
				root.add_child(m)
				m.build(role, side, 1)
				m.set_crouch(g[2])
				m.wounded = String(g[0]).begins_with("wounded")   # mocap limp
				for i in 90:
					m.animate_local(g[1], 1.0 / 60.0)
				for k in 12:
					m._phase = k / 12.0
					m._apply_pose()
					m._solve_arms()
					_pose_checks(m, "%s/%s/%s@%d" % [role, side, g[0], k])
				m.free()
	# Aiming: shouldered at targets around him, standing / crouched / moving,
	# with and without recoil. Both hands must stay on the rifle and the
	# muzzle must point at the target (within the allowed swing).
	var targets := [
		["ahead", Vector3(0, 1.3, -20)], ["left", Vector3(-9, 1.3, -15)],
		["right", Vector3(5, 1.3, -20)], ["up", Vector3(0, 8, -15)],
		["down", Vector3(0, 0.2, -6)], ["far_right", Vector3(20, 1.3, -3)],
	]
	for role in ["rifleman", "grenadier", "anti_armor"]:
		for crouch in [false, true]:
			for vel in [Vector3.ZERO, Vector3(0, 0, -2.0), Vector3(3, 0, 0)]:
				for tg in targets:
					var m: Node3D = SoldierModel.new()
					root.add_child(m)
					m.build(role, "friendly", 0)
					m.set_crouch(crouch)
					for i in 60:
						m.set_aim_point(m.global_transform * tg[1])
						m.animate_local(vel, 1.0 / 60.0)
					var label := "aim %s/%s crouch=%s vel=%s" % [role, tg[0], crouch, vel]
					_check(m.is_shouldered(), label + ": rifle never came up")
					for k in 4:
						m._phase = k / 4.0
						m._recoil = 0.0 if k % 2 == 0 else 1.0
						m._apply_pose()
						m._solve_arms()
						_pose_checks(m, "%s@%d" % [label, k])
					# muzzle on target (only where the target is inside the swing)
					if tg[0] in ["ahead", "left", "right"]:
						m._recoil = 0.0
						m._apply_pose()
						var mz: Vector3 = m.muzzle.global_position
						var fwd: Vector3 = -m.muzzle.global_basis.z
						var want: Vector3 = ((m.global_transform * tg[1]) - mz).normalized()
						_check(fwd.angle_to(want) < 0.12, "%s: muzzle off target by %.2f rad" % [label, fwd.angle_to(want)])
					m.free()
	# Lowering again returns to low ready.
	var m3: Node3D = SoldierModel.new()
	root.add_child(m3)
	m3.build("rifleman", "enemy", 0)
	for i in 40:
		m3.set_aim_point(Vector3(0, 1.3, -20))
		m3.animate_local(Vector3.ZERO, 1.0 / 60.0)
	for i in 60:
		m3.set_aim_point(Vector3.INF)
		m3.animate_local(Vector3.ZERO, 1.0 / 60.0)
	_check(m3._aim_amt == 0.0, "rifle never lowered")
	_pose_checks(m3, "lowered after aiming")
	m3.free()

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

	# Corpses and prone bodies, HD and RETRO.
	for retro in [false, true]:
		SoldierModel.retro = retro
		_corpses(retro)
		_prone(retro)
	SoldierModel.retro = false
	# Triangle budget (weak integrated GPUs, in a browser): per soldier,
	# close-up and far meshes.
	_budget()
	print("detailed soldier: worst grip %.3f, guard %.3f, lowest ankle %.3f" % [worst["grip"], worst["guard"], worst["ankle"]])
	print("model checks: %d, failures: %d" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _corpses(retro: bool) -> void:
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
					var label := "dead %s face_up=%s crouched=%s moving=%s retro=%s" % [role, face_up, crouched, moving, retro]
					var low: float = d.lowest_point()      # real vertices, not box corners
					_check(absf(low) < 0.02, "%s: body not on the ground (lowest %.3f)" % [label, low])
					var hips_y: float = d._hips.global_position.y
					_check(hips_y < 0.35, "%s: body floating (hips at %.2f)" % [label, hips_y])
					var ry: float = d._rifle.global_position.y
					_check(ry > 0.0 and ry < 0.08, "%s: rifle not on the ground (%.3f)" % [label, ry])
					d.free()


## Lowest drawn vertex of the parts accepted by `keep` (world height).
func _low(m: Node3D, keep: Callable) -> float:
	var low := INF
	for mi in m.shown_meshes():
		if not keep.call(mi):
			continue
		var xf: Transform3D = mi.global_transform
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			low = minf(low, (xf * v).y)
	return low


func _prone(retro: bool) -> void:
	var aims := [["rest", Vector3.INF], ["ahead", Vector3(0, 0.4, -20)], ["left", Vector3(-6, 0.4, -20)], ["right", Vector3(6, 0.6, -20)]]
	for role in ["rifleman", "grenadier", "anti_armor"]:
		for side in ["friendly", "enemy"]:
			for vel in [Vector3.ZERO, Vector3(0, 0, -1.0)]:
				for aim in aims:
					var body := Node3D.new()          # stands in for the soldier node
					root.add_child(body)
					body.position = Vector3(2, 0, -1)
					body.rotation.y = 0.6
					var m: Node3D = SoldierModel.new()
					body.add_child(m)
					m.build(role, side, 3)
					m.animate_local(Vector3.ZERO, 1.0 / 60.0)
					m.set_prone(true)
					var label := "prone %s/%s vel=%.1f aim=%s retro=%s" % [role, side, -vel.z, aim[0], retro]
					var worst_drop := INF
					for i in 90:
						if aim[1] != Vector3.INF:
							m.set_aim_point(body.global_transform * aim[1])
						else:
							m.set_aim_point(Vector3.INF)
						m.animate_local(vel, 1.0 / 60.0)
						if i < 40:            # on the way down
							worst_drop = minf(worst_drop, _low(m, func(mi): return mi.get_parent() == m._legs["L"]["foot"] or mi.get_parent() == m._legs["R"]["foot"]))
					_check(worst_drop > -0.04, "%s: foot through the ground going down (%.3f)" % [label, worst_drop])
					_check(m.prone_amount() == 1.0, label + ": never got all the way down")
					for k in 8:
						m._phase = k / 8.0
						m._recoil = 0.0 if k % 2 == 0 else 1.0
						m._apply_pose()
						m._solve_arms()
						var tag := "%s@%d" % [label, k]
						_pose_checks(m, tag)
						var body_low := _low(m, func(mi): return mi.get_parent() != m._rifle)
						_check(body_low > -0.03, "%s: body sunk into the ground (%.3f)" % [tag, body_low])
						var torso_low := _low(m, func(mi): return mi.get_parent() == m.upper or mi.get_parent() == m._hips)
						_check(torso_low < 0.09, "%s: torso floating (%.3f)" % [tag, torso_low])
						var rifle_low := _low(m, func(mi): return mi.get_parent() == m._rifle)
						_check(rifle_low > -0.06, "%s: rifle buried (%.3f)" % [tag, rifle_low])
						_check(m.head.global_position.y < 0.45, "%s: head too high for prone (%.2f)" % [tag, m.head.global_position.y])
					# muzzle points where he aims (rest: straight ahead of his facing)
					m._recoil = 0.0
					m._apply_pose()
					m._solve_arms()
					var mz: Vector3 = m.muzzle.global_position
					var fwd: Vector3 = -m.muzzle.global_basis.z
					var want: Vector3 = -body.global_basis.z
					if aim[1] != Vector3.INF:
						want = ((body.global_transform * aim[1]) - mz).normalized()
					_check(fwd.angle_to(want) < 0.12, "%s: muzzle off by %.2f rad" % [label, fwd.angle_to(want)])
					# and back up again
					m.set_prone(false)
					m.set_aim_point(Vector3.INF)
					var worst_up := INF
					for i in 90:
						m.animate_local(Vector3.ZERO, 1.0 / 60.0)
						worst_up = minf(worst_up, _low(m, func(mi): return mi.get_parent() == m._legs["L"]["foot"] or mi.get_parent() == m._legs["R"]["foot"]))
					_check(worst_up > -0.04, "%s: foot through the ground getting up (%.3f)" % [label, worst_up])
					_check(m.transform.is_equal_approx(Transform3D.IDENTITY), label + ": model not back in place after getting up")
					_pose_checks(m, label + " back up")
					body.free()


func _budget() -> void:
	for cfg in [["rifleman", "friendly"], ["grenadier", "friendly"], ["anti_armor", "friendly"], ["rifleman", "enemy"]]:
		var bm: Node3D = SoldierModel.new()
		root.add_child(bm)
		bm.build(cfg[0], cfg[1], 0)
		var tris := [0, 0]
		for mi in bm._meshes:
			if mi.mesh.get_surface_count() > 0:
				tris[0 if mi.visibility_range_begin == 0.0 else 1] += mi.mesh.surface_get_array_index_len(0) / 3
		_check(tris[0] <= 16000, "%s/%s close-up mesh over budget: %d triangles" % [cfg[0], cfg[1], tris[0]])
		_check(tris[1] <= 5000, "%s/%s far mesh over budget: %d triangles" % [cfg[0], cfg[1], tris[1]])
		_check(tris[1] < tris[0] * 0.5, "%s/%s far mesh not much cheaper (%d vs %d)" % [cfg[0], cfg[1], tris[1], tris[0]])
		var rt := 0
		for mi in bm._retro_meshes:
			if mi.mesh.get_surface_count() > 0:
				rt += mi.mesh.surface_get_array_index_len(0) / 3
		print("%s/%s triangles: close-up %d, far %d, retro %d" % [cfg[0], cfg[1], tris[0], tris[1], rt])
		_check(rt <= 1200, "%s/%s retro mesh over budget: %d triangles" % [cfg[0], cfg[1], rt])
		bm.free()
	print("model checks: %d, failures: %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
