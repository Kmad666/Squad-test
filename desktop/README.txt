SQUAD TEST - desktop build

Windows: run SquadTest.exe. Windows may warn that the app is from an unknown
publisher (it isn't code-signed): click "More info", then "Run anyway".
Linux: run ./SquadTest.x86_64

The desktop build uses the full renderer (Vulkan, or Direct3D 12 on Windows):
volumetric mist so lamps and weapon lights throw visible beams at night,
shadow-casting weapon lights, ambient occlusion, every man's light on even on
LOW graphics. HUD shows "DESKTOP" when it's active.

Weak or integrated graphics? Use SquadTest-LowEnd (.bat on Windows, .sh on
Linux): it runs the same game on the lighter browser renderer. G in game
still switches HIGH / LOW graphics.

Settings (graphics, reticle, last map) are saved per user, separately from
the browser version.
