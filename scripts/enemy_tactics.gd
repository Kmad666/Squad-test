extends Node
## The enemy's small-unit tactics: one brain looking at every defended area
## twice a second and giving the men in it roles. The men themselves still
## do their own cover, peeking and shooting (enemy_soldier.gd); this decides
## WHERE they fight.
##
##  FLANK     After a few seconds in contact, one man (two from a big group)
##            goes to fight from cover off to the squad's side while the rest
##            keep up covering fire (up more, down less). Heavy fire on a
##            flanker in the open puts him to ground until it lifts. Recalled
##            if the squad moves on, or after a while.
##  FALL BACK A position worn down to a third of its men gives it up: the
##            survivors run to the next position further from the squad.
##  REINFORCE A position in a fight gets half the men of a quiet position
##            nearby (riflemen only; once each way).
##  ASSAULT   Outnumbering the squad two to one, they close in, cover to cover.
##
## A house garrison (an area with a "rect") only ever receives: it doesn't
## flank, assault, fall back out of its house or send men away.
##
## Each can be switched off (the statics) for tests and tuning.

const EnemySoldier = preload("res://scripts/enemy_soldier.gd")
const Weapons = preload("res://scripts/weapons.gd")

const FLANK_OUT := 20.0        # how far off to the side a flanker goes (m from the squad)
const FLANK_SCOPE := 14.0      # ... and how far from that spot he'll take cover
const CONTACT := 45.0          # squad this close to an area's edge: in contact
const REINFORCE_REACH := 95.0  # areas this close send help
const FALLBACK_REACH := 110.0
const WAKE_REACH := 75.0        # NORMAL: positions this close hear the fight and stand to

static var flanking := true
static var falling_back := true
static var reinforcing := true
static var assaulting := true
static var verbose := false     # print each decision (probes and tuning)

var main: Node3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	var dt := _t
	_t = 0.0
	if main.squad == null or main.squad.soldiers.is_empty():
		return
	for area in main.areas:
		_think(area, dt)


static func infantry(area: Dictionary) -> Array:
	var out: Array = []
	for m in area["members"]:
		if m.alive and m.kind == "infantry":
			out.append(m)
	return out


## The middle of the fire team nearest to `p`.
func squad_near(p: Vector3) -> Vector3:
	var sq: Node3D = main.squad
	if not sq.split:
		return sq.centroid()
	var best: Vector3 = sq.centroid()
	var bd := INF
	for t in 2:
		if sq.team_members(t).is_empty():
			continue
		var c: Vector3 = sq.centroid(t)
		if c.distance_to(p) < bd:
			bd = c.distance_to(p)
			best = c
	return best


func in_contact(area: Dictionary) -> bool:
	return area["alerted"] and squad_near(area["center"]).distance_to(area["center"]) < area["radius"] + CONTACT


func _think(area: Dictionary, dt: float) -> void:
	var men := infantry(area)
	if not area.has("initial"):
		area["initial"] = men.size()
		area["contact_t"] = 0.0
		area["flank_cd"] = _rng.randf_range(8.0, 14.0)
		area["flankers"] = []
		area["posture"] = "defend"
	if men.is_empty() or not area["alerted"]:
		return
	var sq_c := squad_near(area["center"])
	var contact := in_contact(area)
	area["contact_t"] = area["contact_t"] + dt if contact else maxf(0.0, area["contact_t"] - dt)

	# NORMAL: gunfire wakes the neighbours. A few seconds into a fight the
	# positions close by get into cover and stand to, instead of being found
	# at their posts when the squad arrives.
	if Weapons.difficulty >= 1 and area["contact_t"] > 3.0 and not area.get("woke", false):
		area["woke"] = true
		for a in main.areas:
			if a != area and not a["alerted"] and (a["center"] as Vector3).distance_to(area["center"]) < WAKE_REACH and not infantry(a).is_empty():
				_alert_quietly(a)

	# Covering fire while a mate is moving up.
	var mover := false
	for m in men:
		if m.role != "hold" and m.state == EnemySoldier.State.MOVING:
			mover = true
	for m in men:
		m.covering = mover and m.role == "hold"

	# Men posted to hold a house hold it: they give ground room by room
	# (their own cover sense does that) but don't go out to flank, assault
	# or fall back, and aren't sent off to reinforce the street.
	var garrison: bool = area.get("rect") != null
	if falling_back and contact and not garrison and _fall_back(area, men, sq_c):
		return
	if assaulting and not garrison:
		_assault(area, men, sq_c, contact)
	if flanking and not garrison:
		_flank(area, men, sq_c, contact, dt)
	if reinforcing and contact and area["contact_t"] > 12.0 and not area.get("qrf_got", false):
		_reinforce(area)


# ---------------------------------------------------------------- fall back

func _fall_back(area: Dictionary, men: Array, sq_c: Vector3) -> bool:
	if area.get("fell_back", false) or area["initial"] < 2 or men.size() > int(ceil(area["initial"] * 0.34)):
		return false
	for m in men:
		if m.suppression_level() > 0.85:
			return false                   # pinned men can't break contact; wait for a lull
	var here: float = sq_c.distance_to(area["center"])
	var dest: Dictionary = {}
	var best := INF
	for a in main.areas:
		if a == area or infantry(a).is_empty():
			continue
		var d: float = (a["center"] as Vector3).distance_to(area["center"])
		if d > FALLBACK_REACH or sq_c.distance_to(a["center"]) < here + 8.0:
			continue                       # only away from the squad
		if d < best:
			best = d
			dest = a
	if dest.is_empty():
		return false                       # nowhere to go: last stand
	area["fell_back"] = true
	area["flankers"] = []
	for m in men:
		m.join_area(dest)
	_alert_quietly(dest)
	_say("%s falls back to %s (%d men)" % [area["name"], dest["name"], men.size()])
	main.on_area_abandoned(area, dest)
	return true


# ---------------------------------------------------------------- assault

func _assault(area: Dictionary, men: Array, sq_c: Vector3, contact: bool) -> void:
	var ours: int = main.squad.soldiers.size()
	if main.squad.lav and main.squad.lav.alive:
		ours += 4
	var go: bool = contact and area["contact_t"] > 6.0 and men.size() >= 2 * ours
	if go:
		if area["posture"] != "assault":
			_say("%s assaults (%d men vs %d)" % [area["name"], men.size(), ours])
		area["posture"] = "assault"
		for m in men:
			if m.rpg or m.role == "flank":
				continue
			m.role = "assault"
			m.set_scope(sq_c, 26.0, 14.0)
	elif area["posture"] == "assault":
		area["posture"] = "defend"
		for m in men:
			if m.role == "assault":
				m.hold()
				m.hurry()


# ---------------------------------------------------------------- flank

func _flank(area: Dictionary, men: Array, sq_c: Vector3, contact: bool, dt: float) -> void:
	var active: Array = []
	for m in area["flankers"]:
		if is_instance_valid(m) and m.alive and m.role == "flank" and m.area == area:
			active.append(m)
	area["flankers"] = active
	if not active.is_empty():
		area["flank_t"] = area.get("flank_t", 0.0) + dt
		var moved: float = sq_c.distance_to(area["flank_from"])
		if not contact or moved > 22.0 or area["flank_t"] > 50.0:
			for m in active:
				m.hold()
				m.hurry()
			area["flankers"] = []
			area["flank_cd"] = _rng.randf_range(15.0, 25.0)
			return
		if not area.get("flank_called", false):
			for m in active:
				if _squad_sees(m):
					area["flank_called"] = true
					main.on_flank_spotted(area, m)
					break
		return
	if not contact or area["posture"] != "defend":
		return
	area["flank_cd"] -= dt
	if area["flank_cd"] > 0.0 or men.size() < 3:
		return
	area["flank_cd"] = _rng.randf_range(35.0, 50.0)
	# Which side? The one with more usable cover out there (and on the map).
	var axis: Vector3 = area["center"] - sq_c
	axis.y = 0
	if axis.length() < 6.0:
		return
	axis = axis.normalized()
	var perp := Vector3(-axis.z, 0, axis.x)
	var best_p := Vector3.INF
	var best_n := 0
	for side in [-1.0, 1.0]:
		var p: Vector3 = sq_c + perp * side * FLANK_OUT + axis * 4.0
		var lim: float = main.nav_half - 4.0
		if absf(p.x) > lim or absf(p.z) > lim:
			continue
		var n := _flank_cover(p, sq_c) + _rng.randi_range(0, 1)
		if n > best_n:
			best_n = n
			best_p = p
	if best_n < 2:
		return                             # nothing out there to fight from
	var picks: Array = []
	for m in men:
		if m.role == "hold" and not m.rpg and m.hp >= m.MAX_HP * 0.5 and m.suppression_level() < 0.85:
			picks.append(m)
	picks.sort_custom(func(a, b): return a.global_position.distance_to(best_p) < b.global_position.distance_to(best_p))
	var count := 1 if men.size() < 5 else 2
	if picks.size() < count or men.size() - count < 2:
		return                             # keep a base of fire
	for i in count:
		var m: Node3D = picks[i]
		m.role = "flank"
		m.set_scope(best_p, FLANK_SCOPE, 20.0)
		m.hurry()
		area["flankers"].append(m)
	_say("%s sends %d to flank" % [area["name"], count])
	area["flank_from"] = sq_c
	area["flank_t"] = 0.0
	area["flank_called"] = false


## Cover spots near `p` that would shield a man from the squad.
func _flank_cover(p: Vector3, sq_c: Vector3) -> int:
	var n := 0
	for cp in main.cover_points:
		var c: Vector3 = cp["pos"]
		if Vector2(c.x - p.x, c.z - p.z).length() > FLANK_SCOPE:
			continue
		var to_sq := sq_c - c
		to_sq.y = 0
		if (cp["normal"] as Vector3).dot(to_sq.normalized()) < -0.3 and to_sq.length() > 8.0:
			n += 1
	return n


func _squad_sees(m: Node3D) -> bool:
	var space := main.get_world_3d().direct_space_state
	for s in main.squad.soldiers:
		if s.global_position.distance_to(m.global_position) > 55.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(s.global_position + Vector3(0, 1.5, 0), m.aim_point(), 1)
		if space.intersect_ray(q).is_empty():
			return true
	return false


# ---------------------------------------------------------------- reinforce

func _reinforce(area: Dictionary) -> void:
	var donor: Dictionary = {}
	var best := INF
	for a in main.areas:
		if a == area or a.get("qrf_sent", false) or a.get("fell_back", false) or in_contact(a) or a.get("rect") != null:
			continue
		var riflemen := 0
		for m in infantry(a):
			if not m.rpg:
				riflemen += 1
		if riflemen < 2:
			continue
		var d: float = (a["center"] as Vector3).distance_to(area["center"])
		if d <= REINFORCE_REACH and d < best:
			best = d
			donor = a
	if donor.is_empty():
		return
	var go: Array = []
	for m in infantry(donor):
		if not m.rpg:
			go.append(m)
	go.sort_custom(func(a, b): return a.global_position.distance_to(area["center"]) < b.global_position.distance_to(area["center"]))
	var count := mini(go.size(), infantry(donor).size() / 2)
	if count < 1:
		return
	donor["qrf_sent"] = true
	area["qrf_got"] = true
	if not donor.has("initial"):
		donor["initial"] = infantry(donor).size()
	donor["initial"] -= count              # the men left behind judge "worn down" by what stayed
	area["initial"] += count
	_alert_quietly(donor)
	for i in count:
		go[i].join_area(area)
	_say("%s reinforces %s with %d" % [donor["name"], area["name"], count])
	main.on_reinforcements(donor, area, count)


func _say(text: String) -> void:
	if verbose:
		print("  [tactics %ds] %s" % [Engine.get_physics_frames() / 60, text])


## Gunfire next door: they're awake, without the "CONTACT" announcement.
func _alert_quietly(area: Dictionary) -> void:
	if not area["alerted"]:
		area["alerted"] = true
		main.refresh_area(area)
