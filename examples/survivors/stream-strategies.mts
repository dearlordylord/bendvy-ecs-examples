import { object, text, number, errorMessage } from "./host-values.mts"
import { decision } from "./stream-strategy-values.mts"
import type { Decision, RequestIdentity, WorkerInput } from "./stream-strategy-types.mts"
async function body(response: Response, limit: number): Promise<Uint8Array<ArrayBuffer>> {
  const length = Number(response.headers.get("content-length") ?? 0)
  if (length > limit) throw Error("Strategy response exceeds size limit")
  const reader = response.body?.getReader()
  if (!reader) throw Error("Strategy response has no body")
  const chunks: Uint8Array[] = []
  let size = 0
  for (;;) {
    const result = await reader.read()
    if (result.done) break
    size += result.value.byteLength
    if (size > limit) {
      await reader.cancel()
      throw Error("Strategy response exceeds size limit")
    }
    chunks.push(result.value)
  }
  const output = new Uint8Array(size)
  let offset = 0
  for (const chunk of chunks) {
    output.set(chunk, offset)
    offset += chunk.byteLength
  }
  return output
}
type Generation = {
  worker: Worker
  generation: number
  revision: string
  memoryVersion: number
  url: string
  hash: string
  origin: RequestIdentity
}
export type StrategyLogContext = { generation: number; revision: string; identity?: RequestIdentity }
export type StrategyStatus = "fallback" | "active" | "reloading" | "stopped"
type Pending = { identity: RequestIdentity; timer: ReturnType<typeof setTimeout>; admitted: boolean }
export class StreamStrategies {
  private active: Generation | undefined
  private candidate: Generation | undefined
  private candidateTimer: ReturnType<typeof setTimeout> | undefined
  private pending: Pending | undefined
  private queued: { identity: RequestIdentity; observation: BendABI.StreamBot.Observation } | undefined
  private generation = 0
  private fetchController: AbortController | undefined
  private alive = true
  private memory: unknown = null
  private memoryVersion = -1
  private retryAt = 0
  private failures = 0
  status: StrategyStatus = "fallback"
  revision = "Bend fallback"
  lastError = ""
  private readonly events: {
    identity(): RequestIdentity
    ready(generation: number): void
    decision(identity: RequestIdentity, decision: Decision): boolean
    log(event: string, detail: string, source: StrategyLogContext): void
  }
  constructor(events: StreamStrategies["events"]) {
    this.events = events
  }
  get readyGeneration() {
    return this.candidate?.revision ? this.candidate.generation : undefined
  }
  get contentRevision() {
    return this.active?.hash ?? "Bend fallback"
  }
  private context(source: Generation, identity?: RequestIdentity): StrategyLogContext {
    return { generation: source.generation, revision: source.hash, identity: identity ?? source.origin }
  }
  get activeGeneration() {
    return this.active?.generation ?? 0
  }
  get busy() {
    return !!this.pending
  }
  private dispose(generation: Generation | undefined) {
    if (!generation) return
    generation.worker.terminate()
    URL.revokeObjectURL(generation.url)
  }
  private report(event: string, error: unknown, source: StrategyLogContext) {
    this.lastError = errorMessage(error).slice(0, 500)
    this.events.log(event, this.lastError, source)
  }
  async reload(manifestUrl: string, observation: BendABI.StreamBot.Observation) {
    if (!this.alive) return
    const generation = ++this.generation
    const origin = this.events.identity()
    this.fetchController?.abort()
    const controller = new AbortController()
    this.fetchController = controller
    const fetchTimer = setTimeout(() => controller.abort(), 3000)
    this.dispose(this.candidate)
    this.candidate = undefined
    clearTimeout(this.candidateTimer)
    this.status = "reloading"
    let unownedBlob: string | undefined
    let loadingRevision = manifestUrl.slice(0, 500)
    try {
      const manifestLocation = new URL(manifestUrl, location.href)
      const response = await fetch(manifestLocation, { cache: "no-store", signal: controller.signal })
      if (!response.ok) throw Error(`Strategy manifest HTTP ${response.status}`)
      const raw: unknown = JSON.parse(new TextDecoder().decode(await body(response, 8192)))
      const manifest = object(raw)
      if (number(manifest.version) !== 1) throw Error("Unsupported strategy manifest version")
      const revision = text(manifest.revision)
      if (!/^[0-9a-f]{64}$/.test(revision)) throw Error("Strategy revision must be SHA-256")
      const url = new URL(text(manifest.module), manifestLocation)
      if (url.origin !== manifestLocation.origin) throw Error("Strategy bundle must share the manifest origin")
      const bundle = await fetch(url, { cache: "no-store", signal: controller.signal })
      if (!bundle.ok) throw Error(`Strategy bundle HTTP ${bundle.status}`)
      const bytes = await body(bundle, 262144)
      if (bytes.byteLength > 262144) throw Error("Strategy bundle exceeds 256 KiB")
      const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
        .map((v) => v.toString(16).padStart(2, "0"))
        .join("")
      if (hash !== revision) throw Error("Strategy bundle content does not match manifest revision")
      if (!this.alive || generation !== this.generation) return
      loadingRevision = revision
      if (this.active?.hash === revision) {
        this.status = "active"
        this.events.log("reload-unchanged", revision, this.context(this.active))
        return
      }
      const blob = URL.createObjectURL(new Blob([new Uint8Array(bytes)], { type: "text/javascript" }))
      unownedBlob = blob
      const worker = new Worker(new URL("./stream-strategy-worker.mjs", import.meta.url), { type: "module" })
      const candidate: Generation = {
        worker,
        generation,
        revision: "",
        memoryVersion: -1,
        url: blob,
        hash: revision,
        origin
      }
      this.candidate = candidate
      unownedBlob = undefined
      worker.addEventListener("error", (event) => this.failed(candidate, event.message))
      worker.addEventListener("messageerror", () => this.failed(candidate, "Uncloneable Worker message"))
      worker.addEventListener("message", (event: MessageEvent<unknown>) =>
        this.receive(candidate, revision, event.data)
      )
      this.candidateTimer = setTimeout(() => this.failed(candidate, "Strategy preparation exceeded 1000 ms"), 1000)
      const input: WorkerInput = {
        kind: "prepare",
        url: blob,
        observation,
        memory: this.memory,
        memoryVersion: this.memoryVersion
      }
      worker.postMessage(input)
    } catch (error) {
      if (this.alive && generation === this.generation) {
        if (this.candidate?.generation === generation) {
          this.dispose(this.candidate)
          this.candidate = undefined
          clearTimeout(this.candidateTimer)
        }
        this.status = this.active ? "active" : "fallback"
        this.report("candidate-failed", error, { generation, revision: loadingRevision, identity: origin })
        this.retryAt = performance.now() + Math.min(30000, 1000 * 2 ** Math.min(this.failures++, 5))
      }
    } finally {
      clearTimeout(fetchTimer)
      if (unownedBlob) URL.revokeObjectURL(unownedBlob)
    }
  }
  private receive(source: Generation, hash: string, value: unknown) {
    if (!this.alive || (source !== this.active && source !== this.candidate)) return
    try {
      const message = object(value)
      if (message.kind === "failure") {
        this.failed(source, text(message.message))
        return
      }
      if (message.kind === "ready" && source === this.candidate) {
        clearTimeout(this.candidateTimer)
        source.revision = `${text(message.revision)} · ${hash.slice(0, 12)}`
        source.memoryVersion = number(message.memoryVersion)
        this.events.log("candidate-ready", source.revision, this.context(source))
        this.events.ready(source.generation)
      } else if (message.kind === "decision" && source === this.active && this.pending) {
        const identity = object(message.identity)
        const expected = this.pending.identity
        if (!Object.entries(expected).every(([key, field]) => identity[key] === field)) return
        const result = decision(message.decision)
        const admitted = this.pending.admitted
        clearTimeout(this.pending.timer)
        this.pending = undefined
        if (admitted) {
          if (this.events.decision(expected, result)) this.memory = result.memory
        } else
          this.events.log(
            "obsolete-advice",
            "Decision completed after admission was invalidated",
            this.context(source, expected)
          )
        const queued = this.queued
        this.queued = undefined
        if (queued) this.request(queued.identity, queued.observation)
      }
    } catch (error) {
      this.failed(source, error)
    }
  }
  activate(generation: number) {
    const candidate = this.candidate
    if (!candidate || candidate.generation !== generation || !candidate.revision) return
    this.retireExecution()
    this.dispose(this.active)
    if (candidate.memoryVersion !== this.memoryVersion) {
      this.memory = null
      this.events.log(
        "memory-reset",
        `Version ${this.memoryVersion} → ${candidate.memoryVersion}`,
        this.context(candidate)
      )
    } else this.events.log("memory-preserved", `Version ${this.memoryVersion}`, this.context(candidate))
    this.memoryVersion = candidate.memoryVersion
    this.active = candidate
    this.candidate = undefined
    this.status = "active"
    this.revision = candidate.revision
    this.failures = 0
    this.events.log("activated", this.revision, this.context(candidate))
  }
  request(identity: RequestIdentity, observation: BendABI.StreamBot.Observation) {
    if (!this.alive || !this.active) return
    if (this.pending) {
      this.queued = { identity, observation }
      return
    }
    const active = this.active
    this.pending = {
      identity,
      admitted: true,
      timer: setTimeout(() => this.failed(active, "Strategy decision exceeded 300 ms"), 300)
    }
    const message: WorkerInput = { kind: "decide", identity, observation, memory: this.memory }
    active.worker.postMessage(message)
  }
  invalidate() {
    this.queued = undefined
    if (this.pending) this.pending.admitted = false
  }
  private retireExecution() {
    this.queued = undefined
    clearTimeout(this.pending?.timer)
    this.pending = undefined
  }
  resetMemory() {
    this.invalidate()
    this.memory = null
  }
  recover(manifest: string, observation: BendABI.StreamBot.Observation) {
    if (
      this.alive &&
      !this.active &&
      !this.candidate &&
      this.status !== "reloading" &&
      performance.now() >= this.retryAt
    )
      void this.reload(manifest, observation)
  }
  private failed(source: Generation, error: unknown) {
    if (source === this.candidate) {
      clearTimeout(this.candidateTimer)
      this.dispose(this.candidate)
      this.candidate = undefined
      this.status = this.active ? "active" : "fallback"
      this.report("candidate-failed", error, this.context(source))
    } else if (source === this.active) {
      const pendingIdentity = this.pending?.identity
      this.retireExecution()
      this.dispose(this.active)
      this.active = undefined
      this.status = this.candidate ? "reloading" : "fallback"
      this.revision = "Bend fallback"
      this.report("active-failed", error, this.context(source, pendingIdentity))
    }
    this.retryAt = performance.now() + Math.min(30000, 1000 * 2 ** Math.min(this.failures++, 5))
  }
  stop() {
    this.alive = false
    this.fetchController?.abort()
    ++this.generation
    this.retireExecution()
    clearTimeout(this.candidateTimer)
    this.dispose(this.active)
    this.dispose(this.candidate)
    this.active = this.candidate = undefined
    this.status = "stopped"
  }
}
