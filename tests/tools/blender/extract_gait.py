## One averaged, looping gait cycle per clip: per foot (forward, lateral,
## height, pitch) relative to the hips, and hips (bob, sway, surge, roll,
## yaw), N samples from a left-foot plant, positions in units of leg length.
import bpy, sys, os, json, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
outp = argv[0]
clips = dict(a.split("=") for a in argv[1:])
N = 32
res = {}
for key, f in clips.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=f)
    a = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    pb = a.pose.bones
    fr = a.animation_data.action.frame_range
    sc = bpy.context.scene
    fps = sc.render.fps
    fr0, fr1 = int(fr[0]), int(fr[1])
    D = []
    for fi in range(fr0, fr1 + 1):
        sc.frame_set(fi)
        g = lambda n, tail=False: (a.matrix_world @ (pb[n].tail if tail else pb[n].head)).copy()
        hm = a.matrix_world @ pb["Hips"].matrix
        D.append({"H": g("Hips"), "LA": g("LeftFoot"), "RA": g("RightFoot"), "LT": g("LeftToe"), "RT": g("RightToe"),
                  "LH": g("LeftThigh"), "RH": g("RightThigh"), "Hx": (hm.to_3x3() @ Vector((1, 0, 0))).normalized()})
    zl = sorted(d["LA"].z for d in D)[len(D) // 20]
    zr = sorted(d["RA"].z for d in D)[len(D) // 20]
    plant = [d["LA"].z < zl + 0.03 for d in D]
    starts = [i for i in range(1, len(D)) if plant[i] and not plant[i - 1]]
    per = [starts[i + 1] - starts[i] for i in range(len(starts) - 1)]
    med = sorted(per)[len(per) // 2]
    good = [i for i in range(len(per)) if abs(per[i] - med) <= 2]
    # longest run of consecutive good cycles
    best, cur = [], []
    for i in good:
        cur = cur + [i] if cur and i == cur[-1] + 1 else [i]
        if len(cur) > len(best): best = list(cur)
    cyc = best[:6]
    # leg length: hip joint to ankle at mid-stance
    legs = []
    acc = None
    strides = []
    for ci in cyc:
        s0, s1 = starts[ci], starts[ci + 1]
        travel = D[s1]["H"] - D[s0]["H"]; travel.z = 0
        fwd = travel.normalized(); up = Vector((0, 0, 1)); right = fwd.cross(up).normalized()
        strides.append(travel.length)
        T = (s1 - s0)
        rows = []
        for k in range(N):
            t = s0 + T * k / N
            i0 = int(t); fr_ = t - i0; i1 = min(i0 + 1, len(D) - 1)
            L = lambda n: D[i0][n].lerp(D[i1][n], fr_)
            H = L("H")
            base = D[s0]["H"] + travel * (k / N)          # where the hips would be at steady speed
            row = []
            for s, z0 in (("L", zl), ("R", zr)):
                A = L(s + "A"); Tt = L(s + "T")
                rel = A - H
                ft = Tt - A
                pitch = math.atan2(ft.z, ft.dot(fwd))
                row += [rel.dot(fwd), rel.dot(right), A.z - z0, pitch]
            hx = L("Hx")
            yaw = math.atan2(hx.dot(fwd), hx.dot(right))       # hips turned off the travel line
            roll = math.asin(max(-1, min(1, hx.z)))
            d = H - base
            row += [H.z, d.dot(right), d.dot(fwd), roll, yaw]
            rows.append(row)
        for s in ("L", "R"):
            mid = D[s0 + T // 4] if s == "L" else D[s0 + 3 * T // 4]
            legs.append((mid[s + "H"] - mid[s + "A"]).length)
        acc = rows if acc is None else [[x + y for x, y in zip(r1, r2)] for r1, r2 in zip(acc, rows)]
    n = len(cyc)
    rows = [[x / n for x in r] for r in acc]
    leg = sum(legs) / len(legs)
    hz = sum(r[8] for r in rows) / N
    pitch0 = [sorted(r[3] for r in rows)[N // 2], sorted(r[7] for r in rows)[N // 2]]
    out = []
    for r in rows:
        out.append([round(r[0] / leg, 4), round(r[1] / leg, 4), round(r[2] / leg, 4), round(r[3], 4),
                    round(r[4] / leg, 4), round(r[5] / leg, 4), round(r[6] / leg, 4), round(r[7], 4),
                    round((r[8] - hz) / leg, 4), round(r[9] / leg, 4), round(r[10] / leg, 4), round(r[11], 4), round(r[12], 4)])
    T = med / fps
    stride = sum(strides) / len(strides)
    res[key] = {"cycle_s": round(T, 3), "stride_legs": round(stride / leg, 3), "speed_mps": round(stride / T, 2),
                "leg_m": round(leg, 3), "cycles_used": n, "flat_pitch": [round(p, 3) for p in pitch0], "rows": out}
    print(key, {k: v for k, v in res[key].items() if k != "rows"})
json.dump(res, open(outp, "w"))
