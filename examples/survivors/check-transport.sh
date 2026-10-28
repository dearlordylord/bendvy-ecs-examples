#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/../common.sh"
cd "$example_repo"
mkdir -p examples/survivors/dist
example_emit "$example_repo/examples/survivors/coop-transport-policy.bend" "$example_repo/examples/survivors/dist/coop-transport-policy.mjs"
example_timeout 60 "$BEND" examples/survivors/coop-transport-policy-PROOF.bend --verdict
"$NODE" examples/survivors/coop-transport-policy-check.mts
"$NODE" --test examples/survivors/coop-transport-check.mts
"$NODE" examples/survivors/coop-transport-policy-mutations.mts
