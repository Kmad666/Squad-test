// The parts library. Each part is a few simple shapes (see geometry.js) in
// its own space, with default colours and a way to mount:
//   home     snaps to its place on a bone (helmet on the head, boot on the
//            foot). Bone names ending in * take the side you drop it on.
//            Side parts are authored for the RIGHT side (+X); the left copy
//            is mirrored.
//   surface  sticks to whatever you drop it on: its +Y points out of the
//            surface, its -Z toward "up" (pouches, spikes, patches).
//   upright  keeps its axes, sits at the drop point: weapon pieces snap
//            end to end, building pieces stand on floors.
// Shape quick reference (sizes in metres, rot in degrees):
//   box  s:[w,h,d] top:[x,z scale of top face]   cyl r:[bottom,top] h n
//   sph  r n rings hemi    loft rings:[[y,rx,rz,z,x]] n off(deg)
//   wedge s   torus R r n   tube pts r n      common: at rot sc m(main|trim|detail)

// ------------------------------------------------------------ colours

export const SWATCHES = [
	'#1a1b1d', '#2f3235', '#4a4e52', '#7a7f84', '#b9bdc0', '#e8e6df',
	'#3b4228', '#565f36', '#6f7346', '#4d4030', '#7a6448', '#a89068',
	'#5b3a22', '#8a5a33', '#c08a5a', '#e2b892', '#9a6b4f', '#4e3324',
	'#7d1c14', '#b8321e', '#d9822b', '#e6c040', '#2d5c3a', '#4f9a5a',
	'#1f3a5c', '#3c6fa3', '#7fb8d8', '#5a2d6b', '#9c4fb0', '#6ce0d0',
];

const C = {
	uniform: '#34373a', uniform2: '#4a4e52', kit: '#202225', kit2: '#3b4228', boots: '#17150f',
	gloves: '#1a1b1d', hood: '#212224', skin: '#c08a5a', metal: '#2a2c2e', steel: '#7a7f84',
	lens: '#3fe0c8', red: '#e03a20', wood: '#6b4526', brass: '#b8902e', cloth: '#5b4a35',
	wall: '#9a8f7e', mortar: '#5e574d', roof: '#6b2e22', concrete: '#7c7a74', glass: '#7fb8d8',
};

function cols(main, ink, trim, detail) {
	return { main, ink: ink || main, trim: trim || C.kit, detail: detail || C.lens };
}

// ------------------------------------------------------------ registry

export const PARTS = {};
export const CATEGORIES = { humanoid: [], weapon: [], building: [] };

function P(mode, cat, id, name, shapes, opt = {}) {
	const def = {
		id, name, mode, cat, shapes,
		mount: opt.mount || (opt.home ? 'home' : mode === 'humanoid' ? 'surface' : 'upright'),
		home: opt.home || null,
		colors: opt.colors || cols(C.uniform, C.uniform2, C.kit, C.lens),
		pattern: opt.pattern || 'solid',
		patScale: opt.patScale || 0.25,
		glow: !!opt.glow,
		morph: opt.morph || {},
		marker: opt.marker || null,
		desc: opt.desc || '',
	};
	PARTS[id] = def;
	let c = CATEGORIES[mode].find((x) => x.name === cat);
	if (!c) { c = { name: cat, parts: [] }; CATEGORIES[mode].push(c); }
	c.parts.push(id);
	return def;
}

const H = (bone, at = [0, 0, 0], rot = [0, 0, 0]) => ({ bone, at, rot });

// ================================================================ HUMANOID
const U = 'humanoid';

// ---- body
P(U, 'Body', 'hips_basic', 'Hips', [
	{ p: 'box', s: [0.19, 0.26, 0.16], top: [1.37, 1.19], at: [0, -0.01, 0] },
], { home: H('hips'), colors: cols(C.uniform, C.uniform2) });
P(U, 'Body', 'hips_round', 'Round hips', [
	{ p: 'loft', n: 8, rings: [[-0.14, 0.1, 0.085], [-0.02, 0.135, 0.105], [0.12, 0.13, 0.1]] },
], { home: H('hips'), colors: cols(C.uniform, C.uniform2) });

P(U, 'Body', 'torso_trooper', 'Trooper torso', [
	{ p: 'loft', n: 6, rings: [[0.96, 0.125, 0.095], [1.1, 0.15, 0.108], [1.3, 0.24, 0.135, -0.01], [1.44, 0.275, 0.13], [1.52, 0.18, 0.1, 0.01], [1.575, 0.085, 0.075, 0.01]] },
], { home: H('torso'), colors: cols(C.uniform, C.uniform2) });
P(U, 'Body', 'torso_slim', 'Slim torso', [
	{ p: 'loft', n: 8, rings: [[0.96, 0.12, 0.09], [1.12, 0.13, 0.095], [1.3, 0.18, 0.11, -0.01], [1.44, 0.205, 0.11], [1.53, 0.14, 0.085, 0.01], [1.58, 0.06, 0.06, 0.01]] },
], { home: H('torso'), colors: cols(C.uniform, C.uniform2) });
P(U, 'Body', 'torso_brute', 'Brute torso', [
	{ p: 'loft', n: 6, rings: [[0.96, 0.15, 0.12], [1.1, 0.2, 0.15, -0.02], [1.3, 0.29, 0.17, -0.03], [1.45, 0.32, 0.16], [1.54, 0.22, 0.12, 0.01], [1.59, 0.1, 0.085, 0.01]] },
], { home: H('torso'), colors: cols(C.uniform, C.uniform2) });

P(U, 'Body', 'upper_arm_prism', 'Chunky upper arm', [
	{ p: 'loft', n: 3, off: 90, rings: [[0.05, 0.085, 0.085], [-0.12, 0.092, 0.092], [-0.33, 0.066, 0.066]] },
], { home: H('upper_arm_*'), colors: cols(C.uniform, C.uniform2) });
P(U, 'Body', 'upper_arm_round', 'Round upper arm', [
	{ p: 'loft', n: 6, rings: [[0.045, 0.065, 0.065], [-0.1, 0.066, 0.066], [-0.32, 0.05, 0.05]] },
], { home: H('upper_arm_*'), colors: cols(C.uniform, C.uniform2) });
P(U, 'Body', 'upper_arm_brute', 'Brute upper arm', [
	{ p: 'sph', r: 0.095, n: 6, rings: 3, at: [0, 0.0, 0] },
	{ p: 'loft', n: 6, rings: [[0.0, 0.09, 0.09], [-0.13, 0.095, 0.095], [-0.33, 0.07, 0.07]] },
], { home: H('upper_arm_*'), colors: cols(C.uniform, C.uniform2) });

P(U, 'Body', 'forearm_glove', 'Forearm + glove', [
	{ p: 'loft', n: 3, off: 90, rings: [[0.03, 0.075, 0.075], [-0.1, 0.08, 0.08], [-0.235, 0.056, 0.056]] },
	{ p: 'box', s: [0.088, 0.05, 0.088], top: [1.14, 1.14], at: [0, -0.245, 0], m: 'trim' },
	{ p: 'box', s: [0.104, 0.11, 0.056], top: [0.9, 1.07], at: [0, -0.33, -0.004], m: 'trim' },
	{ p: 'box', s: [0.03, 0.06, 0.032], at: [0.048, -0.32, -0.02], rot: [0, 0, 23], m: 'trim' },
], { home: H('forearm_*'), colors: cols(C.uniform, C.uniform2, C.gloves) });
P(U, 'Body', 'forearm_hand', 'Forearm + bare hand', [
	{ p: 'loft', n: 6, rings: [[0.03, 0.06, 0.06], [-0.1, 0.062, 0.062], [-0.235, 0.045, 0.045]] },
	{ p: 'box', s: [0.09, 0.1, 0.045], top: [0.9, 1], at: [0, -0.31, -0.004], m: 'detail' },
	{ p: 'box', s: [0.026, 0.055, 0.028], at: [0.044, -0.3, -0.018], rot: [0, 0, 23], m: 'detail' },
], { home: H('forearm_*'), colors: cols(C.uniform, C.uniform2, C.kit, C.skin) });
P(U, 'Body', 'forearm_claw', 'Forearm + claws', [
	{ p: 'loft', n: 5, rings: [[0.03, 0.07, 0.07], [-0.1, 0.075, 0.075], [-0.25, 0.055, 0.055]] },
	{ p: 'box', s: [0.1, 0.08, 0.06], at: [0, -0.29, 0] , m: 'trim' },
	{ p: 'cyl', r: [0.012, 0], h: 0.09, n: 4, at: [0.03, -0.37, 0.015], m: 'detail' },
	{ p: 'cyl', r: [0.012, 0], h: 0.1, n: 4, at: [0, -0.375, 0.015], m: 'detail' },
	{ p: 'cyl', r: [0.012, 0], h: 0.09, n: 4, at: [-0.03, -0.37, 0.015], m: 'detail' },
], { home: H('forearm_*'), colors: cols(C.uniform, C.uniform2, C.gloves, '#e8e6df') });

P(U, 'Body', 'thigh_prism', 'Chunky thigh', [
	{ p: 'loft', n: 3, off: 90, rings: [[0.08, 0.115, 0.115], [-0.16, 0.135, 0.135, 0.012], [-0.38, 0.108, 0.108, 0.01], [-0.47, 0.088, 0.088]] },
], { home: H('thigh_*'), colors: cols(C.uniform, C.uniform2) });
P(U, 'Body', 'thigh_round', 'Round thigh', [
	{ p: 'loft', n: 6, rings: [[0.06, 0.09, 0.09], [-0.15, 0.095, 0.095, 0.01], [-0.45, 0.068, 0.068]] },
], { home: H('thigh_*'), colors: cols(C.uniform, C.uniform2) });

P(U, 'Body', 'shin_boot', 'Shin + boot', [
	{ p: 'loft', n: 3, off: 90, rings: [[0.05, 0.1, 0.1], [-0.12, 0.118, 0.118, 0.004], [-0.26, 0.094, 0.094], [-0.315, 0.06, 0.06]] },
	{ p: 'box', s: [0.1, 0.14, 0.124], top: [0.68, 0.68], at: [0, -0.375, 0.004], m: 'trim' },
], { home: H('shin_*'), colors: cols(C.uniform, C.uniform2, C.boots) });
P(U, 'Body', 'shin_round', 'Round shin', [
	{ p: 'loft', n: 6, rings: [[0.04, 0.075, 0.075], [-0.12, 0.072, 0.072, 0.008], [-0.3, 0.05, 0.05], [-0.43, 0.045, 0.045]] },
], { home: H('shin_*'), colors: cols(C.uniform, C.uniform2) });
P(U, 'Body', 'shin_greave', 'Shin + greave', [
	{ p: 'loft', n: 6, rings: [[0.04, 0.075, 0.075], [-0.3, 0.06, 0.06], [-0.43, 0.05, 0.05]] },
	{ p: 'box', s: [0.11, 0.34, 0.04], top: [0.75, 1], at: [0, -0.2, 0.065], m: 'trim' },
], { home: H('shin_*'), colors: cols(C.cloth, C.cloth, C.steel) });

P(U, 'Body', 'foot_boot', 'Boot', [
	{ p: 'box', s: [0.096, 0.084, 0.23], at: [0, -0.042, -0.052] },
	{ p: 'box', s: [0.096, 0.05, 0.064], top: [0.875, 0.81], at: [0, -0.058, -0.148] },
	{ p: 'box', s: [0.104, 0.025, 0.26], at: [0, -0.075, -0.05], m: 'trim' },
], { home: H('foot_*'), colors: cols(C.boots, C.boots, '#0d0d0d') });
P(U, 'Body', 'foot_sandal', 'Bare foot', [
	{ p: 'box', s: [0.09, 0.06, 0.24], top: [0.9, 0.8], at: [0, -0.055, -0.06], m: 'detail' },
	{ p: 'box', s: [0.096, 0.02, 0.25], at: [0, -0.078, -0.055], m: 'trim' },
], { home: H('foot_*'), colors: cols(C.boots, C.boots, '#4d4030', C.skin) });
P(U, 'Body', 'foot_sabaton', 'Armored boot', [
	{ p: 'box', s: [0.11, 0.09, 0.2], at: [0, -0.04, -0.03] },
	{ p: 'wedge', s: [0.1, 0.06, 0.1], at: [0, -0.055, -0.175], rot: [0, 180, 0] },
	{ p: 'box', s: [0.115, 0.02, 0.27], at: [0, -0.078, -0.06], m: 'trim' },
], { home: H('foot_*'), colors: cols(C.steel, C.steel, C.metal), pattern: 'plates', patScale: 0.12 });

// ---- heads
P(U, 'Heads', 'head_hood', 'Balaclava head', [
	{ p: 'loft', n: 6, rings: [[-0.12, 0.068, 0.066, 0.01], [0.0, 0.075, 0.075, 0.01]], capA: false, capB: false },
	{ p: 'loft', n: 6, rings: [[-0.01, 0.075, 0.08], [0.04, 0.095, 0.1, -0.005], [0.13, 0.1, 0.106], [0.2, 0.074, 0.08, 0.005], [0.228, 0.03, 0.03, 0.005]] },
	{ p: 'box', s: [0.07, 0.04, 0.024], at: [0, 0.035, -0.1], m: 'trim' },
], { home: H('head'), colors: cols(C.hood, C.hood, '#161618') });
P(U, 'Heads', 'head_face', 'Face', [
	{ p: 'loft', n: 6, rings: [[-0.12, 0.055, 0.055, 0.01], [0.0, 0.06, 0.06, 0.01]], capA: false, capB: false },
	{ p: 'loft', n: 8, rings: [[-0.01, 0.065, 0.075, -0.01], [0.03, 0.08, 0.095, -0.005], [0.13, 0.092, 0.105], [0.2, 0.075, 0.085, 0.005], [0.23, 0.035, 0.04, 0.005]] },
	{ p: 'wedge', s: [0.03, 0.045, 0.03], at: [0, 0.085, -0.108], rot: [0, 180, 0] },
	{ p: 'box', s: [0.028, 0.014, 0.01], at: [-0.034, 0.118, -0.098], m: 'detail' },
	{ p: 'box', s: [0.028, 0.014, 0.01], at: [0.034, 0.118, -0.098], m: 'detail' },
	{ p: 'box', s: [0.08, 0.012, 0.012], at: [0, 0.137, -0.1], m: 'trim' },
	{ p: 'box', s: [0.04, 0.01, 0.01], at: [0, 0.045, -0.095], m: 'trim' },
	{ p: 'box', s: [0.022, 0.05, 0.035], at: [-0.092, 0.1, 0.0] },
	{ p: 'box', s: [0.022, 0.05, 0.035], at: [0.092, 0.1, 0.0] },
], { home: H('head'), colors: cols(C.skin, C.skin, '#4e3324', '#1a1b1d') });
P(U, 'Heads', 'head_round', 'Mannequin head', [
	{ p: 'cyl', r: [0.05, 0.05], h: 0.12, n: 6, at: [0, -0.04, 0.01] },
	{ p: 'sph', r: 0.105, n: 8, rings: 4, at: [0, 0.12, 0], sc: [0.95, 1.08, 1.02] },
], { home: H('head'), colors: cols('#b9bdc0', '#b9bdc0') });
P(U, 'Heads', 'head_robot', 'Robot head', [
	{ p: 'cyl', r: [0.04, 0.04], h: 0.1, n: 6, at: [0, -0.06, 0], m: 'trim' },
	{ p: 'box', s: [0.17, 0.17, 0.19], top: [0.8, 0.85], at: [0, 0.1, 0] },
	{ p: 'box', s: [0.14, 0.035, 0.02], at: [0, 0.12, -0.095], m: 'detail' },
	{ p: 'cyl', r: [0.004, 0.004], h: 0.12, n: 4, at: [0.06, 0.24, 0.03], m: 'trim' },
], { home: H('head'), colors: cols(C.steel, C.metal, C.metal, C.red), glow: true, pattern: 'plates', patScale: 0.15 });
P(U, 'Heads', 'head_skull', 'Skull head', [
	{ p: 'cyl', r: [0.04, 0.04], h: 0.1, n: 5, at: [0, -0.06, 0.01], m: 'trim' },
	{ p: 'sph', r: 0.1, n: 7, rings: 4, at: [0, 0.13, 0.01], sc: [0.95, 1, 1.1] },
	{ p: 'box', s: [0.12, 0.07, 0.09], top: [0.8, 0.8], at: [0, 0.03, -0.035] },
	{ p: 'box', s: [0.035, 0.03, 0.01], at: [-0.035, 0.115, -0.1], m: 'detail' },
	{ p: 'box', s: [0.035, 0.03, 0.01], at: [0.035, 0.115, -0.1], m: 'detail' },
	{ p: 'box', s: [0.06, 0.012, 0.01], at: [0, 0.035, -0.08], m: 'trim' },
], { home: H('head'), colors: cols('#e8e6df', '#e8e6df', '#4a4e52', C.red), glow: true });

// ---- headgear
P(U, 'Headgear', 'helmet_highcut', 'High-cut helmet', [
	{ p: 'sph', r: 0.125, n: 8, rings: 3, hemi: true, at: [0, 0.135, 0.005], sc: [1, 0.85, 1.06] },
	{ p: 'box', s: [0.045, 0.04, 0.025], at: [0, 0.19, -0.13], m: 'trim' },
	{ p: 'box', s: [0.014, 0.03, 0.11], at: [-0.123, 0.155, 0.005], m: 'trim' },
	{ p: 'box', s: [0.014, 0.03, 0.11], at: [0.123, 0.155, 0.005], m: 'trim' },
	{ p: 'box', s: [0.06, 0.035, 0.03], at: [0, 0.17, 0.13], m: 'trim' },
], { home: H('head'), colors: cols('#3a3d40', '#4a4e52', C.kit) });
P(U, 'Headgear', 'helmet_steel', 'Steel pot', [
	{ p: 'sph', r: 0.13, n: 8, rings: 3, hemi: true, at: [0, 0.125, 0], sc: [1, 0.92, 1.06] },
	{ p: 'cyl', r: [0.155, 0.148], h: 0.014, n: 10, at: [0, 0.125, 0], d: 1.06 },
	{ p: 'tube', pts: [[-0.12, 0.12, 0], [-0.07, 0.0, -0.05], [0, -0.03, -0.07], [0.07, 0.0, -0.05], [0.12, 0.12, 0]], r: 0.006, n: 4, m: 'trim' },
], { home: H('head'), colors: cols('#565f36', '#3b4228', '#4d4030'), pattern: 'grain' });
P(U, 'Headgear', 'helmet_knight', 'Great helm', [
	{ p: 'cyl', r: [0.125, 0.125], h: 0.26, n: 8, at: [0, 0.1, 0], d: 1.08 },
	{ p: 'cyl', r: [0.125, 0.02], h: 0.07, n: 8, at: [0, 0.265, 0], d: 1.08 },
	{ p: 'box', s: [0.17, 0.016, 0.03], at: [0, 0.13, -0.13], m: 'detail' },
	{ p: 'box', s: [0.016, 0.18, 0.02], at: [0, 0.07, -0.135], m: 'trim' },
], { home: H('head'), colors: cols(C.steel, '#4a4e52', C.brass, '#0d0d0d'), pattern: 'grain' });
P(U, 'Headgear', 'beret', 'Beret', [
	{ p: 'sph', r: 0.12, n: 8, rings: 3, at: [0.02, 0.2, 0.0], sc: [1.02, 0.33, 1.05], rot: [0, 0, -12] },
	{ p: 'cyl', r: [0.103, 0.103], h: 0.022, n: 8, at: [0, 0.183, 0], m: 'trim' },
	{ p: 'box', s: [0.03, 0.035, 0.008], at: [-0.04, 0.2, -0.105], m: 'detail' },
], { home: H('head'), colors: cols('#7d1c14', '#7d1c14', '#1a1b1d', C.brass) });
P(U, 'Headgear', 'cap_patrol', 'Patrol cap', [
	{ p: 'cyl', r: [0.105, 0.1], h: 0.085, n: 8, at: [0, 0.2, 0.0] },
	{ p: 'box', s: [0.15, 0.012, 0.09], top: [0.85, 1], at: [0, 0.165, -0.13], rot: [-8, 0, 0], m: 'trim' },
], { home: H('head'), colors: cols('#3b4228', '#565f36', '#2b301c'), pattern: 'camo', patScale: 0.3 });
P(U, 'Headgear', 'boonie', 'Boonie hat', [
	{ p: 'cyl', r: [0.105, 0.095], h: 0.09, n: 8, at: [0, 0.205, 0] },
	{ p: 'cyl', r: [0.19, 0.17], h: 0.012, n: 10, at: [0, 0.16, 0] },
	{ p: 'torus', R: 0.103, r: 0.012, n: 8, m2: 3, at: [0, 0.18, 0], m: 'trim' },
], { home: H('head'), colors: cols('#6f7346', '#4d4030', '#3b4228'), pattern: 'camo', patScale: 0.4 });
P(U, 'Headgear', 'hood_cloth', 'Hood', [
	{ p: 'loft', n: 8, rings: [[-0.04, 0.12, 0.13, 0.025], [0.12, 0.125, 0.13, 0.02], [0.22, 0.09, 0.1, 0.03], [0.28, 0.02, 0.02, 0.06]], capA: false },
], { home: H('head'), colors: cols(C.cloth, '#3e3226'), pattern: 'grain' });
P(U, 'Headgear', 'goggles', 'Goggles', [
	{ p: 'loft', n: 6, rings: [[0.098, 0.103, 0.108], [0.126, 0.103, 0.108]], capA: false, capB: false, m: 'trim' },
	{ p: 'box', s: [0.074, 0.054, 0.024], at: [-0.042, 0.112, -0.104], rot: [3, 18, 0], m: 'trim' },
	{ p: 'box', s: [0.074, 0.054, 0.024], at: [0.042, 0.112, -0.104], rot: [3, -18, 0], m: 'trim' },
	{ p: 'box', s: [0.06, 0.04, 0.016], at: [-0.043, 0.112, -0.113], rot: [3, 18, 0], m: 'detail' },
	{ p: 'box', s: [0.06, 0.04, 0.016], at: [0.043, 0.112, -0.113], rot: [3, -18, 0], m: 'detail' },
], { home: H('head'), colors: cols(C.kit, C.kit, '#0d0d0d', C.red), glow: true });
P(U, 'Headgear', 'gas_mask', 'Gas mask', [
	{ p: 'box', s: [0.15, 0.13, 0.07], top: [0.85, 0.7], at: [0, 0.06, -0.085] },
	{ p: 'cyl', r: [0.036, 0.036], h: 0.055, n: 8, at: [0, 0.02, -0.135], rot: [80, 0, 0], m: 'trim' },
	{ p: 'cyl', r: [0.026, 0.026], h: 0.012, n: 8, at: [-0.04, 0.115, -0.115], rot: [80, 0, 0], m: 'detail' },
	{ p: 'cyl', r: [0.026, 0.026], h: 0.012, n: 8, at: [0.04, 0.115, -0.115], rot: [80, 0, 0], m: 'detail' },
	{ p: 'loft', n: 6, rings: [[0.07, 0.102, 0.105], [0.085, 0.102, 0.105]], capA: false, capB: false, m: 'trim' },
], { home: H('head'), colors: cols('#212224', '#212224', '#4a4e52', C.lens), glow: true });
P(U, 'Headgear', 'visor_band', 'Visor', [
	{ p: 'loft', n: 8, rings: [[0.095, 0.104, 0.11], [0.135, 0.104, 0.11]], capA: false, capB: false, sc: [1, 1, 1], m: 'detail' },
	{ p: 'box', s: [0.03, 0.06, 0.04], at: [-0.105, 0.115, 0.0], m: 'trim' },
	{ p: 'box', s: [0.03, 0.06, 0.04], at: [0.105, 0.115, 0.0], m: 'trim' },
], { home: H('head'), colors: cols(C.metal, C.metal, C.metal, C.lens), glow: true });
P(U, 'Headgear', 'headset', 'Headset', [
	{ p: 'cyl', r: [0.04, 0.04], h: 0.035, n: 8, at: [-0.11, 0.1, 0.005], rot: [0, 0, 90] },
	{ p: 'cyl', r: [0.04, 0.04], h: 0.035, n: 8, at: [0.11, 0.1, 0.005], rot: [0, 0, 90] },
	{ p: 'tube', pts: [[-0.115, 0.13, 0.005], [-0.08, 0.22, 0.005], [0, 0.245, 0.005], [0.08, 0.22, 0.005], [0.115, 0.13, 0.005]], r: 0.008, n: 4, m: 'trim' },
	{ p: 'tube', pts: [[0.115, 0.08, -0.02], [0.08, 0.04, -0.09], [0.03, 0.04, -0.11]], r: 0.005, n: 4, m: 'trim' },
], { home: H('head'), colors: cols(C.kit, C.kit, '#0d0d0d') });

// ---- faces & hair
P(U, 'Faces & hair', 'hair_short', 'Short hair', [
	{ p: 'sph', r: 0.1, n: 8, rings: 3, hemi: true, at: [0, 0.13, 0.008], sc: [1, 1.0, 1.1] },
], { home: H('head'), colors: cols('#2b1d12', '#2b1d12') });
P(U, 'Faces & hair', 'hair_mohawk', 'Mohawk', [
	{ p: 'box', s: [0.03, 0.08, 0.2], top: [0.5, 0.8], at: [0, 0.25, 0.01] },
], { home: H('head'), colors: cols('#b8321e', '#b8321e') });
P(U, 'Faces & hair', 'hair_long', 'Long hair', [
	{ p: 'sph', r: 0.102, n: 8, rings: 3, hemi: true, at: [0, 0.13, 0.008], sc: [1.02, 1.0, 1.1] },
	{ p: 'box', s: [0.19, 0.24, 0.06], top: [1.05, 1], at: [0, 0.03, 0.08] },
], { home: H('head'), colors: cols('#5b3a22', '#5b3a22') });
P(U, 'Faces & hair', 'ponytail', 'Ponytail', [
	{ p: 'tube', pts: [[0, 0.17, 0.1], [0, 0.12, 0.16], [0, 0.0, 0.17], [0, -0.1, 0.15]], r: 0.022, n: 5 },
], { home: H('head'), colors: cols('#2b1d12', '#2b1d12') });
P(U, 'Faces & hair', 'beard', 'Beard', [
	{ p: 'box', s: [0.15, 0.09, 0.07], top: [1, 0.9], at: [0, 0.035, -0.07] },
	{ p: 'wedge', s: [0.09, 0.05, 0.05], at: [0, -0.03, -0.085], rot: [180, 0, 0] },
], { home: H('head'), colors: cols('#4e3324', '#4e3324') });
P(U, 'Faces & hair', 'ears_pointed', 'Pointed ears', [
	{ p: 'wedge', s: [0.02, 0.09, 0.05], at: [-0.1, 0.13, 0.01], rot: [0, 0, 20] },
	{ p: 'wedge', s: [0.02, 0.09, 0.05], at: [0.1, 0.13, 0.01], rot: [0, 0, -20] },
], { home: H('head'), colors: cols(C.skin, C.skin) });
P(U, 'Faces & hair', 'mask_skull', 'Skull mask', [
	{ p: 'box', s: [0.15, 0.16, 0.04], top: [0.85, 1], at: [0, 0.08, -0.095] },
	{ p: 'box', s: [0.035, 0.03, 0.01], at: [-0.035, 0.115, -0.117], m: 'detail' },
	{ p: 'box', s: [0.035, 0.03, 0.01], at: [0.035, 0.115, -0.117], m: 'detail' },
	{ p: 'box', s: [0.08, 0.01, 0.01], at: [0, 0.035, -0.117], m: 'trim' },
], { home: H('head'), colors: cols('#e8e6df', '#e8e6df', '#2f3235', '#0d0d0d') });
P(U, 'Faces & hair', 'eyepatch', 'Eyepatch', [
	{ p: 'box', s: [0.04, 0.035, 0.012], at: [0.035, 0.118, -0.105], m: 'detail' },
	{ p: 'loft', n: 8, rings: [[0.13, 0.094, 0.108], [0.138, 0.094, 0.108]], capA: false, capB: false, rot: [0, 0, 8], m: 'trim' },
], { home: H('head'), colors: cols('#1a1b1d', '#1a1b1d', '#1a1b1d', '#1a1b1d') });

// ---- armour & kit
P(U, 'Armor & kit', 'plate_carrier', 'Plate carrier', [
	{ p: 'box', s: [0.3, 0.32, 0.05], top: [1.05, 1], at: [0, 1.3, -0.135] },
	{ p: 'box', s: [0.3, 0.34, 0.05], at: [0, 1.3, 0.128] },
	{ p: 'loft', n: 6, rings: [[1.13, 0.17, 0.13], [1.25, 0.21, 0.145]], capA: false, capB: false },
	{ p: 'box', s: [0.06, 0.03, 0.29], at: [-0.11, 1.47, 0], m: 'trim' },
	{ p: 'box', s: [0.06, 0.03, 0.29], at: [0.11, 1.47, 0], m: 'trim' },
], { home: H('torso'), colors: cols(C.kit, C.kit, '#151618') });
P(U, 'Armor & kit', 'chest_rig', 'Chest rig', [
	{ p: 'box', s: [0.3, 0.13, 0.06], at: [0, 1.22, -0.14] },
	{ p: 'box', s: [0.06, 0.1, 0.05], at: [-0.1, 1.215, -0.18], m: 'trim' },
	{ p: 'box', s: [0.06, 0.1, 0.05], at: [-0.03, 1.215, -0.18], m: 'trim' },
	{ p: 'box', s: [0.06, 0.1, 0.05], at: [0.04, 1.215, -0.18], m: 'trim' },
	{ p: 'box', s: [0.06, 0.1, 0.05], at: [0.11, 1.215, -0.18], m: 'trim' },
	{ p: 'tube', pts: [[-0.12, 1.28, -0.13], [-0.13, 1.5, -0.06], [-0.1, 1.55, 0.06], [-0.05, 1.35, 0.14]], r: 0.012, n: 4, m: 'trim' },
	{ p: 'tube', pts: [[0.12, 1.28, -0.13], [0.13, 1.5, -0.06], [0.1, 1.55, 0.06], [0.05, 1.35, 0.14]], r: 0.012, n: 4, m: 'trim' },
], { home: H('torso'), colors: cols('#3b4228', '#565f36', '#2b301c'), pattern: 'grain' });
P(U, 'Armor & kit', 'breastplate', 'Breastplate', [
	{ p: 'loft', n: 8, rings: [[1.02, 0.16, 0.125], [1.18, 0.2, 0.15, -0.012], [1.36, 0.26, 0.16, -0.012], [1.47, 0.27, 0.14], [1.53, 0.16, 0.1, 0.01]], capA: false },
	{ p: 'box', s: [0.02, 0.4, 0.02], at: [0, 1.26, -0.165], m: 'trim' },
], { home: H('torso'), colors: cols(C.steel, '#4a4e52', C.brass), pattern: 'grain' });
P(U, 'Armor & kit', 'cape', 'Cape', [
	{ p: 'box', s: [0.4, 0.85, 0.025], top: [0.75, 1], at: [0, 1.1, 0.165], rot: [-6, 0, 0] },
	{ p: 'torus', R: 0.1, r: 0.02, n: 8, m2: 3, at: [0, 1.56, 0.01], m: 'trim' },
], { home: H('torso'), colors: cols('#7d1c14', '#7d1c14', C.brass) });
P(U, 'Armor & kit', 'scarf', 'Scarf', [
	{ p: 'torus', R: 0.09, r: 0.034, n: 8, m2: 4, at: [0, 1.56, 0.005], sc: [1, 1, 1.05] },
	{ p: 'box', s: [0.06, 0.18, 0.02], at: [0.05, 1.44, -0.11], rot: [8, 0, -6] },
], { home: H('torso'), colors: cols('#6f7346', '#4d4030'), pattern: 'stripes', patScale: 0.12 });
P(U, 'Armor & kit', 'battle_belt', 'Battle belt', [
	{ p: 'box', s: [0.3, 0.06, 0.225], at: [0, 0.095, 0] },
	{ p: 'box', s: [0.06, 0.045, 0.02], at: [0, 0.095, -0.115], m: 'detail' },
	{ p: 'box', s: [0.05, 0.08, 0.06], at: [-0.12, 0.05, -0.07], m: 'trim' },
	{ p: 'box', s: [0.08, 0.07, 0.05], at: [0.06, 0.06, 0.12], m: 'trim' },
], { home: H('hips'), colors: cols('#141416', '#141416', C.kit, '#4a4e52') });
P(U, 'Armor & kit', 'holster', 'Holster', [
	{ p: 'box', s: [0.05, 0.15, 0.08], at: [0.165, 0.0, 0.0], rot: [0, 0, -6] },
	{ p: 'box', s: [0.035, 0.06, 0.03], at: [0.165, 0.09, 0.02], m: 'trim' },
], { home: H('hips'), colors: cols(C.kit, C.kit, '#0d0d0d') });
P(U, 'Armor & kit', 'skirt', 'Tasset skirt', [
	{ p: 'loft', n: 8, rings: [[0.11, 0.145, 0.115], [-0.17, 0.2, 0.17]], capA: false, capB: false },
], { home: H('hips'), colors: cols(C.cloth, '#3e3226'), pattern: 'bands', patScale: 0.15 });
P(U, 'Armor & kit', 'shoulder_pad', 'Shoulder pad', [
	{ p: 'sph', r: 0.1, n: 8, rings: 3, hemi: true, at: [0, 0.0, 0.02], sc: [1.05, 0.7, 1.1] },
	{ p: 'torus', R: 0.098, r: 0.01, n: 8, m2: 3, at: [0, 0.0, 0.02], sc: [1.05, 1, 1.1], m: 'trim' },
], { home: H('upper_arm_*'), colors: cols(C.kit, C.kit, '#0d0d0d') });
P(U, 'Armor & kit', 'pauldron', 'Pauldron', [
	{ p: 'sph', r: 0.13, n: 8, rings: 3, hemi: true, at: [0, -0.02, 0.03], sc: [1.1, 0.8, 1.15] },
	{ p: 'sph', r: 0.115, n: 8, rings: 2, hemi: true, at: [0, -0.07, 0.035], sc: [1.1, 0.6, 1.15], m: 'trim' },
], { home: H('upper_arm_*'), colors: cols(C.steel, '#4a4e52', C.brass), pattern: 'grain' });
P(U, 'Armor & kit', 'armband', 'Armband', [
	{ p: 'loft', n: 6, rings: [[-0.12, 0.096, 0.096], [-0.19, 0.09, 0.09]], capA: false, capB: false },
], { home: H('upper_arm_*'), colors: cols('#b8321e', '#b8321e') });
P(U, 'Armor & kit', 'elbow_pad', 'Elbow pad', [
	{ p: 'box', s: [0.05, 0.08, 0.08], top: [0.7, 0.85], at: [-0.075, -0.0, 0], rot: [0, 0, 0] },
], { home: H('forearm_*'), colors: cols(C.kit, C.kit) });
P(U, 'Armor & kit', 'bracer', 'Bracer', [
	{ p: 'loft', n: 6, rings: [[-0.08, 0.085, 0.085], [-0.23, 0.068, 0.068]], capA: false },
], { home: H('forearm_*'), colors: cols('#5b3a22', '#3e2616'), pattern: 'grain' });
P(U, 'Armor & kit', 'knee_pad', 'Knee pad', [
	{ p: 'box', s: [0.1, 0.1, 0.04], top: [0.85, 1], at: [0, -0.0, 0.105], rot: [-6, 0, 0] },
	{ p: 'box', s: [0.12, 0.025, 0.2], at: [0, 0.0, 0.0], m: 'trim' },
], { home: H('shin_*'), colors: cols(C.kit, C.kit, '#0d0d0d') });
P(U, 'Armor & kit', 'thigh_rig', 'Leg holster', [
	{ p: 'box', s: [0.06, 0.16, 0.09], at: [0, -0.16, 0], rot: [0, 0, 0] },
	{ p: 'loft', n: 6, rings: [[-0.1, 0.125, 0.125], [-0.12, 0.125, 0.125]], capA: false, capB: false, m: 'trim' },
], { home: H('thigh_*', [-0.1, 0, 0]), colors: cols(C.kit, C.kit, '#0d0d0d') });

// ---- packs & pouches (packs snap to the back; pouches stick anywhere)
P(U, 'Packs & pouches', 'pack_assault', 'Assault pack', [
	{ p: 'box', s: [0.3, 0.38, 0.14], top: [0.9, 0.85], at: [0, 1.29, 0.215] },
	{ p: 'box', s: [0.22, 0.12, 0.05], at: [0, 1.2, 0.3], m: 'trim' },
	{ p: 'box', s: [0.05, 0.3, 0.02], at: [-0.1, 1.3, 0.29], m: 'trim' },
	{ p: 'box', s: [0.05, 0.3, 0.02], at: [0.1, 1.3, 0.29], m: 'trim' },
], { home: H('torso'), colors: cols('#3b4228', '#565f36', '#2b301c'), pattern: 'grain' });
P(U, 'Packs & pouches', 'pack_radio', 'Radio pack', [
	{ p: 'box', s: [0.26, 0.34, 0.12], at: [0, 1.3, 0.205] },
	{ p: 'box', s: [0.18, 0.06, 0.04], at: [0, 1.35, 0.28], m: 'detail' },
	{ p: 'tube', pts: [[-0.09, 1.46, 0.23], [-0.11, 1.95, 0.27]], r: 0.005, n: 4, m: 'trim' },
], { home: H('torso'), colors: cols(C.kit2, C.kit2, '#0d0d0d', '#3fe06a'), glow: true });
P(U, 'Packs & pouches', 'pack_bedroll', 'Bedroll', [
	{ p: 'cyl', r: [0.065, 0.065], h: 0.36, n: 8, at: [0, 1.53, 0.2], rot: [0, 0, 90] },
	{ p: 'torus', R: 0.068, r: 0.008, n: 8, m2: 3, at: [-0.1, 1.53, 0.2], rot: [0, 0, 90], m: 'trim' },
	{ p: 'torus', R: 0.068, r: 0.008, n: 8, m2: 3, at: [0.1, 1.53, 0.2], rot: [0, 0, 90], m: 'trim' },
], { home: H('torso'), colors: cols('#6f7346', '#4d4030', '#4d4030'), pattern: 'bands', patScale: 0.1 });
P(U, 'Packs & pouches', 'pack_tank', 'Tank pack', [
	{ p: 'cyl', r: [0.07, 0.07], h: 0.42, n: 8, at: [-0.08, 1.3, 0.2] },
	{ p: 'cyl', r: [0.07, 0.07], h: 0.42, n: 8, at: [0.08, 1.3, 0.2] },
	{ p: 'sph', r: 0.07, n: 8, rings: 2, hemi: true, at: [-0.08, 1.51, 0.2] },
	{ p: 'sph', r: 0.07, n: 8, rings: 2, hemi: true, at: [0.08, 1.51, 0.2] },
	{ p: 'tube', pts: [[0, 1.12, 0.23], [0.12, 1.02, 0.18], [0.2, 1.02, 0.0]], r: 0.012, n: 4, m: 'trim' },
], { home: H('torso'), colors: cols('#e6c040', '#2f3235', '#1a1b1d'), pattern: 'bands', patScale: 0.12 });
P(U, 'Packs & pouches', 'pouch_mag', 'Mag pouch', [
	{ p: 'box', s: [0.065, 0.04, 0.1], at: [0, 0.02, 0] },
	{ p: 'box', s: [0.068, 0.044, 0.03], at: [0, 0.023, -0.04], m: 'trim' },
], { colors: cols(C.kit, C.kit, '#151618') });
P(U, 'Packs & pouches', 'pouch_small', 'Small pouch', [
	{ p: 'box', s: [0.06, 0.035, 0.06], at: [0, 0.0175, 0] },
	{ p: 'box', s: [0.062, 0.038, 0.02], at: [0, 0.019, -0.025], m: 'trim' },
], { colors: cols(C.kit, C.kit, '#151618') });
P(U, 'Packs & pouches', 'radio', 'Radio', [
	{ p: 'box', s: [0.06, 0.04, 0.11], at: [0, 0.02, 0] },
	{ p: 'cyl', r: [0.006, 0.003], h: 0.22, n: 4, at: [0.02, 0.03, -0.16], rot: [90, 0, 0], m: 'trim' },
	{ p: 'box', s: [0.03, 0.006, 0.02], at: [0, 0.042, -0.02], m: 'detail' },
], { colors: cols(C.kit2, C.kit2, '#0d0d0d', '#3fe06a'), glow: true });
P(U, 'Packs & pouches', 'canteen', 'Canteen', [
	{ p: 'cyl', r: [0.045, 0.045], h: 0.11, n: 8, at: [0, 0.045, 0], rot: [90, 0, 0] },
	{ p: 'cyl', r: [0.015, 0.015], h: 0.03, n: 6, at: [0, 0.045, -0.065], rot: [90, 0, 0], m: 'trim' },
], { colors: cols('#3b4228', '#3b4228', '#141416') });
P(U, 'Packs & pouches', 'grenade', 'Grenade', [
	{ p: 'sph', r: 0.03, n: 6, rings: 3, at: [0, 0.03, 0] },
	{ p: 'box', s: [0.014, 0.012, 0.035], at: [0, 0.03, -0.035], m: 'trim' },
], { colors: cols('#565f36', '#565f36', '#7a7f84') });
P(U, 'Packs & pouches', 'knife', 'Knife', [
	{ p: 'box', s: [0.035, 0.02, 0.13], top: [0.6, 1], at: [0, 0.01, 0.04] },
	{ p: 'box', s: [0.03, 0.022, 0.1], at: [0, 0.012, -0.07], m: 'trim' },
], { colors: cols(C.kit, C.kit, '#4e3324') });
P(U, 'Packs & pouches', 'patch', 'Patch', [
	{ p: 'box', s: [0.06, 0.008, 0.045], at: [0, 0.004, 0] },
	{ p: 'box', s: [0.03, 0.01, 0.02], at: [0, 0.005, 0], m: 'detail' },
], { colors: cols('#3b4228', '#3b4228', '#141416', '#e6c040') });
P(U, 'Packs & pouches', 'light', 'Light', [
	{ p: 'cyl', r: [0.018, 0.022], h: 0.04, n: 6, at: [0, 0.02, 0], m: 'trim' },
	{ p: 'cyl', r: [0.02, 0.02], h: 0.006, n: 6, at: [0, 0.043, 0], m: 'detail' },
], { colors: cols(C.kit, C.kit, C.metal, '#fff3c0'), glow: true });

// ---- bits
P(U, 'Bits', 'spike', 'Spike', [
	{ p: 'cyl', r: [0.025, 0], h: 0.1, n: 5, at: [0, 0.05, 0] },
], { colors: cols(C.steel, C.steel) });
P(U, 'Bits', 'horn', 'Horn', [
	{ p: 'loft', n: 6, rings: [[0, 0.035, 0.035], [0.07, 0.028, 0.028], [0.14, 0.017, 0.017], [0.2, 0.0, 0.0]] },
], { colors: cols('#e8e6df', '#e8e6df'), morph: { bend: -0.6 } });
P(U, 'Bits', 'antenna', 'Antenna', [
	{ p: 'cyl', r: [0.012, 0.012], h: 0.03, n: 5, at: [0, 0.015, 0], m: 'trim' },
	{ p: 'cyl', r: [0.004, 0.002], h: 0.5, n: 4, at: [0, 0.28, 0] },
], { colors: cols('#1a1b1d', '#1a1b1d', '#0d0d0d') });
P(U, 'Bits', 'plate', 'Armor plate', [
	{ p: 'box', s: [0.12, 0.015, 0.14], top: [0.85, 0.85], at: [0, 0.0075, 0] },
], { colors: cols(C.steel, C.steel), pattern: 'grain' });
P(U, 'Bits', 'stud', 'Stud', [
	{ p: 'sph', r: 0.018, n: 6, rings: 2, hemi: true, at: [0, 0, 0] },
], { colors: cols(C.brass, C.brass) });
P(U, 'Bits', 'chevron', 'Chevrons', [
	{ p: 'box', s: [0.05, 0.006, 0.012], at: [0, 0.003, -0.012] },
	{ p: 'box', s: [0.05, 0.006, 0.012], at: [0, 0.003, 0.012] },
], { colors: cols('#e6c040', '#e6c040') });
P(U, 'Bits', 'fin', 'Fin', [
	{ p: 'wedge', s: [0.012, 0.12, 0.16], at: [0, 0.06, 0], rot: [0, 0, 0] },
], { colors: cols('#3c6fa3', '#3c6fa3') });
P(U, 'Bits', 'glow_strip', 'Glow strip', [
	{ p: 'box', s: [0.015, 0.008, 0.12], at: [0, 0.004, 0], m: 'detail' },
], { colors: cols(C.kit, C.kit, C.kit, C.lens), glow: true });
P(U, 'Bits', 'block', 'Block', [
	{ p: 'box', s: [0.06, 0.06, 0.06], at: [0, 0.03, 0] },
], { colors: cols(C.uniform2, C.uniform2) });
P(U, 'Bits', 'ball', 'Ball', [
	{ p: 'sph', r: 0.04, n: 8, rings: 4, at: [0, 0.03, 0] },
], { colors: cols(C.uniform2, C.uniform2) });
P(U, 'Bits', 'tube', 'Tube', [
	{ p: 'cyl', r: [0.025, 0.025], h: 0.12, n: 6, at: [0, 0.06, 0] },
], { colors: cols(C.uniform2, C.uniform2) });

// ================================================================ WEAPON
// Rifle space: the pistol grip at the origin, barrel toward -Z, +Y up.
// Anchors: receivers centred, barrels / handguards start at their back end,
// stocks at their front, grips / mags hang from their top, optics sit on
// their bottom. Drop a piece on a face and it extends the right way.
const W = 'weapon';
const WC = (main, trim, detail) => cols(main, main, trim || '#141416', detail || C.lens);

P(W, 'Frame', 'rcv_carbine', 'Carbine receiver', [
	{ p: 'box', s: [0.034, 0.05, 0.12], at: [0, 0.012, -0.05] },
	{ p: 'box', s: [0.032, 0.04, 0.16], at: [0, 0.058, -0.07] },
	{ p: 'box', s: [0.024, 0.01, 0.2], at: [0, 0.083, -0.09], m: 'trim' },
	{ p: 'box', s: [0.005, 0.016, 0.045], at: [0.017, 0.055, -0.06], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416'), pattern: 'grain' });
P(W, 'Frame', 'rcv_ak', 'Rifle receiver', [
	{ p: 'box', s: [0.04, 0.065, 0.26], at: [0, 0.03, -0.08] },
	{ p: 'box', s: [0.036, 0.022, 0.24], top: [0.85, 1], at: [0, 0.073, -0.085], m: 'trim' },
], { colors: WC('#3a3d40', '#2a2c2e'), pattern: 'grain' });
P(W, 'Frame', 'rcv_bullpup', 'Bullpup body', [
	{ p: 'box', s: [0.05, 0.11, 0.42], top: [0.9, 0.95], at: [0, 0.02, 0.06] },
	{ p: 'wedge', s: [0.05, 0.05, 0.1], at: [0, 0.0, -0.2], rot: [0, 180, 0] },
	{ p: 'box', s: [0.03, 0.05, 0.14], at: [0, 0.1, -0.05], m: 'trim' },
], { colors: WC('#4a4e52', '#1a1b1d'), pattern: 'grain' });
P(W, 'Frame', 'rcv_scifi', 'Plasma body', [
	{ p: 'box', s: [0.06, 0.1, 0.3], top: [0.7, 0.9], at: [0, 0.035, -0.06] },
	{ p: 'cyl', r: [0.03, 0.03], h: 0.18, n: 6, at: [0, 0.035, -0.12], rot: [90, 0, 0], sc: [1.3, 1, 1], m: 'detail' },
	{ p: 'box', s: [0.064, 0.02, 0.26], at: [0, 0.09, -0.06], m: 'trim' },
], { colors: WC('#e8e6df', '#2f3235', '#6ce0d0'), glow: true });
P(W, 'Frame', 'rcv_pistol', 'Pistol slide', [
	{ p: 'box', s: [0.028, 0.035, 0.19], at: [0, 0.06, -0.06] },
	{ p: 'box', s: [0.026, 0.03, 0.15], at: [0, 0.03, -0.04], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416') });

P(W, 'Barrels', 'barrel_long', 'Long barrel', [
	{ p: 'cyl', r: [0.012, 0.012], h: 0.45, n: 6, at: [0, 0, -0.225], rot: [90, 0, 0] },
], { colors: WC('#141416') });
P(W, 'Barrels', 'barrel_short', 'Short barrel', [
	{ p: 'cyl', r: [0.012, 0.012], h: 0.22, n: 6, at: [0, 0, -0.11], rot: [90, 0, 0] },
], { colors: WC('#141416') });
P(W, 'Barrels', 'barrel_heavy', 'Heavy barrel', [
	{ p: 'cyl', r: [0.022, 0.018], h: 0.5, n: 8, at: [0, 0, -0.25], rot: [90, 0, 0] },
	{ p: 'cyl', r: [0.028, 0.028], h: 0.04, n: 8, at: [0, 0, -0.12], rot: [90, 0, 0], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416') });
P(W, 'Barrels', 'handguard_rail', 'Rail handguard', [
	{ p: 'box', s: [0.044, 0.048, 0.26], at: [0, 0, -0.13] },
	{ p: 'box', s: [0.024, 0.01, 0.26], at: [0, 0.029, -0.13], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416'), pattern: 'grain' });
P(W, 'Barrels', 'handguard_round', 'Round handguard', [
	{ p: 'cyl', r: [0.028, 0.028], h: 0.24, n: 8, at: [0, 0, -0.12], rot: [90, 0, 0] },
	{ p: 'cyl', r: [0.03, 0.03], h: 0.015, n: 8, at: [0, 0, -0.005], rot: [90, 0, 0], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416') });
P(W, 'Barrels', 'handguard_wood', 'Wood handguard', [
	{ p: 'box', s: [0.05, 0.05, 0.22], top: [0.85, 1], at: [0, -0.005, -0.11] },
	{ p: 'box', s: [0.04, 0.025, 0.18], at: [0, 0.035, -0.1], m: 'trim' },
], { colors: WC(C.wood, '#4e3324'), pattern: 'wood', patScale: 0.12 });
P(W, 'Barrels', 'suppressor', 'Suppressor', [
	{ p: 'cyl', r: [0.022, 0.022], h: 0.17, n: 8, at: [0, 0, -0.085], rot: [90, 0, 0] },
], { colors: WC('#1a1b1d') });
P(W, 'Barrels', 'muzzle_brake', 'Muzzle brake', [
	{ p: 'cyl', r: [0.017, 0.017], h: 0.06, n: 6, at: [0, 0, -0.03], rot: [90, 0, 0] },
	{ p: 'box', s: [0.05, 0.012, 0.01], at: [0, 0, -0.02], m: 'trim' },
	{ p: 'box', s: [0.05, 0.012, 0.01], at: [0, 0, -0.04], m: 'trim' },
], { colors: WC('#141416', '#2a2c2e') });
P(W, 'Barrels', 'launcher_ub', 'Underbarrel launcher', [
	{ p: 'cyl', r: [0.03, 0.03], h: 0.26, n: 8, at: [0, -0.03, -0.13], rot: [90, 0, 0] },
	{ p: 'box', s: [0.03, 0.03, 0.2], at: [0, 0.0, -0.12], m: 'trim' },
], { colors: WC('#3b4228', '#141416') });
P(W, 'Barrels', 'rocket_tube', 'Rocket tube', [
	{ p: 'cyl', r: [0.06, 0.06], h: 1.0, n: 8, at: [0, 0, -0.5], rot: [90, 0, 0] },
	{ p: 'cyl', r: [0.075, 0.062], h: 0.12, n: 8, at: [0, 0, 0.0], rot: [90, 0, 0], m: 'trim' },
], { colors: WC('#565f36', '#141416') });

P(W, 'Stocks & grips', 'stock_fixed', 'Fixed stock', [
	{ p: 'box', s: [0.03, 0.055, 0.2], top: [1, 1], at: [0, 0.005, 0.1] },
	{ p: 'box', s: [0.032, 0.09, 0.07], at: [0, -0.01, 0.18] },
	{ p: 'box', s: [0.034, 0.095, 0.015], at: [0, -0.01, 0.22], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416') });
P(W, 'Stocks & grips', 'stock_skeleton', 'Skeleton stock', [
	{ p: 'tube', pts: [[0, 0.02, 0], [0, 0.02, 0.22]], r: 0.009, n: 5 },
	{ p: 'tube', pts: [[0, -0.02, 0], [0, -0.04, 0.22]], r: 0.009, n: 5 },
	{ p: 'box', s: [0.03, 0.09, 0.02], at: [0, -0.01, 0.23], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416') });
P(W, 'Stocks & grips', 'stock_wood', 'Wood stock', [
	{ p: 'box', s: [0.036, 0.05, 0.26], top: [1, 1], at: [0, -0.01, 0.13], rot: [-8, 0, 0], sc: [1, 1, 1] },
	{ p: 'box', s: [0.038, 0.11, 0.06], at: [0, -0.04, 0.24], rot: [-8, 0, 0] },
	{ p: 'box', s: [0.04, 0.115, 0.012], at: [0, -0.042, 0.275], rot: [-8, 0, 0], m: 'trim' },
], { colors: WC(C.wood, '#2a2c2e'), pattern: 'wood', patScale: 0.12 });
P(W, 'Stocks & grips', 'grip_pistol', 'Pistol grip', [
	{ p: 'box', s: [0.028, 0.095, 0.036], at: [0, -0.045, 0.012], rot: [-18, 0, 0] },
], { colors: WC('#1a1b1d') });
P(W, 'Stocks & grips', 'grip_wood', 'Wood grip', [
	{ p: 'box', s: [0.03, 0.1, 0.04], top: [1, 0.9], at: [0, -0.048, 0.014], rot: [-20, 0, 0] },
], { colors: WC(C.wood), pattern: 'wood', patScale: 0.1 });
P(W, 'Stocks & grips', 'foregrip', 'Foregrip', [
	{ p: 'cyl', r: [0.015, 0.017], h: 0.085, n: 6, at: [0, -0.0425, 0] },
], { colors: WC('#1a1b1d') });
P(W, 'Stocks & grips', 'trigger_guard', 'Trigger guard', [
	{ p: 'box', s: [0.008, 0.008, 0.07], at: [0, -0.035, -0.035], m: 'main' },
	{ p: 'box', s: [0.006, 0.02, 0.006], at: [0, -0.012, -0.045], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416') });

P(W, 'Mags & optics', 'mag_straight', 'Straight mag', [
	{ p: 'box', s: [0.022, 0.14, 0.05], at: [0, -0.07, 0] },
	{ p: 'box', s: [0.026, 0.012, 0.054], at: [0, -0.142, 0], m: 'trim' },
], { colors: WC('#2a2c2e', '#141416') });
P(W, 'Mags & optics', 'mag_curved', 'Curved mag', [
	{ p: 'box', s: [0.024, 0.07, 0.05], at: [0, -0.035, 0] },
	{ p: 'box', s: [0.024, 0.07, 0.052], at: [0, -0.098, -0.012], rot: [12, 0, 0] },
	{ p: 'box', s: [0.024, 0.06, 0.054], at: [0, -0.155, -0.035], rot: [26, 0, 0] },
], { colors: WC('#5b3a22', '#141416') });
P(W, 'Mags & optics', 'mag_drum', 'Drum mag', [
	{ p: 'box', s: [0.024, 0.04, 0.045], at: [0, -0.02, 0] },
	{ p: 'cyl', r: [0.065, 0.065], h: 0.05, n: 8, at: [0, -0.1, 0.0], rot: [0, 0, 90] },
], { colors: WC('#1a1b1d', '#2a2c2e') });
P(W, 'Mags & optics', 'scope', 'Scope', [
	{ p: 'cyl', r: [0.018, 0.018], h: 0.2, n: 8, at: [0, 0.045, 0], rot: [90, 0, 0] },
	{ p: 'cyl', r: [0.026, 0.02], h: 0.05, n: 8, at: [0, 0.045, -0.115], rot: [90, 0, 0] },
	{ p: 'cyl', r: [0.022, 0.018], h: 0.04, n: 8, at: [0, 0.045, 0.11], rot: [-90, 0, 0] },
	{ p: 'box', s: [0.02, 0.03, 0.025], at: [0, 0.015, -0.05], m: 'trim' },
	{ p: 'box', s: [0.02, 0.03, 0.025], at: [0, 0.015, 0.05], m: 'trim' },
	{ p: 'cyl', r: [0.022, 0.022], h: 0.004, n: 8, at: [0, 0.045, -0.142], rot: [90, 0, 0], m: 'detail' },
], { colors: WC('#1a1b1d', '#2a2c2e', '#7fb8d8'), glow: true });
P(W, 'Mags & optics', 'red_dot', 'Red dot', [
	{ p: 'box', s: [0.03, 0.035, 0.05], top: [0.8, 0.9], at: [0, 0.0175, 0] },
	{ p: 'box', s: [0.022, 0.022, 0.004], at: [0, 0.025, -0.02], m: 'detail' },
], { colors: WC('#1a1b1d', '#2a2c2e', C.red), glow: true });
P(W, 'Mags & optics', 'iron_sight', 'Iron sight', [
	{ p: 'box', s: [0.02, 0.025, 0.02], at: [0, 0.0125, 0] },
	{ p: 'box', s: [0.004, 0.012, 0.004], at: [0, 0.03, 0], m: 'trim' },
], { colors: WC('#141416', '#2a2c2e') });
P(W, 'Mags & optics', 'laser', 'Laser box', [
	{ p: 'box', s: [0.026, 0.026, 0.06], at: [0, 0.013, 0] },
	{ p: 'cyl', r: [0.006, 0.006], h: 0.006, n: 6, at: [0.006, 0.013, -0.031], rot: [90, 0, 0], m: 'detail' },
], { colors: WC('#3b4228', '#141416', '#3fe06a'), glow: true });
P(W, 'Mags & optics', 'bipod', 'Bipod', [
	{ p: 'box', s: [0.03, 0.02, 0.03], at: [0, -0.01, 0], m: 'trim' },
	{ p: 'tube', pts: [[0, -0.01, 0], [-0.06, -0.2, -0.02]], r: 0.006, n: 4 },
	{ p: 'tube', pts: [[0, -0.01, 0], [0.06, -0.2, -0.02]], r: 0.006, n: 4 },
], { colors: WC('#1a1b1d', '#2a2c2e') });

P(W, 'Melee', 'blade_sword', 'Sword blade', [
	{ p: 'box', s: [0.008, 0.045, 0.6], top: [1, 1], at: [0, 0, -0.3] },
	{ p: 'wedge', s: [0.008, 0.08, 0.045], at: [0, 0, -0.62], rot: [-90, 0, 0] },
], { colors: WC('#b9bdc0', '#7a7f84') });
P(W, 'Melee', 'blade_axe', 'Axe head', [
	{ p: 'box', s: [0.012, 0.16, 0.12], top: [0.5, 0.6], at: [0, 0.0, 0], rot: [-90, 0, 0] },
	{ p: 'box', s: [0.03, 0.04, 0.04], at: [0, 0, 0.06], m: 'trim' },
], { colors: WC('#7a7f84', '#2a2c2e') });
P(W, 'Melee', 'spear_tip', 'Spear tip', [
	{ p: 'cyl', r: [0.03, 0], h: 0.18, n: 4, at: [0, 0, -0.09], rot: [-90, 0, 0], sc: [1, 1, 0.3] },
], { colors: WC('#b9bdc0') });
P(W, 'Melee', 'crossguard', 'Crossguard', [
	{ p: 'box', s: [0.18, 0.028, 0.025], top: [1, 1], at: [0, 0, 0] },
], { colors: WC(C.brass), pattern: 'grain' });
P(W, 'Melee', 'handle', 'Handle', [
	{ p: 'cyl', r: [0.016, 0.016], h: 0.15, n: 6, at: [0, 0, 0.075], rot: [90, 0, 0] },
], { colors: WC('#4e3324'), pattern: 'bands', patScale: 0.03 });
P(W, 'Melee', 'pole', 'Long pole', [
	{ p: 'cyl', r: [0.016, 0.016], h: 1.2, n: 6, at: [0, 0, -0.3], rot: [90, 0, 0] },
], { colors: WC(C.wood), pattern: 'wood', patScale: 0.1 });
P(W, 'Melee', 'pommel', 'Pommel', [
	{ p: 'sph', r: 0.024, n: 6, rings: 3, at: [0, 0, 0.0] },
], { colors: WC(C.brass) });

P(W, 'Markers', 'muzzle_marker', 'Muzzle point', [
	{ p: 'sph', r: 0.012, n: 6, rings: 3, m: 'detail' },
	{ p: 'cyl', r: [0.004, 0], h: 0.05, n: 4, at: [0, 0, -0.03], rot: [-90, 0, 0], m: 'detail' },
], { colors: WC('#ffc847', '#ffc847', '#ffc847'), glow: true, marker: 'muzzle', desc: 'Where bullets and tracers leave. Not drawn in the game.' });

// ================================================================ BUILDING
// Anchored at the bottom centre; walls run along X, 0.2 m thick.
const B = 'building';
const BC = (main, ink, trim, detail) => cols(main, ink || main, trim || '#4a4e52', detail || C.glass);

P(B, 'Walls', 'wall', 'Wall', [
	{ p: 'box', s: [2, 2.6, 0.2], at: [0, 1.3, 0] },
], { colors: BC(C.wall, C.mortar), pattern: 'brick', patScale: 0.5 });
P(B, 'Walls', 'wall_half', 'Low wall', [
	{ p: 'box', s: [2, 1.1, 0.2], at: [0, 0.55, 0] },
	{ p: 'box', s: [2.04, 0.06, 0.26], at: [0, 1.13, 0], m: 'trim' },
], { colors: BC(C.wall, C.mortar, '#7c7a74'), pattern: 'brick', patScale: 0.5 });
P(B, 'Walls', 'wall_window', 'Window wall', [
	{ p: 'box', s: [2, 0.9, 0.2], at: [0, 0.45, 0] },
	{ p: 'box', s: [2, 0.6, 0.2], at: [0, 2.3, 0] },
	{ p: 'box', s: [0.6, 1.1, 0.2], at: [-0.7, 1.45, 0] },
	{ p: 'box', s: [0.6, 1.1, 0.2], at: [0.7, 1.45, 0] },
	{ p: 'box', s: [0.84, 0.05, 0.28], at: [0, 0.925, 0], m: 'trim' },
	{ p: 'box', s: [0.8, 1.1, 0.03], at: [0, 1.45, 0], m: 'detail' },
], { colors: BC(C.wall, C.mortar, '#5e574d', '#2d3f4f'), pattern: 'brick', patScale: 0.5 });
P(B, 'Walls', 'wall_door', 'Door wall', [
	{ p: 'box', s: [0.6, 2.6, 0.2], at: [-0.7, 1.3, 0] },
	{ p: 'box', s: [0.6, 2.6, 0.2], at: [0.7, 1.3, 0] },
	{ p: 'box', s: [0.8, 0.5, 0.2], at: [0, 2.35, 0] },
	{ p: 'box', s: [0.86, 0.06, 0.24], at: [0, 2.1, 0], m: 'trim' },
], { colors: BC(C.wall, C.mortar, '#5e574d'), pattern: 'brick', patScale: 0.5 });
P(B, 'Walls', 'wall_concrete', 'Concrete wall', [
	{ p: 'box', s: [2, 2.6, 0.25], at: [0, 1.3, 0] },
], { colors: BC(C.concrete, '#5f5d58'), pattern: 'grunge', patScale: 1 });
P(B, 'Walls', 'pillar', 'Pillar', [
	{ p: 'cyl', r: [0.16, 0.15], h: 2.6, n: 8, at: [0, 1.3, 0] },
	{ p: 'box', s: [0.42, 0.12, 0.42], at: [0, 0.06, 0], m: 'trim' },
	{ p: 'box', s: [0.42, 0.12, 0.42], at: [0, 2.54, 0], m: 'trim' },
], { colors: BC('#b9bdc0', '#9a9a95', '#7c7a74'), pattern: 'grain' });
P(B, 'Walls', 'fence', 'Fence', [
	{ p: 'box', s: [0.1, 1.2, 0.1], at: [-0.95, 0.6, 0], m: 'trim' },
	{ p: 'box', s: [0.1, 1.2, 0.1], at: [0.95, 0.6, 0], m: 'trim' },
	{ p: 'box', s: [2, 0.12, 0.04], at: [0, 0.4, 0] },
	{ p: 'box', s: [2, 0.12, 0.04], at: [0, 0.9, 0] },
], { colors: BC(C.wood, '#4e3324', '#4e3324'), pattern: 'wood', patScale: 0.4 });

P(B, 'Openings', 'door', 'Door', [
	{ p: 'box', s: [0.8, 2.1, 0.06], at: [0, 1.05, 0] },
	{ p: 'sph', r: 0.03, n: 6, rings: 2, at: [0.3, 1.0, -0.05], m: 'trim' },
], { colors: BC(C.wood, '#4e3324', C.brass), pattern: 'wood', patScale: 0.4 });
P(B, 'Openings', 'window_frame', 'Window frame', [
	{ p: 'box', s: [0.9, 0.06, 0.12], at: [0, 0.03, 0] },
	{ p: 'box', s: [0.9, 0.06, 0.12], at: [0, 1.17, 0] },
	{ p: 'box', s: [0.06, 1.2, 0.12], at: [-0.42, 0.6, 0] },
	{ p: 'box', s: [0.06, 1.2, 0.12], at: [0.42, 0.6, 0] },
	{ p: 'box', s: [0.04, 1.1, 0.06], at: [0, 0.6, 0] },
], { colors: BC('#e8e6df', '#e8e6df') });
P(B, 'Openings', 'shutters', 'Shutters', [
	{ p: 'box', s: [0.45, 1.2, 0.04], at: [-0.68, 0.6, 0] },
	{ p: 'box', s: [0.45, 1.2, 0.04], at: [0.68, 0.6, 0] },
], { colors: BC('#2d5c3a', '#1f4029'), pattern: 'bands', patScale: 0.12 });
P(B, 'Openings', 'awning', 'Awning', [
	{ p: 'box', s: [1.4, 0.04, 0.8], at: [0, 0, -0.4], rot: [-15, 0, 0] },
], { colors: BC('#b8321e', '#e8e6df'), pattern: 'stripes', patScale: 0.6 });
P(B, 'Openings', 'stairs', 'Stairs', [
	{ p: 'box', s: [1, 0.25, 1.5], at: [0, 0.125, 0] },
	{ p: 'box', s: [1, 0.25, 1.2], at: [0, 0.375, 0.15] },
	{ p: 'box', s: [1, 0.25, 0.9], at: [0, 0.625, 0.3] },
	{ p: 'box', s: [1, 0.25, 0.6], at: [0, 0.875, 0.45] },
	{ p: 'box', s: [1, 0.25, 0.3], at: [0, 1.125, 0.6] },
], { colors: BC(C.concrete, '#5f5d58'), pattern: 'grunge', patScale: 1 });

P(B, 'Roofs & floors', 'floor', 'Floor slab', [
	{ p: 'box', s: [2, 0.15, 2], at: [0, 0.075, 0] },
], { colors: BC(C.concrete, '#5f5d58'), pattern: 'stone', patScale: 1 });
P(B, 'Roofs & floors', 'floor_wood', 'Wood floor', [
	{ p: 'box', s: [2, 0.1, 2], at: [0, 0.05, 0] },
], { colors: BC('#8a5a33', '#4e3324'), pattern: 'wood', patScale: 0.8 });
P(B, 'Roofs & floors', 'roof_gable', 'Gable roof', [
	{ p: 'wedge', s: [2.2, 1, 1.1], at: [0, 0.5, -0.55] },
	{ p: 'wedge', s: [2.2, 1, 1.1], at: [0, 0.5, 0.55], rot: [0, 180, 0] },
], { colors: BC(C.roof, '#4a1f17'), pattern: 'scales', patScale: 0.5 });
P(B, 'Roofs & floors', 'roof_flat', 'Flat roof', [
	{ p: 'box', s: [2.2, 0.15, 2.2], at: [0, 0.075, 0] },
	{ p: 'box', s: [2.2, 0.3, 0.1], at: [0, 0.3, -1.05], m: 'trim' },
	{ p: 'box', s: [2.2, 0.3, 0.1], at: [0, 0.3, 1.05], m: 'trim' },
], { colors: BC('#4a4e52', '#2f3235', '#7c7a74'), pattern: 'grunge', patScale: 1 });
P(B, 'Roofs & floors', 'chimney', 'Chimney', [
	{ p: 'box', s: [0.5, 1.2, 0.5], at: [0, 0.6, 0] },
	{ p: 'box', s: [0.6, 0.1, 0.6], at: [0, 1.2, 0], m: 'trim' },
], { colors: BC('#8a4a33', '#4e2a1e', '#5e574d'), pattern: 'brick', patScale: 0.4 });

P(B, 'Props', 'crate', 'Crate', [
	{ p: 'box', s: [1, 1, 1], at: [0, 0.5, 0] },
	{ p: 'box', s: [1.04, 0.1, 1.04], at: [0, 0.05, 0], m: 'trim' },
	{ p: 'box', s: [1.04, 0.1, 1.04], at: [0, 0.95, 0], m: 'trim' },
], { colors: BC('#8a6a3f', '#5b4026', '#5b4026'), pattern: 'wood', patScale: 0.5 });
P(B, 'Props', 'barrel', 'Barrel', [
	{ p: 'cyl', r: [0.3, 0.3], h: 0.9, n: 10, at: [0, 0.45, 0] },
	{ p: 'cyl', r: [0.31, 0.31], h: 0.05, n: 10, at: [0, 0.2, 0], m: 'trim' },
	{ p: 'cyl', r: [0.31, 0.31], h: 0.05, n: 10, at: [0, 0.7, 0], m: 'trim' },
], { colors: BC('#2d5c3a', '#1f4029', '#1a1b1d'), pattern: 'grunge', patScale: 0.6 });
P(B, 'Props', 'sandbags', 'Sandbags', [
	{ p: 'box', s: [0.6, 0.2, 0.35], top: [0.9, 0.9], at: [-0.62, 0.1, 0] },
	{ p: 'box', s: [0.6, 0.2, 0.35], top: [0.9, 0.9], at: [0, 0.1, 0] },
	{ p: 'box', s: [0.6, 0.2, 0.35], top: [0.9, 0.9], at: [0.62, 0.1, 0] },
	{ p: 'box', s: [0.6, 0.2, 0.33], top: [0.9, 0.9], at: [-0.31, 0.3, 0] },
	{ p: 'box', s: [0.6, 0.2, 0.33], top: [0.9, 0.9], at: [0.31, 0.3, 0] },
], { colors: BC('#a89068', '#7a6448'), pattern: 'grain' });
P(B, 'Props', 'lamp_post', 'Street lamp', [
	{ p: 'cyl', r: [0.07, 0.05], h: 3.4, n: 6, at: [0, 1.7, 0] },
	{ p: 'box', s: [0.08, 0.08, 0.7], at: [0, 3.35, -0.3], m: 'trim' },
	{ p: 'box', s: [0.25, 0.08, 0.3], top: [0.7, 0.7], at: [0, 3.3, -0.62], m: 'detail' },
], { colors: BC('#2a2c2e', '#2a2c2e', '#2a2c2e', '#ffcf6a'), glow: true });
P(B, 'Props', 'sign', 'Sign', [
	{ p: 'box', s: [0.08, 2, 0.08], at: [0, 1, 0], m: 'trim' },
	{ p: 'box', s: [0.9, 0.5, 0.05], at: [0, 1.8, 0] },
], { colors: BC('#e6c040', '#1a1b1d', '#4a4e52'), pattern: 'stripes', patScale: 0.3 });
P(B, 'Props', 'barrier', 'Jersey barrier', [
	{ p: 'box', s: [2, 0.25, 0.6], at: [0, 0.125, 0] },
	{ p: 'box', s: [2, 0.6, 0.6], top: [1, 0.35], at: [0, 0.55, 0] },
], { colors: BC(C.concrete, '#5f5d58'), pattern: 'grunge', patScale: 1 });

// ================================================================ templates
// [part id, bone (side parts: R and the L mirror are both made), overrides]

const TROOPER = [
	['hips_basic'], ['battle_belt'], ['holster'],
	['torso_trooper'], ['plate_carrier'], ['pack_assault'],
	['head_hood'], ['helmet_highcut'], ['goggles'],
	['upper_arm_prism', 'upper_arm_*'], ['forearm_glove', 'forearm_*'],
	['thigh_prism', 'thigh_*'], ['shin_boot', 'shin_*'], ['foot_boot', 'foot_*'], ['knee_pad', 'shin_*'],
	['pouch_mag', 'torso', { pos: [-0.075, 1.22, -0.16], normal: [0, 0, -1] }],
	['pouch_mag', 'torso', { pos: [0.0, 1.22, -0.16], normal: [0, 0, -1], mirror: false }],
	['radio', 'torso', { pos: [-0.115, 1.39, -0.16], normal: [0, 0, -1], mirror: false }],
];
const MANNEQUIN = [
	['hips_round'], ['torso_slim'], ['head_round'],
	['upper_arm_round', 'upper_arm_*'], ['forearm_hand', 'forearm_*', { colors: { detail: '#b9bdc0' } }],
	['thigh_round', 'thigh_*'], ['shin_round', 'shin_*'], ['foot_sandal', 'foot_*', { colors: { detail: '#b9bdc0', trim: '#b9bdc0' } }],
].map((t) => { const o = t[2] || {}; o.colors = Object.assign({ main: '#b9bdc0', ink: '#b9bdc0' }, o.colors); return [t[0], t[1], o]; });
const KNIGHT = [
	['hips_basic', null, { colors: { main: '#5b4a35' } }], ['skirt'],
	['torso_brute', null, { colors: { main: '#5b4a35', ink: '#5b4a35' } }], ['breastplate'], ['cape'],
	['head_face'], ['helmet_knight'],
	['upper_arm_brute', 'upper_arm_*', { colors: { main: '#5b4a35', ink: '#5b4a35' }, pattern: 'chain', patScale: 0.06 }], ['pauldron', 'upper_arm_*'],
	['forearm_glove', 'forearm_*', { colors: { main: '#5b4a35', trim: '#7a7f84' } }], ['bracer', 'forearm_*'],
	['thigh_round', 'thigh_*', { colors: { main: '#7a7f84', ink: '#4a4e52' }, pattern: 'chain', patScale: 0.06 }],
	['shin_greave', 'shin_*'], ['foot_sabaton', 'foot_*'],
];

export const TEMPLATES = {
	humanoid: { trooper: { name: 'Trooper', parts: TROOPER }, knight: { name: 'Knight', parts: KNIGHT }, mannequin: { name: 'Mannequin', parts: MANNEQUIN }, blank: { name: 'Blank skeleton', parts: [] } },
	weapon: {
		carbine: {
			name: 'Carbine', parts: [
				['rcv_carbine', 'rifle', { pos: [0, 0, 0] }],
				['grip_pistol', 'rifle', { pos: [0, -0.012, 0.01] }],
				['mag_straight', 'rifle', { pos: [0, -0.012, -0.1], rot: [8, 0, 0] }],
				['stock_fixed', 'rifle', { pos: [0, 0.04, 0.02] }],
				['handguard_rail', 'rifle', { pos: [0, 0.05, -0.15] }],
				['barrel_long', 'rifle', { pos: [0, 0.05, -0.38], size: [1, 1, 0.55] }],
				['muzzle_brake', 'rifle', { pos: [0, 0.05, -0.62] }],
				['red_dot', 'rifle', { pos: [0, 0.088, -0.06] }],
				['muzzle_marker', 'rifle', { pos: [0, 0.05, -0.69] }],
			],
		},
		sword: {
			name: 'Sword', parts: [
				['handle', 'rifle', { pos: [0, 0, -0.07] }],
				['pommel', 'rifle', { pos: [0, 0, 0.09] }],
				['crossguard', 'rifle', { pos: [0, 0, -0.075] }],
				['blade_sword', 'rifle', { pos: [0, 0, -0.09] }],
				['muzzle_marker', 'rifle', { pos: [0, 0, -0.75] }],
			],
		},
		blank: { name: 'Blank', parts: [] },
	},
	building: {
		house: {
			name: 'Small house', parts: [
				['floor', 'building', { pos: [0, 0, 0], size: [3, 1, 1.5] }],
				['wall_door', 'building', { pos: [0, 0.15, -1.4] }],
				['wall', 'building', { pos: [-2, 0.15, -1.4] }],
				['wall_window', 'building', { pos: [2, 0.15, -1.4] }],
				['wall', 'building', { pos: [0, 0.15, 1.4] }],
				['wall_window', 'building', { pos: [-2, 0.15, 1.4] }],
				['wall', 'building', { pos: [2, 0.15, 1.4] }],
				['wall_window', 'building', { pos: [-2.9, 0.15, 0], rot: [0, 90, 0], size: [1.3, 1, 1] }],
				['wall_window', 'building', { pos: [2.9, 0.15, 0], rot: [0, 90, 0], size: [1.3, 1, 1] }],
				['door', 'building', { pos: [0, 0.15, -1.52] }],
				['roof_gable', 'building', { pos: [0, 2.75, 0], size: [2.85, 1, 1.4] }],
				['chimney', 'building', { pos: [1.6, 3, 0.6] }],
			],
		},
		blank: { name: 'Blank', parts: [] },
	},
};
