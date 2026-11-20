// Part materials and the PSX look. Lambert shading, nearest-filtered
// textures, and (when PSX preview is on) vertices snapped to a coarse screen
// grid so models wobble like late-90s hardware. Materials are shared by
// key, so a hundred parts in the same colours cost one material.
import * as THREE from 'three';
import { patternTexture } from './textures.js';

export const psxUniforms = { psxRes: { value: new THREE.Vector2(0, 0) } };

function psxify(mat) {
	mat.onBeforeCompile = (shader) => {
		shader.uniforms.psxRes = psxUniforms.psxRes;
		shader.vertexShader = 'uniform vec2 psxRes;\n' + shader.vertexShader.replace(
			'#include project_vertex',
			`#include project_vertex
			if (psxRes.x > 0.0) {
				vec2 g = psxRes * 0.5;
				gl_Position.xy = floor(gl_Position.xy / gl_Position.w * g + 0.5) / g * gl_Position.w;
			}`,
		);
	};
	mat.customProgramCacheKey = () => 'psx';
	return mat;
}

const _mats = new Map();

function col(c) { return new THREE.Color(c); }

// The three materials of a part: [main (patterned), trim, detail].
export function partMaterials(part) {
	const c = part.colors;
	const keyMain = `m|${part.pattern}|${c.main}|${c.ink}`;
	const keyTrim = `t|${c.trim}`;
	const keyDet = `d|${c.detail}|${part.glow ? 1 : 0}`;
	if (!_mats.has(keyMain)) {
		const tex = patternTexture(part.pattern || 'solid', col(c.main), col(c.ink));
		_mats.set(keyMain, psxify(new THREE.MeshLambertMaterial({ map: tex, name: keyMain })));
	}
	if (!_mats.has(keyTrim)) _mats.set(keyTrim, psxify(new THREE.MeshLambertMaterial({ color: col(c.trim), name: keyTrim })));
	if (!_mats.has(keyDet)) {
		const m = new THREE.MeshLambertMaterial({ color: col(c.detail), name: keyDet });
		if (part.glow) { m.emissive = col(c.detail); m.emissiveIntensity = 0.9; }
		_mats.set(keyDet, psxify(m));
	}
	if (part.vcol) {
		// imported mesh in its own colours (per-triangle vertex colours)
		if (!_mats.has('vcol')) _mats.set('vcol', psxify(new THREE.MeshLambertMaterial({ vertexColors: true, name: 'vcol' })));
		return [_mats.get('vcol'), _mats.get(keyTrim), _mats.get(keyDet)];
	}
	return [_mats.get(keyMain), _mats.get(keyTrim), _mats.get(keyDet)];
}

// Exported (glTF) versions: plain standard materials, fully rough.
const _exp = new Map();
export function exportMaterial(mat) {
	if (_exp.has(mat)) return _exp.get(mat);
	const m = new THREE.MeshStandardMaterial({ roughness: 1, metalness: 0, name: mat.name });
	if (mat.vertexColors) m.vertexColors = true;
	if (mat.map) m.map = mat.map;
	else m.color.copy(mat.color);
	if (mat.emissive && mat.emissive.getHex() !== 0) { m.emissive.copy(mat.emissive); m.emissiveIntensity = 1; }
	_exp.set(mat, m);
	return m;
}

// Ghost material for drag previews.
export const ghostMat = new THREE.MeshBasicMaterial({ color: 0x8fe3ff, transparent: true, opacity: 0.45, depthWrite: false });
export const selectMat = new THREE.MeshBasicMaterial({ color: 0xffc847, wireframe: true, transparent: true, opacity: 0.55, depthTest: false });
