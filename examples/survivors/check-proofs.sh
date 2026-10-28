#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/../common.sh"
cd "$example_repo"
timeout_command=timeout
if ! command -v "$timeout_command" >/dev/null 2>&1; then
  timeout_command=gtimeout
fi
if ! command -v "$timeout_command" >/dev/null 2>&1; then
  echo 'Proof checks require timeout or gtimeout to enforce the wall limit.' >&2
  exit 127
fi
proof_files="$(find examples -type f -iname '*proof*.bend' ! -path '*/dist/*' | LC_ALL=C sort)"
if [[ -z "$proof_files" ]]; then
  echo 'No Bend proof entrypoints found.' >&2
  exit 1
fi
proof_count=0
while IFS= read -r proof; do
  proof_limit=60
  if [[ "$proof" == examples/survivors/offline-policy/preference-PROOF.bend ]]; then
    proof_limit=10
  fi
  printf 'Checking Bend proof: %s (CPU limit %ss, wall limit %ss)\n' "$proof" "$proof_limit" "$proof_limit"
  if "$timeout_command" --kill-after=5s "${proof_limit}s" "${example_cpu[@]}" bash -c 'ulimit -t "$1" && shift && exec "$@"' bend-proof "$proof_limit" "$BEND" "$proof" --verdict; then
    proof_count=$((proof_count + 1))
  else
    status=$?
    printf 'Bend proof command failed: %s (exit %s)\n' "$proof" "$status" >&2
    if [[ "$status" == 124 ]]; then
      printf 'Proof check exceeded the %s-second wall limit.\n' "$proof_limit" >&2
    fi
    exit "$status"
  fi
done <<< "$proof_files"
printf '%s Bend proof entrypoints passed.\n' "$proof_count"
