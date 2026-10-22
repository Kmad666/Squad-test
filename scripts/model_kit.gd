extends RefCounted
## Procedural shape kit for the soldier model.
##
## A Builder collects shapes, each with a colour and a material ID, and bakes
## them into one ArrayMesh (one draw call). The material ID rides in the
## vertex colour's alpha and tells the soldier shader how to shade that
## surface (camo fabric, plain fabric, nylon webbing, rubber, metal, glass).
##
## Shapes:
##   sq()     superellipsoid: rounded boxes, pads, pouches, domes, canisters
##   loft()   a tube through a list of elliptical rings: limbs, torso, pelvis
##   shell()  part of a superellipsoid with thickness and a rim: helmet
##   cyl()    capped cylinder between two points: barrels, tubes, straps
##   tube()   round tube along a polyline: hoses, cables
## Normals are analytic (superellipsoid) or from the surface grid (loft), so
## everything shades smooth without textures.

## Material IDs (vertex alpha). Keep in sync with shaders/soldier.gdshader.
const CAMO := 1.0       # camouflage fatigues
const CLOTH := 0.85     # plain fabric (hood, helmet cover, pack)
const NYLON := 0.7      # webbing / pouches / straps
const RUBBER := 0.55    # mask, pads, soles, gloves
const METAL := 0.4      # weapon metal and polymer
const GLASS := 0.25     # mask lenses, optic glass
const SKIN := 0.1


static func _sgn_pow(v: float, e: float) -> float:
	return signf(v) * pow(absf(v), e)


class Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var lod := 0            # 0 = full detail, 1 = far (fewer segments)

	func _init(p_lod := 0) -> void:
		lod = p_lod

	func seg(n: int) -> int:
		return maxi(4, n if lod == 0 else int(n * 0.5))

	func _col(c: Color, id: float) -> Color:
		return Color(c.r, c.g, c.b, id)

	## Adds a triangle wound so it faces the way its vertex normals point
	## (Godot front faces are clockwise), whatever order the shape code
	## generated it in. Degenerate triangles (at poles) are dropped.
	func _tri(a: int, b: int, c: int) -> void:
		var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if g.length_squared() < 1e-14:
			return
		var n := norms[a] + norms[b] + norms[c]
		if g.dot(n) > 0.0:
			idx.append_array([a, c, b])
		else:
			idx.append_array([a, b, c])

	## A parametric grid of positions/normals (rows x cols), stitched into
	## triangles. `wrap` joins the last column to the first.
	func _grid(pos: Array, nrm: Array, rows: int, ncols: int, c: Color, wrap: bool) -> void:
		var base := verts.size()
		for r in rows:
			for k in ncols:
				verts.append(pos[r * ncols + k])
				norms.append(nrm[r * ncols + k])
				cols.append(c)
		var kmax := ncols if wrap else ncols - 1
		for r in rows - 1:
			for k in kmax:
				var k2 := (k + 1) % ncols
				var a := base + r * ncols + k
				var b := base + r * ncols + k2
				var d := base + (r + 1) * ncols + k
				var e := base + (r + 1) * ncols + k2
				_tri(a, d, b)
				_tri(b, d, e)

	## Superellipsoid with half-extents `r`. e1 shapes the profile top to
	## bottom, e2 around: 1.0 = ellipsoid, 0.2 = rounded box, 0.1 = sharp box.
	## v_min/v_max (radians, -PI/2..PI/2) cut it, e.g. v_min = 0 for a dome.
	func sq(r: Vector3, xf: Transform3D, c: Color, id: float, e1 := 0.25, e2 := 0.25, nu := 12, nv := 8, v_min := -PI / 2.0, v_max := PI / 2.0) -> void:
		nu = seg(nu)
		nv = seg(nv)
		var pos := []
		var nrm := []
		var nb := xf.basis.inverse().transposed()
		for i in nv + 1:
			var v := lerpf(v_min, v_max, float(i) / nv)
			for k in nu:
				var u := -PI + TAU * float(k) / nu
				var cv := cos(v)
				var sv := sin(v)
				var cu := cos(u)
				var su := sin(u)
				var p := Vector3(
					r.x * _sgn_pow(cv, e1) * _sgn_pow(cu, e2),
					r.y * _sgn_pow(sv, e1),
					r.z * _sgn_pow(cv, e1) * _sgn_pow(su, e2))
				var n := Vector3(
					_sgn_pow(cv, 2.0 - e1) * _sgn_pow(cu, 2.0 - e2) / r.x,
					_sgn_pow(sv, 2.0 - e1) / r.y,
					_sgn_pow(cv, 2.0 - e1) * _sgn_pow(su, 2.0 - e2) / r.z)
				if n.length_squared() < 1e-12:
					n = Vector3(0, signf(sv), 0)
				pos.append(xf * p)
				nrm.append((nb * n).normalized())
		_grid(pos, nrm, nv + 1, nu, _col(c, id), true)
		# Close a cut edge with a flat cap so cut shapes aren't hollow.
		if v_min > -PI / 2.0 + 0.01:
			_cap_ring(pos.slice(0, nu), xf.basis * Vector3.DOWN, c, id, false)
		if v_max < PI / 2.0 - 0.01:
			_cap_ring(pos.slice(nv * nu, (nv + 1) * nu), xf.basis * Vector3.UP, c, id, true)

	static func _sgn_pow(v: float, e: float) -> float:
		return signf(v) * pow(absf(v), e)

	func _cap_ring(ring: Array, normal: Vector3, c: Color, id: float, flip: bool) -> void:
		var center := Vector3.ZERO
		for p in ring:
			center += p
		center /= ring.size()
		var base := verts.size()
		verts.append(center)
		norms.append(normal.normalized())
		cols.append(_col(c, id))
		for p in ring:
			verts.append(p)
			norms.append(normal.normalized())
			cols.append(_col(c, id))
		var n := ring.size()
		for k in n:
			_tri(base, base + 1 + k, base + 1 + (k + 1) % n)

	## Loft through rings, each [center: Vector3, rx: float, rz: float] in the
	## XZ plane (rings stacked along any direction; normals from the grid).
	## Ends close with a dome-ish cap point unless open.
	func loft(rings: Array, xf: Transform3D, c: Color, id: float, nu := 14, cap_a := true, cap_b := true) -> void:
		nu = seg(nu)
		var rows := rings.size()
		var pos := []
		for ring in rings:
			var ctr: Vector3 = ring[0]
			for k in nu:
				var u := -PI + TAU * float(k) / nu
				pos.append(ctr + Vector3(cos(u) * ring[1], 0, sin(u) * ring[2]))
		# Grid normals: cross of the around and along tangents.
		var nrm := []
		for r in rows:
			for k in nu:
				var around: Vector3 = pos[r * nu + (k + 1) % nu] - pos[r * nu + (k - 1 + nu) % nu]
				var along: Vector3 = pos[mini(r + 1, rows - 1) * nu + k] - pos[maxi(r - 1, 0) * nu + k]
				var n := around.cross(along)
				# point away from the ring centre
				var out: Vector3 = pos[r * nu + k] - (rings[r][0] as Vector3)
				if n.dot(out) < 0.0:
					n = -n
				nrm.append(n.normalized())
		var wpos := []
		var nb := xf.basis.inverse().transposed()
		var wnrm := []
		for i in pos.size():
			wpos.append(xf * (pos[i] as Vector3))
			wnrm.append((nb * (nrm[i] as Vector3)).normalized())
		_grid(wpos, wnrm, rows, nu, _col(c, id), true)
		var down := xf.basis * ((rings[0][0] as Vector3) - (rings[1][0] as Vector3))
		var up := xf.basis * ((rings[rows - 1][0] as Vector3) - (rings[rows - 2][0] as Vector3))
		if cap_a:
			_cap_ring(wpos.slice(0, nu), down, c, id, (rings[1][0] as Vector3).y < (rings[0][0] as Vector3).y)
		if cap_b:
			_cap_ring(wpos.slice((rows - 1) * nu, rows * nu), up, c, id, (rings[rows - 1][0] as Vector3).y > (rings[rows - 2][0] as Vector3).y)

	## Superellipsoid shell between v_min(u) and v_max with thickness: outer
	## skin, inner skin and the rim. `v_min_fn` gives the lower cut per
	## longitude u (radians, 0 = +X, -PI/2 = -Z front) so the rim can rise
	## over the ears (high-cut helmet).
	func shell(r: Vector3, thick: float, xf: Transform3D, c: Color, id: float, v_min_fn: Callable, e1 := 0.8, e2 := 0.9, nu := 24, nv := 10) -> void:
		nu = seg(nu)
		nv = seg(nv)
		var ri := r - Vector3.ONE * thick
		var nb := xf.basis.inverse().transposed()
		var layers := [[], [], [], []]   # outer pos, outer nrm, inner pos, inner nrm
		for i in nv + 1:
			for k in nu:
				var u := -PI + TAU * float(k) / nu
				var vmin: float = v_min_fn.call(u)
				var v := lerpf(vmin, PI / 2.0, float(i) / nv)
				var cv := cos(v)
				var sv := sin(v)
				var cu := cos(u)
				var su := sin(u)
				var shape := Vector3(_sgn_pow(cv, e1) * _sgn_pow(cu, e2), _sgn_pow(sv, e1), _sgn_pow(cv, e1) * _sgn_pow(su, e2))
				var n := Vector3(
					_sgn_pow(cv, 2.0 - e1) * _sgn_pow(cu, 2.0 - e2) / r.x,
					_sgn_pow(sv, 2.0 - e1) / r.y,
					_sgn_pow(cv, 2.0 - e1) * _sgn_pow(su, 2.0 - e2) / r.z)
				if n.length_squared() < 1e-12:
					n = Vector3.UP
				var wn := (nb * n).normalized()
				layers[0].append(xf * (shape * r))
				layers[1].append(wn)
				layers[2].append(xf * (shape * ri))
				layers[3].append(-wn)
		var col := _col(c, id)
		_grid(layers[0], layers[1], nv + 1, nu, col, true)
		# inner skin, wound the other way
		var base := verts.size()
		for i in layers[2].size():
			verts.append(layers[2][i])
			norms.append(layers[3][i])
			cols.append(col)
		for row in nv:
			for k in nu:
				var k2 := (k + 1) % nu
				var a := base + row * nu + k
				var b := base + row * nu + k2
				var d := base + (row + 1) * nu + k
				var e := base + (row + 1) * nu + k2
				_tri(a, b, d)
				_tri(b, e, d)
		# rim: joins the outer and inner bottom edges
		var rb := verts.size()
		for k in nu:
			var po: Vector3 = layers[0][k]
			var pi_: Vector3 = layers[2][k]
			var down := (po - pi_).cross((layers[0][(k + 1) % nu] as Vector3) - po).normalized()
			verts.append(po)
			norms.append(down)
			cols.append(col)
			verts.append(pi_)
			norms.append(down)
			cols.append(col)
		for k in nu:
			var k2 := (k + 1) % nu
			var o1 := rb + k * 2
			var i1 := o1 + 1
			var o2 := rb + k2 * 2
			var i2 := o2 + 1
			_tri(o1, o2, i1)
			_tri(i1, o2, i2)

	## Capped cylinder from a to b (radius ra at a, rb at b).
	func cyl(a: Vector3, b: Vector3, ra: float, rb: float, c: Color, id: float, nu := 12, xf := Transform3D.IDENTITY) -> void:
		var axis := b - a
		var t := Transform3D(_basis_y(axis.normalized()), Vector3.ZERO)
		var rings := [[Vector3(0, 0, 0), ra, ra], [Vector3(0, axis.length(), 0), rb, rb]]
		# a straight 2-ring loft has poor grid normals at the ends: build directly
		nu = seg(nu)
		var col := _col(c, id)
		var full := xf * Transform3D(t.basis, a)
		var nb := full.basis.inverse().transposed()
		var base := verts.size()
		var h := axis.length()
		var slope := (ra - rb) / maxf(h, 0.0001)
		for ring in 2:
			for k in nu:
				var u := TAU * float(k) / nu
				var rr: float = ra if ring == 0 else rb
				verts.append(full * Vector3(cos(u) * rr, h * ring, sin(u) * rr))
				norms.append((nb * Vector3(cos(u), slope, sin(u))).normalized())
				cols.append(col)
		for k in nu:
			var k2 := (k + 1) % nu
			_tri(base + k, base + k2, base + nu + k)
			_tri(base + k2, base + nu + k2, base + nu + k)
		var ring_a := []
		var ring_b := []
		for k in nu:
			ring_a.append(verts[base + k])
			ring_b.append(verts[base + nu + k])
		_cap_ring(ring_a, full.basis * Vector3.DOWN, c, id, true)
		_cap_ring(ring_b, full.basis * Vector3.UP, c, id, false)

	## Round tube along a polyline (hoses, cables, sling).
	func tube(points: Array, radius: float, c: Color, id: float, nu := 6, xf := Transform3D.IDENTITY) -> void:
		for i in points.size() - 1:
			cyl(points[i], points[i + 1], radius, radius, c, id, nu, xf)

	## Builder-level PrimitiveMesh support (rarely needed now).
	func prim(m: PrimitiveMesh, xf: Transform3D, c: Color, id: float) -> void:
		var arr := m.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		var col := _col(c, id)
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(col)
		for i in range(0, ind.size(), 3):
			_tri(base + ind[i], base + ind[i + 1], base + ind[i + 2])

	static func _basis_y(dir: Vector3) -> Basis:
		var y := dir
		var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var z := x.cross(y).normalized()
		x = y.cross(z).normalized()
		return Basis(x, y, z)

	func triangles() -> int:
		return idx.size() / 3

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		if verts.size() > 0:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am


static func xf(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)
