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


static func _hips(b: B, p: Dictionary) -> void:
	var u: Color = p["uniform"]
	b.tbox(Vector2(0.115, 0.095), Vector2(0.185, 0.13), 0.28, _x(Vector3(0, -0.01, 0)), u, Kit.CAMO)
	b.box(Vector3(0.195, 0.03, 0.14), _x(Vector3(0, 0.1, 0)), p["kit"], Kit.NYLON)
	b.box(Vector3(0.035, 0.02, 0.01), _x(Vector3(0, 0.1, -0.145)), Color(0.12, 0.12, 0.12), Kit.METAL)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.035, 0.055, 0.045), _x(Vector3(0.205 * sx, 0.04, -0.01)), p["kit2"], Kit.NYLON)
	b.box(Vector3(0.07, 0.045, 0.035), _x(Vector3(0.0, 0.07, 0.165)), p["kit2"], Kit.NYLON)


static func _torso(b: B, p: Dictionary) -> void:
	var u: Color = p["uniform"]
	var kit: Color = p["kit"]
	# broad, chunky torso tapering to the waist
	b.tbox(Vector2(0.17, 0.12), Vector2(0.235, 0.14), 0.54, _x(Vector3(0, 1.23, 0)), u, Kit.CAMO)
	b.tbox(Vector2(0.17, 0.11), Vector2(0.085, 0.075), 0.1, _x(Vector3(0, 1.55, 0.005)), u, Kit.CAMO)
	for sx in [-1.0, 1.0]:
		b.tbox(Vector2(0.075, 0.08), Vector2(0.06, 0.07), 0.13, _x(Vector3(0.235 * sx, 1.45, 0)), _dk(u, 0.9), Kit.CAMO)   # shoulder pads
	# vest: front and back plates, mag pouches, shoulder straps
	b.tbox(Vector2(0.2, 0.03), Vector2(0.22, 0.03), 0.36, _x(Vector3(0, 1.32, -0.15)), kit, Kit.NYLON)
	b.tbox(Vector2(0.2, 0.03), Vector2(0.22, 0.03), 0.38, _x(Vector3(0, 1.33, 0.15)), kit, Kit.NYLON)
	for i in 3:
		b.box(Vector3(0.042, 0.055, 0.032), _x(Vector3((i - 1) * 0.095, 1.22, -0.205)), p["kit2"], Kit.NYLON)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.05, 0.022, 0.16), _x(Vector3(0.13 * sx, 1.515, 0)), kit, Kit.NYLON)
	b.box(Vector3(0.07, 0.04, 0.02), _x(Vector3(0, 1.4, -0.19)), _dk(kit, 1.3), Kit.NYLON)
	# pack with a rolled mat on top
	var pk: Color = p["pack"]
	b.tbox(Vector2(0.15, 0.075), Vector2(0.14, 0.07), 0.38, _x(Vector3(0, 1.32, 0.26)), pk, Kit.CLOTH)
	b.cyl(Vector3(-0.15, 1.54, 0.25), Vector3(0.15, 1.54, 0.25), 0.045, 0.045, _dk(pk, 0.75), Kit.CLOTH, 6)
	b.box(Vector3(0.11, 0.07, 0.025), _x(Vector3(0, 1.24, 0.345)), _dk(pk, 0.88), Kit.CLOTH)


static func _head(b: B, p: Dictionary) -> void:
	var hood: Color = p["hood"]
	var mask: Color = p["mask"]
	b.tbox(Vector2(0.075, 0.07), Vector2(0.08, 0.075), 0.12, _x(Vector3(0, -0.04, 0.01)), hood, Kit.CLOTH)    # neck
	b.tbox(Vector2(0.095, 0.1), Vector2(0.1, 0.105), 0.2, _x(Vector3(0, 0.09, 0.012)), hood, Kit.CLOTH)      # head
	# gas mask: a chunky front block, two big lenses, a filter canister on the chin
	b.tbox(Vector2(0.058, 0.04), Vector2(0.088, 0.04), 0.15, _x(Vector3(0, 0.055, -0.09)), mask, Kit.RUBBER, -0.012)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.036, 0.028, 0.008), _x(Vector3(0.045 * sx, 0.105, -0.133), Vector3(0.1, -0.25 * sx, 0)), Color(0.1, 0.1, 0.1), Kit.METAL)
		b.box(Vector3(0.03, 0.022, 0.006), _x(Vector3(0.045 * sx, 0.105, -0.139), Vector3(0.1, -0.25 * sx, 0)), p["lens"], Kit.GLASS)
	b.cyl(Vector3(0, 0.02, -0.125), Vector3(0, -0.015, -0.19), 0.042, 0.046, p["filter"], Kit.METAL, 6)
	b.cyl(Vector3(0, -0.015, -0.19), Vector3(0, -0.02, -0.198), 0.04, 0.036, _dk(p["filter"], 0.4), Kit.METAL, 6)
	# helmet: faceted dome, rim, NVG mount
	var hc: Color = p["helmet"]
	b.sq(Vector3(0.14, 0.135, 0.15), _x(Vector3(0, 0.125, 0.012)), hc, Kit.CLOTH, 1.0, 1.0, 8, 3, -0.12, PI / 2.0)
	b.box(Vector3(0.03, 0.022, 0.012), _x(Vector3(0, 0.19, -0.145), Vector3(-0.4, 0, 0)), Color(0.08, 0.08, 0.08), Kit.METAL)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.022, 0.04, 0.035), _x(Vector3(0.112 * sx, 0.08, 0.01)), Color(0.07, 0.07, 0.07), Kit.RUBBER)   # ear cups


static func _upper_arm(b: B, p: Dictionary, s: String) -> void:
	var u: Color = p["uniform"]
	b.tbox(Vector2(0.058, 0.058), Vector2(0.075, 0.075), 0.36, _x(Vector3(0, -0.14, 0)), u, Kit.CAMO)
	if p["armband"] != null:
		b.tbox(Vector2(0.066, 0.066), Vector2(0.07, 0.07), 0.06, _x(Vector3(0, -0.15, 0)), p["armband"], Kit.CLOTH)


static func _forearm(b: B, p: Dictionary, s: String) -> void:
	var sx := 1.0 if s == "R" else -1.0
	var u: Color = p["uniform"]
	var g: Color = p["gloves"]
	var f := 0.28
	b.tbox(Vector2(0.046, 0.044), Vector2(0.06, 0.06), 0.26, _x(Vector3(0, -0.11, 0)), u, Kit.CAMO)
	b.tbox(Vector2(0.05, 0.05), Vector2(0.058, 0.058), 0.05, _x(Vector3(0, -0.245, 0)), g, Kit.RUBBER)        # glove cuff
	b.tbox(Vector2(0.055, 0.03), Vector2(0.05, 0.032), 0.11, _x(Vector3(0, -f - 0.05, -0.004)), g, Kit.RUBBER)  # big glove
	b.box(Vector3(0.015, 0.03, 0.016), _x(Vector3(0.05 * sx, -f - 0.04, -0.02), Vector3(0, 0, 0.4 * sx)), g, Kit.RUBBER)   # thumb
	b.box(Vector3(0.022, 0.045, 0.04), _x(Vector3(-0.048 * sx, 0.0, 0)), p["pads"], Kit.RUBBER)                   # elbow pad


static func _thigh(b: B, p: Dictionary, s: String) -> void:
	var sx := 1.0 if s == "R" else -1.0
	var u: Color = p["uniform"]
	b.tbox(Vector2(0.07, 0.072), Vector2(0.1, 0.098), 0.53, _x(Vector3(0, -0.195, 0.004)), u, Kit.CAMO)
	b.box(Vector3(0.016, 0.065, 0.055), _x(Vector3(-0.088 * sx, -0.2, 0.004)), _dk(u, 0.88), Kit.CAMO)       # cargo pocket


static func _shin(b: B, p: Dictionary) -> void:
	var u: Color = p["uniform"]
	b.tbox(Vector2(0.06, 0.062), Vector2(0.072, 0.076), 0.35, _x(Vector3(0, -0.135, -0.004)), u, Kit.CAMO)
	b.tbox(Vector2(0.068, 0.074), Vector2(0.07, 0.072), 0.16, _x(Vector3(0, -0.365, 0.004)), p["boots"], Kit.RUBBER)   # boot shaft
	b.box(Vector3(0.062, 0.068, 0.028), _x(Vector3(0, -0.005, 0.07)), p["pads"], Kit.RUBBER)                  # knee pad


static func _foot(b: B, p: Dictionary) -> void:
	var bt: Color = p["boots"]
	# big boot: body, toe, sole (bottom 0.0875 below the ankle, toe and heel
	# within the clearance the gait assumes)
	b.box(Vector3(0.066, 0.045, 0.118), _x(Vector3(0, -0.04, -0.05)), bt, Kit.RUBBER)
	b.tbox(Vector2(0.066, 0.035), Vector2(0.06, 0.03), 0.055, _x(Vector3(0, -0.058, -0.145)), _dk(bt, 1.15), Kit.RUBBER)
	b.box(Vector3(0.07, 0.0125, 0.13), _x(Vector3(0, -0.075, -0.05)), Color(0.035, 0.035, 0.035), Kit.RUBBER)


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
