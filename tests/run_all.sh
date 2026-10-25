#!/usr/bin/env bash
# Headless test suite. Usage: GODOT=/path/to/godot tests/run_all.sh
# Runs at a fixed 60 fps as fast as the CPU allows (minutes of game time in seconds).
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "FAILURES: Godot not found ('$GODOT'); set GODOT=/path/to/godot"; exit 1
fi
"$GODOT" --headless --import >/dev/null 2>&1
# A test whose script fails to compile never quits: cap each run so CI fails instead of hanging.
if command -v timeout >/dev/null 2>&1; then GODOT_RUN="timeout ${TEST_TIMEOUT:-900} $GODOT"; else GODOT_RUN="$GODOT"; fi
fail=0
for t in model_test menu_test battle_test lean_spot_test cover_move_test hud_test lav_test mission_test bridge_test manual_test; do
  echo "== $t"
  out=$($GODOT_RUN --headless --fixed-fps 60 -s "tests/$t.gd" 2>&1); code=$?
  echo "$out" | grep -v "^Godot" | grep -v "^$" | tail -15
  if [ $code -ne 0 ] || echo "$out" | grep -q "SCRIPT ERROR\|^ERROR"; then fail=1; echo "!! $t failed (exit $code)"; fi
done
for map in 0 1 3 4; do
  echo "== death_test map $map"
  out=$(MAP=$map $GODOT_RUN --headless --fixed-fps 60 -s tests/death_test.gd 2>&1); code=$?
  echo "$out" | grep -E "FAIL|failures|corpses"
  if [ $code -ne 0 ] || echo "$out" | grep -q "SCRIPT ERROR\|^ERROR"; then fail=1; echo "!! death_test map $map failed (exit $code)"; fi
done
for run in "1 0" "2 1" "3 0" "4 1" "5 3" "6 4"; do
  set -- $run
  seed=$1; map=$2
  echo "== soak seed $seed map $map (${MINUTES:-5} min game time)"
  out=$(SEED=$seed MAP=$map $GODOT_RUN --headless --fixed-fps 60 -s tests/soak_test.gd 2>&1); code=$?
  echo "$out" | grep "^done" || { fail=1; echo "!! soak never finished"; }
  if [ $code -ne 0 ] || echo "$out" | grep -q "SCRIPT ERROR\|^ERROR"; then fail=1; echo "$out" | grep -A3 "ERROR" | head -20; fi
done
[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "FAILURES"; exit 1; }
