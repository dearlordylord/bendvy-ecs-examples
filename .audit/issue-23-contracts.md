# Transport migration contracts

Issue [23](https://github.com/dearlordylord/bendvy-ecs-examples/issues/23) defines the acceptance boundary. This record describes the pre-migration owners and fixed checks.

## Existing owners

| Responsibility | Current owner | Required owner |
| --- | --- | --- |
| Endpoint creation and native resources | Rust `Transport` | Rust executes Bend effects |
| Incoming acceptance | Rust accept loop | Bend, with bounded Rust offer handles |
| Connection attempt cancellation | Rust generation and browser epoch checks | Bend identities, with Rust cancellation guards |
| Send order, count and byte admission | `CoopTransport` Promise chain | Bend queue metadata and effects |
| Guest attempt and handshake deadline | `coop-browser.mts` | Bend policy, browser timer execution |
| Host handshake deadline | `coop-host.mts` | Bend policy, browser timer execution |
| Readiness, lobby, seat admission | Existing Bend policies | Existing Bend policies |
| Command and snapshot journals | Existing Bend policies | Existing Bend policies |
| Final application receipts and drain decision | `coop-finish.bend` with browser timers | Existing Finish policy with typed deadline effects |
| Frame ceiling, native waits and resource accounting | Rust | Rust |
| Byte codecs and presentation | Browser | Browser |

## Fixed qualification

Run the current browser check before migration from a fresh local build. Record its dirty source state. The check requires explicit joining, host start, a full four-player lobby, fifth-player refusal, shared pause and reserved-seat rejoin over real Iroh.

Retain the existing four-player gameplay, terminal settlement, stalled terminal receipt, transport cleanup, observation, snapshot codec and reliability scenarios. The 600 ms write-delay scenario establishes bounded overload, not playable latency. Keep native solo independent of Node.js and Iroh.

Use one deterministic event/effect seam for cancellation, stale completion, duplicate outcomes, old deadlines, simultaneous offers, send ordering, queue saturation and recovery. Assert exact bytes and bounds. Run native entry-point checks separately from Bend policy checks. Native completion, QUIC confirmation and application receipts remain distinct.

## Baseline observations

The initial working tree contains explicit-join and publication edits from before this task. Preserve them. The existing served build predates those edits and fails the current browser check while waiting for Join party. This smoke result does not qualify the source baseline.

Chromium initially fails to load `libatk-1.0.so.0`. Extracting Debian libraries under `/tmp/issue-23-chromium-libs` allows Chromium 153.0.8010.12 to launch. Run browser checks with `LD_LIBRARY_PATH=/tmp/issue-23-chromium-libs/root/usr/lib/aarch64-linux-gnu` in this environment. No repository dependency or system package changed.

The fresh baseline build waits for `/tmp/bendvy-parity-heavy.lock`, held by an unrelated active compiler job. Do not bypass or delete that lock.

The port 8718 observations above were later excluded because that server served another checkout. Port 8723 served this checkout by absolute path. Fresh baseline lobby/reconnect and cleanup passed there. Final qualification and its open gates are recorded in `research/coop-transport-lifecycle.md` and `research/coop-transport-qualification.json`.
