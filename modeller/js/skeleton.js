// The Squad Test soldier's skeleton, ported from scripts/soldier_model.gd so
// parts made here land in exactly the bone spaces the game animates:
//   hips, torso (the game's "upper" space = model space at rest), head,
//   upper_arm_L/R, forearm_L/R, thigh_L/R, shin_L/R, foot_L/R.
// Model space: metres, origin between the feet, -Z forward, +X = his right.
// Limb bones point their -Y axis down the bone (game's _aim_bone), so a part
// on a bone keeps its place in every pose the game puts him in.
import * as THREE from 'three';

export const H = {
	HIP_Y: 0.985, HIP_X: 0.105, THIGH: 0.44, SHIN: 0.43, ANKLE_Y: 0.085,
	SHOULDER: new THREE.Vector3(0.205, 1.47, 0), UPPER_ARM: 0.31, FOREARM: 0.28, WAIST_Y: 0.99,
};

const V = (x, y, z) => new THREE.Vector3(x, y, z);

export const BONES = {
	humanoid: [
		{ name: 'hips', label: 'Hips', proxy: { box: [0.3, 0.26, 0.22], at: [0, -0.01, 0] } },
		{ name: 'torso', label: 'Torso', proxy: { box: [0.46, 0.66, 0.28], at: [0, 1.28, 0] } },
		{ name: 'head', label: 'Head', proxy: { sph: 0.12, at: [0, 0.08, 0] } },
		...['L', 'R'].flatMap((s) => [
			{ name: `upper_arm_${s}`, label: `Upper arm ${s}`, side: s, proxy: { cyl: [0.07, 0.31], at: [0, -0.155, 0] } },
			{ name: `forearm_${s}`, label: `Forearm ${s}`, side: s, proxy: { cyl: [0.06, 0.38], at: [0, -0.19, 0] } },
			{ name: `thigh_${s}`, label: `Thigh ${s}`, side: s, proxy: { cyl: [0.09, 0.44], at: [0, -0.22, 0] } },
			{ name: `shin_${s}`, label: `Shin ${s}`, side: s, proxy: { cyl: [0.075, 0.43], at: [0, -0.215, 0] } },
			{ name: `foot_${s}`, label: `Foot ${s}`, side: s, proxy: { box: [0.11, 0.09, 0.27], at: [0, -0.045, -0.05] } },
		]),
	],
	weapon: [{ name: 'rifle', label: 'Weapon' }],
	building: [{ name: 'building', label: 'Building' }],
};

export function otherSide(name) {
	if (name.endsWith('_L')) return name.slice(0, -1) + 'R';
	if (name.endsWith('_R')) return name.slice(0, -1) + 'L';
	return null;
}

export function boneSide(name) {
	if (name.endsWith('_L')) return 'L';
	if (name.endsWith('_R')) return 'R';
	return null;
}

// ------------------------------------------------------------ game IK, ported

// Bone matrix at `from`, its -Y axis toward `to`, bending toward `pole`.
function aimBone(from, to, pole) {
	const y = new THREE.Vector3().subVectors(from, to).normalize();
	let x = new THREE.Vector3().crossVectors(y, pole);
	if (x.length() < 0.01) x = new THREE.Vector3().crossVectors(y, V(0, 0, -1));
	x.normalize();
	const z = new THREE.Vector3().crossVectors(x, y).normalize();
	return new THREE.Matrix4().makeBasis(x, y, z).setPosition(from);
}

// Two-bone IK: the middle joint (knee / elbow).
function solve(root, target, a, b, pole) {
	const to = new THREE.Vector3().subVectors(target, root);
	const d = THREE.MathUtils.clamp(to.length(), Math.abs(a - b) + 0.001, a + b - 0.001);
	const u = to.clone().normalize();
	const cosA = THREE.MathUtils.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1);
	const v = pole.clone().sub(u.clone().multiplyScalar(pole.dot(u))).normalize();
	return root.clone().add(u.multiplyScalar(cosA * a)).add(v.multiplyScalar(Math.sqrt(1 - cosA * cosA) * a));
}

// Godot's Basis.looking_at: -Z toward dir.
function lookingAt(dir, up = V(0, 1, 0)) {
	const z = dir.clone().normalize().negate();
	const x = new THREE.Vector3().crossVectors(up, z).normalize();
	const y = new THREE.Vector3().crossVectors(z, x);
	return new THREE.Matrix4().makeBasis(x, y, z);
}

const ry = (a) => new THREE.Matrix4().makeRotationY(a);
const rx = (a) => new THREE.Matrix4().makeRotationX(a);
const tr = (v) => new THREE.Matrix4().makeTranslation(v.x, v.y, v.z);

// The game's low-ready rifle hold (upper space): rifle transform, both hands.
function rifleHold() {
	const grip = V(0.13, 1.16, -0.15);
	const rifle = lookingAt(V(-0.38, -0.16, -1.0)).setPosition(grip);
	const guard = V(-0.022, -0.025, -0.27).applyMatrix4(rifle);
	return { rifle, grip, guard };
}

function smooth(t) { return t * t * (3 - 2 * t); }

// Bone matrices (model space) for a pose:
//   'rest'  arms down and out (easiest to build on)
//   'ready' the game's idle: rifle at low ready
//   'walk'  the game's gait (simplified), rifle at low ready; t = seconds
export function humanoidPose(kind, t = 0) {
	const M = {};
	const walk = kind === 'walk';
	const speed = 1.6;
	const cycle = 0.9 + 0.38 * speed;
	const phase = walk ? ((t * speed) / cycle) % 1 : 0;
	const stance = 0.62;
	const bob = walk ? 0.022 * Math.cos(Math.PI * 2 * 2 * (phase - stance * 0.5)) : 0;
	const twist = walk ? 0.07 * Math.sin(Math.PI * 2 * phase) : 0;
	const hipsPos = V(0, H.HIP_Y - 0.02 + bob, 0);
	M.hips = tr(hipsPos).multiply(ry(-twist * 0.6));
	// upper body sits on the hips (laid out for hips at 0.93), pivoting at the waist
	const waist = V(0, H.WAIST_Y, 0);
	const onHips = V(0, H.HIP_Y - 0.93 - 0.02 + bob, 0);
	const rot = ry(twist);
	const upper = tr(onHips.clone().add(waist)).multiply(rot).multiply(tr(waist.clone().negate()));
	M.torso = upper.clone();
	M.head = upper.clone().multiply(tr(V(0, 1.645, 0)));

	// arms (upper space)
	const hold = rifleHold();
	for (const s of ['L', 'R']) {
		const sx = s === 'L' ? -1 : 1;
		const sh = H.SHOULDER.clone().multiply(V(sx, 1, 1));
		let hand;
		if (kind === 'rest') hand = sh.clone().add(V(0.2 * sx, -0.545, 0.03));
		else hand = s === 'L' ? hold.guard : hold.grip;
		const elbow = solve(sh, hand, H.UPPER_ARM, H.FOREARM, V(0.7 * sx, -0.7, 0.35));
		M[`upper_arm_${s}`] = upper.clone().multiply(aimBone(sh, elbow, V(sx, 0, 0)));
		M[`forearm_${s}`] = upper.clone().multiply(aimBone(elbow, hand, V(sx, 0, 0)));
	}
	if (kind !== 'rest') M.rifle = upper.clone().multiply(hold.rifle);

	// legs
	const reach = Math.min(cycle * stance * 0.5, 0.45);
	for (const s of ['L', 'R']) {
		const sx = s === 'L' ? -1 : 1;
		const hip = hipsPos.clone().add(V(H.HIP_X * sx, -0.04, 0));
		let ankle, pitch = 0;
		if (kind === 'ready') ankle = V(H.HIP_X * sx * 1.15, H.ANKLE_Y, s === 'R' ? 0.03 : -0.08);
		else if (!walk) ankle = V(0.12 * sx, H.ANKLE_Y, 0);
		else {
			const p = (phase + (s === 'R' ? 0.5 : 0)) % 1;
			let off, h = 0;
			if (p < stance) {
				const k = p / stance;
				off = reach * (1 - 2 * k);
				pitch = THREE.MathUtils.lerp(0.15, -0.3, k);
			} else {
				const k = (p - stance) / (1 - stance);
				off = -reach + 2 * reach * smooth(k);
				h = 0.1 * Math.sin(Math.PI * k);
				pitch = THREE.MathUtils.lerp(-0.55, 0.2, k);
			}
			ankle = V(H.HIP_X * sx * 1.1, H.ANKLE_Y + h, -off);
			const toe = -0.0875 * Math.cos(pitch) + 0.185 * Math.sin(pitch);
			const heel = -0.0875 * Math.cos(pitch) - 0.085 * Math.sin(pitch);
			ankle.y = Math.max(ankle.y, -Math.min(toe, heel) + 0.002);
		}
		const to = ankle.clone().sub(hip);
		const maxLen = H.THIGH + H.SHIN - 0.015;
		if (to.length() > maxLen) ankle = hip.clone().add(to.setLength(maxLen));
		const knee = solve(hip, ankle, H.THIGH, H.SHIN, V(0.1 * sx, 0, -1));
		M[`thigh_${s}`] = aimBone(hip, knee, V(0, 0, -1));
		M[`shin_${s}`] = aimBone(knee, ankle, V(0, 0, -1));
		M[`foot_${s}`] = tr(ankle).multiply(ry(0.08 * sx)).multiply(rx(pitch));
	}
	return M;
}

export function poseFor(mode, kind, t) {
	if (mode === 'humanoid') return humanoidPose(kind, t);
	if (mode === 'weapon') return { rifle: new THREE.Matrix4() };
	return { building: new THREE.Matrix4() };
}

// Mirror a bone-local transform across the model's X = 0 plane (the twin on
// the other side, or the other half of a centred bone): S * L * S.
export function mirrorLocal(pos, quat) {
	return {
		pos: [-pos[0], pos[1], pos[2]],
		quat: [quat[0], -quat[1], -quat[2], quat[3]],
	};
}
