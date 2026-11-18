# Hearthvein

A Godot 4 city builder. Design docs are in `docs/`.

## Run and test

Requires Godot 4.7.2 (standard, non-.NET build) as `godot` on your PATH.

- Run the game: `godot --path .` (opens an empty window titled Hearthvein).
- Run the whole test suite headless: `tools/test.sh`
- Run one test file: `tools/test.sh test/test_smoke.gd`

Tests use [GUT](https://github.com/bitwes/Gut) 9.7.1, vendored in `addons/gut`. `tools/test.sh` imports the project on first run (when `.godot/` is missing) and exits with GUT's exit code: 0 on pass, non-zero on failure. Test files go in `test/` and are named `test_*.gd`.

Layout: `sim/` (pure simulation, no scene-tree code), `data/`, `render/`, `ui/`, `test/`.

## Build from source

`packaging/build.sh` exports the Windows and Linux builds into `build/` (needs the export templates, NSIS and appimagetool). It refuses to run unless `CHANGELOG.md` has a `## <version>` section for the version in `project.godot`. `CHANGELOG.md` is the one source for the in-game What's new panel and the GitHub release notes: `packaging/release_notes.sh <version>` prints that version's section (use it with `gh release create --notes-file`).
