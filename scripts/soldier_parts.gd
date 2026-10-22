extends RefCounted
## Geometry for the universal soldier: every body part, kit item and weapon,
## built from the shape kit (scripts/model_kit.gd) and cached per palette and
## detail level, so a squad of twenty costs a handful of builds.
##
## Spaces (the rig in soldier_model.gd moves these):
##   hips   origin at the hip joint height, forward -Z
##   upper  chest/arms/head laid out for hips at 0.93 m; shoulders (+-0.205, 1.47)
##   head   origin at the top of the neck (1.66 in upper space), face -Z
##   thigh / shin   bone runs down -Y; local +Z = forward; outward = -X*side
##   upper arm / forearm   bone runs down -Y; local +Z = outward; forward = +X*side
##   foot   origin at the ankle, toes -Z, sole 0.0875 below
##   rifle  origin at the pistol grip, barrel -Z, +Y up
## (side = +1 right, -1 left)
##
## LOD 0 is the close-up model; LOD 1 drops small details and halves curve
## segments for soldiers further than a few metres away.

const Kit = preload("res://scripts/model_kit.gd")
const B = Kit.Builder

static var _cache := {}
static var tri_count := {}        # part key -> triangles (for budgets / tests)


# ---------------------------------------------------------------- palettes

const _KIT_TONES := [Color(0.115, 0.12, 0.125), Color(0.075, 0.075, 0.08), Color(0.24, 0.245, 0.24)]
const _HELMET_TONES := [Color(0.16, 0.165, 0.17), Color(0.10, 0.10, 0.105)]
const _FILTER_TONES := [Color(0.24, 0.25, 0.22), Color(0.13, 0.13, 0.13)]


## Colours for one soldier. Friendlies: dark grey urban fatigues, charcoal /
## black / wolf-grey kit mixed per man. Rocket team: coyote pack and tube so
## they read as a separate team until they join. Enemies: olive-brown
## fatigues, black kit, red-tinted mask lenses and a red armband.
static func palette(side: String, role: String, variant: int) -> Dictionary:
	var v := absi(variant)
	var p := {}
	if side == "enemy":
		p = {
			"uniform": Color(0.28, 0.26, 0.19), "hood": Color(0.12, 0.115, 0.1),
			"kit": Color(0.07, 0.07, 0.07), "kit2": [Color(0.07, 0.07, 0.07), Color(0.2, 0.18, 0.13)][v % 2],
			"helmet": Color(0.085, 0.085, 0.09), "mask": Color(0.05, 0.05, 0.05),
			"lens": Color(0.35, 0.03, 0.02), "filter": Color(0.12, 0.12, 0.12),
			"gloves": Color(0.06, 0.06, 0.06), "pads": Color(0.07, 0.07, 0.07),
			"boots": Color(0.06, 0.05, 0.045), "pack": Color(0.2, 0.19, 0.14),
			"armband": Color(0.7, 0.07, 0.05), "weapon": "ak",
		}
	else:
		p = {
			"uniform": Color(0.205, 0.21, 0.215), "hood": Color(0.13, 0.13, 0.135),
			"kit": _KIT_TONES[v % 3], "kit2": _KIT_TONES[(v + 1) % 3],
			"helmet": _HELMET_TONES[(v / 3) % 2], "mask": Color(0.06, 0.06, 0.065),
			"lens": Color(0.04, 0.1, 0.09), "filter": _FILTER_TONES[(v / 2) % 2],
			"gloves": Color(0.075, 0.075, 0.08), "pads": Color(0.09, 0.09, 0.095),
			"boots": Color(0.07, 0.065, 0.06), "pack": Color(0.18, 0.185, 0.19),
			"armband": null, "weapon": "m4",
		}
		if role == "anti_armor":
			p["pack"] = Color(0.42, 0.36, 0.26)
			p["kit2"] = Color(0.38, 0.32, 0.23)
	p["role"] = role
	p["key"] = "%s/%s/%d" % [side, role, (v % 6) if side != "enemy" else v % 2]
	return p


# ---------------------------------------------------------------- cache

static func get_mesh(part: String, p: Dictionary, lod: int, extra := "") -> ArrayMesh:
	var key := "%s|%s|%s|%d" % [part, p["key"], extra, lod]
	if not _cache.has(key):
		var b := B.new(lod)
		match part:
			"hips": _hips(b, p)
			"torso": _torso(b, p)
			"head": _head(b, p)
			"upper_arm": _upper_arm(b, p, extra)
			"forearm": _forearm(b, p, extra)
			"thigh": _thigh(b, p, extra)
			"shin": _shin(b, p, extra)
			"foot": _foot(b, p)
			"rifle": _rifle(b, p)
			"launcher": _launcher(b, p)
			"sling": _sling(b, p)
		_cache[key] = b.build()
		tri_count[key] = b.triangles()
	return _cache[key]


static func _x(pos: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return Kit.xf(pos, rot)


static func _dk(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f)


# ---------------------------------------------------------------- body

static func _hips(b: B, p: Dictionary) -> void:
	var u: Color = p["uniform"]
	b.loft([
		[Vector3(0, -0.14, 0.0), 0.07, 0.065], [Vector3(0, -0.1, 0.0), 0.11, 0.09],
		[Vector3(0, -0.04, 0.005), 0.155, 0.11], [Vector3(0, 0.03, 0.005), 0.163, 0.116],
		[Vector3(0, 0.09, 0.0), 0.155, 0.11], [Vector3(0, 0.14, 0.0), 0.148, 0.106],
	], Transform3D.IDENTITY, u, Kit.CAMO, 16)
	# battle belt
	var kit: Color = p["kit"]
	b.loft([[Vector3(0, 0.068, 0), 0.164, 0.119], [Vector3(0, 0.073, 0), 0.171, 0.126],
		[Vector3(0, 0.127, 0), 0.171, 0.126], [Vector3(0, 0.132, 0), 0.164, 0.119]],
		Transform3D.IDENTITY, kit, Kit.NYLON, 18, false, false)
	b.sq(Vector3(0.032, 0.022, 0.009), _x(Vector3(0, 0.1, -0.128)), Color(0.1, 0.1, 0.1), Kit.METAL, 0.2, 0.2, 8, 4)
	# right: holster with pistol
	b.sq(Vector3(0.028, 0.07, 0.045), _x(Vector3(0.19, 0.02, 0.0), Vector3(0, 0, 0.08)), Color(0.06, 0.06, 0.06), Kit.NYLON, 0.3, 0.3, 10, 6)
	b.sq(Vector3(0.015, 0.032, 0.02), _x(Vector3(0.188, 0.105, 0.012), Vector3(0.3, 0, 0)), Color(0.05, 0.05, 0.05), Kit.METAL, 0.3, 0.3, 8, 4)
	# left: pistol mags and dump pouch; rear: IFAK
	var kit2: Color = p["kit2"]
	for i in 2:
		b.sq(Vector3(0.022, 0.045, 0.018), _x(Vector3(-0.175, 0.07, -0.06 + i * 0.045)), kit2, Kit.NYLON, 0.25, 0.3, 8, 5)
	b.sq(Vector3(0.05, 0.07, 0.035), _x(Vector3(-0.13, 0.03, 0.125), Vector3(0, 0.5, 0)), kit, Kit.NYLON, 0.45, 0.5, 10, 6)
	b.sq(Vector3(0.07, 0.045, 0.032), _x(Vector3(0.05, 0.085, 0.14)), kit2, Kit.NYLON, 0.25, 0.3, 10, 6)
	if b.lod == 0:
		# red cross tab on the IFAK
		b.sq(Vector3(0.012, 0.012, 0.003), _x(Vector3(0.05, 0.09, 0.173)), Color(0.45, 0.06, 0.05), Kit.CLOTH, 0.2, 0.2, 6, 4)


static func _torso(b: B, p: Dictionary) -> void:
	var u: Color = p["uniform"]
	var kit: Color = p["kit"]
	var kit2: Color = p["kit2"]
	# body
	b.loft([
		[Vector3(0, 0.96, 0.0), 0.145, 0.105], [Vector3(0, 1.05, 0.0), 0.15, 0.108],
		[Vector3(0, 1.15, -0.005), 0.158, 0.112], [Vector3(0, 1.26, -0.01), 0.172, 0.118],
		[Vector3(0, 1.36, -0.01), 0.185, 0.12], [Vector3(0, 1.44, 0.0), 0.19, 0.112],
		[Vector3(0, 1.50, 0.005), 0.165, 0.1], [Vector3(0, 1.555, 0.01), 0.1, 0.075],
		[Vector3(0, 1.6, 0.01), 0.058, 0.056],
	], Transform3D.IDENTITY, u, Kit.CAMO, 18)
	for sx in [-1.0, 1.0]:
		b.sq(Vector3(0.062, 0.068, 0.066), _x(Vector3(0.19 * sx, 1.462, 0.0)), u, Kit.CAMO, 1.0, 1.0, 12, 8)   # deltoid
	# shirt collar up around the hood
	b.loft([[Vector3(0, 1.53, 0.008), 0.095, 0.085], [Vector3(0, 1.58, 0.01), 0.083, 0.08],
		[Vector3(0, 1.615, 0.012), 0.08, 0.077]], Transform3D.IDENTITY, _dk(u, 0.95), Kit.CAMO, 14, false, false)
	# plate carrier: front and back plate bags, cummerbund, shoulder straps
	b.sq(Vector3(0.155, 0.165, 0.032), _x(Vector3(0, 1.33, -0.124)), kit, Kit.NYLON, 0.22, 0.3, 14, 8)
	b.sq(Vector3(0.155, 0.175, 0.03), _x(Vector3(0, 1.34, 0.124)), kit, Kit.NYLON, 0.22, 0.3, 14, 8)
	b.loft([[Vector3(0, 1.155, 0), 0.172, 0.122], [Vector3(0, 1.165, 0), 0.184, 0.134],
		[Vector3(0, 1.27, 0), 0.188, 0.135], [Vector3(0, 1.28, 0), 0.178, 0.126]],
		Transform3D.IDENTITY, kit, Kit.NYLON, 20, false, false)
	for sx in [-1.0, 1.0]:
		b.sq(Vector3(0.045, 0.02, 0.135), _x(Vector3(0.112 * sx, 1.52, 0.0), Vector3(0, 0, -0.18 * sx)), kit, Kit.NYLON, 0.3, 0.4, 10, 5)
	if b.lod == 0:
		# MOLLE rows on the back plate and cummerbund
		for i in 4:
			b.sq(Vector3(0.14, 0.007, 0.005), _x(Vector3(0, 1.235 + i * 0.05, 0.156)), _dk(kit, 0.8), Kit.NYLON, 0.2, 0.2, 6, 3)
		for sx in [-1.0, 1.0]:
			for i in 2:
				b.sq(Vector3(0.006, 0.006, 0.07), _x(Vector3(0.189 * sx, 1.2 + i * 0.045, 0.02)), _dk(kit, 0.8), Kit.NYLON, 0.2, 0.2, 6, 3)
	# front: triple rifle-mag pouch with flaps, admin pouch with ID patch
	for i in 3:
		var x := (i - 1) * 0.088
		b.sq(Vector3(0.038, 0.062, 0.03), _x(Vector3(x, 1.235, -0.176)), kit2, Kit.NYLON, 0.25, 0.3, 10, 6)
		if b.lod == 0:
			b.sq(Vector3(0.041, 0.02, 0.033), _x(Vector3(x, 1.298, -0.177)), _dk(kit2, 1.15), Kit.NYLON, 0.3, 0.3, 10, 5)
			b.sq(Vector3(0.01, 0.006, 0.004), _x(Vector3(x, 1.285, -0.211)), Color(0.05, 0.05, 0.05), Kit.METAL, 0.3, 0.3, 6, 3)
	b.sq(Vector3(0.08, 0.045, 0.022), _x(Vector3(0, 1.40, -0.163)), kit, Kit.NYLON, 0.25, 0.3, 10, 6)
	if b.lod == 0:
		b.sq(Vector3(0.036, 0.022, 0.004), _x(Vector3(0.03, 1.405, -0.186)), Color(0.16, 0.19, 0.15), Kit.CLOTH, 0.2, 0.2, 6, 3)
		b.sq(Vector3(0.022, 0.014, 0.004), _x(Vector3(-0.045, 1.41, -0.186)), Color(0.05, 0.05, 0.05), Kit.CLOTH, 0.2, 0.2, 6, 3)
	# right side: two frags; left back: radio with a stub antenna
	for i in 2:
		b.sq(Vector3(0.032, 0.036, 0.032), _x(Vector3(0.198, 1.2, -0.075 + i * 0.07)), kit2, Kit.NYLON, 0.5, 1.0, 10, 6)
		if b.lod == 0:
			b.cyl(Vector3(0.198, 1.235, -0.075 + i * 0.07), Vector3(0.198, 1.262, -0.075 + i * 0.07), 0.009, 0.007, Color(0.2, 0.21, 0.18), Kit.METAL, 6)
	b.sq(Vector3(0.034, 0.075, 0.032), _x(Vector3(-0.163, 1.33, 0.15)), kit2, Kit.NYLON, 0.25, 0.3, 10, 6)
	b.cyl(Vector3(-0.17, 1.4, 0.16), Vector3(-0.19, 1.53, 0.19), 0.006, 0.004, Color(0.05, 0.05, 0.05), Kit.METAL, 6)
	# assault pack: body, front pocket, compression straps, lid, grab handle
	var pk: Color = p["pack"]
	b.sq(Vector3(0.132, 0.175, 0.072), _x(Vector3(0, 1.33, 0.228)), pk, Kit.CLOTH, 0.3, 0.35, 14, 8)
	b.sq(Vector3(0.112, 0.08, 0.026), _x(Vector3(0, 1.245, 0.302)), _dk(pk, 0.9), Kit.CLOTH, 0.3, 0.35, 12, 6)
	b.sq(Vector3(0.128, 0.03, 0.078), _x(Vector3(0, 1.495, 0.228)), _dk(pk, 0.92), Kit.CLOTH, 0.35, 0.4, 12, 5)
	if b.lod == 0:
		for sx in [-1.0, 1.0]:
			b.sq(Vector3(0.012, 0.17, 0.004), _x(Vector3(0.085 * sx, 1.33, 0.302)), _dk(pk, 0.7), Kit.NYLON, 0.2, 0.2, 6, 4)
			b.sq(Vector3(0.004, 0.012, 0.07), _x(Vector3(0.134 * sx, 1.27, 0.228)), _dk(pk, 0.7), Kit.NYLON, 0.2, 0.2, 6, 3)
			b.sq(Vector3(0.004, 0.012, 0.07), _x(Vector3(0.134 * sx, 1.4, 0.228)), _dk(pk, 0.7), Kit.NYLON, 0.2, 0.2, 6, 3)
		b.tube([Vector3(-0.04, 1.52, 0.2), Vector3(-0.03, 1.545, 0.21), Vector3(0.03, 1.545, 0.21), Vector3(0.04, 1.52, 0.2)], 0.007, _dk(pk, 0.7), Kit.NYLON, 6)
		# hydration tube over the right shoulder to the chest
		b.tube([Vector3(0.07, 1.51, 0.17), Vector3(0.12, 1.555, 0.06), Vector3(0.13, 1.55, -0.05),
			Vector3(0.12, 1.49, -0.14), Vector3(0.1, 1.43, -0.168)], 0.0075, Color(0.06, 0.06, 0.06), Kit.RUBBER, 6)


static func _head(b: B, p: Dictionary) -> void:
	var hood: Color = p["hood"]
	var mask: Color = p["mask"]
	# balaclava / hood over head and neck
	b.loft([[Vector3(0, -0.1, 0.012), 0.075, 0.072], [Vector3(0, -0.05, 0.006), 0.068, 0.066],
		[Vector3(0, -0.005, 0.0), 0.07, 0.074]], Transform3D.IDENTITY, hood, Kit.CLOTH, 12, false, false)
	b.sq(Vector3(0.088, 0.112, 0.1), _x(Vector3(0, 0.075, 0.008)), hood, Kit.CLOTH, 1.0, 1.0, 16, 10)
	# gas mask: face piece, seal rim, chin cup
	b.sq(Vector3(0.079, 0.088, 0.058), _x(Vector3(0, 0.058, -0.06)), mask, Kit.RUBBER, 0.85, 0.8, 16, 10)
	b.sq(Vector3(0.086, 0.097, 0.026), _x(Vector3(0, 0.062, -0.045)), _dk(mask, 1.2), Kit.RUBBER, 0.6, 0.6, 16, 6)
	b.sq(Vector3(0.056, 0.04, 0.048), _x(Vector3(0, 0.005, -0.08)), mask, Kit.RUBBER, 0.8, 0.8, 12, 6)
	# eye lenses with rims, angled out a little
	for sx in [-1.0, 1.0]:
		var rot := Vector3(0.08, -0.28 * sx, 0)
		b.sq(Vector3(0.033, 0.031, 0.009), _x(Vector3(0.036 * sx, 0.09, -0.107), rot), Color(0.09, 0.09, 0.09), Kit.METAL, 1.0, 1.0, 14, 5)
		b.sq(Vector3(0.027, 0.025, 0.007), _x(Vector3(0.036 * sx, 0.09, -0.112), rot), p["lens"], Kit.GLASS, 1.0, 1.0, 14, 5)
	# filter canister on the left cheek, exhale valve in front
	var fa := Vector3(-0.035, 0.02, -0.105)
	var fb := Vector3(-0.065, -0.002, -0.148)
	b.cyl(fa, fb, 0.024, 0.029, p["filter"], Kit.METAL, 16)
	if b.lod == 0:
		b.cyl(fb, fb + (fb - fa).normalized() * 0.006, 0.026, 0.023, _dk(p["filter"], 0.45), Kit.METAL, 16)
		b.cyl(fa + (fb - fa) * 0.35, fa + (fb - fa) * 0.45, 0.031, 0.031, _dk(p["filter"], 0.7), Kit.METAL, 16)
	b.cyl(Vector3(0.008, 0.012, -0.112), Vector3(0.012, 0.0, -0.138), 0.023, 0.02, _dk(mask, 1.3), Kit.RUBBER, 12)
	if b.lod == 0:
		b.cyl(Vector3(0.012, 0.0, -0.138), Vector3(0.013, -0.003, -0.142), 0.018, 0.016, Color(0.12, 0.12, 0.12), Kit.METAL, 12)
		# head harness straps, laid on the hood's surface from the mask edge
		# round to the back of the head
		for sx in [-1.0, 1.0]:
			for el in [0.42, -0.2]:
				var pts := []
				for k in 5:
					var az := deg_to_rad(lerpf(52.0, 172.0, k / 4.0))
					pts.append(Vector3(0, 0.075, 0.008) + Vector3(sin(az) * cos(el) * 0.094 * sx, sin(el) * 0.118, -cos(az) * cos(el) * 0.106))
				b.tube(pts, 0.0055, mask, Kit.RUBBER, 5)
	# headset ear cups (visible under the high-cut helmet)
	for sx in [-1.0, 1.0]:
		b.sq(Vector3(0.022, 0.038, 0.032), _x(Vector3(0.095 * sx, 0.075, 0.008)), Color(0.07, 0.07, 0.07), Kit.RUBBER, 0.5, 0.6, 10, 6)
	# high-cut ballistic helmet with a fabric cover
	var hc: Color = p["helmet"]
	var vmin := func(u: float) -> float:
		var s := sin(u)
		return lerpf(0.34, 0.14, s * s) if s < 0.0 else lerpf(0.34, -0.3, s * s)
	b.shell(Vector3(0.113, 0.128, 0.126), 0.01, _x(Vector3(0, 0.098, 0.01)), hc, Kit.CLOTH, vmin, 0.85, 0.95, 24, 9)
	# NVG shroud on the front, ARC rails along the sides, velcro patch on
	# top, counterweight / battery pouch at the back
	b.sq(Vector3(0.027, 0.02, 0.008), _x(Vector3(0, 0.152, -0.115), Vector3(-0.42, 0, 0)), Color(0.08, 0.08, 0.08), Kit.METAL, 0.3, 0.3, 8, 4)
	for sx in [-1.0, 1.0]:
		b.sq(Vector3(0.005, 0.011, 0.062), _x(Vector3(0.106 * sx, 0.158, 0.01), Vector3(0, 0, -0.32 * sx)), Color(0.07, 0.07, 0.07), Kit.METAL, 0.25, 0.25, 8, 4)
	if b.lod == 0:
		b.sq(Vector3(0.035, 0.005, 0.03), _x(Vector3(0, 0.222, 0.012)), _dk(hc, 0.85), Kit.CLOTH, 0.2, 0.2, 6, 3)
		b.sq(Vector3(0.042, 0.025, 0.016), _x(Vector3(0, 0.115, 0.13), Vector3(-0.3, 0, 0)), p["kit"], Kit.NYLON, 0.3, 0.3, 8, 4)


static func _upper_arm(b: B, p: Dictionary, s: String) -> void:
	var sx := 1.0 if s == "R" else -1.0
	var u: Color = p["uniform"]
	b.loft([
		[Vector3(0, 0.03, 0), 0.066, 0.068], [Vector3(0, -0.05, 0.0), 0.062, 0.064],
		[Vector3(0.006 * sx, -0.15, 0), 0.056, 0.053], [Vector3(0, -0.24, 0), 0.048, 0.047],
		[Vector3(0, -0.32, 0), 0.044, 0.043],
	], Transform3D.IDENTITY, u, Kit.CAMO, 12)
	# sleeve pocket with flag patch on the outside (+Z)
	b.sq(Vector3(0.036, 0.046, 0.008), _x(Vector3(0, -0.09, 0.059)), _dk(u, 0.9), Kit.CAMO, 0.3, 0.3, 8, 5)
	if b.lod == 0:
		b.sq(Vector3(0.028, 0.019, 0.003), _x(Vector3(0, -0.08, 0.068)), Color(0.15, 0.17, 0.14), Kit.CLOTH, 0.2, 0.2, 6, 3)
	if p["armband"] != null:
		b.loft([[Vector3(0, -0.125, 0), 0.063, 0.062], [Vector3(0, -0.18, 0), 0.059, 0.057]],
			Transform3D.IDENTITY, p["armband"], Kit.CLOTH, 12, false, false)


static func _forearm(b: B, p: Dictionary, s: String) -> void:
	var sx := 1.0 if s == "R" else -1.0
	var u: Color = p["uniform"]
	var g: Color = p["gloves"]
	var f := 0.28      # forearm length (soldier_model.FOREARM)
	b.loft([
		[Vector3(0, 0.025, 0), 0.046, 0.046], [Vector3(0.004 * sx, -0.05, 0), 0.05, 0.046],
		[Vector3(0, -0.15, 0), 0.043, 0.04], [Vector3(0, -0.22, 0), 0.038, 0.035],
	], Transform3D.IDENTITY, u, Kit.CAMO, 12)
	# glove gauntlet, hand, curled fingers, thumb, knuckle armour
	b.loft([[Vector3(0, -0.215, 0), 0.04, 0.037], [Vector3(0, -0.25, 0), 0.037, 0.033],
		[Vector3(0, -f + 0.005, 0), 0.032, 0.026]], Transform3D.IDENTITY, g, Kit.RUBBER, 10, false, false)
	b.sq(Vector3(0.042, 0.045, 0.019), _x(Vector3(0, -f - 0.04, -0.003)), g, Kit.RUBBER, 0.5, 0.6, 10, 6)
	b.sq(Vector3(0.04, 0.028, 0.02), _x(Vector3(0, -f - 0.092, -0.016), Vector3(0, 0, 0)), g, Kit.RUBBER, 0.55, 0.6, 10, 6)
	b.sq(Vector3(0.012, 0.03, 0.012), _x(Vector3(0.035 * sx, -f - 0.05, -0.022), Vector3(0, 0, 0.5 * sx)), g, Kit.RUBBER, 0.7, 0.8, 8, 5)
	if b.lod == 0:
		b.sq(Vector3(0.036, 0.013, 0.008), _x(Vector3(0, -f - 0.075, 0.017)), _dk(g, 1.6), Kit.RUBBER, 0.4, 0.5, 8, 4)
	# elbow pad on the back of the elbow
	b.sq(Vector3(0.018, 0.045, 0.04), _x(Vector3(-0.042 * sx, -0.0, 0.0)), p["pads"], Kit.RUBBER, 0.6, 0.7, 10, 6)


static func _thigh(b: B, p: Dictionary, s: String) -> void:
	var sx := 1.0 if s == "R" else -1.0
	var u: Color = p["uniform"]
	b.loft([
		[Vector3(0, 0.06, 0), 0.088, 0.085], [Vector3(0, -0.06, 0), 0.086, 0.083],
		[Vector3(0, -0.18, 0.005), 0.077, 0.075], [Vector3(0, -0.3, 0.008), 0.066, 0.066],
		[Vector3(0, -0.4, 0.005), 0.057, 0.058], [Vector3(0, -0.46, 0), 0.052, 0.055],
	], Transform3D.IDENTITY, u, Kit.CAMO, 14)
	# cargo pocket and flap on the outside of the thigh (outward = -X * side)
	b.sq(Vector3(0.012, 0.064, 0.05), _x(Vector3(-0.073 * sx, -0.21, 0.004)), _dk(u, 0.93), Kit.CAMO, 0.3, 0.3, 8, 5)
	if b.lod == 0:
		b.sq(Vector3(0.014, 0.018, 0.052), _x(Vector3(-0.077 * sx, -0.145, 0.004)), _dk(u, 1.05), Kit.CAMO, 0.3, 0.3, 8, 4)


static func _shin(b: B, p: Dictionary, s: String) -> void:
	var u: Color = p["uniform"]
	var bt: Color = p["boots"]
	b.loft([
		[Vector3(0, 0.035, 0), 0.056, 0.058], [Vector3(0, -0.07, -0.008), 0.056, 0.064],
		[Vector3(0, -0.18, -0.005), 0.049, 0.055], [Vector3(0, -0.29, 0), 0.046, 0.048],
		[Vector3(0, -0.315, 0), 0.052, 0.056],
	], Transform3D.IDENTITY, u, Kit.CAMO, 12)
	# boot upper to the ankle, laces
	b.loft([[Vector3(0, -0.3, 0), 0.047, 0.05], [Vector3(0, -0.36, 0.002), 0.05, 0.054],
		[Vector3(0, -0.44, 0.004), 0.05, 0.056]], Transform3D.IDENTITY, bt, Kit.RUBBER, 12, false, false)
	if b.lod == 0:
		b.sq(Vector3(0.022, 0.05, 0.006), _x(Vector3(0, -0.385, 0.054)), _dk(bt, 0.6), Kit.NYLON, 0.2, 0.3, 6, 4)
	# knee pad on the front (+Z) with a hard cap
	b.sq(Vector3(0.052, 0.064, 0.03), _x(Vector3(0, -0.005, 0.052)), p["pads"], Kit.RUBBER, 0.5, 0.6, 12, 6)
	if b.lod == 0:
		b.sq(Vector3(0.036, 0.042, 0.012), _x(Vector3(0, 0.0, 0.078)), _dk(p["pads"], 1.4), Kit.RUBBER, 0.5, 0.6, 10, 5)


static func _foot(b: B, p: Dictionary) -> void:
	var bt: Color = p["boots"]
	b.sq(Vector3(0.048, 0.046, 0.108), _x(Vector3(0, -0.035, -0.052)), bt, Kit.RUBBER, 0.45, 0.5, 12, 6)
	b.sq(Vector3(0.047, 0.032, 0.05), _x(Vector3(0, -0.05, -0.128)), _dk(bt, 1.1), Kit.RUBBER, 0.5, 0.6, 10, 5)
	b.sq(Vector3(0.046, 0.04, 0.042), _x(Vector3(0, -0.045, 0.036)), bt, Kit.RUBBER, 0.45, 0.55, 10, 5)
	# sole: bottom face exactly 0.0875 below the ankle (the rig relies on it)
	b.sq(Vector3(0.054, 0.014, 0.132), _x(Vector3(0, -0.0735, -0.05)), Color(0.035, 0.035, 0.035), Kit.RUBBER, 0.2, 0.4, 12, 4)


# ---------------------------------------------------------------- weapons

## Handguard length per weapon (also used for the muzzle position).
static func front_length(p: Dictionary) -> float:
	if p["weapon"] == "ak":
		return 0.0
	return 0.3 if p["role"] == "anti_armor" else 0.4


## Muzzle position in rifle space.
static func muzzle_pos(p: Dictionary) -> Vector3:
	if p["weapon"] == "ak":
		return Vector3(0, 0.04, -0.79)
	return Vector3(0, 0.055, -0.155 - front_length(p) - 0.175)


static func _rifle(b: B, p: Dictionary) -> void:
	if p["weapon"] == "ak":
		_ak(b, p)
	else:
		_m4(b, p)


static func _m4(b: B, p: Dictionary) -> void:
	var m := Color(0.06, 0.06, 0.065)
	var poly := Color(0.08, 0.08, 0.075)
	var f := front_length(p)
	b.sq(Vector3(0.022, 0.032, 0.085), _x(Vector3(0, 0.012, -0.045)), m, Kit.METAL, 0.15, 0.2, 8, 5)        # lower
	b.sq(Vector3(0.021, 0.024, 0.095), _x(Vector3(0, 0.062, -0.06)), m, Kit.METAL, 0.15, 0.2, 8, 5)         # upper
	b.sq(Vector3(0.013, 0.006, 0.16), _x(Vector3(0, 0.091, -0.13)), m, Kit.METAL, 0.15, 0.15, 6, 3)         # top rail
	b.sq(Vector3(0.02, 0.03, 0.03), _x(Vector3(0, -0.02, -0.1)), m, Kit.METAL, 0.2, 0.2, 8, 4)              # mag well
	# curved magazine
	for i in 3:
		b.sq(Vector3(0.016, 0.036, 0.031), _x(Vector3(0, -0.07 - i * 0.058, -0.105 - i * i * 0.008), Vector3(0.08 + i * 0.14, 0, 0)), poly, Kit.METAL, 0.2, 0.25, 8, 4)
	b.sq(Vector3(0.015, 0.046, 0.022), _x(Vector3(0, -0.042, 0.014), Vector3(0.32, 0, 0)), poly, Kit.METAL, 0.3, 0.4, 8, 5)  # grip
	b.cyl(Vector3(0, 0.055, 0.035), Vector3(0, 0.055, 0.22), 0.015, 0.015, m, Kit.METAL, 10)                # buffer tube
	b.sq(Vector3(0.022, 0.042, 0.075), _x(Vector3(0, 0.035, 0.22)), poly, Kit.METAL, 0.3, 0.35, 10, 6)       # stock
	b.sq(Vector3(0.024, 0.058, 0.012), _x(Vector3(0, 0.012, 0.302)), Color(0.04, 0.04, 0.04), Kit.RUBBER, 0.3, 0.4, 8, 4)
	b.sq(Vector3(0.027, 0.028, f * 0.5), _x(Vector3(0, 0.055, -0.155 - f * 0.5)), poly, Kit.METAL, 0.35, 0.4, 10, 5)   # handguard
	b.cyl(Vector3(0, 0.055, -0.155 - f), Vector3(0, 0.055, -0.155 - f - 0.12), 0.0095, 0.0095, m, Kit.METAL, 8)        # barrel
	b.cyl(Vector3(0, 0.055, -0.155 - f - 0.115), Vector3(0, 0.055, -0.155 - f - 0.175), 0.014, 0.013, Color(0.04, 0.04, 0.04), Kit.METAL, 10)  # muzzle device
	# holographic sight
	b.sq(Vector3(0.018, 0.012, 0.04), _x(Vector3(0, 0.105, -0.09)), m, Kit.METAL, 0.2, 0.2, 6, 3)
	if p["role"] == "grenadier":
		# magnified optic instead
		b.cyl(Vector3(0, 0.135, -0.02), Vector3(0, 0.135, -0.17), 0.021, 0.024, m, Kit.METAL, 12)
		b.sq(Vector3(0.018, 0.016, 0.003), _x(Vector3(0, 0.135, -0.172)), p["lens"], Kit.GLASS, 1.0, 1.0, 10, 4)
	else:
		for sx in [-1.0, 1.0]:
			b.sq(Vector3(0.004, 0.026, 0.036), _x(Vector3(0.019 * sx, 0.13, -0.09)), m, Kit.METAL, 0.2, 0.2, 6, 3)
		b.sq(Vector3(0.023, 0.004, 0.036), _x(Vector3(0, 0.157, -0.09)), m, Kit.METAL, 0.2, 0.2, 6, 3)
		b.sq(Vector3(0.016, 0.021, 0.002), _x(Vector3(0, 0.13, -0.112)), Color(0.15, 0.25, 0.2), Kit.GLASS, 0.3, 0.3, 6, 3)
		b.sq(Vector3(0.02, 0.016, 0.02), _x(Vector3(0, 0.115, -0.04)), m, Kit.METAL, 0.2, 0.2, 6, 3)
	if b.lod == 0:
		# rail teeth, charging handle, ejection port, M-LOK slots, trigger guard
		for i in 13:
			b.sq(Vector3(0.0135, 0.003, 0.0035), _x(Vector3(0, 0.098, -0.27 + i * 0.024)), m, Kit.METAL, 0.2, 0.2, 4, 2)
		b.sq(Vector3(0.018, 0.005, 0.012), _x(Vector3(0, 0.077, 0.04)), m, Kit.METAL, 0.2, 0.2, 6, 3)
		b.sq(Vector3(0.002, 0.012, 0.03), _x(Vector3(0.022, 0.06, -0.05)), Color(0.1, 0.1, 0.1), Kit.METAL, 0.2, 0.2, 4, 3)
		for sx in [-1.0, 1.0]:
			for i in int(f / 0.09):
				b.sq(Vector3(0.002, 0.006, 0.018), _x(Vector3(0.027 * sx, 0.055, -0.2 - i * 0.08)), Color(0.03, 0.03, 0.03), Kit.METAL, 0.2, 0.2, 4, 3)
		b.sq(Vector3(0.003, 0.003, 0.03), _x(Vector3(0, -0.022, -0.028)), m, Kit.METAL, 0.2, 0.2, 4, 3)
	if p["role"] == "grenadier":
		b.cyl(Vector3(0, -0.012, -0.17), Vector3(0, -0.012, -0.47), 0.023, 0.023, Color(0.07, 0.075, 0.07), Kit.METAL, 12)
		b.sq(Vector3(0.012, 0.022, 0.024), _x(Vector3(0, -0.035, -0.16)), m, Kit.METAL, 0.2, 0.3, 6, 4)


static func _ak(b: B, p: Dictionary) -> void:
	var m := Color(0.055, 0.055, 0.06)
	var wood := Color(0.3, 0.17, 0.08)
	b.sq(Vector3(0.022, 0.034, 0.13), _x(Vector3(0, 0.035, -0.06)), m, Kit.METAL, 0.15, 0.2, 8, 5)         # receiver
	b.sq(Vector3(0.02, 0.013, 0.12), _x(Vector3(0, 0.068, -0.07)), m, Kit.METAL, 0.4, 0.5, 8, 5)            # dust cover
	b.sq(Vector3(0.018, 0.04, 0.12), _x(Vector3(0, 0.0, 0.19), Vector3(-0.14, 0, 0)), wood, Kit.RUBBER, 0.3, 0.35, 10, 6)   # stock
	b.sq(Vector3(0.02, 0.055, 0.012), _x(Vector3(0, -0.012, 0.305), Vector3(-0.14, 0, 0)), Color(0.05, 0.05, 0.05), Kit.METAL, 0.3, 0.4, 8, 4)
	b.sq(Vector3(0.015, 0.045, 0.02), _x(Vector3(0, -0.035, 0.02), Vector3(0.35, 0, 0)), wood, Kit.RUBBER, 0.35, 0.4, 8, 5)  # grip
	for i in 4:
		b.sq(Vector3(0.017, 0.034, 0.03), _x(Vector3(0, -0.045 - i * 0.052, -0.11 - i * 0.03 - i * i * 0.006), Vector3(0.15 + i * 0.2, 0, 0)), Color(0.07, 0.06, 0.05), Kit.METAL, 0.2, 0.25, 8, 4)
	b.sq(Vector3(0.026, 0.026, 0.13), _x(Vector3(0, 0.03, -0.32)), wood, Kit.RUBBER, 0.4, 0.5, 10, 5)      # lower handguard
	b.sq(Vector3(0.019, 0.015, 0.12), _x(Vector3(0, 0.068, -0.3)), wood, Kit.RUBBER, 0.4, 0.5, 8, 4)       # gas tube cover
	b.cyl(Vector3(0, 0.04, -0.45), Vector3(0, 0.04, -0.74), 0.0105, 0.0105, m, Kit.METAL, 8)                # barrel
	b.cyl(Vector3(0, 0.04, -0.74), Vector3(0, 0.04, -0.79), 0.015, 0.014, m, Kit.METAL, 10)                 # muzzle brake
	b.sq(Vector3(0.008, 0.032, 0.012), _x(Vector3(0, 0.068, -0.66)), m, Kit.METAL, 0.2, 0.2, 6, 3)          # front sight
	b.sq(Vector3(0.016, 0.018, 0.022), _x(Vector3(0, 0.062, -0.45)), m, Kit.METAL, 0.2, 0.2, 6, 3)          # gas block
	if b.lod == 0:
		b.sq(Vector3(0.012, 0.008, 0.02), _x(Vector3(0, 0.08, -0.17)), m, Kit.METAL, 0.2, 0.2, 6, 3)        # rear sight
		b.sq(Vector3(0.004, 0.008, 0.03), _x(Vector3(0.024, 0.04, -0.04)), m, Kit.METAL, 0.2, 0.2, 4, 3)    # charging handle
		b.sq(Vector3(0.003, 0.003, 0.03), _x(Vector3(0, -0.022, -0.028)), m, Kit.METAL, 0.2, 0.2, 4, 3)


## Recoilless rifle carried by the rocketman (tube space: -Z = muzzle).
static func _launcher(b: B, p: Dictionary) -> void:
	var t: Color = _dk(p["kit2"], 1.0)
	b.cyl(Vector3(0, 0, 0.5), Vector3(0, 0, -0.5), 0.055, 0.055, t, Kit.METAL, 16)
	b.cyl(Vector3(0, 0, 0.62), Vector3(0, 0, 0.48), 0.075, 0.058, Color(0.06, 0.06, 0.06), Kit.METAL, 16)     # venturi
	b.cyl(Vector3(0, 0, -0.5), Vector3(0, 0, -0.58), 0.062, 0.062, Color(0.06, 0.06, 0.06), Kit.METAL, 16)    # muzzle ring
	b.sq(Vector3(0.022, 0.028, 0.06), _x(Vector3(-0.065, 0.03, -0.12)), Color(0.07, 0.07, 0.07), Kit.METAL, 0.25, 0.3, 8, 4)   # sight
	b.sq(Vector3(0.015, 0.05, 0.022), _x(Vector3(0, -0.085, -0.05), Vector3(0.25, 0, 0)), Color(0.06, 0.06, 0.06), Kit.METAL, 0.3, 0.4, 8, 4)  # grip
	b.sq(Vector3(0.04, 0.05, 0.08), _x(Vector3(0, -0.06, 0.18)), Color(0.08, 0.08, 0.08), Kit.RUBBER, 0.4, 0.5, 8, 5)  # shoulder pad
	if b.lod == 0:
		for z in [-0.35, 0.3]:
			b.cyl(Vector3(0, 0, z - 0.015), Vector3(0, 0, z + 0.015), 0.059, 0.059, _dk(t, 0.7), Kit.METAL, 16)  # bands
		b.tube([Vector3(0, 0.055, -0.2), Vector3(0, 0.1, -0.15), Vector3(0, 0.1, 0.05), Vector3(0, 0.055, 0.1)], 0.008, Color(0.06, 0.06, 0.06), Kit.METAL, 6)


## Launcher sling: over the left shoulder, across the chest (upper space).
static func _sling(b: B, p: Dictionary) -> void:
	var c := _dk(p["kit2"], 0.6)
	b.tube([Vector3(-0.15, 1.53, 0.08), Vector3(-0.13, 1.52, -0.11), Vector3(-0.03, 1.4, -0.205),
		Vector3(0.1, 1.24, -0.205), Vector3(0.19, 1.12, -0.12), Vector3(0.21, 1.08, 0.06)], 0.011, c, Kit.NYLON, 6)
