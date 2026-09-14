#!/usr/bin/env bash
# (Re)start the harness, rendered offscreen.
#
# The harness draws its own screenshots - see shot.sh - and it never touches
# your shell.json and never talks to cliamp, so it is safe to run while you are
# listening to something.
#
# It does map one real window. QT_QPA_PLATFORM=offscreen is set below and
# Quickshell connects to Wayland anyway once the config declares a
# FloatingWindow, so rather than pretend otherwise, the window is given a title
# of its own and moved to a special workspace as soon as it appears.
set -euo pipefail
cd "$(dirname "$0")"

STAGE="$(./link.sh)"
# Quickshell rewrites its own argv to a bare "/usr/bin/quickshell", so no
# pkill pattern can find a previous harness: every run used to leave one
# behind, window and all. Its own CLI knows which instance is which.
qs -p "$STAGE/shell.qml" kill >/dev/null 2>&1 || true
sleep 0.5

# QML_DISABLE_DISK_CACHE, because the stage's file names never change: with the
# cache on, Quickshell re-runs the compiled copy of whatever the file said the
# first time, and an edit appears to have done nothing.
QML_DISABLE_DISK_CACHE=1 QT_QPA_PLATFORM=offscreen qs -p "$STAGE/shell.qml" >"$STAGE/harness.log" 2>&1 &

for _ in $(seq 1 60); do
  sleep 0.2
  if qs -p "$STAGE/shell.qml" ipc show >/dev/null 2>&1; then
    # Out of the way, not onto whatever workspace you are working on.
    hyprctl dispatch movetoworkspacesilent "special:cliamp-dev,title:^cliamp-harness$" >/dev/null 2>&1 || true
    echo "harness up - dev/shot.sh out.png"
    exit 0
  fi
done
echo "harness did not come up; see $STAGE/harness.log" >&2
tail -30 "$STAGE/harness.log" >&2
exit 1
