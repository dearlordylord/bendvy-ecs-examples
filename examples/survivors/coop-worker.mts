import Finish from "./dist/coop-finish.mjs"
import { coreFrame } from "./observations.mts"
import type { WorkerRequest, WorkerReply } from "./coop-boundary.mts"
import { errorMessage } from "./host-values.mts"
import Game from "./dist/coop-core.mjs"
import Network from "./dist/coop-network.mjs"
import { encodeSnapshotValues } from "./snapshot-envelope.mts"
import Session from "./dist/coop-session.mjs"
import InputQueue from "./dist/coop-input-queue.mjs"
import Connection from "./dist/coop-connection.mjs"
import ClientDelivery from "./dist/coop-client-delivery.mjs"
import HitJournal from "./dist/coop-hit-journal.mjs"
import Lobby from "./dist/coop-lobby.mjs"

type Rejection = { reason: number; seq: number; targetWorldTick: number; worldTick: number }
type Peer = {
  player: number
  gate: BendABI.CoopConnection.State
  session: BendABI.CoopSession.State
  queue: BendABI.CoopInputQueue.State
  eligible: boolean
  rejection: Rejection | null
  epoch: number
  journal: BendABI.CoopHitJournal.State
  character: number
  attached: boolean
  setup: Extract<BendABI.CoopSession.Action, { $: "Setup" }> | null
}
let core: BendABI.CoopCore.CoreState
let hostSession: BendABI.CoopSession.State
let lobby: BendABI.CoopLobby.State
const peers = new Map<number, Peer>()
let timer: ReturnType<typeof setInterval> | undefined
let last = 0,
  accumulator = 0,
  lastSnapshot = 0,
  observationSeq = 0
let currentRound = 0,
  currentPhase = 0,
  currentWorldTick = 0
let lastPhase: number | undefined
let runId = "",
  sessionId = 0
let initial: Extract<WorkerRequest, { type: "init" }>
let contactJournal = HitJournal.fresh(0)
const STEP = 1000 / 60
function emit(message: WorkerReply, transfer: Transferable[] = []) {
  postMessage(message, { transfer })
}
function emitLobby() {
  const players = []
  for (let rows = Lobby.seats(lobby); rows.$ === "Con"; rows = rows.tail) players.push(rows.head)
  emit({
    type: "lobby",
    room: { stage: initial.setup.stage, mode: initial.setup.mode },
    players,
    started: Lobby.started(lobby),
    canStart: Lobby.can_start(lobby),
    running: Lobby.running(lobby),
    inputEpoch: Lobby.input_epoch(lobby)
  })
}
function updateSeat(peer: Peer) {
  const wasRunning = Lobby.running(lobby)
  if (peer.attached)
    lobby = Lobby.update(lobby, {
      $: "Seat",
      player: peer.player,
      character: peer.character,
      ready: Connection.running(peer.gate),
      connected: peer.gate.$ !== "Suspended" && Connection.reason(peer.gate).$ === "None"
    })
  if (wasRunning !== Lobby.running(lobby))
    for (const member of peers.values()) member.queue = InputQueue.fresh(Lobby.input_epoch(lobby), currentWorldTick)
  emitLobby()
}
function applyConnection(peer: Peer, output: BendABI.CoopConnection.Out) {
  peer.gate = output.state
  const action = output.action
  if (action.$ === "StartAndConfirm") {
    last = performance.now()
    lastSnapshot = last
    accumulator = 0
  }
  if (!["Nothing", "PrepareWorld", "PublishInitial"].includes(action.$))
    emit({ type: "handshake-action", player: peer.player, state: peer.gate, action, connectionEpoch: peer.epoch })
  updateSeat(peer)
  return action
}
function handshake(peer: Peer, signal: BendABI.CoopConnection.Signal) {
  return applyConnection(peer, Connection.step(peer.gate, Connection.epoch(peer.gate), signal))
}
function reject(peer: Peer, reason: BendABI.CoopConnection.Reason["$"], error?: unknown) {
  if (error)
    emit({
      type: "error",
      player: peer.player,
      message: errorMessage(error),
      connectionEpoch: peer.epoch,
      ...(error instanceof Error && error.stack ? { stack: error.stack } : {}),
      context: {
        worldTick: currentWorldTick,
        queueWorldTick: peer.queue.worldTick,
        round: currentRound,
        phase: currentPhase
      }
    })
  handshake(peer, { $: "Reject", reason: { $: reason } })
  accumulator = 0
  peer.eligible = false
}
function packet(result: BendABI.CoopCore.CorePacket) {
  if ("state" in result) core = result.state
  if (result.$ === "CoreFailed") throw Error(result.message)
  if (result.$ === "CoreRejected") {
    emit({ type: "rejected", player: 0, message: result.message, connectionEpoch: 0 })
    return null
  }
  const frame = coreFrame(result.observation)
  if (frame && Number.isInteger(frame.tick)) currentWorldTick = frame.tick
  return frame
}
function publishPeer(peer: Peer, observation: number, initial = false) {
  if (!peer.attached) return
  const guestPacket = Game.core_network_observe(core, peer.player)
  core = guestPacket.state
  peer.eligible = Game.network_prediction_allowed(guestPacket.view)
  if (!peer.eligible) peer.queue = InputQueue.fresh(Lobby.input_epoch(lobby), currentWorldTick)
  const publication = initial ? handshake(peer, { $: "Prepared", observation }) : null
  if (initial && publication?.$ !== "PublishInitial") return
  const token = Connection.epoch(peer.gate)
  const snapshot = Network.snapshot(token, initial, runId, observation, guestPacket.view, peer.session, peer.journal, {
    $: "InputTiming",
    worldTick: currentWorldTick,
    lastRejected: peer.rejection ? { $: "Some", value: { $: "RejectedInput", ...peer.rejection } } : { $: "None" }
  })
  const bytes = encodeSnapshotValues(snapshot)
  emit(
    {
      type: "remote-frame",
      player: peer.player,
      bytes,
      observationSeq: observation,
      connectionEpoch: peer.epoch,
      token
    },
    [bytes.buffer]
  )
}
let finished = false
function publish(initialPeer?: Peer) {
  if (finished) return
  const observation = ++observationSeq
  const local = packet(Game.core_observe(core, 0))
  if (!local || !("combatForecast" in local)) throw Error("Missing display observation")
  currentPhase = local.phase
  if (local.roundId !== currentRound) {
    lobby = Lobby.pause(lobby)
    emitLobby()
  }
  for (const peer of peers.values())
    if (local.roundId !== currentRound || currentPhase !== 0)
      peer.queue = InputQueue.fresh(Lobby.input_epoch(lobby), currentWorldTick)
  currentRound = local.roundId
  emit({
    type: "frame",
    frame: local,
    observationSeq: observation,
    contactJournal,
    connectionReady: Lobby.running(lobby)
  })
  for (const peer of peers.values()) {
    if (peer === initialPeer) publishPeer(peer, observation, true)
    else if (Connection.running(peer.gate)) publishPeer(peer, observation)
  }
  if (Finish.terminal(currentPhase)) {
    finished = true
    clearInterval(timer)
    emit({ type: "finished", observationSeq: observation })
  }
}
function prepareWorld(peer: Peer, action: Extract<BendABI.CoopSession.Action, { $: "Setup" }>) {
  if (!Lobby.admit(lobby, peer.player)) return reject(peer, "SetupFailed")
  try {
    const joined = Game.core_attach_player(
      core,
      peer.player,
      action.character,
      action.meta,
      action.arcana,
      action.allowedWeapons
    )
    packet(joined)
    if (joined.$ !== "CorePacket") return reject(peer, "SetupFailed")
    if (!peer.attached) peer.character = action.character
    peer.attached = true
    peer.setup = action
    updateSeat(peer)
    publish(peer)
  } catch (error) {
    reject(peer, "SetupFailed", error)
  }
}
function rebuildLobbyWorld() {
  const s = initial.setup
  packet(Game.core_start(s.character, s.meta, initial.seed))
  packet(Game.core_configure(core, s.stage, s.mode, s.arcana))
  packet(Game.core_configure_unlocks(core, 0, s.allowedWeapons))
  for (const member of peers.values()) {
    const setup = member.setup
    if (member.attached && setup)
      packet(
        Game.core_attach_player(core, member.player, setup.character, setup.meta, setup.arcana, setup.allowedWeapons)
      )
  }
}
function acceptCommand(command: BendABI.CoopSession.Command, player: number) {
  const peer = peers.get(player)
  const action = command.action
  if (player !== 0 && !peer) return
  if (action.$ === "Choice" && !Lobby.running(lobby)) {
    emit({ type: "choice-unavailable", player, connectionEpoch: peer?.epoch ?? 0 })
    return
  }
  if (peer && action.$ !== "Setup" && !Connection.running(peer.gate)) return
  const admission = peer
    ? Session.receive_peer(peer.session, player, command)
    : Session.receive(hostSession, 0, command)
  if (peer) peer.session = admission.state
  else hostSession = admission.state
  if (!admission.accepted) return
  if (action.$ === "Movement" && peer) return reject(peer, "ProtocolError")
  if (action.$ === "MovementTick" && peer) {
    if (!Lobby.running(lobby)) return
    const queued = InputQueue.push_active(
      peer.queue,
      currentPhase,
      peer.eligible,
      action.round,
      command.seq,
      command.intendedTick,
      action.x,
      action.y
    )
    if (!queued.accepted) {
      peer.rejection = {
        reason: queued.reason,
        seq: command.seq,
        targetWorldTick: command.intendedTick,
        worldTick: currentWorldTick
      }
      emit({ type: "input-rejected", player, ...peer.rejection, connectionEpoch: peer.epoch })
    }
    peer.queue = queued.state
    if (queued.reason === 8) reject(peer, "ProtocolError")
  } else if (action.$ === "Choice") {
    packet(Game.core_choose(core, player, action.round, action.index))
    publish()
  } else if (action.$ === "Setup" && peer) {
    if (Connection.running(peer.gate)) {
      if (!Lobby.can_configure(lobby, peer.player)) return
      peer.setup = action
      peer.character = action.character
      rebuildLobbyWorld()
      updateSeat(peer)
      publish()
    } else if (handshake(peer, { $: "Setup" }).$ === "PrepareWorld") prepareWorld(peer, action)
  }
}
function accept(text: string, player: number) {
  const decoded = ClientDelivery.decode(text)
  if (decoded.$ !== "Some") {
    const peer = peers.get(player)
    if (peer) reject(peer, "ProtocolError")
    return
  }
  for (let rows = decoded.value.commands; rows.$ === "Con"; rows = rows.tail) acceptCommand(rows.head, player)
}
function schedule() {
  const now = performance.now()
  const elapsed = Math.min(4 * STEP, Math.max(0, now - last))
  last = now
  if (finished || !Lobby.running(lobby)) {
    accumulator = 0
    return
  }
  accumulator += elapsed
  let steps = 0
  while (!finished && Lobby.running(lobby) && accumulator >= STEP && steps++ < 4) {
    hostSession = Session.clock(hostSession)
    const move = Session.directions(hostSession)
    const moves: BendABI.CoopCore.Movement[] = [{ $: "Movement", id: 0, x: move.x0, y: move.y0 }]
    const pending = new Map<number, BendABI.CoopInputQueue.Taken>()
    for (const peer of peers.values()) {
      if (!peer.attached) continue
      peer.session = Session.clock(peer.session)
      const taken = InputQueue.take_at(peer.queue, currentWorldTick + 1)
      pending.set(peer.player, taken)
      const input = taken.tick.$ === "Some" ? taken.tick.value : null
      moves.push({
        $: "Movement",
        id: peer.player,
        x: input ? Session.axis(input.x) : 0,
        y: input ? Session.axis(input.y) : 0
      })
    }
    let rows: BendList<BendABI.CoopCore.Movement> = { $: "Nil" }
    for (let i = moves.length - 1; i >= 0; i--) {
      const head = moves[i]
      if (head) rows = { $: "Con", head, tail: rows }
    }
    const frame = packet(Game.core_step_players(core, rows))
    if (frame && "advanced" in frame && frame.advanced) {
      for (const peer of peers.values()) {
        const taken = pending.get(peer.player)
        if (!taken) continue
        if (taken.state.worldTick !== frame.tick) throw Error("Input clock disagreed with the authoritative game step.")
        peer.queue = taken.state
        peer.session = Session.applied(frame.tick, peer.session)
        peer.journal = HitJournal.ingest_capped(peer.journal, frame.tick, frame.contacts, frame.contactsOmitted)
      }
      hostSession = Session.applied(frame.tick, hostSession)
      contactJournal = HitJournal.ingest_capped(contactJournal, frame.tick, frame.contacts, frame.contactsOmitted)
    }
    if (frame && frame.phase !== lastPhase) {
      lastPhase = frame.phase
      lastSnapshot = now
      publish()
    }
    accumulator -= STEP
  }
  if (!finished && Lobby.running(lobby) && now - lastSnapshot >= 50) {
    lastSnapshot = now
    publish()
  }
}
onmessage = (event: MessageEvent<WorkerRequest>) => {
  const message = event.data
  if (finished && message.type !== "stop") return
  try {
    switch (message.type) {
      case "init": {
        initial = message
        clearInterval(timer)
        peers.clear()
        runId = message.runId
        sessionId = message.session
        accumulator = observationSeq = currentRound = currentPhase = currentWorldTick = 0
        lastPhase = undefined
        contactJournal = HitJournal.fresh(0)
        hostSession = Session.fresh(sessionId)
        const s = message.setup
        lobby = Lobby.fresh(s.character)
        packet(Game.core_start(s.character, s.meta, message.seed))
        packet(Game.core_configure(core, s.stage, s.mode, s.arcana))
        packet(Game.core_configure_unlocks(core, 0, s.allowedWeapons))
        last = performance.now()
        timer = setInterval(() => {
          try {
            schedule()
          } catch (error) {
            for (const peer of peers.values()) reject(peer, "RuntimeFailed", error)
          }
        }, 4)
        emit({ type: "ready" })
        emitLobby()
        break
      }
      case "configure": {
        const setup = message.setup
        if (
          !Lobby.can_configure_host(lobby, setup.character, setup.stage, setup.mode, setup.arcana, setup.allowedWeapons)
        )
          break
        initial = { ...initial, setup }
        rebuildLobbyWorld()
        lobby = Lobby.update(lobby, { $: "Seat", player: 0, character: setup.character, ready: true, connected: true })
        emitLobby()
        publish()
        break
      }
      case "connected": {
        if (!Lobby.admit(lobby, message.player)) break
        let peer = peers.get(message.player)
        if (!peer) {
          peer = {
            player: message.player,
            gate: Connection.fresh({ $: "Host" }),
            session: Session.fresh(sessionId),
            queue: InputQueue.fresh(Lobby.input_epoch(lobby), currentWorldTick),
            eligible: false,
            rejection: null,
            epoch: 0,
            journal: HitJournal.fresh(0),
            character: 0,
            attached: false,
            setup: null
          }
          peers.set(message.player, peer)
        }
        const transition = Connection.reconnect(peer.gate, message.connectionEpoch)
        if (transition.action.$ !== "SendHello") break
        peer.epoch = message.connectionEpoch
        peer.journal = HitJournal.fresh(peer.epoch)
        peer.session = Session.reconnect(peer.session)
        peer.queue = InputQueue.fresh(Lobby.input_epoch(lobby), currentWorldTick)
        peer.rejection = null
        accumulator = 0
        applyConnection(peer, transition)
        break
      }
      case "handshake": {
        const peer = peers.get(message.player)
        if (peer && message.connectionEpoch === peer.epoch) handshake(peer, message.signal)
        break
      }
      case "command": {
        const peer = peers.get(message.player)
        if (message.player === 0 || peer?.epoch === message.connectionEpoch) accept(message.text, message.player)
        break
      }
      case "disconnect": {
        const peer = peers.get(message.player)
        if (!peer) break
        peer.epoch = message.connectionEpoch
        lobby = Lobby.pause(lobby)
        for (const member of peers.values()) member.queue = InputQueue.fresh(Lobby.input_epoch(lobby), currentWorldTick)
        handshake(peer, { $: "ConnectionLost" })
        peer.queue = InputQueue.fresh(Lobby.input_epoch(lobby), currentWorldTick)
        peer.eligible = false
        peer.session = Session.disconnect(1, peer.session)
        accumulator = 0
        if (!Lobby.started(lobby)) {
          lobby = Lobby.leave(lobby, peer.player)
          peer.attached = false
          peer.setup = null
          rebuildLobbyWorld()
          emitLobby()
        }
        publish()
        break
      }
      case "start":
        lobby = Lobby.start(lobby)
        last = performance.now()
        accumulator = 0
        emitLobby()
        publish()
        break
      case "stop":
        clearInterval(timer)
        close()
        break
    }
  } catch (error) {
    const peer = "player" in message ? peers.get(message.player) : undefined
    if (peer) reject(peer, "RuntimeFailed", error)
    else
      emit({
        type: "error",
        player: 0,
        message: errorMessage(error),
        connectionEpoch: 0,
        context: { worldTick: currentWorldTick }
      })
  } finally {
    if (message.type === "command") emit({ type: "command-consumed", deliveryId: message.deliveryId })
  }
}
