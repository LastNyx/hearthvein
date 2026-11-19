#!/usr/bin/env bash
# Sets the release version in project.godot, export_presets.cfg, packaging/windows/hearthvein.nsi and
# packaging/linux/README.txt. It does not touch CHANGELOG.md: add and date the "## <version> - <date>" section yourself.
# Usage: bump_version.sh <version> [root]   e.g. bump_version.sh 1.2.0
set -euo pipefail
VERSION="${1:?usage: bump_version.sh <version> [root]}"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "bump_version: version must look like 1.2.3 or 1.2.3-rc1" >&2; exit 2; }
NUM="${VERSION%%-*}"
sed -i "s|^config/version=\".*\"|config/version=\"$VERSION\"|" "$ROOT/project.godot"
sed -i -e "s|^application/file_version=\".*\"|application/file_version=\"$NUM.0\"|" \
  -e "s|^application/product_version=\".*\"|application/product_version=\"$NUM.0\"|" "$ROOT/export_presets.cfg"
sed -i "s|^  !define VERSION \".*\"|  !define VERSION \"$VERSION\"|" "$ROOT/packaging/windows/hearthvein.nsi"
sed -i "1s|^Hearthvein [^ ]* |Hearthvein $VERSION |" "$ROOT/packaging/linux/README.txt"
"$ROOT/packaging/check_version.sh" "$VERSION" "$ROOT"
