extends SceneTree
## Move preview orbs on the TEST FIELD:
##  1. standing squad, reticle held on open ground: one blue ("open") orb
##     per man around the spot; none while the reticle sweeps
##  2. E there: the orbs go out while the squad moves, and when it stops
##     every man stands where his orb was
##  3. in cover, reticle on the crates further on: green orbs on cover spots
##     (amber for anyone who won't find any); after the cover-to-cover move
##     every man is at his orb
##  4. switched off: no orbs
## Prints FAIL lines and exits 1 on any failure.

const MovePreview = preload("res://scripts/move_preview.gd")

var main
var f := 0
var fails := 0
var checks := 0
var phase := 0
var t0 := 0
var plan: Array = []


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


## Each man's distance from the orb that was meant for him, worst first.
func _misses() -> Array:
	var out: Array = []
	for o in plan:
		var s: Node3D = o["man"]
		if is_instance_valid(s) and s in main.squad.soldiers:
			var at: Vector3 = s.cover_pos if s.state != 0 else s.global_position
			out.append(Vector2(at.x - o["pos"].x, at.z - o["pos"].z).length())
	out.sort()
	out.reverse()
	return out


func _physics_process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	var mp = main.move_preview
	match phase:
		0:
			if f == 60:
				mp.aim_override = Vector3(-14, 0, 30)
			if f == 70:
				_check(mp.shown().is_empty(), "no orbs the moment the reticle lands (it has to rest first)")
			if f == 120:
				var shown: Array = mp.shown()
				_check(shown.size() == sq.soldiers.size(), "reticle held still: an orb per man (%d of %d)" % [shown.size(), sq.soldiers.size()])
				var ok := true
				for o in shown:
					ok = ok and o["kind"] == "open" and (o["pos"] as Vector3).distance_to(Vector3(-14, 0, 30)) < 7.0
				_check(ok, "all blue (standing in formation), around the spot")
				# Sweep: the aim point jumps around every update.
				phase = 1
				t0 = f
		1:
			mp.aim_override = Vector3(-14 + (f % 20) * 0.6, 0, 30)
			if f - t0 == 60:
				_check(mp.shown().is_empty(), "sweeping the reticle: no orbs")
				mp.aim_override = Vector3(-14, 0, 30)
				t0 = f
				phase = 2
		2:
			if f - t0 == 60:
				plan = sq.preview_move(Vector3(-14, 0, 30))
				sq.move_to(Vector3(-14, 0, 30))
			if f - t0 == 90:
				_check(mp.shown().is_empty(), "on the move: the orbs go out")
			if f - t0 == 600:
				var m := _misses()
				print("formation move: misses ", m.map(func(v): return snappedf(v, 0.01)))
				_check(m[0] < 1.5, "every man ended at his orb (worst %.2f m)" % m[0])
				sq.take_cover(0, Vector3(0, 0, -1))
				t0 = f
				phase = 3
		3:
			if f - t0 == 300:
				mp.aim_override = Vector3(-4, 0, 38.5)      # just behind the crates south of the start
			if f - t0 == 380:
				var shown: Array = mp.shown()
				var kinds := {}
				for o in shown:
					kinds[o["kind"]] = kinds.get(o["kind"], 0) + 1
				print("cover move preview: ", kinds)
				_check(shown.size() == sq.soldiers.size(), "in cover: an orb per man (%d)" % shown.size())
				_check(kinds.get("cover", 0) >= 2 and not kinds.has("open"), "green orbs on the cover spots (%s)" % [kinds])
				plan = sq.preview_move(Vector3(-4, 0, 38.5))
				sq.move_to(Vector3(-4, 0, 38.5))
			if f - t0 == 1200:
				var m := _misses()
				print("cover move: misses ", m.map(func(v): return snappedf(v, 0.01)))
				_check(m[0] < 1.2, "cover to cover: every man ended at his orb (worst %.2f m)" % m[0])
				MovePreview.enabled = false
				mp.aim_override = Vector3(-14, 0, 30)
				t0 = f
				phase = 4
		4:
			if f - t0 == 120:
				_check(mp.shown().is_empty(), "switched off: no orbs")
				MovePreview.enabled = true
				print("preview_test: %d checks, %d failures" % [checks, fails])
				quit(1 if fails > 0 else 0)
	return false
