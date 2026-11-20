// Tiny repeating pattern textures (32 or 64 px, nearest filtering) drawn in
// a part's main colour with its ink colour. One tile covers the part's
// "pattern size" in metres, so stripes and camo stay the same scale on every
// part. Deterministic: the same pattern and colours always give the same
// pixels, so saved designs look identical when reopened.
import * as THREE from 'three';

function rng(seed) {
	let s = seed >>> 0 || 1;
	return () => {
		s ^= s << 13; s >>>= 0;
		s ^= s >> 17;
		s ^= s << 5; s >>>= 0;
		return s / 4294967296;
	};
}

function hashStr(str) {
	let h = 2166136261;
	for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
	return h >>> 0;
}

function hex(c) { return '#' + c.getHexString(); }

function mix(a, b, t) { return a.clone().lerp(b, t); }

// Wrapping blob painter (circles that wrap across tile edges).
function blob(ctx, S, x, y, r) {
	for (const dx of [-S, 0, S]) for (const dy of [-S, 0, S]) {
		ctx.beginPath();
		ctx.arc(x + dx, y + dy, r, 0, Math.PI * 2);
		ctx.fill();
	}
}

function pix(ctx, x, y, w = 1, h = 1) { ctx.fillRect(x, y, w, h); }

export const PATTERNS = {
	solid: { label: 'Solid', size: 8, draw(ctx, S, a) { ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S); } },
	grain: {
		label: 'Grain', size: 32,
		draw(ctx, S, a, b, r) {
			for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
				ctx.fillStyle = hex(mix(a, b, r() * 0.22));
				pix(ctx, x, y);
			}
		},
	},
	camo: {
		label: 'Woodland', size: 64,
		draw(ctx, S, a, b, r) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			const c2 = mix(a, b, 0.5);
			for (const [col, n, rad] of [[c2, 10, 7], [b, 9, 5], [mix(b, new THREE.Color(0, 0, 0), 0.4), 7, 3]]) {
				ctx.fillStyle = hex(col);
				for (let i = 0; i < n; i++) {
					const x = r() * S, y = r() * S;
					for (let k = 0; k < 4; k++) blob(ctx, S, x + (r() - 0.5) * rad * 2, y + (r() - 0.5) * rad, rad * (0.5 + r() * 0.6));
				}
			}
		},
	},
	digital: {
		label: 'Digital', size: 32,
		draw(ctx, S, a, b, r) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			const cols = [mix(a, b, 0.45), b, mix(a, b, 0.75)];
			for (const col of cols) {
				ctx.fillStyle = hex(col);
				for (let i = 0; i < 9; i++) {
					let x = Math.floor(r() * S / 2) * 2, y = Math.floor(r() * S / 2) * 2;
					for (let k = 0; k < 6; k++) {
						pix(ctx, (x + S) % S, (y + S) % S, 2, 2);
						x += (Math.floor(r() * 3) - 1) * 2; y += (Math.floor(r() * 3) - 1) * 2;
					}
				}
			}
		},
	},
	tiger: {
		label: 'Tiger', size: 64,
		draw(ctx, S, a, b, r) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			ctx.fillStyle = hex(b);
			for (let i = 0; i < 7; i++) {
				const y0 = (i / 7) * S + r() * 4;
				const len = 18 + r() * 30, x0 = r() * S;
				for (let x = 0; x < len; x += 1) {
					const th = 3.2 * Math.sin((x / len) * Math.PI) + 0.6;
					const y = y0 + Math.sin((x0 + x) * 0.15) * 2.5;
					pix(ctx, (x0 + x) % S, ((Math.round(y - th / 2)) % S + S) % S, 1, Math.max(1, Math.round(th)));
				}
			}
		},
	},
	stripes: {
		label: 'Stripes', size: 16,
		draw(ctx, S, a, b) {
			for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
				ctx.fillStyle = hex(((x + y) % 16) < 6 ? b : a);
				pix(ctx, x, y);
			}
		},
	},
	bands: {
		label: 'Bands', size: 16,
		draw(ctx, S, a, b) { ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S); ctx.fillStyle = hex(b); ctx.fillRect(0, 0, S, 5); },
	},
	checker: {
		label: 'Checker', size: 16,
		draw(ctx, S, a, b) {
			for (let y = 0; y < 2; y++) for (let x = 0; x < 2; x++) { ctx.fillStyle = hex((x + y) % 2 ? b : a); ctx.fillRect(x * 8, y * 8, 8, 8); }
		},
	},
	dots: {
		label: 'Dots', size: 16,
		draw(ctx, S, a, b) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			ctx.fillStyle = hex(b); ctx.fillRect(3, 3, 3, 3); ctx.fillRect(11, 11, 3, 3);
		},
	},
	scales: {
		label: 'Scales', size: 16,
		draw(ctx, S, a, b) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			ctx.fillStyle = hex(b);
			for (const [cx, cy] of [[0, 0], [8, 8], [16, 0], [0, 16], [16, 16]])
				for (let x = -8; x <= 8; x++) {
					const y = Math.round(Math.sqrt(Math.max(0, 64 - x * x)) * 0.8);
					pix(ctx, cx + x, cy + y);
				}
		},
	},
	chain: {
		label: 'Chainmail', size: 8,
		draw(ctx, S, a, b) {
			ctx.fillStyle = hex(b); ctx.fillRect(0, 0, S, S);
			ctx.fillStyle = hex(a);
			ctx.fillRect(1, 0, 2, 3); ctx.fillRect(0, 1, 4, 1); ctx.fillRect(5, 4, 2, 3); ctx.fillRect(4, 5, 4, 1);
			ctx.fillStyle = hex(mix(a, new THREE.Color(1, 1, 1), 0.35)); pix(ctx, 1, 0); pix(ctx, 5, 4);
		},
	},
	plates: {
		label: 'Plates', size: 32,
		draw(ctx, S, a, b) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			ctx.fillStyle = hex(b); ctx.fillRect(0, 0, S, 1); ctx.fillRect(0, 0, 1, S);
			ctx.fillStyle = hex(mix(a, new THREE.Color(1, 1, 1), 0.18)); ctx.fillRect(1, 1, S - 1, 1);
			ctx.fillStyle = hex(b); for (const [x, y] of [[3, 3], [28, 3], [3, 28], [28, 28]]) ctx.fillRect(x, y, 2, 2);
		},
	},
	wood: {
		label: 'Planks', size: 32,
		draw(ctx, S, a, b, r) {
			for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
				const g = Math.sin(y * 0.9 + Math.sin(x * 0.2) * 1.5) * 0.5 + 0.5;
				ctx.fillStyle = hex(mix(a, b, g * 0.35 + r() * 0.08));
				pix(ctx, x, y);
			}
			ctx.fillStyle = hex(b);
			for (const y of [0, 8, 16, 24]) ctx.fillRect(0, y, S, 1);
			for (const [x, y] of [[10, 1], [26, 9], [5, 17], [20, 25]]) ctx.fillRect(x, y, 1, 7);
		},
	},
	brick: {
		label: 'Brick', size: 32,
		draw(ctx, S, a, b, r) {
			ctx.fillStyle = hex(b); ctx.fillRect(0, 0, S, S);
			for (let row = 0; row < 4; row++) {
				const off = row % 2 ? 8 : 0;
				for (let col = -1; col < 2; col++) {
					ctx.fillStyle = hex(mix(a, b, r() * 0.2));
					ctx.fillRect(col * 16 + off + 1, row * 8 + 1, 15, 7);
				}
			}
		},
	},
	stone: {
		label: 'Stone', size: 32,
		draw(ctx, S, a, b, r) {
			ctx.fillStyle = hex(b); ctx.fillRect(0, 0, S, S);
			const cells = [[0, 0, 13, 10], [14, 0, 18, 12], [0, 11, 9, 11], [10, 13, 12, 9], [23, 13, 9, 10], [0, 23, 15, 9], [16, 23, 16, 9]];
			for (const [x, y, w, h] of cells) { ctx.fillStyle = hex(mix(a, b, r() * 0.25)); ctx.fillRect(x + 1, y + 1, w - 1, h - 1); }
		},
	},
	hex: {
		label: 'Hex mesh', size: 16,
		draw(ctx, S, a, b) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			ctx.fillStyle = hex(b);
			const pts = [[4, 0], [12, 0], [0, 4], [8, 8], [16, 4], [4, 12], [12, 12]];
			for (const [x, y] of pts) { ctx.fillRect(x - 2, y - 1, 4, 1); ctx.fillRect(x - 3, y, 1, 2); ctx.fillRect(x + 2, y, 1, 2); ctx.fillRect(x - 2, y + 2, 4, 1); }
		},
	},
	grunge: {
		label: 'Grime', size: 32,
		draw(ctx, S, a, b, r) {
			ctx.fillStyle = hex(a); ctx.fillRect(0, 0, S, S);
			for (let i = 0; i < 90; i++) {
				ctx.fillStyle = hex(mix(a, b, 0.3 + r() * 0.5));
				pix(ctx, Math.floor(r() * S), Math.floor(r() * S), 1 + Math.floor(r() * 2), 1);
			}
			ctx.fillStyle = hex(mix(a, b, 0.45));
			for (let i = 0; i < 4; i++) { const x = Math.floor(r() * S); ctx.fillRect(x, 0, 1, 6 + Math.floor(r() * 18)); }
		},
	},
};

const _cache = new Map();

// THREE.Color inputs. Returns a shared CanvasTexture.
export function patternTexture(name, main, ink) {
	const key = `${name}|${main.getHexString()}|${ink.getHexString()}`;
	if (_cache.has(key)) return _cache.get(key);
	const P = PATTERNS[name] || PATTERNS.solid;
	const S = P.size;
	const cv = document.createElement('canvas');
	cv.width = cv.height = S;
	const ctx = cv.getContext('2d');
	P.draw(ctx, S, main, ink, rng(hashStr(key)));
	const tex = new THREE.CanvasTexture(cv);
	tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
	tex.magFilter = THREE.NearestFilter;
	tex.minFilter = THREE.NearestFilter;
	tex.generateMipmaps = false;
	tex.colorSpace = THREE.SRGBColorSpace;
	tex.name = key;
	// A pattern drawn at 8 px still means "one tile = pattern size".
	_cache.set(key, tex);
	return tex;
}

// Swatch image for the pattern picker.
export function patternSwatch(name, main, ink, px = 28) {
	const t = patternTexture(name, main, ink);
	const cv = document.createElement('canvas');
	cv.width = cv.height = px;
	const ctx = cv.getContext('2d');
	ctx.imageSmoothingEnabled = false;
	const S = t.image.width;
	const reps = S <= 16 ? 2 : 1;
	const step = px / reps;
	for (let i = 0; i < reps; i++) for (let j = 0; j < reps; j++) ctx.drawImage(t.image, i * step, j * step, step, step);
	return cv.toDataURL();
}
