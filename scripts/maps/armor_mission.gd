extends RefCounted
## Day mission: OPERATION SLEIPNIR (Odin's eight-legged horse, for an
## eight-wheeled LAV). Combined arms on open farmland, 220 m across: the
## biggest map, with room for the LAV to drive.
##
## You start in the south with a LAV-25. An asphalt road winds north
## (x = 10 sin(0.018 z)) to a crossroads village at z = -70; dirt tracks run
## east to a farm (z = -30) and west to a hedgerow treeline (z = -8).
## The enemy holds a checkpoint on the road, the treeline, the farm and the
## village (with an APC patrolling the crossroad). The treeline, farm and
## village have RPG gunners ("rpg": indices into "men") who hunt the LAV:
## the infantry's job is to find and kill them before they get a shot off.

const NAME := "OPERATION SLEIPNIR"
const NIGHT := false
const GROUND := "rural"
const HALF := 110.0
const LAV := true
const START := Vector3(10, 0, 98)
const LAV_START := Vector3(10, 0, 91)
const LAV_YAW := PI                       # facing north (-z)
const AT_TEAM := Vector3(27, 0, 70)       # rocket team at the ruined barn
const OBJECTIVE := "OPERATION SLEIPNIR  -  ADVANCE BEHIND THE LAV (Z: LAV WITH US / OVERWATCH)  -  CLEAR ALL FOUR POSITIONS"
const COMPLETE := "FARMLAND SECURED  -  MISSION COMPLETE  -  R TO REPLAY"

const BOXES := [
	# ---- the start: a wreck on the shoulder, hay, the ruined barn (rocket team)
	[Vector3(17, 0, 78), Vector3(4.4, 1.3, 1.9), 0.3, "car"],
	[Vector3(-12, 0, 76), Vector3(1.6, 1.3, 1.6), 0.0, "hay"],
	[Vector3(-9.8, 0, 74.5), Vector3(1.6, 1.3, 1.6), 0.4, "hay"],
	[Vector3(-14, 0, 73), Vector3(1.6, 1.3, 1.6), 0.8, "hay"],
	[Vector3(22, 0, 72), Vector3(0.5, 1.1, 7.0), 0.0, "wall"],
	[Vector3(27, 0, 76), Vector3(9.0, 1.1, 0.5), 0.0, "wall"],
	[Vector3(31, 0, 68), Vector3(2.4, 2.6, 6.0), 0.1, "tall"],
	[Vector3(-30, 0, 62), Vector3(0.7, 6.0, 0.7), 0.0, "tree"],
	[Vector3(-35, 0, 58), Vector3(0.8, 7.0, 0.8), 0.0, "tree"],
	[Vector3(-27, 0, 55), Vector3(0.6, 5.5, 0.6), 0.0, "tree"],
	[Vector3(34, 0, 52), Vector3(2.4, 1.4, 1.8), 0.5, "rock"],

	# ---- field boundaries (hedgerows with gaps wide enough for the LAV)
	[Vector3(-55, 0, 48), Vector3(9.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(-40, 0, 48), Vector3(9.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(-25, 0, 48), Vector3(8.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(26, 0, 44), Vector3(9.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(41, 0, 44), Vector3(9.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(56, 0, 44), Vector3(8.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(-22, 0, 30), Vector3(1.6, 1.3, 1.6), 0.2, "hay"],
	[Vector3(-19.8, 0, 31.4), Vector3(1.6, 1.3, 1.6), 0.9, "hay"],
	[Vector3(22, 0, 26), Vector3(2.2, 1.3, 1.6), 1.1, "rock"],
	[Vector3(42, 0, 30), Vector3(0.8, 7.0, 0.8), 0.0, "tree"],
	[Vector3(46, 0, 34), Vector3(0.7, 6.0, 0.7), 0.0, "tree"],
	[Vector3(-18, 0, 18), Vector3(0.8, 6.5, 0.8), 0.0, "tree"],
	[Vector3(-6, 0, 30), Vector3(4.4, 1.3, 1.9), 1.4, "car"],
	[Vector3(14, 0, 36), Vector3(2.0, 1.2, 1.5), 0.3, "rock"],

	# ---- OUTPOST: a checkpoint across the road (z ~ 8)
	[Vector3(-3, 0, 8), Vector3(4.0, 1.0, 0.8), 0.0, "sandbag"],
	[Vector3(6.5, 0, 8.5), Vector3(3.6, 1.0, 0.8), 0.0, "sandbag"],
	[Vector3(-9, 0, 1), Vector3(2.4, 2.6, 6.0), 0.0, "tall"],
	[Vector3(4.5, 0, 2), Vector3(1.4, 1.1, 1.4), 0.3, "crate"],
	[Vector3(10, 0, 14), Vector3(4.4, 1.3, 1.9), 1.9, "car"],

	# ---- TREELINE (west): hedgerow along the track, trees behind
	[Vector3(-62, 0, -12), Vector3(10.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(-48, 0, -12), Vector3(10.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(-34, 0, -12), Vector3(9.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(-60, 0, -19), Vector3(0.8, 7.0, 0.8), 0.0, "tree"],
	[Vector3(-52, 0, -21), Vector3(0.7, 6.0, 0.7), 0.0, "tree"],
	[Vector3(-44, 0, -18), Vector3(0.9, 7.5, 0.9), 0.0, "tree"],
	[Vector3(-36, 0, -20), Vector3(0.7, 6.0, 0.7), 0.0, "tree"],
	[Vector3(-68, 0, -22), Vector3(0.8, 6.5, 0.8), 0.0, "tree"],

	# ---- FARM (east): farmhouse, barn, yard walls, hay, a truck
	[Vector3(58, 0, -44), Vector3(12.0, 7.0, 9.0), 0.0, "building"],
	[Vector3(78, 0, -32), Vector3(10.0, 8.0, 16.0), 0.0, "building"],
	[Vector3(49, 0, -31), Vector3(0.5, 1.1, 10.0), 0.0, "wall"],
	[Vector3(55, 0, -24), Vector3(7.0, 1.1, 0.5), 0.0, "wall"],
	[Vector3(64, 0, -26), Vector3(1.6, 1.3, 1.6), 0.0, "hay"],
	[Vector3(66.2, 0, -24.6), Vector3(1.6, 1.3, 1.6), 0.6, "hay"],
	[Vector3(67, 0, -38), Vector3(7.0, 3.2, 2.5), 0.4, "truck"],
	[Vector3(60, 0, -33), Vector3(1.4, 1.1, 1.4), 0.2, "crate"],

	# ---- CROSSROADS village (z ~ -70, road x ~ -9.5)
	[Vector3(-28, 0, -56), Vector3(12.0, 7.0, 10.0), 0.0, "building"],
	[Vector3(9, 0, -55), Vector3(10.0, 6.0, 9.0), 0.0, "building"],
	[Vector3(-30, 0, -87), Vector3(14.0, 8.0, 10.0), 0.0, "building"],
	[Vector3(8, 0, -89), Vector3(12.0, 9.0, 12.0), 0.0, "building"],
	[Vector3(34, 0, -86), Vector3(10.0, 6.0, 8.0), 0.0, "building"],
	[Vector3(-14, 0, -63), Vector3(3.0, 1.0, 0.8), 0.0, "sandbag"],
	[Vector3(-4, 0, -63), Vector3(3.0, 1.0, 0.8), 0.0, "sandbag"],
	[Vector3(-1, 0, -60), Vector3(4.4, 1.3, 1.9), 1.6, "car"],
	[Vector3(-18, 0, -78), Vector3(4.4, 1.3, 1.9), 0.2, "car"],
	[Vector3(20, 0, -78), Vector3(7.0, 3.2, 2.5), 0.05, "truck"],
	[Vector3(14, 0, -65), Vector3(1.4, 1.1, 1.4), 0.4, "crate"],
	[Vector3(-21, 0, -65), Vector3(2.5, 1.1, 1.0), 0.0, "crate"],
	[Vector3(3, 0, -79), Vector3(2.4, 2.6, 6.0), 1.57, "tall"],

	# ---- beyond the village
	[Vector3(-48, 0, -98), Vector3(10.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(30, 0, -100), Vector3(10.0, 1.4, 1.2), 0.0, "hedge"],
	[Vector3(-60, 0, -80), Vector3(0.8, 7.0, 0.8), 0.0, "tree"],
	[Vector3(52, 0, -70), Vector3(0.8, 6.5, 0.8), 0.0, "tree"],
	[Vector3(60, 0, -66), Vector3(0.7, 6.0, 0.7), 0.0, "tree"],
]

const AREAS := [
	{"name": "OUTPOST", "center": Vector3(1, 0, 5), "radius": 12.0,
		"men": [Vector3(-3, 0, 6.8), Vector3(6.5, 0, 7.3), Vector3(-6, 0, 0)]},
	{"name": "TREELINE", "center": Vector3(-48, 0, -15), "radius": 16.0,
		"men": [Vector3(-60, 0, -13.6), Vector3(-48, 0, -13.6), Vector3(-36, 0, -13.6)], "rpg": [1]},
	{"name": "FARM", "center": Vector3(62, 0, -32), "radius": 18.0,
		"men": [Vector3(50.5, 0, -28), Vector3(56, 0, -25.5), Vector3(65, 0, -28), Vector3(64, 0, -39.5)], "rpg": [2]},
	{"name": "CROSSROADS", "center": Vector3(-6, 0, -70), "radius": 22.0,
		"men": [Vector3(-14, 0, -64.5), Vector3(-4, 0, -64.5), Vector3(14, 0, -66.5), Vector3(-21, 0, -66.5), Vector3(3, 0, -76)],
		"apc": [Vector3(-40, 0, -71), Vector3(30, 0, -71)], "rpg": [0, 2]},
]


## Telegraph poles along the road and a far treeline on the horizon
## (scenery only, no collision).
static func build_extras(main: Node3D) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.22, 0.16)
	wood.roughness = 0.95
	var z := -105.0
	while z < 105.0:
		var x := 10.0 * sin(z * 0.018) + 7.5
		_box(main, Vector3(x, 4.0, z), Vector3(0.22, 8.0, 0.22), wood)
		_box(main, Vector3(x, 7.4, z), Vector3(1.8, 0.14, 0.14), wood)
		z += 28.0
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.15, 0.22, 0.1)
	leaves.roughness = 0.95
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in 4:
		for i in 16:
			var t := -150.0 + i * 20.0 + rng.randf_range(-6.0, 6.0)
			var d := 135.0 + rng.randf_range(0.0, 25.0)
			var p := Vector3(t, 0, -d) if side == 0 else (Vector3(t, 0, d) if side == 1 else (Vector3(-d, 0, t) if side == 2 else Vector3(d, 0, t)))
			var r := rng.randf_range(4.0, 7.0)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r
			sm.height = r * 1.7
			sm.radial_segments = 8
			sm.rings = 4
			mi.mesh = sm
			mi.material_override = leaves
			mi.position = p + Vector3(0, r * 0.9, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			main.add_child(mi)


static func _box(main: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	main.add_child(mi)
