extends CanvasLayer
## Full-screen post effect drawn over the 3D view (under the HUD).
## Always: vignette + analogue film grain.
## While firing (heat 0..1): radial zoom blur from the screen centre,
## chromatic split, a warm muzzle-flash wash and a tighter vignette.
## Night vision (N): green phosphor, amplified darks, heavy grain, flicker,
## scan lines and a round eyepiece edge.
## Thermal (I), inside the reticle only: white-hot. Soldiers' shaders mark
## body heat in a yellow no-blue colour; that (and lamps, flashes, fire)
## shows white, everything else cold grey.

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 0
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float heat = 0.0;
uniform float flash = 0.0;
uniform float danger = 0.0;   // squad suppression: drains colour, closes in
uniform float hurt = 0.0;     // red edge flash when a soldier is hit
uniform bool cheap = false;   // LOW graphics: skip the 18-sample blur and the grain
uniform bool retro = false;   // RETRO graphics: chunky pixels, 15-bit colour, ordered dither
uniform bool nvg = false;     // night vision goggles
uniform bool ir = false;      // thermal sight inside ir_rect
uniform vec4 ir_rect = vec4(0.0);   // x0 y0 x1 y1, screen UV

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 4x4 Bayer matrix, 0..1
float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 cell = vec2(0.0);
	if (retro) {
		// sample the 3D view in chunky 3x3 screen-pixel blocks
		vec2 px = 1.0 / SCREEN_PIXEL_SIZE;
		cell = floor(uv * px / 3.0);
		uv = (cell * 3.0 + 1.5) / px;
	}
	vec2 c = uv - 0.5;
	float d = length(c);
	vec3 col;
	if (heat > 0.02 && !cheap) {
		float amt = heat * 0.045;
		float split = heat * 0.006;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float s = 1.0 - amt * float(i) / 5.0;
			acc.r += texture(screen_tex, 0.5 + c * (s + split)).r;
			acc.g += texture(screen_tex, 0.5 + c * s).g;
			acc.b += texture(screen_tex, 0.5 + c * (s - split)).b;
		}
		col = acc / 6.0;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	vec3 raw = col;
	if (nvg) {
		float l = dot(col, vec3(0.3, 0.59, 0.11));
		l = 1.0 - exp(-l * 7.0);                         // lift the dark, crush the bright
		float t = floor(TIME * 30.0);
		float flick = 0.92 + 0.05 * sin(TIME * 53.0) + 0.06 * (hash(vec2(t, 3.1)) - 0.5);
		l = l * flick + (hash(uv * 911.0 + t * 0.37) - 0.5) * 0.24;
		l *= 0.93 + 0.07 * sin(FRAGCOORD.y * 2.2);         // scan lines
		col = vec3(0.13, 1.0, 0.3) * l + vec3(0.7, 1.0, 0.7) * smoothstep(0.8, 1.0, l) * 0.35;
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		col *= mix(0.2, 1.0, smoothstep(0.62, 0.44, length((uv - 0.5) * vec2(aspect, 1.0)) * 0.9));
	}
	if (ir && uv.x > ir_rect.x && uv.x < ir_rect.z && uv.y > ir_rect.y && uv.y < ir_rect.w) {
		float l = dot(raw, vec3(0.3, 0.59, 0.11));
		float warm = min(raw.r, raw.g);
		float hot = smoothstep(0.12, 0.35, warm - raw.b) * smoothstep(0.3, 0.6, warm);
		float t = clamp(l * 0.55, 0.0, 0.4);
		t = max(t, hot * (0.75 + 0.25 * max(raw.r, raw.g)));
		col = mix(vec3(0.03, 0.035, 0.05), vec3(1.0, 0.98, 0.93), t);
		col += (hash(uv * 733.0 + TIME) - 0.5) * 0.05;
	}
	col += vec3(1.0, 0.72, 0.4) * flash * 0.14;
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(grey), danger * 0.55);
	col += vec3(0.7, 0.02, 0.0) * hurt * smoothstep(0.3, 0.75, d);
	float vig = smoothstep(0.9, 0.22, d + heat * 0.14 + danger * 0.18);
	col *= mix(0.45, 1.0, vig);
	if (retro) {
		// 5 bits per channel with ordered dithering, like the old consoles
		col = floor(col * 31.0 + bayer(cell)) / 31.0;
	} else if (!cheap) {
		float n = fract(sin(dot(uv * (TIME + 1.7), vec2(12.9898, 78.233))) * 43758.5453);
		col += (n - 0.5) * 0.04;
	}
	COLOR = vec4(col, 1.0);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect.material = _mat
	add_child(_rect)


func set_cheap(on: bool) -> void:
	_mat.set_shader_parameter("cheap", on)


func set_retro(on: bool) -> void:
	_mat.set_shader_parameter("retro", on)


func set_vision(night_vision: bool, thermal: bool, rect_uv: Vector4) -> void:
	_mat.set_shader_parameter("nvg", night_vision)
	_mat.set_shader_parameter("ir", thermal)
	_mat.set_shader_parameter("ir_rect", rect_uv)


func set_fx(heat: float, flash: float, danger := 0.0, hurt := 0.0) -> void:
	_mat.set_shader_parameter("heat", heat)
	_mat.set_shader_parameter("flash", flash)
	_mat.set_shader_parameter("danger", danger)
	_mat.set_shader_parameter("hurt", hurt)
