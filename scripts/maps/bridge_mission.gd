extends RefCounted
## Day mission: OPERATION BIFROST.
##
## A river crosses the map east to west. You start on the south bank; a 56 m
## road bridge runs north over the water, littered with abandoned cars, a
## bus and box trucks, the only cover on the crossing. The enemy holds the
## north side: a sandbag line across the far end of the bridge, a checkpoint
## at the bridge foot, and a depot behind it with the APC.
##
## Coordinates: x across (bridge deck x -7.6..7.6, road x -5..5), z along the
## road (start z = +44; river z -28..28; north bank z < -28). The water is
## a gap in the ground; invisible "water" boxes stop anyone walking off the
## bank (and the parapets stop anyone stepping off the bridge).

const NAME := "OPERATION BIFROST"
const NIGHT := false
const GROUND := "bridge"
const RIVER_Z := 28.0          # river runs between z = -28 and z = +28
const DECK_X := 7.6            # bridge deck half-width
const START := Vector3(0, 0, 44)
const AT_TEAM := Vector3(-22, 0, 36)
const OBJECTIVE := "OBJECTIVE: FORCE THE BRIDGE AND TAKE THE NORTH BANK"
const COMPLETE := "NORTH BANK SECURED  -  MISSION COMPLETE  -  R TO REPLAY"

const BOXES := [
	# ---- the river: no walking on water (no mesh, no cover)
	[Vector3(29.0, 0, 0), Vector3(42.8, 0.6, 56.0), 0.0, "water"],
	[Vector3(-29.0, 0, 0), Vector3(42.8, 0.6, 56.0), 0.0, "water"],
	# ---- bridge parapets
	[Vector3(7.4, 0, 0), Vector3(0.4, 1.0, 56.0), 0.0, "barrier"],
	[Vector3(-7.4, 0, 0), Vector3(0.4, 1.0, 56.0), 0.0, "barrier"],

	# ---- south bank: the start, a few buildings at the edges
	[Vector3(-36, 0, 46), Vector3(14, 7, 8), 0.0, "building"],
	[Vector3(34, 0, 45), Vector3(16, 9, 10), 0.0, "building"],
	[Vector3(-4, 0, 36), Vector3(4.4, 1.3, 1.9), 0.4, "car"],
	[Vector3(5.5, 0, 32.5), Vector3(3.0, 1.0, 0.6), 0.1, "barrier"],
	[Vector3(-13, 0, 33), Vector3(3.0, 1.1, 1.0), 0.2, "crate"],
	[Vector3(15, 0, 37), Vector3(4.4, 1.3, 1.9), 2.6, "car"],

	# ---- on the bridge: abandoned vehicles, south to north
	[Vector3(-3.0, 0, 23), Vector3(4.4, 1.3, 1.9), 1.85, "car"],
	[Vector3(2.6, 0, 16), Vector3(11.0, 3.0, 2.6), 1.48, "bus"],
	[Vector3(-4.4, 0, 9), Vector3(4.4, 1.3, 1.9), 1.2, "car"],
	[Vector3(-0.5, 0, 3), Vector3(4.4, 1.3, 1.9), 2.45, "car"],
	[Vector3(3.6, 0, -2), Vector3(7.0, 3.2, 2.5), 1.75, "truck"],
	[Vector3(-3.6, 0, -8), Vector3(7.0, 3.2, 2.5), 0.85, "truck"],
	[Vector3(4.6, 0, -11), Vector3(4.4, 1.3, 1.9), 1.6, "car"],
	[Vector3(0.8, 0, -15.5), Vector3(4.4, 1.3, 1.9), 0.25, "car"],

	# ---- enemy line across the north end of the bridge
	[Vector3(-3.6, 0, -21), Vector3(4.6, 1.0, 0.8), 0.0, "sandbag"],
	[Vector3(4.2, 0, -21.3), Vector3(3.8, 1.0, 0.8), 0.0, "sandbag"],
	[Vector3(0.6, 0, -24.5), Vector3(1.4, 1.1, 1.4), 0.3, "crate"],

	# ---- north bank: checkpoint at the bridge foot
	[Vector3(9.5, 0, -33), Vector3(3.0, 3.0, 3.0), 0.0, "building"],
	[Vector3(-2.5, 0, -32), Vector3(3.0, 1.0, 0.6), 0.0, "barrier"],
	[Vector3(3.0, 0, -33.5), Vector3(3.0, 1.0, 0.6), 0.1, "barrier"],
	[Vector3(-10, 0, -31.5), Vector3(4.0, 1.0, 0.8), -0.2, "sandbag"],
	[Vector3(-14, 0, -36), Vector3(4.4, 1.3, 1.9), 0.4, "car"],
	# ---- north bank: the depot (warehouses, containers)
	[Vector3(-26, 0, -44), Vector3(16, 8, 10), 0.0, "building"],
	[Vector3(27, 0, -43), Vector3(14, 7, 12), 0.0, "building"],
	[Vector3(-12, 0, -44.5), Vector3(6.0, 2.6, 2.4), 0.0, "tall"],
	[Vector3(13, 0, -41), Vector3(2.4, 2.6, 6.0), 0.0, "tall"],
	[Vector3(-5, 0, -42), Vector3(2.5, 1.1, 1.0), 0.3, "crate"],
	[Vector3(5.5, 0, -45), Vector3(1.2, 1.1, 1.2), 0.0, "crate"],
	[Vector3(0, 0, -48.5), Vector3(40, 2.6, 0.6), 0.0, "cwall"],
]

const AREAS := [
	{"name": "BRIDGEHEAD", "center": Vector3(0, 0, -22), "radius": 9.0,
		"men": [Vector3(-3.5, 0, -22.5), Vector3(4.0, 0, -22.8), Vector3(0.5, 0, -26)]},
	{"name": "CHECKPOINT", "center": Vector3(0, 0, -34), "radius": 11.0,
		"men": [Vector3(-2.5, 0, -33.5), Vector3(3.0, 0, -35), Vector3(-10, 0, -33.2)]},
	{"name": "DEPOT", "center": Vector3(0, 0, -44), "radius": 14.0,
		"men": [Vector3(-12, 0, -42.5), Vector3(13, 0, -44.5), Vector3(-5, 0, -43.6), Vector3(5.5, 0, -46.5)],
		"apc": [Vector3(-8, 0, -39), Vector3(8, 0, -39)]},
]


## The river: water below, concrete embankments, the bridge deck slab and
## its piers. Plain scenery (no collision; the "water" boxes do the work).
static func build_extras(main: Node3D) -> void:
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(400, RIVER_Z * 2.0)
	water.mesh = wm
	var ws := Shader.new()
	ws.code = WATER_SHADER
	var wmat := ShaderMaterial.new()
	wmat.shader = ws
	water.material_override = wmat
	water.position = Vector3(0, -4.0, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(water)

	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.52, 0.51, 0.48)
	concrete.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.36, 0.36, 0.34)
	dark.roughness = 0.95
	for side in [-1.0, 1.0]:
		_box(main, Vector3(0, -2.5, side * (RIVER_Z + 0.5)), Vector3(400, 5.0, 1.0), concrete)     # embankment walls
	_box(main, Vector3(0, -0.8, 0), Vector3(DECK_X * 2.0, 1.5, RIVER_Z * 2.0), dark)            # deck slab (top just under the road)
	for z in [-10.0, 10.0]:
		_box(main, Vector3(0, -2.8, z), Vector3(10.0, 2.6, 2.2), concrete)                       # piers
	# lamp posts along the parapets (off: it's daytime)
	var post := StandardMaterial3D.new()
	post.albedo_color = Color(0.2, 0.21, 0.22)
	post.metallic = 0.6
	post.roughness = 0.5
	for z in [-20.0, -6.0, 8.0, 22.0]:
		for side in [-1.0, 1.0]:
			_box(main, Vector3(side * 7.4, 3.0, z), Vector3(0.14, 4.0, 0.14), post)
			_box(main, Vector3(side * 6.8, 4.95, z), Vector3(1.3, 0.1, 0.25), post)


static func _box(main: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	main.add_child(mi)


const WATER_SHADER := """
shader_type spatial;
// Slow river: grey-green, ripples moving downstream, sky glints.
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
// Colours here are picked as screen (sRGB) colours, which is how the
// browser's compatibility renderer uses them; the desktop renderer lights in
// linear space, so convert there to keep the same look.
vec3 to_lin(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#endif
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * vec2(0.35, 0.9) + vec2(TIME * 0.6, 0.0);
	float a = noise(p) - noise(p + vec2(0.37, 0.0));
	float b = noise(p) - noise(p + vec2(0.0, 0.37));
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(a * 0.6, 0.0, b * 0.6, 0.0)).xyz);
	ALBEDO = to_lin(mix(vec3(0.07, 0.12, 0.12), vec3(0.12, 0.17, 0.16), noise(wpos.xz * 0.1 + TIME * 0.05)));
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
"""
