extends SceneTree
## Enemy small-unit tactics on the TEST FIELD (scripts/enemy_tactics.gd):
##  1. FLANK: in contact with BRAVO (3 men), one man goes to fight from the
##     squad's side while the others give covering fire
##  2. a man caught by heavy fire on a long move goes to ground where he is
##  3. GRENADE: a man warned of a frag sprints clear of it
##  4. REINFORCE: quiet ALPHA sends a man to BRAVO
##  5. FALL BACK: BRAVO worn down, the survivor runs to CHARLIE (away from us)
##  6. ASSAULT: outnumbering what's left of the squad, they close in
## Prints FAIL lines and exits 1 on any failure.

const Tactics = preload("res://scripts/enemy_tactics.gd")

var main
var f := 0
var phase := 0
var t0 := 0
var fails := 0
var checks := 0
var saw_covering := false
var man: Node3D
var mark := Vector3.ZERO
var tries := 0


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 1
	Tactics.falling_back = false
	Tactics.reinforcing = false
	Tactics.assaulting = false
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _next() -> void:
	phase += 1
	t0 = f


func _physics_process(_d: float) -> bool:
	f += 1
	var sq = main.squad
	if f < 5:
		return false
	var alpha: Dictionary = main.areas[0]
	var bravo: Dictionary = main.areas[1]
	var charlie: Dictionary = main.areas[2]
	# Our men are the audience here: they don't shoot and can't be hurt.
	sq.forced_mode = 0
	for s in sq.soldiers:
		s.hp = s.MAX_HP
	var e: int = f - t0
	match phase:
		0:
			if f == 5:
				sq.anchor = Vector3(2, 0, 12)
			if f == 500:
				_check(sq.centroid().distance_to(Vector3(2, 0, 12)) < 6.0, "squad in position in front of BRAVO")
				bravo["alerted"] = true
				_next()
		1:
			# FLANK
			for m in Tactics.infantry(bravo):
				if m.covering:
					saw_covering = true
			var flankers: Array = bravo.get("flankers", [])
			if not flankers.is_empty() and flankers[0].state == 2:
				man = flankers[0]
				var sq_c: Vector3 = sq.centroid()
				var axis: Vector3 = (bravo["center"] - sq_c).normalized()
				var off: Vector3 = man.global_position - sq_c
				off.y = 0
				var ang := rad_to_deg(acos(clampf(axis.dot(off.normalized()), -1.0, 1.0)))
				print("flanker in position after %.0f s: %.0f deg off the axis, %.0f m from the squad, %s" % [e / 60.0, ang, off.length(), "in cover" if not man._hasty else "in the open"])
				_check(man.role == "flank", "the man is on a flank role")
				_check(ang > 35.0, "he's off to the squad's side (%.0f deg)" % ang)
				_check(off.length() < 34.0, "and close enough to matter (%.0f m)" % off.length())
				_check(not man._hasty, "he found cover out there")
				if not man._hasty:
					var to_sq: Vector3 = sq_c - man._cover["pos"]
					to_sq.y = 0
					_check(man._cover["normal"].dot(to_sq.normalized()) < -0.1, "his cover shields him from the squad")
				_check(saw_covering, "the others gave covering fire while he moved")
				_check(Tactics.infantry(bravo).size() - flankers.size() >= 2, "a base of fire stayed behind")
				_next()
			elif e > 60 * 75:
				_check(false, "nobody flanked within 75 s (flankers %d)" % flankers.size())
				_next()
		2:
			# Caught in the open: a base-of-fire man is sent on a long move, then pinned.
			if e == 1:
				Tactics.flanking = false
				for m in Tactics.infantry(bravo):
					if m.role == "hold":
						man = m
				man.role = "flank"
				man.set_scope(man.global_position + Vector3(-40, 0, 6), 6.0, 20.0)
				man.hurry()
			if e > 90 and man.state == 1 and man.global_position.distance_to(man._dest) > 12.0 and mark == Vector3.ZERO:
				mark = man.global_position
				tries = e
			if mark != Vector3.ZERO and e - tries < 90:
				man._gun.add_suppression(1.0)
			if mark != Vector3.ZERO and e - tries == 90:
				_check(man.state == 2 and man._hasty, "pinned on the move: he went to ground (state %d)" % man.state)
				_check(man.global_position.distance_to(mark) < 3.0, "right where he was (%.1f m on)" % man.global_position.distance_to(mark))
				_check(man._crouched or man._peeking, "down in a hasty position")
				man.hold()
				man.hurry()
				mark = Vector3.ZERO
				tries = 0
				_next()
			elif e > 60 * 20 and mark == Vector3.ZERO:
				_check(false, "the man never set off on his long move")
				_next()
		3:
			# GRENADE: warn a settled man until he reacts (he won't every time).
			if e == 240:
				for m in Tactics.infantry(bravo):
					if m.state == 2 and m.suppression_level() < 0.5:
						man = m
				mark = man.global_position + Vector3(0.6, 0, 0)
			if e >= 240 and man._dive_t <= 0.0 and tries < 12 and e % 5 == 0 and mark != Vector3.INF:
				tries += 1
				man.grenade_warning(mark, 4.5, 1.6)
				if man._dive_t > 0.0:
					t0 = f - 1000        # e restarts from 1000: the fuse is running
			if e == 1000 + 96 and man._dive_t >= 0.0 and tries > 0:
				var d: float = man.global_position.distance_to(mark)
				print("grenade: reacted on warning %d, %.1f m clear when it went off" % [tries, d])
				_check(d > 4.0, "he got clear of the frag (%.1f m)" % d)
				mark = Vector3.ZERO
				_next()
			elif e == 900:
				_check(false, "twelve warnings and he never ran")
				_next()
		4:
			# REINFORCE
			if e == 1:
				Tactics.reinforcing = true
				bravo["contact_t"] = 20.0
				tries = Tactics.infantry(bravo).size()
			if e == 90:
				# The nearer quiet neighbour sends half its riflemen (one of two).
				var donor: Dictionary = alpha if alpha.get("qrf_sent", false) else charlie
				print("reinforce: %s sent a man to BRAVO (ALPHA %d, BRAVO %d, CHARLIE %d)" % [donor["name"], Tactics.infantry(alpha).size(), Tactics.infantry(bravo).size(), Tactics.infantry(charlie).size()])
				_check(donor.get("qrf_sent", false) and Tactics.infantry(donor).size() == 1, "a quiet neighbour sent a man (%d left there)" % Tactics.infantry(donor).size())
				_check(Tactics.infantry(bravo).size() == tries + 1, "BRAVO has him on its books (%d)" % Tactics.infantry(bravo).size())
				_check(donor["alerted"], "the neighbour is awake now")
				_check(main._notice.contains("REINFORCEMENTS"), "the player is told (%s)" % main._notice)
				man = Tactics.infantry(bravo)[-1]
			if e == 60 * 14:
				_check(man.global_position.distance_to(bravo["center"]) < bravo["radius"] + 2.0, "the reinforcement arrived at BRAVO (%.0f m out)" % man.global_position.distance_to(bravo["center"]))
				Tactics.reinforcing = false
				_next()
		5:
			# FALL BACK
			if e == 1:
				Tactics.falling_back = true
				var men: Array = Tactics.infantry(bravo)
				for i in men.size() - 1:
					men[i].take_damage(99.0, 0.0)
				man = men[-1]
				tries = Tactics.infantry(charlie).size()
			if e == 240:
				print("fall back: survivor now in %s (ALPHA %d, BRAVO %d, CHARLIE %d)" % [man.area["name"], Tactics.infantry(alpha).size(), Tactics.infantry(bravo).size(), Tactics.infantry(charlie).size()])
				_check(Tactics.infantry(bravo).is_empty(), "BRAVO given up (%d still there)" % Tactics.infantry(bravo).size())
				_check(man.area == charlie, "the survivor fell back to CHARLIE, away from the squad (now %s)" % man.area["name"])
				_check(Tactics.infantry(charlie).size() == tries + 1, "CHARLIE counts him")
				_check(main.areas_text().contains("BRAVO CLEAR"), "the HUD shows BRAVO clear (%s)" % main.areas_text())
			if e == 60 * 16:
				_check(man.global_position.distance_to(charlie["center"]) < charlie["radius"] + 2.0, "he made it to CHARLIE (%.0f m out)" % man.global_position.distance_to(charlie["center"]))
				_next()
		6:
			# ASSAULT: one of ours left, three of them.
			if e == 1:
				Tactics.assaulting = true
				charlie["alerted"] = true
				sq.anchor = Vector3(16, 0, 4)
				while sq.soldiers.size() > 1:
					var s = sq.soldiers[-1]
					s.hp = 0.1
					s.take_damage(50.0, s.global_position + Vector3(0, 0, -5))
			if e == 60 * 30:
				var n := 0
				var near := 0
				for m in Tactics.infantry(charlie):
					if m.role == "assault":
						n += 1
					if m.global_position.distance_to(sq.centroid()) < 32.0:
						near += 1
				print("assault: posture %s, %d on assault, %d within 32 m of the squad" % [charlie["posture"], n, near])
				_check(charlie["posture"] == "assault", "CHARLIE goes over to the assault")
				_check(n >= 2, "its men are on assault roles (%d)" % n)
				_check(near >= 2, "and they've closed in (%d within 32 m)" % near)
				print("tactics_test: %d checks, %d failures" % [checks, fails])
				quit(1 if fails > 0 else 0)
	return false
