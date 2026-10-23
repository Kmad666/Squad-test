extends Node3D
## The universal soldier model, used by your men and the enemy alike.
## One body, colour variants; weapons and kit per role and side.
##
## A joint hierarchy driven procedurally: hips, legs (thigh / shin / foot)
## placed by two-bone IK with the feet planted; `upper` holds chest, head,
## arms and rifle; arms are solved by IK so the hands land on the rifle.
## The geometry (gas mask, high-cut helmet, plate carrier, fatigues, rifle)
## lives in soldier_parts.gd; each bone gets a close-up and a far mesh that
## swap by distance, all sharing one shader (shaders/soldier.gdshader).

const Atmosphere = preload("res://scripts/atmosphere.gd")
const Parts = preload("res://scripts/soldier_parts.gd")
const RetroParts = preload("res://scripts/soldier_parts_retro.gd")
const SHADER = preload("res://shaders/soldier.gdshader")
const RETRO_SHADER = preload("res://shaders/soldier_retro.gdshader")

## Body measurements (metres; origin between the feet).
const HIP_Y := 0.985          # hips high enough that the legs stand almost straight
const HIP_X := 0.105
const THIGH := 0.44
const SHIN := 0.43
const ANKLE_Y := 0.085
const SHOULDER := Vector3(0.205, 1.47, 0.0)
const UPPER_ARM := 0.31
const FOREARM := 0.28
const WAIST_Y := 0.99         # upper-body pivot (upper space, just above the belt)
const LEAN := 0.25            # forward lean when crouched (radians)
const RETRO_HUNCH := 0.2      # RETRO idle: hunched forward, one foot forward, one back
const BLADE := 0.6            # torso turn when shouldering (left shoulder forward)
const POCKET := Vector3(0.15, 1.46, -0.12)   # rifle butt in the shoulder (upper space)
const AIM_YAW := 0.6         # how far the rifle can swing off the body's facing
const AIM_PITCH := 0.4
# Prone: the whole body pivots forward about the hips onto the ground.
const PRONE_HIP_H := 0.17     # hip joints this high off the ground when lying flat
const PRONE_BACK := 0.3       # hips behind his origin, so the body is centred on it
const PRONE_YAW := -0.3       # body angled off the line of fire, legs out to the left rear
const PRONE_ARCH := -0.38     # chest up on the elbows
const PRONE_HEAD := 1.05      # chin up to look ahead

static var _mats := {}
static var low_quality := false
static var retro := false     # RETRO graphics: chunky low-poly soldiers (V)
const LOD_DIST := 14.0        # beyond this (metres from the camera) the far mesh shows

var upper: Node3D            # chest, head, arms, rifle (moves down when crouched)
var head: Node3D
var muzzle: Node3D           # rifle muzzle (tracers / flash)
var launch_tip: Node3D       # grenade launcher / rocket tube exit, if any
var crouched := false
var prone := false

var _palette: Dictionary
var _meshes: Array = []      # HD mesh instances, close-up and far (for tints)
var _retro_meshes: Array = []   # RETRO mesh instances
var _hips: Node3D
var _legs := {}              # side -> {thigh, shin, foot}
var _arms := {}              # side -> {upper, fore}
var _grip := Vector3.ZERO    # right hand target (upper space)
var _guard := Vector3.ZERO   # left hand target on the handguard (upper space)
var _left_target := Vector3.ZERO
var _patch: MeshInstance3D
var _sgt_parts: Array = []
var _gesture: Tween
var _rifle: Node3D
var _rifle_base := Transform3D.IDENTITY   # rifle in upper space, standing
var _guard_local := Vector3.ZERO          # left hand on the handguard, rifle space
var _grip_rest := Vector3.ZERO            # right hand on the pistol grip (upper space)
# gait / stance state (see _apply_pose)
var _crouch_amt := 0.0       # 0 standing .. 1 crouched (eased when driven)
var _gait_w := 0.0           # 0 idle .. 1 walking/running (eased)
var _speed := 0.0            # smoothed ground speed, m/s
var _phase := 0.0            # gait cycle 0..1 (left foot plants at 0)
var _move_dir := Vector3.FORWARD   # travel direction, model space
var _driven := false         # animate() is being called each frame
var _leg_yaw := 0.0          # hips and legs turned toward travel (strafing)
var _laid := false           # dead: no stance styling
var _prone_amt := 0.0        # 0 up .. 1 lying flat (eased)
var _pr := 0.0               # smoothed prone weight used by the last pose
var _root_posed := false     # the prone pose has moved the model node itself
var _foot_box: Array = []    # corners of the foot's bounding box (foot space), for ground clearance
var _demo_vel := Vector3.ZERO
# aiming (see set_aim_point / recoil)
var _aiming := false
var _aim_amt := 0.0          # 0 low ready .. 1 shouldered (eased)
var _aim_dir := Vector3.FORWARD        # where the rifle points, model space (smoothed)
var _aim_goal := Vector3.FORWARD
var _recoil := 0.0           # 0..1, kicks on each shot, settles fast
var _demo_aim := false
var _demo_fire_t := 0.0


## role: "rifleman" | "grenadier" | "anti_armor"; side: "friendly" | "enemy".
## `variant` mixes kit tones per man.
func build(role: String, side := "friendly", variant := 0) -> void:
	set_process(false)
	add_to_group("soldier_models")
	_palette = Parts.palette(side, role, variant)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0, HIP_Y, 0)
	add_child(_hips)
	_attach(_hips, "hips")
	upper = Node3D.new()
	upper.name = "Upper"
	add_child(upper)
	_attach(upper, "torso")
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.645, 0)
	upper.add_child(head)
	_attach(head, "head")
	# Fire-team patch on the top-back of the helmet (hidden unless split).
	_patch = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.07, 0.045, 0.006)
	_patch.mesh = pm
	_patch.position = Vector3(0, 0.195, 0.112)
	_patch.rotation.x = -0.95
	_patch.visible = false
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(_patch)
	_build_rifle(role)
	for s in ["L", "R"]:
		var ua := Node3D.new()
		upper.add_child(ua)
		_attach(ua, "upper_arm", s)
		var fa := Node3D.new()
		upper.add_child(fa)
		_attach(fa, "forearm", s)
		_arms[s] = {"upper": ua, "fore": fa}
	if role == "anti_armor":
		_build_launcher()
	for s in ["L", "R"]:
		var thigh := Node3D.new()
		add_child(thigh)
		_attach(thigh, "thigh", s)
		var shin := Node3D.new()
		add_child(shin)
		_attach(shin, "shin", s)
		var foot := Node3D.new()
		add_child(foot)
		_attach(foot, "foot")
		_legs[s] = {"thigh": thigh, "shin": shin, "foot": foot}
		if _foot_box.is_empty():
			var box := AABB()
			for mi in foot.get_children():
				if mi is MeshInstance3D:
					box = mi.get_aabb() if box.size == Vector3.ZERO else box.merge(mi.get_aabb())
			for c in 8:
				_foot_box.append(box.get_endpoint(c))
	_solve_legs()
	_left_target = _guard
	_solve_arms()


## Hangs the close-up, far and retro meshes of one part on a bone node.
func _attach(node: Node3D, part: String, extra := "") -> void:
	var rm := MeshInstance3D.new()
	rm.mesh = RetroParts.get_mesh(part, _palette, extra)
	rm.material_override = _retro_material("normal")
	rm.visible = retro
	node.add_child(rm)
	_retro_meshes.append(rm)
	for lod in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = Parts.get_mesh(part, _palette, lod, extra)
		mi.material_override = _material("normal")
		var d := 4.0 if low_quality else LOD_DIST
		if lod == 0:
			mi.visibility_range_end = d
			mi.visibility_range_end_margin = 1.0
		else:
			mi.visibility_range_begin = d
			mi.visibility_range_begin_margin = 1.0
		mi.visible = not retro
		node.add_child(mi)
		_meshes.append(mi)


static func _material(tint: String) -> ShaderMaterial:
	var key := tint + ("_n" if Atmosphere.night else "_d")
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("night", 1.0 if Atmosphere.night else 0.0)
		m.set_shader_parameter("detail", 0.0 if low_quality else 1.0)
		match tint:
			"hurt":
				m.set_shader_parameter("tint", Color(2.2, 0.5, 0.4))
			"dead":
				m.set_shader_parameter("tint", Color(0.45, 0.45, 0.45))
			_:
				m.set_shader_parameter("tint", Color(1, 1, 1))
		_mats[key] = m
	return _mats[key]


static func _retro_material(tint: String) -> ShaderMaterial:
	var key := "retro_" + tint + ("_n" if Atmosphere.night else "_d")
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = RETRO_SHADER
		m.set_shader_parameter("night", 1.0 if Atmosphere.night else 0.0)
		match tint:
			"hurt":
				m.set_shader_parameter("tint", Color(2.2, 0.5, 0.4))
			"dead":
				m.set_shader_parameter("tint", Color(0.45, 0.45, 0.45))
			_:
				m.set_shader_parameter("tint", Color(1, 1, 1))
		_mats[key] = m
	return _mats[key]


## RETRO graphics on / off for every soldier in the scene.
static func set_retro(on: bool, tree: SceneTree) -> void:
	retro = on
	for m in tree.get_nodes_in_group("soldier_models"):
		m._show_retro(on)


func _show_retro(on: bool) -> void:
	for mi in _meshes:
		mi.visible = not on
	for mi in _retro_meshes:
		mi.visible = on


## World height of the lowest vertex of the drawn body (rifle excluded).
func lowest_point() -> float:
	var low := INF
	for mi in shown_meshes():
		if mi.get_parent() == _rifle or mi.mesh.get_surface_count() == 0:
			continue
		var xf: Transform3D = mi.global_transform
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			low = minf(low, (xf * v).y)
	return low


## The mesh instances currently drawn (HD or retro).
func shown_meshes() -> Array:
	return _retro_meshes if retro else _meshes


## Low graphics: no camo noise / fabric bump, and the far mesh from 4 m.
static var _rest_cache := {}


## A thinned set of a mesh's vertices (every few), cached per mesh.
static func _rest_points(mesh: Mesh) -> PackedVector3Array:
	if not _rest_cache.has(mesh):
		var out := PackedVector3Array()
		if mesh.get_surface_count() > 0:
			var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, v.size() / 120)
			for i in range(0, v.size(), step):
				out.append(v[i])
		_rest_cache[mesh] = out
	return _rest_cache[mesh]


static func set_low_quality(on: bool) -> void:
	low_quality = on
	for m in _mats.values():
		m.set_shader_parameter("detail", 0.0 if on else 1.0)


## "normal", "hurt" (red flash) or "dead" (darkened).
func set_tint(tint: String) -> void:
	var m := _material(tint)
	for mi in _meshes:
		mi.material_override = m
	var rm := _retro_material(tint)
	for mi in _retro_meshes:
		mi.material_override = rm


## Rifle at low ready across the body: M4-pattern carbine for your men (the
## grenadier's with an underbarrel launcher and magnified optic, the
## rocketman's shorter), AK-pattern for the enemy.
func _build_rifle(role: String) -> void:
	var rifle := Node3D.new()
	rifle.name = "Rifle"
	# Low ready, close enough to the body that the left hand really reaches
	# the handguard (model_test checks both hands land on the rifle).
	_grip = Vector3(0.13, 1.16, -0.15)
	_grip_rest = _grip
	var dir := Vector3(-0.38, -0.16, -1.0).normalized()
	rifle.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), _grip)
	upper.add_child(rifle)
	_rifle = rifle
	_rifle_base = rifle.transform
	_attach(rifle, "rifle")
	muzzle = Node3D.new()
	muzzle.position = Parts.muzzle_pos(_palette)
	rifle.add_child(muzzle)
	if role == "grenadier":
		launch_tip = Node3D.new()
		launch_tip.position = Vector3(0, -0.012, -0.48)
		rifle.add_child(launch_tip)
	_guard_local = Vector3(-0.022, -0.025, -0.27)      # under / left side of the handguard
	_guard = rifle.transform * _guard_local


## Recoilless rifle slung diagonally across the back of the pack, the muzzle
## end up over the right shoulder (rockets leave from there), on a sling
## over the left shoulder.
func _build_launcher() -> void:
	var tube := Node3D.new()
	var d := Vector3(0.64, 0.77, 0.0).normalized()
	tube.transform = Transform3D(Basis.looking_at(d, Vector3.BACK), Vector3(0.02, 1.38, 0.43))
	upper.add_child(tube)
	_attach(tube, "launcher")
	_attach(upper, "sling")
	launch_tip = Node3D.new()
	launch_tip.position = Vector3(0, 0, -0.62)
	tube.add_child(launch_tip)


# ---------------------------------------------------------------- IK

## Places a bone node at `from`, its -Y axis pointing at `to`, bending toward `pole`.
static func _aim_bone(node: Node3D, from: Vector3, to: Vector3, pole: Vector3) -> void:
	var y := (from - to).normalized()
	var x := y.cross(pole).normalized()
	if x.length() < 0.01:
		x = y.cross(Vector3.FORWARD).normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y, z), from)


## Two-bone IK: returns the middle joint position (knee / elbow).
static func _solve(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var to := target - root
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var u := to.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var v := (pole - u * pole.dot(u)).normalized()
	return root + u * cos_a * a + v * sqrt(1.0 - cos_a * cos_a) * a


func _solve_legs() -> void:
	_apply_pose()


## Poses hips, legs, torso and rifle from the current stance (crouch amount)
## and gait (phase, speed, travel direction, blend weight).
##
## Gait: each foot alternates stance (planted, sliding back under the body as
## he moves) and swing (lifted and carried forward). Feet step along the
## direction of travel in model space, so strafing and backing up step
## sideways / backwards. Running: shorter stance, higher knees, lower hips,
## forward lean. Crouch-walk: short low steps. Hands stay on the rifle; the
## torso twists a little against the hips instead of swinging arms.
func _apply_pose() -> void:
	var pr := smoothstep(0.0, 1.0, _prone_amt)
	_pr = pr
	var c := _crouch_amt * (1.0 - pr)
	var w := _gait_w * (1.0 - pr)         # walking / running
	var cw := _gait_w * pr                # crawling
	var run_t := clampf((_speed - 2.6) / 2.4, 0.0, 1.0) * (1.0 - c)
	var stance := lerpf(lerpf(0.62, 0.34, run_t), 0.62, c)
	var fwd := clampf(-_move_dir.z, 0.0, 1.0)
	var bob := w * lerpf(0.022, -0.04, run_t) * cos(TAU * 2.0 * (_phase - stance * 0.5))
	var st := (1.0 if retro and not _laid else 0.0) * (1.0 - c) * (1.0 - pr)   # retro guard stance weight
	var hip_drop := lerpf(0.02, 0.33, c) + 0.06 * run_t * w + 0.045 * st
	var hip_back := 0.08 * c
	_hips.position = Vector3(0, HIP_Y - hip_drop + bob, hip_back)
	# Prone, the rifle is always up and pointed ahead.
	var a := smoothstep(0.0, 1.0, maxf(_aim_amt, _prone_amt))
	var twist := w * (0.07 + 0.05 * run_t) * sin(TAU * _phase) * (0.3 + 0.7 * fwd) * (1.0 - 0.6 * a)
	# Shouldered: bladed stance (left shoulder forward), and the torso turns
	# with the aim so the arms keep the same reach wherever he points.
	var aim_yaw := atan2(-_aim_dir.x, -_aim_dir.z) * a
	twist += -BLADE * a + 0.8 * aim_yaw
	var leg_yaw := _leg_yaw * w
	var ly := Basis(Vector3.UP, leg_yaw)
	_hips.rotation.y = (leg_yaw * 0.85 - twist * 0.6 - 0.25 * a * (1.0 - w)) * (1.0 - pr)
	# Crawling: the shoulders roll with each stroke.
	twist = twist * (1.0 - pr) + 0.12 * cw * sin(TAU * _phase)
	# Prone: the whole model pivots forward about the hips and comes down
	# until the hips are just off the ground, body angled off the line of fire.
	# Aiming off to one side, a prone man shifts his whole body round.
	var root_b := Basis(Vector3.UP, (PRONE_YAW + 0.85 * aim_yaw) * pr) * Basis(Vector3.RIGHT, -PI / 2.0 * pr)
	if pr > 0.0:
		var hip_at := Vector3(0, lerpf(_hips.position.y, PRONE_HIP_H, pr), PRONE_BACK * pr)
		transform = Transform3D(root_b, hip_at - root_b * _hips.position)
		_root_posed = true
	elif _root_posed:
		transform = Transform3D.IDENTITY
		_root_posed = false
	# The upper body was laid out for hips at 0.93 m: keep it on the hips, and
	# lean it forward by pivoting at the waist (not at the feet, which would
	# swing the torso off the hips). Prone: arched back, chest up on the elbows.
	var lean := (LEAN * c + 0.28 * run_t * w * (0.4 + 0.6 * fwd) + 0.06 * a + RETRO_HUNCH * st * (1.0 - 0.4 * w)) * (1.0 - pr) \
			+ PRONE_ARCH * pr - 0.05 * _recoil
	var waist := Vector3(0, WAIST_Y, 0)
	var on_hips := Vector3(0, HIP_Y - 0.93 - hip_drop + bob, hip_back)
	var rot := Basis(Vector3.UP, twist) * Basis(Vector3.RIGHT, -lean)
	upper.transform = Transform3D(rot, on_hips + waist - rot * waist)
	# Head: eyes stay up and ahead; shouldered, cheek down onto the stock.
	head.rotation = Vector3((lean * 0.7 + 0.14 * a) * (1.0 - pr) + PRONE_HEAD * pr, (aim_yaw - twist) * 0.9 * (1.0 - pr), -0.1 * a * (1.0 - pr))
	# Low ready: counter-rotate the rifle about the grip so the muzzle stays
	# up instead of pointing into the ground when he leans.
	var counter := Transform3D(Basis(Vector3.RIGHT, lean * 0.8), Vector3.ZERO)
	var low := Transform3D(Basis.IDENTITY, _grip_rest) * counter * Transform3D(Basis.IDENTITY, -_grip_rest) * _rifle_base
	var xf := low
	if a > 0.0:
		# Shouldered: butt in the shoulder pocket, barrel along the aim line
		# (worked out in upper space, so it stays on target through the
		# blade, lean, gait twist and bob). Recoil kicks the muzzle up and
		# the rifle back into the shoulder.
		# (_aim_dir is in his facing frame; prone, the body is turned off it)
		var to_upper := upper.basis.inverse() * root_b.inverse()
		var d := (to_upper * _aim_dir).normalized()
		var up := (to_upper * Vector3.UP).normalized()
		if _recoil > 0.0:
			var axis := d.cross(up)
			if axis.length() > 0.01:
				d = d.rotated(axis.normalized(), 0.09 * _recoil)
		var pocket := POCKET + Vector3(0.03 * pr, 0, 0) - d * 0.035 * _recoil
		var aim_xf := Transform3D(Basis.looking_at(d, up), pocket + d * 0.31)
		xf = Transform3D(low.basis.slerp(aim_xf.basis, a), low.origin.lerp(aim_xf.origin, a))
	_rifle.transform = xf
	_grip = xf.origin
	var gl := _guard_local
	gl.z = lerpf(_guard_local.z, -0.22, a)                # hand slides back a little when shouldered
	_guard = xf * gl
	if not (_gesture and _gesture.is_running()):
		_left_target = _guard

	var cycle := _cycle_length()
	var reach := minf(cycle * stance * 0.5, lerpf(0.45, 0.28, c))
	var lift := lerpf(0.1, 0.2, run_t) * lerpf(1.0, 0.6, c)
	# Steps are laid out in leg space (hips turned toward travel), so a
	# strafe becomes a diagonal run with the torso twisted to keep facing.
	var dir := Basis(Vector3.UP, -leg_yaw) * _move_dir
	var lat := absf(dir.x)
	reach *= 1.0 - 0.45 * lat
	var kick := 0.24 * run_t
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var hip := _hips.position + ly * Vector3(HIP_X * sx, -0.04, 0)
		# Standing (or crouched) rest position.
		var rest := Vector3(HIP_X * sx * 1.15, ANKLE_Y, -0.03 + (0.06 if s == "R" else -0.05))
		if s == "R":
			rest.z += 0.2 * c + 0.13 * a * (1.0 - c) * (1.0 - st) + 0.17 * st   # one foot back when low / shooting / retro guard
			rest.x += 0.04 * a + 0.03 * st
		else:
			rest.z -= 0.05 * a * (1.0 - c) * (1.0 - st) + 0.13 * st
			rest.x -= 0.02 * st
		var pitch := 0.0
		var ankle := rest
		if w > 0.0:
			var p := fposmod(_phase + (0.5 if s == "R" else 0.0), 1.0)
			var off := 0.0
			var h := 0.0
			if p < stance:                                  # planted, sliding back
				var t := p / stance
				off = reach * (1.0 - 2.0 * t)
				pitch = lerpf(0.15, -0.3, t)
			else:                                           # lifted, carried forward
				var t := (p - stance) / (1.0 - stance)
				off = -reach + 2.0 * reach * smoothstep(0.0, 1.0, t)
				# running: the heel kicks up behind first, then the knee drives through
				h = lift * sin(PI * t) + kick * sin(PI * clampf(t / 0.6, 0.0, 1.0))
				pitch = lerpf(-0.55, 0.2, t) - kick * 2.5 * sin(PI * clampf(t / 0.6, 0.0, 1.0))
			var local := Vector3(HIP_X * sx * (1.1 + 0.6 * lat), 0, 0) + dir * off
			local.x = maxf(local.x, 0.085) if s == "R" else minf(local.x, -0.085)   # never cross the feet
			var gait := Vector3(_hips.position.x, ANKLE_Y + h, _hips.position.z * 0.5) + ly * local
			ankle = rest.lerp(gait, w)
			pitch *= w
			# Keep the sole on or above the ground however the foot is pitched:
			# the heel rises at toe-off instead of the toes digging in.
			# (sole corners: toe 0.185 m ahead of the ankle, heel 0.085 behind,
			# 0.0875 below; pitch > 0 lifts the toes)
			var toe := -0.0875 * cos(pitch) + 0.185 * sin(pitch)
			var heel := -0.0875 * cos(pitch) - 0.085 * sin(pitch)
			ankle.y = maxf(ankle.y, -minf(toe, heel) + 0.002)
		var knee_pole := ly * Vector3(0.1 * sx, 0, -1)
		var bone_pole := ly * Vector3(0, 0, -1)
		var foot_yaw := leg_yaw + 0.08 * sx
		if pr > 0.0:
			# Prone: legs straight back and apart, toes pointed (tops of the
			# feet on the ground). Crawling: each knee in turn is drawn up and
			# out to the side along the ground, then pushes back.
			var u := cw * (0.5 - 0.5 * cos(TAU * fposmod(_phase + (0.5 if s == "R" else 0.0), 1.0)))
			var flat := Vector3(sx * (0.2 + 0.2 * u), hip.y - 0.83 + 0.42 * u, -PRONE_HIP_H + 0.075 + 0.03 * u)
			ankle = ankle.lerp(flat, pr)
			pitch = lerpf(pitch, -1.25, pr)
			var side := Vector3(sx, 0, -0.35 + 0.4 * u)      # drawn-up knee goes out flat, not down
			knee_pole = knee_pole.lerp(side, pr)
			bone_pole = bone_pole.lerp(side, pr)
			foot_yaw += 0.3 * sx * pr
			# Never into the ground: lift the ankle until the whole foot clears
			# it at the angle it's at (on the way down that means kneeling on
			# tucked toes before the legs go back).
			var fb := root_b * Basis(Vector3.UP, foot_yaw) * Basis(Vector3.RIGHT, pitch)
			var under := 0.0
			for corner in _foot_box:
				under = minf(under, (fb * corner).y)
			var aw := transform * ankle
			if aw.y < 0.005 - under:
				aw.y = 0.005 - under
				ankle = transform.affine_inverse() * aw
		# Never ask a leg to reach further than it can.
		var to := ankle - hip
		var max_len := THIGH + SHIN - 0.015
		if to.length() > max_len:
			ankle = hip + to.normalized() * max_len
		var knee := _solve(hip, ankle, THIGH, SHIN, knee_pole)
		_aim_bone(_legs[s]["thigh"], hip, knee, bone_pole)
		_aim_bone(_legs[s]["shin"], knee, ankle, bone_pole)
		_legs[s]["foot"].transform = Transform3D(Basis(Vector3.UP, foot_yaw) * Basis(Vector3.RIGHT, pitch), ankle)


## Eases unit vector `from` toward `to`. (Vector3.slerp loses precision and
## errors when the two are almost parallel, which is most frames.)
static func _blend_dir(from: Vector3, to: Vector3, t: float) -> Vector3:
	var v := from.lerp(to, t)
	if v.length_squared() < 1e-6:
		return to
	return v.normalized()


## Metres travelled per full gait cycle (two steps): longer strides when fast.
func _cycle_length() -> float:
	return lerpf(lerpf(0.9 + 0.38 * _speed, 0.7 + 0.35 * _speed, _crouch_amt), 0.6, smoothstep(0.0, 1.0, _prone_amt))


## Call every physics frame with the body's actual world velocity. Advances
## the gait, eases into / out of walking, and eases crouch transitions.
func animate(world_vel: Vector3, delta: float) -> void:
	var v := _frame().basis.inverse() * Vector3(world_vel.x, 0, world_vel.z)
	v.y = 0.0
	animate_local(v, delta)


## Same, with the velocity already in model space (-Z = facing).
func animate_local(v: Vector3, delta: float) -> void:
	_driven = true
	var spd := v.length()
	var crouch_goal := 1.0 if crouched else 0.0
	var aim_goal := 1.0 if _aiming else 0.0
	var prone_goal := 1.0 if prone else 0.0
	if spd < 0.05 and _speed < 0.02 and _gait_w == 0.0 and _crouch_amt == crouch_goal \
			and _aim_amt == aim_goal and not _aiming and _recoil == 0.0 and _prone_amt == prone_goal:
		return                                              # settled: nothing to pose
	_prone_amt = move_toward(_prone_amt, prone_goal, (1.8 if prone else 2.2) * delta)
	_aim_amt = move_toward(_aim_amt, aim_goal, (4.5 if _aiming else 2.5) * delta)
	_aim_dir = _blend_dir(_aim_dir, _aim_goal, clampf(14.0 * delta, 0.0, 1.0))
	_recoil = move_toward(_recoil, 0.0, 7.0 * delta)
	_speed = lerpf(_speed, spd, clampf(10.0 * delta, 0.0, 1.0))
	if spd > 0.15:
		_move_dir = _blend_dir(_move_dir, v / spd, clampf(10.0 * delta, 0.0, 1.0))
	_gait_w = move_toward(_gait_w, 1.0 if _speed > 0.35 else 0.0, 4.0 * delta)
	_crouch_amt = move_toward(_crouch_amt, crouch_goal, 5.0 * delta)
	_phase = fposmod(_phase + _speed * delta / _cycle_length(), 1.0)
	# Turn the hips toward travel (mirrored when backing up), up to ~70 deg.
	var ang := atan2(-_move_dir.x, -_move_dir.z)
	if absf(ang) > PI / 2.0:
		ang -= PI * signf(ang)
	var yaw_goal := clampf(ang * 0.85, -1.2, 1.2) if _speed > 0.35 else 0.0
	_leg_yaw = move_toward(_leg_yaw, yaw_goal, 5.0 * delta)
	if _gait_w == 0.0:
		_speed = 0.0 if spd < 0.05 and _speed < 0.05 else _speed
	_apply_pose()
	_solve_arms()


func _solve_arms() -> void:
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var sh := SHOULDER * Vector3(sx, 1, 1)
		var hand: Vector3 = _left_target if s == "L" else _grip
		# Prone: elbows down on the ground; crawling, they take turns forward.
		var pole := Vector3(0.7 * sx, -0.7, 0.35).lerp(Vector3(0.8 * sx, -0.2 + 0.5 * _gait_w * sin(TAU * _phase) * sx, -0.6), _pr)
		var elbow := _solve(sh, hand, UPPER_ARM, FOREARM, pole)
		_aim_bone(_arms[s]["upper"], sh, elbow, Vector3(sx, 0, 0))
		_aim_bone(_arms[s]["fore"], elbow, hand, Vector3(sx, 0, 0))


# ---------------------------------------------------------------- pose API

## Raise the rifle to the shoulder and point it at `world_point`, or lower it
## to low ready with Vector3.INF. Call every frame while engaging; the raise
## and lower are eased in animate(). The aim swings at most a little off the
## body's facing (the body itself turns toward the target).
func set_aim_point(world_point: Vector3) -> void:
	_aiming = world_point != Vector3.INF
	if not _aiming:
		_aim_goal = Vector3.FORWARD
		return
	var frame := _frame()
	var pocket_w: Vector3 = upper.global_transform * POCKET if _pr > 0.0 else frame * Vector3(0.12, 1.42, -0.12)
	var d := frame.basis.inverse() * (world_point - pocket_w)
	if d.length() < 0.1:
		return
	d = d.normalized()
	var yaw := clampf(atan2(-d.x, -d.z), -AIM_YAW, AIM_YAW)
	var pitch := clampf(asin(clampf(d.y, -1.0, 1.0)), -AIM_PITCH, AIM_PITCH)
	_aim_goal = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## One shot: the muzzle kicks up and the rifle rocks back into the shoulder.
## His facing frame (the parent's): -Z ahead, Y up, whatever the prone pose
## has done to the model node itself.
func _frame() -> Transform3D:
	return global_transform * transform.affine_inverse()


func recoil() -> void:
	_recoil = minf(1.0, _recoil + 0.65)


func is_shouldered() -> bool:
	return _aim_amt > 0.85


## Model viewer: animate in place as if moving at `local_vel` (model space).
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
		_solve_arms()


func prone_amount() -> float:
	return _prone_amt


func set_crouch(on: bool) -> void:
	if on == crouched:
		return
	crouched = on
	if not _driven:          # static model (viewer): snap; driven ones ease in animate()
		_crouch_amt = 1.0 if on else 0.0
		_solve_legs()
		_solve_arms()


func _set_left_hand(p: Vector3) -> void:
	_left_target = p
	_solve_arms()


## Left-hand signals: "move", "halt", "cover", "fire" (pointing `yaw_off`
## radians left/right of straight ahead).
func gesture(kind: String, yaw_off := 0.0) -> void:
	if _gesture:
		_gesture.kill()
	var tw := create_tween()
	_gesture = tw
	var cur := [_left_target]      # array so the lambda can update it
	var sh := SHOULDER * Vector3(-1, 1, 1)
	var step := func(to: Vector3, t: float) -> void:
		tw.tween_method(_set_left_hand, cur[0], to, t)
		cur[0] = to
	match kind:
		"move":     # hand up, chop forward twice
			for i in 2:
				step.call(sh + Vector3(0.0, 0.42, -0.25), 0.14)
				step.call(sh + Vector3(0.05, 0.02, -0.52), 0.16)
			tw.tween_interval(0.12)
		"halt":     # raised fist, held
			step.call(sh + Vector3(-0.05, 0.5, -0.08), 0.15)
			tw.tween_interval(0.9)
		"cover":    # arm out, palm down, pump
			step.call(sh + Vector3(-0.2, 0.0, -0.4), 0.12)
			for i in 2:
				step.call(sh + Vector3(-0.2, -0.3, -0.38), 0.15)
				step.call(sh + Vector3(-0.2, 0.0, -0.4), 0.13)
		"fire":     # point at the target
			var d := Vector3(-sin(yaw_off), 0.08, -cos(yaw_off)).normalized()
			step.call(sh + d * 0.56, 0.15)
			tw.tween_interval(0.8)
	step.call(_guard, 0.25)
	tw.tween_callback(func() -> void: _set_left_hand(_guard))   # in case he crouched meanwhile


func set_team_patch(t: int, visible_on: bool) -> void:
	_patch.visible = visible_on and t >= 0
	if t >= 0:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.2, 1.0, 0.35) if t == 0 else Color(1.0, 0.7, 0.15)
		_patch.material_override = m


## Sergeant: amber chevrons on both sleeves and a radio antenna on the pack.
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
		var ua: Node3D = _arms[s]["upper"]
		for i in 2:
			var ch := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.055, 0.011, 0.006)
			ch.mesh = bm
			ch.material_override = amber
			ch.position = Vector3(0, -0.015 - i * 0.024, 0.07)     # outer sleeve (+Z)
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ua.add_child(ch)
			_sgt_parts.append(ch)
	var ant := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.004
	cm.bottom_radius = 0.008
	cm.height = 0.8
	cm.radial_segments = 6
	ant.mesh = cm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.08)
	ant.material_override = dark
	ant.position = Vector3(-0.185, 1.82, 0.2)       # whip antenna from the radio pouch
	ant.rotation.x = 0.15
	upper.add_child(ant)
	_sgt_parts.append(ant)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	tip.mesh = sm
	tip.material_override = amber
	tip.position = Vector3(-0.185, 2.215, 0.26)
	upper.add_child(tip)
	_sgt_parts.append(tip)


## Dead. `face_up` false: sprawled on his front, arms out. `face_up` true:
## fallen backwards and rolled onto his side (the pack won't let a body lie
## flat on its back), arms in front. Feet go slack and the rifle drops flat on
## the ground beside him. He bends at the waist until upper body and legs both
## rest on the ground, then is lowered so nothing sinks or floats.
func lay_down(face_up: bool) -> void:
	if _gesture:
		_gesture.kill()
	_laid = true
	crouched = false
	_crouch_amt = 0.0
	prone = false
	_prone_amt = 0.0
	if _root_posed:
		transform = Transform3D.IDENTITY
		_root_posed = false
	_gait_w = 0.0
	_leg_yaw = 0.0
	_aiming = false
	_aim_amt = 0.0
	_recoil = 0.0
	_apply_pose()
	if face_up:
		_left_target = Vector3(-0.1, 1.12, -0.36)
		_grip = Vector3(0.08, 1.0, -0.34)
	else:
		_left_target = Vector3(-0.42, 1.05, -0.05)
		_grip = Vector3(0.42, 1.05, -0.05)
	_solve_arms()
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var foot: Node3D = _legs[s]["foot"]
		if face_up:       # heels down, toes falling outward
			foot.basis = Basis(Vector3.UP, -0.8 * sx) * Basis(Vector3.RIGHT, -0.35)
		else:             # toes pointed, soles up
			foot.basis = Basis(Vector3.UP, 0.1 * sx) * Basis(Vector3.RIGHT, -1.3)
	# Lay him flat (legs along the ground), then bend at the waist until his
	# upper body (chest kit face down, pack face up) rests on the ground too.
	# Resting points are the corners of every body part's box.
	rotation = Vector3.ZERO
	var inv := global_transform.affine_inverse()
	var inv_u := upper.global_transform.affine_inverse()
	var pts_u := PackedVector3Array()   # upper space
	var pts_l := PackedVector3Array()   # model space
	# Resting points: real (thinned) vertices of the shown body, using the
	# light far mesh for HD. Bounding-box corners would invent points that
	# aren't on the body (full shoulder width and full pack depth at once).
	var rest_meshes: Array = _retro_meshes if retro else _meshes.filter(func(m): return m.visibility_range_begin > 0.0)
	for mi in rest_meshes:
		if mi.get_parent() == _rifle:
			continue
		var is_upper: bool = upper.is_ancestor_of(mi)
		var xf: Transform3D = (inv_u if is_upper else inv) * mi.global_transform
		for v in _rest_points(mi.mesh):
			if is_upper:
				pts_u.append(xf * v)
			else:
				pts_l.append(xf * v)
	var r := Basis(Vector3.RIGHT, -PI / 2.0)
	if face_up:
		r = Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, 1.3)    # on his back, rolled onto his side
	var ll := INF
	for p in pts_l:
		ll = minf(ll, (r * p).y)
	var on_hips := upper.position - (Vector3(0, WAIST_Y, 0) - upper.basis * Vector3(0, WAIST_Y, 0))
	var waist := Vector3(0, WAIST_Y, 0)
	var best_w := 0.0
	var best_err := INF
	var best_lu := ll
	for k in 51:
		var w := -0.6 + 0.024 * k
		var bend := Basis(Vector3.RIGHT, w)
		var uxf := Transform3D(bend, on_hips + waist - bend * waist)
		var lu := INF
		for p in pts_u:
			lu = minf(lu, (r * (uxf * p)).y)
		# upper body may rest on the ground, never sink below the legs
		var err := absf(lu - ll) + absf(w) * 0.02
		if err < best_err:
			best_err = err
			best_w = w
			best_lu = lu
	var bend := Basis(Vector3.RIGHT, best_w)
	upper.transform = Transform3D(bend, on_hips + waist - bend * waist)
	head.rotation.x = -0.35 if face_up else 0.25      # head lolls back / turned down
	basis = r
	position.y = 0.0
	# Final contact from every vertex actually drawn (exact, one pass).
	var floor_y := global_position.y
	var lowest := lowest_point()
	if lowest < INF:
		position.y = floor_y - lowest
	# Rifle flat on the ground at his right side, along the body.
	var along := global_basis.y
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP).normalized() * (-1.0 if face_up else 1.0)
	var ground := global_position.y - position.y
	var at := global_position + side * 0.5 + along * 0.9
	var b := Basis.looking_at(-along.rotated(Vector3.UP, 0.35), Vector3.UP)
	b = b * Basis(Vector3.BACK, PI / 2.0)       # lying on its side
	_rifle.global_transform = Transform3D(b, Vector3(at.x, ground + 0.03, at.z))
