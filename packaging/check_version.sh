#!/usr/bin/env bash
# Fails unless <version> (a tag without the leading "v") matches the version in the four places that carry it:
# project.godot, export_presets.cfg (numeric part + ".0"), packaging/windows/hearthvein.nsi, packaging/linux/README.txt.
# Usage: check_version.sh <version> [root]
set -euo pipefail
VERSION="${1:?usage: check_version.sh <version> [root]}"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
NUM="${VERSION%%-*}"
bad=0
want() { # <file> <expected text>
  if ! grep -qF -- "$2" "$ROOT/$1"; then echo "check_version: $1 does not say $2 (tag is v$VERSION)" >&2; bad=1; fi
}
want project.godot "config/version=\"$VERSION\""
want export_presets.cfg "application/file_version=\"$NUM.0\""
want export_presets.cfg "application/product_version=\"$NUM.0\""
want packaging/windows/hearthvein.nsi "!define VERSION \"$VERSION\""
want packaging/linux/README.txt "Hearthvein $VERSION "
[ "$bad" = 0 ] || { echo "check_version: bump the version (packaging/bump_version.sh $VERSION) and re-tag" >&2; exit 1; }
echo "version $VERSION ok"
