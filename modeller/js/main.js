// Squad Modeller: the editor. Parts are plain data (see newPart); every
// change rebuilds the part's mesh from that data, so what you see is
// exactly what Save stores and Export writes.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { TransformControls } from 'three/addons/controls/TransformControls.js';
import { PARTS, CATEGORIES, TEMPLATES, SWATCHES } from './parts.js';
import { buildPartGeometry, partPivot, MORPHS, triangleCount, MESHES, clusterTris } from './geometry.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { partMaterials, psxUniforms, ghostMat, selectMat } from './materials.js';
import { PATTERNS, patternSwatch } from './textures.js';
import { BONES, poseFor, otherSide, boneSide, mirrorLocal } from './skeleton.js';
import { exportGLB, readGLBDesign, download, FORMAT, VERSION } from './io.js';

const $ = (s) => document.querySelector(s);
const DEG = Math.PI / 180;

const MODES = {
	humanoid: {
		label: 'Character', target: [0, 0.92, 0], cam: [1.9, 1.5, -3.3], grid: [4, 16, 0], sym: true, snap: false,
		step: 0.01, budget: 300, template: 'boxy',
		hint: 'Front of the character faces you (−Z). Parts snap to the game\'s soldier skeleton.',
	},
	weapon: {
		label: 'Weapon', target: [0, 0.0, -0.2], cam: [1.55, 0.45, -0.45], grid: [1.6, 32, -0.3], sym: true, snap: true,
		step: 0.005, budget: 400, template: 'carbine', plane: 'x',
		hint: 'Ghost hands: right hand on the grip (origin), left hand where the soldier holds the handguard. Barrel points −Z.',
	},
	building: {
		label: 'Building', target: [0, 1.2, 0], cam: [7, 5.5, -9], grid: [24, 24, 0], sym: false, snap: true,
		step: 0.25, budget: 1200, template: 'house', plane: 'y',
		hint: 'Grid squares are 1 m. Q turns the next piece 90°. The soldier is 1.8 m tall.',
	},
};

const state = {
	mode: 'humanoid',
	name: 'trooper',
	parts: [],
	selected: null,
	colorSlot: 'main',
	pose: 'rest',
	psx: true,
	showBones: false,
	turn: 0,                   // upright parts: yaw for the next placement (Q)
	settings: {},              // per mode: { sym, snap }
	clipboard: null,
	meshes: {},                // imported .glb meshes in this design (see importGLB)
};

// ================================================================ scene

const view = $('#view');
const renderer = new THREE.WebGLRenderer({ antialias: false });
view.appendChild(renderer.domElement);
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x232a2f);
const camera = new THREE.PerspectiveCamera(38, 1, 0.01, 200);
scene.add(new THREE.HemisphereLight(0xe4ecff, 0x40382c, 2.8));
const sun = new THREE.DirectionalLight(0xfff4e0, 2.8);
sun.position.set(-2.5, 4, -3);
scene.add(sun);
const rim = new THREE.DirectionalLight(0x9fc4ff, 0.9);
rim.position.set(3, 2, 4);
scene.add(rim);

const orbit = new OrbitControls(camera, renderer.domElement);
orbit.enableDamping = false;
orbit.zoomSpeed = 1.2;

// The gizmo drives `handle`, which sits at the part's pivot (see
// partPivot); the part's mesh follows it.
const handle = new THREE.Object3D();
const gizmo = new TransformControls(camera, renderer.domElement);
gizmo.setSpace('local');
gizmo.setSize(0.75);
scene.add(gizmo.getHelper());

let grid = null;
const rig = new THREE.Group();
scene.add(rig);
let bones = {};
let proxies = [];
const partMeshes = new Map();
let helpers = new THREE.Group();          // ghost hands / ground plane visuals
scene.add(helpers);
let weaponPreview = null;
const proxyMat = new THREE.MeshBasicMaterial({ color: 0x6ce0d0, wireframe: true, transparent: true, opacity: 0.22, depthWrite: false });
proxyMat.visible = false;

function resize() {
	const w = view.clientWidth, h = view.clientHeight;
	const pr = state.psx ? 0.5 : Math.min(window.devicePixelRatio || 1, 2);
	renderer.setPixelRatio(pr);
	renderer.setSize(w, h);
	camera.aspect = w / Math.max(h, 1);
	camera.updateProjectionMatrix();
	if (state.psx) psxUniforms.psxRes.value.set(w * pr * 0.75, h * pr * 0.75);
	else psxUniforms.psxRes.value.set(0, 0);
	view.classList.toggle('psx', state.psx);
}
new ResizeObserver(resize).observe(view);

// ================================================================ rig

function buildRig() {
	gizmo.detach();
	for (const m of partMeshes.values()) m.geometry.dispose();
	partMeshes.clear();
	rig.clear();
	bones = {};
	proxies = [];
	for (const b of BONES[state.mode]) {
		const o = new THREE.Object3D();
		o.name = b.name;
		o.matrixAutoUpdate = false;
		rig.add(o);
		bones[b.name] = o;
		if (b.proxy) {
			const pr = b.proxy;
			let g;
			if (pr.box) g = new THREE.BoxGeometry(...pr.box);
			else if (pr.sph) g = new THREE.SphereGeometry(pr.sph, 8, 6);
			else g = new THREE.CylinderGeometry(pr.cyl[0], pr.cyl[0], pr.cyl[1], 8);
			const m = new THREE.Mesh(g, proxyMat);
			m.position.set(...pr.at);
			m.userData.bone = b.name;
			o.add(m);
			proxies.push(m);
		}
	}
	weaponPreview = null;
	if (state.mode === 'humanoid') buildWeaponPreview();
	buildHelpers();
	applyPose(0);
}

function applyPose(t) {
	const M = poseFor(state.mode, state.pose, t);
	for (const [name, o] of Object.entries(bones)) {
		o.matrix.copy(M[name] || new THREE.Matrix4());
		o.matrixWorldNeedsUpdate = true;
	}
	if (weaponPreview) {
		weaponPreview.visible = !!M.rifle;
		if (M.rifle) { weaponPreview.matrix.copy(M.rifle); weaponPreview.matrixWorldNeedsUpdate = true; }
	}
	rig.updateMatrixWorld(true);
}

// The last weapon made in Weapon mode, held in the hands in the rifle poses.
function buildWeaponPreview() {
	let design = null;
	try { design = JSON.parse(localStorage.getItem('sqm.autosave.weapon') || 'null'); } catch (e) { design = null; }
	const parts = design && design.parts ? design.parts : templateParts('weapon', 'carbine');
	const g = new THREE.Group();
	g.matrixAutoUpdate = false;
	for (const p of parts) {
		const def = PARTS[p.def];
		if (!def || def.marker) continue;
		const m = new THREE.Mesh(buildPartGeometry(def, p), partMaterials(p));
		m.position.set(...p.pos);
		m.quaternion.set(...p.quat);
		g.add(m);
	}
	rig.add(g);
	weaponPreview = g;
}

function buildHelpers() {
	scene.remove(helpers);
	helpers = new THREE.Group();
	scene.add(helpers);
	const cfg = MODES[state.mode];
	if (grid) scene.remove(grid);
	grid = new THREE.GridHelper(cfg.grid[0], cfg.grid[1], 0x55606a, 0x343c43);
	grid.position.y = cfg.grid[2];
	scene.add(grid);
	if (state.mode === 'weapon') {
		const hm = new THREE.MeshBasicMaterial({ color: 0xffc847, transparent: true, opacity: 0.18, depthWrite: false });
		const right = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.1, 0.07), hm);
		right.position.set(0.0, -0.045, 0.01);
		right.rotation.x = -18 * DEG;
		const left = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.06, 0.1), hm);
		left.position.set(-0.03, -0.03, -0.27);
		helpers.add(right, left);
	}
	if (state.mode === 'building') {
		// a soldier-sized stand-in for scale
		const sm = new THREE.MeshBasicMaterial({ color: 0x6ce0d0, transparent: true, opacity: 0.25, depthWrite: false });
		const man = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 1.8, 8), sm);
		man.position.set(-4, 0.9, -2.5);
		helpers.add(man);
	}
}

// ================================================================ part data

let _uid = 0;
function uid() { _uid += 1; return 'p' + Date.now().toString(36) + _uid.toString(36); }

function eulerQuat(rot) {
	return new THREE.Quaternion().setFromEuler(new THREE.Euler(...(rot || [0, 0, 0]).map((a) => a * DEG), 'XYZ')).toArray();
}

function newPart(defId, bone, pos, quat, ov = {}) {
	const def = PARTS[defId];
	return {
		id: uid(), def: defId, bone,
		pos: pos.slice(), quat: quat.slice(),
		size: (ov.size || [1, 1, 1]).slice(),
		morph: Object.assign({}, def.morph, ov.morph || {}),
		sides: ov.sides || 0,
		colors: Object.assign({}, def.colors, ov.colors || {}),
		pattern: ov.pattern || def.pattern,
		patScale: ov.patScale || def.patScale,
		glow: ov.glow ?? def.glow,
		flip: !!ov.flip,
		vcol: ov.vcol ?? !!def.imported,
		simplify: ov.simplify || 0,
		pair: null,
	};
}

const getPart = (id) => state.parts.find((p) => p.id === id);
const twinOf = (p) => (p && p.pair ? getPart(p.pair) : null);

function wantsTwin(p) {
	const def = PARTS[p.def];
	if (def.marker || !state.settings[state.mode].sym) return false;
	return !!boneSide(p.bone) || Math.abs(p.pos[0]) > 0.015;
}

function makeTwin(p) {
	const t = JSON.parse(JSON.stringify(p));
	t.id = uid();
	t.bone = otherSide(p.bone) || p.bone;
	Object.assign(t, mirrorLocal(p.pos, p.quat));
	t.flip = !p.flip;
	t.pair = p.id;
	p.pair = t.id;
	return t;
}

// Keeps a twin's transform the mirror image of its partner.
function mirrorInto(p, t) {
	const m = mirrorLocal(p.pos, p.quat);
	t.pos = m.pos;
	t.quat = m.quat;
	const bone = otherSide(p.bone) || p.bone;
	if (t.bone !== bone) { t.bone = bone; reparent(t); }
	syncTransform(t);
}

// Shared look and shape: copy everything except place and side.
function copyLook(p, t) {
	t.size = p.size.slice();
	t.morph = Object.assign({}, p.morph);
	t.sides = p.sides;
	t.colors = Object.assign({}, p.colors);
	t.pattern = p.pattern;
	t.patScale = p.patScale;
	t.glow = p.glow;
	t.verts = JSON.parse(JSON.stringify(p.verts || {}));
	t.vcol = p.vcol;
	t.simplify = p.simplify;
}

// Apply `fn` to the selected part and its twin, then rebuild both.
function editSelected(fn, rebuild = true) {
	const p = getPart(state.selected);
	if (!p) return;
	fn(p);
	const t = twinOf(p);
	if (t) copyLook(p, t);
	if (rebuild) { rebuildMesh(p); if (t) rebuildMesh(t); }
	updateStats();
}

// ================================================================ meshes

function createMesh(p) {
	const def = PARTS[p.def];
	const mesh = new THREE.Mesh(buildPartGeometry(def, p), partMaterials(p));
	mesh.userData.partId = p.id;
	mesh.position.set(...p.pos);
	mesh.quaternion.set(...p.quat);
	(bones[p.bone] || rig).add(mesh);
	partMeshes.set(p.id, mesh);
	return mesh;
}

function rebuildMesh(p) {
	const mesh = partMeshes.get(p.id);
	if (!mesh) return;
	mesh.geometry.dispose();
	mesh.geometry = buildPartGeometry(PARTS[p.def], p);
	mesh.material = partMaterials(p);
	for (const c of mesh.children) if (c.userData.fx) c.geometry = mesh.geometry;
	if (p.id === state.selected) refreshDots();
}

// ================================================================ point editing
// Select a part, press V (or "Edit points"), click a corner dot and drag it.

const vertHandle = new THREE.Object3D();
const dotMat = new THREE.PointsMaterial({ color: 0x6ce0d0, size: 9, sizeAttenuation: false, depthTest: false, transparent: true });
const dotSelMat = new THREE.PointsMaterial({ color: 0xffc847, size: 13, sizeAttenuation: false, depthTest: false, transparent: true });
let dots = null, dotSel = null;

function clearDots() {
	for (const d of [dots, dotSel]) if (d) { d.parent && d.parent.remove(d); d.geometry.dispose(); }
	dots = dotSel = null;
}

function refreshDots() {
	clearDots();
	const p = getPart(state.selected);
	if (!state.editPts || !p) return;
	const mesh = partMeshes.get(p.id);
	const pts = mesh.geometry.userData.points;
	dots = new THREE.Points(new THREE.BufferGeometry().setFromPoints(pts), dotMat);
	dots.renderOrder = 20;
	dots.raycast = () => {};
	mesh.add(dots);
	if (state.vsel != null && pts[state.vsel]) {
		dotSel = new THREE.Points(new THREE.BufferGeometry().setFromPoints([pts[state.vsel]]), dotSelMat);
		dotSel.renderOrder = 21;
		dotSel.raycast = () => {};
		mesh.add(dotSel);
	}
}

function setEditPts(on) {
	state.editPts = on;
	state.vsel = null;
	const p = getPart(state.selected);
	if (on && p) {
		gizmo.detach();
		setGizmoMode('translate');
		status('Edit points: click a corner dot, then drag the arrows. V or Esc to finish.');
	} else if (p) {
		placeHandle(p);
		gizmo.attach(handle);
	}
	refreshDots();
	renderProps();
}

// Nearest corner dot to the cursor (within 12 px), or null.
function pickDot(x, y) {
	const p = getPart(state.selected);
	if (!p || !dots) return null;
	const mesh = partMeshes.get(p.id);
	const r = renderer.domElement.getBoundingClientRect();
	let best = null, bd = 12;
	mesh.geometry.userData.points.forEach((pt, i) => {
		const v = pt.clone().applyMatrix4(mesh.matrixWorld).project(camera);
		const d = Math.hypot(r.left + (v.x + 1) / 2 * r.width - x, r.top + (1 - v.y) / 2 * r.height - y);
		if (d < bd) { bd = d; best = i; }
	});
	return best;
}

function selectDot(i) {
	const p = getPart(state.selected);
	state.vsel = i;
	const mesh = partMeshes.get(p.id);
	mesh.add(vertHandle);
	vertHandle.position.copy(mesh.geometry.userData.points[i]);
	vertHandle.quaternion.identity();
	vertHandle.scale.set(1, 1, 1);
	gizmo.setSpace('local');
	setGizmoMode('translate');
	gizmo.attach(vertHandle);
	refreshDots();
}

function moveDot() {
	const p = getPart(state.selected);
	if (!p || state.vsel == null) return;
	const mesh = partMeshes.get(p.id);
	const b = mesh.geometry.userData.base[state.vsel];
	const v = vertHandle.position.clone();
	if (p.flip) v.x = -v.x;
	p.verts = p.verts || {};
	const d = [v.x - b.x, v.y - b.y, v.z - b.z].map((n) => Math.round(n * 10000) / 10000);
	p.verts[state.vsel] = d;
	const t = twinOf(p);
	// a centred part with symmetry on: the matching corner on the other side mirrors
	if (!t && state.settings[state.mode].sym && Math.abs(b.x) > 1e-4) {
		const base = mesh.geometry.userData.base;
		const j = base.findIndex((q) => Math.abs(q.x + b.x) < 1e-4 && Math.abs(q.y - b.y) < 1e-4 && Math.abs(q.z - b.z) < 1e-4);
		if (j >= 0) p.verts[j] = [-d[0], d[1], d[2]];
	}
	if (t) { copyLook(p, t); rebuildMesh(t); }
	rebuildMesh(p);
	updateStats();
}

function syncTransform(p) {
	const mesh = partMeshes.get(p.id);
	if (!mesh) return;
	mesh.position.set(...p.pos);
	mesh.quaternion.set(...p.quat);
	if (p.id === state.selected && !gizmo.dragging) placeHandle(p);
}

function pivotOf(p) {
	const c = partPivot(PARTS[p.def]);
	if (p.flip) c.x = -c.x;
	return c;
}

function placeHandle(p) {
	const mesh = partMeshes.get(p.id);
	if (!mesh) return;
	mesh.parent.add(handle);
	handle.quaternion.copy(mesh.quaternion);
	handle.position.copy(pivotOf(p)).applyQuaternion(mesh.quaternion).add(mesh.position);
	handle.scale.set(1, 1, 1);
	handle.updateMatrixWorld(true);
}

function reparent(p) {
	const mesh = partMeshes.get(p.id);
	if (mesh && bones[p.bone] && mesh.parent !== bones[p.bone]) bones[p.bone].add(mesh);
}

function addPart(p) {
	state.parts.push(p);
	createMesh(p);
}

function removePart(id) {
	const i = state.parts.findIndex((p) => p.id === id);
	if (i < 0) return;
	const mesh = partMeshes.get(id);
	if (mesh) {
		if (state.selected === id) gizmo.detach();
		mesh.parent.remove(mesh);
		mesh.geometry.dispose();
		partMeshes.delete(id);
	}
	state.parts.splice(i, 1);
}

function rebuildAll() {
	for (const m of partMeshes.values()) { m.parent && m.parent.remove(m); m.geometry.dispose(); }
	partMeshes.clear();
	for (const p of state.parts) if (PARTS[p.def] && bones[p.bone]) createMesh(p);
	select(getPart(state.selected) ? state.selected : null, true);
}

// ================================================================ selection

function select(id, keepPanel = false) {
	for (const m of partMeshes.values()) {
		for (const c of [...m.children]) if (c.userData.fx) m.remove(c);
	}
	state.selected = id && getPart(id) ? id : null;
	const p = getPart(state.selected);
	if (p) {
		const mesh = partMeshes.get(p.id);
		const fx = new THREE.Mesh(mesh.geometry, selectMat);
		fx.userData.fx = true;
		fx.renderOrder = 10;
		fx.raycast = () => {};
		mesh.add(fx);
		const t = twinOf(p);
		if (t && partMeshes.get(t.id)) {
			const tm = partMeshes.get(t.id);
			const fx2 = new THREE.Mesh(tm.geometry, selectMatDim);
			fx2.userData.fx = true;
			fx2.renderOrder = 10;
			fx2.raycast = () => {};
			tm.add(fx2);
		}
		state.vsel = null;
		if (state.editPts) gizmo.detach();
		else { placeHandle(p); gizmo.attach(handle); }
	} else {
		gizmo.detach();
		state.editPts = false;
	}
	refreshDots();
	renderProps();
}
const selectMatDim = selectMat.clone();
selectMatDim.opacity = 0.2;

// ================================================================ placing

const raycaster = new THREE.Raycaster();
const ndc = new THREE.Vector2();

function rayFromEvent(x, y) {
	const r = renderer.domElement.getBoundingClientRect();
	ndc.set(((x - r.left) / r.width) * 2 - 1, -((y - r.top) / r.height) * 2 + 1);
	raycaster.setFromCamera(ndc, camera);
	return raycaster;
}

function overView(x, y) {
	const r = view.getBoundingClientRect();
	return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
}

// What the ray hits: a part, else a bone's body (characters) or the work
// plane (weapons: the centre plane, buildings: the ground).
function hitTest(ray, exclude = []) {
	rig.updateMatrixWorld(true);
	const targets = [];
	for (const [id, m] of partMeshes) if (!exclude.includes(id)) targets.push(m);
	let hits = ray.intersectObjects(targets, false);
	const mk = (h, bone) => ({
		point: h.point.clone(),
		normal: h.face ? h.face.normal.clone().transformDirection(h.object.matrixWorld) : new THREE.Vector3(0, 1, 0),
		bone, partId: h.object.userData.partId || null,
	});
	if (hits.length) return mk(hits[0], hits[0].object.parent.name);
	if (proxies.length) {
		hits = ray.intersectObjects(proxies, false);
		if (hits.length) return mk(hits[0], hits[0].object.userData.bone);
	}
	const plane = MODES[state.mode].plane;
	if (plane) {
		const pl = plane === 'x' ? new THREE.Plane(new THREE.Vector3(1, 0, 0), 0) : new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
		const pt = ray.ray.intersectPlane(pl, new THREE.Vector3());
		if (pt) {
			const n = pl.normal.clone();
			if (n.dot(ray.ray.direction) > 0) n.negate();
			return { point: pt, normal: n, bone: state.mode === 'weapon' ? 'rifle' : 'building', partId: null };
		}
	}
	return null;
}

function snapV(v, step) { return Math.round(v / step) * step; }

// Part orientation for a surface: +Y out of the surface, -Z toward "up".
function surfaceQuat(n, up, fwd) {
	const y = n.clone().normalize();
	let z = up.clone().addScaledVector(y, -up.dot(y));
	if (z.lengthSq() < 0.04) z = fwd.clone().addScaledVector(y, -fwd.dot(y));
	z.normalize().negate();
	const x = new THREE.Vector3().crossVectors(y, z);
	return new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(x, y, z)).toArray();
}

function homePlacement(def, side) {
	let bone = def.home.bone;
	let pos = def.home.at.slice(), quat = eulerQuat(def.home.rot), flip = false;
	if (bone.includes('*')) {
		bone = bone.replace('*', side || 'R');
		if (side === 'L') { ({ pos, quat } = mirrorLocal(pos, quat)); flip = true; }
	}
	return { bone, pos, quat, flip };
}

function placementFor(def, hit) {
	if (!hit || !bones[hit.bone]) return null;
	if (def.mount === 'home') {
		const side = boneSide(hit.bone) || (hit.point.x >= 0 ? 'R' : 'L');
		return homePlacement(def, side);
	}
	const bone = bones[hit.bone];
	const inv = bone.matrixWorld.clone().invert();
	const lp = hit.point.clone().applyMatrix4(inv);
	const cfg = MODES[state.mode];
	const snap = state.settings[state.mode].snap;
	let quat;
	if (def.mount === 'surface') {
		const n = hit.normal.clone().transformDirection(inv);
		const up = new THREE.Vector3(0, 1, 0).transformDirection(inv);
		const fwd = new THREE.Vector3(0, 0, -1).transformDirection(inv);
		quat = surfaceQuat(n, up, fwd);
		if (snap) { lp.x = snapV(lp.x, cfg.step); lp.y = snapV(lp.y, cfg.step); lp.z = snapV(lp.z, cfg.step); }
	} else {
		const bq = new THREE.Quaternion();
		bone.matrixWorld.decompose(new THREE.Vector3(), bq, new THREE.Vector3());
		quat = bq.invert().multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), state.turn)).toArray();
		if (snap) {
			if (state.mode === 'building') { lp.x = snapV(lp.x, cfg.step); lp.z = snapV(lp.z, cfg.step); lp.y = snapV(lp.y, 0.05); }
			else { lp.x = snapV(lp.x, cfg.step); lp.y = snapV(lp.y, cfg.step); lp.z = snapV(lp.z, cfg.step); }
		}
		if (state.mode === 'weapon' && state.settings.weapon.sym && Math.abs(lp.x) < 0.03) lp.x = 0;
	}
	return { bone: hit.bone, pos: lp.toArray(), quat, flip: false };
}

// Where a part goes when clicked in the palette instead of dragged.
function defaultPlacement(def) {
	if (def.mount === 'home') return homePlacement(def, 'R');
	const ray = new THREE.Raycaster();
	if (state.mode === 'humanoid') ray.set(new THREE.Vector3(0, 1.3, -3), new THREE.Vector3(0, 0, 1));
	else if (state.mode === 'weapon') ray.set(new THREE.Vector3(0, 2, -0.15), new THREE.Vector3(0, -1, 0));
	else ray.set(new THREE.Vector3(0.1, 40, 0.1), new THREE.Vector3(0, -1, 0));
	const hit = hitTest(ray);
	if (hit) return placementFor(def, hit);
	if (state.mode === 'weapon') return { bone: 'rifle', pos: [0, 0.06, -0.15], quat: [0, 0, 0, 1], flip: false };
	return null;
}

function placeNew(def, pl) {
	if (!pl) return null;
	if (def.marker) for (const q of state.parts.filter((x) => PARTS[x.def].marker === def.marker)) removePart(q.id);
	const p = newPart(def.id, pl.bone, pl.pos, pl.quat, { flip: pl.flip });
	addPart(p);
	if (wantsTwin(p)) addPart(makeTwin(p));
	select(p.id);
	commit();
	status(`Added ${def.name}${p.pair ? ' (with mirrored twin)' : ''}.`);
	return p;
}

// ================================================================ palette

const thumbCache = {};
let thumbRenderer = null;

function thumbFor(def) {
	if (thumbCache[def.id]) return thumbCache[def.id];
	if (!thumbRenderer) {
		thumbRenderer = new THREE.WebGLRenderer({ antialias: false, preserveDrawingBuffer: true, alpha: true });
		thumbRenderer.setSize(64, 64);
		thumbRenderer.setPixelRatio(1);
		thumbRenderer.userData = { scene: new THREE.Scene(), cam: new THREE.PerspectiveCamera(30, 1, 0.001, 100) };
		const s = thumbRenderer.userData.scene;
		s.add(new THREE.HemisphereLight(0xe4ecff, 0x40382c, 2.4));
		const d = new THREE.DirectionalLight(0xffffff, 2.2);
		d.position.set(-1, 2, -2);
		s.add(d);
	}
	const { scene: ts, cam } = thumbRenderer.userData;
	const p = newPart(def.id, '', [0, 0, 0], [0, 0, 0, 1]);
	const geo = buildPartGeometry(def, p);
	const mesh = new THREE.Mesh(geo, partMaterials(p));
	ts.add(mesh);
	const sph = geo.boundingSphere;
	const dir = def.mode === 'weapon' ? new THREE.Vector3(1, 0.35, -0.45) : def.mode === 'building' ? new THREE.Vector3(0.8, 0.7, -1) : new THREE.Vector3(0.65, 0.4, -1);
	dir.normalize();
	const dist = sph.radius / Math.sin((cam.fov / 2) * DEG) * 1.05;
	cam.position.copy(sph.center).addScaledVector(dir, dist);
	cam.near = dist / 50; cam.far = dist * 4;
	cam.updateProjectionMatrix();
	cam.lookAt(sph.center);
	const keep = psxUniforms.psxRes.value.clone();
	psxUniforms.psxRes.value.set(0, 0);
	thumbRenderer.render(ts, cam);
	psxUniforms.psxRes.value.copy(keep);
	const url = thumbRenderer.domElement.toDataURL();
	ts.remove(mesh);
	geo.dispose();
	thumbCache[def.id] = url;
	return url;
}

const closedCats = new Set(JSON.parse(localStorage.getItem('sqm.closedCats') || '[]'));

function buildPalette() {
	const pal = $('#palette');
	pal.innerHTML = '';
	const pending = [];
	const imp = document.createElement('div');
	imp.style.padding = '8px';
	imp.append(el('button', { class: 'btn', style: 'width:100%', title: 'Add any .glb model as a part (or drop a .glb onto the page)', onclick: () => $('#importIn').click() }, '⇪ Import .glb model'));
	pal.append(imp);
	const cats = [];
	const ids = Object.keys(state.meshes).map((id) => 'imp:' + id).filter((id) => PARTS[id]);
	if (ids.length) cats.push({ name: 'Imported', parts: ids });
	for (const cat of cats.concat(CATEGORIES[state.mode])) {
		const sec = document.createElement('div');
		sec.className = 'cat' + (closedCats.has(state.mode + cat.name) ? ' closed' : '');
		const h = document.createElement('h3');
		h.innerHTML = `<span>${cat.name}</span><span>${cat.parts.length}</span>`;
		h.onclick = () => {
			sec.classList.toggle('closed');
			const k = state.mode + cat.name;
			if (sec.classList.contains('closed')) closedCats.add(k); else closedCats.delete(k);
			localStorage.setItem('sqm.closedCats', JSON.stringify([...closedCats]));
		};
		const g = document.createElement('div');
		g.className = 'grid';
		for (const id of cat.parts) {
			const def = PARTS[id];
			const t = document.createElement('div');
			t.className = 'thumb';
			t.title = def.name + (def.mount === 'home' ? ' (snaps into place)' : def.mount === 'surface' ? ' (sticks where dropped)' : '') + (def.desc ? '\n' + def.desc : '');
			const img = document.createElement('img');
			t.append(img);
			const sp = document.createElement('span');
			sp.textContent = def.name;
			t.append(sp);
			t.addEventListener('pointerdown', (e) => startPaletteDrag(e, def));
			g.append(t);
			pending.push([img, def]);
		}
		sec.append(h, g);
		pal.append(sec);
	}
	// thumbnails in small batches so the page stays responsive
	const step = () => {
		const t0 = performance.now();
		while (pending.length && performance.now() - t0 < 12) {
			const [img, def] = pending.shift();
			img.src = thumbFor(def);
		}
		if (pending.length) requestAnimationFrame(step);
	};
	requestAnimationFrame(step);
}

// ---- dragging from the palette

let pdrag = null;

function makeGhost(def, flip) {
	const p = newPart(def.id, '', [0, 0, 0], [0, 0, 0, 1], { flip });
	const m = new THREE.Mesh(buildPartGeometry(def, p), ghostMat);
	m.renderOrder = 5;
	m.raycast = () => {};
	m.visible = false;
	return m;
}

function startPaletteDrag(e, def) {
	e.preventDefault();
	pdrag = { def, x: e.clientX, y: e.clientY, moved: false, ghosts: null, pl: null };
	window.addEventListener('pointermove', onPaletteMove);
	window.addEventListener('pointerup', onPaletteUp, { once: true });
}

function onPaletteMove(e) {
	if (!pdrag) return;
	if (!pdrag.moved && Math.hypot(e.clientX - pdrag.x, e.clientY - pdrag.y) > 5) {
		pdrag.moved = true;
		pdrag.ghosts = [makeGhost(pdrag.def, false), makeGhost(pdrag.def, true), makeGhost(pdrag.def, true), makeGhost(pdrag.def, false)];
		document.body.style.cursor = 'grabbing';
	}
	if (!pdrag.moved) return;
	const [g, gf, tw, twf] = pdrag.ghosts;
	for (const x of pdrag.ghosts) x.visible = false;
	pdrag.pl = null;
	if (overView(e.clientX, e.clientY)) {
		const pl = placementFor(pdrag.def, hitTest(rayFromEvent(e.clientX, e.clientY)));
		if (pl) {
			pdrag.pl = pl;
			const main = pl.flip ? gf : g;
			bones[pl.bone].add(main);
			main.position.set(...pl.pos);
			main.quaternion.set(...pl.quat);
			main.visible = true;
			const probe = { def: pdrag.def.id, bone: pl.bone, pos: pl.pos };
			if (wantsTwin(probe)) {
				const tg = pl.flip ? twf : tw;
				const m = mirrorLocal(pl.pos, pl.quat);
				bones[otherSide(pl.bone) || pl.bone].add(tg);
				tg.position.set(...m.pos);
				tg.quaternion.set(...m.quat);
				tg.visible = true;
			}
		}
	}
	$('#dropHint').style.display = overView(e.clientX, e.clientY) && !pdrag.pl ? 'flex' : 'none';
}

function onPaletteUp(e) {
	window.removeEventListener('pointermove', onPaletteMove);
	document.body.style.cursor = '';
	$('#dropHint').style.display = 'none';
	if (!pdrag) return;
	const d = pdrag;
	pdrag = null;
	if (d.ghosts) for (const gh of d.ghosts) { gh.parent && gh.parent.remove(gh); gh.geometry.dispose(); }
	if (!d.moved) {
		const pl = defaultPlacement(d.def);
		if (pl) placeNew(d.def, pl);
		else status('Drag that one onto the model.');
		return;
	}
	if (d.pl && overView(e.clientX, e.clientY)) placeNew(d.def, d.pl);
}

// ================================================================ viewport input

let vdown = null;

renderer.domElement.addEventListener('pointerdown', (e) => {
	if (e.button !== 0 || gizmo.dragging) return;
	if (state.editPts && state.selected) {
		const i = pickDot(e.clientX, e.clientY);
		if (i != null) { selectDot(i); vdown = null; return; }
	}
	const hit = hitTest(rayFromEvent(e.clientX, e.clientY));
	vdown = { x: e.clientX, y: e.clientY, id: hit && hit.partId, moved: false };
	if (hit && hit.partId) {
		if (state.selected !== hit.partId) select(hit.partId);
		orbit.enabled = false;
		renderer.domElement.setPointerCapture(e.pointerId);
	}
});

renderer.domElement.addEventListener('pointermove', (e) => {
	if (!vdown || !vdown.id || state.editPts) return;
	if (!vdown.moved && Math.hypot(e.clientX - vdown.x, e.clientY - vdown.y) < 5) return;
	vdown.moved = true;
	const p = getPart(vdown.id);
	if (!p) return;
	const def = PARTS[p.def];
	const t = twinOf(p);
	const hit = hitTest(rayFromEvent(e.clientX, e.clientY), [p.id, t && t.id]);
	const pl = placementFor(def, hit);
	if (!pl) return;
	p.pos = pl.pos; p.quat = pl.quat;
	const flipChanged = def.mount === 'home' && p.flip !== pl.flip;
	if (def.mount === 'home') p.flip = pl.flip;
	if (p.bone !== pl.bone) { p.bone = pl.bone; reparent(p); }
	if (flipChanged) rebuildMesh(p);
	syncTransform(p);
	if (t) {
		if (flipChanged) { t.flip = !p.flip; rebuildMesh(t); }
		mirrorInto(p, t);
	}
});

renderer.domElement.addEventListener('pointerup', (e) => {
	orbit.enabled = true;
	if (!vdown) return;
	const d = vdown;
	vdown = null;
	if (d.moved) { commit(); renderProps(); return; }
	if (!d.id && Math.hypot(e.clientX - d.x, e.clientY - d.y) < 4 && !gizmo.dragging && !gizmo.axis) select(null);
});

// ---- gizmo

let gizmoStart = null;
gizmo.addEventListener('dragging-changed', (e) => {
	orbit.enabled = !e.value;
	const p = getPart(state.selected);
	if (e.value) { gizmoStart = true; return; }
	if (!p) return;
	if (state.editPts) { commit(); renderProps(); return; }
	const mesh = partMeshes.get(p.id);
	if (gizmo.mode === 'scale') {
		const s = handle.scale;
		p.size = [p.size[0] * s.x, p.size[1] * s.y, p.size[2] * s.z].map((v) => Math.max(0.02, Math.round(v * 1000) / 1000));
		mesh.scale.set(1, 1, 1);
		// the size is now baked around the pivot: put the mesh back on the handle
		mesh.position.copy(handle.position).sub(pivotOf(p).applyQuaternion(handle.quaternion));
		p.pos = mesh.position.toArray();
		handle.scale.set(1, 1, 1);
		const t = twinOf(p);
		rebuildMesh(p);
		if (t) { copyLook(p, t); const tm = partMeshes.get(t.id); tm && tm.scale.set(1, 1, 1); rebuildMesh(t); mirrorInto(p, t); }
	}
	placeHandle(p);
	commit();
	renderProps();
});

gizmo.addEventListener('objectChange', () => {
	const p = getPart(state.selected);
	if (!p) return;
	if (state.editPts) { moveDot(); return; }
	const mesh = partMeshes.get(p.id);
	mesh.quaternion.copy(handle.quaternion);
	mesh.scale.copy(handle.scale);
	mesh.position.copy(handle.position).sub(pivotOf(p).multiply(handle.scale).applyQuaternion(handle.quaternion));
	p.pos = mesh.position.toArray().map((v) => Math.round(v * 10000) / 10000);
	p.quat = mesh.quaternion.toArray();
	const t = twinOf(p);
	if (t) {
		mirrorInto(p, t);
		const tm = partMeshes.get(t.id);
		if (tm) tm.scale.copy(mesh.scale);
	}
});

function setGizmoMode(m) {
	gizmo.setMode(m);
	for (const b of document.querySelectorAll('#gizmoBar .btn')) b.classList.toggle('on', b.dataset.g === m);
}
for (const b of document.querySelectorAll('#gizmoBar .btn')) b.onclick = () => setGizmoMode(b.dataset.g);

function applySnapToGizmo() {
	const s = state.settings[state.mode].snap;
	gizmo.setTranslationSnap(s ? MODES[state.mode].step : null);
	gizmo.setRotationSnap(s ? 15 * DEG : null);
	gizmo.setScaleSnap(s ? 0.05 : null);
}

// ================================================================ actions

function deleteSelected() {
	const p = getPart(state.selected);
	if (!p) return;
	const t = twinOf(p);
	removePart(p.id);
	if (t) removePart(t.id);
	select(null);
	commit();
	status(`Deleted ${PARTS[p.def].name}${t ? ' and its twin' : ''}.`);
}

function duplicateSelected() {
	const p = getPart(state.selected);
	if (!p) return;
	const def = PARTS[p.def];
	const t = twinOf(p);
	const c = JSON.parse(JSON.stringify(p));
	c.id = uid();
	c.pair = null;
	if (state.mode === 'building') c.pos[0] += 1;
	else if (state.mode === 'weapon') c.pos[2] -= 0.04;
	else if (def.mount !== 'home') {
		const off = new THREE.Vector3(0.05, 0, 0).applyQuaternion(new THREE.Quaternion(...p.quat));
		c.pos = [c.pos[0] + off.x, c.pos[1] + off.y, c.pos[2] + off.z];
	}
	addPart(c);
	if (t) addPart(makeTwin(c));
	select(c.id);
	commit();
	status(`Duplicated ${def.name}.`);
}

function turnSelected() {
	const p = getPart(state.selected);
	if (!p) {
		state.turn = (state.turn + Math.PI / 2) % (Math.PI * 2);
		status(`Next piece turned ${Math.round(state.turn / DEG)}°.`);
		return;
	}
	const mesh = partMeshes.get(p.id);
	placeHandle(p);
	if (state.mode === 'humanoid') handle.rotateOnAxis(new THREE.Vector3(0, 1, 0), Math.PI / 2);
	else handle.rotateOnWorldAxis(new THREE.Vector3(0, 1, 0), Math.PI / 2);
	mesh.quaternion.copy(handle.quaternion);
	mesh.position.copy(handle.position).sub(pivotOf(p).applyQuaternion(handle.quaternion));
	p.pos = mesh.position.toArray();
	p.quat = mesh.quaternion.toArray();
	const t = twinOf(p);
	if (t) mirrorInto(p, t);
	placeHandle(p);
	commit();
}

function frameSelected() {
	const p = getPart(state.selected);
	const box = new THREE.Box3();
	if (p) box.setFromObject(partMeshes.get(p.id));
	else for (const m of partMeshes.values()) box.expandByObject(m);
	if (box.isEmpty()) return resetCamera();
	const c = box.getCenter(new THREE.Vector3());
	const r = box.getSize(new THREE.Vector3()).length() * 0.5;
	const dir = camera.position.clone().sub(orbit.target).normalize();
	orbit.target.copy(c);
	camera.position.copy(c).addScaledVector(dir, Math.max(r / Math.sin((camera.fov / 2) * DEG), 0.3));
	orbit.update();
}

function resetCamera() {
	const cfg = MODES[state.mode];
	orbit.target.set(...cfg.target);
	camera.position.set(...cfg.cam);
	orbit.update();
}

// ================================================================ history & storage

const hist = {};

function serialize() {
	const d = { format: FORMAT, version: VERSION, mode: state.mode, name: state.name, parts: state.parts };
	if (Object.keys(state.meshes).length) d.meshes = state.meshes;
	return d;
}

function commit() {
	const h = hist[state.mode];
	const snap = JSON.stringify(serialize());
	if (h.stack[h.i] !== snap) {
		h.stack.length = h.i + 1;
		h.stack.push(snap);
		if (h.stack.length > 150) h.stack.shift();
		h.i = h.stack.length - 1;
	}
	try { localStorage.setItem('sqm.autosave.' + state.mode, snap); } catch (e) { /* storage full or blocked */ }
	updateStats();
	updateTopbar();
}

function restore(snap) {
	const d = JSON.parse(snap);
	state.name = d.name;
	useMeshes(d.meshes);
	state.parts = d.parts;
	rebuildAll();
	updateStats();
	updateTopbar();
}

function undo() {
	const h = hist[state.mode];
	if (h.i > 0) { h.i--; restore(h.stack[h.i]); localStorage.setItem('sqm.autosave.' + state.mode, h.stack[h.i]); status('Undo.'); }
}
function redo() {
	const h = hist[state.mode];
	if (h.i < h.stack.length - 1) { h.i++; restore(h.stack[h.i]); localStorage.setItem('sqm.autosave.' + state.mode, h.stack[h.i]); status('Redo.'); }
}

// Template entries: [part id, bone?, { pos, rot | normal, mirror, colors, size, ... }]
function templateParts(mode, key) {
	const tpl = TEMPLATES[mode][key];
	const out = [];
	for (const [id, boneArg, o = {}] of tpl.parts) {
		const def = PARTS[id];
		if (!def) continue;
		let pl;
		if (o.pos) {
			const bone = (boneArg || (def.home && def.home.bone) || '').replace('*', 'R');
			let quat = eulerQuat(o.rot);
			if (o.normal) quat = surfaceQuat(new THREE.Vector3(...o.normal), new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, 0, -1));
			pl = { bone, pos: o.pos, quat, flip: false };
		} else pl = homePlacement(def, 'R');
		const p = newPart(id, pl.bone, pl.pos, pl.quat, Object.assign({ flip: pl.flip }, o));
		out.push(p);
		const mirror = o.mirror !== false && !def.marker && (boneSide(p.bone) || Math.abs(p.pos[0]) > 0.015);
		if (mirror && (MODES[mode].sym || boneSide(p.bone))) out.push(makeTwin(p));
	}
	return out;
}

// ================================================================ imported models

function registerImport(id, rec) {
	MESHES.set(id, rec);
	const n = rec.pos.length / 9;
	PARTS['imp:' + id] = {
		id: 'imp:' + id, name: rec.name, mode: state.mode, cat: 'Imported',
		shapes: [{ p: 'mesh', mesh: id }], mount: 'upright', home: null,
		colors: { main: '#9a9a9a', ink: '#1a1b1d', trim: '#2f3235', detail: '#6ce0d0' },
		pattern: 'solid', patScale: 0.25, glow: false, morph: {}, marker: null, imported: true,
		desc: `Imported model, ${n} triangles. Use Simplify to cut triangles.`,
	};
}

// Make `meshes` (from a design) the current imported set.
function useMeshes(meshes) {
	const before = Object.keys(state.meshes).join();
	state.meshes = meshes || {};
	for (const [id, rec] of Object.entries(state.meshes)) registerImport(id, rec);
	if (Object.keys(state.meshes).join() !== before) buildPalette();
}

const MAX_IMPORT_TRIS = 4000;

// Reads any .glb: every mesh is flattened into one part (in its own colours:
// material colour x texture colour sampled at each triangle), stood on its
// base at the origin, scaled to a sensible size if it is huge or tiny, and
// thinned to at most MAX_IMPORT_TRIS triangles.
async function importGLB(file) {
	const buf = await file.arrayBuffer();
	const gltf = await new Promise((res, rej) => new GLTFLoader().parse(buf, '', res, rej));
	gltf.scene.updateMatrixWorld(true);
	const samplers = new Map();
	const sampler = (tex) => {
		if (!tex || !tex.image) return null;
		if (samplers.has(tex)) return samplers.get(tex);
		let fn = null;
		try {
			const img = tex.image;
			const w = Math.min(img.width || 256, 256), h = Math.min(img.height || 256, 256);
			const cv = document.createElement('canvas');
			cv.width = w; cv.height = h;
			const ctx = cv.getContext('2d');
			ctx.drawImage(img, 0, 0, w, h);
			const data = ctx.getImageData(0, 0, w, h).data;
			fn = (u, v) => {
				u = u - Math.floor(u); v = v - Math.floor(v);
				if (!tex.flipY) v = v; else v = 1 - v;
				const x = Math.min(w - 1, Math.floor(u * w)), y = Math.min(h - 1, Math.floor(v * h));
				const i = (y * w + x) * 4;
				return [data[i] / 255, data[i + 1] / 255, data[i + 2] / 255];
			};
		} catch (e) { fn = null; }
		samplers.set(tex, fn);
		return fn;
	};
	const toLinear = (c) => new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);
	let tris = [];
	gltf.scene.traverse((o) => {
		if (!o.isMesh || !o.geometry || !o.geometry.attributes.position) return;
		const g = o.geometry.index ? o.geometry.toNonIndexed() : o.geometry;
		const P = g.attributes.position, UV = g.attributes.uv, VC = g.attributes.color;
		const mats = Array.isArray(o.material) ? o.material : [o.material];
		const groups = g.groups.length ? g.groups : [{ start: 0, count: P.count, materialIndex: 0 }];
		for (const gr of groups) {
			const mat = mats[gr.materialIndex || 0] || mats[0] || {};
			const base = mat.color ? mat.color.clone() : new THREE.Color(1, 1, 1);
			const smp = sampler(mat.map);
			for (let i = gr.start; i + 2 < gr.start + gr.count; i += 3) {
				const v = [0, 1, 2].map((k) => new THREE.Vector3().fromBufferAttribute(P, i + k).applyMatrix4(o.matrixWorld));
				const c = base.clone();
				if (smp && UV) {
					const u = (UV.getX(i) + UV.getX(i + 1) + UV.getX(i + 2)) / 3, w = (UV.getY(i) + UV.getY(i + 1) + UV.getY(i + 2)) / 3;
					c.multiply(toLinear(smp(u, w)));
				}
				if (VC) c.multiply(new THREE.Color(VC.getX(i), VC.getY(i), VC.getZ(i)));
				// stored as display colours (sRGB) so the swatches and export match
				const sc = c.clone().convertLinearToSRGB();
				tris.push({ v, m: 0, c: [sc.r, sc.g, sc.b] });
			}
		}
	});
	if (!tris.length) throw new Error('No meshes found in that .glb.');
	const box = new THREE.Box3();
	for (const t of tris) for (const v of t.v) box.expandByPoint(v);
	const size = box.getSize(new THREE.Vector3());
	const big = Math.max(size.x, size.y, size.z);
	const fit = { humanoid: 0.4, weapon: 0.8, building: 4 }[state.mode];
	const k = big > fit * 8 || big < fit / 8 ? fit / big : 1;
	const c = box.getCenter(new THREE.Vector3());
	for (const t of tris) for (const v of t.v) { v.x = (v.x - c.x) * k; v.y = (v.y - box.min.y) * k; v.z = (v.z - c.z) * k; }
	const orig = tris.length;
	let cell = big * k * 0.004;
	while (tris.length > MAX_IMPORT_TRIS) { tris = clusterTris(tris, cell); cell *= 1.4; }
	const r4 = (n) => Math.round(n * 10000) / 10000;
	const r3 = (n) => Math.round(n * 1000) / 1000;
	const rec = { name: file.name.replace(/\.glb$/i, '').slice(0, 40), pos: [], col: [] };
	for (const t of tris) {
		for (const v of t.v) rec.pos.push(r4(v.x), r4(v.y), r4(v.z));
		rec.col.push(r3(t.c[0]), r3(t.c[1]), r3(t.c[2]));
	}
	const id = 'm' + Date.now().toString(36);
	state.meshes[id] = rec;
	registerImport(id, rec);
	buildPalette();
	const def = PARTS['imp:' + id];
	const pl = defaultPlacement(def) || { bone: Object.keys(bones)[0], pos: [0, 0, 0], quat: [0, 0, 0, 1], flip: false };
	const p = placeNew(def, pl);
	status(`Imported ${rec.name}: ${tris.length} triangles` + (orig > tris.length ? ` (thinned from ${orig})` : '') + (k !== 1 ? `, rescaled ×${k.toPrecision(2)}` : '') + '. Drag it into place; Simplify cuts triangles.');
	renderProps();
}

async function importFiles(files) {
	for (const f of files) {
		if (!/\.glb$/i.test(f.name)) { toast(`${f.name}: only .glb files can be imported.`); continue; }
		try { await importGLB(f); } catch (err) { console.error(err); toast(`Could not import ${f.name}: ${err.message}`); }
	}
}

function loadTemplate(key) {
	state.parts = templateParts(state.mode, key);
	state.name = key;
	state.selected = null;
	rebuildAll();
	commit();
	status(`Started from the ${TEMPLATES[state.mode][key].name} template.`);
}

function loadDesign(d) {
	if (!d || d.format !== FORMAT || !Array.isArray(d.parts)) throw new Error('That file is not a Squad Modeller design.');
	if (d.mode !== state.mode) setMode(d.mode, false);
	useMeshes(d.meshes);
	const missing = d.parts.filter((p) => !PARTS[p.def]).length;
	state.parts = d.parts.filter((p) => PARTS[p.def]);
	state.name = d.name || 'model';
	state.selected = null;
	rebuildAll();
	commit();
	status(`Opened ${state.name}.` + (missing ? ` ${missing} unknown parts were skipped.` : ''));
}

// ================================================================ modes

function setMode(mode, loadSaved = true) {
	state.mode = mode;
	localStorage.setItem('sqm.mode', mode);
	if (!state.settings[mode]) {
		let s = null;
		try { s = JSON.parse(localStorage.getItem('sqm.settings.' + mode) || 'null'); } catch (e) { s = null; }
		state.settings[mode] = s || { sym: MODES[mode].sym, snap: MODES[mode].snap };
	}
	if (!hist[mode]) hist[mode] = { stack: [], i: -1 };
	state.selected = null;
	state.turn = 0;
	if (mode !== 'humanoid') state.pose = 'rest';
	$('#poseSel').value = state.pose;
	buildRig();
	buildPalette();
	resetCamera();
	applySnapToGizmo();
	const sel = $('#templateSel');
	sel.innerHTML = '';
	for (const [k, t] of Object.entries(TEMPLATES[mode])) {
		const o = document.createElement('option');
		o.value = k; o.textContent = t.name;
		sel.append(o);
	}
	if (loadSaved) {
		const h = hist[mode];
		if (h.stack.length) restore(h.stack[h.i]);
		else {
			let saved = null;
			try { saved = JSON.parse(localStorage.getItem('sqm.autosave.' + mode) || 'null'); } catch (e) { saved = null; }
			if (saved && Array.isArray(saved.parts)) {
				useMeshes(saved.meshes);
				state.parts = saved.parts.filter((p) => PARTS[p.def]);
				state.name = saved.name || mode;
				rebuildAll();
				commit();
			} else loadTemplate(MODES[mode].template);
		}
	}
	$('#overlay').textContent = MODES[mode].hint;
	updateTopbar();
	updateStats();
	renderProps();
}

// ================================================================ UI: top bar

function updateTopbar() {
	for (const b of document.querySelectorAll('#modeTabs .btn')) b.classList.toggle('on', b.dataset.mode === state.mode);
	const s = state.settings[state.mode];
	$('#btnSym').classList.toggle('on', s.sym);
	$('#btnSnap').classList.toggle('on', s.snap);
	$('#btnPsx').classList.toggle('on', state.psx);
	$('#btnBones').classList.toggle('on', state.showBones);
	$('#btnBones').style.display = state.mode === 'humanoid' ? '' : 'none';
	$('#poseSel').style.display = state.mode === 'humanoid' ? '' : 'none';
	const h = hist[state.mode];
	$('#btnUndo').disabled = !h || h.i <= 0;
	$('#btnRedo').disabled = !h || h.i >= h.stack.length - 1;
}

function saveSettings() {
	localStorage.setItem('sqm.settings.' + state.mode, JSON.stringify(state.settings[state.mode]));
}

for (const b of document.querySelectorAll('#modeTabs .btn')) b.onclick = () => { if (b.dataset.mode !== state.mode) setMode(b.dataset.mode); };
$('#btnNew').onclick = () => {
	const k = $('#templateSel').value;
	if (state.parts.length && !confirm(`Replace the current ${MODES[state.mode].label.toLowerCase()} with the ${TEMPLATES[state.mode][k].name} template? (Undo can bring it back.)`)) return;
	loadTemplate(k);
};
$('#btnUndo').onclick = undo;
$('#btnRedo').onclick = redo;
$('#btnSym').onclick = toggleSym;
$('#btnSnap').onclick = toggleSnap;
$('#btnPsx').onclick = togglePsx;
$('#btnBones').onclick = () => { state.showBones = !state.showBones; proxyMat.visible = state.showBones; updateTopbar(); };
$('#poseSel').onchange = (e) => { state.pose = e.target.value; applyPose(clock.getElapsedTime()); status(e.target.selectedOptions[0].textContent + ' — the same pose code the game uses.'); };
$('#btnSave').onclick = saveFile;
$('#btnOpen').onclick = () => $('#fileIn').click();
$('#btnImport').onclick = () => $('#importIn').click();
$('#importIn').onchange = (e) => { const fs = [...e.target.files]; e.target.value = ''; importFiles(fs); };
window.addEventListener('dragover', (e) => { if ([...e.dataTransfer.items].some((i) => i.kind === 'file')) { e.preventDefault(); $('#dropHint').textContent = 'Drop a .glb to import it'; $('#dropHint').style.display = 'flex'; } });
window.addEventListener('dragleave', (e) => { if (!e.relatedTarget) $('#dropHint').style.display = 'none'; });
window.addEventListener('drop', (e) => {
	$('#dropHint').style.display = 'none';
	$('#dropHint').textContent = 'Drop onto the model';
	if (!e.dataTransfer.files.length) return;
	e.preventDefault();
	importFiles([...e.dataTransfer.files]);
});
$('#btnExport').onclick = exportFile;
$('#btnHelp').onclick = () => { $('#help').style.display = 'flex'; };
$('#helpClose').onclick = () => { $('#help').style.display = 'none'; };
$('#help').onclick = (e) => { if (e.target.id === 'help') $('#help').style.display = 'none'; };

function toggleSym() {
	const s = state.settings[state.mode];
	s.sym = !s.sym;
	saveSettings();
	updateTopbar();
	status(s.sym ? 'Symmetry on: new parts get a mirrored twin.' : 'Symmetry off: new parts are single.');
}
function toggleSnap() {
	const s = state.settings[state.mode];
	s.snap = !s.snap;
	saveSettings();
	applySnapToGizmo();
	updateTopbar();
	status(s.snap ? `Snap on (${MODES[state.mode].step} m, 15°).` : 'Snap off.');
}
function togglePsx() {
	state.psx = !state.psx;
	localStorage.setItem('sqm.psx', state.psx ? '1' : '0');
	resize();
	updateTopbar();
}

function safeName() { return (state.name || 'model').replace(/[^\w\-]+/g, '_').slice(0, 60) || 'model'; }

function saveFile() {
	download(JSON.stringify(serialize(), null, 1), `${safeName()}.squadmodel.json`, 'application/json');
	status(`Saved ${safeName()}.squadmodel.json to your downloads.`);
}

async function exportFile() {
	try {
		const buf = await exportGLB(serialize());
		const prefix = { humanoid: 'char', weapon: 'weapon', building: 'building' }[state.mode];
		download(buf, `${prefix}_${safeName()}.glb`, 'model/gltf-binary');
		status(`Exported ${prefix}_${safeName()}.glb (${(buf.byteLength / 1024).toFixed(0)} KB). Send it over and it goes into the game.`);
	} catch (err) {
		console.error(err);
		toast('Export failed: ' + err.message);
	}
}

$('#fileIn').onchange = async (e) => {
	const f = e.target.files[0];
	e.target.value = '';
	if (!f) return;
	try {
		let d;
		if (f.name.toLowerCase().endsWith('.glb')) {
			d = readGLBDesign(await f.arrayBuffer());
			if (!d) throw new Error('That .glb has no Squad Modeller design inside.');
		} else d = JSON.parse(await f.text());
		loadDesign(d);
	} catch (err) {
		toast(err.message);
	}
};

// ================================================================ UI: right panel

function el(tag, attrs = {}, ...kids) {
	const e = document.createElement(tag);
	for (const [k, v] of Object.entries(attrs)) {
		if (k === 'class') e.className = v;
		else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
		else if (v !== undefined && v !== null) e.setAttribute(k, v);
	}
	for (const k of kids) if (k != null) e.append(k);
	return e;
}

function slider(label, min, max, step, value, onInput, fmt = (v) => (+v).toFixed(2)) {
	const val = el('span', { class: 'val' }, fmt(value));
	const inp = el('input', { type: 'range', min, max, step, value });
	inp.addEventListener('input', () => { val.textContent = fmt(inp.value); onInput(+inp.value); });
	inp.addEventListener('change', () => commit());
	inp.addEventListener('dblclick', () => { const d = label === 'Twist' || label === 'Sides' ? 0 : (min < 0 ? 0 : 1); inp.value = d; inp.dispatchEvent(new Event('input')); commit(); });
	return el('div', { class: 'row' }, el('label', {}, label), inp, val);
}

function renderProps() {
	const box = $('#props');
	box.innerHTML = '';
	const p = getPart(state.selected);
	if (!p) return renderModelPanel(box);
	const def = PARTS[p.def];
	const t = twinOf(p);
	const boneLabel = (BONES[state.mode].find((b) => b.name === p.bone) || {}).label || p.bone;
	box.append(el('h2', {}, def.name));
	box.append(el('div', { class: 'sub' }, `on ${boneLabel}` + (t ? ' · mirrored twin' : '') + (def.mount === 'home' ? ' · snaps into place' : '')));
	const acts = el('div', { class: 'btns' },
		el('button', { class: 'btn', onclick: duplicateSelected, title: 'Ctrl+D' }, 'Duplicate'),
		el('button', { class: 'btn', onclick: deleteSelected, title: 'Delete' }, 'Delete'),
	);
	if (t) acts.append(el('button', { class: 'btn', title: 'Split from its twin so each can be edited alone', onclick: () => { p.pair = null; t.pair = null; select(p.id); commit(); status('Unlinked from the twin.'); } }, 'Unlink twin'));
	else if (!def.marker) acts.append(el('button', { class: 'btn', title: 'Add a mirrored copy on the other side', onclick: () => { addPart(makeTwin(p)); select(p.id); commit(); } }, 'Add twin'));
	if (def.mount === 'home') acts.append(el('button', { class: 'btn', title: 'Put it back in its default spot', onclick: () => {
		const pl = homePlacement(def, boneSide(p.bone) || 'R');
		Object.assign(p, { pos: pl.pos, quat: pl.quat });
		syncTransform(p);
		if (t) mirrorInto(p, t);
		commit();
	} }, 'Snap home'));
	else acts.append(el('button', { class: 'btn', title: 'Q turns 90°', onclick: turnSelected }, 'Turn 90°'));
	box.append(acts);
	if (def.desc) box.append(el('div', { class: 'tip' }, def.desc));

	if (!p.vcol) {
	// colours
	box.append(el('h4', {}, 'Colours'));
	const slots = [['main', 'Main'], ['ink', 'Pattern'], ['trim', 'Trim'], ['detail', 'Detail']];
	const used = new Set(def.shapes.map((s) => s.m || 'main'));
	for (const [k, lab] of slots) {
		if ((k === 'trim' || k === 'detail') && !used.has(k)) continue;
		if (k === 'ink' && p.pattern === 'solid') continue;
		const inp = el('input', { type: 'color', value: p.colors[k] });
		inp.addEventListener('input', () => { editSelected((q) => { q.colors[k] = inp.value; }); });
		inp.addEventListener('change', () => { commit(); refreshPatternSwatches(); });
		const row = el('div', { class: 'colrow' + (state.colorSlot === k ? ' active' : '') }, inp, el('span', {}, lab));
		row.addEventListener('click', (e) => {
			state.colorSlot = k;
			for (const r of box.querySelectorAll('.colrow')) r.classList.remove('active');
			row.classList.add('active');
		});
		row.dataset.slot = k;
		box.append(row);
	}
	if (![...box.querySelectorAll('.colrow')].some((r) => r.dataset.slot === state.colorSlot)) {
		state.colorSlot = 'main';
		const r = box.querySelector('.colrow');
		r && r.classList.add('active');
	}
	const sw = el('div', { class: 'swatches' });
	for (const c of SWATCHES) {
		const d = el('div', { title: c });
		d.style.background = c;
		d.onclick = () => {
			const k = state.colorSlot;
			editSelected((q) => { q.colors[k] = c; });
			const inp = box.querySelector(`.colrow[data-slot="${k}"] input`);
			if (inp) inp.value = c;
			commit();
			refreshPatternSwatches();
		};
		sw.append(d);
	}
	box.append(sw);
	if (used.has('detail')) {
		const cb = el('input', { type: 'checkbox' });
		cb.checked = !!p.glow;
		cb.onchange = () => { editSelected((q) => { q.glow = cb.checked; }); commit(); };
		box.append(el('label', { class: 'chk' }, cb, 'Detail glows (lenses, lights)'));
	}

	// pattern
	box.append(el('h4', {}, 'Pattern'));
	const pats = el('div', { class: 'patterns', id: 'patGrid' });
	box.append(pats);
	refreshPatternSwatches();
	box.append(slider('Pattern size', 0.03, 2, 0.01, p.patScale, (v) => editSelected((q) => { q.patScale = v; }), (v) => (+v).toFixed(2) + 'm'));

	}
	// size
	box.append(el('h4', {}, 'Size'));
	const geo = (v) => Math.cbrt(v[0] * v[1] * v[2]);
	let allBase = geo(p.size);
	box.append(slider('All', 0.2, 3, 0.01, allBase, (v) => {
		const k = v / allBase;
		allBase = v;
		editSelected((q) => { q.size = q.size.map((s) => Math.max(0.02, s * k)); });
	}));
	['X (width)', 'Y (height)', 'Z (depth)'].forEach((lab, i) => {
		box.append(slider(lab, 0.1, 4, 0.01, p.size[i], (v) => editSelected((q) => { q.size[i] = v; })));
	});

	if (def.imported) {
		box.append(el('h4', {}, 'Imported model'));
		const own = el('input', { type: 'checkbox' });
		own.checked = !!p.vcol;
		own.onchange = () => { editSelected((q) => { q.vcol = own.checked; }); commit(); renderProps(); };
		box.append(el('label', { class: 'chk' }, own, 'Use its own colours (off: use Main colour + pattern)'));
		const tc = el('div', { class: 'tip' }, `${triangleCount(partMeshes.get(p.id).geometry)} triangles`);
		box.append(slider('Simplify', 0, 1, 0.01, p.simplify || 0, (v) => {
			editSelected((q) => { q.simplify = v; if (q.verts && Object.keys(q.verts).length) q.verts = {}; });
			tc.textContent = `${triangleCount(partMeshes.get(p.id).geometry)} triangles`;
		}));
		box.append(tc);
	}

	// points
	box.append(el('h4', {}, 'Points'));
	const nMoved = Object.keys(p.verts || {}).length;
	box.append(el('div', { class: 'btns' },
		el('button', { class: 'btn' + (state.editPts ? ' on' : ''), title: 'V', onclick: () => setEditPts(!state.editPts) }, state.editPts ? 'Done editing' : 'Edit points'),
		nMoved ? el('button', { class: 'btn', onclick: () => { editSelected((q) => { q.verts = {}; }); commit(); refreshDots(); renderProps(); } }, `Reset ${nMoved} moved`) : null,
	));
	box.append(el('div', { class: 'tip' }, state.editPts ? 'Click a corner dot, then drag the arrows. Shared corners move together; the twin mirrors it.' : 'Move individual corners for custom shapes.'));

	// shape
	box.append(el('h4', {}, 'Shape'));
	for (const m of MORPHS) {
		box.append(slider(m.label, m.min, m.max, m.step, p.morph[m.key] || 0, (v) => editSelected((q) => { q.morph[m.key] = v; }), m.key === 'twist' ? (v) => `${(+v).toFixed(0)}°` : undefined));
	}
	const round = def.shapes.some((s) => (s.n || (s.p === 'cyl' || s.p === 'sph' ? 8 : 0)) >= 5 || ['tube', 'torus'].includes(s.p));
	if (round) box.append(slider('Sides', -4, 8, 1, p.sides || 0, (v) => editSelected((q) => { q.sides = v; if (q.verts && Object.keys(q.verts).length) { q.verts = {}; status('Changing sides resets moved points.'); } }), (v) => (v > 0 ? '+' : '') + v));
	box.append(el('div', { class: 'tip' }, 'Double-click a slider to reset it.'));

	// style clipboard
	box.append(el('h4', {}, 'Style'));
	box.append(el('div', { class: 'btns' },
		el('button', { class: 'btn', onclick: () => { state.clipboard = { colors: { ...p.colors }, pattern: p.pattern, patScale: p.patScale, glow: p.glow }; status('Style copied.'); } }, 'Copy style'),
		el('button', { class: 'btn', onclick: () => { if (!state.clipboard) return; editSelected((q) => { Object.assign(q, JSON.parse(JSON.stringify(state.clipboard))); }); commit(); renderProps(); } }, 'Paste style'),
		el('button', { class: 'btn', title: 'Give every copy of this part the same look', onclick: () => {
			for (const q of state.parts) if (q.def === p.def && q !== p) { copyLook(p, q); rebuildMesh(q); }
			commit(); status(`Every ${def.name} now matches.`);
		} }, 'Match all'),
	));
}

function refreshPatternSwatches() {
	const p = getPart(state.selected);
	const box = document.getElementById('patGrid');
	if (!p || !box) return;
	box.innerHTML = '';
	const a = new THREE.Color(p.colors.main);
	let b = new THREE.Color(p.colors.ink);
	// keep the previews readable when main and ink are close (dark kit on dark kit)
	const lum = (c) => 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;
	if (Math.abs(lum(a) - lum(b)) < 0.12) b = lum(a) < 0.4 ? a.clone().lerp(new THREE.Color(1, 1, 1), 0.45) : a.clone().multiplyScalar(0.45);
	for (const [k, P] of Object.entries(PATTERNS)) {
		const d = el('div', { title: P.label, class: p.pattern === k ? 'on' : '' });
		d.style.backgroundImage = `url(${patternSwatch(k, a, b)})`;
		d.onclick = () => {
			editSelected((q) => {
				q.pattern = k;
				if (q.colors.ink === q.colors.main && k !== 'solid') q.colors.ink = '#1a1b1d';
			});
			commit();
			renderProps();
		};
		box.append(d);
	}
}

function renderModelPanel(box) {
	box.append(el('h2', {}, MODES[state.mode].label));
	const name = el('input', { type: 'text', value: state.name, title: 'Used for file names' });
	name.addEventListener('change', () => { state.name = name.value.trim() || 'model'; commit(); });
	box.append(el('div', { class: 'row' }, el('label', {}, 'Name'), name));

	box.append(el('h4', {}, 'Colours used'));
	const used = new Map();
	for (const p of state.parts) {
		const def = PARTS[p.def];
		const slots = new Set(def.shapes.map((s) => s.m || 'main'));
		if (p.pattern !== 'solid') slots.add('ink');
		for (const k of slots) used.set(p.colors[k], (used.get(p.colors[k]) || 0) + 1);
	}
	const uc = el('div', { class: 'usedcols' });
	for (const [hex, n] of [...used.entries()].sort((a, b) => b[1] - a[1])) {
		const inp = el('input', { type: 'color', value: hex });
		let cur = hex;
		inp.addEventListener('input', () => {
			for (const p of state.parts) {
				let hit = false;
				for (const k of ['main', 'ink', 'trim', 'detail']) if (p.colors[k] === cur) { p.colors[k] = inp.value; hit = true; }
				if (hit) rebuildMesh(p);
			}
			cur = inp.value;
			lab.style.background = cur;
		});
		inp.addEventListener('change', () => { commit(); renderProps(); });
		const lab = el('label', { title: `${hex} · used ${n}×. Click to recolour all of it.` }, inp);
		lab.style.background = hex;
		uc.append(lab);
	}
	box.append(uc);
	box.append(el('div', { class: 'tip' }, 'Click a colour to change it on every part at once.'));

	box.append(el('h4', {}, 'Triangles'));
	const tbl = el('table', { class: 'stats' });
	const per = {};
	let total = 0;
	for (const p of state.parts) {
		const m = partMeshes.get(p.id);
		if (!m || PARTS[p.def].marker) continue;
		const n = triangleCount(m.geometry);
		per[p.bone] = (per[p.bone] || 0) + n;
		total += n;
	}
	for (const b of BONES[state.mode]) if (per[b.name]) tbl.append(el('tr', {}, el('td', {}, b.label), el('td', {}, String(per[b.name]))));
	tbl.append(el('tr', {}, el('td', {}, 'Total'), el('td', {}, String(total))));
	box.append(tbl);
	box.append(el('div', { class: 'tip' }, `Budget: 300 triangles. Each box is 12, so the Boxy parts keep a whole soldier under it.`));

	box.append(el('h4', {}, 'How to'));
	const tips = {
		humanoid: ['<b>Drag</b> body parts, gear and armour onto the body: they snap to the right bone.', '<b>Pouches & bits</b> stick wherever you drop them.', '<b>Click</b> a part to edit it, <b>drag</b> it to slide it around.', 'Try <b>Rifle ready</b> and <b>Walk</b> in the pose menu.'],
		weapon: ['Drop pieces on faces: barrels and handguards extend forward, stocks back, grips and mags hang down, optics sit on top.', 'Place the <b>Muzzle point</b> where shots leave the barrel.', 'Your weapon shows in the character\'s hands in the rifle poses.'],
		building: ['Drop walls on the floor; <b>Q</b> turns the next piece 90°.', 'Snap keeps pieces on a 0.25 m grid.', 'Window frames and doors sit on the ground or other pieces.'],
	};
	for (const t of tips[state.mode]) {
		const d = el('div', { class: 'tip' });
		d.innerHTML = '· ' + t;
		box.append(d);
	}
}

// ================================================================ stats / status

function updateStats() {
	let total = 0;
	for (const p of state.parts) {
		const m = partMeshes.get(p.id);
		if (m && !PARTS[p.def].marker) total += triangleCount(m.geometry);
	}
	const budget = MODES[state.mode].budget;
	$('#tris').textContent = `${state.parts.length} parts · ${total} triangles`;
	$('#budgetTxt').textContent = `${total} / ${budget} tris (PSX budget)`;
	const f = $('#budgetFill');
	f.style.width = Math.min(100, (total / budget) * 100) + '%';
	f.style.background = total > budget * 1.3 ? 'var(--danger)' : total > budget ? 'var(--accent)' : 'var(--ok)';
}

let statusTimer = null;
function status(msg) {
	$('#status').textContent = msg;
	clearTimeout(statusTimer);
	statusTimer = setTimeout(() => { $('#status').textContent = 'Drag parts from the left onto the model. Press ? for help.'; }, 6000);
}

function toast(msg) {
	const t = $('#toast');
	t.textContent = msg;
	t.style.display = 'block';
	setTimeout(() => { t.style.display = 'none'; }, 4000);
}

// ================================================================ keys

window.addEventListener('keydown', (e) => {
	if (e.target.tagName === 'INPUT' && e.target.type === 'text') return;
	const k = e.key.toLowerCase();
	const mod = e.ctrlKey || e.metaKey;
	if (mod && k === 'z' && !e.shiftKey) { e.preventDefault(); undo(); return; }
	if (mod && (k === 'y' || (k === 'z' && e.shiftKey))) { e.preventDefault(); redo(); return; }
	if (mod && k === 'd') { e.preventDefault(); duplicateSelected(); return; }
	if (mod && k === 's') { e.preventDefault(); saveFile(); return; }
	if (mod) return;
	if (k === 'delete' || k === 'backspace') { e.preventDefault(); deleteSelected(); }
	else if (k === 'w') setGizmoMode('translate');
	else if (k === 'e') setGizmoMode('rotate');
	else if (k === 'r') setGizmoMode('scale');
	else if (k === 'm') toggleSym();
	else if (k === 'g') toggleSnap();
	else if (k === 'p') togglePsx();
	else if (k === 'q') turnSelected();
	else if (k === 'f') frameSelected();
	else if (k === 'v') { if (state.selected) setEditPts(!state.editPts); }
	else if (k === 'escape') { if (state.editPts) setEditPts(false); else select(null); $('#help').style.display = 'none'; }
	else if (k === '?' || k === 'h') $('#help').style.display = 'flex';
});

// ================================================================ loop & start

const clock = new THREE.Clock();
function loop() {
	requestAnimationFrame(loop);
	if (state.pose === 'walk' && state.mode === 'humanoid') applyPose(clock.getElapsedTime());
	renderer.render(scene, camera);
}

state.psx = localStorage.getItem('sqm.psx') !== '0';
setGizmoMode('translate');
const startMode = localStorage.getItem('sqm.mode');
setMode(MODES[startMode] ? startMode : 'humanoid');
resize();
loop();
status('Drag parts from the left onto the model. Press ? for help.');

// for tests and the console
window.sqmProject = null;
const projectPoint = (pt) => {
	rig.updateMatrixWorld(true);
	const v = new THREE.Vector3(...pt).project(camera);
	const r = renderer.domElement.getBoundingClientRect();
	return [r.left + (v.x + 1) / 2 * r.width, r.top + (1 - v.y) / 2 * r.height];
};
window.sqmCam = (pos, target) => { camera.position.set(...pos); orbit.target.set(...(target || MODES[state.mode].target)); orbit.update(); };
window.sqmHandle = handle;
window.sqm = { importFiles, setEditPts, selectDot, vertHandle, gizmo, projectPoint, state, PARTS, serialize, loadDesign, loadTemplate, setMode, exportGLB, placementFor, hitTest, rayFromEvent, select, commit, undo, redo, templateParts, partMeshes, bones };
