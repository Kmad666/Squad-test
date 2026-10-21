# Squad Test

Godot 4 third-person squad shooter prototype, playable in the browser (PC).
You command a squad of six soldiers as one unit. Each soldier picks its own target and fires on its own.

**Play:** https://kmad666.github.io/Squad-test/

## Controls
| Key | Action |
|---|---|
| WASD / arrows | Move the squad (loose cluster around the ring marker) |
| Mouse | Aim the raised camera (click to grab the mouse, Esc to release) |
| Hold left mouse | **Focus fire**: only targets inside the reticle; with none there, the squad saturates the area under it |
| Hold right mouse | **Fire at will**: each soldier picks any target he can see |
| F | Auto fire toggle (permanent fire at will) |
| C / Space | Take cover against the direction the camera faces / leave cover (moving also leaves cover) |
| Tab | Reticle settings (sizes are saved in your browser) |
| Wheel | Zoom |

## How cover works
On the cover order, each soldier runs to the closest free spot behind a box, on the far side from where
the camera is facing (the arrow at the squad marker shows that direction). The squad's center pulls the choice so the
group stays together. In cover, soldiers crouch and pop up to fire over low crates. Behind tall crates they lean out past the edge to shoot, then duck back.

Every push to `main` builds the web version and publishes it to GitHub Pages (gh-pages branch).

Font: Share Tech Mono (SIL Open Font License, see `fonts/OFL.txt`).
