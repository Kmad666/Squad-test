# Squad Test

Godot 4 third-person squad shooter prototype, playable in the browser (PC).
You command a squad of six soldiers as one unit. Each soldier picks its own target and fires on its own.

**Play:** https://kmad666.github.io/Squad-test/
**Modeller:** https://kmad666.github.io/Squad-test/modeller/ (build characters, weapons and buildings for the game)

## Controls
| Key | Action |
|---|---|
| WASD / arrows | Move the squad (loose cluster) |
| Mouse | Aim the raised camera (click to grab the mouse, Esc to release) |
| Hold left mouse | **Focus fire**: only targets inside the reticle; with none there, the squad saturates the area under it |
| Right click | **Special**: one click = the nearest man carrying the selected special throws / fires one at the reticle |
| 1 / 2 / 3 / 4 | Select special: frag, flashbang, grenade launcher, rocket |
| X | Next special that still has ammo |
| F1 | Show / hide the controls panel |
| Esc | Field manual: pauses and explains every mechanic (tabs; Esc again to resume) |
| F | Auto fire toggle: fire at will (each soldier picks any target he can see) |
| E | Move the squad to the spot under the reticle (WASD cancels); in cover, they go cover to cover |
| C / Space | Take cover against the direction the camera faces / leave cover. Cover stays on while you move: WASD / E go cover to cover |
| T | Split into fire teams A + B (helmet patches: A green, B amber) / join back up |
| Q | Switch which fire team you command (the other gives covering fire at will) |
| B | Bounding advance to the point under the reticle: teams leapfrog, one moves while one covers |
| H | Hold position: nobody moves, WASD scouts ahead with the camera (H again to release) |
| M | Next map (remembered) |
| Tab | Reticle settings (sizes are saved in your browser) |
| G | Graphics LOW / HIGH (LOW: no shadows or bloom, 70% 3D resolution, lighter screen effects; remembered) |
| V | RETRO graphics on / off (chunky low-poly soldiers, vertex wobble, pixelated dithered screen; remembered) |
| L | Weapon lights on / off (on by default at night; on LOW graphics only every third man's) |
| N | Night vision: green phosphor, amplified darks, grain, flicker, scan lines, round eyepiece edge |
| I | Thermal sight, inside the reticle only: bodies white-hot, everything else cold grey |
| R | Restart |
| Wheel | Zoom |

## How cover works
On the cover order, each soldier runs to the closest free spot behind a box, on the far side from where
the camera is facing (the arrow at the squad marker shows that direction). The squad's center pulls the choice so the
group stays together. In cover, soldiers crouch and pop up to fire over low crates. Behind tall crates they lean out past the edge to shoot, then duck back.
A man with no spot within reach goes prone where he is.

Cover is a persistent state of the unit: it stays in cover until you press C again. Moving while in cover (WASD or
E) goes **cover to cover**: the unit's point moves (never more than 6 m ahead of the men), each man heads for the
point plus his place in the spread the unit had when it took cover, and every 0.4 s takes the nearest free cover
spot within 4.5 m of there that shields him from where the camera faces, running low (x0.85 speed) between spots.
He keeps the spot he holds unless a new one is at least 1.5 m better. With no cover within reach he goes **prone and
crawls** (1 m/s) to where he's headed, and gets up again as soon as cover is in reach. Prone men fire from where
they lie once stopped, are hit x0.45 as often, take 40% less from blasts, and show only a low, small target.
Bounding advances still leave cover and run.

Every push to `main` builds the web version and publishes it to GitHub Pages (gh-pages branch).

Font: Share Tech Mono (SIL Open Font License, see `fonts/OFL.txt`).

## Units
- **Starting squad:** 5 riflemen + 1 grenadier (rifle with under-barrel grenade launcher).
- **Anti-armor team (coyote packs and kit):** 3 men with burst rifles and shoulder rocket launchers, waiting west of the start.
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
- Enemy riflemen (olive-brown camo, red armband, red mask lenses) and the APC shoot back (red tracers). The APC's turret tracks you with a machine gun and fires explosive cannon shells. Enemies need line of sight: a soldier crouched behind a low crate is hidden.
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
(prone instead: x0.45, crawling or not) x(1 - 0.75 x the shooter's suppression).

## Test field (daytime)
Three defended areas, each with a floating label showing hostiles left:
- **ALPHA** (west): 2 riflemen behind a sandbag line.
- **BRAVO** (centre checkpoint): 3 riflemen.
- **CHARLIE** (east motor pool): 2 riflemen + the APC, which patrols the lane behind it.

The anti-armor team waits north-west of the start. Enemies stand at their posts until they spot you (within 45 m)
or take fire; then the whole area alerts. Alerted riflemen run to cover that shields them from your squad, peek
to shoot (leaning around tall crates), stay down when pinned, move when you flank them, and fall back when wounded.
The APC stops patrolling to fight. Night lighting is still in the code (`NIGHT` in `scripts/atmosphere.gd`).

## Tests
Headless tests live in `tests/` (not included in the web build). Every push runs them on GitHub before deploying;
if they fail, the live game stays on the last good version.

```
GODOT=/path/to/godot tests/run_all.sh          # MINUTES=10 for longer soak runs
```
- `battle_test.gd`: scripted advance through all three areas, prints squad health and enemy states every 10 s.
- `lean_spot_test.gd`: checks no two soldiers share a lean-out spot at tall crates.
- `manual_test.gd`: Esc opens / pages / closes the field manual and pauses / unpauses.
- `mission_test.gd`: scripted run of the street mission using split, bound and flank orders.
- `model_test.gd`: geometry checks on the soldier model in every pose and gait: torso attached to hips,
  feet never below ground, legs never over-stretched, feet never crossing, both hands on the rifle, corpses resting
  on the ground with the rifle beside them, and prone / crawling bodies (HD and RETRO) lying on the ground without
  sinking into it, rifle pointed ahead.
- `cover_move_test.gd`: persistent cover on the test field: the unit stays in cover while you move it, men go cover
  to cover, go prone and crawl in the open, prone men are harder to hit, and leaving cover stands everyone up.
- `death_test.gd`: in-game edge cases on both maps: men killed mid-run, mid-signal and crouched, the sergeant killed
  (one heir promoted), crouch toggled every frame, enemies killed while peeking.
- `soak_test.gd`: random orders (including split / switch / bound / hold), WASD bursts in and out of cover, cover toggles, fire modes, specials, graphics toggles and restarts; fails on any script error.

## Maps
- **OPERATION LAMPLIGHTER** (default, night): a street between two rows of buildings, a back alley joined to the road
  by two side passages, and a walled compound at the end of the road (gate on the road, breach at the alley mouth).
  Cars, crates, dumpsters and barriers for cover; sodium street lamps, lit windows and a floodlight over the gate.
  Enemies: a ROADBLOCK mid-street (2), an ALLEY ambush (2), the COMPOUND (4 + APC). The anti-armor team waits in the
  first side passage. At night enemies only spot you within 35 m. Objective: secure the compound.
- **TEST FIELD** (day): open ground with three small enemy positions, for tuning mechanics.
- **MODEL VIEWER** (day, no enemies): every variant of the universal soldier (`scripts/soldier_model.gd`) on a
  turntable in its idle pose: rifleman, sergeant, grenadier, rocketman, enemy, crouched, and a hand-signal loop;
  then the gaits, firing poses, and prone (lying still, crawling, firing prone).

## Soldier model
One universal soldier (`soldier_model.gd`) is built for everyone, friend and foe: a jointed body (hips, torso, head,
two-bone IK arms and legs). The look (`soldier_parts.gd`): urban-camo fatigues, full gas mask (lenses, rims, side
filter, exhale valve, harness straps) over a balaclava, headset, high-cut helmet with cover, NVG mount, side rails and
counterweight pouch, plate carrier with MOLLE, mag / frag / radio / admin pouches, battle belt with holster, IFAK and
dump pouch, assault pack with hydration tube, elbow and knee pads, gloves, boots; M4-pattern carbines (holo sight,
rail, M-LOK) for your men, AK-pattern rifles for the enemy.
Shapes come from a small procedural kit (`model_kit.gd`: superellipsoids, lofted limbs, a cut helmet shell, tubes)
baked into one vertex-coloured mesh per bone; the vertex alpha is a material ID read by `shaders/soldier.gdshader`
(camo fabric with procedural blotches and weave bump, webbing, rubber, metal, glass; mask lenses glow at night).
Each bone carries a close-up mesh (~13k triangles per soldier) and a far one (~4k) that swap at 14 m (4 m on LOW
graphics, which also drops the camo/bump noise); meshes are cached per kit variant.
RETRO graphics (V) swap in `soldier_parts_retro.gd`: an original late-90s console-style version of the same soldier
on the same bones (~950 faceted triangles, chunky proportions, baked vertex lighting, bold lens colours), drawn with
`shaders/soldier_retro.gdshader` (per-vertex lighting, vertices snapped to a 3-pixel screen grid); the post effect
adds 3x3 screen pixels and 5-bit-per-channel ordered dithering.
Variants: friendlies in dark grey with charcoal / black / wolf-grey kit mixed per man and green lenses; the rocket
team with coyote pack, pouches and tube; enemies in olive-brown camo, black kit, red lenses and a red armband.
Grenade launcher and magnified optic for the grenadier, recoilless rifle slung on the rocketman's back, amber
chevrons and a whip antenna for the sergeant.
Movement: a procedural gait driven by each body's real velocity (`animate()`, called every physics frame):
feet alternate planted / swinging steps along the direction of travel, stride and cadence scale with speed,
running adds a forward lean, lower hips and a heel kick, crouching gives short low steps, and when strafing or
backing up the hips turn toward travel while the torso keeps facing the enemy. Crouch transitions ease in.
Aiming: `set_aim_point(world point | Vector3.INF)` while engaging raises the rifle to the shoulder (bladed stance,
torso turns with the aim, cheek on the stock, works through crouch / gait / lean); `recoil()` on each shot kicks the
muzzle up. Friendlies shoulder when they have a shot and may fire; enemies when their gunner has a target and is up.
Poses: idle (rifle at low ready), crouch (hips drop, torso leans forward from the waist, rifle stays level),
prone (`set_prone()`: the whole body pivots forward about the hips onto the ground over ~0.5 s, angled off the line
of fire with the chest up on the elbows, rifle shouldered and pointed ahead, legs apart with toes pointed; crawling,
each knee in turn is drawn up and out along the ground while the shoulders roll and the elbows take turns forward),
left-hand signals, and dead (your men sprawl face down; enemies fall back onto their side; the rifle drops beside
the body and the body is fitted to the ground so nothing sinks or floats).

Vision: weapon lights are shadowless SpotLight3Ds on each friendly rifle (`soldier.gd`). Night vision is a post
effect (`postfx.gd`). Thermal: inside the reticle (its screen rect is passed to both soldier shaders and the post
effect) the soldier shaders drop their lighting and emit a yellow, no-blue "heat" colour kept under the bloom
threshold; the post effect turns that (and other hot, warm-saturated light such as lamps and flashes) white and
everything else cold grey, so only the reticle shows thermal.

`tests/tools/capture_vision.gd` screenshots lights / night vision / thermal / both (MAP=0 night, MAP=1 day, RETRO=1).
`tests/tools/render_gait.gd` renders each gait at six points of its stride; `tests/tools/render_prone.gd` the drop
to prone, the prone pose from five sides and the crawl cycle; `tests/tools/capture_game.gd`
screenshots the real game mid-move. `tests/tools/render_models.gd` renders close-ups of every pose from several angles for visual review (needs a real
renderer, e.g. under `xvfb-run`; usage is in the file). Not part of the test suite.

Maps live in `scripts/maps/`. Each lists its boxes (`building`, `cwall`, `car`, `crate`, `dumpster`, `barrier`,
`sandbag`, `wall`, `tall`), enemy areas, start point, anti-armor team spot, and adds its own lights.

## Specials (limited ammo)
Every rifleman carries one hand grenade (frags and flashbangs, mixed), the grenadier 6 launcher rounds, each
rocket man 2 rockets. One right click = one man uses one special of the selected kind on the reticle (an enemy
inside it that the special can reach, or the ground under it); aimed past his range, he throws as far as he can
that way. Rockets go to a man with a clear line of fire when possible. If the selected
kind is empty, the click switches to the next kind with ammo and uses it. When the whole unit is out, right click
only flashes NO EXPLOSIVES LEFT. Flashbangs do no damage but blind (no shooting) and pin enemies in a 7 m radius
for 3.5 s. The bar at the bottom shows what's left; the panel bottom-right shows every man's health and special.

## Sergeant, hand signals and reaction time
One soldier is the sergeant (amber chevrons, radio antenna, SGT in the squad panel). Orders go through his left-hand
signals: move out (forward chop), halt (raised fist), take cover (palm-down pump), open fire (points at the reticle).
Each man reacts after 0.22 s + 0.065 s per metre from his team leader (+ a little random); the leader reacts in ~0.1 s.
Men accelerate and slow with weight, run for cover at a heavier pace, and when leaving cover move low and slow for
~2 s while firing at enemies inside the reticle. A newer order cancels any reaction still pending from an older one.
If the sergeant falls, a rifleman takes over; a split team without him is signalled by its first man.

## Squad Modeller (`modeller/`)
A browser tool for building PSX-style models from parts, Spore-style: drag body parts, gear, armour, weapon
pieces or building pieces onto the model, recolour them (main / pattern ink / trim / detail, 16 pixel
patterns), and reshape them with size, taper, bulge, bend, lean, twist and sides sliders. Symmetry gives
every part a mirrored twin. **Edit points** (V) moves individual corners. **Import** (or drag a .glb onto the
page) adds any .glb as a part in its own colours (material x texture colour per triangle, exported as vertex
colours), stood on its base, rescaled if huge or tiny, capped at 4000 triangles, with a Simplify slider (vertex
clustering); the mesh is stored inside the design. Three modes:
- **Character**: built directly on this game's soldier skeleton (bones and spaces ported from
  `scripts/soldier_model.gd`), so parts follow the game's gait, crouch, aim and death poses with no rigging
  step. The pose menu previews *Rifle ready* and *Walk* with the same maths.
- **Weapon**: grip at the origin, barrel toward -Z (rifle space); ghost hands show where the soldier holds it;
  a *Muzzle point* marks where shots leave.
- **Building**: pieces on a 0.25 m grid, 1 m squares, origin at ground level.

**Export .glb** writes one mesh per bone (`hips`, `torso`, `head`, `upper_arm_L/R`, `forearm_L/R`,
`thigh_L/R`, `shin_L/R`, `foot_L/R`) in that bone's own space, under a `Character` root; weapons as `rifle`
with a `muzzle` child; buildings as `building`. Textures are embedded with nearest filtering, and the
editable design is stored in the scene extras so a .glb reopens in the modeller. Designs also save as
`.squadmodel.json` and autosave in the browser.

Plain HTML + JavaScript (three.js r170 vendored in `modeller/vendor/`, MIT), no build step. `modeller/.gdignore`
keeps Godot from importing it; the deploy workflow copies it to `/modeller/` on GitHub Pages.
Local run: `python3 -m http.server` inside `modeller/`, then open http://localhost:8000.
