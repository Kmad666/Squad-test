extends SceneTree
## In-game edge cases for the soldier model: men killed mid-run, crouched and
## mid-signal; the sergeant killed (promotion); crouch toggled every frame;
## enemies killed while peeking. Corpses must rest on the ground, no errors.
## MAP env var picks the map (default 1, TEST FIELD).

var main
var frame := 0
var fails := 0


func _initialize() -> void:
	load("res://scripts/main.gd").forced_map = int(OS.get_environment("MAP")) if OS.get_environment("MAP") != "" else 1
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)


func _on_ground(model: Node3D, label: String) -> void:
	var low := INF
	for mi in model._meshes:
		if mi.get_parent() == model._rifle:
			continue
		var bb: AABB = mi.get_aabb()
		for c in 8:
			low = minf(low, (mi.global_transform * bb.get_endpoint(c)).y)
	var ground: float = model.get_parent().global_position.y
	_check(absf(low - ground) < 0.03, "%s corpse not on the ground (lowest %.3f, ground %.3f)" % [label, low, ground])
	var ry: float = model._rifle.global_position.y - ground
	_check(ry > 0.0 and ry < 0.08, "%s rifle not on the ground (%.3f)" % [label, ry])


func _physics_process(_d) -> bool:
	frame += 1
	var sq = main.squad
	match frame:
		30:
			sq.move_to(sq.soldiers[0].global_position + Vector3(0, 0, -30))
		75:
			# mid-run, sergeant signalling: kill a running man and one mid-signal
			sq.soldiers[0].signal_hand("move")
			sq.soldiers[1].signal_hand("halt")
			sq.soldiers[1].take_damage(500.0, Vector3.ZERO)
			sq.soldiers[2].take_damage(500.0, Vector3.ZERO)
		80:
			# kill the sergeant mid-gesture: promotion
			var sgt = sq.soldiers[0]
			_check(sgt.is_sergeant, "soldiers[0] should be the sergeant")
			sgt.take_damage(500.0, Vector3.ZERO)
		81:
			var heirs := 0
			for s in sq.soldiers:
				if s.is_sergeant:
					heirs += 1
			_check(heirs == 1, "exactly one new sergeant after promotion (got %d)" % heirs)
		100:
			sq.take_cover()
	if frame >= 110 and frame < 170 and sq.soldiers.size() > 1:
		sq.soldiers[1]._set_crouch(frame % 2 == 0)          # crouch spam
	if frame == 170 and sq.soldiers.size() > 1:
		sq.soldiers[1]._set_crouch(true)
	if frame == 175 and sq.soldiers.size() > 1:
		sq.soldiers[1].take_damage(500.0, Vector3.ZERO)     # dies crouched, still easing down
	if frame == 200:
		# enemies: kill everyone, whatever they are doing
		var n := 0
		for a in main.areas:
			for e in a["members"]:
				if "alive" in e and e.alive and e.has_method("_set_crouch"):
					if n % 2 == 0:
						e._set_crouch(true)
					e.take_damage(500.0, 0.0)
					n += 1
		print("enemies killed: ", n)
	if frame == 260:
		var dead_f := 0
		for child in main.squad.get_children():
			if child.has_method("signal_hand") and child.dead:
				dead_f += 1
				_on_ground(child._model, "friendly %s" % child.name)
		for a in main.areas:
			for e in a["members"]:
				if "alive" in e and not e.alive and e.has_method("_set_crouch"):
					_on_ground(e._model, "enemy %s" % e.name)
		print("friendly corpses checked: ", dead_f)
		_check(dead_f >= 4, "expected at least 4 dead friendlies, found %d" % dead_f)
		print("death test failures: ", fails)
		quit(1 if fails > 0 else 0)
	return false
