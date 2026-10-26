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
it does not fake its state. The suspended rolling PCM window must become silent
before resuming, so cached pre-suspension samples cannot satisfy recovery.
Settings are changed through the normal menu between
runs because the running view has no sound checkbox. Muted play must produce
silent master PCM; unmuted play and audio resume must recover nonzero PCM while
reusing one context. This check changes the ordinary sound preference through its
supported public control and verifies bot play preserves the resulting profile.

## Foreground soak

Run a separate long session after the short acceptance checks pass:

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
