extends SceneTree
## Randomised long soak: random move orders, WASD bursts (in and out of
## cover), cover toggles, fire modes, specials, quality toggles and restarts.
## Stacking on doors and breaching where the map has houses. Watches for
## errors, and a watchdog looks at every man twice a second: anyone outside
## the map, inside a wall, or trying to move and going nowhere for 12 s is
## reported (WATCHDOG lines) and fails the run.
var main
var f := 0
var rng := RandomNumberGenerator.new()
var restarts := 0
var held := ""                  # WASD action being held, released at release_f
var release_f := 0
var watch := {}                 # man -> {pos, t (s going nowhere), walled (s inside a box)}
var problems := 0
var duration := 60 * 60 * int(OS.get_environment("MINUTES") if OS.get_environment("MINUTES") != "" else "5")
func _initialize():
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	load("res://scripts/main.gd").forced_map = int(OS.get_environment("MAP")) if OS.get_environment("MAP") != "" else 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _physics_process(_d):
	f += 1
	if main == null or not is_instance_valid(main):
		return false
	var sq = main.squad
	if f % 3 == 0: main.debug_reticle_all = rng.randf() < 0.5
	if held != "" and f >= release_f:
		Input.action_release(held)
		held = ""
	if f % 90 == 0:
		var k: float = main.nav_half / 50.0      # random spots across the whole map, big or small
		match rng.randi_range(0, 16):
			0, 1: sq.move_to(Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45)) * k)
			2: sq.take_cover() if not sq.in_cover else sq.leave_cover()
			3: sq.forced_mode = rng.randi_range(0, 2)
			4: sq.forced_specials = not sq.forced_specials
			5: main.cam_rig.yaw = rng.randf_range(-PI, PI)
			6:
				match rng.randi_range(0, 4):
					0: main.toggle_quality()
					1: main.toggle_retro()
					2: main.toggle_lights()
					3: main.toggle_night_vision()
					4: main.toggle_thermal()
			7: sq.anchor = Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45)) * k
			8: sq.join_teams() if sq.split else sq.split_teams()
			9: sq.switch_team()
			10: sq.start_bound(Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-45, 45)) * k)
			11: sq.set_holding(not sq.holding)
			12:
				if held == "":
					held = ["move_forward", "move_back", "move_left", "move_right"][rng.randi_range(0, 3)]
					Input.action_press(held)
					release_f = f + rng.randi_range(30, 300)
			13: sq.toggle_lav()                  # LAV with us / overwatch (no-op without one)
			14:
				if sq.lav and rng.randf() < 0.3:
					sq.lav.armor_hit(60.0)           # chip at it; now and then it's lost mid-move
			15:
				if not main.doors.is_empty():      # stack on some door near or far, whoever's commanding
					sq.breach_order(rng.randi_range(0, main.doors.size() - 1))
			16: sq.breach_order()                  # go (or stack on whatever's nearest, or nothing)
	if f % 30 == 0:
		_watchdog()
	if f % 1800 == 0:
		var alive = 0
		for t in main.targets: alive += int(t.alive)
		print("t=", f / 60, "s squad ", sq.soldiers.size(), " kia ", sq.kia, " enemies alive ", alive, " kills ", main.kills, " nodes ", root.get_child_count(), " objs ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		if sq.soldiers.is_empty() or alive == 0:
			restarts += 1
			print("  reload (", restarts, ")")
			main.queue_free()
			main = load("res://main.tscn").instantiate()
			root.add_child(main)
	if f >= duration:
		print("done, restarts ", restarts, ", watchdog problems ", problems)
		quit(1 if problems > 0 else 0)
	return false


func _report(what: String, m: Node3D) -> void:
	problems += 1
	if problems <= 12:
		print("WATCHDOG t=%ds %s: %s at %s  %s" % [f / 60, what, m.name, m.global_position.snapped(Vector3(0.01, 0.01, 0.01)), _describe(m)])


func _describe(m: Node3D) -> String:
	if m.get("cover_pos") != null:
		return "squad #%d state %d prone %s stacked %s dest %s" % [m.index, m.state, m.is_prone(), m.stacked, (m.cover_pos if m.state != 0 else m.move_target).snapped(Vector3(0.1, 0.1, 0.1))]
	return "enemy role %s state %d area %s dest %s" % [m.role, m.state, m.area["name"], m._dest.snapped(Vector3(0.1, 0.1, 0.1))]


func _watchdog() -> void:
	var men: Array = main.squad.soldiers.duplicate()
	for t in main.targets:
		if t.alive and t.kind == "infantry":
			men.append(t)
	var lim: float = main.nav_half + 1.5
	for m in men:
		var p: Vector3 = m.global_position
		if not watch.has(m):
			watch[m] = {"pos": p, "t": 0.0, "walled": 0.0, "told": false}
		var w: Dictionary = watch[m]
		if w["told"]:
			continue
		if is_nan(p.x) or is_nan(p.z) or absf(p.x) > lim or absf(p.z) > lim or p.y < -0.6 or p.y > 2.5:
			w["told"] = true
			_report("OUT OF THE MAP", m)
			continue
		# Deep inside a box (not just brushing it) for two seconds.
		w["walled"] = w["walled"] + 0.5 if main.CoverUtil.inside_any(main.cover_defs, p, -0.35) else 0.0
		if w["walled"] >= 2.0:
			w["told"] = true
			_report("INSIDE A BOX", m)
			continue
		# Wants to move, isn't moving.
		var trying: bool = m._moving if m.get("cover_pos") != null else (m.state == 1 and m.global_position.distance_to(m._dest) > 1.0)
		if trying and p.distance_to(w["pos"]) < 0.4:
			w["t"] += 0.5
			if w["t"] >= 12.0:
				w["told"] = true
				_report("STUCK 12 s", m)
		else:
			w["t"] = 0.0
			w["pos"] = p
	for m in watch.keys():
		if not is_instance_valid(m):
			watch.erase(m)
