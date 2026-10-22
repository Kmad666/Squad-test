extends RefCounted
## Night mission: OPERATION LAMPLIGHTER.
##
## You enter a city street from the south. The main road runs north between
## two rows of buildings to a walled compound. A back alley runs parallel on
## the west side, joined to the road by two side passages; the anti-armor
## team waits in the first passage. A roadblock holds the middle of the road,
## two riflemen watch the alley, and the compound (gate on the road, breach at
## the alley mouth) holds four riflemen and the APC.
##
## Coordinates: x across (road is x -5..5), z along the road (start z = +44,
## compound z -24..-47). Box types:
##   building / cwall : solid, block sight, cover only at their corners
##   car / crate / dumpster / barrier / sandbag : low cover, shoot over it
##   tall : tall crate, lean around it

const NAME := "OPERATION LAMPLIGHTER"
const NIGHT := true
const GROUND := "street"
const START := Vector3(0, 0, 44)
const AT_TEAM := Vector3(-14, 0, 31.5)
const OBJECTIVE := "OBJECTIVE: SECURE THE COMPOUND AT THE END OF THE ROAD"
const COMPLETE := "COMPOUND SECURED  -  MISSION COMPLETE  -  R TO REPLAY"

const BOXES := [
	# ---- buildings: east side of the road
	[Vector3(13, 0, 39), Vector3(12, 9, 18), 0.0, "building"],
	[Vector3(13, 0, 16.5), Vector3(12, 11, 17), 0.0, "building"],
	[Vector3(13, 0, -7.5), Vector3(12, 8, 21), 0.0, "building"],
	[Vector3(25, 0, 13), Vector3(12, 12, 70), 0.0, "building"],
	[Vector3(27, 0, -35), Vector3(10, 9, 26), 0.0, "building"],
	# ---- buildings: west side of the road (the alley runs behind them)
	[Vector3(-12, 0, 41), Vector3(10, 10, 14), 0.0, "building"],
	[Vector3(-12, 0, 20.5), Vector3(10, 8, 17), 0.0, "building"],
	[Vector3(-12, 0, -3.5), Vector3(10, 12, 21), 0.0, "building"],
	[Vector3(-28, 0, 13), Vector3(12, 11, 70), 0.0, "building"],
	[Vector3(-28, 0, -35), Vector3(12, 9, 26), 0.0, "building"],
	# ---- backdrop behind the start
	[Vector3(-1.5, 0, 49.5), Vector3(65, 7, 1), 0.0, "building"],

	# ---- compound: walls (gate on the road, breach at the alley mouth) and HQ
	[Vector3(-9.5, 0, -24), Vector3(11, 2.6, 0.6), 0.0, "cwall"],
	[Vector3(13, 0, -24), Vector3(18, 2.6, 0.6), 0.0, "cwall"],
	[Vector3(-22, 0, -35.5), Vector3(0.6, 2.6, 23), 0.0, "cwall"],
	[Vector3(22, 0, -35.5), Vector3(0.6, 2.6, 23), 0.0, "cwall"],
	[Vector3(0, 0, -47), Vector3(44.6, 2.6, 0.6), 0.0, "cwall"],
	[Vector3(13, 0, -41), Vector3(10, 6, 10), 0.0, "building"],
	# compound interior
	[Vector3(0, 0, -28), Vector3(4.0, 1.0, 0.7), 0.0, "sandbag"],
	[Vector3(-9, 0, -30), Vector3(3.5, 1.0, 0.7), 0.3, "sandbag"],
	[Vector3(8, 0, -30), Vector3(3.5, 1.0, 0.7), -0.3, "sandbag"],
	[Vector3(-15, 0, -33), Vector3(2.0, 1.1, 1.2), 0.0, "crate"],
	[Vector3(-4, 0, -36), Vector3(1.6, 2.4, 1.6), 0.0, "tall"],
	[Vector3(3, 0, -38), Vector3(2.5, 1.1, 1.0), 0.0, "crate"],
	[Vector3(6, 0, -34), Vector3(1.2, 1.1, 1.2), 0.4, "crate"],
	[Vector3(-15, 0, -38), Vector3(4.4, 1.3, 1.9), 1.4, "car"],

	# ---- the road: parked and crashed cars, the roadblock
	[Vector3(-3.4, 0, 36), Vector3(4.4, 1.3, 1.9), 1.65, "car"],
	[Vector3(3.5, 0, 27), Vector3(4.4, 1.3, 1.9), 1.5, "car"],
	[Vector3(-1.5, 0, 18), Vector3(4.4, 1.3, 1.9), 0.95, "car"],
	[Vector3(3.6, 0, 10), Vector3(4.4, 1.3, 1.9), 1.57, "car"],
	[Vector3(-2.5, 0, 5.5), Vector3(3.0, 1.0, 0.6), 0.0, "barrier"],
	[Vector3(2.5, 0, 5.2), Vector3(3.0, 1.0, 0.6), -0.1, "barrier"],
	[Vector3(-3.8, 0, 1.0), Vector3(4.4, 1.3, 1.9), 1.62, "car"],
	[Vector3(2, 0, -8), Vector3(4.4, 1.3, 1.9), 0.25, "car"],
	[Vector3(-3.5, 0, -15), Vector3(4.4, 1.3, 1.9), 1.4, "car"],
	[Vector3(3.6, 0, -19), Vector3(4.4, 1.3, 1.9), 1.7, "car"],
	# sidewalk clutter
	[Vector3(6, 0, 32), Vector3(1.2, 1.1, 1.2), 0.2, "crate"],
	[Vector3(-6, 0, 25), Vector3(1.2, 1.3, 2.0), 0.0, "dumpster"],
	[Vector3(6.2, 0, 20), Vector3(1.4, 1.1, 1.0), -0.3, "crate"],
	[Vector3(6, 0, -1), Vector3(1.2, 1.3, 2.0), 0.0, "dumpster"],
	[Vector3(-6, 0, -9), Vector3(1.2, 1.1, 1.2), 0.5, "crate"],
	# courtyards and side passages
	[Vector3(10, 0, 27.5), Vector3(2.0, 1.1, 1.0), 0.3, "crate"],
	[Vector3(9, 0, 5.5), Vector3(2.0, 1.3, 1.2), 0.0, "dumpster"],
	[Vector3(-9, 0, 30.5), Vector3(1.4, 1.1, 1.0), 0.0, "crate"],
	[Vector3(-12, 0, 9.5), Vector3(2.0, 1.1, 1.0), 0.2, "crate"],

	# ---- the alley (x -22..-17)
	[Vector3(-20.5, 0, 42), Vector3(1.2, 1.3, 2.0), 0.0, "dumpster"],
	[Vector3(-18, 0, 36), Vector3(1.2, 1.1, 1.2), 0.3, "crate"],
	[Vector3(-20.8, 0, 26), Vector3(1.0, 1.1, 1.4), 0.0, "crate"],
	[Vector3(-18.2, 0, 18), Vector3(1.2, 1.3, 2.0), 0.0, "dumpster"],
	[Vector3(-20.5, 0, 12), Vector3(1.2, 1.1, 1.2), -0.2, "crate"],
	[Vector3(-20.6, 0, 3), Vector3(1.4, 2.4, 1.4), 0.0, "tall"],
	[Vector3(-18, 0, -3), Vector3(1.2, 1.1, 1.2), 0.4, "crate"],
	[Vector3(-20.6, 0, -9), Vector3(1.2, 1.3, 2.0), 0.0, "dumpster"],
	[Vector3(-18.2, 0, -16), Vector3(1.2, 1.1, 1.2), 0.0, "crate"],
	# small plaza between the alley mouth and the road
	[Vector3(-12, 0, -19), Vector3(3.0, 1.0, 0.6), 0.2, "barrier"],
	[Vector3(-9, 0, -16), Vector3(1.2, 1.1, 1.2), 0.0, "crate"],
]

const AREAS := [
	{"name": "ROADBLOCK", "center": Vector3(0, 0, 2), "radius": 9.0,
		"men": [Vector3(-2.5, 0, 4.3), Vector3(2.5, 0, 4.0)]},
	{"name": "ALLEY", "center": Vector3(-19.5, 0, -7), "radius": 8.0,
		"men": [Vector3(-18, 0, -4.1), Vector3(-20.4, 0, -11.2)]},
	{"name": "COMPOUND", "center": Vector3(0, 0, -35), "radius": 16.0,
		"men": [Vector3(-1, 0, -29), Vector3(-9, 0, -31.2), Vector3(8, 0, -31), Vector3(-4, 0, -38)],
		"apc": [Vector3(-12, 0, -43.5), Vector3(4, 0, -43.5)]},
]

const SODIUM := Color(1.0, 0.66, 0.32)


## Street lamps, the alley light and the compound floodlight that glares
## down at the gate.
static func build_extras(main: Node3D) -> void:
	var a: Node3D = main.atmosphere
	a.add_light_pole(Vector3(6.3, 0, 34), 6.0, Vector3(1.5, 0, 33), SODIUM, 10.0, 62.0, 17.0, true, 2.0)
	a.add_light_pole(Vector3(-6.3, 0, 14), 6.0, Vector3(-1.5, 0, 14), SODIUM, 10.0, 62.0, 17.0, false, 2.0)
	a.add_light_pole(Vector3(6.3, 0, -4), 6.0, Vector3(1.5, 0, -4), SODIUM, 10.0, 62.0, 17.0, false, 2.0)
	a.add_light_pole(Vector3(-17.3, 0, 24), 4.5, Vector3(-19.5, 0, 24), Color(0.7, 0.82, 1.0), 6.0, 70.0, 12.0, false, 1.4)
	a.add_light_pole(Vector3(8.5, 0, -35.4), 7.5, Vector3(0, 0, -24), Color(0.85, 0.92, 1.0), 18.0, 34.0, 40.0, true, 3.6)
