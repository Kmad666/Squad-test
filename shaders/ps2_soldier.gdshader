// PS2-era soldier: Gouraud (per-vertex) lighting and "painted texture"
// shading done procedurally in model space. Vertex alpha = material ID
// (scripts/model_kit.gd): 1.0 camo trousers, 0.85 fabric (jacket, knit
// balaclava above y 1.55), 0.7 webbing, 0.55 rubber/leather/polymer,
// 0.4 metal, 0.25 eyes, 0.1 skin.
shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_schlick_ggx, cull_back;

uniform vec4 tint : source_color = vec4(1.0);

varying vec3 lpos;
varying float mid;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lpos = VERTEX;
	mid = COLOR.a;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float rough = 0.9;
	float spec = 0.2;
	// baked-in occlusion like a painted texture: darker toward the ground and
	// in a soft noise "fold" pattern
	float ao = mix(0.72, 1.0, smoothstep(0.0, 0.5, lpos.y));
	float folds = vnoise(lpos * vec3(9.0, 26.0, 9.0));
	if (mid > 0.93) {
		// urban camo trousers: soft-edged blotches (a bilinear-filtered 256px look)
		float b1 = vnoise(lpos * 14.0) * 0.6 + vnoise(lpos * 31.0) * 0.4;
		float b2 = vnoise(lpos * 18.0 + vec3(4.0, 1.0, 7.0));
		c = mix(c, c * 0.68, smoothstep(0.52, 0.62, b1));
		c = mix(c, c * 1.2, smoothstep(0.6, 0.7, b2) * (1.0 - smoothstep(0.52, 0.62, b1)));
		c *= mix(0.78, 1.08, folds);            // puffy fabric folds
	} else if (mid > 0.78) {
		if (lpos.y > 1.55) {
			// knit balaclava: vertical ribbing
			float rib = 0.5 + 0.5 * sin(atan(lpos.x, lpos.z) * 70.0);
			c *= mix(0.8, 1.15, rib);
		}
		c *= mix(0.85, 1.07, folds);
		rough = 0.95;
	} else if (mid > 0.62) {
		c *= mix(0.9, 1.06, vnoise(lpos * 60.0));
		rough = 0.8;
	} else if (mid > 0.47) {
		rough = 0.5;
		spec = 0.4;
	} else if (mid > 0.32) {
		rough = 0.35;
		spec = 0.6;
		c *= mix(0.85, 1.2, vnoise(lpos * 40.0));   // worn edges
	} else if (mid > 0.17) {
		rough = 0.15;
		spec = 0.7;
		ao = 1.0;
	} else {
		rough = 0.7;
		spec = 0.25;
		ao = 1.0;
	}
	ALBEDO = c * ao * tint.rgb;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
