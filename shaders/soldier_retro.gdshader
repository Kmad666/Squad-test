// RETRO soldier: late-90s console look. Flat vertex colours, per-vertex
// lighting, and vertices snapped to a coarse screen grid so the model
// "wobbles" slightly as it moves, like hardware without sub-pixel precision.
// Vertex alpha is the material ID (see scripts/model_kit.gd); only glass
// (mask lenses) is special: it glows faintly at night.
shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_disabled, cull_back;

uniform vec4 tint : source_color = vec4(1.0);
uniform bool ir_on = false;        // thermal sight on (I): bodies glow hot inside ir_rect
uniform vec4 ir_rect = vec4(0.0);  // the reticle on screen, x0 y0 x1 y1 in screen UV
uniform float night = 0.0;
uniform float snap_px = 3.0;      // grid size in screen pixels (0 = off)

varying float mid;

void vertex() {
	mid = COLOR.a;
	if (snap_px > 0.0) {
		vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
		vec2 grid = VIEWPORT_SIZE / (2.0 * snap_px);
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = floor(ndc.xy * grid + 0.5) / grid;
		POSITION = vec4(ndc * clip.w, clip.w);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb;
	ROUGHNESS = 1.0;
	if (mid > 0.17 && mid < 0.32) {
		ALBEDO = (COLOR.rgb * 2.5 + 0.03) * tint.rgb;      // bold, readable lenses
		EMISSION = COLOR.rgb * (0.9 + night * 2.2) * tint.rgb;   // goggles glow, brighter at night
	}
	if (night > 0.0) {
		RIM = 0.4 * night;
		RIM_TINT = 0.5;
	}

	// Thermal sight: inside the reticle the body shows as heat, a marker
	// colour (yellow, no blue) the post effect turns white-hot. Face and
	// hands run hottest, the rifle and mask lenses cool, a corpse cools off.
	if (ir_on && SCREEN_UV.x > ir_rect.x && SCREEN_UV.x < ir_rect.z && SCREEN_UV.y > ir_rect.y && SCREEN_UV.y < ir_rect.w) {
		float heat = 0.8;
		if (mid < 0.17) heat = 1.0;                      // skin
		else if (mid < 0.32) heat = 0.25;                // lenses
		else if (mid < 0.47) heat = 0.3;                 // weapon metal
		heat *= 0.75 + 0.25 * abs(dot(normalize(NORMAL), vec3(0.0, 0.0, 1.0)));
		heat *= clamp(max(tint.r, tint.g), 0.0, 1.0);    // dead: cooling
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		RIM = 0.0;
		EMISSION = vec3(1.0, 1.0, 0.0) * heat * 1.15;   // under the bloom threshold: no glow past the reticle
	}
}
