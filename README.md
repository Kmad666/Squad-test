# Squad Test

Godot 4 third-person squad shooter prototype, playable in the browser (PC).
You command a squad of six soldiers as one unit. Each soldier picks its own target and fires on its own.

**Play:** https://kmad666.github.io/Squad-test/

## Controls
| Key | Action |
|---|---|
| WASD / arrows | Move the squad (loose cluster around the yellow marker) |
| Mouse | Orbit the camera (click to grab the mouse, Esc to release) |
| Wheel | Zoom |
| C / Space | Take cover / leave cover (moving also leaves cover) |
| F | Toggle hold fire |

## How cover works
On the cover order, each soldier runs to the closest free spot behind a box, on the far side from the
nearest target dummy (or from where the camera faces). The squad's center pulls the choice so the
group stays together. In cover, soldiers crouch and pop up to fire over low crates. Behind tall crates they lean out past the edge to shoot, then duck back.

Every push to `main` builds the web version and publishes it to GitHub Pages (gh-pages branch).
