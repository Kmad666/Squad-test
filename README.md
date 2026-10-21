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
| C / Space | Take cover against the direction the camera faces / leave cover (moving also leaves cover) |
| Tab | Reticle settings (sizes are saved in your browser) |
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
