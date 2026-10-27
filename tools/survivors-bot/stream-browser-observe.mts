export function installStreamObservers() {
  if (new URL(location.href).searchParams.has("stream-goals-check")) {
    const positions: { tick: number; x: number; y: number }[] = []
    new MutationObserver((mutations) => {
      const canvas = document.querySelector<HTMLCanvasElement>("#game")
      if (!canvas) return
      const state = {
        tick: Number(canvas.dataset.tick),
        x: Number(canvas.dataset.playerX),
        y: Number(canvas.dataset.playerY)
      }
      const batch: typeof positions = []
      for (const mutation of mutations.toReversed()) {
        if (mutation.target !== canvas) continue
        if (mutation.attributeName === "data-tick") {
          if (Number.isFinite(state.tick) && state.tick <= 120) batch.push({ ...state })
          state.tick = Number(mutation.oldValue)
        } else if (mutation.attributeName === "data-player-x") state.x = Number(mutation.oldValue)
        else if (mutation.attributeName === "data-player-y") state.y = Number(mutation.oldValue)
      }
      positions.push(...batch.toReversed())
      if (positions.length > 256) positions.splice(0, positions.length - 256)
      document.documentElement.dataset.checkGoalPositions = JSON.stringify(positions)
    }).observe(document, {
      subtree: true,
      attributes: true,
      attributeOldValue: true,
      attributeFilter: ["data-tick", "data-player-x", "data-player-y"]
    })
  }
  const goalInputs: unknown[] = []
  const liveBlobs = new Set<string>()
  const createObjectURL = URL.createObjectURL.bind(URL)
  const revokeObjectURL = URL.revokeObjectURL.bind(URL)
  let createdBlobs = 0
  URL.createObjectURL = (object) => {
    const url = createObjectURL(object)
    liveBlobs.add(url)
    document.documentElement.dataset.checkBlobLive = String(liveBlobs.size)
    document.documentElement.dataset.checkBlobCreated = String(++createdBlobs)
    return url
  }
  URL.revokeObjectURL = (url) => {
    revokeObjectURL(url)
    liveBlobs.delete(url)
    document.documentElement.dataset.checkBlobLive = String(liveBlobs.size)
  }
  const NativeWorker = globalThis.Worker
  globalThis.Worker = class extends NativeWorker {
    constructor(url: string | URL, options?: WorkerOptions) {
      if (document.documentElement.dataset.checkWorkerConstructorFailure === "armed") {
        document.documentElement.dataset.checkWorkerConstructorFailure = "observed"
        throw new Error("acceptance Worker construction failure")
      }
      super(url, options)
      this.addEventListener("message", (event: MessageEvent<unknown>) => {
        const value = event.data
        if (
          value !== null &&
          typeof value === "object" &&
          "kind" in value &&
          value.kind === "failure" &&
          "message" in value &&
          typeof value.message === "string"
        ) {
          const previous = Number(document.documentElement.dataset.checkWorkerFailureLength ?? 0)
          document.documentElement.dataset.checkWorkerFailureLength = String(Math.max(previous, value.message.length))
        }
      })
    }
    override postMessage(message: unknown, options?: Transferable[] | StructuredSerializeOptions) {
      if (
        message !== null &&
        typeof message === "object" &&
        "kind" in message &&
        message.kind === "decide" &&
        "observation" in message
      ) {
        const observation = message.observation
        if (
          observation !== null &&
          typeof observation === "object" &&
          "phase" in observation &&
          observation.phase === 0 &&
          "tick" in observation &&
          "px" in observation &&
          "py" in observation &&
          "goals" in observation &&
          "identity" in message
        ) {
          goalInputs.push({
            identity: message.identity,
            tick: observation.tick,
            px: observation.px,
            py: observation.py,
            goals: observation.goals
          })
          if (goalInputs.length > 16) goalInputs.shift()
          document.documentElement.dataset.checkGoalInputs = JSON.stringify(goalInputs)
        }
        if (
          observation !== null &&
          typeof observation === "object" &&
          "phase" in observation &&
          (observation.phase === 1 || observation.phase === 2) &&
          "fallback" in observation &&
          typeof observation.fallback === "number" &&
          "tick" in observation &&
          typeof observation.tick === "number" &&
          "offers" in observation
        ) {
          let offers = observation.offers,
            count = 0
          while (
            offers !== null &&
            typeof offers === "object" &&
            "$" in offers &&
            offers.$ === "Con" &&
            "tail" in offers &&
            count < 16
          ) {
            count++
            offers = offers.tail
          }
          document.documentElement.dataset.checkUpgradeFallback = String(observation.fallback)
          document.documentElement.dataset.checkUpgradeOfferCount = String(count)
          document.documentElement.dataset.checkUpgradeTick = String(observation.tick)
          document.documentElement.dataset.checkUpgradeSentAt = String(performance.now())
          if ("identity" in message)
            document.documentElement.dataset.checkUpgradeIdentity = JSON.stringify(message.identity)
        }
      }
      if (Array.isArray(options)) super.postMessage(message, options)
      else super.postMessage(message, options)
    }
  }
  const Original = globalThis.AudioContext
  if (!Original) return
  let nodes = 0
  let contexts = 0
  let tappedMaster = false
  type RunningEpoch =
    | { kind: "inactive"; id: number }
    | { kind: "running"; id: number; baseline: number; lastSampleTime: number }
  globalThis.AudioContext = class extends Original {
    private epoch: RunningEpoch = { kind: "inactive", id: 0 }
    private observeState() {
      const data = document.documentElement.dataset
      data.checkAudioState = this.state
      data.checkAudioCurrentTime = String(this.currentTime)
      data.checkAudioSampleRate = String(this.sampleRate)
      if (this.state === "running" && this.epoch.kind === "inactive") {
        this.epoch = {
          kind: "running",
          id: this.epoch.id + 1,
          baseline: this.currentTime,
          lastSampleTime: this.currentTime
        }
        data.checkAudioRecentPcmPeak = "0"
      } else if (this.state !== "running" && this.epoch.kind === "running") {
        this.epoch = { kind: "inactive", id: this.epoch.id }
        data.checkAudioRecentPcmPeak = "0"
      }
      data.checkAudioEpoch = String(this.epoch.id)
      data.checkAudioRunningBaseline = this.epoch.kind === "running" ? String(this.epoch.baseline) : ""
    }
    constructor(options?: AudioContextOptions) {
      super(options)
      document.documentElement.dataset.checkAudioContexts = String(++contexts)
      document.addEventListener("stream-check-suspend-audio", () => {
        void this.suspend()
          .then(() => {
            this.observeState()
            document.documentElement.dataset.checkAudioSuspendedAt = String(this.currentTime)
            document.documentElement.dataset.checkAudioSuspendedWallAt = String(performance.now())
            document.documentElement.dataset.checkAudioSuspendCompleted = "true"
          })
          .catch((error: unknown) => {
            document.documentElement.dataset.checkAudioSuspendError = String(error)
          })
      })
      document.addEventListener("stream-check-observe-audio", () => this.observeState())
      this.observeState()
      this.addEventListener("statechange", () => this.observeState())
    }
    override createGain() {
      const gain = super.createGain()
      if (tappedMaster) return gain
      const connect = gain.connect.bind(gain)
      Object.defineProperty(gain, "connect", {
        value: (destination: AudioNode | AudioParam, output?: number, input?: number) => {
          if (destination instanceof AudioNode) {
            if (!tappedMaster && destination === this.destination) {
              tappedMaster = true
              const analyser = this.createAnalyser()
              analyser.fftSize = 256
              connect(analyser)
              const samples = new Float32Array(256)
              const recent: { at: number; peak: number; epoch: number }[] = []
              let observedPeak = 0
              setInterval(() => {
                this.observeState()
                analyser.getFloatTimeDomainData(samples)
                const peak = samples.reduce((maximum, value) => Math.max(maximum, Math.abs(value)), 0)
                const now = performance.now()
                observedPeak = Math.max(observedPeak, peak)
                const contextTime = this.currentTime
                const epoch = this.epoch
                const eligible =
                  epoch.kind === "running" &&
                  contextTime > epoch.lastSampleTime &&
                  contextTime > epoch.baseline + (analyser.fftSize + 128) / this.sampleRate
                if (eligible) {
                  recent.push({ at: now, peak, epoch: epoch.id })
                  document.documentElement.dataset.checkAudioEligibleSampleTime = String(contextTime)
                  document.documentElement.dataset.checkAudioEligibleSampleEpoch = String(epoch.id)
                  document.documentElement.dataset.checkAudioEligibleSamplePeak = String(peak)
                }
                if (epoch.kind === "running") epoch.lastSampleTime = contextTime
                while (
                  recent[0] &&
                  (recent[0].at < now - 1000 || recent[0].epoch !== epoch.id || epoch.kind !== "running")
                )
                  recent.shift()
                document.documentElement.dataset.checkAudioRecentSamples = JSON.stringify(recent)
                document.documentElement.dataset.checkAudioFftSize = String(analyser.fftSize)
                document.documentElement.dataset.checkAudioRawPcmPeak = String(peak)
                document.documentElement.dataset.checkAudioSampleEligible = String(eligible)
                document.documentElement.dataset.checkAudioPcmPeak = String(observedPeak)
                document.documentElement.dataset.checkAudioRecentPcmPeak = String(
                  Math.max(0, ...recent.map((sample) => sample.peak))
                )
              }, 100)
            }
            return connect(destination, output, input)
          }
          return connect(destination, output)
        }
      })
      return gain
    }
    override createOscillator() {
      document.documentElement.dataset.checkAudioNodes = String(++nodes)
      return super.createOscillator()
    }
    override createBufferSource() {
      document.documentElement.dataset.checkAudioNodes = String(++nodes)
      return super.createBufferSource()
    }
  }
  type Span = {
    index: string
    startedAt: number
    endedAt: number
    activeMs: number
    frozenAt: number | null
    frozenActiveMs: number
  }
  let current:
    | {
        element: Element
        index: string
        startedAt: number
        at: number
        activeMs: number
        frozenAt: number | null
        frozenActiveMs: number
        paused: boolean
        frozen: boolean
      }
    | undefined
  const completed: Span[] = []
  const observer = new MutationObserver(() => {
    const button = document.querySelector<HTMLButtonElement>("#dialog .stream-recommendation")
    const selected = button && !button.closest<HTMLElement>("#overlay")?.hidden ? button : null
    const paused = document.querySelector("#stream-pause")?.textContent === "Resume"
    const frozen = selected?.dataset.streamRecommendation === "frozen"
    const now = performance.now()
    if (current && (current.element !== selected || current.paused !== paused || current.frozen !== frozen)) {
      if (!current.paused) {
        current.activeMs += now - current.at
        if (current.frozen) current.frozenActiveMs += now - current.at
      }
      current.at = now
      if (current.element !== selected) {
        completed.push({
          index: current.index,
          startedAt: current.startedAt,
          endedAt: now,
          activeMs: current.activeMs,
          frozenAt: current.frozenAt,
          frozenActiveMs: current.frozenActiveMs
        })
        if (completed.length > 16) completed.shift()
        document.documentElement.dataset.checkRecommendationSpans = JSON.stringify(completed)
        current = undefined
      } else {
        current.paused = paused
        current.frozen = frozen
        if (frozen && current.frozenAt === null) current.frozenAt = now
      }
    }
    if (!current && selected)
      current = {
        element: selected,
        index: selected.dataset.choice ?? "",
        startedAt: now,
        at: now,
        activeMs: 0,
        frozenAt: frozen ? now : null,
        frozenActiveMs: 0,
        paused,
        frozen
      }
  })
  observer.observe(document, { subtree: true, attributes: true, childList: true, characterData: true })
}
