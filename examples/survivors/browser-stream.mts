import Session from "./dist/stream-session.mjs"
import Bot from "./dist/stream-bot.mjs"
import { rows, errorMessage } from "./host-values.mts"
import { StreamStrategies, type StrategyLogContext } from "./stream-strategies.mts"
import type { Decision, RequestIdentity } from "./stream-strategy-types.mts"
export type StreamDiagnostic = {
  session: number
  run: number
  tick: number
  phase: number
  mode: string
  paused: boolean
  frames: number
  generation: number
  revision: string
  status: string
  commits: number
  lastError: string
  logs: {
    event: string
    detail: string
    tick: number
    at: number
    session: number
    run: number
    generation: number
    revision: string
    request: number
    decision: number
    originSession: number
    originRun: number
    intention: BendABI.StreamBot.Intention | null
  }[]
}
const query = new URL(location.href).searchParams
function duration(name: string, fallback: number) {
  const value = Number(query.get(name) ?? fallback)
  if (!Number.isSafeInteger(value) || value < 0 || value > 60000) throw Error(`Invalid stream ${name}`)
  return value
}
function streamSeed() {
  const value = Number(query.get("seed") ?? 982451653)
  if (!Number.isSafeInteger(value) || value < 0 || value > 0xffffffff) throw Error("Invalid stream seed")
  return value
}
export class BrowserStream {
  private machine = Session.fresh(duration("advice", 500), duration("dwell", 1500), duration("between", 5000))
  private memory = Bot.initial()
  private observation: BendABI.StreamBot.Observation | undefined
  private strategies: StreamStrategies | undefined
  private signature = ""
  private serial = 0
  private session = 0
  private run = 0
  private seed = streamSeed()
  private nextAdvice = 0
  private latest = 0
  private actualPhase = 0
  private frames = 0
  private commits = 0
  private lastDraw = 0
  private intention = "Ready to observe"
  private logs: StreamDiagnostic["logs"] = []
  private error = ""
  private adviceSource: StrategyLogContext | undefined
  private frozenSource: StrategyLogContext | undefined
  private starting = false
  private frameTicks = 0
  private fpsFrames = 0
  private statsAt = performance.now()
  private fps = 0
  private tps = 0
  private readonly hooks: {
    start(seed: number): Promise<void>
    choose(index: number): void
    stop(): void
    audio(): string
    unlock(): void
    audioStop(): void
  }
  constructor(hooks: BrowserStream["hooks"]) {
    this.hooks = hooks
    const container = document.createElement("section")
    container.id = "stream-controls"
    container.innerHTML = `<div class="stream-heading"><strong>✦ Stream session</strong><span id="stream-status">Ready</span><button id="stream-compact" aria-label="Toggle stream controls" aria-expanded="true">⚙</button></div><div class="stream-actions"><button id="stream-start">Start stream</button><button id="stream-pause" disabled>Pause</button><button id="stream-stop" disabled>Stop</button><button id="stream-reload">Reload strategy</button><button id="stream-audio">Resume audio</button><a href="./">Player mode</a></div><label class="stream-module">Strategy manifest <input id="stream-strategy" value="" spellcheck="false"></label><p id="stream-intention">Ready to observe</p><p id="stream-error" role="alert" hidden></p><details><summary>Diagnostics</summary><pre id="stream-diagnostics"></pre></details>`
    document.body.append(container)
    const input = container.querySelector<HTMLInputElement>("#stream-strategy")
    if (input) input.value = query.get("strategy") ?? "./stream-strategy.json"
    container.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return
      const id = event.target.closest("button")?.id
      if (id === "stream-start") {
        this.hooks.unlock()
        void this.start(true).catch((error: unknown) => this.fail(error))
      } else if (id === "stream-pause") {
        this.hooks.unlock()
        this.pause(!this.machine.paused)
      } else if (id === "stream-stop") this.stop()
      else if (id === "stream-reload" && this.observation)
        void this.strategies?.reload(this.manifest(), this.observation)
      else if (id === "stream-audio") this.hooks.unlock()
      else if (id === "stream-compact") {
        const compact = container.classList.toggle("stream-compact")
        container.querySelector("#stream-compact")?.setAttribute("aria-expanded", String(!compact))
      }
    })
    this.draw()
  }
  get active() {
    return this.machine.mode.$ !== "Stopped" || this.starting
  }
  get runningSession() {
    return this.machine.mode.$ !== "Stopped"
  }
  get paused() {
    return this.machine.paused
  }
  get canMove() {
    return Session.can_move(this.machine)
  }
  private now() {
    return Math.floor(performance.now())
  }
  private manifest() {
    return document.querySelector<HTMLInputElement>("#stream-strategy")?.value ?? "./stream-strategy.json"
  }
  private log(
    event: string,
    detail: string,
    origin?: RequestIdentity,
    source?: StrategyLogContext,
    intention: BendABI.StreamBot.Intention | null = null
  ) {
    const identity = origin ?? source?.identity ?? this.machine.identity
    this.logs.push({
      event,
      detail: detail.slice(0, 500),
      tick: this.latest,
      at: this.now(),
      session: this.session,
      run: this.run,
      generation: source?.generation ?? this.machine.identity.generation,
      revision: source?.revision ?? this.strategies?.contentRevision ?? "Bend fallback",
      request: identity.request,
      decision: identity.decision,
      originSession: identity.session,
      originRun: identity.run,
      intention
    })
    if (this.logs.length > 200) this.logs.splice(0, this.logs.length - 200)
  }
  private apply(input: BendABI.StreamSession.Input) {
    const before = this.machine
    const result = Session.step(this.machine, input)
    this.machine = result.state
    if (before.mode.$ === "Advice" && result.state.mode.$ === "Dwell") {
      this.frozenSource = before.mode.received
        ? this.adviceSource
        : { generation: 0, revision: "Bend fallback", identity: before.identity }
      this.log(
        "recommendation-frozen",
        String(result.state.mode.index),
        this.frozenSource?.identity ?? before.identity,
        this.frozenSource
      )
    }
    if (result.effect.$ === "Commit") {
      ++this.commits
      this.log("commit", String(result.effect.index), this.frozenSource?.identity ?? before.identity, this.frozenSource)
      this.hooks.choose(result.effect.index)
      this.machine = Session.step(this.machine, { $: "Played" }).state
      this.signature = ""
    } else if (result.effect.$ === "NextRun") void this.start(false).catch((error: unknown) => this.fail(error))
    return result.accepted
  }
  private async start(newSession: boolean) {
    if (this.starting) return
    this.starting = true
    if (newSession) {
      this.strategies?.stop()
      const session = Math.max(Date.now(), this.session + 1)
      if (!Number.isSafeInteger(session)) throw Error("Stream session identity exhausted")
      this.session = session
      this.run = 0
      this.logs = []
      this.commits = 0
      this.strategies = new StreamStrategies({
        identity: () => this.machine.identity,
        ready: () => {},
        decision: (identity, result) => this.advice(identity, result),
        fallback: () => {
          this.memory = Bot.fallback(this.memory)
          this.intention = "Follow the Bend policy"
        },
        log: (event, detail, source) => {
          this.log(event, detail, undefined, source)
          if (event.endsWith("failed")) this.error = detail
        }
      })
    }
    ++this.run
    this.memory = Bot.initial()
    this.adviceSource = this.frozenSource = undefined
    this.signature = ""
    this.observation = undefined
    this.intention = "Find a safe route"
    this.error = ""
    this.strategies?.resetMemory()
    this.apply({
      $: "Start",
      session: this.session,
      run: this.run,
      generation: this.strategies?.activeGeneration ?? 0,
      now: this.now()
    })
    const seed = this.seed
    this.seed = (this.seed + 2654435761) >>> 0
    try {
      await this.hooks.start(seed)
      if (this.machine.mode.$ !== "Stopped") this.log("run-started", `Run ${this.run}, seed ${seed}`)
    } finally {
      this.starting = false
    }
    this.draw()
  }
  private advice(identity: RequestIdentity, result: Decision) {
    const intention = result.intention
    let accepted = false
    if (intention.$ === "UpgradeChoice")
      accepted = this.apply({ $: "Reply", identity, index: intention.index, now: this.now() })
    else if (intention.$ === "GoalChoice") {
      accepted = this.apply({
        $: "MovementReply",
        identity,
        index: intention.index,
        count: this.observation ? rows(this.observation.goals).length : 0,
        now: this.now()
      })
      if (accepted) this.memory = Bot.choose(this.memory, intention.index)
    } else if (this.machine.mode.$ === "Advice")
      accepted = this.apply({ $: "Reply", identity, index: this.machine.mode.fallback, now: this.now() })
    else {
      accepted = this.apply({ $: "MovementReply", identity, index: 0, count: 1, now: this.now() })
      if (accepted) this.memory = Bot.fallback(this.memory)
    }
    const source = {
      generation: identity.generation,
      revision: this.strategies?.contentRevision ?? "Bend fallback",
      identity
    }
    this.log(accepted ? "advice-accepted" : "advice-rejected", result.label, identity, source, intention)
    if (accepted && this.machine.mode.$ === "Advice") this.adviceSource = source
    if (accepted) this.intention = result.label || "Follow the Bend policy"
    return accepted
  }
  private viewport() {
    return document.querySelector<HTMLCanvasElement>("#game") ?? { width: 1024, height: 640 }
  }
  observed(state: BendABI.Game.State) {
    this.latest = state.run.session.tick
    this.actualPhase = state.run.session.phase
  }
  movement(state: BendABI.Game.State) {
    const planned = Bot.plan(
      this.memory,
      state.run,
      state.offers,
      state.snapshots,
      this.viewport().width,
      this.viewport().height
    )
    this.memory = planned.memory
    if (!this.observation || !Bot.same_goals(this.observation.goals, planned.observation.goals)) {
      this.apply({ $: "Invalidate" })
      this.strategies?.invalidate()
      this.nextAdvice = 0
    }
    this.observation = planned.observation
    ++this.frameTicks
    return { x: planned.dx, y: planned.dy }
  }
  frame(now: number, state: BendABI.Game.State | undefined) {
    ++this.frames
    ++this.fpsFrames
    if (now - this.statsAt >= 1000) {
      this.fps = Math.round((this.fpsFrames * 1000) / (now - this.statsAt))
      this.tps = Math.round((this.frameTicks * 1000) / (now - this.statsAt))
      this.frameTicks = this.fpsFrames = 0
      this.statsAt = now
    }
    if (this.active && state && !this.starting) {
      this.latest = state.run.session.tick
      const phase = state.run.session.phase
      this.actualPhase = phase
      const offers = rows(state.offers)
      const signature = `${phase}:${offers.map((offer) => `${offer.kind},${offer.id},${offer.level}`).join(";")}`
      if ((phase === 1 || phase === 2) && signature !== this.signature) {
        this.signature = signature
        this.adviceSource = this.frozenSource = undefined
        this.strategies?.invalidate()
        this.observation = Bot.plan(
          this.memory,
          state.run,
          state.offers,
          state.snapshots,
          this.viewport().width,
          this.viewport().height
        ).observation
        this.apply({
          $: "Offers",
          decision: ++this.serial,
          phase,
          count: offers.length,
          fallback: this.observation.fallback,
          now: Math.floor(now)
        })
        this.request()
      } else if (phase >= 3 && this.machine.mode.$ !== "BetweenRuns") {
        this.strategies?.invalidate()
        this.apply({ $: "Ended", now: Math.floor(now) })
        this.log("run-ended", phase === 4 ? "Victory" : "Death")
      }
      const candidate = this.strategies?.readyGeneration
      if (candidate !== undefined && this.apply({ $: "Activate", generation: candidate })) {
        this.strategies?.activate(candidate)
        if (this.machine.mode.$ === "Advice") this.request()
        this.nextAdvice = 0
      }
      this.apply({ $: "Frame", now: Math.floor(now) })
      if (this.observation) {
        this.strategies?.recover(this.manifest(), this.observation)
        if (
          !this.machine.paused &&
          this.machine.mode.$ === "Advice" &&
          !this.machine.mode.received &&
          !this.strategies?.busy
        )
          this.request()
        if (this.canMove && now >= this.nextAdvice && !this.strategies?.busy) {
          this.apply({ $: "Request", decision: ++this.serial, phase, now: Math.floor(now) })
          this.request()
          this.nextAdvice = now + 500
        }
      }
      this.highlight()
    }
    if (now - this.lastDraw > 200) {
      this.lastDraw = now
      this.draw()
    }
  }
  private request() {
    if (!this.machine.paused && this.observation) this.strategies?.request(this.machine.identity, this.observation)
  }
  pause(paused: boolean, reason = "Operator") {
    if (!this.active) return
    this.apply({ $: paused ? "Pause" : "Resume", now: this.now() })
    this.strategies?.invalidate()
    this.hooks.audioStop()
    this.log(paused ? "paused" : "resumed", reason)
    if (!paused && this.machine.mode.$ === "Advice") this.request()
    this.draw()
  }
  stop() {
    this.apply({ $: "Stop" })
    this.strategies?.stop()
    this.signature = ""
    this.hooks.stop()
    this.intention = "Stream stopped"
    this.log("stopped", "All strategy work retired")
    this.draw()
  }
  fail(error: unknown) {
    this.error = errorMessage(error)
    this.stop()
    this.intention = "Simulation failed. Start a new session."
    this.log("simulation-failed", this.error)
    this.draw()
  }
  private highlight() {
    const mode = this.machine.mode
    const index = mode.$ === "Dwell" ? mode.index : mode.$ === "Advice" && mode.received ? mode.recommendation : -1
    for (const button of document.querySelectorAll<HTMLButtonElement>("[data-choice]")) {
      button.disabled = true
      const selected = Number(button.dataset.choice) === index
      button.classList.toggle("stream-recommendation", selected)
      const recommendation = selected ? (mode.$ === "Dwell" ? "frozen" : "considering") : "none"
      if (button.dataset.streamRecommendation !== recommendation) button.dataset.streamRecommendation = recommendation
    }
    for (const button of document.querySelectorAll<HTMLButtonElement>("#dialog [data-run],#banish"))
      button.disabled = true
  }
  diagnostic(): StreamDiagnostic {
    return {
      session: this.session,
      run: this.run,
      tick: this.latest,
      phase: this.actualPhase,
      mode: this.machine.mode.$,
      paused: this.machine.paused,
      frames: this.frames,
      generation: this.machine.identity.generation,
      revision: this.strategies?.revision ?? "Bend fallback",
      status: this.strategies?.status ?? "stopped",
      commits: this.commits,
      lastError: this.error || this.strategies?.lastError || "",
      logs: this.logs
    }
  }
  private draw() {
    const diagnostic = this.diagnostic()
    const status = document.querySelector("#stream-status")
    if (status)
      status.textContent = `${this.machine.paused ? "Paused" : diagnostic.mode} · ${diagnostic.status} · ${this.fps} FPS / ${this.tps} TPS · audio ${this.hooks.audio()}`
    const intention = document.querySelector("#stream-intention")
    if (intention) intention.textContent = this.intention
    const error = document.querySelector<HTMLElement>("#stream-error")
    if (error) {
      error.hidden = !diagnostic.lastError
      error.textContent = diagnostic.lastError
    }
    const diagnostics = document.querySelector("#stream-diagnostics")
    if (diagnostics) diagnostics.textContent = JSON.stringify(diagnostic, null, 2)
    const start = document.querySelector<HTMLButtonElement>("#stream-start")
    const pause = document.querySelector<HTMLButtonElement>("#stream-pause")
    const stop = document.querySelector<HTMLButtonElement>("#stream-stop")
    if (start) start.disabled = this.active
    if (pause) {
      pause.disabled = !this.active
      pause.textContent = this.machine.paused ? "Resume" : "Pause"
    }
    if (stop) stop.disabled = !this.active
  }
}
