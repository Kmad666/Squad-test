extends CanvasLayer
## Full-screen post effect drawn over the 3D view (under the HUD).
## Always: vignette + analogue film grain.
## While firing (heat 0..1): radial zoom blur from the screen centre,
## chromatic split, a warm muzzle-flash wash and a tighter vignette.

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

void fragment() {
	vec2 uv = SCREEN_UV;
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
	col += vec3(1.0, 0.72, 0.4) * flash * 0.14;
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(grey), danger * 0.55);
	col += vec3(0.7, 0.02, 0.0) * hurt * smoothstep(0.3, 0.75, d);
	float vig = smoothstep(0.9, 0.22, d + heat * 0.14 + danger * 0.18);
	col *= mix(0.45, 1.0, vig);
	if (!cheap) {
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


func set_fx(heat: float, flash: float, danger := 0.0, hurt := 0.0) -> void:
	_mat.set_shader_parameter("heat", heat)
	_mat.set_shader_parameter("flash", flash)
	_mat.set_shader_parameter("danger", danger)
	_mat.set_shader_parameter("hurt", hurt)
