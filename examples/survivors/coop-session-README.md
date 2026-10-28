# Co-op command boundary

[Connection readiness](coop-connection.bend) is a separate Bend state machine.
Iroh connectivity only starts version negotiation. Setup prepares the world;
the host stays paused until the guest has applied and acknowledged the exact
initial observation. The host then confirms the start before guest prediction
and input advance. Repeated or stale acknowledgements cannot restart a run.
The worker keeps one connection state machine and input queue per remote seat.
The Bend lobby owns room admission and explicit host start. Its `running` decision
requires the frozen participant roster to be ready before the worker advances time.

The model also owns retry epochs, frame/version admission, failure reasons and
which deadlines can fail a handshake. Its control codec cannot decode local
`Prepared`, `SnapshotSeen`, `Timeout` or `Lost` events from peer bytes. The host
browser observes the worker's Bend state so its IO deadline can fail locally
when a worker cannot respond. Worker crashes are handled without asking that
failed worker to process its own error. Browser/transport adapters execute the
returned actions; the formal laws do not prove their IO implementation.

The public module contract is version one. Keep both tabs updated. A mismatch
is shown beside the guest heading; the static lobby does not assert that an
uncontacted host is available. Peer rejection retains the host endpoint and
invitation so a compatible guest can try again.

[Session admission](coop-session.bend) owns authenticated player binding,
sequence checks, movement expiration and acknowledgements.
[The protocol](coop-protocol.bend) owns command framing and canonical numeric
encoding. Their data declarations and functions are the authority for wire
shape, limits and timing policy.

The transport host supplies the authenticated identity; it must not trust an
identity from the message payload. Admission and game application are separate:
[the game core](coop-core.bend) validates actual setup and reward eligibility.
[Reward policy](coop-reward-policy.bend) supplies the admission decision and
remaining obligations used by that core.

The host advances the admission clock during reward pauses and acknowledges
input only after an actual game step. A movement command's intended tick is its
exact target world tick: a late command is rejected rather than shifted forward.
Transport sequence numbers and world ticks are different clocks. The
[worker](coop-worker.mts) connects these boundaries.

Movement commands use a separate lobby input generation in their `round` field.
The generation advances on a transport departure and on a reward-round change.
Old queued or delayed movement cannot enter the resumed generation. Reward choices
continue to carry the actual reward round. A shared pause stops guest prediction,
drops unsent movement, and clears every authoritative movement queue while
preserving snapshot receipts and in-flight transport identities.

## Separate clocks and prediction lead

The co-op path keeps packet identity, observation freshness, authoritative world
time and the guest's predicted display cursor separate. A command's `seq`
orders packets; `targetWorldTick` names the exact simulation tick it may affect.
Observation numbers reject stale snapshots. The authority anchor advances with
the host simulation, while the display cursor may run ahead to cover expected
input delay. Missing command rows remain neutral world ticks during replay.

The pure prediction module derives lead as
`min(54, ceil(min(ackDelayMs, 1000) * 60 / 1000) + 4)` ticks. This delay is measured
from command enqueue to host admission acknowledgement, including queues and the
return snapshot; it is not pure network RTT. Every admitted observation raises
the selected lead monotonically when that delay grows. The cursor is the maximum
of its previous value and the saturating new anchor plus lead. Existing sequence
numbers, target ticks and axes stay unchanged; newly exposed gaps remain neutral.
Lifecycle resets may choose a smaller lead. Late commands are rejected, never
silently shifted to a different gameplay tick.

A sustained delay beyond the capped lead is a degraded condition. In particular,
600 ms for each combined input/ACK write can exceed the timely-delivery budget
within this horizon. Overload checks establish bounded resources and explicit
late-input rejection, not playability under an arbitrary network delay.

## Protocol v5 and bounded delivery

The client keeps accepted commands in a bounded journal until their batch
completes. The bound is 64 total commands, including the active flight and
pending rows, with 62 movement slots and two reserved control slots. One flight
at a time carries up to 32 ordered commands in the `BSB1` envelope; its encoded
frame is limited to 5156 bytes. Completion must match the current connection
epoch and batch ID. Failure retains the journal and fences that flow, so an
accepted command is not reported as delivered merely because a write was
started.

A guest transport departure suspends the shared run without disconnecting the
stored player record or discarding its reward choice. The host keeps its Iroh
endpoint and invitation open. A new connection resets only the guest command
lane, receipt and queued inputs; the host lane, session ID and simulation state
remain intact. Opening an invitation waits for an explicit **Join party** action before joining its available or reserved seat. Before the run starts, admitted Setup updates rebuild the untouched lobby world from the host seed and each guest's selected setup. After start, Setup only attaches or resumes the existing player.
Rejoining returns the existing character, health, equipment and reward state,
regardless of the setup selected on the reloaded page. The snapshot rebuilds the
guest's prediction from current authority instead of replaying old local input.

The room invitation bundles three single-peer Iroh endpoints, one for each guest
seat. The browser retains the assigned seat in its URL for reload. Each endpoint
has its own handshake epoch, snapshot receipt window, and bounded writer.
The invitation is a bearer capability, not a durable account identity. Whoever
holds a seat link may fill that reserved seat once its connection is free. A connected guest cannot be replaced concurrently. Closing or reloading
the host destroys the in-memory world and endpoint; an old invitation cannot
restore that run. An ended admission session cannot be revived by reconnect.

The reconnect laws pin each private command session transition. Authenticated seat
admission checks the real player identity before mapping it to its private command
lane. Four-player attachment selects an existing record by player ID and retains
its state. The generic
[attachment dispatcher laws](coop-attach-LAWS.bend) prove that a two-player
attachment sends the original affine state directly to its resume adapter,
ignoring new setup. Production wires that adapter to `Core.completed`, which returns
the unchanged state; the full core wiring is checked by source review and
executed state equality. This is not a kernel proof of all game/core functions
or of browser/Iroh lifecycle behavior.

The [session laws](coop-session-LAWS.bend), [reward laws](coop-reward-policy-LAWS.bend),
[protocol laws](coop-protocol-LAWS.bend), prediction laws and [pickup laws](pickup-selection-LAWS.bend)
state their precise guarantees. The ordinary `check.sh` runs the proof entrypoints
directly with `bend --verdict`. From the repository root,
These laws prove pure Bend behavior. They do not establish end-to-end
browser/Iroh qualification. Universal wire encode/decode roundtrip across every
transport path and cross-platform floating-point determinism remain outside the
current proofs.

Snapshot delivery has a separate Bend journal (`coop-snapshot-flow.bend`): up to sixteen
application-unacknowledged observations, one native writer and one replaceable
latest pending observation. The guest sends the exact token/observation receipt only after
parsing, admission and `ui.present` complete. QUIC stream completion and byte
acknowledgement clear only the writer, never the application window.
`coop-client-delivery.bend` prepares input and the latest receipt in one `BSC1`
packet, with one shared native writer. It completes the stored child IDs and
preserves newer pending work; its outer frame limit is 5190 bytes.
Guest receipts coalesce to one latest pending receipt;
cumulative host-token/observation acknowledgements release the window. This bounds stale work; it cannot
promise a network latency bound. At high latency the snapshot cadence decreases
instead of building an ever older queue.

Both roles use `coop-hit-effects.bend` for confirmed contact effects. A receipt
first crossed during presentation recovery gets four display ticks from its
first delivery to that ledger. Duplicates cannot restart it; reconnect attaches
to the current journal without replaying old effects. These are cosmetic events;
health and progression remain authoritative host state.

The remote presentation clock has four Bend modes. Priming waits for its role's
initial delay (six guest ticks, three host ticks); after starvation, Holding
resumes at the first newer tick. Ordinary playback uses 60 Hz, or 66 Hz above
`delay + 1` received ticks of backlog. Emergency Boosting enters above
`delay + 4`, runs at 84 Hz until backlog reaches `delay + 1`, and resets on
starvation/history recovery/new stream. This is a bounded cosmetic speed tradeoff.
On readiness, elapsed credit is capped separately at 33,334 microseconds so a
background gap cannot become a large resume jump. All remote actors and
confirmed effects share that cursor; local movement and shot clocks retain
60 Hz budgets. A slow producer can still force short holds. This does not
promise continuous motion across arbitrary outages or overloaded host CPUs.

Snapshots use the browser gzip codec in `coop-snapshot-codec.mts`. One serial
receiver admits at most sixteen compressed jobs, including the active job, and
16 MiB of compressed input. Each complete decoded snapshot is limited to 1 MiB;
CRC/ISIZE must pass before bounded CBOR decoding and schema admission. The
`BCB1` frame carries a self-contained Bend snapshot. The CBOR tokenizer permits
at most 16,384 entries per container, 32 nested containers, 262,144 tokens and
4,096 bytes per string. Field validation enforces Bend numeric ranges. Tags,
maps, indefinite lengths, undefined values, non-finite numbers, invalid UTF-8
and trailing data are rejected. These IO limits do not establish a
1 MiB bound on browser-internal decompressor allocation.

The host may update its own survivor, arcana, stage and mode before the explicit
start. Bend validates the host setup and closes that operation once started. A
prestart edit rebuilds the untouched world from the same seed and stored player
setups without replacing connections. Lobby delivery includes the shared stage
and mode so guests display the host destination independently of local unlocks.
