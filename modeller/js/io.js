// Export to .glb (for Godot / Squad Test) and reading designs back.
//
// Layout of an exported file (all in metres, +Y up, -Z forward):
//   Character            root, extras.squad_modeller = format info
//     hips, torso, head, upper_arm_L ... foot_R
//                        one node per game bone, placed at the build pose.
//                        Its mesh is in that bone's own space, exactly what
//                        scripts/soldier_model.gd hangs on the bone, so the
//                        game can swap it in and animate it as is.
//   Weapon
//     rifle              grip at the origin, barrel toward -Z
//       muzzle           empty node where shots leave (if placed)
//   Building
//     building           one mesh, origin at ground level
// Each bone mesh has one surface per material (pattern textures embedded,
// nearest filtering). The full editable design is stored in the scene's
// extras, so a .glb opens here again.
import * as THREE from 'three';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';
import { PARTS } from './parts.js';
import { buildPartGeometry } from './geometry.js';
import { partMaterials, exportMaterial } from './materials.js';
import { BONES, poseFor } from './skeleton.js';

export const FORMAT = 'squad-modeller';
export const VERSION = 1;
export const ROOT_NAME = { humanoid: 'Character', weapon: 'Weapon', building: 'Building' };

// Merged geometry of every (non-marker) part on one bone, in bone space.
export function boneGeometry(parts) {
	const buckets = new Map();
	const m = new THREE.Matrix4(), nm = new THREE.Matrix3();
	const v = new THREE.Vector3();
	for (const p of parts) {
		const def = PARTS[p.def];
		if (!def || def.marker) continue;
		const geo = buildPartGeometry(def, p);
		const mats = partMaterials(p);
		m.compose(new THREE.Vector3(...p.pos), new THREE.Quaternion(...p.quat), new THREE.Vector3(1, 1, 1));
		nm.getNormalMatrix(m);
		const P = geo.attributes.position.array, N = geo.attributes.normal.array, UV = geo.attributes.uv.array;
		for (const g of geo.groups) {
			const mat = exportMaterial(mats[g.materialIndex]);
			if (!buckets.has(mat)) buckets.set(mat, { pos: [], nrm: [], uv: [] });
			const b = buckets.get(mat);
			for (let i = g.start; i < g.start + g.count; i++) {
				v.set(P[i * 3], P[i * 3 + 1], P[i * 3 + 2]).applyMatrix4(m);
				b.pos.push(v.x, v.y, v.z);
				v.set(N[i * 3], N[i * 3 + 1], N[i * 3 + 2]).applyMatrix3(nm).normalize();
				b.nrm.push(v.x, v.y, v.z);
				b.uv.push(UV[i * 2], UV[i * 2 + 1]);
			}
		}
		geo.dispose();
	}
	if (!buckets.size) return null;
	let pos = [], nrm = [], uv = [];
	const mats = [];
	const geo = new THREE.BufferGeometry();
	let start = 0;
	for (const [mat, b] of buckets) {
		pos = pos.concat(b.pos); nrm = nrm.concat(b.nrm); uv = uv.concat(b.uv);
		const count = b.pos.length / 3;
		geo.addGroup(start, count, mats.length);
		mats.push(mat);
		start += count;
	}
	geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
	geo.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
	geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
	return { geo, mats };
}

export function buildExportScene(design) {
	const scene = new THREE.Scene();
	scene.name = design.name || 'model';
	scene.userData = { squad_modeller: design };
	const root = new THREE.Object3D();
	root.name = ROOT_NAME[design.mode];
	const boneList = BONES[design.mode];
	root.userData = {
		squad_modeller: { format: FORMAT, version: VERSION, mode: design.mode, units: 'm', up: '+Y', forward: '-Z', bones: boneList.map((b) => b.name) },
	};
	scene.add(root);
	const pose = poseFor(design.mode, 'rest', 0);
	for (const b of boneList) {
		const parts = design.parts.filter((p) => p.bone === b.name);
		const merged = boneGeometry(parts);
		const node = merged ? new THREE.Mesh(merged.geo, merged.mats) : new THREE.Object3D();
		node.name = b.name;
		const mat = pose[b.name] || new THREE.Matrix4();
		mat.decompose(node.position, node.quaternion, node.scale);
		for (const p of parts) {
			const def = PARTS[p.def];
			if (!def || !def.marker) continue;
			const mk = new THREE.Object3D();
			mk.name = def.marker;
			mk.position.set(...p.pos);
			mk.quaternion.set(...p.quat);
			node.add(mk);
		}
		root.add(node);
	}
	return scene;
}

export function exportGLB(design) {
	const scene = buildExportScene(design);
	return new Promise((resolve, reject) => {
		new GLTFExporter().parse(scene, resolve, reject, { binary: true, trs: true });
	});
}

// The design stored in a .glb's scene extras (null if none).
export function readGLBDesign(buf) {
	const dv = new DataView(buf);
	if (dv.getUint32(0, true) !== 0x46546c67) throw new Error('Not a .glb file');
	const len = dv.getUint32(12, true);
	const json = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, 20, len)));
	const ex = json.scenes && json.scenes[0] && json.scenes[0].extras;
	return (ex && ex.squad_modeller) || null;
}

export function download(data, filename, type) {
	const blob = data instanceof Blob ? data : new Blob([data], { type });
	const a = document.createElement('a');
	a.href = URL.createObjectURL(blob);
	a.download = filename;
	document.body.appendChild(a);
	a.click();
	setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}
