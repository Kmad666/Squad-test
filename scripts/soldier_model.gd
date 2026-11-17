extends Node3D
## The soldier, blocky: box legs, torso, arms and head (a helmet slab on
## top), and a black stick for a rifle. Nothing walks: the legs never move.
## The arms do: hands stay on the rifle (two-bone IK), it comes up to the
## shoulder to aim, kicks on each shot, and the left hand gives signals.
## Crouched, the upper body hunches forward at the waist. Prone, the whole
## block figure lies flat. Dead, it falls on its face or its back.
##
## Model space: -Z ahead, +X his right, feet at the origin.
## Same interface as before (soldier.gd, enemy_soldier.gd and the tests use
## it): build, animate, set_aim_point, recoil, set_crouch, set_prone,
## gesture, set_team_patch, set_sergeant, set_tint, lay_down.

const Atmosphere = preload("res://scripts/atmosphere.gd")
const SHADER = preload("res://shaders/soldier.gdshader")

# Body (metres).
const HIP_Y := 0.92           # top of the legs
const HIP_X := 0.125          # leg centres either side
const LEG_SIZE := Vector3(0.22, 0.92, 0.24)
const WAIST_Y := 0.92         # the upper body hunches forward about this height
const TORSO := Vector3(0.52, 0.62, 0.3)
const NECK_Y := 1.54          # top of the torso, bottom of the head
const HEAD := 0.32
const SHOULDER := Vector3(0.33, 1.47, 0.0)
const UPPER_ARM := 0.36
const FOREARM := 0.36
const ARM_W := 0.17
# (kept for code that still asks: the legs are one straight block)
const THIGH := 0.46
const SHIN := 0.46
const ANKLE_Y := 0.0
const LEG := 0.92

const HUNCH := 0.75           # crouched: forward lean at the waist (radians)
const POCKET := Vector3(0.17, 1.4, -0.16)        # rifle butt when aimed (upper space)
const PRONE_POCKET := Vector3(0.19, 1.6, 0.06)   # ... lying down: beside his head, clear of the ground
const AIM_YAW := 0.6          # how far the rifle can swing off the body's facing
const AIM_PITCH := 0.4
const PRONE_LIFT := 0.15      # lying flat: half the body's thickness off the ground
const PRONE_BACK := 0.95      # ... and slid back so the middle of him is on his spot
const GUN_LEN := 0.82
const BODY_LAYER := 2         # render layer of soldier bodies (weapon lights don't take shadows from them)

# Material IDs in the vertex alpha (shaders/soldier.gdshader): plain fabric,
# weapon metal, skin.
const FABRIC := 0.85
const METAL := 0.40
const SKIN := 0.10

static var _mats := {}
static var _box_cache := {}
static var low_quality := false
static var retro := false     # RETRO graphics: the soldiers were blocky already (kept for main.gd)
static var mocap_gait := false
static var detailed := false
static var thermal := false   # thermal sight (I): bodies glow hot inside the reticle
static var thermal_rect := Vector4.ZERO   # the reticle in screen UV (x0, y0, x1, y1)

var upper: Node3D            # torso, head, arms, rifle (hunches forward when crouched)
var head: Node3D
var muzzle: Node3D           # rifle muzzle (tracers / flash)
var launch_tip: Node3D       # grenade launcher / rocket tube exit, if any
var crouched := false
var prone := false
var wounded := false         # (no limp any more: nothing walks)

var _palette: Dictionary
var _meshes: Array = []
var _arms := {}              # side -> {upper, fore}
var _rifle: Node3D
var _grip := Vector3.ZERO    # right hand (upper space)
var _left_target := Vector3.ZERO
var _guard := Vector3.ZERO   # left hand on the rifle at low ready (upper space)
var _rest_rifle := Transform3D.IDENTITY   # low ready (upper space)
var _patch: MeshInstance3D
var _sgt_parts: Array = []
var _gesture: Tween
var _gesturing := false
var _laid := false
var _root_posed := false      # lying down has moved the model node itself

var _crouch_amt := 0.0
var _prone_amt := 0.0
var _aiming := false
var _aim_amt := 0.0
var _aim_dir := Vector3.FORWARD          # model frame, smoothed
var _aim_goal := Vector3.FORWARD
var _recoil := 0.0
var _driven := false
var _demo_vel := Vector3.ZERO
var _demo_aim := false
var _demo_fire_t := 0.0


# ---------------------------------------------------------------- build

static func palette(side: String, role: String, variant: int) -> Dictionary:
	var v := absi(variant)
	var p := {}
	if side == "enemy":
		p = {"uniform": Color(0.34, 0.31, 0.22), "legs": Color(0.24, 0.22, 0.16), "helmet": Color(0.12, 0.12, 0.12),
			"skin": Color(0.62, 0.48, 0.38), "arms": Color(0.34, 0.31, 0.22), "band": Color(0.75, 0.08, 0.05)}
	else:
		var tones := [Color(0.27, 0.32, 0.24), Color(0.25, 0.3, 0.25), Color(0.29, 0.31, 0.23)]
		p = {"uniform": tones[v % 3], "legs": Color(0.2, 0.22, 0.18), "helmet": [Color(0.22, 0.26, 0.19), Color(0.2, 0.23, 0.18)][v % 2],
			"skin": [Color(0.78, 0.6, 0.47), Color(0.55, 0.4, 0.3), Color(0.68, 0.52, 0.4)][v % 3], "arms": tones[v % 3], "band": null}
		if role == "anti_armor":
			p["uniform"] = Color(0.33, 0.3, 0.22)
	p["role"] = role
	return p


## role: "rifleman" | "grenadier" | "anti_armor"; side: "friendly" | "enemy".
func build(role: String, side := "friendly", variant := 0) -> void:
	set_process(false)
	add_to_group("soldier_models")
	_palette = palette(side, role, variant)
	# Legs: two blocks, standing still.
	for sx in [-1.0, 1.0]:
		_block(self, LEG_SIZE, Vector3(HIP_X * sx, LEG_SIZE.y / 2.0, 0), _palette["legs"])
	upper = Node3D.new()
	upper.name = "Upper"
	add_child(upper)
	_block(upper, TORSO, Vector3(0, WAIST_Y + TORSO.y / 2.0, 0), _palette["uniform"])
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, NECK_Y, 0)
	upper.add_child(head)
	_block(head, Vector3(HEAD, HEAD, HEAD), Vector3(0, HEAD / 2.0, 0), _palette["skin"], SKIN)
	_block(head, Vector3(HEAD + 0.05, 0.1, HEAD + 0.05), Vector3(0, HEAD + 0.02, 0), _palette["helmet"])   # helmet
	_block(head, Vector3(HEAD + 0.05, 0.2, 0.05), Vector3(0, HEAD - 0.1, HEAD / 2.0 + 0.01), _palette["helmet"])   # ...down the back of the head
	for ex in [-0.075, 0.075]:     # eyes: which way he's facing, at a glance
		_block(head, Vector3(0.06, 0.05, 0.02), Vector3(ex, HEAD * 0.6, -HEAD / 2.0 - 0.005), Color(0.05, 0.05, 0.05), METAL)
	# Fire-team patch on the back of the helmet (hidden unless split).
	_patch = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.12, 0.08, 0.01)
	_patch.mesh = pm
	_patch.position = Vector3(0, HEAD - 0.04, HEAD / 2.0 + 0.02)
	_patch.visible = false
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(_patch)
	for s in ["L", "R"]:
		var ua := Node3D.new()
		upper.add_child(ua)
		_block(ua, Vector3(ARM_W, UPPER_ARM, ARM_W), Vector3(0, -UPPER_ARM / 2.0, 0), _palette["arms"])
		if _palette["band"] != null:     # enemy: red armband
			_block(ua, Vector3(ARM_W + 0.01, 0.07, ARM_W + 0.01), Vector3(0, -0.1, 0), _palette["band"])
		var fa := Node3D.new()
		upper.add_child(fa)
		_block(fa, Vector3(ARM_W - 0.01, FOREARM, ARM_W - 0.01), Vector3(0, -FOREARM / 2.0, 0), _palette["arms"])
		_block(fa, Vector3(ARM_W - 0.02, 0.09, ARM_W - 0.02), Vector3(0, -FOREARM + 0.02, 0), _palette["skin"], SKIN)   # hand
		_arms[s] = {"upper": ua, "fore": fa}
	_build_rifle(role)
	if role == "anti_armor":
		_build_launcher()
	_left_target = _guard
	_apply_pose()


## One coloured block, centred at `at` in `parent`'s space.
func _block(parent: Node3D, size: Vector3, at: Vector3, col: Color, mat_id := FABRIC) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box(size, col, mat_id)
	mi.position = at
	mi.material_override = _material("normal")
	mi.layers = BODY_LAYER
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


## A box mesh with its colour (and material ID) in the vertex colours, cached.
static func _box(size: Vector3, col: Color, mat_id: float) -> ArrayMesh:
	var key := "%s|%s|%.2f" % [size, col, mat_id]
	if not _box_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		var arrays := bm.get_mesh_arrays()
		var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var cols := PackedColorArray()
		cols.resize(n)
		cols.fill(Color(col.r, col.g, col.b, mat_id))
		arrays[Mesh.ARRAY_COLOR] = cols
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_box_cache[key] = m
	return _box_cache[key]


## The rifle: a black stick, held at low ready across the body.
func _build_rifle(role: String) -> void:
	_rifle = Node3D.new()
	_rifle.name = "Rifle"
	upper.add_child(_rifle)
	_block(_rifle, Vector3(0.05, 0.07, GUN_LEN), Vector3(0, 0, -GUN_LEN / 2.0 + 0.18), Color(0.05, 0.05, 0.05), METAL)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -GUN_LEN + 0.18)
	_rifle.add_child(muzzle)
	if role == "grenadier":
		_block(_rifle, Vector3(0.06, 0.06, 0.3), Vector3(0, -0.065, -0.32), Color(0.08, 0.08, 0.08), METAL)   # launcher under the barrel
		launch_tip = Node3D.new()
		launch_tip.position = Vector3(0, -0.065, -0.48)
		_rifle.add_child(launch_tip)
	var dir := Vector3(-0.55, -0.2, -1.0).normalized()
	_rest_rifle = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(0.1, 1.15, -0.25))
	_rifle.transform = _rest_rifle
	_guard = _rest_rifle * _guard_on_rifle()


## Where the hands hold the stick (rifle space).
func _grip_on_rifle() -> Vector3:
	return Vector3(0, -0.02, 0.02)


func _guard_on_rifle() -> Vector3:
	return Vector3(0, -0.02, -0.3)


## Rocket tube slung across the back; rockets leave from its top end.
func _build_launcher() -> void:
	var tube := Node3D.new()
	var d := Vector3(0.6, 0.8, 0.0).normalized()
	tube.transform = Transform3D(Basis.looking_at(d, Vector3.BACK), Vector3(0.0, 1.3, 0.24))
	upper.add_child(tube)
	_block(tube, Vector3(0.13, 0.13, 1.05), Vector3.ZERO, Color(0.3, 0.33, 0.22), METAL)
	launch_tip = Node3D.new()
	launch_tip.position = Vector3(0, 0, -0.53)
	tube.add_child(launch_tip)


# ---------------------------------------------------------------- materials

static func _material(tint: String) -> ShaderMaterial:
	var key := tint + ("_n" if Atmosphere.night else "_d")
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("ir_on", thermal)
		m.set_shader_parameter("ir_rect", thermal_rect)
		m.set_shader_parameter("night", 1.0 if Atmosphere.night else 0.0)
		m.set_shader_parameter("detail", 0.0)        # plain blocks: no camo, no fabric grain
		match tint:
			"hurt":
				m.set_shader_parameter("tint", Color(2.2, 0.5, 0.4))
			"dead":
				m.set_shader_parameter("tint", Color(0.45, 0.45, 0.45))
			_:
				m.set_shader_parameter("tint", Color(1, 1, 1))
		_mats[key] = m
	return _mats[key]


static func set_retro(on: bool, _tree: SceneTree) -> void:
	retro = on


static func set_thermal(on: bool, rect_uv: Vector4) -> void:
	thermal = on
	thermal_rect = rect_uv
	for m in _mats.values():
		m.set_shader_parameter("ir_on", on)
		m.set_shader_parameter("ir_rect", rect_uv)


static func set_low_quality(on: bool) -> void:
	low_quality = on


## "normal", "hurt" (red flash) or "dead" (darkened).
func set_tint(tint: String) -> void:
	var m := _material(tint)
	for mi in _meshes:
		mi.material_override = m


## The block meshes being drawn.
func shown_meshes() -> Array:
	return _meshes


## World height of the lowest corner of the body (rifle excluded).
func lowest_point() -> float:
	var low := INF
	for mi in _meshes:
		if mi.get_parent() == _rifle:
			continue
		var box: AABB = mi.get_aabb()
		var xf: Transform3D = mi.global_transform
		for c in 8:
			low = minf(low, (xf * box.get_endpoint(c)).y)
	return low


# ---------------------------------------------------------------- pose

## Places a bone node at `from`, its -Y axis pointing at `to`, bending toward `pole`.
static func _aim_bone(node: Node3D, from: Vector3, to: Vector3, pole: Vector3) -> void:
	var y := (from - to).normalized()
	var x := y.cross(pole).normalized()
	if x.length() < 0.01:
		x = y.cross(Vector3.FORWARD).normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y, z), from)


## Two-bone IK: returns the middle joint position (the elbow).
static func _solve(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var to := target - root
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var u := to.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var v := (pole - u * pole.dot(u)).normalized()
	return root + u * cos_a * a + v * sqrt(1.0 - cos_a * cos_a) * a


## Body (hunch, lying flat) and rifle (low ready / aimed, recoil) from the
## eased amounts; then the arms reach for it.
func _apply_pose() -> void:
	if _laid:
		return
	var pr := smoothstep(0.0, 1.0, _prone_amt)
	var c := _crouch_amt * (1.0 - pr)
	var a := smoothstep(0.0, 1.0, maxf(_aim_amt, pr))
	# Lying flat: the whole figure tips forward onto its front.
	if pr > 0.0:
		var rb := Basis(Vector3.RIGHT, -PI / 2.0 * pr)
		transform = Transform3D(rb, Vector3(0, PRONE_LIFT * pr, PRONE_BACK * pr))
		_root_posed = true
	elif _root_posed:
		transform = Transform3D.IDENTITY     # back on his feet (only ever undo what lying down did)
		_root_posed = false
	# Upper body: hunched forward when crouched, turned with the aim.
	var aim_yaw := atan2(-_aim_dir.x, -_aim_dir.z) * a * (1.0 - pr)
	var ub := Basis(Vector3.UP, aim_yaw * 0.8) * Basis(Vector3.RIGHT, -HUNCH * c)
	var waist := Vector3(0, WAIST_Y, 0)
	upper.transform = Transform3D(ub, waist - ub * waist)
	head.rotation.x = HUNCH * c * 0.6 + 1.2 * pr     # look up ahead when hunched or lying down
	# Rifle: low ready, or butt in the shoulder pointing along the aim.
	var up_frame := transform.basis * upper.basis          # upper space -> his facing frame
	var aim_b := up_frame.inverse() * Basis.looking_at(_aim_dir, Vector3.UP if absf(_aim_dir.y) < 0.95 else Vector3.BACK)
	var aimed := Transform3D(aim_b, POCKET.lerp(PRONE_POCKET, pr))
	var rx := _rest_rifle.interpolate_with(aimed, a)
	# Recoil: back into the shoulder, muzzle up.
	rx.basis = rx.basis * Basis(Vector3.RIGHT, 0.12 * _recoil)
	rx.origin += rx.basis.z * 0.05 * _recoil
	_rifle.transform = rx
	_grip = rx * _grip_on_rifle()
	_guard = rx * _guard_on_rifle()
	if not _gesturing:
		_left_target = _guard              # (a hand signal has the left hand)
	_solve_arms()


func _solve_arms() -> void:
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var sh := SHOULDER * Vector3(sx, 1, 1)
		var hand: Vector3 = _left_target if s == "L" else _grip
		# Elbows out and down standing; lying flat, out and up (off the ground).
		var pole := Vector3(0.7 * sx, -0.7, 0.35).lerp(Vector3(0.7 * sx, -0.2, 0.9), smoothstep(0.0, 1.0, _prone_amt))
		var elbow := _solve(sh, hand, UPPER_ARM, FOREARM, pole)
		_aim_bone(_arms[s]["upper"], sh, elbow, Vector3(sx, 0, 0))
		_aim_bone(_arms[s]["fore"], elbow, hand, Vector3(sx, 0, 0))


## Call every physics frame with the body's world velocity (only used to
## know he's being driven: nothing walks). Eases crouch, prone and the aim.
func animate(world_vel: Vector3, delta: float) -> void:
	animate_local(Vector3(world_vel.x, 0, world_vel.z), delta)


func animate_local(_v: Vector3, delta: float) -> void:
	_driven = true
	if _laid:
		return
	var crouch_goal := 1.0 if crouched else 0.0
	var aim_goal := 1.0 if _aiming else 0.0
	var prone_goal := 1.0 if prone else 0.0
	if _crouch_amt == crouch_goal and _aim_amt == aim_goal and not _aiming and _recoil == 0.0 \
			and _prone_amt == prone_goal and not _gesturing:
		return                                              # settled: nothing to pose
	_prone_amt = move_toward(_prone_amt, prone_goal, (1.8 if prone else 2.2) * delta)
	_aim_amt = move_toward(_aim_amt, aim_goal, (4.5 if _aiming else 2.5) * delta)
	_aim_dir = _aim_dir.lerp(_aim_goal, clampf(14.0 * delta, 0.0, 1.0)).normalized()
	_recoil = move_toward(_recoil, 0.0, 7.0 * delta)
	_crouch_amt = move_toward(_crouch_amt, crouch_goal, 5.0 * delta)
	_apply_pose()


# ---------------------------------------------------------------- pose API

## Raise the rifle to the shoulder and point it at `world_point`, or lower it
## to low ready with Vector3.INF. Call every frame while engaging.
func set_aim_point(world_point: Vector3) -> void:
	_aiming = world_point != Vector3.INF
	if not _aiming:
		_aim_goal = Vector3.FORWARD
		return
	var frame := _frame()
	var d := frame.basis.inverse() * (world_point - frame * Vector3(0.15, 1.4, -0.15))
	if d.length() < 0.1:
		return
	d = d.normalized()
	var yaw := clampf(atan2(-d.x, -d.z), -AIM_YAW, AIM_YAW)
	var pitch := clampf(asin(clampf(d.y, -1.0, 1.0)), -AIM_PITCH, AIM_PITCH)
	if prone:
		pitch = clampf(pitch, -0.15, 0.15)
	_aim_goal = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## His facing frame (the parent's): -Z ahead, Y up, whatever lying down has
## done to the model node itself.
func _frame() -> Transform3D:
	return global_transform * transform.affine_inverse()


## One shot: the stick kicks back and up.
func recoil() -> void:
	_recoil = minf(1.0, _recoil + 0.65)


func is_shouldered() -> bool:
	return _aim_amt > 0.85


## Model viewer: as if moving at `local_vel` (nothing walks, so only "driven").
func set_demo_motion(local_vel: Vector3) -> void:
	_demo_vel = local_vel
	set_process(local_vel != Vector3.ZERO or _demo_aim)


## Model viewer: shoulder the rifle at a point straight ahead and fire bursts.
func set_demo_aim(on: bool) -> void:
	_demo_aim = on
	set_process(on or _demo_vel != Vector3.ZERO)


func _process(delta: float) -> void:
	if _demo_aim:
		set_aim_point(_frame() * Vector3(0.0, 0.3 if prone else 1.35, -12.0))
		_demo_fire_t -= delta
		if _demo_fire_t <= 0.0 and _aim_amt > 0.95:
			recoil()
			_demo_fire_t = 0.1 if randf() < 0.7 else 0.9
	animate_local(_demo_vel, delta)


## Down on the ground (eased in animate()), or back up.
func set_prone(on: bool) -> void:
	if on == prone:
		return
	prone = on
	if not _driven:
		_prone_amt = 1.0 if on else 0.0
		_apply_pose()


func prone_amount() -> float:
	return _prone_amt


## Crouched: hunched forward at the waist (eased in animate()).
func set_crouch(on: bool) -> void:
	if on == crouched:
		return
	crouched = on
	if not _driven:
		_crouch_amt = 1.0 if on else 0.0
		_apply_pose()


func _set_left_hand(p: Vector3) -> void:
	_left_target = p
	_solve_arms()


## Left-hand signals: "move", "halt", "cover", "fire" (pointing `yaw_off`
## radians left/right of straight ahead).
func gesture(kind: String, yaw_off := 0.0) -> void:
	if _laid:
		return
	if _gesture:
		_gesture.kill()
	var tw := create_tween()
	_gesture = tw
	_gesturing = true
	var cur := [_left_target]
	var sh := SHOULDER * Vector3(-1, 1, 1)
	var step := func(to: Vector3, t: float) -> void:
		tw.tween_method(_set_left_hand, cur[0], to, t)
		cur[0] = to
	match kind:
		"move":     # hand up, chop forward twice
			for i in 2:
				step.call(sh + Vector3(0.0, 0.5, -0.25), 0.14)
				step.call(sh + Vector3(0.05, 0.02, -0.58), 0.16)
			tw.tween_interval(0.12)
		"halt":     # raised fist, held
			step.call(sh + Vector3(-0.05, 0.58, -0.08), 0.15)
			tw.tween_interval(0.9)
		"cover":    # arm out, palm down, pump
			step.call(sh + Vector3(-0.2, 0.0, -0.46), 0.12)
			for i in 2:
				step.call(sh + Vector3(-0.2, -0.32, -0.42), 0.15)
				step.call(sh + Vector3(-0.2, 0.0, -0.46), 0.13)
		"fire":     # point at the target
			var d := Vector3(-sin(yaw_off), 0.08, -cos(yaw_off)).normalized()
			step.call(sh + d * 0.6, 0.15)
			tw.tween_interval(0.8)
	tw.tween_method(_set_left_hand, cur[0], _guard, 0.25)
	tw.tween_callback(func() -> void:
		_gesturing = false
		_set_left_hand(_guard))


func set_team_patch(t: int, visible_on: bool) -> void:
	_patch.visible = visible_on and t >= 0
	if t >= 0:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.2, 1.0, 0.35) if t == 0 else Color(1.0, 0.7, 0.15)
		_patch.material_override = m


## Sergeant: amber stripes on both arms and a radio antenna on his back.
func set_sergeant(on: bool) -> void:
	for p in _sgt_parts:
		p.queue_free()
	_sgt_parts.clear()
	if not on:
		return
	var amber := StandardMaterial3D.new()
	amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amber.albedo_color = Color(1.0, 0.72, 0.15)
	for s in ["L", "R"]:
		var stripe := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(ARM_W + 0.012, 0.045, ARM_W + 0.012)
		stripe.mesh = bm
		stripe.material_override = amber
		stripe.position = Vector3(0, -0.06, 0)
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arms[s]["upper"].add_child(stripe)
		_sgt_parts.append(stripe)
	var ant := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.025, 0.75, 0.025)
	ant.mesh = am
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.06, 0.06)
	ant.material_override = dark
	ant.position = Vector3(-0.18, NECK_Y + 0.3, TORSO.z / 2.0 + 0.02)
	upper.add_child(ant)
	_sgt_parts.append(ant)
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.05, 0.05, 0.05)
	tip.mesh = tm
	tip.material_override = amber
	tip.position = ant.position + Vector3(0, 0.39, 0)
	upper.add_child(tip)
	_sgt_parts.append(tip)


## Dead: flat on his face (arms out) or on his back, and the rifle dropped
## beside him on the ground.
func lay_down(face_up: bool) -> void:
	if _gesture:
		_gesture.kill()
	_gesturing = false
	crouched = false
	prone = false
	_crouch_amt = 0.0
	_prone_amt = 0.0
	_aiming = false
	_aim_amt = 0.0
	_recoil = 0.0
	_aim_dir = Vector3.FORWARD
	_apply_pose()
	_laid = true
	upper.transform = Transform3D.IDENTITY
	head.rotation = Vector3(0, 0.4 if face_up else -0.3, 0)
	if face_up:
		_left_target = SHOULDER * Vector3(-1, 1, 1) + Vector3(-0.35, -0.45, -0.15)
		_grip = SHOULDER + Vector3(0.4, -0.4, -0.2)
	else:
		_left_target = SHOULDER * Vector3(-1, 1, 1) + Vector3(-0.45, 0.4, -0.1)    # arms flung out past the head
		_grip = SHOULDER + Vector3(0.5, 0.3, -0.1)
	_solve_arms()
	transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0 if face_up else -PI / 2.0), Vector3.ZERO)
	var floor_y := global_position.y - position.y
	var lowest := lowest_point()
	if lowest < INF:
		position.y += floor_y - lowest + 0.005
	# Rifle on the ground at his right side, along the body.
	var along := global_basis.y
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP).normalized() * (-1.0 if face_up else 1.0)
	var at := global_position + side * 0.55 + along * 0.8
	var b := Basis.looking_at(-along.rotated(Vector3.UP, 0.35), Vector3.UP)
	_rifle.global_transform = Transform3D(b, Vector3(at.x, floor_y + 0.04, at.z))
