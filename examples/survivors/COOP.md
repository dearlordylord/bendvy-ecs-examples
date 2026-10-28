# Browser co-op

This mode supports two to four players, including the host. Open `coop.html`,
choose setup and **Create room**, then share the invitation with up to three friends.
Opening an invitation shows the setup screen. Select **Join party** to connect; loading or previewing the link does not reserve a seat. Guests can change their survivor and arcana in the lobby until the host starts. The lobby shows all four
seats and their readiness. The host selects **Start run** when at least two players
are ready. The roster closes when the run starts. Players install nothing. Keep the host page
open; browser Iroh uses relays. Move with WASD, arrows or the touch pad. Attacks
are automatic; XP requires physical pickup. Opening the map is local.

Before the host starts, every player can change their survivor and arcana. The
host can also change the stage and mode after guests join. Guests see those shared
room settings even when the stage is locked in their own profile; the host controls
the destination. Starting locks all setup choices for the run.

Shared XP level-ups pause for each living player's choice; chests pause for their
collector. A fallen connected player stays at zero HP for 300 simulation ticks
(five seconds at 60 Hz). If another connected player is alive when the timer
expires, the fallen player revives with 30% maximum HP rounded down (minimum one)
and 180 ticks of invulnerability. The timer stops during reward and connection
pauses. If all players die together, the match ends. The host keeps the shared
world in memory. A guest reload can rejoin through the same invitation;
closing or reloading the host loses that run. There is no host migration.
A departing guest pauses the shared run. Reload the same guest URL and select **Join party** to reclaim its
reserved seat; the URL keeps a seat number after joining. Invitations are bearer
capabilities, so anyone holding a reserved seat link can reclaim it when free.

Ordinary enemy admission uses the solo stage budget plus 25% per additional
living player: two living players use 125%, three use 150%, and four use 175%.
The result rounds down and remains capped at 500. One living player keeps the
solo budget. This changes population admission only; enemy HP, damage, shared
XP and timed bosses retain their existing rules. It does not instantly remove
enemies already present when a player falls.

The native two-bot balance runner, paired seeds, pressure samples and offline
retrospective workflow are documented in
[the bot tools](../../tools/survivors-bot/README.md#balance-comparisons-and-retrospective-evidence).

At a terminal result, Bend progression settles each local player's profile once,
keyed by run and player. Departure or host loss is not a settlement receipt and
does not award an aborted run's accumulated rewards.

## Simulation and display

The host's Bend ECS simulation owns movement, damage, pickups, XP and rewards.
Browser JavaScript handles device input, Iroh bytes, worker scheduling, compression
and drawing. The native solo launch remains independent of Node and Iroh.

The guest predicts its own movement with immutable target world ticks. The host
applies a command only at its assigned tick; missing input is neutral and late
input is rejected. Reconciliation uses the authoritative anchor and retained
local inputs. The lead adapts monotonically on admitted authoritative observations;
existing command targets and sequence numbers remain unchanged. Known pauses
and death disable prediction.

Remote players, enemies and confirmed projectiles use one Bend interpolation
clock over at most eight authoritative snapshots. Startup and underrun have
separate refill rules; bounded emergency catch-up removes excess display lag.
Actors share a bracket and
fraction; recycled lifetimes are not interpolated together. The browser does not
forecast or replay the future world. Local projectile anticipation is cosmetic:
it captures the displayed muzzle, uses stable shot identities, and cannot change
HP, XP or rewards.

Confirmed contact receipts come from the same prepared host resolver used for
combat. Shot and target lifetimes identify the recipient. Bend maps confirmed
shot endpoints and effects to the displayed target trajectory, with a recorded
impact fallback when that lifetime is absent. Recent cosmetic history and effect
storage are bounded; canonical outcomes remain in the host snapshots. The host
emits at most the latest 512 ordered cosmetic receipts per step before network
serialization. Omitted receipts contribute to the cosmetic overflow counter;
damage, kills, XP and rewards are still resolved in full.

## Delivery and timing

Snapshot delivery permits sixteen application-unacknowledged observations, one
native write and one replaceable latest pending observation. A cumulative receipt
must name an actually sent observation from this connection. It is emitted after
guest parsing, admission and presentation. Native write completion and QUIC
acknowledgement do not mean the guest applied a snapshot.

Guest input uses a 64-command journal: at most 62 movement commands and two
reserved control entries. Ordered batches contain at most 32 commands. Admission
happens before prediction; a full journal stops further prediction instead of
inventing unsent movement. One shared client writer sends a `BSC1` packet carrying
an optional `BSB1` input batch and the latest snapshot ACK together. The input
journal and coalesced receipt history retain their separate bounds; they do not
compete through alternating native writes. Host and worker validate the whole
packet before consuming either child. Gzip is a bounded snapshot byte-transport
adapter; it contains no game decisions.

These limits bound pending work, not network latency. The 600 ms per native write
stress case can exceed the supported prediction lead and batch throughput.
That overload case checks bounded degradation and recovery, not playable input
response. A suspended host browser can stall everyone; the UI reports the stall
or failure rather than claiming a worker prevents suspension. Reload both peers
after a protocol update.

## Run and check

From the repository root, use the browser prerequisites in
[README.md](README.md#browser-launch), then run:

```sh
npm run build --prefix examples/survivors/web
npm run preview --prefix examples/survivors/web
```

Open http://127.0.0.1:8713/coop.html. Cross-device invitations require HTTPS.
Rebuild and restart preview after source changes. Publication uses the separate
[fresh-build procedure](README.md#publication).

```sh
bash examples/survivors/check-proofs.sh
```

For the scope of the kernel proofs, see the
[local projectile proof boundary](../../research/coop-local-projectiles-proof-boundary.md)
and [reliability plan](../../research/coop-reliability-plan.md).
The [results report](../../research/coop-reliability-results.md) records the
qualified scenarios and remaining limits.

After serving the build, run the real browser and Iroh check with Playwright:

```sh
node examples/survivors/coop-browser-check.mts http://127.0.0.1:8713/
node examples/survivors/coop-four-player-check.mts examples/survivors/dist/web/dist
```

The browser check creates a host and three guests, refuses a fifth player, starts
the run explicitly, then checks shared pause and reserved-seat rejoin. Playwright
requires its Chromium browser and operating-system dependencies. Captures go to
the system temporary directory. Cross-device timing still needs manual checks.

The repository-only [netcode skill](../../skills/realtime-netcode/SKILL.md) records
review rules and pitfalls. It is not installed globally. Primary-source reading
is collected in the [industry audit](../../research/coop-reliability-industry-audit.md).

### Typed observations and byte delivery

`Game.Packet` and `CorePacket` carry typed Bend observations. `None` means no
observation; co-op `Clock` carries step/contact receipts and `Display` carries the
presentation projection plus the detached prediction scene. Host adapters only
reshape Bend collections for drawing. Local Bend and worker results are trusted
through generated ABI types; they are not fully parsed again at runtime.

The worker projects `Core.NetworkView` from authoritative state and encodes
`CoopNetwork.Snapshot` as standard CBOR with pinned cborg. Each shared session,
player record and visible actor appears once. Actors retain their original mixed
order, status, trajectory, ownership, visits and lifetime data. Bend reconstructs
the existing observation and prediction scene with the same `view_observation`
function used by the local view. Inactive pool entries and internal indexes do
not cross the wire. Each snapshot is complete, including after reconnect.

The wire uses positional constructor variants and flat bounded sequences. The
existing ABI generator derives field layouts and numeric ranges from Bend.
Finite fractional values round-trip exactly without coordinate quantization.
The `BCB1` frame contains gzip-compressed CBOR and remains within Iroh's 1 MiB
message limit. Gzip CRC and size checks precede CBOR admission. The tokenizer
rejects excessive depth, container lengths, strings and total token counts before
recursive decoding. Maps, tags, indefinite lengths, undefined values, non-finite
numbers, malformed UTF-8 and trailing bytes are rejected.

`commandAck` is the guest command admission sequence used for input timing.
It is distinct from the application receipt for a token and observation. The
unused resolved-input receipt is absent. Rejected-input diagnostics remain in
`inputTiming`. The compressed queue, connection fencing, latest pending snapshot,
application receipt window and snapshot cadence retain their existing behavior.

After `bash examples/survivors/build-web.sh`, run the existing boundary checks:

```sh
node examples/survivors/observations-check.mts examples/survivors/dist/web/dist
node examples/survivors/coop-snapshot-codec-check.mts examples/survivors/dist/web/dist/coop-connection.mjs
npm run check:typescript
```

The observation check covers phases, admission, reconnect, actor and contact
identities, spectator views, ownership, ordering and input diagnostics through
the production CBOR and gzip boundary. The codec check covers byte and queue
bounds.

Completed runs release the room automatically. The final defeat or victory
observation is published to every connected guest before the simulation worker
stops. The host waits for application receipts bound to each guest's connection
token and final observation. Native write completion is insufficient. A 20 second
drain deadline bounds retention when a guest disappears or stops acknowledging.
All three host endpoints close, including vacant seats. Guests retain their result
screen and saved progression. The invitation cannot reopen the completed run.
Active runs retain the existing pause and reserved-seat reconnect behavior.

After a fresh web build, check this lifecycle with:

```sh
node examples/survivors/coop-finish-check.mts examples/survivors/dist/web/dist
node examples/survivors/coop-finish-browser-check.mts http://127.0.0.1:8718/
node examples/survivors/coop-finish-browser-check.mts http://127.0.0.1:8718/ --stalled-receipt
node examples/survivors/coop-transport-cleanup-check.mts http://127.0.0.1:8718/coop.html
```

Serve `examples/survivors/dist/web` at the indicated URL. The browser lifecycle
check injects a terminal Bend session through a test-only worker response route.
The shipped worker has no test command. The stalled receipt scenario forges a
future observation to verify receipt rejection and bounded closure. The transport
check exercises peer reconnect and garbage collection across repeated rooms.
