#!/usr/bin/env bash
# Prints the body of the "## <version>" section of CHANGELOG.md (no heading line, up to the next "## " heading, blank
# lines trimmed at both ends), e.g. for: gh release create v1.1.1 --notes-file <(packaging/release_notes.sh 1.1.1)
# Usage: release_notes.sh <version> [changelog-path]. Exits 1 when the version has no section or the section is empty.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
FILE="${2:-$ROOT/CHANGELOG.md}"
if [ -z "$VERSION" ]; then
  echo "usage: release_notes.sh <version> [changelog-path]" >&2
  exit 2
fi
notes="$(awk -v head="## $VERSION" '
  /^## / { if (on) exit; n = length(head); on = (substr($0, 1, n) == head && (length($0) == n || substr($0, n + 1, 1) == " ")); next }
  on { print }
' "$FILE")"
# $(...) dropped the trailing blank lines; drop the leading ones
notes="$(printf '%s\n' "$notes" | sed '/./,$!d')"
if [ -z "$notes" ]; then
  echo "release_notes.sh: no \"## $VERSION\" section (or it is empty) in $FILE" >&2
  exit 1
fi
printf '%s\n' "$notes"
