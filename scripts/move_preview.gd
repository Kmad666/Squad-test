extends Node3D
## Move preview: hold the reticle still on the ground and floating,
## see-through orbs show where each man of the team you command would end up
## if you pressed E now (squad.preview_move: the same rules as the move).
## In command mode (Tab) they follow the cursor, and with men selected show
## where a right click would send them (squad.preview_detach).
##   green  behind cover
##   amber  flat on the ground in the open (no cover there for him)
##   blue   standing in formation (an ordinary move: nobody takes cover)
## They fade out while the reticle sweeps and while the team is already on
## its way somewhere. On / off in the reticle settings (O); remembered.

const MAX_ORBS := 12
const HOVER := 1.25              # orb height over the spot (m)
const BOB := 0.07                # ... and how far it drifts up and down
const STEADY := 0.2              # reticle held this still (s) before they show
const SWEEP := 1.2               # the aim point moving more than this (m) per update: sweeping
const RANGE := 90.0              # no preview further than this from the team
const EVERY := 0.12              # re-plan this often (s)
const COLORS := {
	"cover": Color(0.35, 1.0, 0.45),
	"prone": Color(1.0, 0.72, 0.22),
	"open": Color(0.4, 0.8, 1.0),
}

static var enabled := true

var main: Node3D
var _orbs: Array = []           # [{root, shell, core, ring, pos, kind, on}]
var _t := 0.0
var _plan_t := 0.0
var _steady := 0.0
var _last_p: Variant = null
var _fade := 0.0                # 0..1, all orbs together
var aim_override: Variant = null   # tests: preview this point instead of the reticle's


static func load_setting() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	enabled = bool(cfg.get_value("game", "move_preview", true))


static func set_enabled(on: bool) -> void:
	enabled = on
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("game", "move_preview", on)
	cfg.save("user://settings.cfg")


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.36
	sphere.height = 0.72
	sphere.radial_segments = 20
	sphere.rings = 10
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.15
	core_mesh.height = 0.3
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.3
	ring_mesh.outer_radius = 0.42
	for i in MAX_ORBS:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var shell := _part(sphere, 0.3, root)       # the glassy outside
		var core := _part(core_mesh, 0.9, root)      # a brighter heart
		var ring := _part(ring_mesh, 0.45, self)     # the spot on the ground
		ring.visible = false
		_orbs.append({"root": root, "shell": shell, "core": core, "ring": ring, "pos": Vector3.ZERO, "kind": "open", "on": false})


func _part(mesh: Mesh, alpha: float, parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true                 # seen through the crate a man would be behind
	mat.disable_fog = true
	mat.render_priority = 2
	mat.albedo_color = Color(1, 1, 1, alpha)
	m.material_override = mat
	m.set_meta("alpha", alpha)
	parent.add_child(m)
	return m


func _process(delta: float) -> void:
	_t += delta
	var want := _wanted(delta)
	_fade = move_toward(_fade, 1.0 if want else 0.0, delta * (5.0 if want else 8.0))
	for i in _orbs.size():
		var o: Dictionary = _orbs[i]
		var show: bool = o["on"] and _fade > 0.01
		o["root"].visible = show
		o["ring"].visible = show
		if not show:
			continue
		var col: Color = COLORS[o["kind"]]
		var root: Node3D = o["root"]
		var target: Vector3 = o["pos"] + Vector3(0, HOVER + sin(_t * 2.2 + i * 1.3) * BOB, 0)
		root.global_position = root.global_position.lerp(target, 1.0 - exp(-14.0 * delta))
		var pulse := 0.85 + 0.15 * sin(_t * 3.0 + i)
		for part in [o["shell"], o["core"], o["ring"]]:
			var mat: StandardMaterial3D = part.material_override
			mat.albedo_color = Color(col.r, col.g, col.b, part.get_meta("alpha") * _fade * pulse)
		o["ring"].global_position = o["pos"] + Vector3(0, 0.06, 0)


## Should the preview show, and if so, re-plan now and then.
func _wanted(delta: float) -> bool:
	var sq = main.squad
	if not enabled or sq == null or sq.soldiers.is_empty():
		return false
	# Command mode (Tab): the cursor instead of the reticle, and with men
	# selected, where they'd go on their own.
	var cmd: bool = main.command != null and main.command.active()
	var men: Array = main.command.selected_men() if cmd else []
	if men.is_empty() and (sq.order_target != null or (not cmd and Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.05)):
		return false                   # already on the move
	var p: Variant = aim_override
	if p == null:
		p = main.command.hover_point() if cmd else main.reticle_ground_point()
	var reach := RANGE * (1.5 if cmd else 1.0)
	if p == null or (p as Vector3).distance_to(sq.anchor) > reach or (men.is_empty() and (p as Vector3).distance_to(sq.anchor) < 2.0):
		_last_p = null
		return false
	_plan_t -= delta
	if _plan_t > 0.0:
		return _steady >= STEADY
	_plan_t = EVERY
	if _last_p == null or (p as Vector3).distance_to(_last_p) > SWEEP:
		_steady = 0.0
	else:
		_steady += EVERY
	_last_p = p
	if _steady < STEADY:
		return false
	var plan: Array = sq.preview_move(p) if men.is_empty() else sq.preview_detach(men, p)
	for i in _orbs.size():
		var o: Dictionary = _orbs[i]
		if i < plan.size():
			var was: bool = o["on"]
			o["pos"] = plan[i]["pos"]
			o["kind"] = plan[i]["kind"]
			o["on"] = true
			if not was or _fade < 0.05:
				o["root"].global_position = o["pos"] + Vector3(0, HOVER, 0)   # appear in place, then glide
		else:
			o["on"] = false
	return not plan.is_empty()


## What the orbs show right now (tests): [{pos, kind}] of the ones lit.
func shown() -> Array:
	var out: Array = []
	if _fade < 0.5:
		return out
	for o in _orbs:
		if o["on"]:
			out.append({"pos": o["pos"], "kind": o["kind"]})
	return out
