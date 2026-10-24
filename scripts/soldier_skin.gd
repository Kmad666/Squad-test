extends Node3D
## The detailed soldier (assets/soldier/soldier.glb, a skinned Character
## Creator rig) worn over the procedural rig in soldier_model.gd.
##
## The procedural rig still does all the animation: gait, crouch, aim,
## recoil, prone, crawl, signals, corpses. drive() maps its pose onto this
## skeleton every frame:
##   - hips, spine (blended from hips to chest), neck and head copy the rig's
##     rotations
##   - arms and legs are re-solved with this model's own limb lengths (two-
##     bone IK, knees / elbows bending the way the rig's do): feet go where
##     the rig's feet are, hands go to the rig's hand targets scaled to his
##     shorter reach, and the rifle is shifted with the right hand so both
##     hands stay on it
## Each bone's rotation offset from "our" convention to its own axes is
## measured once from the rest pose.
##
## Colours: the model's own textures are olive (the enemy, with the flag
## patch subdued); your men get grey variants of the clothing and kit, green
## lenses; the enemy red. Tints (hurt / dead) are material variants; the
## thermal sight is a second pass that draws the heat colour inside the
## reticle only.

const SoldierModel = preload("res://scripts/soldier_model.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
const SCENE := preload("res://assets/soldier/soldier.glb")
const KIT := ["Mark_Helmet1", "Mark_Plate_1", "Mark_Gloves_1", "Mark_Pouches_1", "Mark_Boots_2", "Mark_Kitel_1", "Mark_Pants_1"]
const PALM := 0.07           # wrist (hand bone) to the middle of the grip

const IR_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform bool ir_on = false;
uniform vec4 ir_rect = vec4(0.0);
uniform float heat = 0.8;
void fragment() {
	if (!ir_on || SCREEN_UV.x < ir_rect.x || SCREEN_UV.x > ir_rect.z || SCREEN_UV.y < ir_rect.y || SCREEN_UV.y > ir_rect.w)
		discard;
	float facing = 0.75 + 0.25 * abs(dot(normalize(NORMAL), vec3(0.0, 0.0, 1.0)));
	ALBEDO = vec3(1.0, 1.0, 0.0) * heat * facing;
}
"""

static var _mats := {}       # "side/tint/surface" -> material
static var _ir_mats: Array = []
static var _with_ir: Array = []   # [material, its thermal pass]: attached only while thermal is on
static var _rest_cache := {} # calibration, the same for every instance

var model: Node3D            # the SoldierModel this skin belongs to
var skeleton: Skeleton3D
var body: MeshInstance3D
var side := "friendly"
var _b := {}                 # bone name -> index
var _cal := {}               # calibration (shared)
var _rifle_shift := Vector3.ZERO


func setup(m: Node3D, side_name: String) -> void:
	model = m
	side = side_name
	var inst: Node3D = SCENE.instantiate()
	add_child(inst)
	skeleton = inst.find_children("*", "Skeleton3D", true, false)[0]
	body = inst.find_children("*", "MeshInstance3D", true, false)[0]
	body.layers = SoldierModel.BODY_LAYER
	for i in skeleton.get_bone_count():
		_b[skeleton.get_bone_name(i)] = i
	_calibrate()
	set_tint("normal")


func bone(n: String) -> int:
	return _b["CC_Base_" + n] if _b.has("CC_Base_" + n) else -1


## A bone's rest transform in skeleton (= model) space.
func _rest(n: String) -> Transform3D:
	return skeleton.get_bone_global_rest(bone(n))


## The rig's bone convention: -Y from `from` toward `to`, X = Y x pole.
static func aim_basis(from: Vector3, to: Vector3, pole: Vector3) -> Basis:
	var y := (from - to).normalized()
	var x := y.cross(pole).normalized()
	if x.length() < 0.01:
		x = y.cross(Vector3.FORWARD).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _calibrate() -> void:
	if not _rest_cache.is_empty():
		_cal = _rest_cache
		return
	var c := {}
	var hips_ref := Transform3D(Basis.IDENTITY, Vector3(0, SoldierModel.HIP_Y - 0.02, 0))
	c["hip_off"] = hips_ref.affine_inverse() * _rest("Hip_01").origin
	c["O_hip"] = _rest("Hip_01").basis
	for n in ["Waist_033", "Spine01_034", "Spine02_035", "NeckTwist01_036", "NeckTwist02_037", "Head_038"]:
		c["O_" + n] = _rest(n).basis           # rig reference: upright, identity
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var thigh := _rest(s + "_Thigh_0" + ("3" if s == "L" else "18"))
		var calf := _rest(s + "_Calf_0" + ("4" if s == "L" else "21"))
		var foot := _rest(s + "_Foot_0" + ("5" if s == "L" else "22"))
		c[s + "_thigh_len"] = thigh.origin.distance_to(calf.origin)
		c[s + "_calf_len"] = calf.origin.distance_to(foot.origin)
		var fwd := Vector3(0, 0, -1)
		c["O_" + s + "_thigh"] = aim_basis(thigh.origin, calf.origin, fwd).inverse() * thigh.basis
		c["O_" + s + "_calf"] = aim_basis(calf.origin, foot.origin, fwd).inverse() * calf.basis
		var foot_ref := Basis(Vector3.UP, 0.08 * sx)
		c["O_" + s + "_foot"] = foot_ref.inverse() * foot.basis
		# ankle offset: the rig's standing ankle -> this model's, in foot space
		var our_ankle := Vector3(SoldierModel.HIP_X * sx * 1.15, SoldierModel.ANKLE_Y, -0.03 + (0.06 if s == "R" else -0.05))
		c[s + "_ankle_off"] = foot_ref.inverse() * (foot.origin - our_ankle)
		var ua := _rest(s + "_Upperarm_0" + ("50" if s == "L" else "74"))
		var fa := _rest(s + "_Forearm_0" + ("51" if s == "L" else "77"))
		var hd := _rest(s + "_Hand_0" + ("55" if s == "L" else "81"))
		c[s + "_upper_len"] = ua.origin.distance_to(fa.origin)
		c[s + "_fore_len"] = fa.origin.distance_to(hd.origin)
		var side_pole := Vector3(sx, 0, 0)
		c["O_" + s + "_upper"] = aim_basis(ua.origin, fa.origin, side_pole).inverse() * ua.basis
		c["O_" + s + "_fore"] = aim_basis(fa.origin, hd.origin, side_pole).inverse() * fa.basis
		c["O_" + s + "_hand"] = fa.basis.inverse() * hd.basis   # wrist straight, as at rest
	# reach: this model's shoulder-to-grip vs the rig's
	c["reach_k"] = (c["R_upper_len"] + c["R_fore_len"] + PALM) / (SoldierModel.UPPER_ARM + SoldierModel.FOREARM)
	_rest_cache = c
	_cal = c


## Global (skeleton-space) pose of every bone in the driven chain, computed
## parent first. Undriven bones keep their rest offset from their parent.
var _g := {}


func _fk(i: int) -> Transform3D:
	if _g.has(i):
		return _g[i]
	var p := skeleton.get_bone_parent(i)
	var t := skeleton.get_bone_rest(i) if p < 0 else _fk(p) * skeleton.get_bone_rest(i)
	_g[i] = t
	return t


func _pose(i: int, basis: Basis, origin: Variant = null) -> void:
	var p := skeleton.get_bone_parent(i)
	var pg := _fk(p) if p >= 0 else Transform3D.IDENTITY
	var o: Vector3 = origin if origin != null else (pg * skeleton.get_bone_rest(i).origin)
	var g := Transform3D(basis.orthonormalized(), o)
	_g[i] = g
	var local := pg.affine_inverse() * g
	skeleton.set_bone_pose_position(i, local.origin)
	skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


## Rotation that turns direction a onto direction b.
static func _turn(a: Vector3, b: Vector3) -> Basis:
	var ax := a.cross(b)
	var s := ax.length()
	if s < 1e-5:
		return Basis.IDENTITY
	return Basis(ax / s, atan2(s, a.dot(b)))


func _limb(root_i: int, mid_i: int, end_i: int, s: String, seg: Array, our_root: Vector3, our_mid: Vector3,
		target: Vector3, our_a: Node3D, our_b: Node3D, our_space: Basis, end_basis: Variant, reach := 0.0) -> void:
	# `reach`: the target is this far past the end bone along the second
	# segment (the palm past the wrist): solve to it, then pull the end back.
	var c := _cal
	var root_p: Vector3 = _fk(skeleton.get_bone_parent(root_i)) * skeleton.get_bone_rest(root_i).origin
	var la: float = c[s + seg[0]]
	var lb: float = c[s + seg[1]] + reach
	var to := target - root_p
	if to.length() > la + lb - 0.002:
		target = root_p + to.normalized() * (la + lb - 0.002)
	var pole := our_mid - (our_root + target) * 0.5
	if pole.length() < 0.01:
		pole = our_mid - our_root
	var mid := SoldierModel._solve(root_p, target, la, lb, pole)
	# the rig's bone frames, turned onto this model's (slightly different) bone directions
	var a_basis: Basis = our_space * our_a.basis
	var b_basis: Basis = our_space * our_b.basis
	var a_basis_cc := _turn(-a_basis.y, (mid - root_p).normalized()) * a_basis
	var b_basis_cc := _turn(-b_basis.y, (target - mid).normalized()) * b_basis
	_pose(root_i, a_basis_cc * c[seg[2]], root_p)
	_pose(mid_i, b_basis_cc * c[seg[3]], mid)
	var eb: Basis = end_basis if end_basis != null else _g[mid_i].basis * c[seg[4]]
	_pose(end_i, eb, mid + (target - mid).normalized() * (lb - reach))


func drive() -> void:
	if not is_visible_in_tree():
		return
	var m := model
	var c := _cal
	_g.clear()
	var hips: Transform3D = m._hips.transform
	var up: Transform3D = m.upper.transform
	var head_b: Basis = up.basis * m.head.basis
	# torso
	_pose(bone("Hip_01"), hips.basis * c["O_hip"], hips * c["hip_off"])
	_pose(bone("Waist_033"), hips.basis.slerp(up.basis, 0.25) * c["O_Waist_033"])
	_pose(bone("Spine01_034"), hips.basis.slerp(up.basis, 0.6) * c["O_Spine01_034"])
	_pose(bone("Spine02_035"), up.basis * c["O_Spine02_035"])
	_pose(bone("NeckTwist01_036"), up.basis.slerp(head_b, 0.35) * c["O_NeckTwist01_036"])
	_pose(bone("NeckTwist02_037"), up.basis.slerp(head_b, 0.7) * c["O_NeckTwist02_037"])
	_pose(bone("Head_038"), head_b * c["O_Head_038"])
	# legs: feet where the rig's feet are (this model's ankle height / offset)
	for s in ["L", "R"]:
		var lg: Dictionary = m._legs[s]
		var foot: Node3D = lg["foot"]
		var ankle: Vector3 = foot.transform * c[s + "_ankle_off"]
		var fb: Basis = foot.basis * c["O_" + s + "_foot"]
		var ids := ["Thigh_03", "Calf_04", "Foot_05"] if s == "L" else ["Thigh_018", "Calf_021", "Foot_022"]
		_limb(bone(s + "_" + ids[0]), bone(s + "_" + ids[1]), bone(s + "_" + ids[2]), s,
			["_thigh_len", "_calf_len", "O_" + s + "_thigh", "O_" + s + "_calf", ""],
			lg["thigh"].position, lg["shin"].position, ankle, lg["thigh"], lg["shin"], Basis.IDENTITY, fb)
	# arms: hand targets scaled about the shoulder to this model's reach; the
	# rifle moves with the right hand so it stays in both hands.
	var k: float = c["reach_k"]
	var shift := Vector3.ZERO
	var laid: bool = m._laid
	for s in ["R", "L"]:
		var sx := -1.0 if s == "L" else 1.0
		var ids := ["Upperarm_050", "Forearm_051", "Hand_055"] if s == "L" else ["Upperarm_074", "Forearm_077", "Hand_081"]
		var ua_i := bone(s + "_" + ids[0])
		var our_sh: Vector3 = SoldierModel.SHOULDER * Vector3(sx, 1, 1)
		var cc_sh: Vector3 = _fk(skeleton.get_bone_parent(ua_i)) * skeleton.get_bone_rest(ua_i).origin    # model space
		var cc_sh_u: Vector3 = up.affine_inverse() * cc_sh                                               # upper space
		var hand_u: Vector3 = m._grip if s == "R" else m._left_target
		var want_u: Vector3
		if s == "R":
			want_u = cc_sh_u + (hand_u - our_sh) * k
			shift = want_u - hand_u
		elif not laid and not (m._gesture and m._gesture.is_running()):
			want_u = hand_u + shift                          # left hand on the (moved) handguard
		else:
			want_u = cc_sh_u + (hand_u - our_sh) * k         # signalling / sprawled: just scaled
		# hand bone sits at the wrist, a palm's length back from the grip
		var arm: Dictionary = m._arms[s]
		var our_elbow: Vector3 = arm["fore"].position
		_limb(ua_i, bone(s + "_" + ids[1]), bone(s + "_" + ids[2]), s,
			["_upper_len", "_fore_len", "O_" + s + "_upper", "O_" + s + "_fore", "O_" + s + "_hand"],
			up * our_sh, up * our_elbow, up * want_u, arm["upper"], arm["fore"], up.basis, null, PALM)
	if not laid:
		var r: Node3D = m._rifle
		r.position += shift - _rifle_shift
		_rifle_shift = shift


## The rig rebuilt the rifle transform from scratch: no shift applied yet.
func rifle_reset() -> void:
	_rifle_shift = Vector3.ZERO


static func _material(side_name: String, tint: String, surf: int, base: Material) -> Material:
	var key := "%s/%s/%d/%s" % [side_name, tint, surf, "n" if Atmosphere.night else "d"]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = base.duplicate()
	var name: String = base.resource_name
	if name in KIT:
		var path := "res://assets/soldier/%s_%s.png" % [name, "grey" if side_name == "friendly" else "enemy"]
		m.albedo_texture = load(path)
	if name == "Mark_SunGlusses_Glus":
		var lens := Color(0.2, 0.9, 0.35) if side_name == "friendly" else Color(1.0, 0.12, 0.08)
		m.albedo_color = lens * 0.35
		m.emission_enabled = true
		m.emission = lens
		m.emission_energy_multiplier = 1.6 if Atmosphere.night else 0.25
		m.metallic = 0.6
		m.roughness = 0.08
	match tint:
		"hurt":
			m.albedo_color = m.albedo_color * Color(1.0, 0.45, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.55, 0.05, 0.02)
		"dead":
			m.albedo_color = m.albedo_color * Color(0.55, 0.55, 0.55)
			if name == "Mark_SunGlusses_Glus":
				m.emission_enabled = false
	var ir := ShaderMaterial.new()
	ir.shader = _ir_shader()
	ir.set_shader_parameter("ir_on", SoldierModel.thermal)
	ir.set_shader_parameter("ir_rect", SoldierModel.thermal_rect)
	var heat := 1.0 if name == "Mark_HeadMasked" else (0.25 if name == "Mark_SunGlusses_Glus" else 0.8)
	ir.set_shader_parameter("heat", heat * (0.45 if tint == "dead" else 1.0))
	m.next_pass = ir if SoldierModel.thermal else null    # (an unused pass would still cost a draw)
	_ir_mats.append(ir)
	_with_ir.append([m, ir])
	_mats[key] = m
	return m


static var _irs: Shader


static func _ir_shader() -> Shader:
	if _irs == null:
		_irs = Shader.new()
		_irs.code = IR_SHADER
	return _irs


static func set_thermal(on: bool, rect_uv: Vector4) -> void:
	for m in _ir_mats:
		m.set_shader_parameter("ir_on", on)
		m.set_shader_parameter("ir_rect", rect_uv)
	for pair in _with_ir:
		pair[0].next_pass = pair[1] if on else null


func set_tint(tint: String) -> void:
	for i in body.mesh.get_surface_count():
		body.set_surface_override_material(i, _material(side, tint, i, body.mesh.surface_get_material(i)))
