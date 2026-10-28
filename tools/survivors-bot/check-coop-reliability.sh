#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/../../examples/common.sh"
cd "$example_repo"
example_timeout 600 "$NODE" "$example_repo/tools/survivors-bot/coop-reliability-browser-check.mts"
