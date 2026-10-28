# Bend transport lifecycle

Issue [23](https://github.com/dearlordylord/bendvy-ecs-examples/issues/23) moves application-visible transport lifecycle and send scheduling into Bend while retaining Iroh and the host-authoritative simulation.

## Ownership

`coop-transport-policy.bend` owns endpoint phase, connection attempts, invitation candidate retries, incoming admission, operation identities, send admission and order, and application deadline decisions. Each browser endpoint has one owner. Its event queue commits a Bend transition before executing the returned effects, including when native callbacks fire synchronously.

`coop-transport.mts` executes those effects. It keeps opaque invitation, byte, native and timer references and reports outcomes through the same typed boundary used by deterministic tests. It copies admitted payload bytes. Incoming traffic uses authenticated Iroh connection identity. Diagnostic text does not contain invitation capabilities.

Rust owns Iroh endpoints, connections and streams, cryptographic identity, address tickets, the self-hosted relay, cancellation, native watchdogs and resource safety. Incoming attempts become bounded single-use offers. Bend chooses acceptance or refusal before authentication binds a peer. Native callbacks identify their connection and operation. Stale disconnects cannot close a newer connection. Native guards also apply to callers that bypass Bend.

The existing Connection, Lobby, Session, ClientDelivery, SnapshotFlow and Finish policies remain responsible for their respective application rules. Transport connectivity does not establish world readiness. Native write completion, optional QUIC confirmation and application snapshot receipts remain distinct. Final settlement still waits for Finish receipts or its drain deadline. The migration changes no gameplay wire format, prediction, interpolation, command journal or snapshot codec.

## Resource limits

The Bend send queue includes its active writer within sixteen messages and 4 MiB. One write executes at a time. Browser and Rust reject frames above 1 MiB. The browser event bridge has count and byte bounds and terminates the endpoint on overflow.

Rust bounds incoming offers, outstanding connection operations, concurrent native sends and retained send bytes. Offers expire and can be consumed once. Creation, connect, accept and incomplete stream operations retain 20-second native watchdogs. These watchdogs protect native resources independently of Bend application deadlines. One abortable task expires the offer store. Endpoint close invalidates outstanding work and releases the native callback. Peer-only disconnect retains the endpoint and invitation.

## Qualification

The [qualification record](coop-transport-qualification.json) contains the final local build identity, artifact hashes, passing checks and open gates. Overall issue qualification is incomplete.

The source baseline was dirty `master` at `d937e1a04968e067f0c3b4a2da9b9c34212c0acb`, including pending explicit-join work. A fresh build passed actual-Iroh four-player admission, explicit host start, fifth-player refusal, shared pause, reserved-seat reconnect, terminal settlement, forged terminal receipts and repeated wrapper collection. Query and fragment invitation previews passed without loading the native endpoint factory.

The migration adds a repeatable `check-transport.sh` gate for production Bend transitions, kernel proofs, deterministic executor faults and semantic mutations. `coop-transport-native-check.mts` exercises actual Iroh raw entry points, including single-use offers, explicit admission, exact bytes, frame and byte bounds, stale disconnect and cancellation. `coop-transport-watchdog-check.mts` uses native fault peers to exercise oversized receive rejection, the 20-second stalled-frame watchdog, endpoint reuse and prompt close during an incomplete read. It verifies sixteen stored offers, refusal of a seventeenth attempt, expiry, and recovery of all sixteen slots with fresh clients before consuming an old handle. These checks passed against the final production build.

A separate trial reusing clients after their native connection attempts timed out failed while accepting a replacement handshake. All original attempts had rejected; the replacement outcome collection did not complete. The cause remains unknown. Ordinary cancellation and replacement passed the raw transport check, but retrying that same endpoint pair after native timeout remains unqualified.

The existing browser checks exercise the integrated game and cleanup. The final build passed explicit joining, query and fragment previews, four-player start, capacity refusal, shared pause, reserved-seat reconnect and repeated wrapper collection. Normal terminal receipts, forged receipts and first-seat departure while another receipt remained missing all released the three host endpoints and preserved the remaining result screens.

A fresh Linux native solo binary was compiled and launched with Node absent from `PATH`. Gameplay and profile settlement were observed on a temporary X11 display. A separate launch handled `WM_DELETE_WINDOW` and exited zero. The browser networking modules are outside the native import path.

The restored reliability checker retains the historical seed, trajectories, observation delay, send-delay matrix and thresholds. Initial baseline runs under concurrent heavy workloads failed historical lag windows and reached terminal gameplay before the active reconnect check. Those failures do not establish a migration regression or passing qualification. Missing receipt-latency and rejection metrics are marked unavailable, rather than zero. Full comparative reliability qualification remains open until recorded runs satisfy the unchanged criteria.

The full repository proof sweep failed at the unchanged `offline-policy/preference-PROOF.bend` under its existing 60-second CPU and wall limits. A standalone retry with the same limits also exited 137. The file hash matches the starting commit. The other 65 proof entrypoints passed, including the new transport proofs. This does not make the full proof gate pass.

Pure proofs establish only the stated Bend transitions. They do not prove browser scheduling, Rust, Wasm collection, Iroh, cryptography, latency or the entire game. Browser and native execution supply separate finite evidence. This change does not deploy or publish a release.
