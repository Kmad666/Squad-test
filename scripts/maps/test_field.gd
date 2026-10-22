extends RefCounted
## Daytime test field: open ground, crates and walls, three small enemy
## positions (ALPHA, BRAVO, CHARLIE). Good for tuning mechanics.

const NAME := "TEST FIELD"
const NIGHT := false
const GROUND := "field"
const START := Vector3(0, 0, 42)           # outside enemy rifle range
const AT_TEAM := Vector3(-36, 0, 32)       # anti-armor team waiting to link up
const OBJECTIVE := "TEST FIELD  -  CLEAR ALL THREE AREAS"
const COMPLETE := "ALL AREAS CLEARED  -  PRESS R TO RESTART"

## Cover: [ground position, size, yaw, type]. "crate" and "wall" are low cover
## (1.1 m, shoot over it), "tall" crates (2.4 m) are hard cover you lean around.
const BOXES := [
	# Start zone
	[Vector3(-4, 0, 36), Vector3(3.0, 1.1, 1.0), 0.0, "crate"],
	[Vector3(5, 0, 37), Vector3(2.5, 1.1, 1.0), 0.2, "crate"],
	# Midfield: cover to advance through
	[Vector3(-14, 0, 24), Vector3(5.0, 1.1, 0.5), 0.1, "wall"],
	[Vector3(-6, 0, 20), Vector3(1.6, 2.4, 1.6), 0.0, "tall"],
	[Vector3(2, 0, 22), Vector3(3.0, 1.1, 1.0), 0.0, "crate"],
	[Vector3(12, 0, 18), Vector3(4.5, 1.1, 0.5), -0.2, "wall"],
	[Vector3(20, 0, 12), Vector3(2.5, 1.1, 1.0), 0.4, "crate"],
	[Vector3(-24, 0, 10), Vector3(3.0, 1.1, 1.0), -0.3, "crate"],
	[Vector3(-34, 0, 4), Vector3(1.6, 2.4, 1.6), 0.0, "tall"],
	[Vector3(-4, 0, 8), Vector3(4.0, 1.1, 0.5), 0.0, "wall"],
	[Vector3(8, 0, 4), Vector3(2.0, 1.1, 1.0), 0.6, "crate"],
	[Vector3(17, 0, -2), Vector3(1.6, 2.4, 1.6), 0.3, "tall"],
	[Vector3(32, 0, -6), Vector3(3.0, 1.1, 1.0), 1.2, "crate"],
	[Vector3(-13, 0, -1), Vector3(3.5, 1.1, 0.5), 0.4, "wall"],
	[Vector3(-6, 0, -8), Vector3(2.0, 1.1, 1.0), -0.4, "crate"],
	# Area ALPHA (west): sandbag line with a tall crate behind it
	[Vector3(-24, 0, -13), Vector3(5.0, 1.1, 0.5), 0.0, "wall"],
	[Vector3(-29.5, 0, -17), Vector3(0.5, 1.1, 4.0), 0.0, "wall"],
	[Vector3(-19, 0, -16), Vector3(1.2, 1.1, 1.2), 0.0, "crate"],
	[Vector3(-23, 0, -22), Vector3(1.6, 2.4, 1.6), 0.0, "tall"],
	# Area BRAVO (centre): checkpoint
	[Vector3(0, 0, -20), Vector3(4.0, 1.1, 0.5), 0.0, "wall"],
	[Vector3(8, 0, -21), Vector3(4.0, 1.1, 0.5), 0.15, "wall"],
	[Vector3(4, 0, -27), Vector3(1.6, 2.4, 1.6), 0.0, "tall"],
	[Vector3(-3, 0, -29), Vector3(2.0, 1.1, 1.0), 0.5, "crate"],
	[Vector3(11, 0, -30), Vector3(2.0, 1.1, 1.0), -0.4, "crate"],
	# Area CHARLIE (east): motor pool, the APC patrols the lane behind it
	[Vector3(22, 0, -29), Vector3(5.0, 1.1, 0.5), 0.0, "wall"],
	[Vector3(31, 0, -31), Vector3(2.5, 1.1, 1.0), -0.2, "crate"],
	[Vector3(17, 0, -36), Vector3(1.6, 2.4, 1.6), 0.0, "tall"],
	[Vector3(38, 0, -37), Vector3(1.6, 2.4, 1.6), 0.0, "tall"],
]

## Enemy positions. Small groups on purpose: you have the numbers for now.
const AREAS := [
	{"name": "ALPHA", "center": Vector3(-24, 0, -18), "radius": 11.0,
		"men": [Vector3(-24, 0, -15), Vector3(-20, 0, -18)]},
	{"name": "BRAVO", "center": Vector3(4, 0, -25), "radius": 11.0,
		"men": [Vector3(1, 0, -22), Vector3(7, 0, -23), Vector3(4, 0, -31)]},
	{"name": "CHARLIE", "center": Vector3(27, 0, -35), "radius": 12.0,
		"men": [Vector3(24, 0, -31), Vector3(31, 0, -33)],
		"apc": [Vector3(20, 0, -44), Vector3(36, 0, -44)]},
]



static func build_extras(_main: Node3D) -> void:
	pass
