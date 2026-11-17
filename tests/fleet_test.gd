extends SceneTree
## ARMORED FLEET (prototype mode, fleet.tscn):
##  1. the countryside is hilly and every vehicle sits on the ground
##  2. WASD: the fleet drives off together, in its wedge, hulls facing the way
##     they go, everyone on the ground the whole way
##  3. machine guns (LMB) on the box: rounds hit and it loses health
##  4. main guns (RMB): every vehicle fires once, the shells hit the box hard,
##     all five reload, and fire again once loaded
##  5. driving straight at the box: nobody drives into it
##  6. shoot it to nothing: TARGET DESTROYED
## Prints FAIL lines and exits 1 on any failure.

var fm
var f := 0
var fails := 0
var checks := 0
var phase := 0
var t0 := 0
var hp0 := 0.0
var worst_ground := 0.0
var inside := 0


func _initialize() -> void:
	fm = load("res://fleet.tscn").instantiate()
	root.add_child(fm)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _box_aim() -> Vector3:
	return fm._target.position + Vector3(0, 2, 0)


func _physics_process(_d: float) -> bool:
	f += 1
	if f < 5:
		return false
	for v in fm.vehicles:
		worst_ground = maxf(worst_ground, absf(v.global_position.y - fm.height(v.global_position.x, v.global_position.z)))
		var p: Vector3 = v.global_position
		if absf(p.x) < fm.TARGET_SIZE.x / 2.0 and absf(p.z) < fm.TARGET_SIZE.z / 2.0 and not fm.target_dead:
			inside += 1
	match phase:
		0:
			var lo := INF
			var hi := -INF
			for i in 40:
				for j in 40:
					var h: float = fm.height(-380.0 + i * 19.0, -380.0 + j * 19.0)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			_check(hi - lo > 12.0, "hilly countryside (%.1f m from the lowest dip to the highest hill)" % (hi - lo))
			_check(fm.vehicles.size() == 5, "five vehicles in the fleet")
			fm.forced_input = {"move": Vector2(0, -1)}
			t0 = f
			phase = 1
		1:
			if f - t0 == 420:
				var moved: float = 250.0 - fm.anchor.z
				_check(moved > 40.0, "WASD: the fleet drove off (%.0f m)" % moved)
				var off := 0.0
				var facing := 1.0
				for v in fm.vehicles:
					off = maxf(off, v.global_position.distance_to(fm._slot_world(v)))
					facing = minf(facing, (-v._body.global_basis.z).normalized().dot(Vector3(0, 0, -1)))
				_check(off < 10.0, "the vehicles keep their places in the wedge (worst %.1f m off)" % off)
				_check(facing > 0.9, "hulls face the way they're going (worst %.2f)" % facing)
				_check(worst_ground < 0.05, "every vehicle on the ground the whole way (worst %.2f m off)" % worst_ground)
				fm.forced_input = {"mg": true, "aim": _box_aim()}
				hp0 = fm.target_hp
				t0 = f
				phase = 2
		2:
			if f - t0 == 300:
				_check(fm.hits_mg > 20 and fm.target_hp < hp0, "machine guns on the box: %d hits, health %d -> %d" % [fm.hits_mg, hp0, fm.target_hp])
				fm.forced_input = {"main": true, "aim": _box_aim()}
				hp0 = fm.target_hp
				t0 = f
				phase = 3
		3:
			if f - t0 == 60:
				var reloading := 0
				for v in fm.vehicles:
					if v.reload > 0.0:
						reloading += 1
				_check(reloading == 5, "RMB: every main gun fired and is reloading (%d)" % reloading)
				fm.forced_input = {"aim": _box_aim()}
			if f - t0 == 150:
				_check(fm.hits_main >= 4, "main gun shells hit the box (%d of 5)" % fm.hits_main)
				_check(hp0 - fm.target_hp >= 4 * fm.MAIN_DMG * 0.9, "...hard (health %d -> %d)" % [hp0, fm.target_hp])
				fm.forced_input = {"main": true, "aim": _box_aim()}
			if f - t0 == 300:
				var shots := 0
				for v in fm.vehicles:
					shots += v.shots_main
				_check(shots == 10, "reloaded and fired again (%d shots)" % shots)
				fm.forced_input = {"move": Vector2(0, -1), "aim": _box_aim()}
				t0 = f
				phase = 4
		4:
			if f - t0 == 1500:
				_check(inside == 0, "driving at the box, nobody drove into it (%d frames inside)" % inside)
				_check(fm.anchor.distance_to(Vector3.ZERO) < 60.0, "...though the fleet got right up to it (%.0f m)" % Vector2(fm.anchor.x, fm.anchor.z).length())
				fm.target_hp = 50.0
				fm.forced_input = {"main": true, "aim": _box_aim()}
				t0 = f
				phase = 5
		5:
			if f - t0 == 400:
				_check(fm.target_dead, "shot to nothing: the box is destroyed")
				_check(fm._banner.visible and fm._banner.text.contains("DESTROYED"), "TARGET DESTROYED on screen")
				print("fleet_test: %d checks, %d failures" % [checks, fails])
				quit(1 if fails > 0 else 0)
	return false
