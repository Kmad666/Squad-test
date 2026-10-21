extends RefCounted
## Weapon stats and the hit-chance model.
##
## Every shot rolls against a hit chance:
##   base accuracy (weapon)
##   x range falloff  (full inside effective range, down to 30% at max range)
##   x target size    (infantry 1.0, vehicle 1.7: big targets are easier to hit)
##   x weapon vs target (rockets are clumsy against infantry: x0.55)
##   x shooter moving x0.6, aimed (focus fire / specials) x1.15,
##     follow-up shots in a burst x0.85 (recoil)
## clamped to 3%..95%, so nothing is ever guaranteed.
##
## Damage: "soft" applies to infantry, "armor" to vehicles. Small arms do
## nothing to armor (they ricochet); rockets are built for it.

const RIFLE := {
	"name": "RIFLE", "kind": "bullet",
	"acc": 0.55, "eff": 30.0, "max": 70.0,
	"soft": 1.0, "armor": 0.0,
	"burst_min": 2, "burst_max": 4, "cycle": 0.1, "pause_min": 0.5, "pause_max": 1.1,
}

const BURST_RIFLE := {
	"name": "BURST RIFLE", "kind": "bullet",
	"acc": 0.65, "eff": 40.0, "max": 75.0,
	"soft": 1.2, "armor": 0.0,
	"burst_min": 3, "burst_max": 3, "cycle": 0.07, "pause_min": 0.55, "pause_max": 0.9,
}

const GRENADE_LAUNCHER := {
	"name": "GRENADE LAUNCHER", "kind": "grenade",
	"acc": 0.45, "eff": 25.0, "max": 55.0,
	"soft": 10.0, "armor": 15.0, "radius": 4.0,
	"reload": 2.5, "speed": 22.0,
}

const ROCKET_LAUNCHER := {
	"name": "ROCKET LAUNCHER", "kind": "rocket",
	"acc": 0.7, "eff": 45.0, "max": 90.0,
	"soft": 20.0, "armor": 120.0, "radius": 3.0,
	"reload": 5.0, "speed": 45.0, "vs_infantry": 0.55,
}

## role -> [primary, secondary (empty = none)]
const ROLES := {
	"rifleman": [RIFLE, {}],
	"grenadier": [RIFLE, GRENADE_LAUNCHER],
	"anti_armor": [BURST_RIFLE, ROCKET_LAUNCHER],
}


static func hit_chance(w: Dictionary, target: Node3D, dist: float, moving: bool, aimed: bool, followup: bool) -> float:
	if dist > w["max"]:
		return 0.0
	var p: float = w["acc"]
	if dist > w["eff"]:
		p *= lerpf(1.0, 0.3, clampf((dist - w["eff"]) / (w["max"] - w["eff"]), 0.0, 1.0))
	p *= target.size_factor
	if target.kind == "infantry":
		p *= w.get("vs_infantry", 1.0)
	if moving:
		p *= 0.6
	if aimed:
		p *= 1.15
	if followup:
		p *= 0.85
	return clampf(p, 0.03, 0.95)
