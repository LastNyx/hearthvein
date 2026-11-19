#!/usr/bin/env bash
# Builds the Hearthvein release artefacts into build/:
#   Hearthvein-<ver>-setup.exe, Hearthvein-<ver>-x86_64.AppImage, Hearthvein-<ver>-linux-x86_64.tar.gz
# Needs: godot 4.7.2 + matching export templates, NSIS (makensis, or NSIS_EXE under wine),
#        appimagetool.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
GODOT="${GODOT:-godot}"
NSIS_EXE="${NSIS_EXE:-$HOME/.local/opt/nsis/Bin/makensis.exe}"
APPIMAGETOOL="${APPIMAGETOOL:-$HOME/.local/bin/appimagetool}"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDEBUG=-all
export WINEPREFIX="${WINEPREFIX:-$HOME/.cache/hv_wine_build}"

# The release needs a CHANGELOG.md section for this version (the GitHub release notes come from it).
packaging/release_notes.sh "$VERSION" >/dev/null || { echo "build.sh: add a \"## $VERSION\" section to CHANGELOG.md first" >&2; exit 1; }

rm -rf build
mkdir -p build/windows build/linux

echo "== export"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/Hearthvein.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/Hearthvein.x86_64

echo "== windows installer"
# packaging/windows is the cwd so the .nsi's relative defaults resolve
if command -v makensis >/dev/null; then
  (cd packaging/windows && makensis -V2 -DVERSION="$VERSION" -DNUMVER="${VERSION%%-*}" hearthvein.nsi)
else
  (cd packaging/windows && wine "$NSIS_EXE" -V2 -DVERSION="$VERSION" -DNUMVER="${VERSION%%-*}" hearthvein.nsi)
fi

echo "== linux AppImage"
APPDIR=build/AppDir
mkdir -p "$APPDIR/usr/bin"
cp build/linux/Hearthvein.x86_64 "$APPDIR/usr/bin/Hearthvein.x86_64"
cp assets/icon/hearthvein.png "$APPDIR/hearthvein.png"
cp packaging/linux/hearthvein.desktop "$APPDIR/hearthvein.desktop"
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/Hearthvein.x86_64" "$@"
EOF
chmod +x "$APPDIR/AppRun"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "build/Hearthvein-$VERSION-x86_64.AppImage"

echo "== linux tarball"
T="build/tar/Hearthvein-$VERSION-linux-x86_64"
mkdir -p "$T"
cp build/linux/Hearthvein.x86_64 assets/icon/hearthvein.png packaging/linux/hearthvein.desktop packaging/linux/README.txt "$T/"
tar -C build/tar -czf "build/Hearthvein-$VERSION-linux-x86_64.tar.gz" "Hearthvein-$VERSION-linux-x86_64"
rm -rf build/tar "$APPDIR"
ls -l build/*.exe build/*.AppImage build/*.tar.gz
