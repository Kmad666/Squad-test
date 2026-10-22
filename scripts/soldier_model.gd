extends Node3D
## The universal soldier model, used by your men and the enemy alike.
## One body, colour variants; weapons and kit per role.
##
## Built as a joint hierarchy so it can be animated later:
##   hips, legs (thigh / shin / foot) placed by two-bone IK with the feet
##   planted; `upper` holds chest, head, arms and rifle; arms are solved by IK
##   so the hands land on the rifle's grip and handguard.
## Every body segment is merged into ONE mesh with the colours baked into
## vertex colours, so the whole soldier is ~15 draw calls.
##
## Pose for now: idle (relaxed stance, rifle at low ready). Crouch lowers the
## hips and re-solves the legs. The left hand can leave the rifle for signals.

const Atmosphere = preload("res://scripts/atmosphere.gd")

## Colour variants.
const FRIENDLY := {
	"uniform": Color(0.33, 0.37, 0.23), "vest": Color(0.24, 0.27, 0.17), "gear": Color(0.21, 0.23, 0.16),
	"helmet": Color(0.27, 0.30, 0.20), "boots": Color(0.13, 0.11, 0.08), "gloves": Color(0.15, 0.15, 0.12),
}
const ANTI_ARMOR := {
	"uniform": Color(0.50, 0.45, 0.32), "vest": Color(0.44, 0.37, 0.25), "gear": Color(0.38, 0.32, 0.22),
	"helmet": Color(0.46, 0.41, 0.29), "boots": Color(0.20, 0.16, 0.11), "gloves": Color(0.30, 0.26, 0.19),
}
const ENEMY := {
	"uniform": Color(0.27, 0.28, 0.30), "vest": Color(0.12, 0.12, 0.13), "gear": Color(0.15, 0.15, 0.16),
	"helmet": Color(0.10, 0.10, 0.11), "boots": Color(0.07, 0.07, 0.07), "gloves": Color(0.08, 0.08, 0.08),
	"armband": Color(0.75, 0.08, 0.06),
}
const SKINS := [Color(0.80, 0.62, 0.48), Color(0.56, 0.40, 0.29), Color(0.70, 0.52, 0.38), Color(0.40, 0.28, 0.20), Color(0.86, 0.68, 0.55)]
const METAL := Color(0.07, 0.07, 0.075)
const POLY := Color(0.11, 0.11, 0.10)

## Body measurements (metres; origin between the feet).
const HIP_Y := 0.985          # hips high enough that the legs stand almost straight
const HIP_X := 0.105
const THIGH := 0.44
const SHIN := 0.43
const ANKLE_Y := 0.085
const SHOULDER := Vector3(0.205, 1.47, 0.0)
const UPPER_ARM := 0.29
const FOREARM := 0.27
const WAIST_Y := 0.99         # upper-body pivot (upper space, just above the belt)
const LEAN := 0.25            # forward lean when crouched (radians)

static var _mats := {}

var upper: Node3D            # chest, head, arms, rifle (moves down when crouched)
var head: Node3D
var muzzle: Node3D           # rifle muzzle (tracers / flash)
var launch_tip: Node3D       # grenade launcher / rocket tube exit, if any
var crouched := false

var _colors: Dictionary
var _skin: Color
var _meshes: Array = []      # every merged mesh instance (for tints)
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


## role: "rifleman" | "grenadier" | "anti_armor"; side: "friendly" | "enemy".
func build(role: String, side := "friendly", variant := 0) -> void:
	_colors = (ENEMY if side == "enemy" else (ANTI_ARMOR if role == "anti_armor" else FRIENDLY)).duplicate()
	_skin = SKINS[variant % SKINS.size()]
	_build_hips()
	upper = Node3D.new()
	upper.name = "Upper"
	add_child(upper)
	_build_chest(side)
	_build_head()
	_build_rifle(role)
	_build_arms(side)
	if role == "anti_armor":
		_build_launcher()
	for s in ["L", "R"]:
		_build_leg(s)
	_solve_legs()
	_left_target = _guard
	_solve_arms()


# ---------------------------------------------------------------- mesh merging

## Collects primitive shapes with a colour each and bakes them into one mesh.
class Merger:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(m: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
		var arr := m.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(c)
		for i in ind:
			idx.append(base + i)

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cap(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	c.radial_segments = 10
	c.rings = 3
	return c


static func _cyl(top: float, bottom: float, height: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = seg
	c.rings = 1
	return c


static func _sphere(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = 12
	s.rings = 6
	return s


static func _xf(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


static func _material(tint: String) -> StandardMaterial3D:
	var key := tint + ("_n" if Atmosphere.night else "_d")
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.45 if Atmosphere.night else 0.8
		m.metallic_specular = 0.6 if Atmosphere.night else 0.35
		match tint:
			"hurt":
				m.albedo_color = Color(2.2, 0.5, 0.4)
			"dead":
				m.albedo_color = Color(0.45, 0.45, 0.45)
			_:
				if Atmosphere.night:
					m.rim_enabled = true      # readable silhouettes in the dark
					m.rim = 0.5
					m.rim_tint = 0.6
		_mats[key] = m
	return _mats[key]


func _instance(parent: Node3D, mg: Merger) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mg.build()
	mi.material_override = _material("normal")
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


## "normal", "hurt" (red flash) or "dead" (darkened).
func set_tint(tint: String) -> void:
	var m := _material(tint)
	for mi in _meshes:
		mi.material_override = m


# ---------------------------------------------------------------- body

func _build_hips() -> void:
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0, HIP_Y, 0)
	add_child(_hips)
	var mg := Merger.new()
	var c := _colors
	mg.add(_cap(0.12, 0.36), _xf(Vector3(0, -0.03, 0), Vector3(0, 0, PI / 2), Vector3(1, 1, 0.72)), c["uniform"])
	mg.add(_cyl(0.165, 0.165, 0.06, 14), _xf(Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1, 0.72)), c["gear"])       # belt
	mg.add(_box(Vector3(0.05, 0.05, 0.03)), _xf(Vector3(0, 0.1, -0.12)), METAL)                                       # buckle
	mg.add(_box(Vector3(0.07, 0.1, 0.09)), _xf(Vector3(-0.16, 0.06, -0.02)), c["vest"])                               # pouch
	mg.add(_box(Vector3(0.06, 0.12, 0.08)), _xf(Vector3(0.17, 0.03, 0.02)), c["gear"])                                # holster
	mg.add(_box(Vector3(0.12, 0.08, 0.06)), _xf(Vector3(0, 0.07, 0.12)), c["vest"])                                   # dump pouch
	_instance(_hips, mg)


func _build_chest(side: String) -> void:
	var mg := Merger.new()
	var c := _colors
	mg.add(_cap(0.165, 0.6), _xf(Vector3(0, 1.3, 0), Vector3.ZERO, Vector3(1.22, 1, 0.72)), c["uniform"])        # torso
	mg.add(_box(Vector3(0.38, 0.36, 0.29)), _xf(Vector3(0, 1.33, -0.005)), c["vest"])                              # plate carrier
	for x in [-0.1, 0.0, 0.1]:
		mg.add(_box(Vector3(0.085, 0.13, 0.055)), _xf(Vector3(x, 1.23, -0.17)), c["gear"])                          # mag pouches
	mg.add(_box(Vector3(0.1, 0.08, 0.05)), _xf(Vector3(-0.1, 1.42, -0.165)), c["gear"])                             # admin pouch
	mg.add(_box(Vector3(0.07, 0.16, 0.07)), _xf(Vector3(0.2, 1.3, 0.05)), c["gear"])                                # radio pouch
	for x in [-0.12, 0.12]:
		mg.add(_box(Vector3(0.07, 0.03, 0.3)), _xf(Vector3(x, 1.52, 0.0)), c["vest"])                               # shoulder straps
	mg.add(_box(Vector3(0.31, 0.4, 0.17)), _xf(Vector3(0, 1.33, 0.23)), c["gear"])                                  # backpack
	mg.add(_box(Vector3(0.27, 0.14, 0.05)), _xf(Vector3(0, 1.25, 0.33)), c["vest"])                                  # pack pocket
	mg.add(_cyl(0.06, 0.06, 0.34), _xf(Vector3(0, 1.57, 0.24), Vector3(0, 0, PI / 2)), c["uniform"].darkened(0.2))   # bedroll
	mg.add(_cyl(0.055, 0.06, 0.09), _xf(Vector3(0, 1.6, 0)), _skin)                                                  # neck
	mg.add(_cyl(0.075, 0.08, 0.05), _xf(Vector3(0, 1.575, 0)), c["uniform"])                                         # collar
	_instance(upper, mg)


func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.66, 0)
	upper.add_child(head)
	var mg := Merger.new()
	var c := _colors
	mg.add(_sphere(0.1), _xf(Vector3(0, 0.07, -0.005), Vector3.ZERO, Vector3(0.95, 1.1, 1.0)), _skin)                 # head
	mg.add(_box(Vector3(0.05, 0.02, 0.02)), _xf(Vector3(-0.035, 0.09, -0.1)), Color(0.05, 0.04, 0.03))              # eyes
	mg.add(_box(Vector3(0.05, 0.02, 0.02)), _xf(Vector3(0.035, 0.09, -0.1)), Color(0.05, 0.04, 0.03))
	mg.add(_sphere(0.132, true), _xf(Vector3(0, 0.1, 0.005), Vector3.ZERO, Vector3(1.0, 0.95, 1.08)), c["helmet"])  # helmet shell
	mg.add(_cyl(0.137, 0.137, 0.022, 16), _xf(Vector3(0, 0.1, 0.005), Vector3.ZERO, Vector3(1, 1, 1.08)), c["helmet"].darkened(0.15))
	mg.add(_box(Vector3(0.055, 0.04, 0.03)), _xf(Vector3(0, 0.13, -0.14), Vector3(0.35, 0, 0)), METAL)               # NVG mount, on the helmet front
	mg.add(_box(Vector3(0.012, 0.09, 0.012)), _xf(Vector3(-0.09, 0.03, -0.03), Vector3(0, 0, 0.25)), c["gear"])       # chin strap
	mg.add(_box(Vector3(0.012, 0.09, 0.012)), _xf(Vector3(0.09, 0.03, -0.03), Vector3(0, 0, -0.25)), c["gear"])
	_instance(head, mg)
	# Fire-team patch on the back of the helmet (hidden unless split).
	_patch = MeshInstance3D.new()
	_patch.mesh = _box(Vector3(0.11, 0.06, 0.02))
	_patch.position = Vector3(0, 0.15, 0.135)
	_patch.visible = false
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(_patch)


func _build_leg(s: String) -> void:
	var c := _colors
	var thigh := Node3D.new()
	add_child(thigh)
	var mg := Merger.new()
	mg.add(_cap(0.075, THIGH + 0.08), _xf(Vector3(0, -THIGH * 0.5, 0)), c["uniform"])
	mg.add(_box(Vector3(0.08, 0.12, 0.05)), _xf(Vector3(0.07 if s == "R" else -0.07, -0.2, 0.0)), c["uniform"].darkened(0.1))   # cargo pocket
	_instance(thigh, mg)
	var shin := Node3D.new()
	add_child(shin)
	mg = Merger.new()
	mg.add(_cap(0.063, SHIN + 0.06), _xf(Vector3(0, -SHIN * 0.5, 0)), c["uniform"])
	mg.add(_box(Vector3(0.1, 0.1, 0.05)), _xf(Vector3(0, -0.04, -0.06)), c["gear"])                                   # knee pad
	mg.add(_cyl(0.07, 0.072, 0.12), _xf(Vector3(0, -SHIN + 0.04, 0)), c["boots"])                                     # boot top
	_instance(shin, mg)
	var foot := Node3D.new()
	add_child(foot)
	mg = Merger.new()
	mg.add(_box(Vector3(0.11, 0.1, 0.26)), _xf(Vector3(0, -0.03, -0.05)), c["boots"])
	mg.add(_box(Vector3(0.115, 0.025, 0.27)), _xf(Vector3(0, -0.075, -0.05)), Color(0.04, 0.04, 0.04))               # sole
	_instance(foot, mg)
	_legs[s] = {"thigh": thigh, "shin": shin, "foot": foot}


func _build_arms(side: String) -> void:
	var c := _colors
	for s in ["L", "R"]:
		var ua := Node3D.new()
		upper.add_child(ua)
		var mg := Merger.new()
		mg.add(_cap(0.056, UPPER_ARM + 0.07), _xf(Vector3(0, -UPPER_ARM * 0.5, 0)), c["uniform"])
		if s == "L" and c.has("armband"):
			mg.add(_cyl(0.062, 0.062, 0.07), _xf(Vector3(0, -0.1, 0)), c["armband"])
		mg.add(_box(Vector3(0.06, 0.07, 0.025)), _xf(Vector3(-0.055 if s == "L" else 0.055, -0.07, 0), Vector3.ZERO), c["vest"])   # shoulder patch
		_instance(ua, mg)
		var fa := Node3D.new()
		upper.add_child(fa)
		mg = Merger.new()
		mg.add(_cap(0.048, FOREARM + 0.04), _xf(Vector3(0, -FOREARM * 0.5, 0)), c["uniform"])
		mg.add(_cyl(0.053, 0.05, 0.05), _xf(Vector3(0, -FOREARM + 0.04, 0)), c["uniform"].darkened(0.15))               # cuff
		mg.add(_box(Vector3(0.075, 0.1, 0.045)), _xf(Vector3(0, -FOREARM - 0.04, 0)), c["gloves"])                      # hand
		_instance(fa, mg)
		_arms[s] = {"upper": ua, "fore": fa}


## Rifle at low ready across the body. The grenadier's has an underbarrel
## launcher; the burst rifle (anti-armor) is a shorter carbine.
func _build_rifle(role: String) -> void:
	var rifle := Node3D.new()
	rifle.name = "Rifle"
	_grip = Vector3(0.14, 1.12, -0.2)
	var dir := Vector3(-0.32, -0.2, -1.0).normalized()
	rifle.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), _grip)
	upper.add_child(rifle)
	_rifle = rifle
	_rifle_base = rifle.transform
	var carbine := role == "anti_armor"
	var front := 0.36 if carbine else 0.44          # handguard length
	var mg := Merger.new()
	mg.add(_box(Vector3(0.05, 0.075, 0.3)), _xf(Vector3(0, 0.03, -0.05)), METAL)                                     # receiver
	mg.add(_box(Vector3(0.04, 0.06, 0.22)), _xf(Vector3(0, 0.0, 0.2)), POLY)                                         # stock
	mg.add(_box(Vector3(0.045, 0.08, 0.04)), _xf(Vector3(0, -0.015, 0.31)), POLY)                                    # butt pad
	mg.add(_box(Vector3(0.035, 0.09, 0.04)), _xf(Vector3(0, -0.05, 0.0), Vector3(0.25, 0, 0)), POLY)                 # pistol grip
	mg.add(_box(Vector3(0.035, 0.13, 0.055)), _xf(Vector3(0, -0.07, -0.11), Vector3(-0.2, 0, 0)), METAL)             # magazine
	mg.add(_box(Vector3(0.05, 0.055, front)), _xf(Vector3(0, 0.035, -0.2 - front * 0.5)), POLY)                      # handguard
	mg.add(_cyl(0.011, 0.011, 0.22), _xf(Vector3(0, 0.04, -0.2 - front - 0.1), Vector3(PI / 2, 0, 0)), METAL)       # barrel
	mg.add(_cyl(0.018, 0.018, 0.05), _xf(Vector3(0, 0.04, -0.2 - front - 0.2), Vector3(PI / 2, 0, 0)), METAL)       # muzzle device
	mg.add(_cyl(0.022, 0.022, 0.11), _xf(Vector3(0, 0.095, -0.05), Vector3(PI / 2, 0, 0)), METAL)                   # optic
	mg.add(_box(Vector3(0.02, 0.03, 0.03)), _xf(Vector3(0, 0.075, -0.05)), METAL)                                     # optic mount
	if role == "grenadier":
		mg.add(_cyl(0.03, 0.03, 0.26), _xf(Vector3(0, -0.035, -0.32), Vector3(PI / 2, 0, 0)), _colors["gear"])      # underbarrel GL
		mg.add(_box(Vector3(0.03, 0.05, 0.05)), _xf(Vector3(0, -0.04, -0.19)), METAL)
	_instance(rifle, mg)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.04, -0.2 - front - 0.24)
	rifle.add_child(muzzle)
	if role == "grenadier":
		launch_tip = Node3D.new()
		launch_tip.position = Vector3(0, -0.035, -0.47)
		rifle.add_child(launch_tip)
	# Left hand rests on the handguard.
	_guard_local = Vector3(0, 0.0, -0.2 - front * 0.55)
	_guard = rifle.transform * _guard_local


## Rocket tube slung diagonally across the back of the pack, the muzzle end
## up over the right shoulder (rockets leave from there).
func _build_launcher() -> void:
	var tube := Node3D.new()
	var d := Vector3(0.64, 0.77, 0.0).normalized()
	tube.transform = Transform3D(Basis.looking_at(d, Vector3.BACK), Vector3(0.02, 1.38, 0.425))
	upper.add_child(tube)
	var mg := Merger.new()
	mg.add(_cyl(0.065, 0.065, 1.1, 12), _xf(Vector3(0, 0, 0), Vector3(PI / 2, 0, 0)), _colors["gear"].darkened(0.1))
	mg.add(_cyl(0.08, 0.075, 0.12, 12), _xf(Vector3(0, 0, -0.52), Vector3(PI / 2, 0, 0)), POLY)
	mg.add(_cyl(0.08, 0.075, 0.1, 12), _xf(Vector3(0, 0, 0.52), Vector3(PI / 2, 0, 0)), POLY)
	mg.add(_box(Vector3(0.04, 0.08, 0.06)), _xf(Vector3(0, 0.07, -0.15)), METAL)                                   # sight
	_instance(tube, mg)
	# Sling: over the left shoulder, across the chest to the tube's lower end.
	var sling := Merger.new()
	sling.add(_box(Vector3(0.03, 0.62, 0.012)), _xf(Vector3(0.0, 1.36, -0.165), Vector3(0, 0, 0.62)), _colors["gear"].darkened(0.3))
	_instance(upper, sling)
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
	var hip_drop := 0.33 if crouched else 0.02
	var hip_back := 0.08 if crouched else 0.0
	_hips.position = Vector3(0, HIP_Y - hip_drop, hip_back)
	# The upper body was laid out for hips at 0.93 m: keep it on the hips, and
	# lean it forward when low by pivoting at the waist (not at the feet, which
	# would swing the torso off the hips).
	var lean := LEAN if crouched else 0.0
	var waist := Vector3(0, WAIST_Y, 0)
	var on_hips := Vector3(0, HIP_Y - 0.93 - hip_drop, hip_back)
	var rot := Basis(Vector3.RIGHT, -lean)
	upper.transform = Transform3D(rot, on_hips + waist - rot * waist)
	head.rotation.x = lean * 0.7                         # keep eyes up
	# Counter-rotate the rifle about the grip so the muzzle stays at low
	# ready instead of pointing into the ground.
	var counter := Transform3D(Basis(Vector3.RIGHT, lean * 0.8), Vector3.ZERO)
	_rifle.transform = Transform3D(Basis.IDENTITY, _grip) * counter * Transform3D(Basis.IDENTITY, -_grip) * _rifle_base
	_guard = _rifle.transform * _guard_local
	if not (_gesture and _gesture.is_running()):
		_left_target = _guard
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var hip := _hips.position + Vector3(HIP_X * sx, -0.04, 0)
		var ankle := Vector3(HIP_X * sx * 1.15, ANKLE_Y, -0.03 + (0.06 if s == "R" else -0.05))
		if crouched and s == "R":
			ankle.z += 0.2                                   # one foot back when kneeling-low
		var knee := _solve(hip, ankle, THIGH, SHIN, Vector3(0.1 * sx, 0, -1))
		_aim_bone(_legs[s]["thigh"], hip, knee, Vector3(0, 0, -1))
		_aim_bone(_legs[s]["shin"], knee, ankle, Vector3(0, 0, -1))
		_legs[s]["foot"].transform = Transform3D(Basis(Vector3.UP, 0.08 * sx), ankle)


func _solve_arms() -> void:
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var sh := SHOULDER * Vector3(sx, 1, 1)
		var hand: Vector3 = _left_target if s == "L" else _grip
		var pole := Vector3(0.7 * sx, -0.7, 0.35)
		var elbow := _solve(sh, hand, UPPER_ARM, FOREARM, pole)
		_aim_bone(_arms[s]["upper"], sh, elbow, Vector3(sx, 0, 0))
		_aim_bone(_arms[s]["fore"], elbow, hand, Vector3(sx, 0, 0))


# ---------------------------------------------------------------- pose API

func set_crouch(on: bool) -> void:
	if on == crouched:
		return
	crouched = on
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
			ch.mesh = _box(Vector3(0.025, 0.02, 0.09))
			ch.material_override = amber
			ch.position = Vector3(-0.058 if s == "L" else 0.058, -0.06 - i * 0.035, 0)
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ua.add_child(ch)
			_sgt_parts.append(ch)
	var ant := MeshInstance3D.new()
	ant.mesh = _cyl(0.006, 0.01, 0.8, 6)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.08)
	ant.material_override = dark
	ant.position = Vector3(0.12, 1.88, 0.27)
	ant.rotation.x = -0.15
	upper.add_child(ant)
	_sgt_parts.append(ant)
	var tip := MeshInstance3D.new()
	tip.mesh = _sphere(0.012)
	tip.material_override = amber
	tip.position = Vector3(0.12, 2.27, 0.33)
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
	if crouched:
		crouched = false
		_solve_legs()
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
	for mi in _meshes:
		if mi.get_parent() == _rifle:
			continue
		var is_upper: bool = upper.is_ancestor_of(mi)
		var xf: Transform3D = (inv_u if is_upper else inv) * mi.global_transform
		var bb: AABB = mi.get_aabb()
		for c in 8:
			if is_upper:
				pts_u.append(xf * bb.get_endpoint(c))
			else:
				pts_l.append(xf * bb.get_endpoint(c))
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
	position.y = -minf(ll, best_lu)
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
