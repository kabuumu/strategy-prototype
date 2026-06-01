#!/usr/bin/env bash
# Headless smoke test: import assets, then boot every scene for a few frames and
# fail if any logs a script/parse error. Catches the most common breakage (a
# scene that no longer compiles or crashes in _ready) without the editor.
#
# Usage:  tools/smoke_test.sh
# Requires the `godot` binary on PATH (Godot 4.4+).
set -u
cd "$(dirname "$0")/.."

SCENES=(
	src/title/title.tscn
	src/level_select/level_select.tscn
	src/autobattler/autobattler.tscn
)

echo "== importing assets =="
godot --headless --import >/dev/null 2>&1

fail=0
echo "== booting scenes =="
for scene in "${SCENES[@]}"; do
	out=$(godot --headless --quit-after 3 "$scene" 2>&1 \
		| grep -iE "SCRIPT ERROR|Parse Error|nonexistent|null instance|Invalid call|can't" \
		| grep -v "Godot Engine")
	if [ -n "$out" ]; then
		printf "  FAIL  %-34s %s\n" "$scene" "$(echo "$out" | head -1)"
		fail=1
	else
		printf "  ok    %s\n" "$scene"
	fi
done

if [ "$fail" -ne 0 ]; then
	echo "== SMOKE TEST FAILED =="
	exit 1
fi
echo "== all scenes booted clean =="
