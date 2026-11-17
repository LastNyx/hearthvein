#!/usr/bin/env bash
# Run GUT headless. Usage: tools/test.sh [test/test_file.gd]
# No argument runs every test under test/. Exits with GUT's exit code, or 1 if any script failed to
# parse/load (GUT can still exit 0 then).
set -u
cd "$(dirname "$0")/.."

# Always import first so new class_name scripts are registered (about 4 s).
godot --headless --import >/dev/null 2>&1

args=(--headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json)
if [ $# -ge 1 ]; then
	args+=("-gselect=$(basename "$1")")
fi
log=$(mktemp)
godot "${args[@]}" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
if grep -qE "Parse Error|Failed to load script|SCRIPT ERROR" "$log"; then
	echo "tools/test.sh: script errors found above, failing the run" >&2
	[ "$code" -eq 0 ] && code=1
fi
rm -f "$log"
exit "$code"
