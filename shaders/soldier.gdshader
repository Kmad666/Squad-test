// Soldier surfaces. The mesh's vertex colour gives the base colour; its
// alpha is a material ID (see scripts/model_kit.gd):
//   1.00 camo fatigues   0.85 plain fabric   0.70 nylon webbing
//   0.55 rubber          0.40 weapon metal   0.25 glass     0.10 skin
// Everything is procedural (no textures): camo blotches and fabric grain
// come from 3D noise in the part's own space, and a cheap derivative bump
// gives cloth and webbing some surface. `detail` 0 skips the bump/camo
// noise for the low graphics setting.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(1.0);
uniform bool ir_on = false;        // thermal sight on (I): bodies glow hot inside ir_rect
uniform vec4 ir_rect = vec4(0.0);  // the reticle on screen, x0 y0 x1 y1 in screen UV
uniform float detail = 1.0;
uniform float night = 0.0;
uniform vec3 camo_a : source_color = vec3(0.78);   // camo blotch multipliers
uniform vec3 camo_b : source_color = vec3(1.22);
uniform float camo_scale = 16.0;

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
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lpos = VERTEX;
	mid = COLOR.a;
}

// Perturb the view-space normal by a height field h (surface gradient bump).
vec3 bump(vec3 n, vec3 vpos, float h, float strength) {
	vec3 dpdx = dFdx(vpos);
	vec3 dpdy = dFdy(vpos);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad * strength);
}

void fragment() {
	vec3 base = COLOR.rgb;
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.35;
	float h = 0.0;
	float bstr = 0.0;
	vec3 n = NORMAL;
	float glow = 0.0;
	// fade fine detail with distance so it never shimmers
	float dist = length(VERTEX);
	float fine = detail * clamp(1.0 - (dist - 6.0) / 14.0, 0.0, 1.0);

	if (mid > 0.93) {
		// camo fatigues: three-tone blotches + fabric grain + folds
		if (detail > 0.0) {
			float b1 = vnoise(lpos * camo_scale) * 0.65 + vnoise(lpos * camo_scale * 2.3) * 0.35;
			float b2 = vnoise(lpos * camo_scale * 1.3 + vec3(7.1, 3.3, 1.7));
			vec3 m = vec3(1.0);
			m = mix(m, camo_a, smoothstep(0.56, 0.6, b1));
			m = mix(m, camo_b, smoothstep(0.62, 0.66, b2) * (1.0 - smoothstep(0.56, 0.6, b1)));
			base *= m;
		}
		rough = 0.92;
		h = vnoise(lpos * 90.0) * 0.5 + vnoise(lpos * 14.0) * 1.5;
		bstr = 0.004;
	} else if (mid > 0.78) {
		// plain fabric
		rough = 0.9;
		h = vnoise(lpos * 80.0) * 0.6 + vnoise(lpos * 12.0) * 0.8;
		bstr = 0.004;
	} else if (mid > 0.62) {
		// nylon webbing: fine horizontal weave
		rough = 0.78;
		spec = 0.4;
		h = sin(lpos.y * 520.0) * 0.25 + vnoise(lpos * 60.0) * 0.5;
		bstr = 0.0025;
		base *= 0.96 + 0.08 * vnoise(lpos * 25.0);
	} else if (mid > 0.47) {
		// rubber: soft sheen
		rough = 0.55;
		spec = 0.45;
		h = vnoise(lpos * 120.0) * 0.3;
		bstr = 0.002;
	} else if (mid > 0.32) {
		// weapon metal / polymer: worn edges catch a little light
		rough = 0.42;
		metal = 0.55;
		spec = 0.5;
		h = vnoise(lpos * 200.0) * 0.2;
		bstr = 0.0015;
	} else if (mid > 0.17) {
		// glass: dark, glossy, tinted reflection
		rough = 0.06;
		metal = 0.5;
		spec = 0.9;
		glow = 1.0;
		base = base * 0.6 + vec3(0.02, 0.05, 0.05);
	} else {
		rough = 0.6;
		spec = 0.3;
	}

	if (fine > 0.0 && bstr > 0.0) {
		n = bump(n, VERTEX, h, bstr * fine);
	}
	ALBEDO = base * tint.rgb;
	ROUGHNESS = mix(rough, rough * 0.7, night);    // wet / glossier at night
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL = n;
	if (night > 0.0) {
		RIM = 0.5 * night;
		RIM_TINT = 0.6;
		// mask lenses glow faintly in the dark (friendly green, enemy red)
		EMISSION = COLOR.rgb * glow * night * 3.0 * tint.rgb;
	}

	// Thermal sight: inside the reticle the body shows as heat, a marker
	// colour (yellow, no blue) the post effect turns white-hot. Face and
	// hands run hottest, the rifle and mask lenses cool, a corpse cools off.
	if (ir_on && SCREEN_UV.x > ir_rect.x && SCREEN_UV.x < ir_rect.z && SCREEN_UV.y > ir_rect.y && SCREEN_UV.y < ir_rect.w) {
		float heat = 0.8;
		if (mid < 0.17) heat = 1.0;                      // skin
		else if (mid < 0.32) heat = 0.25;                // lenses
		else if (mid < 0.47) heat = 0.3;                 // weapon metal
		heat *= 0.75 + 0.25 * abs(dot(normalize(n), vec3(0.0, 0.0, 1.0)));
		heat *= clamp(max(tint.r, tint.g), 0.0, 1.0);    // dead: cooling
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		METALLIC = 0.0;
		RIM = 0.0;
		EMISSION = vec3(1.0, 1.0, 0.0) * heat * 1.15;   // under the bloom threshold: no glow past the reticle
	}
}
