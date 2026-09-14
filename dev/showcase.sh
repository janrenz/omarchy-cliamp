#!/usr/bin/env bash
# Regenerate every screenshot in the README, from the harness.
#
#   dev/showcase.sh
#
# The window shots come from the offscreen harness on fixture data, so they are
# reproducible and contain nobody's library. The bar shots need the real bar and
# are taken by dev/shot-bar.sh, which is separate because it touches playback.
set -euo pipefail
cd "$(dirname "$0")"
repo="$(cd .. && pwd)"
. ./stage.sh

./run.sh >/dev/null

call() { qs -p "$STAGE/shell.qml" ipc call dev "$@" >/dev/null 2>&1; }
shot() { qs -p "$STAGE/shell.qml" ipc call dev shot "$1" >/dev/null 2>&1; sleep 0.6; }

# Broadcast is the listing card: it is the section nobody else has, and it
# needs a moment because both its adapters are live.
call section broadcast
sleep 6
shot "$repo/preview.png"
cp "$repo/preview.png" "$repo/showcase-broadcast.png"

call section podcast
sleep 1.5
shot "$repo/showcase-podcasts.png"

# Into a show, for the episode list.
call enter
sleep 1.5
shot "$repo/showcase-episodes.png"

call section queue
sleep 1
shot "$repo/showcase-queue.png"

call section settings
sleep 1
shot "$repo/showcase-settings.png"

call help true
sleep 0.6
shot "$repo/showcase-keys.png"
call help false

# Leave nothing running: a harness instance is a whole Quickshell, and the
# ones this script used to leave behind added up until the machine ran out of
# memory.
qs -p "$STAGE/shell.qml" kill >/dev/null 2>&1 || true

echo "wrote preview.png and showcase-*.png"
