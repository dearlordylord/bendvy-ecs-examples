# Survivors Iroh transport

Pinned: Iroh 1.4.1, Noq/Noq-proto 1.4.0, wasm-bindgen 0.2.122. This crate only
transports bytes. Bend decides the meaning and acceptance of application messages.

## Browser API

```js
import init, { Transport } from './iroh_transport.js';
await init();
const endpoint = await Transport.create(event => owner.enqueue(event));
const invite = endpoint.invitation();
await endpoint.join(invite, operationId);
await endpoint.acceptOffer(offerId, operationId);
endpoint.refuseOffer(offerId);
await endpoint.send(new Uint8Array([1, 2, 3]), false, connectionId);
endpoint.disconnectPeer(connectionId);
endpoint.close();
```

Incoming attempts produce opaque `incoming` offers. Bend chooses acceptance or
refusal. Each offer is single-use and expires after 20 seconds. Offers do not
provide an authenticated player identity. Successful Iroh authentication produces
`connected` with `operationId`, `connectionId`, and authenticated `peerId`.
Messages and departures carry that connection ID. Promise rejection reports the
outcome of the requested operation, rather than an unscoped callback error.

An endpoint holds one authenticated connection. `disconnectPeer(connectionId)`
closes only that connection and retains the invitation. Zero or an omitted ID
cancels its current pending operation or connection. A stale nonzero ID cannot
disconnect a replacement connection. Bend retains at most sixteen waiting offers
while one acceptance is pending. Failed authentication tries the oldest waiting
offer. Successful authentication refuses the remaining offers, preserving one
exclusive peer.
Recreate a closed endpoint;
it cannot be rebound. Bend refuses another offer while connected or connecting. A peer
disconnect leaves a still-open endpoint available for another connection. The
invitation serializes the endpoint ID and addressing information, not a private
key or a game authorization grant. Application admission belongs to the Bend
protocol layer. Keys and state exist only in memory.

One message uses one reliable QUIC unidirectional stream terminated by EOF, with
at most 1048576 bytes (1 MiB). The receiver reads one stream to completion before accepting
the next. **Callers must serialize sends** to preserve their application enqueue
order. The locked Noq-proto 1.4.0 `Streams::accept` returns monotonically increasing
remote stream indexes (`src/connection/streams/mod.rs:65`), including implicitly
opened lower indexes (`streams/state.rs:845–873`); the receiver consequently waits
for lower streams even when higher stream packets arrive first. The native probe
exercises a delayed first stream followed by 49 already-finished streams. This is
a pinned implementation dependency, not a general claim of cross-stream ordering
for every QUIC library. Review it when upgrading Noq or use a persistent framed
stream instead.

The native adapter rejects sends above 1048576 bytes (1 MiB), more than 16
concurrent sends, and more than 4 MiB of retained send bytes. It bounds stored
incoming offers and pending connection operations to sixteen each. These limits
also apply to callers that bypass Bend. One abortable expiry task services the
offer store. Closing releases stored offers, connections, callbacks and tasks.
Creating/connecting and incomplete incoming/outgoing frames have 20-second limits;
an idle healthy connection is not timed out by the application. Oversized or
stalled receive streams close that connection. Browser endpoints use only our
self-hosted relay at `https://quint-graph.fly.dev` (Iroh 1.4.1, Fly region `yyz`).
The custom relay map replaces the public development relay list; there is no
silent public-relay fallback. Browser endpoints remain relay-only; no NAT
traversal/direct-connect result is claimed. Existing invitation links from hosts
using public relays must be replaced after both browsers reload.

## Build and checks

The browser co-op mode uses this adapter directly. Rust transports encrypted bytes;
Bend owns game admission and simulation. There is no separate lab or chat UI.

Developer prerequisites: Rust 1.94+, the Wasm target and matching bindgen CLI:

```sh
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.122 --locked
bash tools/iroh-transport/build.sh /tmp/survivors-iroh
```

The regular Survivors web build invokes the script and packages its output at
`./iroh/`. Hosted players install nothing. Native solo does not need this toolchain.

From the repository root:

```sh
CARGO_TARGET_DIR=/tmp/bendvy-iroh-cargo-target cargo test --locked --features native-probe --manifest-path tools/iroh-transport/Cargo.toml --jobs 2
```

After serving a fresh Survivors build, run the browser boundary checks:

```sh
node examples/survivors/coop-transport-native-check.mts http://127.0.0.1:8713/coop.html
CARGO_TARGET_DIR=/tmp/bendvy-iroh-cargo-target cargo build --locked --features native-probe --bin iroh-native-probe --manifest-path tools/iroh-transport/Cargo.toml --jobs 2
node examples/survivors/coop-transport-watchdog-check.mts http://127.0.0.1:8713/coop.html /tmp/bendvy-iroh-cargo-target/debug/iroh-native-probe
```

The watchdog check uses native fault peers to bypass browser send admission. Its
`--fault oversized` and `--fault stalled` modes read the invitation from standard
input and do not print it. The check exercises receive bounds, stalled streams,
offer saturation and expiry, and endpoint reuse over actual Iroh. Two consecutive
connect timeouts each retry immediately on the same endpoints through the production
Bend admission policy and deliver exact bytes after authentication. Delayed expired
offer callbacks arrive before each replacement offer, so failed authentication
must preserve the waiting retry. The separate saturation check uses fresh clients
to isolate native offer-store capacity recovery.

The optional `iroh-native-probe` binary is a byte echo diagnostic, not a game
server or native Bend/Iroh FFI. Its loopback checks cover ordering and frame bounds;
they do not qualify macOS or cross-network direct connectivity.

## Game boundary

`examples/survivors/coop-transport-policy.bend` owns transport transitions,
identified operations, incoming admission and ordered send scheduling.
`coop-transport.mts` executes its effects through Rust and returns identified
outcomes. It copies byte payloads and serializes callbacks through one owner.
The send queue includes the active write within 16 messages and 4 MiB. The
callback bridge also has count and byte bounds. Both browser and Rust enforce
the 1 MiB frame ceiling. Normal sends do not wait for an acknowledgment. The optional
`confirmDelivery` adapter flag (second boolean argument in the Wasm API) waits
for QUIC to acknowledge the finished stream before a rejection closes the peer.
This is a transport receipt, not proof that the application processed it; ordinary
movement/snapshot sends retain their existing latency. The Bend readiness
handshake requires its own explicit snapshot-applied acknowledgment. Bend validates
commands and maps the authenticated connection to an allowed player.

Primary references: [browser example](https://github.com/n0-computer/iroh-examples/tree/main/browser-echo)
and [browser limitations](https://docs.iroh.computer/languages/wasm-browser).
