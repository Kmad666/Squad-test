#!/usr/bin/env bash
# Headless test suite. Usage: GODOT=/path/to/godot tests/run_all.sh
# Runs at a fixed 60 fps as fast as the CPU allows (minutes of game time in seconds).
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --import >/dev/null 2>&1
fail=0
for t in battle_test lean_spot_test; do
  echo "== $t"
  out=$("$GODOT" --headless --fixed-fps 60 -s "tests/$t.gd" 2>&1)
  echo "$out" | grep -v "^Godot" | grep -v "^$" | tail -15
  if echo "$out" | grep -q "SCRIPT ERROR\|^ERROR"; then fail=1; fi
done
for seed in 1 2 3; do
  echo "== soak seed $seed (${MINUTES:-5} min game time)"
  out=$(SEED=$seed "$GODOT" --headless --fixed-fps 60 -s tests/soak_test.gd 2>&1)
  echo "$out" | grep "^done"
  if echo "$out" | grep -q "SCRIPT ERROR\|^ERROR"; then fail=1; echo "$out" | grep -A3 "ERROR" | head -20; fi
done
[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "FAILURES"; exit 1; }
