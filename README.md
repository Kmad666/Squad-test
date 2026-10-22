# Squad Test

Godot 4 third-person squad shooter prototype, playable in the browser (PC).
You command a squad of six soldiers as one unit. Each soldier picks its own target and fires on its own.

**Play:** https://kmad666.github.io/Squad-test/

## Controls
| Key | Action |
|---|---|
| WASD / arrows | Move the squad (loose cluster) |
| Mouse | Aim the raised camera (click to grab the mouse, Esc to release) |
| Hold left mouse | **Focus fire**: only targets inside the reticle; with none there, the squad saturates the area under it |
| Hold right mouse | **Specials**: grenadiers and rocket teams fire their launchers at the reticle |
| F | Auto fire toggle: fire at will (each soldier picks any target he can see) |
| E | Move the squad to the spot under the reticle (WASD cancels) |
| C / Space | Take cover against the direction the camera faces / leave cover (moving also leaves cover) |
| Tab | Reticle settings (sizes are saved in your browser) |
| R | Restart |
| Wheel | Zoom |

## How cover works
On the cover order, each soldier runs to the closest free spot behind a box, on the far side from where
the camera is facing (the arrow at the squad marker shows that direction). The squad's center pulls the choice so the
group stays together. In cover, soldiers crouch and pop up to fire over low crates. Behind tall crates they lean out past the edge to shoot, then duck back.

Every push to `main` builds the web version and publishes it to GitHub Pages (gh-pages branch).

Font: Share Tech Mono (SIL Open Font License, see `fonts/OFL.txt`).

## Units
- **Starting squad:** 5 riflemen + 1 grenadier (rifle with under-barrel grenade launcher).
- **Anti-armor team (tan uniforms):** 3 men with burst rifles and shoulder rocket launchers, waiting west of the start.
  Walk the squad up to them and they join.
- **Enemy APC** (behind the dummies): heavy armor, 360 HP. Bullets ricochet, grenades do 15, rockets do 120. Rebuilds 20 s after it's destroyed.

## Hit chance
Every shot rolls to hit. Chance = weapon accuracy x range falloff x target size x modifiers, clamped 3%-95%.

| Weapon | Accuracy | Effective / max range | Damage (infantry / armor) | Notes |
|---|---|---|---|---|
| Rifle | 55% | 30 / 70 m | 1 / 0 | 2-4 round bursts |
| Burst rifle | 65% | 40 / 75 m | 1.2 / 0 | 3-round bursts |
| Grenade launcher | 45% | 25 / 55 m | 10 / 15, 4 m blast | lobbed over cover, 2.5 s reload |
| Rocket launcher | 70% | 45 / 90 m | 20 / 120, 3 m blast | x0.55 vs infantry, 5 s reload |

Modifiers: beyond effective range accuracy falls to 30% at max range; vehicle targets x1.7 (big); shooter moving x0.6;
aimed fire (focus fire, launchers) x1.15; follow-up rounds in a burst x0.85. Missed launcher shots land a few metres off,
so the blast can still catch the target.

## Enemy fire, health and suppression
- Enemy riflemen (grey, red armband) and the APC shoot back (red tracers). The APC's turret tracks you with a machine gun and fires explosive cannon shells. Enemies need line of sight: a soldier crouched behind a low crate is hidden.
- Soldiers have 100 HP. Below 50 they're **wounded** (slower, less accurate); at 0 they're **down** and leave the squad.
- **Suppression** (both sides): rounds snapping past within ~2 m build it up; it fades ~1.5 s after the fire stops.
  Suppressed soldiers peek less and shoot worse; **pinned** soldiers stay down. Suppressed enemies fire slower and
  worse; pinned enemies stop firing. Focus fire is how you pin a target, then flank or blow it up.
- Squares over enemies inside the reticle show what the squad will engage (thicker = currently being shot at),
  with an amber suppression bar underneath.

| Enemy weapon | Accuracy | Effective / max range | Damage |
|---|---|---|---|
| Enemy rifle | 32% | 30 / 58 m | 16 |
| APC machine gun | 30% | 40 / 65 m | 14 |
| APC cannon | 50% | 45 / 70 m | 55, 3.5 m blast (x0.3 behind cover), 7 s reload |

Enemy hit chance: weapon accuracy x range falloff x0.75 vs moving soldiers x0.6 vs soldiers fighting from cover
x(1 - 0.75 x the shooter's suppression).

## Test field (daytime)
Three defended areas, each with a floating label showing hostiles left:
- **ALPHA** (west): 2 riflemen behind a sandbag line.
- **BRAVO** (centre checkpoint): 3 riflemen.
- **CHARLIE** (east motor pool): 2 riflemen + the APC, which patrols the lane behind it.

The anti-armor team waits north-west of the start. Enemies stand at their posts until they spot you (within 45 m)
or take fire; then the whole area alerts. Alerted riflemen run to cover that shields them from your squad, peek
to shoot (leaning around tall crates), stay down when pinned, move when you flank them, and fall back when wounded.
The APC stops patrolling to fight. Night lighting is still in the code (`NIGHT` in `scripts/atmosphere.gd`).
