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


# ---------------------------------------------------------------- enemy weapons
# "soft" is damage to a soldier (100 HP). "suppress" is how much a round
# passing close to a soldier rattles him (hits rattle more).

const ENEMY_RIFLE := {
	"name": "ENEMY RIFLE", "kind": "bullet",
	"acc": 0.32, "eff": 30.0, "max": 58.0,
	"soft": 16.0, "armor": 0.0, "suppress": 0.1,
	"burst_min": 2, "burst_max": 3, "cycle": 0.12, "pause_min": 1.4, "pause_max": 2.6,
}

const APC_MG := {
	"name": "APC MACHINE GUN", "kind": "bullet",
	"acc": 0.3, "eff": 40.0, "max": 65.0,
	"soft": 14.0, "armor": 0.0, "suppress": 0.14,
	"burst_min": 4, "burst_max": 7, "cycle": 0.09, "pause_min": 1.2, "pause_max": 2.0,
}

const APC_CANNON := {
	"name": "APC CANNON", "kind": "shell",
	"acc": 0.5, "eff": 45.0, "max": 70.0,
	"soft": 55.0, "armor": 0.0, "radius": 3.5, "suppress": 0.5,
	"reload": 7.0, "speed": 60.0,
}


## Enemy shots at a soldier: weapon accuracy x range falloff,
## x0.75 if the soldier is moving, x0.6 if he's fighting from cover
## (only part of him shows), x(1 - 0.75 x the shooter's own suppression).
static func enemy_hit_chance(w: Dictionary, soldier: Node3D, dist: float, own_suppression: float) -> float:
	if dist > w["max"]:
		return 0.0
	var p: float = w["acc"]
	if dist > w["eff"]:
		p *= lerpf(1.0, 0.3, clampf((dist - w["eff"]) / (w["max"] - w["eff"]), 0.0, 1.0))
	if soldier.is_moving():
		p *= 0.75
	if soldier.is_in_cover():
		p *= 0.6
	p *= 1.0 - 0.75 * own_suppression
	return clampf(p, 0.02, 0.9)
