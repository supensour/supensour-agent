#!/usr/bin/env bash
# save-latest.sh <branch-dir> <timestamped.json>
# Point `<branch-dir>/latest.json` at the newest saved review.
#
# This is a COPY, deliberately not a symlink: Windows needs admin rights or Developer
# Mode to create one, and Git Bash silently degrades `ln -s` to a copy anyway — so a
# symlink would mean two different behaviors for the same command. A copy behaves
# identically on Linux, macOS and Windows, and `--push-saved` reads latest.json the same
# way either way (it is a complete findings file, not a pointer).
#
# Prints the path written.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DIR="${1:?save-latest.sh <branch-dir> <timestamped.json>}"
SRC="${2:?timestamped json required}"
[ -f "$SRC" ] || die "save-latest.sh: no such file: $SRC"
[ -d "$DIR" ] || die "save-latest.sh: no such directory: $DIR"

DEST="$DIR/latest.json"
cp "$SRC" "$DEST"
log "🔗 latest.json → $(basename "$SRC")"
printf '%s\n' "$DEST"
