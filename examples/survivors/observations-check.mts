import assert from "node:assert/strict"
import { resolve } from "node:path"
import { pathToFileURL } from "node:url"
import { bendModule } from "../bend-module.mts"
import { defined, list, rows } from "./host-values.mts"
import { gameFrame, coreFrame } from "./observations.mts"
import { snapshotValues, admitSnapshot, encodeSnapshotValues, decodeSnapshotValues } from "./snapshot-envelope.mts"
import { encodeSnapshot, decodeSnapshot } from "./coop-snapshot-codec.mts"
const directory = resolve(defined(process.argv[2]))
const url = (name: string) => pathToFileURL(resolve(directory, `${name}.mjs`))
const [{ default: Game }, { default: Core }, { default: Connection }, { default: Session }, { default: Journal }] =
  await Promise.all([
    bendModule<BendABI.Game.API>()(url("game"), ["start_seed", "observe", "observation"]),
    bendModule<BendABI.CoopCore.API>()(url("coop-core"), [
      "core_start",
      "core_observe",
      "core_clock",
      "core_network_observe",
      "restore_network",
      "scheduled_record",
      "resolve_revives"
    ]),
    bendModule<BendABI.CoopConnection.API>()(url("coop-connection"), [
      "protocol_version",
      "fresh",
      "reconnect",
      "step",
      "running"
    ]),
    bendModule<BendABI.CoopSession.API>()(url("coop-session"), ["fresh", "last_seq"]),
    bendModule<BendABI.CoopHitJournal.API>()(url("coop-hit-journal"), ["fresh", "attach", "play"])
  ])
const packet = Game.start_seed(0, 0, 12345)
if (packet.$ !== "Packet") throw Error(packet.error)
const observed = Game.observe(packet.state)
const spatial = { $: "Spatial", x: 100, y: 200, age: 3, radius: 8 } satisfies BendABI.EnemySpatial.Spatial
const items: BendABI.PickupState.Item[] = [
  { $: "Xp", amount: 7, accumulator: true },
  { $: "Gold", coins: 13 },
  { $: "Healing", health: 17 },
  { $: "Chest" },
  { $: "Relic", stage: 2 }
]
const snapshots: BendABI.GameObservation.Snapshot[] = items.map((item, index) => ({
  $: "PickupSnapshot",
  pickup: {
    $: "State",
    spatial,
    payload: { $: "Payload", item, generation: index + 10, active: true },
    identity: index + 100
  }
}))
snapshots.splice(2, 0, {
  $: "EnemySnapshot",
  enemy: {
    $: "State",
    spatial,
    archetype: 4,
    identity: 21,
    vitals: { $: "Vitals", health: 20, maximum: 40 },
    status: {
      $: "Status",
      slow: { $: "Slow", ticks: 2, frozen: false },
      burn: { $: "Burn", ticks: 3, sourcePlayer: { $: "Some", value: 1 } }
    }
  }
})
snapshots.unshift({
  $: "ProjectileSnapshot",
  projectile: {
    $: "State",
    spatial,
    identity: 31,
    side: { $: "PlayerShot" },
    payload: { $: "ShotPayload", weapon: 11, damage: 5, active: true },
    trajectory: {
      $: "Trajectory",
      vx: 1,
      vy: 2,
      life: 17,
      pierce: 2,
      visited: list([21]),
      weaponOwner: 0,
      logicalSlot: 3,
      sourcePlayer: { $: "Some", value: 1 }
    }
  }
})
const observation = Game.observation(
  { ...observed.observation.run, session: { ...observed.observation.run.session, tick: 20 } },
  observed.observation.offers,
  list(snapshots)
)
const direct = gameFrame(observation)
assert.equal(direct.players[0]?.reviveTick, 0)
assert.deepEqual(
  direct.pickups.map((p) => p.item.kind),
  ["xp", "gold", "healing", "chest", "relic"]
)
assert.equal(direct.actorOrder.length, 7)
assert.equal(direct.projectiles[0]?.lifetime, "1:17:0:3")
assert.equal(direct.enemies[0]?.lifetime, "enemy:21:17")
const started = Core.core_start(0, 0, 12345)
if (started.$ !== "CorePacket") throw Error(started.message)
const view = Core.core_observe(started.state, 0)
if (view.$ !== "CorePacket") throw Error(view.message)
assert.ok(coreFrame(view.observation))
const clock = Core.core_clock(view.state)
if (clock.$ !== "CorePacket") throw Error(clock.message)
assert.equal(clock.observation.$, "StepObservation")
assert.equal(coreFrame({ $: "NoObservation" }), null)
console.log("PASS current direct observation, all pickups, actors, ordering, lifetimes, packets")

const network = Core.core_network_observe(view.state, 0)
const initial: BendABI.CoopNetwork.Snapshot = {
  $: "Snapshot",
  connectionVersion: Connection.protocol_version(),
  token: 7,
  initial: true,
  view: network.view,
  runId: "protocol-regression",
  commandAck: Session.last_seq(Session.fresh(1).guest),
  observationSeq: 1,
  contactJournal: Journal.fresh(7),
  inputTiming: { $: "InputTiming", worldTick: 0, lastRejected: { $: "None" } }
}
const roundtrip = async (snapshot: BendABI.CoopNetwork.Snapshot) =>
  decodeSnapshotValues(await decodeSnapshot(await encodeSnapshot(encodeSnapshotValues(snapshot))))
const admitted = await roundtrip(initial)
assert.equal(admitted.connectionVersion, 1)
assert.deepEqual(Core.restore_network(admitted.view), view.observation)
for (const connectionVersion of [0, 2, 3, 4, 5, 0xffffffff])
  assert.throws(() => admitSnapshot(snapshotValues({ ...initial, connectionVersion })), TypeError)
const players = rows(network.view.players)
const own = defined(players[0])
const downed = Core.scheduled_record(own, { ...own.player, hp: 0 }, 10)
assert.equal(downed.reviveTick, 310)
const downedObservation = Core.restore_network({ ...network.view, players: list([downed]) })
if (downedObservation.$ !== "ViewObservation") throw Error("downed player observation")
const downedFrame = coreFrame(downedObservation)
if (!downedFrame || !("players" in downedFrame)) throw Error("downed player frame")
assert.equal(downedFrame.players[0]?.reviveTick, 310)
assert.equal(Core.scheduled_record(downed, downed.player, 11).reviveTick, 310)
const teammate = { ...own, id: 1 }
assert.deepEqual(rows(Core.resolve_revives(list([downed, teammate]), 309))[0], downed)
const restored = defined(rows(Core.resolve_revives(list([downed, teammate]), 310))[0])
assert.equal(restored.player.hp, Math.max(1, Math.floor((own.player.maxHp * 30) / 100)))
assert.equal(restored.player.invuln, 180)
assert.equal(restored.reviveTick, 0)
assert.deepEqual(rows(Core.resolve_revives(list([downed, { ...teammate, player: downed.player }]), 310))[0], downed)
assert.deepEqual(rows(Core.resolve_revives(list([downed, { ...teammate, connected: false }]), 310))[0], downed)
assert.equal(Core.scheduled_record(restored, { ...restored.player, hp: 0 }, 320).reviveTick, 620)
assert.equal(
  defined(rows(Core.resolve_revives(list([{ ...downed, player: { ...downed.player, maxHp: 2 } }, teammate]), 310))[0])
    .player.hp,
  1
)
for (const phase of [0, 1, 2, 3, 4]) {
  const state = { ...network.state, snapshots: list(snapshots), shared: { ...network.view.shared, phase, tick: 20 } }
  const expected = Core.core_observe(state, 0)
  if (expected.$ !== "CorePacket") throw Error(expected.message)
  const compact = Core.core_network_observe(expected.state, 0)
  const received = await roundtrip({ ...initial, view: compact.view, commandAck: 91 })
  const restored = Core.restore_network(received.view)
  assert.deepEqual(restored, expected.observation)
  assert.equal(received.commandAck, 91)
  assert.deepEqual(coreFrame(restored), coreFrame(expected.observation))
}
const deadPlayers = list([
  { ...own, player: { ...own.player, hp: 0, px: 1, py: 2 } },
  { ...own, id: 1, player: { ...own.player, hp: 30, px: 300, py: 400 } }
])
const spectator = { ...initial, view: { ...initial.view, players: deadPlayers } }
const spectatorView = Core.restore_network((await roundtrip(spectator)).view)
if (spectatorView.$ !== "ViewObservation") throw Error("spectator")
assert.equal(spectatorView.game.run.player.px, 300)
assert.equal(rows(spectatorView.forecast.players)[0]?.run.player.px, 1)
const poisoned = structuredClone(spectator)
if (poisoned.view.players.$ !== "Con") throw Error("player")
poisoned.view.players.head.player.hp = 123
assert.notDeepEqual(Core.restore_network((await roundtrip(poisoned)).view), spectatorView)
for (const changed of [
  snapshots.map((s) =>
    s.$ === "EnemySnapshot" ? { ...s, enemy: { ...s.enemy, vitals: { ...s.enemy.vitals, health: 19 } } } : s
  ),
  snapshots.map((s) =>
    s.$ === "EnemySnapshot" ? { ...s, enemy: { ...s.enemy, spatial: { ...s.enemy.spatial, x: 101 } } } : s
  ),
  snapshots.map((s) =>
    s.$ === "ProjectileSnapshot"
      ? {
          ...s,
          projectile: {
            ...s.projectile,
            trajectory: { ...s.projectile.trajectory, sourcePlayer: { $: "Some", value: 0 } }
          }
        }
      : s
  ),
  snapshots.map((s) =>
    s.$ === "PickupSnapshot" ? { ...s, pickup: { ...s.pickup, payload: { ...s.pickup.payload, generation: 99 } } } : s
  ),
  [...snapshots].reverse()
] satisfies BendABI.GameObservation.Snapshot[][]) {
  const original = { ...initial, view: { ...initial.view, snapshots: list(snapshots) } }
  const mutated = { ...original, view: { ...original.view, snapshots: list(changed) } }
  assert.notDeepEqual(Core.restore_network((await roundtrip(mutated)).view), Core.restore_network(original.view))
}
console.log(
  "PASS compact CBOR/gzip boundary, phases, exact actors, ownership, status, visits, order, pickups and spectator"
)

const hit: BendABI.CoopHitJournal.HitEvent = {
  $: "HitEvent",
  id: "confirmed:7:20:31:21",
  tick: 20,
  kind: 0,
  shotId: "1:17:0:3",
  shotSeed: 31,
  targetSeed: 21,
  targetGeneration: 17,
  fraction: 0.125,
  impactX: 100.1,
  impactY: -200.2,
  targetAtImpactX: 100,
  targetAtImpactY: 200,
  radius: 8,
  outcome: 0
}
const withContact = {
  ...initial,
  contactJournal: { ...initial.contactJournal, now: 20, events: list([hit]) },
  inputTiming: {
    $: "InputTiming",
    worldTick: 20,
    lastRejected: { $: "Some", value: { $: "RejectedInput", reason: 3, seq: 90, targetWorldTick: 19, worldTick: 20 } }
  }
} satisfies BendABI.CoopNetwork.Snapshot
const confirmed = await roundtrip(withContact)
assert.deepEqual(confirmed.contactJournal, withContact.contactJournal)
assert.deepEqual(confirmed.inputTiming, withContact.inputTiming)
const playback = Journal.attach(Journal.fresh(7))
const played = Journal.play(playback, confirmed.contactJournal, 20)
assert.deepEqual(rows(played.events), [hit])
assert.deepEqual(Journal.play(played.state, confirmed.contactJournal, 20).events, list([]))
for (const changed of [
  { ...hit, id: "changed" },
  { ...hit, targetGeneration: 18 },
  { ...hit, shotId: "1:18:0:3" }
]) {
  const incoming = await roundtrip({
    ...withContact,
    contactJournal: { ...withContact.contactJournal, events: list([changed]) }
  })
  assert.notDeepEqual(Journal.play(playback, incoming.contactJournal, 20), played)
}
for (const epoch of [7, 8]) {
  const received = await roundtrip({ ...withContact, token: epoch, observationSeq: epoch, initial: true })
  let host = Connection.reconnect(Connection.fresh({ $: "Host" }), epoch).state
  let guest = Connection.reconnect(Connection.fresh({ $: "Guest" }), epoch).state
  const stepHost = (signal: BendABI.CoopConnection.Signal) => {
    const out = Connection.step(host, epoch, signal)
    host = out.state
    return out.action
  }
  const stepGuest = (signal: BendABI.CoopConnection.Signal) => {
    const out = Connection.step(guest, epoch, signal)
    guest = out.state
    return out.action
  }
  assert.equal(stepGuest({ $: "Hello", version: 1, token: epoch }).$, "HelloAckAndSetup")
  stepHost({ $: "HelloAck", version: 1, token: epoch })
  assert.equal(stepHost({ $: "Setup" }).$, "PrepareWorld")
  assert.equal(stepHost({ $: "Prepared", observation: received.observationSeq }).$, "PublishInitial")
  assert.equal(Connection.running(host), false)
  assert.equal(
    stepGuest({
      $: "Frame",
      version: received.connectionVersion,
      token: received.token,
      observation: received.observationSeq
    }).$,
    "PresentSnapshot"
  )
  assert.equal(Connection.running(host), false)
  assert.deepEqual(coreFrame(Core.restore_network(received.view)), coreFrame(view.observation))
  assert.equal(
    stepGuest({ $: "SnapshotSeen", token: received.token, observation: received.observationSeq }).$,
    "SendReadyAck"
  )
  assert.equal(stepHost({ $: "ReadyAck", token: epoch - 1, observation: received.observationSeq }).$, "Nothing")
  assert.equal(Connection.running(host), false)
  assert.equal(
    stepHost({ $: "ReadyAck", token: received.token, observation: received.observationSeq }).$,
    "StartAndConfirm"
  )
  assert.equal(stepGuest({ $: "Started", token: epoch }).$, "GuestReady")
  assert.equal(Connection.running(host), true)
  assert.equal(Connection.running(guest), true)
  const stale = await roundtrip({ ...withContact, token: epoch - 1, observationSeq: 999 })
  assert.equal(
    Connection.step(guest, epoch - 1, { $: "Frame", version: 1, token: stale.token, observation: stale.observationSeq })
      .action.$,
    "Nothing"
  )
}
console.log(
  "PASS confirmed contacts, contact negative controls, diagnostic timing, initial handshake, reconnect and stale connection fencing"
)
