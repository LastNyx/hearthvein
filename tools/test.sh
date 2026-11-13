#!/usr/bin/env bash
# Run GUT headless. Usage: tools/test.sh [test/test_file.gd]
# No argument runs every test under test/. Exits with GUT's exit code.
set -u
cd "$(dirname "$0")/.."

if [ ! -f .godot/global_script_class_cache.cfg ]; then
	godot --headless --import >/dev/null 2>&1
fi

args=(--headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json)
if [ $# -ge 1 ]; then
	args+=("-gselect=$(basename "$1")")
fi
exec godot "${args[@]}"
