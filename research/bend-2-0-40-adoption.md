# Bend 2.0.40 and core 0.1.0.6 adoption

Date: 2026-11-15. Survivors now consumes official Bend **2.0.40** and published
**bendvy-ecs-core@0.1.0.6** through all 32 core imports. Native launch still needs
no Node.js. The package was built from core commit
`b2d5eb542906ee92fe2cac0c9fff9a36352fd3ef`:

- Content hash: `0x14a72e1c180a5ab1f8a056d43822425c`.
- Full publisher manifest SHA256:
  `14a72e1c180a5ab1f8a056d43822425c515d763acc1135cb50b78df9f0dc32b2`.
- Payload: 368 files, 2,915,402 bytes.

Performance was checked **before publication** against those exact payload bytes
in a separate consumer copy. Production imports were changed only after the
published name and manifest were verified. The first ordinary Hub consumer fetched
all 368 files; each matched the prepared publisher manifest, with no extra files.

## Actual browser game loop

The comparison used the archived original game with Bend 2.0.39/core 0.1.0.2 and
the updated game with Bend 2.0.40/core 0.1.0.6. Each scenario used five fresh paired
runs in alternating order, the same recorded controls, and the public
`advance_live`/`choose`, `observe`, `gameFrame` and `Renderer.draw` path. Final pixel
readback completed before the endpoint clock. Complete states, frames, pixels and
PNGs matched; every browser process closed without live descendants.

| Scenario | Baseline median | Updated median | Paired updated/baseline ratio | 95% paired interval |
| --- | ---: | ---: | ---: | ---: |
| Fresh | 12,168.5 ms | 12,470.7 ms | 0.9994 | 0.9567–1.0441 |
| Advanced | 11,207.5 ms | 11,000.0 ms | 0.9811 | 0.9410–1.0232 |
| Dense | 4,804.6 ms | 4,832.2 ms | 0.9951 | 0.9511–1.0432 |

The paired geometric ratio differs from the ratio of the two medians. Intervals
use 10,000 paired log-ratio bootstrap resamples. All intervals cross one: there
was **no statistically detected browser slowdown**, with finite uncertainty,
rather than proof that every future run or platform has identical speed.

Fresh and advanced cover ticks 0–1200. Dense replays through tick 4200, with a
3600-tick warmup and 600 timed actions; it renders 4209 frames including warmup
and recorded choices. Runs used Linux ARM64, Chromium 153.0.8010.12 and the same
separately supplied ARM64 Chromium system libraries on both sides. The only
console error was an attributed missing `/favicon.ico`, not a game asset or
JavaScript failure.

## Diagnostics and the ownership decision

Removing the recursive core column carriers was rejected after a controlled
same-compiler comparison: restoring them reduced Native replay time to a paired
ratio of 0.6209 (interval 0.5711–0.6722), while the browser comparison detected no
difference. No compensating game boxing rewrite was added. With the restored
core, Native code and allocated data match the old core under the same .40
compiler; the other adopted core changes add no generated Native work in this
consumer.

Counterexamples remain in the evidence. The first headless Native fresh cohort
reported 1.1989 (1.0532–1.3630); a CPU-11 repeat reported 0.9381
(0.7785–1.1021), so the 20% effect was not reproduced consistently. Supplementary
Bun fresh replay reported 1.1538 (1.0391–1.2894). These burst replays use
`advance` and a full-state endpoint fold, unlike the per-frame play loop.
**Native application window rendering and FPS were not measured.** Bun is not a
shipped play entry; advanced/dense Bun stress remained deferred. The original
nine-cohort receipt remains explicitly incomplete after a clean scheduling pause
and is not described as a passing campaign.

## Published program and functional checks

Actual Hub C/JS/MJS emissions match the measured private program after only the
package namespace rename in its identifier and qualified export-key encodings.
Both actual Native replay and co-op images have all 24 allocated ELF sections
byte-identical. The final full web build's `game.mjs` also matches that verified
public module exactly.

All three co-op scenarios compared complete record arrays: 1226 fresh, 1238
advanced and 4317 dense records. Only `summary.wallMs`, derived from `IO.now`, was
omitted. The following maintained checks passed with official .40, Node 24.20.0
and Clang 19.1.7:

- `npm run check:typescript`, including generated ABI, lint, formatting and boundary tests.
- `npm run build --prefix examples/survivors/web`, including Iroh Wasm and Astro.
- `npm run test:full-game:manual`: full Native run ended at tick 36786 with the required death, boss, chest, choice and evolution witnesses.
- `bash examples/survivors/check-proofs.sh`: all 66 `--verdict` entrypoints, retaining 60-second CPU/wall limits and the preference proof's 10-second limit.

The initial web build exposed .40's new `Base.Lost` name collision. The local
connection signal is now `ConnectionLost`, including both TypeScript producers,
laws/proofs and current docs; state transitions, fields and wire version are
unchanged. The initial proof run failed while constructing the Lean kernel. The
exact official kernel source was then built with Lean 4.34.0 into its normal
source-keyed cache; no `BENDTT` override or proof-budget increase was used. Failed
attempts remain retained separately from successful results.

Local receipts include `actual-hub-six-bind.json`,
`actual-hub-six-equivalence.json`, `connection-lost-game-emission-identity.json`,
`functional-results.json`, and the original per-command raw outputs. Temporary
measurement helpers were archived with verified hashes and removed; generated
builds and evidence are outside tracked source. No site was deployed.
