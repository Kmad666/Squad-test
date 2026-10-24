#!/bin/sh
# Squad Test on the browser's lighter renderer (OpenGL, compatibility).
# Use this if SquadTest.x86_64 is slow or won't start on a weak / integrated GPU.
cd "$(dirname "$0")" && exec ./SquadTest.x86_64 --rendering-driver opengl3 --rendering-method gl_compatibility "$@"
