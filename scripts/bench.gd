extends Node
## Firing benchmark, for measuring the web build: open the page with
## ?bench=fleet or ?bench=squad (desktop: -- --bench=fleet). The level select
## jumps straight there; this sits 6 s idle, then fires everything nonstop
## for 12 s, and prints frame rates to the console:
##   BENCH fleet idle 58.0 fps | firing 41.0 fps | worst frame 120 ms
## Does nothing without the parameter.

var host: Node
var _t := 0.0
var _frames := {"idle": [], "firing": []}
var _done := false


static func requested() -> String:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("window.location.search", true)
		if q is String and (q as String).contains("bench="):
			return (q as String).split("bench=")[1].split("&")[0]
		return ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench="):
			return a.substr(8)
	return ""


func _process(delta: float) -> void:
	if _done or host == null:
		return
	_t += delta
	var phase := "idle" if _t < 6.0 else "firing"
	if _t > 1.0:
		_frames[phase].append(delta)
	if host.get("forced_input") != null:
		_fleet(phase)
	else:
		_squad(phase)
	if _t > 18.0:
		_done = true
		var line := "BENCH %s" % ("fleet" if host.get("forced_input") != null else "squad")
		for k in ["idle", "firing"]:
			var a: Array = _frames[k]
			var sum := 0.0
			var worst := 0.0
			for d in a:
				sum += d
				worst = maxf(worst, d)
			line += " | %s %.1f fps, worst frame %.0f ms" % [k, a.size() / maxf(sum, 0.001), worst * 1000.0]
		print(line)


func _fleet(phase: String) -> void:
	var at: Vector3 = host._target.position + Vector3(0, 3, 0)
	if phase == "idle":
		host.forced_input = {"aim": at}
		return
	host.forced_input["aim"] = at
	host.forced_input["mg"] = true
	host.forced_input["main"] = true
	if host.mortars_ready() == host.vehicles.size():
		host.forced_input["mortar"] = true


func _squad(phase: String) -> void:
	var sq = host.squad
	if sq == null:
		return
	if _t < 1.5 and host.areas.size() > 0:
		# Up close to the first enemy position, everyone too tough to die.
		var c: Vector3 = host.areas[0]["center"] + Vector3(0, 0, 24)
		sq.teams[0]["anchor"] = c
		for s in sq.soldiers:
			s.global_position = c + s.slot_offset
			s.move_target = s.global_position
	for s in sq.soldiers:
		s.hp = 100000.0
	for a in host.areas:
		for m in a["members"]:
			if m.alive:
				m.hp = 100000.0
	sq.auto_fire = phase == "firing"
	host.debug_reticle_all = phase == "firing"
