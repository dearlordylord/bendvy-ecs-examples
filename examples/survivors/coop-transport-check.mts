import assert from "node:assert/strict"
import test from "node:test"
import { list } from "./host-values.mts"
import {
  CoopTransport,
  type NativeEvent,
  type NativeTransport,
  type TransportEvent,
  type TransportIO
} from "./coop-transport.mts"

function deferred<T>() {
  return Promise.withResolvers<T>()
}
async function flush() {
  for (let i = 0; i < 8; i++) await Promise.resolve()
}
function observed<T>(promise: Promise<T>) {
  return promise.then(
    (value) => ({ ok: true as const, value }),
    (error) => ({ ok: false as const, error: String(error) })
  )
}
class FaultIO implements TransportIO {
  time = 0
  sequence = 0
  callback: ((event: NativeEvent) => void) | undefined
  creation = deferred<NativeTransport>()
  joins: { ticket: string; operation: number; result: ReturnType<typeof deferred<unknown>> }[] = []
  accepts: { offer: number; operation: number; result: ReturnType<typeof deferred<unknown>> }[] = []
  writes: { bytes: Uint8Array; confirm: boolean; connection: number; result: ReturnType<typeof deferred<unknown>> }[] =
    []
  refused: number[] = []
  disconnected: number[] = []
  closes = 0
  creates = 0
  current = 0
  timers = new Map<number, { callback: () => void; due: number; cancelled: boolean }>()
  native: NativeTransport = {
    endpointId: () => "local-authenticated-endpoint",
    invitation: () => "opaque-test-invitation",
    join: (ticket, operation) => {
      const result = deferred<unknown>()
      this.joins.push({ ticket, operation, result })
      return result.promise
    },
    acceptOffer: (offer, operation) => {
      const result = deferred<unknown>()
      this.accepts.push({ offer, operation, result })
      return result.promise
    },
    refuseOffer: (offer) => {
      this.refused.push(offer)
    },
    send: (bytes, confirm, connection) => {
      const result = deferred<unknown>()
      this.writes.push({ bytes, confirm, connection, result })
      return result.promise
    },
    disconnectPeer: (connection = 0) => {
      this.disconnected.push(connection)
      if (this.current !== 0 && (connection === 0 || this.current === connection)) {
        const current = this.current
        this.current = 0
        this.emit({ type: "disconnected", connectionId: current, peerId: `peer-${current}` })
      }
    },
    close: () => {
      this.closes++
      this.current = 0
      this.emit({ type: "closed" })
    }
  }
  constructor(ready = true) {
    if (ready) this.creation.resolve(this.native)
  }
  create = (callback: (event: NativeEvent) => void) => {
    this.creates++
    this.callback = callback
    return this.creation.promise
  }
  now = () => this.time
  schedule = (callback: () => void, milliseconds: number) => {
    const id = ++this.sequence
    this.timers.set(id, { callback, due: this.time + milliseconds, cancelled: false })
    return id
  }
  cancel = (timer: unknown) => {
    if (typeof timer !== "number") throw TypeError("Expected a test timer identity")
    const value = this.timers.get(timer)
    if (value) value.cancelled = true
  }
  emit(event: NativeEvent) {
    this.callback?.(event)
  }
  connect(operation: number) {
    this.current = operation
    this.emit({ type: "connected", operationId: operation, connectionId: operation, peerId: `peer-${operation}` })
  }
  receive(bytes = new Uint8Array([7]), connection = this.current, peer = `peer-${connection}`) {
    this.emit({ type: "message", connectionId: connection, peerId: peer, bytes })
  }
  fire(timer: number, at?: number) {
    const value = this.timers.get(timer)
    assert.ok(value, "the test fires a timer actually requested by the production policy")
    this.time = at ?? value.due
    value.callback()
  }
}
async function open(callback?: (event: TransportEvent) => void, io = new FaultIO()) {
  const events: TransportEvent[] = []
  const transport = await CoopTransport.create((event) => {
    events.push(event)
    callback?.(event)
  }, io)
  return { io, events, transport }
}
async function connect(transport: CoopTransport, io: FaultIO) {
  const joined = transport.join("opaque-test-invitation")
  const attempt = io.joins.at(-1)
  assert.ok(attempt)
  io.connect(attempt.operation)
  attempt.result.resolve(undefined)
  await joined
  return attempt.operation
}
function latestState(events: TransportEvent[]) {
  const event = events.at(-1)
  assert.ok(event)
  return event.state
}

await test("serialized sends retain exact copied bytes, order and confirmation mode", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  const first = new Uint8Array([0, 255, 3]),
    second = new Uint8Array([4, 5])
  const one = transport.send(first),
    two = transport.send(second, { confirmDelivery: true })
  first.fill(9)
  second.fill(8)
  assert.equal(io.writes.length, 1)
  assert.deepEqual(io.writes[0]?.bytes, new Uint8Array([0, 255, 3]))
  assert.equal(io.writes[0]?.confirm, false)
  io.receive()
  assert.equal(latestState(events).pendingSends, 2)
  assert.equal(latestState(events).pendingBytes, 5)
  io.writes[0]?.result.resolve(undefined)
  assert.equal((await one).byteLength, 3)
  await flush()
  assert.equal(io.writes.length, 2)
  assert.deepEqual(io.writes[1]?.bytes, new Uint8Array([4, 5]))
  assert.equal(io.writes[1]?.confirm, true)
  io.writes[1]?.result.resolve(undefined)
  assert.equal((await two).byteLength, 2)
  transport.close()
})

await test("the active writer counts toward the sixteen-message bound and capacity recovers", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  const sends = Array.from({ length: 16 }, (_, index) => transport.send(new Uint8Array([index])))
  await assert.rejects(transport.send(new Uint8Array([99])), /QueueFull/)
  assert.equal(io.writes.length, 1)
  io.receive()
  assert.equal(latestState(events).pendingSends, 16)
  for (let index = 0; index < 16; index++) {
    assert.deepEqual(io.writes[index]?.bytes, new Uint8Array([index]))
    io.writes[index]?.result.resolve(undefined)
    await sends[index]
    await flush()
  }
  const recovered = transport.send(new Uint8Array([100]))
  io.writes[16]?.result.resolve(undefined)
  await recovered
  io.receive()
  assert.equal(latestState(events).pendingSends, 0)
  assert.equal(latestState(events).pendingBytes, 0)
  transport.close()
})

await test("four MiB bounds active and queued bytes and rejects oversized frames", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  const frame = new Uint8Array(1024 * 1024)
  const sends = Array.from({ length: 4 }, () => transport.send(frame))
  await assert.rejects(transport.send(new Uint8Array([1])), /QueueFull/)
  await assert.rejects(transport.send(new Uint8Array(1024 * 1024 + 1)), /FrameTooLarge/)
  io.receive()
  assert.equal(latestState(events).pendingBytes, 4 * 1024 * 1024)
  for (let index = 0; index < 4; index++) {
    io.writes[index]?.result.resolve(undefined)
    await sends[index]
    await flush()
  }
  const recovered = transport.send(frame)
  io.writes[4]?.result.resolve(undefined)
  await recovered
  transport.close()
})

await test("failed writes reject their operation and do not report application receipts", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  const failed = observed(transport.send(new Uint8Array([1])))
  const next = transport.send(new Uint8Array([2]), { confirmDelivery: true })
  io.writes[0]?.result.reject(Error("injected native write failure"))
  assert.equal((await failed).ok, false)
  await flush()
  io.writes[1]?.result.resolve(undefined)
  await next
  assert.equal(events.filter((event) => event.type === "message").length, 0)
  transport.close()
})

await test("close rejects active and queued work once and ignores late write success", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  const active = observed(transport.send(new Uint8Array([1])))
  const queued = observed(transport.send(new Uint8Array([2])))
  transport.close()
  transport.close()
  assert.equal((await active).ok, false)
  assert.equal((await queued).ok, false)
  io.writes[0]?.result.resolve(undefined)
  await flush()
  assert.equal(io.writes.length, 1)
  assert.equal(io.closes, 1)
  assert.equal(events.filter((event) => event.type === "closed").length, 1)
  await assert.rejects(transport.send(new Uint8Array([3])))
})

await test("cancelled connection outcomes cannot replace or close a newer peer", async () => {
  const { io, events, transport } = await open()
  const oldJoin = observed(transport.join("old-invitation"))
  const old = io.joins.at(-1)
  assert.ok(old)
  transport.disconnectPeer()
  assert.equal((await oldJoin).ok, false)
  const connection = await connect(transport, io)
  old.result.reject(Error("late failure"))
  await flush()
  io.emit({
    type: "connected",
    operationId: old.operation,
    connectionId: old.operation,
    peerId: `peer-${old.operation}`
  })
  io.emit({ type: "disconnected", connectionId: old.operation, peerId: `peer-${old.operation}` })
  io.receive(new Uint8Array([99]), old.operation)
  io.receive(new Uint8Array([8]), connection, "forged-payload-peer")
  io.receive(new Uint8Array([9]), connection)
  assert.equal(io.current, connection)
  assert.equal(latestState(events).connected, true)
  assert.equal(events.filter((event) => event.type === "connected").length, 1)
  assert.deepEqual(
    events.filter((event) => event.type === "message").map((event) => event.bytes),
    [new Uint8Array([9])]
  )
  transport.close()
})

await test("reconnect fences pending write completion and old deadline events", async () => {
  const { io, events, transport } = await open()
  const firstConnection = await connect(transport, io)
  transport.syncReadiness({ $: "GuestHello", epoch: 1 })
  const oldTimers = [...io.timers.keys()]
  const active = observed(transport.send(new Uint8Array([1])))
  transport.disconnectPeer()
  assert.equal((await active).ok, false)
  const secondConnection = await connect(transport, io)
  assert.notEqual(secondConnection, firstConnection)
  transport.syncReadiness({ $: "GuestRunning", epoch: 3, token: 3 })
  const next = transport.send(new Uint8Array([2]))
  io.writes[0]?.result.resolve(undefined)
  for (const timer of oldTimers) io.fire(timer, io.time + 50000)
  await flush()
  io.receive()
  assert.equal(latestState(events).pendingSends, 1)
  assert.equal(events.filter((event) => event.type === "timeout").length, 0)
  io.writes[1]?.result.resolve(undefined)
  await next
  transport.close()
})

await test("simultaneous incoming offers accept one and refuse competitors without trusted payload identities", async () => {
  const { io, events, transport } = await open()
  io.emit({ type: "incoming", offerId: 7 })
  io.emit({ type: "incoming", offerId: 8 })
  io.emit({ type: "incoming", offerId: 9 })
  assert.equal(io.accepts.length, 1)
  assert.deepEqual(io.refused, [8, 9])
  const accepted = io.accepts[0]
  assert.ok(accepted)
  io.connect(accepted.operation)
  accepted.result.resolve(undefined)
  io.emit({
    type: "connected",
    operationId: accepted.operation,
    connectionId: accepted.operation,
    peerId: `peer-${accepted.operation}`
  })
  assert.equal(events.filter((event) => event.type === "connected").length, 1)
  io.emit({ type: "incoming", offerId: 10 })
  assert.deepEqual(io.refused, [8, 9, 10])
  transport.close()
})

await test("a creation deadline rejects creation and closes a late successful native endpoint", async () => {
  const io = new FaultIO(false)
  const events: TransportEvent[] = []
  const created = observed(CoopTransport.create((event) => events.push(event), io))
  const timer = [...io.timers.keys()].at(-1)
  assert.ok(timer)
  io.fire(timer)
  assert.equal((await created).ok, false)
  io.creation.resolve(io.native)
  await flush()
  assert.equal(io.closes, 1)
  assert.equal(events.filter((event) => event.type === "closed").length, 1)
  assert.equal(events.filter((event) => event.type === "ready").length, 0)
})

await test("a callback can enqueue disconnect without reentering a half-committed transition", async () => {
  let depth = 0,
    maximumDepth = 0
  const opened = await open((event) => {
    depth++
    maximumDepth = Math.max(maximumDepth, depth)
    if (event.type === "connected") transport?.disconnectPeer()
    depth--
  })
  const transport = opened.transport
  await connect(transport, opened.io)
  assert.equal(maximumDepth, 1)
  assert.deepEqual(
    opened.events.filter((event) => event.type !== "ready").map((event) => event.type),
    ["connected", "disconnected"]
  )
  assert.equal(latestState(opened.events).connected, false)
  transport.close()
})

await test("event bridge overload closes bounded work even when error callbacks enqueue more input", async () => {
  let overflowing = false
  let depth = 0,
    maximumDepth = 0
  const opened = await open((event) => {
    depth++
    maximumDepth = Math.max(maximumDepth, depth)
    if (event.type === "message" && !overflowing) {
      overflowing = true
      for (let index = 0; index < 100; index++) io?.receive(new Uint8Array(65536))
    }
    if (event.type === "error") io?.receive(new Uint8Array([99]))
    depth--
  })
  const io = opened.io
  await connect(opened.transport, io)
  io.receive()
  await flush()
  assert.equal(maximumDepth, 1)
  assert.equal(io.closes, 1)
  assert.equal(opened.events.filter((event) => event.type === "closed").length, 1)
  assert.equal(latestState(opened.events).closed, true)
})

await test("Bend retries invitation candidates in order and reports the selected seat before connected callbacks", async () => {
  const { io, events, transport } = await open()
  const joined = transport.joinCandidates(["seat-one-capability", "seat-two-capability", "seat-three-capability"])
  assert.deepEqual(
    io.joins.map((attempt) => attempt.ticket),
    ["seat-one-capability"]
  )
  io.joins[0]?.result.reject(Error("first seat occupied"))
  await flush()
  assert.deepEqual(
    io.joins.map((attempt) => attempt.ticket),
    ["seat-one-capability", "seat-two-capability"]
  )
  const second = io.joins[1]
  assert.ok(second)
  io.connect(second.operation)
  second.result.resolve(undefined)
  assert.equal(await joined, 1)
  const connected = events.find((event) => event.type === "connected")
  assert.ok(connected)
  assert.equal(connected.candidate, 1)
  transport.close()
})

await test("closing an acceptance invalidates late accept completion and receive callbacks", async () => {
  const { io, events, transport } = await open()
  io.emit({ type: "incoming", offerId: 22 })
  const accepted = io.accepts.at(-1)
  assert.ok(accepted)
  transport.close()
  io.emit({ type: "connected", operationId: accepted.operation, connectionId: accepted.operation, peerId: "late-peer" })
  io.emit({ type: "message", connectionId: accepted.operation, peerId: "late-peer", bytes: new Uint8Array([1]) })
  accepted.result.reject(Error("accept cancelled"))
  await flush()
  assert.equal(events.filter((event) => event.type === "connected" || event.type === "message").length, 0)
  assert.equal(events.filter((event) => event.type === "closed").length, 1)
  assert.equal(io.closes, 1)
})

await test("native write and QUIC confirmation cannot satisfy application readiness", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  transport.syncReadiness({ $: "GuestSnapshot", epoch: 1, token: 19 })
  const write = transport.send(new Uint8Array([1, 2]), { confirmDelivery: true })
  io.writes[0]?.result.resolve(undefined)
  await write
  const timer = [...io.timers.entries()].find(([, value]) => !value.cancelled)
  assert.ok(timer)
  io.fire(timer[0])
  assert.equal(events.filter((event) => event.type === "timeout" && event.kind === "handshake").length, 1)
  transport.close()
})

await test("application readiness cancels its deadline and drain remains a separate bounded deadline", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  transport.syncReadiness({ $: "GuestRunning", epoch: 1, token: 19 })
  for (const [timer] of io.timers) io.fire(timer, 50000)
  assert.equal(events.filter((event) => event.type === "timeout").length, 0)
  transport.beginDrain()
  const drain = [...io.timers.entries()].find(([, value]) => !value.cancelled)
  assert.ok(drain)
  io.fire(drain[0], drain[1].due - 1)
  assert.equal(events.filter((event) => event.type === "timeout").length, 0)
  const resumed = [...io.timers.entries()].find(([, value]) => !value.cancelled && value.due > io.time)
  assert.ok(resumed)
  io.fire(resumed[0])
  assert.equal(events.filter((event) => event.type === "timeout" && event.kind === "drain").length, 1)
  transport.close()
})

await test("pre-creation callback storage is bounded and a late endpoint is released", async () => {
  const io = new FaultIO(false)
  const events: TransportEvent[] = []
  const creating = observed(CoopTransport.create((event) => events.push(event), io))
  for (let offer = 1; offer <= 100; offer++) io.emit({ type: "incoming", offerId: offer })
  assert.equal((await creating).ok, false)
  io.creation.resolve(io.native)
  await flush()
  assert.equal(io.closes, 1)
  assert.equal(io.accepts.length, 0)
  assert.equal(events.filter((event) => event.type === "closed").length, 1)
})

await test("byte bridge saturation closes before admitting more than four MiB of queued receives", async () => {
  let injected = false
  const opened = await open((event) => {
    if (event.type === "message" && !injected) {
      injected = true
      for (let frame = 0; frame < 6; frame++) io.receive(new Uint8Array(1024 * 1024))
    }
  })
  const io = opened.io
  await connect(opened.transport, io)
  io.receive()
  assert.equal(io.closes, 1)
  assert.equal(opened.events.filter((event) => event.type === "closed").length, 1)
  assert.ok(opened.events.filter((event) => event.type === "message").length <= 5)
})

await test("oversized received frames are rejected before application notification", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  io.receive(new Uint8Array(1024 * 1024 + 1))
  assert.equal(events.filter((event) => event.type === "message").length, 0)
  assert.equal(events.filter((event) => event.type === "closed").length, 1)
  assert.equal(io.closes, 1)
})

function room(started: boolean, players: readonly number[]): BendABI.CoopLobby.State {
  return {
    $: "State",
    started,
    inputEpoch: 0,
    seats: list(players.map((player) => ({ $: "Seat", player, character: 0, ready: true, connected: true })))
  }
}

await test("aborting creation rejects immediately and releases a late successful endpoint", async () => {
  const io = new FaultIO(false),
    controller = new AbortController()
  const events: TransportEvent[] = []
  const creation = observed(CoopTransport.create((event) => events.push(event), io, { signal: controller.signal }))
  assert.equal(io.creates, 1)
  controller.abort()
  assert.equal((await creation).ok, false)
  io.creation.resolve(io.native)
  await flush()
  assert.equal(io.closes, 1)
  assert.equal(events.filter((event) => event.type === "closed").length, 1)
  assert.equal(events.filter((event) => event.type === "ready").length, 0)
  assert.equal([...io.timers.values()].filter((timer) => !timer.cancelled).length, 0)
})

await test("aborting creation ignores a late native failure and already-aborted creation starts no IO", async () => {
  const io = new FaultIO(false),
    controller = new AbortController()
  const events: TransportEvent[] = []
  const creation = observed(CoopTransport.create((event) => events.push(event), io, { signal: controller.signal }))
  controller.abort()
  assert.equal((await creation).ok, false)
  io.creation.reject(Error("late creation failure"))
  await flush()
  assert.equal(io.closes, 0)
  assert.equal(events.filter((event) => event.type === "closed").length, 1)
  const alreadyAborted = new FaultIO(false)
  const result = await observed(CoopTransport.create(() => {}, alreadyAborted, { signal: controller.signal }))
  assert.equal(result.ok, false)
  assert.equal(alreadyAborted.creates, 0)
})

await test("a guest endpoint refuses incoming offers before authenticating any peer", async () => {
  const io = new FaultIO()
  const transport = await CoopTransport.create(() => {}, io, { role: "guest" })
  io.emit({ type: "incoming", offerId: 30 })
  assert.equal(io.accepts.length, 0)
  assert.deepEqual(io.refused, [30])
  transport.close()
})

await test("host room admission refuses absent frozen seats and terminal rooms before acceptance", async () => {
  const { io, events, transport } = await open()
  transport.updateRoom(room(true, [0, 1]), 2, false)
  io.emit({ type: "incoming", offerId: 40 })
  assert.equal(io.accepts.length, 0)
  assert.deepEqual(io.refused, [40])
  transport.updateRoom(room(true, [0, 1, 2]), 2, false)
  io.emit({ type: "incoming", offerId: 41 })
  const accepted = io.accepts.at(-1)
  assert.ok(accepted)
  transport.updateRoom(room(true, [0, 1, 2]), 2, true)
  io.connect(accepted.operation)
  accepted.result.resolve(undefined)
  await flush()
  assert.equal(events.filter((event) => event.type === "connected").length, 0)
  assert.equal(io.current, 0)
  io.emit({ type: "incoming", offerId: 42 })
  assert.deepEqual(io.refused, [40, 42])
  assert.equal(io.accepts.length, 1)
  transport.close()
})

await test("terminal admission keeps an existing peer for final delivery while refusing new offers", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  transport.syncReadiness({ $: "HostRunning", epoch: 1 })
  transport.updateRoom(room(true, [0, 1]), 1, true)
  io.emit({ type: "incoming", offerId: 50 })
  assert.deepEqual(io.refused, [50])
  assert.equal(io.closes, 0)
  const finalFrame = transport.send(new Uint8Array([6, 7, 8]))
  io.writes[0]?.result.resolve(undefined)
  await finalFrame
  io.receive()
  assert.equal(latestState(events).connected, true)
  transport.close()
})

await test("failed candidate lists permit an explicit new attempt without reviving old deadlines", async () => {
  const { io, events, transport } = await open()
  const failed = observed(transport.joinCandidates(["unavailable-one", "unavailable-two"]))
  const oldTimers = [...io.timers.keys()]
  io.joins[0]?.result.reject(Error("unavailable"))
  await flush()
  io.joins[1]?.result.reject(Error("unavailable"))
  assert.equal((await failed).ok, false)
  const connection = await connect(transport, io)
  transport.syncReadiness({ $: "GuestRunning", epoch: 1, token: 1 })
  for (const timer of oldTimers) io.fire(timer, 100000)
  await flush()
  io.receive()
  assert.equal(latestState(events).connected, true)
  assert.equal(io.current, connection)
  assert.equal(events.filter((event) => event.type === "timeout").length, 0)
  transport.disconnectPeer()
  const invitation = transport.invitation()
  transport.disconnectPeer()
  transport.disconnectPeer()
  assert.equal(transport.invitation(), invitation)
  assert.equal(events.filter((event) => event.type === "disconnected").length, 1)
  transport.close()
})

await test("a room drain deadline survives departure of its endpoint's peer", async () => {
  const { io, events, transport } = await open()
  await connect(transport, io)
  transport.beginDrain()
  const deadline = io.sequence
  transport.disconnectPeer()
  assert.equal(io.timers.get(deadline)?.cancelled, false, "peer departure must retain the room drain timer")
  io.fire(deadline)
  assert.equal(events.filter((event) => event.type === "timeout" && event.kind === "drain").length, 1)
  assert.equal(latestState(events).connected, false)
  transport.close()
})

await test("guest creation and candidate attempts share the original forty-five-second deadline", async () => {
  const io = new FaultIO(false)
  const creating = CoopTransport.create(() => {}, io, { role: "guest" })
  const attemptDeadline = io.sequence
  io.time = 40000
  io.creation.resolve(io.native)
  const transport = await creating
  assert.equal(
    io.timers.get(attemptDeadline)?.cancelled,
    false,
    "guest creation must retain its original attempt deadline"
  )
  const joining = observed(transport.joinCandidates(["slow-one", "slow-two"]))
  io.joins[0]?.result.reject(Error("unavailable"))
  await flush()
  assert.equal(io.joins.length, 2)
  io.fire(attemptDeadline, 45000)
  assert.equal((await joining).ok, false)
  assert.ok(io.disconnected.includes(0), "the original deadline cancels the native connection attempt")
  transport.close()
})
