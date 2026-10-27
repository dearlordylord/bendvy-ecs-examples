# Browser stream verification

The acceptance driver uses the built game in Chromium and WebKit. It copies the
completed build into a private diagnostic snapshot and checks every file hash
before and after copying. The source build may then change without affecting the
running check. It serves that snapshot and real strategy manifests from one local
HTTP origin. Fault strategies execute in the production Worker; the driver never
sets game state or replaces the session controller.

Build the browser application first, then run from the repository root:

```sh
node tools/survivors-bot/stream-browser-check.mts \
  --root examples/survivors/dist/web \
  --browser both \
  --out .audit/stream-browser-check
```

The driver captures changing game frames, real audio scheduling and nonzero PCM
at a passive master-signal tap, operator pause, live strategy replacement, a
dependency-only strategy rebuild, memory migration, candidate and active-strategy
failures, and ordinary player controls after stream mode. It also checks rapid
reload generations, an actual delayed Worker reply overlapping pause/resume,
Worker-construction failure with Blob cleanup, bounded failure messages before
host clipping, retained source attribution, stop/restart and profile isolation.
The real upgrade case chooses an offer different from Bend fallback and checks
that exact highlight and commit. A DOM observer measures the frozen card dwell,
excluding operator pauses, with a 34 ms scheduling tolerance against 1500 ms.
The exact abstract dwell is covered separately by Bend laws; this is not a
measurement of physical screen paint or speaker output. The dependency-edit case
invokes the normal strategy build tool; it does not rebuild Bend.

The fixture server publishes each strategy under its SHA-256 filename and changes
only its manifest pointer. Syntax errors, initialization errors, deliberate
infinite loops and invalid advice are fixture inputs, not simulated Worker
responses. Errors must appear in production diagnostics, a healthy old strategy
must survive a broken candidate, and rendering must continue after active faults.

Use a fresh `--out` directory for each run. Reports, the source identity, the
complete application hash manifest and screenshots are written there. The driver
checks all snapshot hashes again at the end. The copy is a diagnostic fixture, not
a publication artifact. A nonzero exit status means a failed assertion or a
browser/runtime error. The report preserves completed cases
and the failure. Browser results complement Bend laws and mutation checks; they
are not a proof of all possible event schedules.

## Focused audio and controls check

Run `--audio-only` with either browser or `--browser both` for the compact
controls, actual AudioContext suspension, suspended status, public Resume audio,
and Settings sound checkbox cases. Suspension invokes the captured native context;
it does not fake its state. After native suspend resolves, the context timeline
must remain held across a 1200 ms wall-clock interval. Suspended analyser data may
retain nonzero history, as required by the
[Web Audio suspension semantics](https://www.w3.org/TR/webaudio-1.0/#dom-audiocontext-suspend).
At each native
running transition the observer starts a new epoch. Only reads with progressing
context time more than `(fftSize + 128) / sampleRate` beyond that epoch's baseline
enter the rolling PCM window. Thus recovery requires fresh PCM from the actual
application graph through the public Resume audio button. No waveform inequality,
new context or synthetic tone is used. Receipts retain clock anchors, epoch,
eligible samples, raw peaks, native state, context count and public status,
including observations on failure.
Settings are changed through the normal menu between
runs because the running view has no sound checkbox. Muted play must produce
silent master PCM; unmuted play and audio resume must recover nonzero PCM while
reusing one context. This check changes the ordinary sound preference through its
supported public control and verifies bot play preserves the resulting profile.

## Bend navigation checks

The navigation gate requires Bend 2.0.39, Node.js 24.20 or newer, coreutils
`timeout` or `gtimeout`, and the matching compiler source checkout. Prepare that
checkout separately from the examples:

```sh
git clone https://github.com/bendlang/bend.git /tmp/bend-stream-verifier
git -C /tmp/bend-stream-verifier checkout a3efe8a3801f423827424227172eed9802c5e6cb
BEND_SOURCE_ROOT=/tmp/bend-stream-verifier \
  node --experimental-transform-types --stack-size=8192 \
  examples/survivors/check-stream-goal.mts
```

The gate checks the complete source with the installed compiler, rejects nine
type-correct production mutants at their named laws, and checks all 82 navigation
laws with the kernel. Each child has a 10-second CPU limit and 60-second wall
limit. Selected-root checking retains the complete checked compiler book and its
original recursive-group ordering. It checks the named laws, rather than claiming
a kernel verdict for every imported game function. Receipts bind the sources,
checked types, proofs, toolchain and emitted kernel artifacts. Existing routing
and steering implementations remain inherited dependencies; the laws constrain
their use, not their mathematical correctness.

## External goal navigation

Run `--browser chromium --goals-only` to contrast east and west cardinal advice in fresh runs with
the same seed. Each accepted generated `GoalChoice` must match the exact index,
request and source hash of a real supplied bounded candidate. A read-only DOM
observer reconstructs actual Canvas position publications, including updates
batched in one browser task. The game can advance multiple ticks before publishing
a frame, so a rendered common tick is not guaranteed. The revised capture protocol
uses only actual endpoint samples in [80,100]. It selects the pair by the
lexicographic key `(absolute tick gap, maximum tick, east tick, west tick)`, without
reading coordinates. Conflicting duplicate ticks, backwards ticks, nonfinite or
out-of-arena coordinates, and observed movement exceeding the bound reject capture.
Identical duplicate projections collapse. Fresh isolated profiles, the fixed seed
982451653, source-pinned default character/stage/arcana/mode, initial tick zero and
identical initial coordinates are required. Each run's session/run must remain
constant. The exact complete supplied request identity, source hash, unique index
and direction kind must match admission, with supplied tick <= accepted tick < T,
where T is the smaller endpoint tick. Supplied ticks remain below 60.

The declared source-derived Euclidean displacement ceiling is 6 units per tick.
For each endpoint, uncertainty is `6 * abs(endpointTick - T)`. East displacement
minus uncertainty must exceed 30; negative west displacement minus uncertainty
must exceed 30; east-minus-west displacement minus both uncertainties must exceed
60. For each direction, the distance from the exact supplied player point to its
fixed supplied target, minus observed endpoint-to-target distance and uncertainty,
must exceed 20. Strict positive margins imply the original inequalities at T by
the triangle inequality. The driver records actual samples, selection key,
uncertainties, raw distances and each margin. It neither interpolates positions
nor reports an inferred shared-tick position as an observation.

For fresh character/meta/arcana zero, movement distance is nominally at most 3.75
units including legal rank-five speed upgrades. Normalization, clamped arena
coordinates and conservative F32 rounding slack give less than 4 per coordinate,
hence Euclidean displacement less than 6. This is a source audit, not a formal
F32 theorem. A checked-in SHA-256 manifest pins movement, setup, upgrade and
build sources read using `git show` at the clean actual `version.json` revision.
It also pins the audited emitted game, progression and bot arithmetic modules.
Unknown revisions or hash drift fail closed and require bound re-audit. The
manifest currently names the immutable ignored-goal d847 control and corrected
1b781f5 build. The identical revised protocol must reject the old control on
spatial margins after successful admission and capture before positive evidence
is accepted. Historical reports and the original missing-common-tick failure are
retained; retrospective arithmetic does not replace these reruns.

Pure controls cover coordinate-independent tie selection, duplicate/reset
rejection, uncertainty-induced false positives, excessive uncertainty, invalid
admission timing and source drift:

```sh
node --test tools/survivors-bot/stream-goal-capture.test.mts
```

The driver saves both trajectories before asserting their physical contrast, so
a rejected implementation retains observations for diagnosis. Chromium against
the immutable `d847fc3` build accepts both cardinal intentions but fails this
physical navigation gate. That build cannot qualify external strategy control;
its interrupted long soak is not transferable to a corrected runtime.

## Optional future endurance diagnostics

The current task uses bounded functional checks. The user explicitly excluded a
24-hour run and recording. Do not start the following optional endurance tool for
this task. It remains available for a separately requested investigation:

```sh
node tools/survivors-bot/stream-browser-check.mts \
  --root examples/survivors/dist/web \
  --browser chromium --headed \
  --soak-only --soak-hours 24 \
  --out .audit/stream-browser-soak
```

The driver records its contract before measuring. Initial limits are:

- Probes, render progress and gameplay/decision progress must each occur within 15 seconds.
- The page must remain visible and unpaused.
- At most three owned strategy Workers may overlap.
- The diagnostic log must contain at most 256 entries.
- Browser process-tree resident memory must remain below 2 GiB.
- After 15 minutes of warmup, resident memory growth must remain within 512 MiB.
- A 24-hour qualification must include multiple automatic runs, transition pause
  and stop checks, and at least two verified rotations of each fault kind.

These limits qualify only the recorded source, browser, setup and machine. They
are operational bounds, not universal performance requirements or proof of no
leaks. Linux/macOS process RSS is sampled with `ps`; it is not JS heap size.

Every minute the driver rotates successful reloads, rejected candidates and
active-strategy failures. Each rotation must produce its expected activation,
rejection or failure followed by recovery; requests alone do not count. Verified
outcomes are written to a separate JSONL trail. It records progress and resource
samples every 15 seconds and captures a screenshot every 15 minutes. The latest checkpoint is
replaced atomically, while the JSONL samples preserve the trajectory. The final
report marks `qualified24h` only after at least 24 actual wall-clock hours.
A shorter `--soak-hours` value is useful for development but cannot qualify 24/7
operation.

The qualification capture setup is native headed Chromium with Canvas/audio
execution and periodic screenshots. The driver attaches through CDP with
`noDefaults` so Playwright does not force focus or visibility. A real tab switch
exercises the hidden-document pause and explicit-resume behaviour. Short WebKit
and default Chromium checks use Playwright's standard browser defaults; they do
not qualify hidden-tab lifecycle behaviour. Neither setup qualifies OBS, encoder
output, continuous hidden-tab streaming, a sleeping device or browser autoplay
without a gesture. Initial start is a real browser click. The native Chromium
launch does not add background-throttling bypass flags.
A display server is required; a dedicated Xvfb display is suitable on Linux.

The watchdog checks elapsed gaps before accepting new progress and checks again
after final maintenance work. Focused harness tests reject a stalled probe that
returns one late tick/frame and enforce an actual asynchronous probe deadline:

```sh
node --test tools/survivors-bot/stream-browser-health.test.mts
```

## Browser environment

Install the OS dependencies required by the pinned Playwright browsers. For an
existing custom WebKit wrapper, `PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH` may point to
that executable. The default uses Playwright's installed WebKit. Such an override
must be recorded with the environment because it changes the launch artifact.

Native headless/grid compatibility, Bend proof/mutation results, complete
visibility lifecycle coverage and source-level observation bounds remain separate
acceptance evidence. Do not infer those properties from screenshots or a green
browser report.

## Stop during a frozen offer

Run `--stop-frozen-only --browser both` for the bounded invalidated-offer case.
The ordinary game must reach an actual accepted frozen upgrade recommendation
within a bounded 15-minute arrival wait. The earlier 180-second attempt reached
only 40 simulation seconds under machine load, before an offer arrived; this
arrival budget does not alter any dwell or Stop assertion. Focused setup allows
one 15-minute deadline across initial readiness, the shipped strategy's actual
automatic recovery, and fixture activation attempts. A failed replacement retains the healthy strategy and does not retry automatically, so
fixture setup uses at most 30 public Reload attempts within that shared
deadline, with at least three seconds between attempts. A retry requires an observed failure of the
requested candidate and its retirement; live candidates never overlap. Production
preparation remains limited to 1000 ms per attempt. The check requires actual
desired-revision activation, and records every attempt, rather than claiming a
first-attempt latency guarantee. Focused Start, Reload and Stop controls use native
keyboard Enter after focusing their visible, enabled public buttons. This avoids
coordinate-stability waits while live status text changes under slow rendering;
ordinary full-suite controls keep their click coverage. During its configured
10-second dwell, a real replacement Worker must become
candidate-ready while activation remains deferred. Public Stop must precede the
commit. The check observes the full dwell plus a margin after Stop: no offer
commit, candidate activation, automatic restart, Canvas tick advancement, new
sound nodes or fresh graph PCM may return. Silence is measured after the rolling
window clears, on the same running context with eligible progressing-clock reads.
Finally, public Start must create a fresh session and run with no old event
identities. Raw preparation and periodic hold receipts survive failures. This is
a focused functional check; it starts no endurance session or recording.
