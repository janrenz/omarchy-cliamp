#!/usr/bin/env bash
# Every test there is.
#
#   dev/test.sh
set -euo pipefail
cd "$(dirname "$0")"

node test-model.js
node test-adapters.js
