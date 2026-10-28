# Endpoint lifecycle design

The caller keeps an asynchronous transport facade. Each facade owns one Bend value. Native callbacks enqueue identified events. One drain commits each transition before executing its ordered effects. Bytes, invitation capabilities and native objects stay in bounded maps outside Bend.

## Candidate comparison

A unified endpoint reducer owns phase, operation identities, send metadata and application deadlines. Disconnect changes phase and clears queued work in one transition. A split lifecycle and writer design would need a top-level reducer to coordinate cancellation and completion. Without that owner, it reproduces the existing split state. Prefer the unified reducer.

The existing Connection, Lobby, ClientDelivery, SnapshotFlow and Finish modules retain their semantic decisions. Transport connectivity never implies readiness. Timer effects carry an identified deadline; readiness expiry reports a local Timeout to Connection. Finish still decides final receipt satisfaction and bounded drain.

## Data contract

Use typed operation, connection, offer, request and deadline references. Never wrap exhausted IDs. Endpoint phases are Dormant, Creating, Available, Connecting, Accepting, Connected and Closed. A writer records its operation, connection and pending request. Pending metadata records request reference, byte size and whether QUIC confirmation is requested. Admission counts the active writer within 16 messages and 4 MiB. Frame size remains 1 MiB.

The transition returns committed State and ordered Effects. Events include explicit local creation, join and send requests; native offers; identified create, join, accept and write outcomes; authenticated messages and departures; identified timer firings; readiness updates; and close. Effects execute native operations, dispose stale resources, schedule or cancel deadlines, and settle or notify callers.

Rust owns Iroh objects, cryptographic identities, address codecs, relay configuration, watchdogs, cancellation and hard bounds. It exposes bounded single-use offers before acceptance. An offer is not a trusted peer. Only Iroh authentication supplies peer identity. Native outcomes identify the operation and connection so stale failures cannot clear newer work.

## Verification order

Capture the current dirty source baseline before production migration. Qualify pure transitions and deterministic executor behavior before replacing callers. Qualify Rust raw-entry bounds independently. Rebuild and run real-Iroh browser, terminal settlement, cleanup, reliability, native solo and proof gates after all callers migrate. Passing pure tests cannot replace the browser gate.
