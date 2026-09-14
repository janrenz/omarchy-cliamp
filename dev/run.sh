#!/usr/bin/env bash
# (Re)start the harness, rendered offscreen.
#
# Offscreen means no window on anyone's screen: the harness cannot be occluded,
# cannot land on a workspace nobody is looking at, and cannot cover what
# someone else is doing. It draws its own screenshots - see shot.sh. It never
# touches your shell.json and never talks to cliamp, so it is safe to run while
# you are listening to something.
set -euo pipefail
cd "$(dirname "$0")"

STAGE="$(./link.sh)"
# -x, so this matches the harness and not the shell running this script - a
# bare -f pattern also matches any command line that mentions the path.
pkill -x -f "qs -p $STAGE/shell.qml" 2>/dev/null || true
sleep 0.5

# QML_DISABLE_DISK_CACHE, because the stage's file names never change: with the
# cache on, Quickshell re-runs the compiled copy of whatever the file said the
# first time, and an edit appears to have done nothing.
QML_DISABLE_DISK_CACHE=1 QT_QPA_PLATFORM=offscreen qs -p "$STAGE/shell.qml" >"$STAGE/harness.log" 2>&1 &

for _ in $(seq 1 60); do
  sleep 0.2
  if qs -p "$STAGE/shell.qml" ipc show >/dev/null 2>&1; then
    echo "harness up - dev/shot.sh out.png"
    exit 0
  fi
done
echo "harness did not come up; see $STAGE/harness.log" >&2
tail -30 "$STAGE/harness.log" >&2
exit 1
