extends RefCounted
## Helpers for testing points against cover boxes.
## Each cover def is a Dictionary: {"xform": Transform3D (ground-level center), "size": Vector3}.


static func inside_any(defs: Array, p: Vector3, margin: float) -> bool:
	for def in defs:
		var xf: Transform3D = def["xform"]
		var size: Vector3 = def["size"]
		var l: Vector3 = xf.affine_inverse() * p
		if absf(l.x) < size.x * 0.5 + margin and absf(l.z) < size.z * 0.5 + margin:
			return true
	return false


## Moves a point out of any cover box (plus margin) along the shortest axis.
static func push_out(defs: Array, p: Vector3, margin: float) -> Vector3:
	var out: Vector3 = p
	for def in defs:
		var xf: Transform3D = def["xform"]
		var size: Vector3 = def["size"]
		var l: Vector3 = xf.affine_inverse() * out
		var hx: float = size.x * 0.5 + margin
		var hz: float = size.z * 0.5 + margin
		if absf(l.x) < hx and absf(l.z) < hz:
			if hx - absf(l.x) < hz - absf(l.z):
				l.x = hx if l.x >= 0.0 else -hx
			else:
				l.z = hz if l.z >= 0.0 else -hz
			out = xf * l
	return out
