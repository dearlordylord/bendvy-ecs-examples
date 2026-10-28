import { CoopTransport, type TransportEvent } from "./coop-transport.mts"
import type { CoopSetup } from "./coop-ui.mts"
import type { WorkerRequest, WorkerReply } from "./coop-boundary.mts"
import { decodeControlFrame } from "./coop-control-frame.mts"
import { encodeSnapshot } from "./coop-snapshot-codec.mts"
import { encodeInvitation, encodeLobby, type PartyLobby } from "./coop-party-wire.mts"
import { defined, errorMessage, list } from "./host-values.mts"
import Connection from "./dist/coop-connection.mjs"
import ClientDelivery from "./dist/coop-client-delivery.mjs"
import Finish from "./dist/coop-finish.mjs"
import SnapshotFlow from "./dist/coop-snapshot-flow.mjs"

interface Seat {
  player: number
  transport: CoopTransport | null
  epoch: number
  connected: boolean
  gate: BendABI.CoopConnection.State
  flow: BendABI.CoopSnapshotFlow.State
  latest: Extract<WorkerReply, { type: "remote-frame" }> | null
  terminal: { token: number; observation: number; applied: boolean } | null
}
interface HostCallbacks {
  finished: () => void
  frame: (message: Extract<WorkerReply, { type: "frame" }>) => void
  lobby: (lobby: PartyLobby) => void
  invitation: (ticket: string) => void
  status: (message: string, error?: boolean) => void
  error: (error: unknown) => void
}
export class CoopHost {
  #worker: Worker
  #seats: Seat[] = []
  #closed = false
  #finish = Finish.fresh()
  #terminalObservation: number | null = null
  #pending = new Map<number, number>()
  #delivery = 0
  #callbacks: HostCallbacks
  #lobby: PartyLobby | null = null
  #decoder = new TextDecoder("utf-8", { fatal: true })
  private constructor(callbacks: HostCallbacks) {
    this.#callbacks = callbacks
    this.#worker = new Worker("./coop-worker.mjs", { type: "module" })
    this.#worker.onmessage = (event: MessageEvent<WorkerReply>) => {
      if (this.#closed) return
      try {
        this.#message(event.data)
      } catch (error) {
        callbacks.error(error)
        this.fail("The host could not process the game. Create a new room.")
      }
    }
    this.#worker.onerror = (event) => {
      callbacks.error(event.error || Error(event.message))
      this.fail("The host simulation failed. Create a new room.")
    }
  }
  static async create(
    setup: CoopSetup,
    session: number,
    seed: number,
    runId: string,
    callbacks: HostCallbacks,
    signal?: AbortSignal
  ) {
    const host = new CoopHost(callbacks)
    const abort = () => host.close()
    signal?.addEventListener("abort", abort, { once: true })
    try {
      for (const player of [1, 2, 3]) {
        const seat: Seat = {
          player,
          transport: null,
          epoch: 0,
          connected: false,
          gate: Connection.fresh({ $: "Host" }),
          flow: SnapshotFlow.fresh(0),
          latest: null,
          terminal: null
        }
        host.#seats.push(seat)
        const transport = await CoopTransport.create(
          (event) => {
            void host.#event(seat, event).catch((error: unknown) => {
              if (event.connectionEpoch === seat.epoch) host.#fail(seat, error)
            })
          },
          undefined,
          signal ? { signal } : {}
        )
        if (host.#closed) {
          transport.close()
          throw Error("Room creation cancelled.")
        }
        seat.transport = transport
      }
      host.#post({ type: "init", setup, session, seed, runId })
      return host
    } catch (error) {
      host.close()
      throw error
    } finally {
      signal?.removeEventListener("abort", abort)
    }
  }
  #post(message: WorkerRequest) {
    this.#worker.postMessage(message)
  }
  command(text: string) {
    return this.#command(text, 0, 0)
  }
  #command(text: string, player: number, connectionEpoch: number) {
    if (
      this.#closed ||
      this.#terminalObservation !== null ||
      [...this.#pending.values()].filter((owner) => owner === player).length >= 64
    )
      return false
    const deliveryId = ++this.#delivery
    this.#pending.set(deliveryId, player)
    this.#post({ type: "command", player, text, deliveryId, connectionEpoch })
    return true
  }
  configure(setup: CoopSetup) {
    if (!this.#closed) this.#post({ type: "configure", setup })
  }
  start() {
    this.#post({ type: "start" })
  }
  fail(message: string) {
    if (this.#closed) return
    this.close()
    this.#callbacks.status(message, true)
  }
  #signal(seat: Seat, signal: BendABI.CoopConnection.Signal) {
    this.#post({ type: "handshake", player: seat.player, connectionEpoch: seat.epoch, signal })
  }
  #fail(seat: Seat, error: unknown) {
    if (this.#closed || this.#terminalObservation !== null) return
    this.#callbacks.status(`Player ${seat.player + 1}: ${errorMessage(error)}`, true)
    this.#signal(seat, { $: "Reject", reason: { $: "TransportFailed" } })
  }
  async #event(seat: Seat, event: TransportEvent) {
    if (this.#closed) return
    if (event.type === "connected") {
      seat.epoch = event.connectionEpoch
      seat.connected = true
      seat.latest = null
      seat.gate = Connection.state(Connection.reconnect(seat.gate, seat.epoch))
      seat.flow = SnapshotFlow.fresh(Connection.epoch(seat.gate))
      seat.transport?.syncReadiness(seat.gate)
      this.#post({ type: "connected", player: seat.player, connectionEpoch: seat.epoch })
    } else if (event.type === "message") {
      if (!seat.connected || event.connectionEpoch !== seat.epoch) return
      if (event.bytes.length > ClientDelivery.max_frame_bytes()) {
        this.#signal(seat, { $: "Reject", reason: { $: "ProtocolError" } })
        return
      }
      const control = decodeControlFrame(event.bytes, (text) => Connection.decode(text))
      if (control.$ === "Some") {
        if (this.#terminalObservation !== null) return
        this.#signal(seat, control.value)
        return
      }
      const text = this.#decoder.decode(event.bytes)
      const decoded = ClientDelivery.decode(text)
      if (decoded.$ !== "Some") {
        this.#signal(seat, { $: "Reject", reason: { $: "ProtocolError" } })
        return
      }
      const packet = decoded.value
      if (packet.receipt.$ === "Some") {
        const receipt = packet.receipt.value
        if (
          seat.terminal &&
          !seat.terminal.applied &&
          receipt.token === seat.terminal.token &&
          receipt.observation === seat.terminal.observation &&
          SnapshotFlow.matches(seat.flow, receipt.token, receipt.observation)
        ) {
          seat.terminal.applied = true
          this.#finish = Finish.applied(this.#finish)
        }
        seat.flow = SnapshotFlow.ack(seat.flow, packet.receipt.value.token, packet.receipt.value.observation)
        this.#flush(seat)
        this.#finishIfReady()
      }
      if (this.#terminalObservation !== null) return
      if (packet.commands.$ !== "Nil" && !this.#command(text, seat.player, seat.epoch))
        this.#signal(seat, { $: "Reject", reason: { $: "ProtocolError" } })
    } else if (event.type === "timeout") {
      if (event.kind === "handshake") this.#signal(seat, { $: "Timeout" })
      else {
        this.#finish = Finish.expire(this.#finish)
        this.#finishIfReady()
      }
    } else if (event.type === "disconnected") {
      seat.epoch = event.connectionEpoch
      seat.connected = false
      seat.latest = null
      if (this.#terminalObservation !== null) return
      this.#post({ type: "disconnect", player: seat.player, connectionEpoch: seat.epoch })
    } else if (event.type === "error") this.#fail(seat, Error(event.message))
  }
  #message(message: WorkerReply) {
    if (message.type === "ready") {
      this.#callbacks.invitation(encodeInvitation(this.#seats.map((seat) => defined(seat.transport).invitation())))
    } else if (message.type === "command-consumed") this.#pending.delete(message.deliveryId)
    else if (message.type === "frame") {
      if (Finish.terminal(message.frame.phase)) {
        this.#terminalObservation = message.observationSeq
        this.#updateAdmission()
      }
      this.#callbacks.frame(message)
    } else if (message.type === "finished") {
      this.#worker.terminate()
      this.#pending.clear()
      this.#callbacks.finished()
      this.#finish = Finish.begin(
        this.#finish,
        this.#seats.filter((seat) => seat.terminal && !seat.terminal.applied).length
      )
      this.#seats[0]?.transport?.beginDrain()
      this.#finishIfReady()
    } else if (message.type === "lobby") {
      this.#lobby = message
      this.#updateAdmission()
      this.#callbacks.lobby(message)
      for (const seat of this.#seats)
        if (seat.connected) {
          const epoch = seat.epoch
          void defined(seat.transport)
            .send(encodeLobby(message))
            .catch((error: unknown) => {
              if (seat.epoch === epoch) this.#fail(seat, error)
            })
        }
    } else if (message.type === "remote-frame") {
      const seat = this.#seats.find((row) => row.player === message.player)
      if (!seat || !seat.connected || seat.epoch !== message.connectionEpoch) return
      if (!SnapshotFlow.offer_allowed(seat.flow, message.observationSeq)) return
      if (message.observationSeq === this.#terminalObservation)
        seat.terminal = { token: message.token, observation: message.observationSeq, applied: false }
      seat.latest = message
      seat.flow = SnapshotFlow.offer(seat.flow, message.observationSeq)
      this.#flush(seat)
    } else if (message.type === "handshake-action") {
      const seat = this.#seats.find((row) => row.player === message.player)
      if (!seat || !seat.connected || seat.epoch !== message.connectionEpoch) return
      seat.gate = message.state
      const action = message.action
      seat.transport?.syncReadiness(seat.gate)
      if (["SendHello", "StartAndConfirm", "CloseConnection"].includes(action.$)) {
        const epoch = seat.epoch
        void defined(seat.transport)
          .send(Connection.encode_action(action), { confirmDelivery: action.$ === "CloseConnection" })
          .then(() => {
            if (action.$ === "CloseConnection" && seat.epoch === epoch) seat.transport?.disconnectPeer()
          })
          .catch((error: unknown) => {
            if (seat.epoch !== epoch) return
            if (action.$ === "CloseConnection") seat.transport?.disconnectPeer()
            else this.#fail(seat, error)
          })
      }
    } else if (message.type === "error") this.#callbacks.error(Error(message.message))
    else if (message.type === "rejected") this.#callbacks.status(message.message, true)
    else if (message.type === "choice-unavailable" && message.player === 0)
      this.#callbacks.status("Waiting for all teammates to reconnect.")
  }
  #flush(seat: Seat) {
    if (!seat.connected || this.#closed) return
    const prepared = SnapshotFlow.prepare(seat.flow)
    seat.flow = prepared.state
    if (prepared.observation.$ !== "Some") return
    const message = seat.latest
    seat.latest = null
    if (!message || message.observationSeq !== prepared.observation.value) throw Error("Snapshot journal disagreed.")
    const epoch = seat.epoch
    void encodeSnapshot(message.bytes)
      .then((bytes) => {
        if (!this.#closed && seat.connected && epoch === seat.epoch) return defined(seat.transport).send(bytes)
      })
      .then(() => {
        if (this.#closed || epoch !== seat.epoch) return
        seat.flow = SnapshotFlow.complete(seat.flow, message.token, message.observationSeq)
        this.#flush(seat)
      })
      .catch((error: unknown) => {
        if (epoch === seat.epoch) this.#fail(seat, error)
      })
  }
  #updateAdmission() {
    const lobby = this.#lobby
    if (!lobby) return
    const state: BendABI.CoopLobby.State = {
      $: "State",
      started: lobby.started,
      inputEpoch: lobby.inputEpoch,
      seats: list(
        lobby.players.map((row) => ({
          $: "Seat",
          player: row.player,
          character: row.character,
          ready: row.ready,
          connected: row.connected
        }))
      )
    }
    for (const seat of this.#seats) seat.transport?.updateRoom(state, seat.player, this.#terminalObservation !== null)
  }
  #finishIfReady() {
    if (Finish.closed(this.#finish)) this.close()
  }
  close() {
    this.#closed = true
    this.#worker.terminate()
    for (const seat of this.#seats) {
      seat.transport?.close()
    }
    this.#pending.clear()
  }
}
