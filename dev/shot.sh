#!/usr/bin/env bash
# Photograph what the harness is drawing.
#
#   dev/shot.sh out.png              # as it is
#   dev/shot.sh out.png queue        # after switching to that section
set -euo pipefail
cd "$(dirname "$0")"
. ./stage.sh
OUT="$(realpath -m "${1:-/tmp/cliamp.png}")"

if [ $# -ge 2 ]; then
  qs -p "$STAGE/shell.qml" ipc call dev section "$2"
  sleep 0.6
fi
qs -p "$STAGE/shell.qml" ipc call dev shot "$OUT"
sleep 0.6
[ -s "$OUT" ] && echo "$OUT" || { echo "no image written; see $STAGE/harness.log" >&2; exit 1; }
