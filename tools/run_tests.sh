#!/usr/bin/env bash
# Headless unit tests for game logic. Complements tools/smoke_test.sh (which only
# boots scenes). Runs the dependency-free GDScript test runner under res://tests/.
#
# Usage:  tools/run_tests.sh
# Requires the `godot` binary on PATH (Godot 4.4+).
set -u
cd "$(dirname "$0")/.."

echo "== importing assets =="
godot --headless --import >/dev/null 2>&1

echo "== running unit tests =="
# The runner prints results and quit()s with a non-zero code on any failure.
godot --headless --script res://tests/run_tests.gd
exit $?
