# Bend bots

The bot policy lives in [offline-policy.bend](../../examples/survivors/offline-policy.bend).
The native window and headless runners call that same Bend implementation.
Movement, XP planning, memory and upgrade selection stay in the native process.
There is no Node/Python bot controller, observation file or JSON command bridge.

Run these commands from the repository root. Native builds require Bend and the
[pinned LLVM Clang toolchain](../../toolchains/README.md).

## Watch a bot

```sh
bash tools/survivors-bot/visible.sh --profile fresh --seed 12345
bash tools/survivors-bot/visible.sh --count 10 --threads 8 --profile fresh --seed 12345
bash tools/survivors-bot/visible.sh --profile advanced --seed 12345 --ticks 1800
bash tools/survivors-bot/visible.sh --unlimited --profile advanced --ticks 1800
```

`--count N` displays 1 to 64 independent games in one native process and one
window. The default is 1. `NIGHTFALL_BOT_COUNT` sets the same option through the
environment. Games use consecutive U32 seeds starting at `--seed`, wrapping after
4294967295. Bend executes independent world steps and tile rendering through a balanced
fork/join tree on the CPU pool. `--threads N` sets its size. The default
`--threads auto` lets Bend choose from the available CPUs.
`NIGHTFALL_BOT_THREADS` sets the same option through the environment. The launcher
prints the actual runtime thread count when starting a grid.
Each cell shows its bot ID,
seed and metrics. Finished games remain visible while other games continue.
The window closes when every game has finished.

The launcher reuses the native binary when its build inputs are unchanged.
It checks content hashes of Bend sources, compiler tools, Bend runtime and package
cache, dependency pins and SDK identity files. Changed inputs or a changed binary
trigger a rebuild. The first launch after this update rebuilds once to save the
build receipt. Profile, seed, count, threads, pacing and run limits do not require
recompilation.
Close the window or press Escape to stop. `--ticks` bounds game time; `--seconds`
bounds wall time. Zero means no bound. `--build-only` compiles without opening a
window. `--rebuild` forces compilation. `--no-build` deliberately reuses the
existing binary without checking its inputs. Native build receipts remain under
the ignored `dist` directory.

By default, the window runs at realtime pace. `--unlimited` uses a separate
simulation loop that advances continuously and requests a picture approximately
every 100 ms. There is no eight millisecond simulation budget. About 10 FPS is
intentional in this mode; TPS and SPEED show the simulation rate independently.
Presentation and simulation share a thread, so drawing still consumes time.
Close/Escape is handled on presentations. An expensive simulation step can delay
the next presentation. This mode is not a headless benchmark.
`NIGHTFALL_BOT_PACING=unlimited` selects the same mode through the environment.

The bot window displays FPS, actual simulation ticks per wall second (TPS), and
game-time speed relative to 60 ticks per second. Measurements use half-second
wall-clock windows and include simulation, rendering and display waits. The
active `REALTIME` or `UNLIMITED` mode appears beside them. Startup shows dashes
until the first complete measurement window.

## Headless simulations

```sh
bash tools/survivors-bot/native-batch.sh --count 10 --ticks 1800 --profile both --workers 2
bash tools/survivors-bot/native-batch.sh --count 10 --ticks 1800 --profile both --execution bend --threads 2
```

Each world runs the game and bot natively without rendering or a realtime delay.
Process execution distributes independent worlds across `--workers`. Bend
execution uses its runtime thread pool inside one process. Both write run receipts
and summary JSONL under `examples/survivors/dist/native-batches/`. Output is a
report, not a transport used to make decisions. No 100× speed claim is established.

## Two bots in one co-op world

The co-op runner uses the same Bend policy for both players. Compile and run it
without a window or Node.js:

```sh
mkdir -p examples/survivors/dist
bend examples/survivors/offline-coop-batch.bend -o examples/survivors/dist/nightfall-coop.c
tools/clang -std=c11 -O3 examples/survivors/dist/nightfall-coop.c -o examples/survivors/dist/nightfall-coop -lpthread -lm
NIGHTFALL_COOP_PROFILE=advanced NIGHTFALL_COOP_SEED=982451653 NIGHTFALL_COOP_TICKS=6000 examples/survivors/dist/nightfall-coop +RTS --threads 1 --gpu off -RTS
```

`NIGHTFALL_COOP_PROFILE` selects `fresh` or `advanced`. The seed defaults to
12345 and the horizon to 7200 ticks; the maximum horizon is 37000 ticks.
Characters and arcanas can be set independently with `NIGHTFALL_COOP_CHARACTER0`,
`NIGHTFALL_COOP_CHARACTER1`, `NIGHTFALL_COOP_ARCANA0`, and `NIGHTFALL_COOP_ARCANA1`.
The runner prints a sample every 60 game ticks and a terminal summary. Decisions
and policy memory remain inside the native process.

`offline-coop-step.bend` contains the shared pure controller transition.
`offline-coop-audit.bend` adds scheduled physical-state, action and policy-memory
captures; compile that entrypoint and set `NIGHTFALL_COOP_AUDIT=scheduled`.
Its `bendvy-coop-observer-v3` schema includes each player's revival tick as the
fourth player-record field. Pre-revival v2 captures use a different schema.
`offline-coop-journal-audit.bend` records ordered observations and contact events
with exact F32 bits. These verification entrypoints share the same transition.

The personal-total fold and its laws preserve the existing damage and reward
calculation while avoiding intermediate personal row and snapshot lists. The
global snapshot/relic reduction and player revival scheduling remain separate.
This integration does not establish the 100× performance target.

`balance-report.py` is an offline report analyzer, not a game runner. Performance
qualification continues separately in GitHub issue #11.

## Check co-op transport reliability

Build and serve Survivors with the commands in the
[Survivors README](../../examples/survivors/README.md#browser-launch). Run the browser
check against that exact artifact:

```sh
COOP_URL=http://127.0.0.1:8713/coop.html bash tools/survivors-bot/check-coop-reliability.sh
```

The wrapper holds the shared backend-check lock. Run other browser checks after
it finishes. Parallel compilation or game sessions can disrupt browser scheduling
and invalidate a latency comparison.

The check reloads the guest during active gameplay and rejoins its reserved seat.
It then measures the original 32-second controls with seed 1729, 300 ms observation
delay, and native send delays of 0, 200, and 600 ms. Reconnect precedes measurement
because this combat trajectory can legitimately end in defeat before 32 seconds.
The latency, motion, input, and resource thresholds remain unchanged. The 600 ms
case checks bounded overload and makes no playability claim.

Artifacts default to `/tmp/coop-transport-qualification`. Set `COOP_QA_DIR` to keep
separate runs. `COOP_SOURCE_ARTIFACT_DIR` selects the expected served directory;
its default is `examples/survivors/dist/web`. The checker compares every served
file with that directory before and after each case. Compare baseline and
candidate builds with the same checker, inputs, thresholds, and workload conditions.
