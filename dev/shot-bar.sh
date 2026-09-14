#!/usr/bin/env bash
# The two bar states, from the real bar.
#
#   dev/shot-bar.sh
#
# Unlike showcase.sh this one needs the plugin running in your own shell, and it
# pauses playback for a second to photograph the pause morph before putting it
# back the way it found it. Nothing else here touches what you are listening to.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
crop="${BAR_CROP:-760x56+0+0}"

grab() { grim "$1"; magick "$1" -crop "$crop" +repage -resize 1520x "$1"; }

state="$(cliamp remote call runtime.status --wait 2>/dev/null | grep -o '"state":"[a-z]*"' | head -1 | cut -d'"' -f4)"

if [ "$state" != "playing" ]; then
  echo "nothing is playing - start something first, so the spectrum has data" >&2
  exit 1
fi

sleep 1
grab "$repo/showcase-bar-playing.png"

cliamp remote call pause --wait >/dev/null 2>&1
sleep 1.5
grab "$repo/showcase-bar-paused.png"
cliamp remote call play --wait >/dev/null 2>&1

echo "wrote showcase-bar-playing.png and showcase-bar-paused.png"
