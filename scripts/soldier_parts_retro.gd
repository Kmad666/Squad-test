extends RefCounted
## RETRO soldier: a late-90s console-style version of the universal soldier.
## A few hundred faceted triangles, chunky proportions (broad shoulders, big
## gloves and boots, a slightly oversized helmet and mask), flat vertex
## colours, no textures. Same bones, spaces and palettes as the HD model
## (soldier_parts.gd), so every animation, pose and test carries over.
## Drawn with shaders/soldier_retro.gdshader (vertex snapping, vertex lighting).

const Kit = preload("res://scripts/model_kit.gd")
const Parts = preload("res://scripts/soldier_parts.gd")
const B = Kit.Builder

static var _cache := {}


static func get_mesh(part: String, p: Dictionary, extra := "") -> ArrayMesh:
	var key := "%s|%s|%s" % [part, p["key"], extra]
	if not _cache.has(key):
		var b := B.new(0, true)
		b.bake = 1.0
		b.brighten = 1.3
		match part:
			"hips": _hips(b, p)
			"torso": _torso(b, p)
			"head": _head(b, p)
			"upper_arm": _upper_arm(b, p, extra)
			"forearm": _forearm(b, p, extra)
			"thigh": _thigh(b, p, extra)
			"shin": _shin(b, p)
			"foot": _foot(b, p)
			"rifle": _rifle(b, p)
			"launcher": _launcher(b, p)
			"sling": _sling(b, p)
		_cache[key] = b.build()
	return _cache[key]


static func _x(pos: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return Kit.xf(pos, rot)


static func _dk(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f)


const GOGGLE_RED := Color(0.9, 0.06, 0.03)
## Rotations that put one edge of a 3-sided loft forward (+Z) or outward.
const POINT_FWD := PI / 2.0


## Triangular-prism limb: a 3-sided loft through [centre, radius] rings,
## one ridge pointing along +Z (forward on legs, outward on arms).
static func _prism(b: B, rings: Array, c: Color, id: float) -> void:
	var rr := []
	for r in rings:
		rr.append([r[0], r[1], r[1]])
	b.loft(rr, _x(Vector3.ZERO, Vector3(0, POINT_FWD, 0)), c, id, 3)


static func _hips(b: B, p: Dictionary) -> void:
	var u: Color = p["uniform"]
	# narrow waist and hips
	b.tbox(Vector2(0.095, 0.08), Vector2(0.13, 0.095), 0.26, _x(Vector3(0, -0.01, 0)), u, Kit.CAMO)
	b.box(Vector3(0.14, 0.024, 0.105), _x(Vector3(0, 0.1, 0)), Color(0.06, 0.06, 0.06), Kit.NYLON)
	b.box(Vector3(0.03, 0.02, 0.01), _x(Vector3(0, 0.1, -0.11)), Color(0.35, 0.35, 0.33), Kit.METAL)
	b.box(Vector3(0.026, 0.05, 0.032), _x(Vector3(0.155, 0.045, 0.0)), Color(0.06, 0.06, 0.06), Kit.NYLON)   # holster


static func _torso(b: B, p: Dictionary) -> void:
	var u: Color = p["uniform"]
	# jacket: heroic V, broad shoulders tapering to a narrow waist (6 facets)
	b.loft([
		[Vector3(0, 0.96, 0.0), 0.125, 0.095], [Vector3(0, 1.1, 0.0), 0.15, 0.108],
		[Vector3(0, 1.3, -0.01), 0.24, 0.135], [Vector3(0, 1.44, 0.0), 0.275, 0.13],
		[Vector3(0, 1.52, 0.01), 0.18, 0.1], [Vector3(0, 1.575, 0.01), 0.085, 0.075],
	], Transform3D.IDENTITY, u, Kit.CAMO, 6)
	# popped round collar
	b.collar(Vector2(0.095, 0.085), Vector2(0.125, 0.115), 1.52, 1.665, 0.018, 0.015, Transform3D.IDENTITY, _dk(u, 0.8), Kit.CAMO, 8)


static func _head(b: B, p: Dictionary) -> void:
	var hood: Color = p["hood"]
	# balaclava: faceted head and neck
	b.loft([[Vector3(0, -0.12, 0.01), 0.068, 0.066], [Vector3(0, 0.0, 0.01), 0.075, 0.075]],
		Transform3D.IDENTITY, hood, Kit.CLOTH, 6, false, false)
	b.loft([
		[Vector3(0, -0.01, 0.0), 0.075, 0.08], [Vector3(0, 0.04, -0.005), 0.095, 0.1],
		[Vector3(0, 0.13, 0.0), 0.1, 0.106], [Vector3(0, 0.2, 0.005), 0.074, 0.08],
		[Vector3(0, 0.228, 0.005), 0.03, 0.03],
	], Transform3D.IDENTITY, hood, Kit.CLOTH, 6)
	b.box(Vector3(0.035, 0.02, 0.012), _x(Vector3(0, 0.035, -0.1)), _dk(hood, 0.75), Kit.CLOTH)   # mouth panel
	# goggles: strap round the head, frames, glowing red lenses
	b.loft([[Vector3(0, 0.098, 0), 0.103, 0.108], [Vector3(0, 0.126, 0), 0.103, 0.108]],
		Transform3D.IDENTITY, Color(0.05, 0.05, 0.05), Kit.NYLON, 6, false, false)
	for sx in [-1.0, 1.0]:
		var rot := Vector3(0.05, -0.32 * sx, 0)
		b.box(Vector3(0.037, 0.027, 0.012), _x(Vector3(0.042 * sx, 0.112, -0.104), rot), Color(0.05, 0.05, 0.05), Kit.METAL)
		b.box(Vector3(0.03, 0.02, 0.008), _x(Vector3(0.043 * sx, 0.112, -0.113), rot), GOGGLE_RED, Kit.GLASS)
	b.box(Vector3(0.012, 0.012, 0.01), _x(Vector3(0, 0.112, -0.112)), Color(0.05, 0.05, 0.05), Kit.METAL)   # bridge


static func _upper_arm(b: B, p: Dictionary, s: String) -> void:
	var u: Color = p["uniform"]
	_prism(b, [[Vector3(0, 0.05, 0), 0.085], [Vector3(0, -0.12, 0), 0.092], [Vector3(0, -0.33, 0), 0.066]], u, Kit.CAMO)
	if p["armband"] != null:
		_prism(b, [[Vector3(0, -0.12, 0), 0.1], [Vector3(0, -0.19, 0), 0.094]], p["armband"], Kit.CLOTH)


static func _forearm(b: B, p: Dictionary, s: String) -> void:
	var sx := 1.0 if s == "R" else -1.0
	var u: Color = p["uniform"]
	var g: Color = p["gloves"]
	var f := 0.28
	_prism(b, [[Vector3(0, 0.03, 0), 0.075], [Vector3(0, -0.1, 0), 0.08], [Vector3(0, -0.235, 0), 0.056]], u, Kit.CAMO)
	b.tbox(Vector2(0.044, 0.044), Vector2(0.05, 0.05), 0.05, _x(Vector3(0, -0.245, 0)), g, Kit.RUBBER)        # glove cuff
	b.tbox(Vector2(0.052, 0.028), Vector2(0.047, 0.03), 0.11, _x(Vector3(0, -f - 0.05, -0.004)), g, Kit.RUBBER)  # big glove
	b.box(Vector3(0.015, 0.03, 0.016), _x(Vector3(0.048 * sx, -f - 0.04, -0.02), Vector3(0, 0, 0.4 * sx)), g, Kit.RUBBER)   # thumb


static func _thigh(b: B, p: Dictionary, s: String) -> void:
	# puffy trouser leg, ridge forward
	_prism(b, [[Vector3(0, 0.08, 0), 0.115], [Vector3(0, -0.16, 0.012), 0.135], [Vector3(0, -0.38, 0.01), 0.108], [Vector3(0, -0.47, 0), 0.088]], p["uniform"], Kit.CAMO)


static func _shin(b: B, p: Dictionary) -> void:
	# puffy lower leg gathered into a narrow boot that is thinnest at the top
	_prism(b, [[Vector3(0, 0.05, 0), 0.1], [Vector3(0, -0.12, 0.004), 0.118], [Vector3(0, -0.26, 0), 0.094], [Vector3(0, -0.315, 0), 0.06]], p["uniform"], Kit.CAMO)
	b.tbox(Vector2(0.05, 0.062), Vector2(0.034, 0.042), 0.14, _x(Vector3(0, -0.375, 0.004)), p["boots"], Kit.RUBBER)


static func _foot(b: B, p: Dictionary) -> void:
	var bt: Color = p["boots"]
	# narrow, long boot; sole bottom 0.0875 below the ankle, toe and heel
	# within the clearance the gait assumes
	b.box(Vector3(0.048, 0.042, 0.115), _x(Vector3(0, -0.042, -0.052)), bt, Kit.RUBBER)
	b.tbox(Vector2(0.048, 0.032), Vector2(0.042, 0.026), 0.05, _x(Vector3(0, -0.058, -0.148)), _dk(bt, 1.15), Kit.RUBBER)
	b.box(Vector3(0.052, 0.0125, 0.13), _x(Vector3(0, -0.075, -0.05)), Color(0.035, 0.035, 0.035), Kit.RUBBER)


static func _rifle(b: B, p: Dictionary) -> void:
	var m := Color(0.07, 0.07, 0.075)
	var mz: Vector3 = Parts.muzzle_pos(p)
	if p["weapon"] == "ak":
		var wood := Color(0.3, 0.17, 0.08)
		b.box(Vector3(0.026, 0.04, 0.13), _x(Vector3(0, 0.035, -0.06)), m, Kit.METAL)
		b.tbox(Vector2(0.022, 0.03), Vector2(0.024, 0.06), 0.24, _x(Vector3(0, 0.0, 0.19), Vector3(PI / 2 - 0.14, 0, 0)), wood, Kit.RUBBER)
		b.box(Vector3(0.02, 0.05, 0.024), _x(Vector3(0, -0.04, 0.02), Vector3(0.35, 0, 0)), wood, Kit.RUBBER)
		b.box(Vector3(0.02, 0.06, 0.034), _x(Vector3(0, -0.07, -0.12), Vector3(0.3, 0, 0)), Color(0.08, 0.07, 0.06), Kit.METAL)
		b.box(Vector3(0.02, 0.05, 0.034), _x(Vector3(0, -0.15, -0.17), Vector3(0.65, 0, 0)), Color(0.08, 0.07, 0.06), Kit.METAL)
		b.box(Vector3(0.03, 0.032, 0.13), _x(Vector3(0, 0.035, -0.32)), wood, Kit.RUBBER)
	else:
		var f: float = Parts.front_length(p)
		b.box(Vector3(0.027, 0.045, 0.12), _x(Vector3(0, 0.03, -0.05)), m, Kit.METAL)                      # receiver
		b.box(Vector3(0.025, 0.05, 0.085), _x(Vector3(0, 0.03, 0.22)), Color(0.09, 0.09, 0.09), Kit.METAL)  # stock
		b.box(Vector3(0.028, 0.062, 0.014), _x(Vector3(0, 0.01, 0.305)), Color(0.05, 0.05, 0.05), Kit.RUBBER)
		b.box(Vector3(0.02, 0.05, 0.024), _x(Vector3(0, -0.04, 0.015), Vector3(0.3, 0, 0)), Color(0.09, 0.09, 0.09), Kit.METAL)
		b.box(Vector3(0.019, 0.075, 0.032), _x(Vector3(0, -0.085, -0.11), Vector3(0.22, 0, 0)), Color(0.09, 0.09, 0.09), Kit.METAL)
		b.box(Vector3(0.032, 0.033, f * 0.5), _x(Vector3(0, 0.05, -0.17 - f * 0.5)), Color(0.09, 0.09, 0.09), Kit.METAL)
		b.box(Vector3(0.02, 0.026, 0.04), _x(Vector3(0, 0.105, -0.08)), m, Kit.METAL)                       # sight
		if p["role"] == "grenadier":
			b.cyl(Vector3(0, -0.012, -0.17), Vector3(0, -0.012, -0.47), 0.03, 0.03, Color(0.08, 0.085, 0.08), Kit.METAL, 6)
	b.cyl(Vector3(0, mz.y, mz.z + 0.42), mz, 0.013, 0.013, m, Kit.METAL, 5)                                  # barrel
	b.cyl(mz + Vector3(0, 0, 0.06), mz, 0.019, 0.019, Color(0.05, 0.05, 0.05), Kit.METAL, 5)                  # muzzle


static func _launcher(b: B, p: Dictionary) -> void:
	var t: Color = p["kit2"]
	b.cyl(Vector3(0, 0, 0.55), Vector3(0, 0, -0.55), 0.065, 0.065, t, Kit.METAL, 6)
	b.cyl(Vector3(0, 0, 0.62), Vector3(0, 0, 0.5), 0.085, 0.066, Color(0.07, 0.07, 0.07), Kit.METAL, 6)
	b.box(Vector3(0.025, 0.03, 0.06), _x(Vector3(-0.075, 0.035, -0.12)), Color(0.07, 0.07, 0.07), Kit.METAL)


static func _sling(b: B, p: Dictionary) -> void:
	b.tube([Vector3(-0.17, 1.53, 0.08), Vector3(-0.14, 1.52, -0.12), Vector3(0.0, 1.36, -0.225),
		Vector3(0.19, 1.13, -0.13), Vector3(0.23, 1.08, 0.06)], 0.013, _dk(p["kit2"], 0.6), Kit.NYLON, 4)
