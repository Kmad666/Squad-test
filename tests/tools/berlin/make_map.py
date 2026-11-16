#!/usr/bin/env python3
"""Writes scripts/maps/berlin_mission.gd from the Kettenkiez study's layout.

    node tests/tools/berlin/dump_layout.cjs design/berlin/src tests/tools/berlin/layout.json
    python3 tests/tools/berlin/make_map.py

layout.json is what the study's own code places (house lots, the vacant lot,
parked cars, tram, lanterns, trees, street furniture). This turns it into the
game's boxes and adds what makes it a mission: carriage gateways opened into
the courtyards, the courtyards themselves, barricades, the enemy and the
rocket team. Coordinates are the study's: Kettenstraße (the tram street) runs
along x, Gordianstraße along z; -z is north.
"""
import json, math, os, random

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
L = json.load(open(os.path.join(HERE, "layout.json")))
D = L["D"]
EDGE, A_FRONT, B_FRONT, DEPTH = D["L"], D["aFront"], D["bFront"], 13.0
A_BACK, B_BACK = A_FRONT + DEPTH, B_FRONT + DEPTH          # 26, 24: the courtyard side of the houses
GATE_W, GATE_H = 4.2, 4.0

# House colours by style (plaster creams and ochres, grey where the stucco was
# knocked off, brick, 1980s concrete), a few of each so neighbours differ.
PALETTE = {
    "rich": [(0.80, 0.74, 0.60), (0.83, 0.78, 0.66), (0.76, 0.68, 0.52)],
    "moderate": [(0.74, 0.66, 0.48), (0.70, 0.70, 0.62), (0.78, 0.72, 0.58)],
    "stripped": [(0.56, 0.55, 0.51), (0.60, 0.58, 0.53)],
    "nouveau": [(0.62, 0.68, 0.60), (0.66, 0.70, 0.72), (0.80, 0.76, 0.64)],
    "brick": [(0.50, 0.28, 0.21), (0.55, 0.32, 0.22)],
    "gdr": [(0.62, 0.62, 0.59)],
    "corner": [(0.80, 0.72, 0.56), (0.76, 0.70, 0.60)],
    "rear": [(0.52, 0.50, 0.46), (0.58, 0.54, 0.47), (0.48, 0.47, 0.45)],
}

# Carriage gateways opened right through a house into its courtyard: lot name
# -> where along the street (x for Kettenstraße lots, z for Gordianstraße
# lots). All five are houses the study gives a wide gate.
GATES = {"B 1,1 1": 57.0, "A 1,1 1": 58.0, "B -1,1 1": 63.0, "A 1,-1 0": 42.0, "B 1,-1 1": -63.0}
OPEN_YARDS = [(1, 1), (-1, 1), (1, -1)]     # quadrants (sign x, sign z) whose courtyards you can get into; (-1,-1) is closed

# Houses you can go into: the ground floor is real (walls, doors, rooms,
# windows); the storeys above are one block the game lifts off when the squad
# is inside. lot name -> [label, does it have a back door onto its yard, how
# many of the enemy are inside].
INTERIORS = {
    "B 1,1 0": ["EAST HOUSE", True, 3],        # beside the south barricade; backs onto the south-east yard
    "B -1,1 0": ["WEST HOUSE", True, 0],       # opposite it, empty: yours to take and fire from
    "A -1,-1 0": ["KETTEN HOUSE", False, 4],   # north side of Kettenstrasse, looks onto the crossing and the vacant lot
    "B 1,-1 0": ["NORTH HOUSE", True, 4],      # beside the north strongpoint; backs onto the north-east yard
}
WALL_T, CEIL, DOOR_W, WIN_W, SILL_H, HEAD_H = 0.4, 3.6, 1.6, 2.0, 1.0, 2.3

rnd = random.Random(1887)
houses = []         # {name, rect, height, colour}
rooms = []          # [x0, z0, x1, z1, house]
doors = []          # [pos, normal (from room a into room b), a, b]   (-1 = outside)
garrisons = []      # {name, rect, men}
boxes = []          # (comment or None, [x, y, z], [sx, sy, sz], yaw, type, colour or None)


def box(pos, size, yaw, kind, colour=None, note=None):
    boxes.append((note, [round(v, 2) for v in pos], [round(v, 2) for v in size], round(yaw, 3), kind, colour))


def rect(x0, x1, z0, z1, h, kind, colour=None, note=None, y=0.0):
    """Axis-aligned box from its footprint."""
    box([(x0 + x1) / 2, y, (z0 + z1) / 2], [abs(x1 - x0), h, abs(z1 - z0)], 0.0, kind, colour, note)


def colour(style):
    return rnd.choice(PALETTE[style])


# ------------------------------------------------------------------ houses
def house(lot):
    h = round(rnd.uniform(20.5, 23.0), 1)
    col = colour(lot["style"])
    first = True
    for seg in lot["segs"]:
        (ox, oz), (ax, az), w = seg["o"], seg["a"], seg["w"]
        ex, ez = ox + ax * w, oz + az * w
        if seg.get("chamfer"):
            # The cut corner: a block on the diagonal filling in behind it.
            mx, mz = (ox + ex) / 2, (oz + ez) / 2
            sx, sz = math.copysign(1, mx), math.copysign(1, mz)
            t = D["chamfer"] / math.sqrt(2)
            cx, cz = mx + sx * t / 2 / math.sqrt(2) * 1.0, mz + sz * t / 2 / math.sqrt(2) * 1.0
            # Godot yaw: local x -> (cos, 0, -sin). The chamfer runs along (-sx, sz).
            yaw = math.atan2(-sz, -sx)
            box([cx, 0, cz], [D["chamfer"] * math.sqrt(2), h, t], yaw, "building", col)
            continue
        note = lot["name"] + " (" + lot["style"] + ")" if first else None
        first = False
        along_x = abs(ax) > 0.5
        if along_x:
            s = math.copysign(1, oz)
            x0, x1 = sorted((ox, ex))
            z0, z1 = s * A_FRONT, s * A_BACK
            gate = GATES.get(lot["name"])
            if gate is None:
                rect(x0, x1, z0, z1, h, "building", col, note)
            else:
                rect(x0, gate - GATE_W / 2, z0, z1, h, "building", col, note + ", gateway at x %.0f" % gate)
                rect(gate + GATE_W / 2, x1, z0, z1, h, "building", col)
                rect(gate - GATE_W / 2, gate + GATE_W / 2, z0, z1, h - GATE_H, "building", col, y=GATE_H)
        else:
            s = math.copysign(1, ox)
            z0, z1 = sorted((oz, ez))
            x0, x1 = s * B_FRONT, s * B_BACK
            gate = GATES.get(lot["name"])
            if gate is None:
                rect(x0, x1, z0, z1, h, "building", col, note)
            else:
                rect(x0, x1, z0, gate - GATE_W / 2, h, "building", col, note + ", gateway at z %.0f" % gate)
                rect(x0, x1, gate + GATE_W / 2, z1, h, "building", col)
                rect(x0, x1, gate - GATE_W / 2, gate + GATE_W / 2, h - GATE_H, "building", col, y=GATE_H)


def interior(lot):
    """A house with a real ground floor. Plan, in the house's own frame (u
    along the street, v back from the front): a front row and a back row of
    rooms either side of a spine wall, two or three bays long. The front
    door is in the last bay, the back door (if any) in the first, and the
    doors through the spine are off to one side of each bay, so no door looks
    straight through another."""
    label, has_back, men_n = INTERIORS[lot["name"]]
    seg = lot["segs"][0]
    (ox, oz), (ax, az), w = seg["o"], seg["a"], seg["w"]
    ex, ez = ox + ax * w, oz + az * w
    along_x = abs(ax) > 0.5
    h = round(rnd.uniform(20.5, 23.0), 1)
    col = colour(lot["style"])
    if along_x:
        s = math.copysign(1, oz)
        u0 = min(ox, ex)
        to_world = lambda u, v: (u0 + u, s * (A_FRONT + v))
        v_dir, u_dir = (0, 0, s), (1, 0, 0)
    else:
        s = math.copysign(1, ox)
        u0 = min(oz, ez)
        to_world = lambda u, v: (s * (B_FRONT + v), u0 + u)
        v_dir, u_dir = (s, 0, 0), (0, 0, 1)
    Lh = w
    hi = len(houses)

    def piece(ua, ub, va, vb, hgt, kind, y=0.0, c=col):
        (xa, za), (xb, zb) = to_world(ua, va), to_world(ub, vb)
        rect(min(xa, xb), max(xa, xb), min(za, zb), max(za, zb), hgt, kind, c if kind == "hwall" else None, y=y)

    def run(along_u, a, b, c0, c1, openings):
        """A wall from a to b (along u, or along v) filling the band c0..c1
        across it, with door / window openings [(centre, kind)]."""
        def put(p, q, hgt, kind, y=0.0):
            if q - p < 0.05:
                return
            if along_u:
                piece(p, q, c0, c1, hgt, kind, y)
            else:
                piece(c0, c1, p, q, hgt, kind, y)
        at = a
        for centre, kind in sorted(openings):
            half = (DOOR_W if kind == "door" else WIN_W) / 2
            put(at, centre - half, CEIL, "hwall")
            if kind == "window":
                put(centre - half, centre + half, SILL_H, "wall")
            put(centre - half, centre + half, CEIL - HEAD_H, "hwall", HEAD_H)
            at = centre + half
        put(at, b, CEIL, "hwall")

    bays = 2 if Lh < 18 else 3
    bw = Lh / bays
    mid_v = DEPTH / 2
    hall, back_bay = bays - 1, 0
    centre = lambda k: (k + 0.5) * bw
    # Outside walls.
    run(True, 0, Lh, 0, WALL_T, [(centre(k), "door" if k == hall else "window") for k in range(bays)])
    run(True, 0, Lh, DEPTH - WALL_T, DEPTH, [(centre(k), "door" if k == back_bay else "window") for k in range(bays)] if has_back else [])
    run(False, WALL_T, DEPTH - WALL_T, 0, WALL_T, [])
    run(False, WALL_T, DEPTH - WALL_T, Lh - WALL_T, Lh, [])
    # Spine wall and the walls between bays.
    spine = [(centre(k) + (1.6 if k % 2 == 0 else -1.6), "door") for k in range(bays)]
    run(True, WALL_T, Lh - WALL_T, mid_v - WALL_T / 2, mid_v + WALL_T / 2, spine)
    for k in range(1, bays):
        run(False, WALL_T, mid_v - WALL_T / 2, k * bw - WALL_T / 2, k * bw + WALL_T / 2, [(mid_v / 2 - 0.6, "door")])
        run(False, mid_v + WALL_T / 2, DEPTH - WALL_T, k * bw - WALL_T / 2, k * bw + WALL_T / 2, [(mid_v * 1.5 + 0.6, "door")])
    # Rooms, front row then back row, and the doors between them.
    base = len(rooms)

    def room_rect(k, back):
        ua, ub = k * bw + (WALL_T if k == 0 else WALL_T / 2), (k + 1) * bw - (WALL_T if k == bays - 1 else WALL_T / 2)
        va, vb = (mid_v + WALL_T / 2, DEPTH - WALL_T) if back else (WALL_T, mid_v - WALL_T / 2)
        (xa, za), (xb, zb) = to_world(ua, va), to_world(ub, vb)
        return [round(min(xa, xb), 2), round(min(za, zb), 2), round(max(xa, xb), 2), round(max(za, zb), 2)]

    for back in (False, True):
        for k in range(bays):
            rooms.append(room_rect(k, back) + [hi])
    front = lambda k: base + k
    rear = lambda k: base + bays + k

    def door(u, v, n, a, b):
        x, z = to_world(u, v)
        doors.append([[round(x, 2), 0, round(z, 2)], list(n), a, b])

    door(centre(hall), WALL_T / 2, v_dir, -1, front(hall))
    if has_back:
        door(centre(back_bay), DEPTH - WALL_T / 2, v_dir, rear(back_bay), -1)
    for k, (u, _) in enumerate(spine):
        door(u, mid_v, v_dir, front(k), rear(k))
    for k in range(1, bays):
        door(k * bw, mid_v / 2 - 0.6, u_dir, front(k - 1), front(k))
        door(k * bw, mid_v * 1.5 + 0.6, u_dir, rear(k - 1), rear(k))
    # A table or a cupboard in each room: something to get behind indoors.
    for i in range(bays * 2):
        r = rooms[base + i]
        cx, cz = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
        ang = rnd.choice([0.0, 1.571])
        if i % 2 == 0:
            box([cx + rnd.uniform(-0.6, 0.6), 0, cz + rnd.uniform(-0.6, 0.6)], [1.8, 0.9, 0.9], ang, "crate")
        else:
            box([cx + rnd.uniform(-0.8, 0.8), 0, cz + rnd.uniform(-0.8, 0.8)], [1.3, 2.0, 0.6], ang, "tall")
    (xa, za), (xb, zb) = to_world(0, 0), to_world(Lh, DEPTH)
    hrect = [round(min(xa, xb), 2), round(min(za, zb), 2), round(max(xa, xb), 2), round(max(za, zb), 2)]
    houses.append({"name": label, "rect": hrect, "height": h, "colour": col})
    # The garrison: men at the front windows first, then the back rooms.
    if men_n:
        men = []
        spots = [(centre(k), WALL_T + 0.7) for k in range(bays) if k != hall] + [(centre(hall) + 2.2, WALL_T + 0.9)] + [(centre(k), mid_v + 2.5) for k in range(bays)]
        for u, v in spots[:men_n]:
            x, z = to_world(u, v)
            men.append([round(x, 2), 0, round(z, 2)])
        garrisons.append({"name": label, "rect": hrect, "men": men})


gap = None
for lot in L["lots"]:
    if lot.get("gap"):
        gap = lot
    elif lot["name"] in INTERIORS:
        first_box = len(boxes)
        interior(lot)
        n, pos, size, yaw, kind, c = boxes[first_box]
        boxes[first_box] = ("%s: %s (%s), enterable: ground-floor walls, sills and furniture" % (INTERIORS[lot["name"]][0], lot["name"], lot["style"]), pos, size, yaw, kind, c)
    else:
        house(lot)

# ------------------------------------------------------------------ courtyards
# Behind the street houses of an open block: a band of yard (34 m deep behind
# the Kettenstraße houses, 28 m behind the Gordianstraße ones), the rest of
# the block filled by rear houses. One side wing sticks out into each band.
YARD_U, YARD_V = 52.0, 60.0
for sx in (-1, 1):
    for sz in (-1, 1):
        name = {(1, 1): "south-east", (-1, 1): "south-west", (1, -1): "north-east", (-1, -1): "north-west"}[(sx, sz)]
        if (sx, sz) not in OPEN_YARDS:
            rect(sx * B_BACK, sx * EDGE, sz * A_BACK, sz * EDGE, 18.0, "building", colour("rear"), "the %s block: closed (rear houses fill it)" % name)
            continue
        rect(sx * YARD_U, sx * EDGE, sz * YARD_V, sz * EDGE, 18.0, "building", colour("rear"), "the %s courtyard: rear houses, side wings, yard clutter" % name)
        rect(sx * 72, sx * 79, sz * A_BACK, sz * 42, 16.0, "building", colour("rear"))
        rect(sx * B_BACK, sx * 38, sz * 78, sz * 85, 16.0, "building", colour("rear"))
        # The neighbours' rear houses close the yard off at the edge of the map.
        rect(sx * B_BACK, sx * YARD_U, sz * EDGE, sz * (EDGE + 13), 18.0, "building", colour("rear"))
        rect(sx * EDGE, sx * (EDGE + 13), sz * A_BACK, sz * YARD_V, 18.0, "building", colour("rear"))
        # More sheds, a garage row and walls: no long open crossings.
        rect(sx * 58, sx * 68, sz * 51, sz * 54, 2.6, "tall")
        rect(sx * 30, sx * 33, sz * 60, sz * 64, 2.6, "tall")
        rect(sx * 54, sx * 66, sz * 38, sz * 38.4, 1.1, "wall")
        rect(sx * 42, sx * 42.4, sz * 72, sz * 84, 1.1, "wall")
        rect(sx * 82, sx * 86, sz * 30, sz * 33, 2.6, "tall")
        box([sx * 46, 0, sz * 34], [1.4, 1.1, 1.4], 0.5, "crate")
        box([sx * 70, 0, sz * 47], [1.8, 1.3, 1.1], 0.3, "dumpster")
        box([sx * 36, 0, sz * 74], [1.4, 1.1, 1.4], 0.2, "crate")
        # Yard walls with gaps, a shed, bins and crates: cover on the way through.
        rect(sx * 36, sx * 36.4, sz * 30, sz * 41, 1.1, "wall")
        rect(sx * 88, sx * 88.4, sz * 40, sz * 52, 1.1, "wall")
        rect(sx * 30, sx * 41, sz * 68, sz * 68.4, 1.1, "wall")
        rect(sx * 44, sx * 48, sz * 44, sz * 47, 2.6, "tall")
        box([sx * 28.5, 0, sz * 50], [1.8, 1.3, 1.1], 0.0, "dumpster")
        box([sx * 64, 0, sz * 30], [1.8, 1.3, 1.1], 1.57, "dumpster")
        box([sx * 58, 0, sz * 46], [1.4, 1.1, 1.4], 0.4, "crate")
        box([sx * 40, 0, sz * 56], [2.5, 1.1, 1.0], 0.2, "crate")
        box([sx * 46, 0, sz * 90], [1.4, 1.1, 1.4], 0.1, "crate")
        box([sx * 84, 0, sz * 56], [1.4, 1.1, 1.4], 0.7, "crate")

# ------------------------------------------------------------------ the vacant lot
(ox, oz), (ax, az), w = gap["segs"][0]["o"], gap["segs"][0]["a"], gap["segs"][0]["w"]
gx0, gx1 = sorted((ox, ox + ax * w))
gz = math.copysign(1, oz)
mid = (gx0 + gx1) / 2
rect(gx0, mid - 2.2, gz * (A_FRONT + 0.1), gz * (A_FRONT + 0.4), 2.6, "tall", None, "the vacant lot: hoarding along the pavement (with a break), rubble")
rect(mid + 2.2, gx1, gz * (A_FRONT + 0.1), gz * (A_FRONT + 0.4), 2.6, "tall")
box([mid + 4.5, 0, gz * 17.5], [2.2, 1.2, 1.6], 0.4, "rock")
box([mid - 5.0, 0, gz * 20.5], [2.4, 1.3, 1.7], 1.1, "rock")
box([mid, 0, gz * 23.5], [2.5, 1.1, 1.0], 0.1, "crate")
box([mid - 1.0, 0, gz * 16.0], [1.4, 1.1, 1.4], 0.5, "crate")

# ------------------------------------------------------------------ the tram, stops, furniture
for m in L["misc"]:
    if m["what"] == "tram":
        first = True
        for a, b in ((0, 9.6), (9.9, 19.8), (20.1, 30.0)):          # three sections, running back toward +x
            rect(m["xFront"] + a, m["xFront"] + b, m["z"] - 1.2, m["z"] + 1.2, 3.45, "tram", None, "the tram (30 m, three sections) standing on the north track" if first else None)
            first = False
    elif m["what"] == "tramstop":
        rect(m["x"] - 2.0, m["x"] + 2.0, m["z"] - 0.15, m["z"] + 0.15, 2.5, "tall", None, "tram stop shelter")
    elif m["what"] == "litfass":
        box([m["x"], 0, m["z"]], [1.4, 3.6, 1.4], 0.0, "tall", None, "advertising column (Litfaßsäule)")
    elif m["what"] == "pump":
        box([m["x"], 0, m["z"]], [0.6, 1.4, 0.6], 0.78, "crate", None, "hand pump")


# ------------------------------------------------------------------ what the mission adds on the streets
BARRICADES = [
    ("GORDIAN SOUTH: barricade across Gordianstraße", [
        ([-2.6, 0, 36.0], [4.0, 1.0, 0.8], 0.0, "sandbag"), ([2.9, 0, 37.2], [3.5, 1.0, 0.8], 0.0, "sandbag"),
        ([0.2, 0, 33.2], [4.4, 1.3, 1.9], 0.12, "car"), ([-8.6, 0, 34.0], [1.4, 1.1, 1.4], 0.3, "crate"), ([8.4, 0, 35.4], [2.5, 1.1, 1.0], 0.0, "crate")]),
    ("CROSSING: sandbags on the north side, a kiosk", [
        ([-3.4, 0, -9.0], [4.0, 1.0, 0.8], 0.0, "sandbag"), ([4.0, 0, -8.6], [3.5, 1.0, 0.8], 0.0, "sandbag"),
        ([-8.6, 0, -15.2], [2.2, 2.6, 2.2], 0.0, "tall"), ([9.6, 0, 9.6], [1.4, 1.1, 1.4], 0.4, "crate")]),
    ("KETTEN EAST: the tram street east of the tram", [
        ([62.0, 0, -4.9], [4.0, 1.0, 0.8], 1.571, "sandbag"), ([66.0, 0, -4.2], [1.4, 1.1, 1.4], 0.2, "crate"), ([70.0, 0, -9.6], [2.5, 1.1, 1.0], 0.0, "crate")]),
    ("GORDIAN NORTH: the strongpoint up Gordianstraße", [
        ([-2.6, 0, -44.0], [4.0, 1.0, 0.8], 0.0, "sandbag"), ([3.0, 0, -45.2], [3.5, 1.0, 0.8], 0.0, "sandbag"),
        ([0.0, 0, -57.5], [6.0, 2.6, 2.4], 0.0, "tall"), ([1.0, 0, -66.0], [7.0, 3.2, 2.5], 0.1, "truck"),
        ([-8.4, 0, -49.0], [1.4, 1.1, 1.4], 0.3, "crate"), ([8.4, 0, -53.0], [2.5, 1.1, 1.0], 0.0, "crate")]),
]
for note, items in BARRICADES:
    for i, (pos, size, yaw, kind) in enumerate(items):
        box(pos, size, yaw, kind, None, note if i == 0 else None)

# ------------------------------------------------------------------ parked cars (the study's, thinned)
# Two in three stay. None in front of a gateway, on a barricade or under the APC.
def blocked(c):
    x, z = c["x"], c["z"]
    for name, at in GATES.items():
        street, quad = name.split(" ")[0], name.split(" ")[1]
        sx, sz = [int(v) for v in quad.split(",")]
        if street == "A" and abs(x - at) < 5.0 and z * sz > 0:
            return True
        if street == "B" and abs(z - at) < 5.0 and x * sx > 0:
            return True
    if abs(x) < 6 and (30 < z < 40 or -70 < z < -42):
        return True                       # the two Gordianstraße barricades
    if abs(x - mid) < 4.0 and z > 0:
        return True                       # in front of the break in the hoarding
    return False


kept = 0
first = True
for i, c in enumerate(L["cars"]):
    if i % 3 == 2 or blocked(c):
        continue
    along_x = abs(c["z"]) < 9
    box([c["x"], 0, c["z"]], [c["len"], 1.3, 1.9], 0.0 if along_x else 1.571, "car", None, "parked cars (from the study, thinned)" if first else None)
    first = False
    kept += 1

# ------------------------------------------------------------------ lindens
first = True
for t in L["trees"]:
    x, z = t["x"], t["z"]
    u, v = abs(x), abs(z)
    in_yard = u > B_BACK and v > A_BACK
    quad = (int(math.copysign(1, x)), int(math.copysign(1, z)))
    if in_yard and (quad not in OPEN_YARDS or (u > YARD_U and v > YARD_V)):
        continue                           # under the rear houses
    hgt = round(rnd.uniform(6.5, 8.0) * t.get("s", 1.0), 1)
    box([x, 0, z], [0.7, hgt, 0.7], 0.0, "tree", None, "lindens along Gordianstraße, courtyard and vacant-lot trees" if first else None)
    first = False


# ------------------------------------------------------------------ write it
def v3(v):
    return "Vector3(%s, %s, %s)" % tuple(("%g" % a) for a in v)


lines = []
for note, pos, size, yaw, kind, col in boxes:
    if note:
        lines.append("\t# " + note)
    extra = ", Color(%g, %g, %g)" % col if col else ""
    lines.append("\t[%s, %s, %g, \"%s\"%s]," % (v3(pos), v3(size), yaw, kind, extra))

def area_radius(r):
    return round(math.hypot(r[2] - r[0], r[3] - r[1]) / 2 + 1, 1)


g_lines = []
for g in garrisons:
    r = g["rect"]
    g_lines.append('\t{"name": "%s", "center": Vector3(%g, 0, %g), "radius": %g, "rect": [%g, %g, %g, %g],\n\t\t"men": [%s]},' % (
        g["name"], (r[0] + r[2]) / 2, (r[1] + r[3]) / 2, area_radius(r), r[0], r[1], r[2], r[3], ", ".join(v3(m) for m in g["men"])))
h_lines = ['\t{"name": "%s", "rect": [%g, %g, %g, %g], "height": %g, "color": Color(%g, %g, %g)},' % ((hh["name"],) + tuple(hh["rect"]) + (hh["height"],) + hh["colour"]) for hh in houses]
r_lines = ["\t[%g, %g, %g, %g, %d]," % tuple(r) for r in rooms]
d_lines = ["\t[%s, %s, %d, %d]," % (v3(d[0]), v3(d[1]), d[2], d[3]) for d in doors]

lamps = ", ".join("Vector2(%g, %g)" % (round(p["x"], 1), round(p["z"], 1)) for p in L["lamps"])

out = '''extends RefCounted
## Day mission: OPERATION GORDIAN. A Berlin crossroads, built from the
## Kettenkiez study in design/berlin (a Prenzlauer Berg district, generated
## in three.js). GENERATED by tests/tools/berlin/make_map.py from that
## study's own layout: don't edit the boxes here, edit the generator.
##
## Kettenstraße (granite setts, tram rails, 26 m between the house fronts)
## runs along x; Gordianstraße (asphalt, lindens, 22 m) runs along z; they
## cross at the origin. North is -z. Four perimeter blocks of five-storey
## houses, each lot at its real position and width, with cut corners at the
## crossing. Parked cars line the kerbs, a 30 m tram stands east of the
## crossing, and one lot on Kettenstraße is a vacant lot behind a hoarding.
##
## Five houses have their carriage gateway open right through to the
## courtyard (GATES in the generator), so three of the blocks are ways
## round the crossing: for the squad, and for the enemy's flankers.
##   south-east yard: Gordianstraße z 57  <->  Kettenstraße x 58
##   south-west yard: Gordianstraße z 63  <->  the vacant lot (x -57)
##   north-east yard: Kettenstraße x 42   <->  Gordianstraße z -63
## The north-west block is closed.
##
## Four houses have a real ground floor (INTERIORS in the generator): the
## EAST HOUSE and WEST HOUSE either side of the south barricade, the KETTEN
## HOUSE on the tram street and the NORTH HOUSE by the north strongpoint.
## Three are garrisoned; the west one is empty.

const NAME := "OPERATION GORDIAN"
const NIGHT := false
const GROUND := "city"
const HALF := %(half)g
const START := Vector3(0, 0, 88)
const AT_TEAM := Vector3(38, 0, 44)        # rocket team in the south-east courtyard
const OBJECTIVE := "OPERATION GORDIAN  -  TAKE THE CROSSROADS  -  GATEWAYS LEAD THROUGH THE COURTYARDS (ROCKET TEAM: EAST YARD)"
const COMPLETE := "CROSSROADS SECURED  -  MISSION COMPLETE  -  R TO REPLAY"

## Shown on the BRIEFING tab of the field manual (and the first time you
## play the map). Markup: {h}heading{/h}, {k}key{/k}, {d}note{/d}.
const BRIEFING := """{h}SITUATION{/h}
A Berlin crossroads, 190 m across. {h}Gordianstrasse{/h} (asphalt, trees, parked cars) runs north from your start and crosses {h}Kettenstrasse{/h} (setts, tram rails, a tram standing east of the crossing). Five-storey houses wall in both streets. Five of them have a {h}carriage gateway{/h}: a dark tunnel through the house into the courtyard behind.

{h}MISSION{/h}
Take the crossroads: clear all eight positions, three of them inside houses.

{h}ENEMY{/h}
  - {h}Gordian South:{/h} a barricade across the street ahead of you (3 riflemen).
  - {h}Crossing:{/h} sandbags and a kiosk at the crossroads (3).
  - {h}Vacant lot:{/h} a gap in the houses on Kettenstrasse west, behind a hoarding (3).
  - {h}Ketten East:{/h} behind the tram (3), with the {h}APC{/h} patrolling the tram street.
  - {h}Gordian North:{/h} the strongpoint up the street (3).
  - Garrisons inside the {h}East House{/h} (3), {h}Ketten House{/h} (4) and {h}North House{/h} (4), firing from the windows.

{h}YOUR UNIT{/h}
Six men, two of them with flashbangs. The {h}anti-armor team{/h} waits in the east courtyard: through the gateway on your right at the brick house.

{h}SUGGESTED PLAN{/h}
  1. Don't walk up the middle of the street. Go through the gateway on your right into the east courtyard and pick up the anti-armor team.
  2. The East House backs onto that courtyard. Put the reticle on its back door and press {k}G{/k} to stack up, then {k}G{/k} again to go in. Clear it room by room.
  3. The {h}West House{/h}, across the street, is empty. A team in there ({k}C{/k} at the windows) can fire on the south barricade.
  4. From the east courtyard, a second gateway leads out onto Kettenstrasse behind the tram. Rockets for the APC.

{h}WATCH OUT FOR{/h}
  - Enemy flankers and reinforcements use the gateways too. Watch the ones behind you.
  - Inside 10 m the enemy is deadly. Use flashbangs and frags on defended rooms."""

const LAMPS := [%(lamps)s]

const BOXES := [
%(boxes)s
]

const AREAS := [
	{"name": "GORDIAN SOUTH", "center": Vector3(0, 0, 34), "radius": 13.0,
		"men": [Vector3(-2.6, 0, 34.8), Vector3(2.9, 0, 36.0), Vector3(8.4, 0, 34.2)]},
	{"name": "CROSSING", "center": Vector3(2, 0, -6), "radius": 17.0,
		"men": [Vector3(-3.4, 0, -10.2), Vector3(4.0, 0, -9.8), Vector3(19.6, 0, -1.5)]},
	{"name": "VACANT LOT", "center": Vector3(%(lot_x)g, 0, 20), "radius": 13.0,
		"men": [Vector3(%(lot_a)g, 0, 18.8), Vector3(%(lot_b)g, 0, 19.2), Vector3(%(lot_x)g, 0, 24.7)]},
	{"name": "KETTEN EAST", "center": Vector3(58, 0, -2), "radius": 18.0,
		"men": [Vector3(63.3, 0, -4.9), Vector3(66, 0, -5.5), Vector3(52.5, 0, -1.5)],
		"apc": [Vector3(46, 0, 3.4), Vector3(86, 0, 3.4)]},
	{"name": "GORDIAN NORTH", "center": Vector3(0, 0, -53), "radius": 17.0,
		"men": [Vector3(-2.6, 0, -45.2), Vector3(3.0, 0, -46.4), Vector3(0, 0, -59.5)]},
%(garrisons)s
]

## Houses with a real ground floor. "rect" is the footprint [x0, z0, x1, z1];
## the game builds the storeys above (and lifts them off when the squad is
## inside). ROOMS are [x0, z0, x1, z1, house]; DOORS are [centre, the way
## through from room a into room b, a, b], with -1 for outside.
const HOUSES := [
%(houses)s
]
const ROOMS := [
%(rooms)s
]
const DOORS := [
%(doors)s
]


## Scenery with no collision: gas lanterns, the tram's overhead wires, and
## the streets carrying on beyond the edge of the map.
static func build_extras(main: Node3D) -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.16, 0.13)
	iron.roughness = 0.6
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.85, 0.7)
	glass.roughness = 0.2
	for p in LAMPS:
		_box(main, Vector3(p.x, 2.0, p.y), Vector3(0.12, 4.0, 0.12), iron)
		_box(main, Vector3(p.x, 4.25, p.y), Vector3(0.42, 0.5, 0.42), glass)
		_box(main, Vector3(p.x, 4.55, p.y), Vector3(0.52, 0.1, 0.52), iron)
	# Contact wires over both tracks, span wires between the facades.
	for z in [-1.55, 1.55]:
		_box(main, Vector3(0, 5.8, z), Vector3(HALF * 2.0, 0.03, 0.03), iron)
	var x := -HALF + 8.0
	while x < HALF:
		_box(main, Vector3(x, 6.6, 0), Vector3(0.03, 0.03, 26.0), iron)
		x += 32.0
	# The streets go on: house rows beyond the four ends.
	var sh := Shader.new()
	sh.code = main.BUILDING_SHADER
	var tones := [Color(0.76, 0.7, 0.56), Color(0.62, 0.62, 0.58), Color(0.72, 0.66, 0.5), Color(0.56, 0.55, 0.51)]
	var k := 0
	for arm in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		for side in [-1.0, 1.0]:
			var along_x: bool = absf(arm.x) > 0.5
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(110, 21.5, 13) if along_x else Vector3(13, 21.5, 110)
			mi.mesh = bm
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("wall_col", tones[k %% tones.size()])
			m.set_shader_parameter("seed", float(k) * 7.3)
			m.set_shader_parameter("night", 0.0)
			mi.material_override = m
			mi.position = arm * (HALF + 55.5) + (Vector3(0, 0, side * 19.5) if along_x else Vector3(side * 17.5, 0, 0)) + Vector3(0, 10.75, 0)
			main.add_child(mi)
			k += 1


static func _box(main: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
''' % {"half": EDGE, "lamps": lamps, "boxes": "\n".join(lines), "garrisons": "\n".join(g_lines), "houses": "\n".join(h_lines), "rooms": "\n".join(r_lines), "doors": "\n".join(d_lines), "lot_x": round(mid, 1), "lot_a": round(mid + 4.5, 1), "lot_b": round(mid - 5.0, 1)}

path = os.path.join(ROOT, "scripts", "maps", "berlin_mission.gd")
open(path, "w").write(out)
print("wrote %s: %d boxes (%d parked cars of %d), %d houses with %d rooms and %d doors" % (os.path.relpath(path, ROOT), len(boxes), kept, len(L["cars"]), len(houses), len(rooms), len(doors)))
