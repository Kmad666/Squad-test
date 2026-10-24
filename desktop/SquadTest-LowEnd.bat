@echo off
rem Squad Test on the browser's lighter renderer (OpenGL, compatibility).
rem Use this if SquadTest.exe is slow or won't start on a weak / integrated GPU.
start "" "%~dp0SquadTest.exe" --rendering-driver opengl3 --rendering-method gl_compatibility
