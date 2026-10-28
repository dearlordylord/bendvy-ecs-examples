import assert from "node:assert/strict"
import { resolve } from "node:path"
import { pathToFileURL } from "node:url"
import { bendModule } from "../bend-module.mts"
import { list, rows } from "./host-values.mts"

const root = pathToFileURL(resolve(process.argv[2] ?? "examples/survivors/dist") + "/")
const { default: P } = await bendModule<BendABI.CoopTransportPolicy.API>()(new URL("coop-transport-policy.mjs", root), [
  "fresh",
  "step",
  "pending_count",
  "pending_bytes",
  "connected",
  "closed",
  "can_send"
])
type State = BendABI.CoopTransportPolicy.State
type Effect = BendABI.CoopTransportPolicy.Effect
let checks = 0
function run(state: State, event: BendABI.CoopTransportPolicy.Signal, now = 100) {
  const out = P.step(state, event, now)
  checks++
  return { state: out.state, effects: rows(out.effects) }
}
function effect<K extends Effect["$"]>(effects: Effect[], kind: K): Extract<Effect, { $: K }> {
  const found = effects.find((item): item is Extract<Effect, { $: K }> => item.$ === kind)
  if (found) return found
  throw Error(`Missing ${kind} effect`)
}
function available() {
  const created = run(P.fresh(), { $: "Begin", request: 1, role: { $: "HostEndpoint" } })
  const operation = effect(created.effects, "Create").operation
  const out = run(created.state, { $: "Created", operation, success: true })
  assert.equal(out.state.phase.$, "Available")
  assert.equal(effect(out.effects, "Settle").success, true)
  assert.deepEqual(run(out.state, { $: "Created", operation, success: true }).effects, [])
  return out.state
}
function connected() {
  const joining = run(available(), { $: "Join", request: 2, candidates: list([10, 20, 30]) })
  const connect = effect(joining.effects, "Connect")
  const out = run(joining.state, {
    $: "ConnectedEvent",
    operation: connect.operation,
    connection: connect.operation,
    peer: "authenticated"
  })
  assert.equal(effect(out.effects, "NotifyConnected").candidate, 10)
  assert.equal(effect(out.effects, "SettleJoin").selected, 10)
  assert.equal(P.connected(out.state), true)
  return { state: out.state, connection: connect.operation }
}
{
  const start = run(P.fresh(), { $: "Begin", request: 1, role: { $: "HostEndpoint" } }, 100)
  const timer = effect(start.effects, "Schedule")
  assert.equal(timer.after, 45000)
  assert.equal(effect(run(start.state, { $: "Deadline", id: timer.id }, 200).effects, "Schedule").after, 44900)
  const timed = run(start.state, { $: "Deadline", id: timer.id }, 45100)
  assert.equal(P.closed(timed.state), true)
  assert.equal(effect(timed.effects, "Settle").success, false)
  const late = run(timed.state, { $: "Created", operation: effect(start.effects, "Create").operation, success: true })
  assert.deepEqual(late.effects, [{ $: "CloseEndpoint" }])
  assert.deepEqual(run(late.state, { $: "CloseRequest" }).effects, [])
}
{
  let joined = run(available(), { $: "Join", request: 2, candidates: list([10, 20, 30]) })
  const old = effect(joined.effects, "Connect").operation
  joined = run(joined.state, { $: "AttemptFailed", operation: old })
  assert.equal(effect(joined.effects, "Connect").candidate, 20)
  assert.deepEqual(run(joined.state, { $: "AttemptFailed", operation: old }).state, joined.state)
  const stale = run(joined.state, { $: "ConnectedEvent", operation: old, connection: old, peer: "old" })
  assert.deepEqual(stale.effects, [{ $: "Disconnect", connection: old }])
  joined = run(joined.state, { $: "AttemptFailed", operation: effect(joined.effects, "Connect").operation })
  assert.equal(effect(joined.effects, "Connect").candidate, 30)
  joined = run(joined.state, { $: "AttemptFailed", operation: effect(joined.effects, "Connect").operation })
  assert.equal(effect(joined.effects, "SettleJoin").success, false)
  assert.equal(joined.state.phase.$, "Available")
}
{
  const accepted = run(available(), { $: "Incoming", offer: 1 })
  const accept = effect(accepted.effects, "Accept")
  const queued = run(accepted.state, { $: "Incoming", offer: 2 })
  assert.deepEqual(queued.effects, [])
  const retry = run(queued.state, { $: "AttemptFailed", operation: accept.operation })
  assert.equal(effect(retry.effects, "Accept").offer, 2)
  const authenticated = run(queued.state, {
    $: "ConnectedEvent",
    operation: accept.operation,
    connection: accept.operation,
    peer: "admitted"
  })
  assert.equal(effect(authenticated.effects, "Refuse").offer, 2)
  const cancelled = run(queued.state, { $: "DisconnectRequest" })
  assert.equal(effect(cancelled.effects, "Refuse").offer, 2)
  const late = run(cancelled.state, {
    $: "ConnectedEvent",
    operation: accept.operation,
    connection: accept.operation,
    peer: "late"
  })
  assert.deepEqual(late.effects, [{ $: "Disconnect", connection: accept.operation }])
}
{
  const accepting = run(available(), { $: "Incoming", offer: 1 })
  let state = accepting.state
  for (let offer = 2; offer <= 17; offer++) {
    const queued = run(state, { $: "Incoming", offer })
    assert.deepEqual(queued.effects, [])
    state = queued.state
  }
  assert.deepEqual(run(state, { $: "Incoming", offer: 18 }).effects, [{ $: "Refuse", offer: 18 }])
  assert.deepEqual(
    run(state, { $: "CloseRequest" })
      .effects.filter((item) => item.$ === "Refuse")
      .map((item) => item.offer),
    Array.from({ length: 16 }, (_, index) => index + 2)
  )
}
{
  const { state, connection } = connected()
  assert.deepEqual(
    run(state, { $: "ConnectedEvent", operation: connection, connection, peer: "authenticated" }).effects,
    []
  )
  assert.deepEqual(run(state, { $: "Received", connection, peer: "forged", request: 3 }).effects, [])
  assert.deepEqual(
    run(state, { $: "Received", connection: connection - 1, peer: "authenticated", request: 3 }).effects,
    []
  )
  assert.equal(
    effect(run(state, { $: "Received", connection, peer: "authenticated", request: 3 }).effects, "NotifyMessage")
      .request,
    3
  )
  assert.deepEqual(run(state, { $: "Departed", connection: connection - 1, peer: "authenticated" }).state, state)
  assert.deepEqual(run(state, { $: "Incoming", offer: 12 }).effects, [{ $: "Refuse", offer: 12 }])
}
{
  const session = connected()
  let state = session.state
  let writer: Extract<Effect, { $: "Write" }> | undefined
  for (let i = 0; i < 16; i++) {
    const queued = run(state, { $: "Send", request: 100 + i, bytes: 1, confirm: i === 0 })
    if (i === 0) writer = effect(queued.effects, "Write")
    else assert.deepEqual(queued.effects, [])
    state = queued.state
  }
  assert.equal(P.pending_count(state), 16)
  assert.equal(P.pending_bytes(state), 16)
  const full = run(state, { $: "Send", request: 117, bytes: 1, confirm: false })
  assert.equal(effect(full.effects, "Settle").reason.$, "QueueFull")
  assert.deepEqual(full.state, state)
  assert.ok(writer)
  assert.equal(writer.confirm, true)
  const completed = run(state, {
    $: "Written",
    operation: writer.operation,
    connection: session.connection,
    success: true
  })
  assert.equal(effect(completed.effects, "Settle").request, 100)
  assert.equal(effect(completed.effects, "Write").request, 101)
  assert.equal(P.pending_count(completed.state), 15)
  assert.deepEqual(
    run(completed.state, { $: "Written", operation: writer.operation, connection: session.connection, success: false })
      .state,
    completed.state
  )
  const restored = run(completed.state, { $: "Send", request: 118, bytes: 1, confirm: false })
  assert.equal(P.pending_count(restored.state), 16)
  const closed = run(restored.state, { $: "CloseRequest" })
  assert.equal(closed.effects.filter((item) => item.$ === "Settle").length, 16)
  assert.equal(P.pending_count(closed.state), 0)
  assert.equal(P.pending_bytes(closed.state), 0)
  assert.deepEqual(
    run(closed.state, { $: "Written", operation: writer.operation, connection: session.connection, success: true })
      .effects,
    []
  )
}
{
  let { state } = connected()
  for (let i = 0; i < 4; i++) state = run(state, { $: "Send", request: i + 10, bytes: 1048576, confirm: false }).state
  assert.equal(P.pending_bytes(state), 4194304)
  assert.equal(
    effect(run(state, { $: "Send", request: 20, bytes: 1, confirm: false }).effects, "Settle").reason.$,
    "QueueFull"
  )
  assert.equal(
    effect(run(state, { $: "Send", request: 21, bytes: 1048577, confirm: false }).effects, "Settle").reason.$,
    "FrameTooLarge"
  )
}
{
  const session = connected()
  const oldTimer = session.state.handshake
  assert.equal(oldTimer.$, "Some")
  const disconnected = run(session.state, { $: "DisconnectRequest" })
  const accepting = run(disconnected.state, { $: "Incoming", offer: 20 })
  const accept = effect(accepting.effects, "Accept")
  const rejoined = run(accepting.state, {
    $: "ConnectedEvent",
    operation: accept.operation,
    connection: accept.operation,
    peer: "new"
  })
  if (oldTimer.$ === "Some")
    assert.deepEqual(run(rejoined.state, { $: "Deadline", id: oldTimer.value.id }, 100000).state, rejoined.state)
  const drain = run(rejoined.state, { $: "Arm", kind: { $: "GuestDrain" } }, 200)
  assert.equal(effect(drain.effects, "Schedule").after, 25000)
  const fired = run(drain.state, { $: "Deadline", id: effect(drain.effects, "Schedule").id }, 25200)
  assert.equal(effect(fired.effects, "NotifyTimeout").kind.$, "GuestDrain")
  assert.equal(P.connected(fired.state), true, "The deadline reports to the existing receipt policy")
}
{
  const start = run(P.fresh(), { $: "Begin", request: 1, role: { $: "GuestEndpoint" } })
  const out = run(start.state, { $: "Created", operation: effect(start.effects, "Create").operation, success: true })
  assert.deepEqual(run(out.state, { $: "Incoming", offer: 99 }).effects, [{ $: "Refuse", offer: 99 }])
}
{
  const lobby: BendABI.CoopLobby.State = { $: "State", started: false, seats: list([]), inputEpoch: 0 }
  const pending = run(available(), { $: "Incoming", offer: 70 })
  const operation = effect(pending.effects, "Accept").operation
  const denied = run(pending.state, { $: "Room", terminal: true, lobby, seat: 1 })
  assert.equal(denied.state.phase.$, "Available", "Terminal admission cancels an in-progress acceptance")
  assert.equal(effect(denied.effects, "Disconnect").connection, 0)
  assert.deepEqual(run(denied.state, { $: "ConnectedEvent", operation, connection: operation, peer: "late" }).effects, [
    { $: "Disconnect", connection: operation }
  ])
  assert.deepEqual(run(denied.state, { $: "Incoming", offer: 71 }).effects, [{ $: "Refuse", offer: 71 }])
  const current = connected()
  const draining = run(current.state, { $: "Room", terminal: true, lobby, seat: 1 })
  assert.equal(P.connected(draining.state), true, "Existing connected peers retain the final receipt drain")
  const outsider = run(available(), { $: "Room", terminal: false, lobby: { ...lobby, started: true }, seat: 1 })
  assert.deepEqual(run(outsider.state, { $: "Incoming", offer: 72 }).effects, [{ $: "Refuse", offer: 72 }])
}
{
  const active = connected()
  const writing = run(active.state, { $: "Send", request: 40, bytes: 1, confirm: false })
  const write = effect(writing.effects, "Write")
  const failed = run(writing.state, {
    $: "Written",
    operation: write.operation,
    connection: active.connection,
    success: false
  })
  assert.equal(
    effect(failed.effects, "Settle").success,
    false,
    "A failed native write cannot acknowledge an application command"
  )
}
{
  const idle = available()
  const exhausted = { ...idle, epoch: 4294967295 }
  assert.deepEqual(
    run(exhausted, { $: "DisconnectRequest" }).state,
    exhausted,
    "Repeated idle disconnect does not consume epochs"
  )
  const active = connected().state
  assert.equal(
    P.closed(run({ ...active, epoch: 4294967295 }, { $: "DisconnectRequest" }).state),
    true,
    "An exhausted epoch fails closed"
  )
  const invalid = run(idle, { $: "Join", request: 2, candidates: list([1, 2, 3, 4]) })
  assert.equal(effect(invalid.effects, "SettleJoin").success, false, "Candidate storage is bounded")
}
{
  const active = connected()
  const draining = run(active.state, { $: "Arm", kind: { $: "Drain" } }, 100)
  const timer = effect(draining.effects, "Schedule")
  const departed = run(draining.state, { $: "Departed", connection: active.connection, peer: "authenticated" }, 200)
  assert.equal(
    departed.effects.some((row) => row.$ === "CancelTimer" && row.id === timer.id),
    false,
    "Peer departure cannot cancel the endpoint's room drain"
  )
  assert.equal(
    effect(run(departed.state, { $: "Deadline", id: timer.id }, 20100).effects, "NotifyTimeout").kind.$,
    "Drain"
  )
}
{
  const start = run(P.fresh(), { $: "Begin", request: 1, role: { $: "GuestEndpoint" } }, 0)
  const timer = effect(start.effects, "Schedule")
  const endpoint = run(
    start.state,
    { $: "Created", operation: effect(start.effects, "Create").operation, success: true },
    40000
  )
  assert.equal(
    endpoint.effects.some((row) => row.$ === "CancelTimer" && row.id === timer.id),
    false,
    "Guest endpoint creation retains its original attempt deadline"
  )
  const joining = run(endpoint.state, { $: "Join", request: 2, candidates: list([1, 2]) }, 40000)
  assert.equal(
    joining.effects.some((row) => row.$ === "Schedule"),
    false,
    "Joining cannot extend the original guest attempt budget"
  )
  const retry = run(
    joining.state,
    { $: "AttemptFailed", operation: effect(joining.effects, "Connect").operation },
    44000
  )
  const expired = run(retry.state, { $: "Deadline", id: timer.id }, 45000)
  assert.equal(effect(expired.effects, "SettleJoin").success, false)
  assert.equal(effect(expired.effects, "Disconnect").connection, 0)
}
console.log(
  JSON.stringify({
    status: "PASS",
    checks,
    scope:
      "production Bend transport lifecycle, stale identities, admission, ordered bounded sends, cancellation and deadlines"
  })
)
