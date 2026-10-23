// Low-poly shape kit. Every part is a list of simple shapes (boxes, lofts,
// cylinders, spheres, wedges, rings, tubes) in the part's own space. The part's
// size and morph sliders (taper, bulge, bend, twist, lean, sides) are baked
// straight into the vertices, so exports carry the final shape with no scale
// tricks. Faces are flat shaded (PSX style) and textured with a planar UV
// per face, so patterns keep a constant size in metres on every part.
import * as THREE from 'three';

export const SLOTS = ['main', 'trim', 'detail'];
const SLOT_INDEX = { main: 0, trim: 1, detail: 2 };
const DEG = Math.PI / 180;

// ------------------------------------------------------------ triangles

class TriList {
	constructor() { this.tris = []; }
	// Adds a triangle, wound so its normal points away from `ref`.
	add(a, b, c, slot, ref) {
		const n = new THREE.Vector3().subVectors(b, a).cross(new THREE.Vector3().subVectors(c, a));
		if (n.lengthSq() < 1e-14) return;
		if (ref) {
			const ctr = new THREE.Vector3().add(a).add(b).add(c).multiplyScalar(1 / 3);
			if (n.dot(ctr.sub(ref)) < 0) { const t = b; b = c; c = t; }
		}
		this.tris.push({ v: [a.clone(), b.clone(), c.clone()], m: slot });
	}
	quad(a, b, c, d, slot, ref) {
		this.add(a, b, c, slot, ref);
		this.add(a, c, d, slot, ref);
	}
}

function sidesFor(n, adj) {
	if (n >= 5) return Math.max(3, Math.min(24, Math.round(n + adj)));
	return n;
}

// rings: [[y, rx, rz, z = 0, x = 0], ...] along +Y. Side faces wind away
// from the ring centre at their own height, so waists and bulges are fine.
function loft(out, rings, n, slot, off = 0, capA = true, capB = true) {
	const pts = rings.map(([y, rx, rz, z = 0, x = 0]) => {
		const ring = [];
		for (let k = 0; k < n; k++) {
			const u = off + (Math.PI * 2 * k) / n;
			ring.push(new THREE.Vector3(x + Math.cos(u) * rx, y, z + Math.sin(u) * rz));
		}
		return { ring, ctr: new THREE.Vector3(x, y, z) };
	});
	for (let r = 0; r + 1 < pts.length; r++) {
		const A = pts[r], B = pts[r + 1];
		const ref = new THREE.Vector3().addVectors(A.ctr, B.ctr).multiplyScalar(0.5);
		for (let k = 0; k < n; k++) {
			const k2 = (k + 1) % n;
			out.quad(A.ring[k], A.ring[k2], B.ring[k2], B.ring[k], slot, ref);
		}
	}
	const cap = (P, dir) => {
		const ref = P.ctr.clone().addScaledVector(new THREE.Vector3(0, 1, 0), -dir * 10);
		for (let k = 1; k + 1 < n; k++) out.add(P.ring[0], P.ring[k], P.ring[k + 1], slot, ref);
	};
	if (capA) cap(pts[0], -1);
	if (capB) cap(pts[pts.length - 1], 1);
}

function box(out, s, slot, top = [1, 1], shift = 0) {
	const [w, h, d] = s.map((v) => v / 2);
	const tw = w * top[0], td = d * top[1];
	const p = [
		[-w, -h, -d], [w, -h, -d], [w, -h, d], [-w, -h, d],
		[-tw, h, -td + shift], [tw, h, -td + shift], [tw, h, td + shift], [-tw, h, td + shift],
	].map((a) => new THREE.Vector3(...a));
	const ref = new THREE.Vector3(0, 0, shift * 0.5);
	for (const f of [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])
		out.quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], slot, ref);
}

// Ramp: full footprint at the bottom, top edge along the back (+Z).
function wedge(out, s, slot) {
	const [w, h, d] = s.map((v) => v / 2);
	const p = [[-w, -h, -d], [w, -h, -d], [w, -h, d], [-w, -h, d], [-w, h, d], [w, h, d]].map((a) => new THREE.Vector3(...a));
	const ref = new THREE.Vector3(0, -h / 3, d / 3);
	out.quad(p[0], p[1], p[2], p[3], slot, ref);
	out.quad(p[3], p[2], p[5], p[4], slot, ref);
	out.quad(p[0], p[1], p[5], p[4], slot, ref);
	out.add(p[0], p[3], p[4], slot, ref);
	out.add(p[1], p[2], p[5], slot, ref);
}

function sphere(out, r, n, rings, slot, hemi) {
	const rr = [];
	const span = hemi ? Math.PI / 2 : Math.PI;
	for (let i = 0; i <= rings; i++) {
		const phi = span - (span * i) / rings;   // bottom (or equator) to the top
		rr.push([Math.cos(phi) * r, Math.max(Math.sin(phi) * r, 0), Math.max(Math.sin(phi) * r, 0)]);
	}
	loft(out, rr, n, slot, 0, hemi, false);
}

function torus(out, R, r, n, m, slot) {
	const ring = (i) => {
		const u = (Math.PI * 2 * i) / n;
		const pts = [];
		for (let j = 0; j < m; j++) {
			const v = (Math.PI * 2 * j) / m;
			pts.push(new THREE.Vector3((R + Math.cos(v) * r) * Math.cos(u), Math.sin(v) * r, (R + Math.cos(v) * r) * Math.sin(u)));
		}
		return { pts, c: new THREE.Vector3(Math.cos(u) * R, 0, Math.sin(u) * R) };
	};
	for (let i = 0; i < n; i++) {
		const A = ring(i), B = ring((i + 1) % n);
		for (let j = 0; j < m; j++) {
			const j2 = (j + 1) % m;
			const ref = new THREE.Vector3().addVectors(A.c, B.c).multiplyScalar(0.5);
			out.quad(A.pts[j], A.pts[j2], B.pts[j2], B.pts[j], slot, ref);
		}
	}
}

// A cylinder from a to b (radii ra, rb).
function cylAB(out, a, b, ra, rb, n, slot, caps = true) {
	const tmp = new TriList();
	const len = a.distanceTo(b);
	loft(tmp, [[0, ra, ra], [len, rb, rb]], n, slot, 0, caps, caps);
	const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3().subVectors(b, a).normalize());
	for (const t of tmp.tris) {
		for (const v of t.v) v.applyQuaternion(q).add(a);
		out.tris.push(t);
	}
}

// ------------------------------------------------------------ shapes

function buildShape(sh, adj) {
	const out = new TriList();
	const slot = SLOT_INDEX[sh.m || 'main'];
	switch (sh.p) {
		case 'box': box(out, sh.s, slot, sh.top || [1, 1], sh.shift || 0); break;
		case 'wedge': wedge(out, sh.s, slot); break;
		case 'cyl': {
			const n = sidesFor(sh.n || 8, adj);
			const [r1, r2] = sh.r;
			const d = sh.d ?? 1;
			loft(out, [[-sh.h / 2, r1, r1 * d], [sh.h / 2, r2, r2 * d]], n, slot, (sh.off || 0) * DEG, sh.capA !== false, sh.capB !== false);
			break;
		}
		case 'sph': {
			const n = sidesFor(sh.n || 8, adj);
			sphere(out, sh.r, n, Math.max(2, Math.round((sh.rings || 4) * n / (sh.n || 8))), slot, !!sh.hemi);
			break;
		}
		case 'loft': {
			const n = sidesFor(sh.n || 6, adj);
			loft(out, sh.rings, n, slot, (sh.off || 0) * DEG, sh.capA !== false, sh.capB !== false);
			break;
		}
		case 'torus': torus(out, sh.R, sh.r, sidesFor(sh.n || 10, adj), sh.m2 || 4, slot); break;
		case 'tube': {
			const n = sidesFor(sh.n || 5, adj);
			const pts = sh.pts.map((p) => new THREE.Vector3(...p));
			for (let i = 0; i + 1 < pts.length; i++) cylAB(out, pts[i], pts[i + 1], sh.r, sh.r, n, slot, true);
			break;
		}
		default: console.warn('unknown shape', sh.p);
	}
	const sc = new THREE.Vector3(...(sh.sc || [1, 1, 1]));
	const e = new THREE.Euler(...(sh.rot || [0, 0, 0]).map((a) => a * DEG), 'XYZ');
	const q = new THREE.Quaternion().setFromEuler(e);
	const at = new THREE.Vector3(...(sh.at || [0, 0, 0]));
	const flipWinding = sc.x * sc.y * sc.z < 0;
	for (const t of out.tris) {
		for (const v of t.v) v.multiply(sc).applyQuaternion(q).add(at);
		if (flipWinding) { const tmp = t.v[1]; t.v[1] = t.v[2]; t.v[2] = tmp; }
	}
	return out.tris;
}

// ------------------------------------------------------------ morphs

export const MORPHS = [
	{ key: 'taper', label: 'Taper', min: -0.9, max: 0.9, step: 0.01 },
	{ key: 'bulge', label: 'Bulge', min: -0.6, max: 1, step: 0.01 },
	{ key: 'bend', label: 'Bend', min: -1, max: 1, step: 0.01 },
	{ key: 'lean', label: 'Lean', min: -1, max: 1, step: 0.01 },
	{ key: 'twist', label: 'Twist', min: -180, max: 180, step: 1 },
];

// Applies size and morphs to every vertex, around the pivot `pv`. `t` runs
// 0 (bottom) .. 1 (top) over the part's height; taper / bulge scale X and Z
// around the pivot's axis, bend curves it forward (+Z), lean sideways (+X),
// twist turns it.
function morphTris(tris, size, morph, pv) {
	for (const t of tris) for (const v of t.v) v.sub(pv).multiply(size).add(pv);
	let lo = Infinity, hi = -Infinity;
	for (const t of tris) for (const v of t.v) { lo = Math.min(lo, v.y); hi = Math.max(hi, v.y); }
	const h = Math.max(hi - lo, 1e-4);
	const { taper = 0, bulge = 0, bend = 0, lean = 0, twist = 0 } = morph || {};
	if (!taper && !bulge && !bend && !lean && !twist) return;
	for (const t of tris) for (const v of t.v) {
		const k = (v.y - lo) / h;
		let f = 1 - taper * (k * 2 - 1);
		f *= 1 + bulge * Math.sin(Math.PI * k);
		f = Math.max(f, 0.03);
		let x = (v.x - pv.x) * f, z = (v.z - pv.z) * f;
		const a = twist * DEG * (k - 0.5);
		const c = Math.cos(a), s = Math.sin(a);
		const xr = x * c - z * s, zr = x * s + z * c;
		v.x = pv.x + xr + lean * h * 0.5 * k * k;
		v.z = pv.z + zr + bend * h * 0.5 * k * k;
	}
}

// ------------------------------------------------------------ assembly

// The point a part scales and morphs around: its own centre for parts that
// snap onto a bone (they are authored in the bone's space, often far from
// its origin), its origin (the mounting point) for everything else.
const _pivots = new Map();
export function partPivot(def) {
	if (def.mount !== 'home') return new THREE.Vector3();
	if (!_pivots.has(def.id)) {
		const box = new THREE.Box3();
		for (const sh of def.shapes) for (const t of buildShape(sh, 0)) for (const v of t.v) box.expandByPoint(v);
		_pivots.set(def.id, box.getCenter(new THREE.Vector3()));
	}
	return _pivots.get(def.id).clone();
}

// Builds the BufferGeometry for one part: groups 0 main, 1 trim, 2 detail.
export function buildPartGeometry(def, part) {
	const adj = part.sides || 0;
	let tris = [];
	for (const sh of def.shapes) tris = tris.concat(buildShape(sh, adj));
	morphTris(tris, new THREE.Vector3(...(part.size || [1, 1, 1])), part.morph, partPivot(def));
	// Corner points: every distinct vertex position, numbered in a fixed
	// order, so hand edits (part.verts: { index: [dx, dy, dz] }) stick to the
	// same corner. Shared corners move together, so faces stay closed.
	const keyOf = (v) => `${Math.round(v.x * 1e5)},${Math.round(v.y * 1e5)},${Math.round(v.z * 1e5)}`;
	const index = new Map();
	const base = [];
	const refs = [];
	for (const t of tris) for (const v of t.v) {
		const k = keyOf(v);
		if (!index.has(k)) { index.set(k, base.length); base.push(v.clone()); refs.push([]); }
		refs[index.get(k)].push(v);
	}
	const offs = part.verts || {};
	for (const [i, d] of Object.entries(offs)) {
		const list = refs[+i];
		if (!list) continue;
		for (const v of list) { v.x += d[0]; v.y += d[1]; v.z += d[2]; }
	}
	const sx = part.flip ? -1 : 1;
	const points = base.map((b, i) => {
		const d = offs[i] || [0, 0, 0];
		return new THREE.Vector3((b.x + d[0]) * sx, b.y + d[1], b.z + d[2]);
	});
	if (part.flip) {
		for (const t of tris) {
			for (const v of t.v) v.x = -v.x;
			const tmp = t.v[1]; t.v[1] = t.v[2]; t.v[2] = tmp;
		}
	}
	const geo = trisToGeometry(tris, part.patScale || 0.25);
	geo.userData.points = points;              // shown corners (part space)
	geo.userData.base = base;                  // corners before hand edits, unflipped
	return geo;
}

export function trisToGeometry(tris, tile) {
	tris.sort((a, b) => a.m - b.m);
	const pos = [], nrm = [], uv = [];
	const e1 = new THREE.Vector3(), e2 = new THREE.Vector3(), n = new THREE.Vector3();
	const groups = [];
	let cur = -1, start = 0;
	tris.forEach((t, i) => {
		if (t.m !== cur) {
			if (cur >= 0) groups.push([start, i * 3 - start, cur]);
			cur = t.m; start = i * 3;
		}
		const [a, b, c] = t.v;
		n.crossVectors(e1.subVectors(b, a), e2.subVectors(c, a)).normalize();
		const ax = Math.abs(n.x), ay = Math.abs(n.y), az = Math.abs(n.z);
		for (const v of t.v) {
			pos.push(v.x, v.y, v.z);
			nrm.push(n.x, n.y, n.z);
			if (ax >= ay && ax >= az) uv.push(v.z / tile, v.y / tile);
			else if (ay >= az) uv.push(v.x / tile, v.z / tile);
			else uv.push(v.x / tile, v.y / tile);
		}
	});
	if (cur >= 0) groups.push([start, tris.length * 3 - start, cur]);
	const g = new THREE.BufferGeometry();
	g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
	g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
	g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
	for (const [s, c, m] of groups) g.addGroup(s, c, m);
	g.computeBoundingSphere();
	g.computeBoundingBox();
	return g;
}

export function triangleCount(geom) {
	return geom.attributes.position.count / 3;
}
