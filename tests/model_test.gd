extends SceneTree
## The blocky soldier (scripts/soldier_model.gd), every role and side:
##  - standing: feet on the ground, nothing below it; hands on the rifle
##  - the legs never move (no walk animation), whatever he does
##  - crouched: the upper body hunches forward (head lower and further
##    ahead), hands still on the rifle
##  - aiming: the rifle comes up and the muzzle points at the target,
##    standing and crouched, and goes back down afterwards
##  - hand signals move the left hand and give it back to the rifle
##  - prone: lying on the ground (nothing sunk, nothing floating), head low,
##    muzzle ahead; back up, the model is back in place
##  - dead, face down and face up: on the ground, the rifle beside him
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
		print("FAIL ", what)


## Where his hand is: the end of the forearm block (upper space).
func _hand(m: Node3D, s: String) -> Vector3:
	var fa: Node3D = m._arms[s]["fore"]
	return fa.transform * Vector3(0, -SoldierModel.FOREARM, 0)


func _hands_on(m: Node3D, label: String) -> void:
	_check(_hand(m, "R").distance_to(m._grip) < 0.03, "%s: right hand off the rifle (%.3f)" % [label, _hand(m, "R").distance_to(m._grip)])
	_check(_hand(m, "L").distance_to(m._guard) < 0.03, "%s: left hand off the rifle (%.3f)" % [label, _hand(m, "L").distance_to(m._guard)])


func _legs(m: Node3D) -> Array:
	var out: Array = []
	for c in m.get_children():
		if c is MeshInstance3D:
			out.append(c.global_transform)
	return out


func _settle(m: Node3D, frames := 120) -> void:
	for i in frames:
		m.animate(Vector3.ZERO, 1.0 / 60.0)


func _muzzle_dir(m: Node3D) -> Vector3:
	return -(m._rifle.global_basis.z).normalized()


func _run() -> void:
	for side in ["friendly", "enemy"]:
		for role in ["rifleman", "grenadier", "anti_armor"]:
			var label := "%s %s" % [side, role]
			var m: Node3D = SoldierModel.new()
			root.add_child(m)
			m.build(role, side, 1)
			_settle(m, 2)
			var legs0 := _legs(m)
			_check(legs0.size() == 2, "%s: two leg blocks (%d)" % [label, legs0.size()])
			var low: float = m.lowest_point()
			_check(absf(low) < 0.01, "%s: standing on the ground (lowest %.3f)" % [label, low])
			_hands_on(m, label + " standing")
			_check(m.muzzle != null, label + ": has a muzzle")
			if role != "rifleman":
				_check(m.launch_tip != null, label + ": has a launcher tip")
			var head0: Vector3 = m.head.global_position
			# Crouch: hunch forward.
			m.set_crouch(true)
			_settle(m)
			var head1: Vector3 = m.head.global_position
			_check(head1.y < head0.y - 0.1 and head1.z < head0.z - 0.25, "%s: crouched, he hunches forward (head %.2f lower, %.2f ahead)" % [label, head0.y - head1.y, head0.z - head1.z])
			_hands_on(m, label + " crouched")
			# Aim at points around him, standing and crouched.
			for crouch in [true, false]:
				m.set_crouch(crouch)
				for t in [Vector3(0, 1.4, -15), Vector3(-5, 1.0, -12), Vector3(4, 3.0, -14), Vector3(2, 0.2, -10)]:
					for i in 90:
						m.set_aim_point(t)
						m.animate(Vector3.ZERO, 1.0 / 60.0)
					var tag := "%s aiming at %s%s" % [label, t, " crouched" if crouch else ""]
					_check(m.is_shouldered(), tag + ": rifle never came up")
					var want: Vector3 = (t - m.muzzle.global_position).normalized()
					_check(_muzzle_dir(m).angle_to(want) < 0.15, "%s: muzzle off target by %.2f rad" % [tag, _muzzle_dir(m).angle_to(want)])
					_hands_on(m, tag)
			m.set_aim_point(Vector3.INF)
			_settle(m)
			_check(m._aim_amt == 0.0, label + ": rifle never lowered")
			# A hand signal: the left hand leaves the rifle, then comes back.
			m.gesture("halt")
			await create_timer(0.3).timeout
			_check(_hand(m, "L").distance_to(m._guard) > 0.2, label + ": halt signal didn't raise the left hand")
			await create_timer(1.6).timeout
			_settle(m, 2)
			_hands_on(m, label + " after a signal")
			var moved := 0.0
			var legs1 := _legs(m)
			for i in legs1.size():
				moved = maxf(moved, legs1[i].origin.distance_to(legs0[i].origin))
			_check(moved < 0.001, "%s: the legs never moved (%.3f)" % [label, moved])
			m.set_crouch(false)
			_settle(m)
			# Prone, aiming ahead.
			m.set_prone(true)
			for i in 150:
				m.set_aim_point(Vector3(0, 0.3, -12))     # (world: he stands at the origin facing -Z)
				m.animate(Vector3.ZERO, 1.0 / 60.0)
			_check(m.prone_amount() == 1.0, label + ": never got all the way down")
			var pl: float = m.lowest_point()
			_check(pl > -0.03 and pl < 0.06, "%s: prone body not on the ground (lowest %.3f)" % [label, pl])
			_check(m.head.global_position.y < 0.5, "%s: head too high for prone (%.2f)" % [label, m.head.global_position.y])
			var fwd := _muzzle_dir(m)
			_check(fwd.dot(Vector3.FORWARD) > 0.9, "%s: prone, the rifle points ahead (%.2f)" % [label, fwd.dot(Vector3.FORWARD)])
			_check(m.muzzle.global_position.y > -0.02, "%s: prone rifle in the ground (%.2f)" % [label, m.muzzle.global_position.y])
			_hands_on(m, label + " prone")
			m.set_prone(false)
			m.set_aim_point(Vector3.INF)
			_settle(m, 200)
			_check(m.transform.is_equal_approx(Transform3D.IDENTITY), label + ": model not back in place after getting up")
			m.queue_free()
			# Dead, both ways.
			for face_up in [false, true]:
				var d: Node3D = SoldierModel.new()
				root.add_child(d)
				d.build(role, side, 2)
				_settle(d, 2)
				d.lay_down(face_up)
				var dl: float = d.lowest_point()
				var tag := "%s dead face %s" % [label, "up" if face_up else "down"]
				_check(absf(dl) < 0.02, "%s: body not on the ground (lowest %.3f)" % [tag, dl])
				_check(d.head.global_position.y < 0.5, "%s: body not lying down (head at %.2f)" % [tag, d.head.global_position.y])
				var ry: float = d._rifle.global_position.y
				_check(ry > 0.0 and ry < 0.1, "%s: rifle not on the ground (%.3f)" % [tag, ry])
				d.queue_free()
	print("model_test: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)
