#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/nightfall-visible-test-XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/repo/tools/survivors-bot" "$fixture/repo/examples/survivors" "$fixture/repo/scripts" "$fixture/repo/toolchains" "$fixture/bend/bin" "$fixture/bend/bend2" "$fixture/library" "$fixture/sdk"
cp "$repo/tools/survivors-bot/visible.sh" "$fixture/repo/tools/survivors-bot/"
cp "$repo/tools/clang" "$fixture/repo/tools/clang"
cp "$repo/scripts/native-toolchain.sh" "$fixture/repo/scripts/native-toolchain.sh"
cp "$repo/toolchains/clang.env" "$fixture/repo/toolchains/clang.env"
cat > "$fixture/compiler" <<'COMPILER'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == version ]]; then echo 'bend 2.0.40'; exit 0; fi
[[ $CC == "$FIXTURE/repo/tools/clang" ]]
[[ $1 == "$FIXTURE/repo/examples/survivors/native-bot.bend" && $2 == -o ]]
[[ ${FAIL_BUILD:-0} == 0 ]] || exit 42
if [[ ${CHANGE_DURING_BUILD:-0} == 1 ]]; then printf 'changed during build\n' >> "$FIXTURE/repo/examples/survivors/native-bot.bend"; fi
printf 'build\n' >> "$FIXTURE/builds"
cat > "$3" <<'BINARY'
#!/usr/bin/env bash
set -euo pipefail
[[ ${BENDRTS+x} != x ]]
printf '%s\n' "$@" > "$FIXTURE/runtime-args"
printf '%s %s %s %s %s %s\n' "$NIGHTFALL_BOT_PROFILE" "$NIGHTFALL_BOT_SEED" "$NIGHTFALL_BOT_TICKS" "$NIGHTFALL_BOT_SECONDS" "$NIGHTFALL_BOT_PACING" "$NIGHTFALL_BOT_COUNT"
exit "${NATIVE_EXIT:-0}"
BINARY
COMPILER
cat > "$fixture/clang" <<'CLANG'
#!/bin/sh
[ "$1" = --version ] || exit 1
printf '%s\n' 'clang version 19.1.7'
CLANG
chmod +x "$fixture/compiler" "$fixture/clang"
cp "$fixture/compiler" "$fixture/bend/bin/bend"
printf 'source\n' > "$fixture/repo/examples/survivors/native-bot.bend"
printf 'base\n' > "$fixture/bend/bend2/base.bend"
printf 'dependency\n' > "$fixture/library/package.bend"
printf '{}\n' > "$fixture/repo/bendhub-dependencies.json"
printf 'sdk\n' > "$fixture/sdk/SDKSettings.json"
export FIXTURE="$fixture" BEND="$fixture/bend/bin/bend" BEND_LIB="$fixture/library" BENDVY_CLANG="$fixture/clang" NODE=/nonexistent/node PYTHON=/nonexistent/python
export BENDRTS='--gpu on --threads 99'
runner="$fixture/repo/tools/survivors-bot/visible.sh"
bash "$runner" --profile advanced --seed 4294967295 --ticks 1800 --seconds 45 > "$fixture/actual"
[[ $(cat "$fixture/actual") == 'advanced 4294967295 1800 45 realtime 1' ]]
[[ -z $(cat "$fixture/runtime-args") ]]
[[ $(wc -l < "$fixture/builds") == 1 ]]
bash "$runner" --seed 12 --unlimited --count 10 > "$fixture/automatic-reuse"
[[ $(cat "$fixture/automatic-reuse") == 'fresh 12 0 0 unlimited 10' ]]
[[ $(wc -l < "$fixture/builds") == 1 ]]
bash "$runner" --seed 12 --unlimited --count 11 > "$fixture/count-reuse"
[[ $(cat "$fixture/count-reuse") == 'fresh 12 0 0 unlimited 11' ]]
[[ $(wc -l < "$fixture/builds") == 1 ]]
BENDVY_CLANG=/nonexistent/clang bash "$runner" --no-build --seed 0 --count 64 > "$fixture/reuse"
[[ $(cat "$fixture/reuse") == 'fresh 0 0 0 realtime 64' ]]
[[ $(wc -l < "$fixture/builds") == 1 ]]
bash "$runner" --no-build --unlimited --ticks 120 > "$fixture/unlimited"
[[ $(cat "$fixture/unlimited") == 'fresh 12345 120 0 unlimited 1' ]]
NIGHTFALL_BOT_COUNT=3 NIGHTFALL_BOT_PACING=unlimited bash "$runner" --no-build > "$fixture/environment"
[[ $(cat "$fixture/environment") == 'fresh 12345 0 0 unlimited 3' ]]
if NIGHTFALL_BOT_COUNT=0 bash "$runner" --no-build >/dev/null 2>&1; then
  echo 'Accepted invalid environment count' >&2; exit 1
fi
if NIGHTFALL_BOT_PACING=invalid bash "$runner" --no-build >/dev/null 2>&1; then
  echo 'Accepted invalid pacing' >&2; exit 1
fi
bash "$runner" --build-only > "$fixture/build-only"
[[ $(cat "$fixture/build-only") == "Ready: $fixture/repo/examples/survivors/dist/nightfall-bot" ]]
[[ $(wc -l < "$fixture/builds") == 1 ]]
bash "$runner" --no-build --count 10 --threads 4 >/dev/null
[[ $(tr '\n' ' ' < "$fixture/runtime-args") == '+RTS --threads 4 -RTS ' ]]
NIGHTFALL_BOT_THREADS=2 bash "$runner" --no-build >/dev/null
[[ $(tr '\n' ' ' < "$fixture/runtime-args") == '+RTS --threads 2 -RTS ' ]]
bash "$runner" --threads auto --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == 1 ]]
for invalid in '--threads 0' '--threads -1' '--threads 1.5' '--threads 4294967296' '--count 0' '--count 65' '--count 1.5' '--seed 01' '--seed -1' '--seed 4294967296' '--ticks 1.5' '--seconds 4294968' '--profile both' '--no-build --build-only' '--no-build --rebuild' '--mode heuristic' '--bogus'; do
  if bash "$runner" $invalid >/dev/null 2>&1; then echo "Accepted invalid: $invalid" >&2; exit 1; fi
done
status=0
FAIL_BUILD=1 bash "$runner" --rebuild > "$fixture/failed" 2>/dev/null || status=$?
[[ $status == 42 && ! -s "$fixture/failed" ]]
for input in "$fixture/repo/examples/survivors/native-bot.bend" "$fixture/library/package.bend" "$fixture/bend/bend2/base.bend" "$fixture/repo/toolchains/clang.env" "$fixture/bend/bin/bend" "$fixture/clang"; do
  before=$(wc -l < "$fixture/builds")
  printf '\n' >> "$input"
  touch -r "$fixture/repo/examples/survivors/dist/nightfall-bot" "$input"
  bash "$runner" --build-only > /dev/null
  [[ $(wc -l < "$fixture/builds") == $((before + 1)) ]]
done
before=$(wc -l < "$fixture/builds")
printf 'new module\n' > "$fixture/repo/examples/survivors/new-module.bend"
bash "$runner" --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == $((before + 1)) ]]
mv "$fixture/repo/examples/survivors/new-module.bend" "$fixture/not-a-build-input"
bash "$runner" --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == $((before + 2)) ]]
before=$(wc -l < "$fixture/builds")
(cd "$fixture/repo/examples"; bash ../tools/survivors-bot/visible.sh --build-only >/dev/null)
[[ $(wc -l < "$fixture/builds") == $before ]]
before=$(wc -l < "$fixture/builds")
SDKROOT="$fixture/sdk" bash "$runner" --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == $((before + 1)) ]]
printf 'new sdk\n' >> "$fixture/sdk/SDKSettings.json"
SDKROOT="$fixture/sdk" bash "$runner" --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == $((before + 2)) ]]
SDKROOT="$fixture/sdk" bash "$runner" --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == $((before + 2)) ]]
before=$(wc -l < "$fixture/builds")
printf '# modified executable\n' >> "$fixture/repo/examples/survivors/dist/nightfall-bot"
SDKROOT="$fixture/sdk" bash "$runner" --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == $((before + 1)) ]]
before=$(wc -l < "$fixture/builds")
SDKROOT="$fixture/sdk" bash "$runner" --rebuild --build-only >/dev/null
[[ $(wc -l < "$fixture/builds") == $((before + 1)) ]]
status=0
CHANGE_DURING_BUILD=1 bash "$runner" --rebuild >/dev/null 2>&1 || status=$?
[[ $status != 0 ]]
status=0
NATIVE_EXIT=23 bash "$runner" --no-build >/dev/null || status=$?
[[ $status == 23 ]]
for obsolete in run.mts runner.mts planner.mts provider.mts context.mts visible.mts visible-controller.mts batch.mts batch-worker.mts batch-wall.mts; do
  [[ ! -e "$repo/tools/survivors-bot/$obsolete" ]] || { echo "Obsolete external bot controller: $obsolete" >&2; exit 1; }
done
if rg -n '(python[0-9]*|node|observation\.json|command-)' "$repo/tools/survivors-bot/visible.sh"; then
  echo 'Native visible launcher reintroduced an external controller dependency.' >&2
  exit 1
fi
echo 'NATIVE VISIBLE WRAPPER PASS'
