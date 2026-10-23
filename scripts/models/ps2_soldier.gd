extends RefCounted
## A static PS2-era soldier (no rig, no animation): one smooth-shaded mesh in
## a relaxed contrapposto with the rifle at low ready. Original design: a
## patrol trooper in a charcoal field jacket, open-face knit balaclava, puffy
## urban-camo cargo trousers bloused into lace-up boots, olive belt-and-harness
## webbing, black gloves, AK-74-pattern rifle.
##
## Built with the shape kit (scripts/model_kit.gd) in model space, drawn with
## shaders/ps2_soldier.gdshader (Gouraud lighting and painted-texture style
## shading: soft camo, knit ribbing, fabric folds, baked occlusion).
##   var mi := PS2Soldier.build()      # MeshInstance3D, feet at y = 0, facing -Z

const Kit = preload("res://scripts/model_kit.gd")
const SoldierModel = preload("res://scripts/soldier_model.gd")
const B = Kit.Builder

# palette
const JACKET := Color(0.19, 0.2, 0.21)
const PANTS := Color(0.34, 0.345, 0.35)
const KNIT := Color(0.075, 0.075, 0.08)
const SKIN := Color(0.72, 0.53, 0.42)
const WEB := Color(0.26, 0.27, 0.19)
const GLOVE := Color(0.06, 0.06, 0.065)
const BOOT := Color(0.07, 0.06, 0.055)
const SOLE := Color(0.035, 0.035, 0.035)
const STEEL := Color(0.09, 0.09, 0.1)
const POLY := Color(0.07, 0.07, 0.07)
const PLUM := Color(0.33, 0.14, 0.11)

# joints (model space, metres; feet on y = 0, facing -Z)
const HIP_L := Vector3(-0.1, 0.95, 0.0)
const HIP_R := Vector3(0.1, 0.955, 0.0)
const KNEE_L := Vector3(-0.125, 0.52, -0.075)
const KNEE_R := Vector3(0.11, 0.52, 0.01)
const ANKLE_L := Vector3(-0.15, 0.09, -0.06)
const ANKLE_R := Vector3(0.13, 0.09, 0.055)
const SH_L := Vector3(-0.205, 1.47, 0.0)
const SH_R := Vector3(0.205, 1.47, 0.0)
const GRIP := Vector3(0.12, 1.12, -0.19)       # right hand on the pistol grip
const GUARD := Vector3(-0.04, 1.08, -0.4)      # left hand under the handguard
const HEAD := Vector3(0.0, 1.71, -0.01)

static var _mesh: ArrayMesh
static var triangles := 0


static func build() -> MeshInstance3D:
	if _mesh == null:
		var b := B.new(0)
		_body(b)
		_head(b)
		_kit(b)
		_arms(b)
		_rifle(b)
		_mesh = b.build()
		triangles = b.triangles()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ps2_soldier.gdshader")
	mi.material_override = m
	return mi


static func _x(pos: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return Kit.xf(pos, rot)


static func _dk(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f)


## Frame for a limb from a to b: local -Y runs a -> b, local +Z leans
## toward `front`.
static func _frame(a: Vector3, b: Vector3, front: Vector3) -> Transform3D:
	var y := (a - b).normalized()
	var z := (front - y * front.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), a)


## Lofted limb from a to b through [t (0..1 along it), rx, rz] rings.
static func _limb(b: B, a: Vector3, e: Vector3, rings: Array, front: Vector3, c: Color, id: float, nu := 16, caps := true) -> void:
	var len := a.distance_to(e)
	var rr := []
	for r in rings:
		rr.append([Vector3(0, -r[0] * len, 0), r[1], r[2]])
	b.loft(rr, _frame(a, e, front), c, id, nu, caps, caps)


## Flat strap through points, `w` wide, lying on the surface whose outward
## direction is `out` at each point.
static func _strap(b: B, pts: Array, outs: Array, w: float, c: Color) -> void:
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var mid := (p0 + p1) * 0.5
		var along := (p1 - p0)
		var o: Vector3 = ((outs[i] as Vector3) + (outs[i + 1] as Vector3)).normalized()
		var x := along.normalized().cross(o).normalized()
		var basis := Basis(x * w * 0.5, along * 0.5 * 1.08, o * 0.006)
		b.sq(Vector3.ONE, Transform3D(basis, mid), c, Kit.NYLON, 0.15, 0.2, 8, 4)


# ---------------------------------------------------------------- body

static func _body(b: B) -> void:
	# trousers: seat and hips
	b.loft([
		[Vector3(0, 0.8, 0.0), 0.09, 0.085], [Vector3(0, 0.86, 0.0), 0.15, 0.11],
		[Vector3(0, 0.93, 0.005), 0.168, 0.12], [Vector3(0, 1.0, 0.0), 0.155, 0.112],
	], Transform3D.IDENTITY, PANTS, Kit.CAMO, 20)
	# puffy legs with fold ripples, bloused at the boot
	for leg in [[HIP_L, KNEE_L, ANKLE_L, -1.0], [HIP_R, KNEE_R, ANKLE_R, 1.0]]:
		var hip: Vector3 = leg[0]
		var knee: Vector3 = leg[1]
		var ankle: Vector3 = leg[2]
		var sx: float = leg[3]
		var fwd := Vector3(0, 0, -1)
		_limb(b, hip + Vector3(0, 0.05, 0), knee, [
			[0.0, 0.1, 0.098], [0.12, 0.122, 0.115], [0.3, 0.138, 0.128], [0.46, 0.131, 0.122],
			[0.58, 0.121, 0.114], [0.68, 0.127, 0.119], [0.84, 0.112, 0.106], [1.0, 0.09, 0.088],
		], fwd, PANTS, Kit.CAMO, 18)
		_limb(b, knee + Vector3(0, 0.03, 0), ankle + Vector3(0, 0.1, 0), [
			[0.0, 0.092, 0.095], [0.18, 0.116, 0.112], [0.42, 0.12, 0.114], [0.6, 0.106, 0.102],
			[0.72, 0.112, 0.107], [0.86, 0.098, 0.095], [0.95, 0.078, 0.076], [1.0, 0.062, 0.062],
		], fwd, PANTS, Kit.CAMO, 18)
		# cargo pocket with flap on the outside of the thigh
		var tmid := hip.lerp(knee, 0.5) + Vector3(0.115 * sx, 0, 0.005)
		b.sq(Vector3(0.016, 0.075, 0.06), _x(tmid, Vector3(0, 0, -0.08 * sx)), _dk(PANTS, 0.93), Kit.CAMO, 0.3, 0.35, 10, 6)
		b.sq(Vector3(0.019, 0.02, 0.064), _x(tmid + Vector3(0.004 * sx, 0.075, 0), Vector3(0, 0, -0.08 * sx)), _dk(PANTS, 1.05), Kit.CAMO, 0.35, 0.4, 10, 5)
		# knee seam patch
		b.sq(Vector3(0.07, 0.06, 0.02), _frame(knee + Vector3(0, 0.02, -0.075), knee + Vector3(0, -0.1, -0.08), fwd), _dk(PANTS, 0.9), Kit.CAMO, 0.6, 0.6, 12, 6)
		_boot(b, ankle, sx)
	# field jacket: short, over the hips, standing collar, front zip
	var jr := [
		[0.9, 0.17, 0.128], [0.93, 0.168, 0.124], [1.02, 0.158, 0.114], [1.14, 0.166, 0.118],
		[1.27, 0.186, 0.128], [1.38, 0.2, 0.128], [1.46, 0.2, 0.118], [1.52, 0.165, 0.102],
		[1.565, 0.09, 0.08],
	]
	var rings := []
	for r in jr:
		rings.append([Vector3(0, r[0], -0.005), r[1], r[2]])
	b.loft(rings, Transform3D.IDENTITY, JACKET, Kit.CLOTH, 22)
	for sx in [-1.0, 1.0]:
		b.sq(Vector3(0.066, 0.07, 0.07), _x(Vector3(0.188 * sx, 1.455, 0.0)), JACKET, Kit.CLOTH, 1.0, 1.0, 14, 9)   # shoulder
		b.sq(Vector3(0.045, 0.008, 0.065), _x(Vector3(0.15 * sx, 1.515, 0.0), Vector3(0, 0, -0.32 * sx)), _dk(JACKET, 0.85), Kit.CLOTH, 0.3, 0.3, 8, 4)  # epaulette
		b.sq(Vector3(0.006, 0.006, 0.006), _x(Vector3(0.115 * sx, 1.522, 0.0)), STEEL, Kit.METAL, 1.0, 1.0, 6, 4)       # button
		# chest pocket with flap and button
		b.sq(Vector3(0.056, 0.062, 0.013), _x(Vector3(0.088 * sx, 1.315, -0.132), Vector3(0, 0.25 * sx, 0)), _dk(JACKET, 0.94), Kit.CLOTH, 0.3, 0.35, 10, 6)
		b.sq(Vector3(0.059, 0.019, 0.015), _x(Vector3(0.089 * sx, 1.375, -0.134), Vector3(0, 0.25 * sx, 0)), _dk(JACKET, 1.08), Kit.CLOTH, 0.35, 0.4, 10, 5)
		b.sq(Vector3(0.007, 0.007, 0.004), _x(Vector3(0.093 * sx, 1.37, -0.15)), STEEL, Kit.METAL, 1.0, 1.0, 6, 4)
	b.collar(Vector2(0.088, 0.082), Vector2(0.094, 0.088), 1.535, 1.625, 0.012, 0.005, Transform3D.IDENTITY, _dk(JACKET, 0.92), Kit.CLOTH, 14)
	# zip line down the front, following the jacket's front surface
	for i in jr.size() - 2:
		var y0: float = jr[i][0]
		var y1: float = jr[i + 1][0]
		var z0: float = -0.005 - float(jr[i][2]) - 0.002
		var z1: float = -0.005 - float(jr[i + 1][2]) - 0.002
		var a := Vector3(0, y0, z0)
		var e := Vector3(0, y1, z1)
		b.sq(Vector3(0.006, a.distance_to(e) * 0.52, 0.003), Transform3D(_frame(e, a, Vector3(0, 0, -1)).basis, (a + e) * 0.5), Color(0.05, 0.05, 0.05), Kit.METAL, 0.3, 0.3, 6, 3)


static func _boot(b: B, ankle: Vector3, sx: float) -> void:
	var yaw := 0.12 * sx                      # toes out a little
	var f := Transform3D(Basis(Vector3.UP, -yaw), ankle)
	# shaft up the ankle, under the bloused trousers
	b.loft([[Vector3(0, -0.03, 0.005), 0.052, 0.06], [Vector3(0, 0.05, 0.005), 0.05, 0.056], [Vector3(0, 0.11, 0.0), 0.046, 0.05]],
		f, BOOT, Kit.RUBBER, 14, false, true)
	b.sq(Vector3(0.05, 0.045, 0.11), f * _x(Vector3(0, -0.038, -0.055)), BOOT, Kit.RUBBER, 0.45, 0.5, 14, 8)
	b.sq(Vector3(0.049, 0.033, 0.052), f * _x(Vector3(0, -0.052, -0.13)), _dk(BOOT, 1.2), Kit.RUBBER, 0.5, 0.6, 12, 6)
	b.sq(Vector3(0.056, 0.014, 0.135), f * _x(Vector3(0, -0.076, -0.05)), SOLE, Kit.RUBBER, 0.2, 0.4, 14, 4)
	b.sq(Vector3(0.05, 0.02, 0.04), f * _x(Vector3(0, -0.068, 0.045)), SOLE, Kit.RUBBER, 0.3, 0.4, 10, 4)   # heel
	# laces: crossing ridges up the front
	for i in 5:
		var y := -0.02 + i * 0.026
		b.sq(Vector3(0.026, 0.004, 0.005), f * _x(Vector3(0, y, -0.058 - 0.004 * (4 - i)), Vector3(0, 0, 0.35 * (1 if i % 2 == 0 else -1))), Color(0.12, 0.11, 0.1), Kit.NYLON, 0.4, 0.5, 6, 3)


static func _head(b: B) -> void:
	var h := HEAD
	var hx := Transform3D(Basis(Vector3.UP, 0.12), h)      # head turned a touch toward the muzzle
	# neck and knit balaclava
	b.loft([[Vector3(0, -0.17, 0.012), 0.07, 0.068], [Vector3(0, -0.1, 0.01), 0.064, 0.062], [Vector3(0, -0.04, 0.0), 0.068, 0.074]],
		hx, KNIT, Kit.CLOTH, 16, false, false)
	b.sq(Vector3(0.094, 0.118, 0.104), hx * _x(Vector3(0, 0.0, 0.006)), KNIT, Kit.CLOTH, 1.0, 1.0, 22, 14)
	b.sq(Vector3(0.02, 0.03, 0.022), hx * _x(Vector3(0.093, -0.005, 0.01)), KNIT, Kit.CLOTH, 1.0, 1.0, 10, 6)     # ear
	b.sq(Vector3(0.02, 0.03, 0.022), hx * _x(Vector3(-0.093, -0.005, 0.01)), KNIT, Kit.CLOTH, 1.0, 1.0, 10, 6)
	b.sq(Vector3(0.017, 0.03, 0.022), hx * _x(Vector3(0, -0.012, -0.095), Vector3(-0.2, 0, 0)), KNIT, Kit.CLOTH, 1.0, 1.0, 10, 6)  # nose under the knit
	b.sq(Vector3(0.05, 0.03, 0.03), hx * _x(Vector3(0, -0.07, -0.075)), KNIT, Kit.CLOTH, 1.0, 1.0, 12, 6)   # chin
	# open eye band: skin, rolled knit rim, eyes and brows
	b.sq(Vector3(0.066, 0.022, 0.03), hx * _x(Vector3(0, 0.026, -0.082)), SKIN, Kit.SKIN, 0.7, 0.8, 16, 8)
	b.sq(Vector3(0.074, 0.009, 0.028), hx * _x(Vector3(0, 0.05, -0.084)), _dk(KNIT, 1.3), Kit.CLOTH, 0.7, 0.8, 16, 4)
	b.sq(Vector3(0.074, 0.009, 0.028), hx * _x(Vector3(0, 0.002, -0.086)), _dk(KNIT, 1.3), Kit.CLOTH, 0.7, 0.8, 16, 4)
	for sx in [-1.0, 1.0]:
		b.sq(Vector3(0.013, 0.008, 0.006), hx * _x(Vector3(0.03 * sx, 0.027, -0.107)), Color(0.85, 0.83, 0.8), Kit.GLASS, 1.0, 1.0, 10, 6)
		b.sq(Vector3(0.006, 0.0065, 0.004), hx * _x(Vector3(0.03 * sx, 0.027, -0.111)), Color(0.12, 0.09, 0.06), Kit.GLASS, 1.0, 1.0, 8, 5)
		b.sq(Vector3(0.017, 0.004, 0.005), hx * _x(Vector3(0.031 * sx, 0.041, -0.104), Vector3(0, 0, -0.12 * sx)), Color(0.15, 0.1, 0.07), Kit.SKIN, 0.5, 0.6, 8, 4)


static func _kit(b: B) -> void:
	# belt over the jacket hem
	b.loft([[Vector3(0, 0.955, 0), 0.172, 0.13], [Vector3(0, 0.96, 0), 0.178, 0.136],
		[Vector3(0, 1.0, 0), 0.172, 0.13], [Vector3(0, 1.005, 0), 0.166, 0.124]],
		Transform3D.IDENTITY, WEB, Kit.NYLON, 22, false, false)
	b.sq(Vector3(0.03, 0.025, 0.008), _x(Vector3(0, 0.98, -0.137)), STEEL, Kit.METAL, 0.25, 0.25, 8, 4)
	# Y-harness: shoulder straps down the front to the belt, crossing at the back
	for sx in [-1.0, 1.0]:
		var pts := [Vector3(0.092 * sx, 1.0, -0.134), Vector3(0.1 * sx, 1.18, -0.124), Vector3(0.112 * sx, 1.35, -0.135),
			Vector3(0.118 * sx, 1.47, -0.115), Vector3(0.122 * sx, 1.535, -0.03), Vector3(0.11 * sx, 1.51, 0.09),
			Vector3(0.05 * sx, 1.38, 0.13)]
		var outs := [Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0.1, -1), Vector3(0, 0.6, -1), Vector3(0, 1, 0), Vector3(0, 0.6, 1), Vector3(0, 0, 1)]
		_strap(b, pts, outs, 0.038, WEB)
		# double mag pouches on the belt
		for i in 2:
			b.sq(Vector3(0.033, 0.055, 0.03), _x(Vector3((0.07 + i * 0.07) * sx, 0.95, -0.15 + i * 0.02), Vector3(0, 0.3 * sx * i, 0)), WEB, Kit.NYLON, 0.3, 0.35, 10, 6)
			b.sq(Vector3(0.035, 0.017, 0.032), _x(Vector3((0.07 + i * 0.07) * sx, 1.003, -0.151 + i * 0.02), Vector3(0, 0.3 * sx * i, 0)), _dk(WEB, 1.12), Kit.NYLON, 0.35, 0.4, 10, 4)
	_strap(b, [Vector3(0, 1.38, 0.13), Vector3(0, 1.15, 0.125), Vector3(0, 1.0, 0.134)], [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)], 0.04, WEB)
	# frag on the left harness strap, canteen at the back right, first-aid pouch back left
	b.sq(Vector3(0.028, 0.034, 0.028), _x(Vector3(-0.115, 1.27, -0.16)), Color(0.22, 0.25, 0.17), Kit.METAL, 0.9, 1.0, 12, 8)
	b.cyl(Vector3(-0.115, 1.302, -0.16), Vector3(-0.115, 1.325, -0.16), 0.01, 0.008, STEEL, Kit.METAL, 8)
	b.sq(Vector3(0.012, 0.022, 0.004), _x(Vector3(-0.098, 1.31, -0.19), Vector3(0, 0, 0.3)), STEEL, Kit.METAL, 0.3, 0.3, 6, 3)
	b.sq(Vector3(0.05, 0.075, 0.04), _x(Vector3(0.135, 0.92, 0.125), Vector3(0, -0.5, 0)), WEB, Kit.NYLON, 0.5, 0.8, 12, 8)
	b.cyl(Vector3(0.135, 0.995, 0.125), Vector3(0.135, 1.015, 0.125), 0.014, 0.012, Color(0.05, 0.05, 0.05), Kit.RUBBER, 8)
	b.sq(Vector3(0.06, 0.05, 0.035), _x(Vector3(-0.13, 0.935, 0.13), Vector3(0, 0.45, 0)), WEB, Kit.NYLON, 0.3, 0.35, 10, 6)


static func _arms(b: B) -> void:
	for side in [["R", SH_R, GRIP, 1.0], ["L", SH_L, GUARD, -1.0]]:
		var sh: Vector3 = side[1]
		var hand: Vector3 = side[2]
		var sx: float = side[3]
		var pole := Vector3(0.7 * sx, -0.7, 0.35)
		var elbow: Vector3 = SoldierModel._solve(sh, hand, SoldierModel.UPPER_ARM, SoldierModel.FOREARM, pole)
		var out := Vector3(sx, 0, 0.2)
		_limb(b, sh + (sh - elbow).normalized() * 0.03, elbow, [
			[0.0, 0.07, 0.068], [0.25, 0.071, 0.068], [0.55, 0.066, 0.062], [0.8, 0.06, 0.056], [1.0, 0.056, 0.054]],
			out, JACKET, Kit.CLOTH, 16)
		b.sq(Vector3(0.058, 0.058, 0.058), _x(elbow), JACKET, Kit.CLOTH, 1.0, 1.0, 12, 8)
		_limb(b, elbow, hand, [
			[0.0, 0.055, 0.054], [0.3, 0.058, 0.053], [0.65, 0.05, 0.046], [0.82, 0.052, 0.048], [0.86, 0.046, 0.043], [0.9, 0.04, 0.038]],
			out, JACKET, Kit.CLOTH, 16, false)
		# glove: cuff, back of the hand, curled fingers, thumb
		var fdir := (hand - elbow).normalized()
		var fr := _frame(hand - fdir * 0.03, hand + fdir * 0.09, out)
		b.loft([[Vector3(0, 0.0, 0), 0.042, 0.04], [Vector3(0, -0.03, 0), 0.04, 0.036]], fr, GLOVE, Kit.RUBBER, 12, true, false)
		b.sq(Vector3(0.045, 0.048, 0.022), fr * _x(Vector3(0, -0.07, 0.002)), GLOVE, Kit.RUBBER, 0.5, 0.6, 12, 7)
		for i in 4:
			var fy := -0.112
			var fx := (i - 1.5) * 0.021
			b.sq(Vector3(0.0105, 0.022, 0.014), fr * _x(Vector3(fx, fy, -0.016), Vector3(0.9, 0, 0)), GLOVE, Kit.RUBBER, 0.8, 0.9, 8, 5)
		b.sq(Vector3(0.012, 0.03, 0.013), fr * _x(Vector3(0.04 * sx, -0.07, -0.025), Vector3(0.3, 0, 0.5 * sx)), GLOVE, Kit.RUBBER, 0.8, 0.9, 8, 5)
		b.sq(Vector3(0.04, 0.012, 0.008), fr * _x(Vector3(0, -0.085, 0.022)), _dk(GLOVE, 1.8), Kit.RUBBER, 0.4, 0.5, 8, 4)   # knuckle pad


# ---------------------------------------------------------------- rifle

static func _rifle(b: B) -> void:
	var dir := (GUARD - GRIP).normalized()
	dir = (dir + Vector3(0, 0.02, -0.25)).normalized()
	var r := Transform3D(Basis.looking_at(dir, Vector3.UP), GRIP)
	var s := func(h: Vector3, pos: Vector3, c: Color, id: float, rot := Vector3.ZERO, e1 := 0.2, e2 := 0.25) -> void:
		b.sq(h, r * _x(pos, rot), c, id, e1, e2, 10, 6)
	s.call(Vector3(0.023, 0.036, 0.135), Vector3(0, 0.035, -0.06), STEEL, Kit.METAL)                 # receiver
	s.call(Vector3(0.021, 0.014, 0.125), Vector3(0, 0.07, -0.07), STEEL, Kit.METAL, Vector3.ZERO, 0.4, 0.5)   # dust cover
	s.call(Vector3(0.004, 0.012, 0.035), Vector3(0.025, 0.045, -0.03), _dk(STEEL, 1.3), Kit.METAL)    # charging handle
	s.call(Vector3(0.016, 0.046, 0.021), Vector3(0, -0.038, 0.022), POLY, Kit.RUBBER, Vector3(0.35, 0, 0), 0.35, 0.4)   # grip
	s.call(Vector3(0.003, 0.004, 0.032), Vector3(0, -0.02, -0.03), STEEL, Kit.METAL)                   # trigger guard
	# plum polymer magazine, curved
	for i in 4:
		s.call(Vector3(0.0165, 0.034, 0.031), Vector3(0, -0.045 - i * 0.052, -0.112 - i * 0.03 - i * i * 0.006), PLUM, Kit.RUBBER, Vector3(0.15 + i * 0.2, 0, 0), 0.25, 0.3)
	# side-folding skeleton stock (tube frame + butt plate)
	b.tube([r * Vector3(0, 0.045, 0.07), r * Vector3(0, 0.035, 0.31)], 0.009, STEEL, Kit.METAL, 8)
	b.tube([r * Vector3(0, -0.01, 0.075), r * Vector3(0, -0.035, 0.3)], 0.009, STEEL, Kit.METAL, 8)
	s.call(Vector3(0.02, 0.055, 0.01), Vector3(0, 0.002, 0.312), STEEL, Kit.METAL)
	# handguard and gas tube (black polymer), barrel, front sight, muzzle brake
	s.call(Vector3(0.026, 0.025, 0.12), Vector3(0, 0.028, -0.315), POLY, Kit.RUBBER, Vector3.ZERO, 0.4, 0.5)
	s.call(Vector3(0.018, 0.014, 0.11), Vector3(0, 0.067, -0.3), POLY, Kit.RUBBER, Vector3.ZERO, 0.4, 0.5)
	b.cyl(r * Vector3(0, 0.04, -0.43), r * Vector3(0, 0.04, -0.72), 0.0105, 0.0105, STEEL, Kit.METAL, 12)
	s.call(Vector3(0.016, 0.018, 0.02), Vector3(0, 0.062, -0.45), STEEL, Kit.METAL)
	s.call(Vector3(0.007, 0.032, 0.01), Vector3(0, 0.068, -0.655), STEEL, Kit.METAL)
	b.cyl(r * Vector3(0, 0.04, -0.72), r * Vector3(0, 0.04, -0.79), 0.0155, 0.0145, _dk(STEEL, 0.8), Kit.METAL, 12)
	s.call(Vector3(0.012, 0.008, 0.022), Vector3(0, 0.08, -0.17), STEEL, Kit.METAL)                   # rear sight
	# sling from the front swivel back along the body
	b.tube([r * Vector3(0, -0.01, -0.44), r * Vector3(-0.04, -0.12, -0.25), r * Vector3(-0.03, -0.13, 0.05), r * Vector3(0, -0.03, 0.29)], 0.006, WEB, Kit.NYLON, 6)
