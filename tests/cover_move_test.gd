extends SceneTree
## Persistent cover on the TEST FIELD (map 1):
##  1. take cover at the start, then hold W: the unit stays in cover the whole
##     way, nobody drops back to following, men hop to new cover and go prone
##     and crawl where there's none, and the unit ends up well forward with
##     every man settled in cover or prone
##  2. in open ground (no cover for 30 m): taking cover puts everyone prone;
##     prone men are low, small and harder to hit; WASD crawls them along,
##     still in cover; a move order (E) keeps cover too
##  3. C again (leave cover): everyone gets up and follows
## Crawling never goes faster than a crawl and no crawler gets stuck.
## Prints FAIL lines and exits 1 on any failure.

const Weapons = preload("res://scripts/weapons.gd")
const OPEN := Vector3(40, 0, 40)

var main
var f := 0
var fails := 0
var checks := 0
var start_c := Vector3.ZERO
var max_prone := 0
var hopped := {}
var fast_crawl := 0.0
var moving_status := false
var last_pos := {}
var stuck := {}
var worst_stuck := 0.0


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _centroid() -> Vector3:
	return main.squad.centroid()


## Every frame: crawl speed, and progress of every man crawling somewhere.
func _watch() -> void:
	var sq = main.squad
	var prone := 0
	for s in sq.soldiers:
		if s.is_prone():
			prone += 1
			if s._model.prone_amount() >= 1.0:      # all the way down (not sliding to a stop)
				var v: Vector3 = s.get_real_velocity()
				fast_crawl = maxf(fast_crawl, Vector2(v.x, v.z).length())
		if s._hop:
			hopped[s] = true
	max_prone = maxi(max_prone, prone)
	if f % 30 == 0:
		for s in sq.soldiers:
			var p: Vector3 = s.global_position
			var to: float = Vector2(s.cover_pos.x - p.x, s.cover_pos.z - p.z).length()
			if s.is_prone() and s._model.prone_amount() >= 1.0 and to > 0.6 and last_pos.has(s) and p.distance_to(last_pos[s]) < 0.1:
				stuck[s] = stuck.get(s, 0.0) + 0.5
				worst_stuck = maxf(worst_stuck, stuck[s])
			else:
				stuck[s] = 0.0
			last_pos[s] = p


func _physics_process(_d) -> bool:
	f += 1
	var sq = main.squad
	_watch()
	match f:
		30:
			sq.take_cover()
		300:
			for s in sq.soldiers:
				_check(s.state == 2, "#%d not settled in cover / prone 4 s after taking cover (state %d)" % [s.index, s.state])
			start_c = _centroid()
			Input.action_press("move_forward")
		720:
			Input.action_release("move_forward")
		1320:
			var c := _centroid()
			print("cover move: centroid %s -> %s, most prone at once %d, men who hopped cover %d, fastest crawl %.2f m/s" % [
					start_c.snapped(Vector3(0.1, 0.1, 0.1)), c.snapped(Vector3(0.1, 0.1, 0.1)), max_prone, hopped.size(), fast_crawl])
			_check(start_c.z - c.z > 6.0, "unit barely advanced in cover (%.1f m)" % (start_c.z - c.z))
			_check(max_prone > 0, "nobody went prone moving through open ground")
			_check(hopped.size() > 0, "nobody moved cover to cover")
			_check(moving_status, "status never showed the cover move")
			for s in sq.soldiers:
				_check(s.state == 2, "#%d not settled 10 s after the move (state %d)" % [s.index, s.state])
				_check(s.has_real_cover or s.is_prone(), "#%d settled neither in cover nor prone" % s.index)
			# open ground
			sq.leave_cover()
			sq.anchor = OPEN
			for s in sq.soldiers:
				s.global_position = OPEN + s.slot_offset
		1440:
			sq.take_cover()
		1620:
			var w: Dictionary = Weapons.ENEMY_RIFLE
			for s in sq.soldiers:
				_check(s.is_prone() and s.state == 2, "#%d not prone in open ground (prone %s, state %d)" % [s.index, s.is_prone(), s.state])
				_check(s.exposed_point().y - s.global_position.y < 0.4, "#%d prone but still exposed high" % s.index)
				_check(s._cap.height < 0.7, "#%d prone hitbox not shrunk (%.2f)" % [s.index, s._cap.height])
				var p: float = Weapons.enemy_hit_chance(w, s, 20.0, 0.0)
				_check(p <= w["acc"] * Weapons.PRONE_HIT + 0.001, "#%d prone hit chance %.2f not reduced" % [s.index, p])
				_check(not s.is_in_cover(), "#%d lying in the open counted as in cover" % s.index)
			start_c = _centroid()
			Input.action_press("move_left")
		1860:
			Input.action_release("move_left")
			_check(sq.in_cover, "unit dropped out of cover while crawling")
			for s in sq.soldiers:
				_check(s.is_prone(), "#%d got up crawling through open ground" % s.index)
			var moved: float = start_c.x - _centroid().x
			_check(moved > 1.5, "prone men didn't crawl (%.1f m)" % moved)
			# a move order keeps cover too
			sq.move_to(_centroid() + Vector3(-15, 0, 0))
		1880:
			_check(sq.in_cover, "move order broke cover")
			_check(sq.order_target != null, "move order lost")
		2160:
			var ev := InputEventAction.new()      # C again: leave cover
			ev.action = "take_cover"
			ev.pressed = true
			Input.parse_input_event(ev)
		2400:
			_check(not sq.in_cover, "unit still in cover after C")
			for s in sq.soldiers:
				_check(not s.is_prone() and s.state == 0, "#%d still down / in cover after leaving cover" % s.index)
			_check(fast_crawl < 1.2, "crawling too fast (%.2f m/s)" % fast_crawl)
			_check(worst_stuck < 3.0, "a crawler made no progress for %.1f s" % worst_stuck)
			print("cover move checks: %d, failures: %d" % [checks, fails])
			quit(1 if fails > 0 else 0)
	if f > 300 and f < 720:
		_check(sq.in_cover, "unit left cover while moving (frame %d)" % f)
		if f > 330:
			for s in sq.soldiers:
				if s.state == 0:
					_check(false, "#%d back to following mid cover move (frame %d)" % [s.index, f])
		if "COVER TO COVER" in sq.status_text():
			moving_status = true
	return false
