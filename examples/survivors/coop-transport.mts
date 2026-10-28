import Policy from "./dist/coop-transport-policy.mjs"
import { defined, list, rows } from "./host-values.mts"

export type NativeEvent =
  | { type: "ready" | "connecting"; peerId: string }
  | { type: "incoming"; offerId: number }
  | { type: "connected"; operationId: number; connectionId: number; peerId: string }
  | { type: "disconnected"; connectionId: number; peerId: string }
  | { type: "message"; connectionId: number; peerId: string; bytes: Uint8Array }
  | { type: "closed" | "invalid" }
export interface NativeTransport {
  endpointId(): string
  invitation(): string
  join(ticket: string, operation: number): Promise<unknown>
  acceptOffer(offer: number, operation: number): Promise<unknown>
  refuseOffer(offer: number): void
  send(bytes: Uint8Array, confirmDelivery: boolean, connection: number): Promise<unknown>
  disconnectPeer(connection?: number): void
  close(): void
}
type NativeCallback = (event: NativeEvent) => void
interface NativeFactory {
  create: (callback: NativeCallback) => Promise<NativeTransport>
}
export interface TransportIO extends NativeFactory {
  now(): number
  schedule(callback: () => void, milliseconds: number): unknown
  cancel(timer: unknown): void
}
interface TransportState {
  endpoint: string
  peer: string
  connected: boolean
  closed: boolean
  connectionEpoch: number
  pendingSends: number
  pendingBytes: number
}
type PublicEvent =
  | { type: "ready" | "disconnected"; peerId: string }
  | { type: "connected"; peerId: string; candidate: number }
  | { type: "message"; peerId: string; bytes: Uint8Array }
  | { type: "timeout"; kind: "handshake" | "drain" }
  | { type: "error"; message: string }
  | { type: "closed" }
export type TransportEvent = PublicEvent & { connectionEpoch: number; state: TransportState }
type TransportCallback = (event: TransportEvent) => void
let initialized: Promise<NativeFactory> | undefined
function nativeId(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 4294967295)
    throw TypeError("Invalid native operation identity.")
  return value
}
function parseNativeEvent(value: unknown): NativeEvent {
  if (typeof value !== "object" || value === null || !("type" in value))
    throw TypeError("Invalid native transport event.")
  switch (value.type) {
    case "ready":
    case "connecting":
      if ("peerId" in value && typeof value.peerId === "string") return { type: value.type, peerId: value.peerId }
      break
    case "incoming":
      if ("offerId" in value) return { type: "incoming", offerId: nativeId(value.offerId) }
      break
    case "connected":
      if ("operationId" in value && "connectionId" in value && "peerId" in value && typeof value.peerId === "string")
        return {
          type: "connected",
          operationId: nativeId(value.operationId),
          connectionId: nativeId(value.connectionId),
          peerId: value.peerId
        }
      break
    case "disconnected":
      if ("connectionId" in value && "peerId" in value && typeof value.peerId === "string")
        return { type: "disconnected", connectionId: nativeId(value.connectionId), peerId: value.peerId }
      break
    case "message":
      if (
        "connectionId" in value &&
        "peerId" in value &&
        typeof value.peerId === "string" &&
        "bytes" in value &&
        value.bytes instanceof Uint8Array
      )
        return { type: "message", connectionId: nativeId(value.connectionId), peerId: value.peerId, bytes: value.bytes }
      break
    case "closed":
      return { type: "closed" }
  }
  throw TypeError("Invalid native transport event.")
}
function nativeMethod(owner: object, name: string): (...args: unknown[]) => unknown {
  const method: unknown = Reflect.get(owner, name)
  if (typeof method !== "function") throw TypeError(`Missing native transport method: ${name}.`)
  return (...args) => {
    const result: unknown = Reflect.apply(method, owner, args)
    return result
  }
}
function parseNativeTransport(value: unknown): NativeTransport {
  if (typeof value !== "object" || value === null) throw TypeError("Invalid native transport.")
  const endpointId = nativeMethod(value, "endpointId"),
    invitation = nativeMethod(value, "invitation"),
    join = nativeMethod(value, "join"),
    acceptOffer = nativeMethod(value, "acceptOffer"),
    refuseOffer = nativeMethod(value, "refuseOffer"),
    send = nativeMethod(value, "send"),
    disconnectPeer = nativeMethod(value, "disconnectPeer"),
    close = nativeMethod(value, "close")
  function text(result: unknown): string {
    if (typeof result !== "string") throw TypeError("Invalid native transport text.")
    return result
  }
  return {
    endpointId: () => text(endpointId()),
    invitation: () => text(invitation()),
    join: async (ticket, operation) => join(ticket, operation),
    acceptOffer: async (offer, operation) => acceptOffer(offer, operation),
    refuseOffer: (offer) => {
      refuseOffer(offer)
    },
    send: async (bytes, confirmDelivery, connection) => send(bytes, confirmDelivery, connection),
    disconnectPeer: (connection) => {
      disconnectPeer(connection)
    },
    close: () => {
      close()
    }
  }
}
async function defaultFactory(callback: NativeCallback) {
  let loading = initialized
  if (!loading) {
    const moduleUrl = new URL("./iroh/iroh_transport.js", import.meta.url).href
    loading = import(moduleUrl).then(async (value: unknown): Promise<NativeFactory> => {
      if (typeof value !== "object" || value === null || !("default" in value) || !("Transport" in value))
        throw TypeError("Invalid native transport module.")
      await nativeMethod(value, "default")()
      const transport = value.Transport
      if (typeof transport !== "function" && (typeof transport !== "object" || transport === null))
        throw TypeError("Invalid native transport factory.")
      const create = nativeMethod(transport, "create")
      return {
        create: async (event) =>
          parseNativeTransport(
            await create((raw: unknown) => {
              try {
                event(parseNativeEvent(raw))
              } catch {
                event({ type: "invalid" })
              }
            })
          )
      }
    })
    initialized = loading
    void loading.catch(() => {
      if (initialized === loading) initialized = undefined
    })
  }
  return (await loading).create(callback)
}

const browserIO: TransportIO = {
  create: defaultFactory,
  now: () => Math.floor(performance.now()),
  schedule: (callback, milliseconds) => {
    const handle = setTimeout(callback, milliseconds)
    return { cancel: () => clearTimeout(handle) }
  },
  cancel: (timer) => {
    if (typeof timer !== "object" || timer === null) throw TypeError("Invalid timer handle.")
    nativeMethod(timer, "cancel")()
  }
}
type Request =
  | { kind: "create"; resolve: () => void; reject: (error: Error) => void }
  | { kind: "join"; tickets: Map<number, string>; resolve: (selected: number) => void; reject: (error: Error) => void }
  | { kind: "send"; bytes: Uint8Array; resolve: (result: SendResult) => void; reject: (error: Error) => void }
export interface TransportOptions {
  role?: "host" | "guest"
  signal?: AbortSignal
}
export interface SendResult {
  peerId: string
  connectionEpoch: number
  byteLength: number
}
export class CoopTransport {
  #state = Policy.fresh()
  #native: NativeTransport | null = null
  #callback: TransportCallback | undefined
  #io: TransportIO
  #requests = new Map<number, Request>()
  #messages = new Map<number, Uint8Array>()
  #timers = new Map<number, unknown>()
  #events: BendABI.CoopTransportPolicy.Signal[] = []
  #beforeCreated: NativeEvent[] = []
  #beforeCreatedBytes = 0
  #eventBytes = 0
  #draining = false
  #nextRequest = 0
  #endpoint = ""
  #invitation: string | undefined
  #terminalError: string | undefined
  private constructor(callback: TransportCallback, io: TransportIO) {
    this.#callback = callback
    this.#io = io
  }
  static async create(callback: TransportCallback, io: TransportIO = browserIO, options: TransportOptions = {}) {
    const channel = new CoopTransport(callback, io)
    const request = channel.#reference()
    const abort = () => channel.close()
    options.signal?.addEventListener("abort", abort, { once: true })
    try {
      await new Promise<void>((resolve, reject) => {
        channel.#requests.set(request, { kind: "create", resolve, reject })
        if (options.signal?.aborted) channel.close()
        else
          channel.#dispatch({
            $: "Begin",
            request,
            role: options.role === "guest" ? { $: "GuestEndpoint" } : { $: "HostEndpoint" }
          })
      })
      return channel
    } finally {
      options.signal?.removeEventListener("abort", abort)
    }
  }
  #reference() {
    if (this.#nextRequest === 4294967295) {
      this.close()
      throw Error("Transport request identities exhausted.")
    }
    return ++this.#nextRequest
  }
  invitation() {
    return defined(this.#invitation)
  }
  async join(ticket: string) {
    await this.joinCandidates([ticket])
  }
  joinCandidates(tickets: readonly string[]): Promise<number> {
    if (Policy.closed(this.#state) || this.#terminalError) return Promise.reject(Error("Transport is closed."))
    if (tickets.length > 3) return Promise.reject(Error("Too many invitation candidates."))
    const request = this.#reference()
    return new Promise((resolve, reject) => {
      const candidates = new Map(tickets.map((ticket, index) => [index + 1, ticket]))
      this.#requests.set(request, { kind: "join", tickets: candidates, resolve, reject })
      this.#dispatch({ $: "Join", request, candidates: list([...candidates.keys()]) })
    })
  }
  send(payload: unknown, { confirmDelivery = false }: { confirmDelivery?: boolean } = {}): Promise<SendResult> {
    if (Policy.closed(this.#state) || this.#terminalError) return Promise.reject(Error("Transport is closed."))
    if (typeof payload === "string") payload = new TextEncoder().encode(payload)
    if (!(payload instanceof Uint8Array)) return Promise.reject(TypeError("Expected bytes or UTF-8 text."))
    const request = this.#reference()
    return new Promise((resolve, reject) => {
      const bytes = payload.byteLength <= Policy.max_frame_bytes() ? payload.slice() : new Uint8Array()
      this.#requests.set(request, { kind: "send", bytes, resolve, reject })
      this.#dispatch({ $: "Send", request, bytes: payload.byteLength, confirm: confirmDelivery }, bytes.byteLength)
    })
  }
  updateRoom(lobby: BendABI.CoopLobby.State, seat: number, terminal: boolean) {
    this.#dispatch({ $: "Room", lobby, seat, terminal })
  }
  syncReadiness(state: BendABI.CoopConnection.State) {
    this.#dispatch({ $: "Readiness", state })
  }
  beginDrain(guest = false) {
    this.#dispatch({ $: "Arm", kind: guest ? { $: "GuestDrain" } : { $: "Drain" } })
  }
  disconnectPeer() {
    this.#dispatch({ $: "DisconnectRequest" })
  }
  close() {
    this.#dispatch({ $: "CloseRequest" })
  }
  #snapshot(): TransportState {
    return {
      endpoint: this.#endpoint,
      peer: Policy.peer(this.#state),
      connected: Policy.connected(this.#state),
      closed: Policy.closed(this.#state),
      connectionEpoch: Policy.epoch(this.#state),
      pendingSends: Policy.pending_count(this.#state),
      pendingBytes: Policy.pending_bytes(this.#state)
    }
  }
  #emit(event: PublicEvent) {
    this.#callback?.({ ...event, connectionEpoch: Policy.epoch(this.#state), state: this.#snapshot() })
  }
  #nativeEvent(event: NativeEvent) {
    if (this.#terminalError) return
    if (!this.#native) {
      if (Policy.closed(this.#state)) return
      const bytes = event.type === "message" ? event.bytes.byteLength : 0
      if (
        this.#beforeCreated.length >= Policy.max_bridge_events() ||
        this.#beforeCreatedBytes + bytes > Policy.max_bridge_bytes()
      ) {
        this.close()
        return
      }
      this.#beforeCreated.push(event.type === "message" ? { ...event, bytes: event.bytes.slice() } : event)
      this.#beforeCreatedBytes += bytes
      return
    }
    switch (event.type) {
      case "ready":
      case "connecting":
        return
      case "incoming":
        this.#dispatch({ $: "Incoming", offer: event.offerId })
        return
      case "connected":
        this.#dispatch({
          $: "ConnectedEvent",
          operation: event.operationId,
          connection: event.connectionId,
          peer: event.peerId
        })
        return
      case "disconnected":
        this.#dispatch({ $: "Departed", connection: event.connectionId, peer: event.peerId })
        return
      case "message": {
        if (event.bytes.byteLength > Policy.max_frame_bytes()) {
          this.#terminalError = "Invalid transport frame."
          this.close()
          return
        }
        const request = this.#reference()
        this.#messages.set(request, event.bytes.slice())
        this.#dispatch(
          { $: "Received", connection: event.connectionId, peer: event.peerId, request },
          event.bytes.byteLength
        )
        return
      }
      case "invalid":
        this.#terminalError = "Invalid native transport event."
        this.close()
        return
      case "closed":
        this.#dispatch({ $: "CloseRequest" })
        return
    }
  }
  #dispatch(event: BendABI.CoopTransportPolicy.Signal, bytes = 0) {
    if (this.#events.length >= Policy.max_bridge_events() || this.#eventBytes + bytes > Policy.max_bridge_bytes()) {
      this.#events = [{ $: "CloseRequest" }]
      this.#messages.clear()
      this.#eventBytes = 0
      this.#terminalError = "Transport event queue is full."
    } else {
      this.#events.push(event)
      this.#eventBytes += bytes
    }
    if (this.#draining) return
    this.#draining = true
    try {
      while (this.#events.length) {
        const next = defined(this.#events.shift())
        if (next.$ === "Received") this.#eventBytes -= this.#messages.get(next.request)?.byteLength ?? 0
        if (next.$ === "Send") {
          const request = this.#requests.get(next.request)
          if (request?.kind === "send") this.#eventBytes -= request.bytes.byteLength
        }
        const out = Policy.step(this.#state, next, Math.floor(this.#io.now()))
        this.#state = out.state
        for (const effect of rows(out.effects)) this.#execute(effect)
        if (next.$ === "Received") this.#messages.delete(next.request)
      }
    } finally {
      this.#draining = false
    }
  }
  #execute(effect: BendABI.CoopTransportPolicy.Effect) {
    switch (effect.$) {
      case "Create":
        void this.#io
          .create((event) => this.#nativeEvent(event))
          .then(
            (native) => {
              this.#native = native
              try {
                this.#endpoint = native.endpointId()
                this.#invitation = native.invitation()
              } catch {
                native.close()
                this.#native = null
                this.#dispatch({ $: "Created", operation: effect.operation, success: false })
                return
              }
              this.#dispatch({ $: "Created", operation: effect.operation, success: true })
              const events = this.#beforeCreated
              this.#beforeCreated = []
              this.#beforeCreatedBytes = 0
              for (const event of events) this.#nativeEvent(event)
            },
            () => this.#dispatch({ $: "Created", operation: effect.operation, success: false })
          )
        return
      case "Connect": {
        const request = this.#requests.get(effect.request)
        if (request?.kind !== "join") throw Error("Missing invitation reference.")
        void defined(this.#native)
          .join(defined(request.tickets.get(effect.candidate)), effect.operation)
          .catch(() => this.#dispatch({ $: "AttemptFailed", operation: effect.operation }))
        return
      }
      case "Accept":
        void defined(this.#native)
          .acceptOffer(effect.offer, effect.operation)
          .catch(() => this.#dispatch({ $: "AttemptFailed", operation: effect.operation }))
        return
      case "Refuse":
        this.#native?.refuseOffer(effect.offer)
        return
      case "Write": {
        const request = this.#requests.get(effect.request)
        if (request?.kind !== "send") throw Error("Missing transport byte reference.")
        void defined(this.#native)
          .send(request.bytes, effect.confirm, effect.connection)
          .then(
            () =>
              this.#dispatch({
                $: "Written",
                operation: effect.operation,
                connection: effect.connection,
                success: true
              }),
            () =>
              this.#dispatch({
                $: "Written",
                operation: effect.operation,
                connection: effect.connection,
                success: false
              })
          )
        return
      }
      case "Disconnect":
        this.#native?.disconnectPeer(effect.connection)
        return
      case "CloseEndpoint":
        this.#native?.close()
        this.#native = null
        this.#invitation = undefined
        return
      case "Settle": {
        const request = this.#requests.get(effect.request)
        this.#requests.delete(effect.request)
        if (!request) return
        if (!effect.success) request.reject(Error(`Transport operation failed (${effect.reason.$}).`))
        else if (request.kind === "create") {
          request.resolve()
          this.#emit({ type: "ready", peerId: this.#endpoint })
        } else if (request.kind === "send")
          request.resolve({
            peerId: Policy.peer(this.#state),
            connectionEpoch: Policy.epoch(this.#state),
            byteLength: request.bytes.byteLength
          })
        else throw Error("Join completion requires a selected invitation.")
        return
      }
      case "SettleJoin": {
        const request = this.#requests.get(effect.request)
        this.#requests.delete(effect.request)
        if (request?.kind !== "join") return
        if (effect.success) request.resolve(effect.selected - 1)
        else request.reject(Error(`Transport connection failed (${effect.reason.$}).`))
        return
      }
      case "NotifyConnected":
        this.#emit({ type: "connected", peerId: effect.peer, candidate: effect.candidate - 1 })
        return
      case "NotifyDisconnected":
        this.#emit({ type: "disconnected", peerId: effect.peer })
        return
      case "NotifyMessage":
        this.#emit({ type: "message", peerId: effect.peer, bytes: defined(this.#messages.get(effect.request)) })
        return
      case "NotifyClosed": {
        const message = this.#terminalError
        this.#terminalError = undefined
        if (message) this.#emit({ type: "error", message })
        this.#emit({ type: "closed" })
        this.#callback = undefined
        for (const request of this.#requests.values()) request.reject(Error("Transport is closed."))
        this.#requests.clear()
        this.#messages.clear()
        this.#beforeCreated = []
        this.#beforeCreatedBytes = 0
        return
      }
      case "NotifyTimeout":
        this.#emit({ type: "timeout", kind: effect.kind.$ === "Handshake" ? "handshake" : "drain" })
        return
      case "Schedule":
        this.#timers.set(
          effect.id,
          this.#io.schedule(() => {
            this.#timers.delete(effect.id)
            this.#dispatch({ $: "Deadline", id: effect.id })
          }, effect.after)
        )
        return
      case "CancelTimer": {
        const timer = this.#timers.get(effect.id)
        if (timer !== undefined) this.#io.cancel(timer)
        this.#timers.delete(effect.id)
        return
      }
    }
  }
}
