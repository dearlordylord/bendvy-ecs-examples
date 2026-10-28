import { escapeHtml as esc, defined, errorMessage } from "./host-values.mts"
import { element, enableSecondaryRewardTouch } from "./dom.mts"
import type { Setup, SetupKind, Profile } from "./profile.mts"
import { reviveSeconds, type Offer, type Frame, type Player } from "./frame.mts"
import { CHARACTERS, STAGES, ARCANA, RUN_MODES, WEAPONS, PASSIVES, UNIONS, ACHIEVEMENTS } from "./content.mts"
import {
  loadProfile,
  validateSetup,
  metaCode,
  allowedWeapons,
  isUnlocked,
  unlock,
  observeRun,
  recordRun
} from "./progression.mts"
import { Renderer } from "./renderer.mts"
import { AudioEngine } from "./audio.mts"
import { ObservationPresentation } from "./coop-presentation.mts"
import { renderCoopSetup } from "./expedition-menu.mts"
export interface CoopSetup extends Setup {
  meta: number
  allowedWeapons: number
}
export interface CoopLobby {
  room: Pick<Setup, "stage" | "mode">
  players: { player: number; character: number; ready: boolean; connected: boolean }[]
  started: boolean
  canStart: boolean
}
export interface CoopCallbacks {
  onHost?: (setup: CoopSetup) => unknown
  onStart?: () => unknown
  onRetry?: () => unknown
  onSetupChange?: (setup: CoopSetup) => void
  onLeave?: () => unknown
  onInput?: (input: { x: number; y: number }) => void
  onChoice?: (choice: { round: number; index: number }) => unknown
  onPrepareDisplay?: (now: number) => void
  onDisplay?: (frame: Frame | null, paintAt: number) => Frame | null
}
const kinds: SetupKind[] = ["character", "stage", "arcana", "mode"]

// Presentation and device IO only. The controller supplies authoritative Bend frames.
const time = (ticks: number) =>
  `${Math.floor(ticks / 3600)
    .toString()
    .padStart(2, "0")}:${Math.floor((ticks / 60) % 60)
    .toString()
    .padStart(2, "0")}`
function playerHealthLabel(frame: Frame, player: Player) {
  const remaining = reviveSeconds(frame, player)
  if (remaining !== null) return `Reviving in ${remaining}s`
  return player.hp === 0 ? "Fallen" : `${player.hp} / ${player.maxHp}`
}
const catalogs = { character: CHARACTERS, arcana: ARCANA, stage: STAGES, mode: RUN_MODES }
const movementKeys = new Set(["KeyW", "KeyA", "KeyS", "KeyD", "ArrowUp", "ArrowLeft", "ArrowDown", "ArrowRight"])
// Device IO: select the nearest of the keyboard's eight directions. Independent
// axis signs turn virtually every off-centre thumb position into a diagonal.
function touchDirection(x: number, y: number, radius: number) {
  if (Math.hypot(x, y) < radius * 0.2) return { x: 0, y: 0 }
  const diagonalThreshold = Math.SQRT2 - 1 // tan(22.5 degrees)
  return {
    x: Math.abs(x) > Math.abs(y) * diagonalThreshold ? Math.sign(x) : 0,
    y: Math.abs(y) > Math.abs(x) * diagonalThreshold ? Math.sign(y) : 0
  }
}
function offerPresentation(offer: Offer) {
  const item =
    offer.kind === 5
      ? UNIONS[offer.id]
      : offer.kind === 0 || offer.kind === 3
        ? WEAPONS[offer.id]
        : offer.kind === 1
          ? PASSIVES[offer.id]
          : offer.kind === 4
            ? { name: "Golden gift", icon: "◈", description: "Gold for this run." }
            : { name: "Restorative elixir", icon: "♥", description: "Restore health." }
  return {
    name: (offer.kind === 3 ? (item && "evolvedName" in item ? item.evolvedName : undefined) : item?.name) || "Reward",
    description:
      (offer.kind === 3
        ? item && "evolvedDescription" in item
          ? item.evolvedDescription
          : undefined
        : item?.description) || "",
    icon: item?.icon || "✦",
    detail: offer.kind === 5 ? "Union" : offer.kind === 3 ? "Evolution" : offer.kind <= 1 ? `Level ${offer.level}` : ""
  }
}
// The Bend progression core owns awards and durable receipt deduplication.
// This adapter only observes rendered equipment and supplies an IO run/player key.
class CoopRunProgress {
  profile!: Profile
  history!: ReturnType<typeof observeRun>
  savedReceipt!: string | null
  added!: string[]
  constructor(profile: Profile) {
    this.profile = profile
    this.reset()
  }
  reset() {
    this.history = observeRun({}, {})
    this.savedReceipt = null
    this.added = []
  }
  observe(frame: Frame) {
    this.history = observeRun(this.history, { weapons: frame.weapons })
    if (frame.phase !== 3 && frame.phase !== 4) return null
    if (typeof frame.runId !== "string" || !frame.runId || !Number.isInteger(frame.ownPlayerId)) return null
    const receipt = `${frame.runId}:${frame.ownPlayerId}`
    if (receipt !== this.savedReceipt) {
      this.added = recordRun(this.profile, { ...frame, ...this.history, runId: receipt })
      this.savedReceipt = receipt
    }
    return { receipt, added: this.added }
  }
}
export class CoopUI {
  document!: Document
  window!: Window
  callbacks!: CoopCallbacks
  $!: typeof element
  profile!: Profile
  progress!: CoopRunProgress
  canvas!: HTMLCanvasElement
  renderer!: Renderer
  presentation!: ObservationPresentation
  audio!: AudioEngine
  keys!: Set<string>
  touch!: { x: number; y: number }
  touchPointerId!: number | null
  lastInput!: string
  frame!: Frame | null
  displayedFrame!: Frame | null
  rewardSignature!: string
  choiceBusy!: boolean
  events!: AbortController
  entryRole!: string
  openPanel!: string | null
  pendingUnlock!: { kind: string; id: number } | null
  animate!: (now: number) => void
  previous!: number
  fps!: number
  renderFailed!: boolean
  animation!: number
  roomSetup: Pick<Setup, "stage" | "mode"> | undefined
  playerSignature!: string
  constructor(callbacks: CoopCallbacks = {}, { document = globalThis.document, window = globalThis.window } = {}) {
    this.document = document
    this.window = window
    this.callbacks = callbacks
    this.$ = (selector) => element(selector, document)
    this.profile = loadProfile()
    this.progress = new CoopRunProgress(this.profile)
    this.canvas = this.$("#coop-game")
    this.renderer = new Renderer(this.canvas)
    this.presentation = new ObservationPresentation()
    this.audio = new AudioEngine()
    this.audio.setMuted(this.profile.settings?.muted ?? false)
    this.audio.setVolume(this.profile.settings?.volume ?? 0.42)
    this.keys = new Set()
    this.touch = { x: 0, y: 0 }
    this.touchPointerId = null
    this.lastInput = ""
    this.frame = null
    this.displayedFrame = null
    this.rewardSignature = ""
    this.choiceBusy = false
    this.events = new AbortController()
    const on = <K extends keyof HTMLElementEventMap>(
      target: Pick<HTMLElement, "addEventListener">,
      type: K,
      listener: (event: HTMLElementEventMap[K]) => unknown,
      options: AddEventListenerOptions = {}
    ) => target.addEventListener(type, listener, { ...options, signal: this.events.signal })
    const join =
      new URL(window.location.href).searchParams.get("join") ??
      new URLSearchParams(window.location.hash.slice(1)).get("join")
    this.entryRole = join ? "guest" : "host"
    this.openPanel = null
    this.pendingUnlock = null
    const initial = validateSetup(this.profile, {})
    for (const kind of kinds) {
      const catalog = catalogs[kind]
      const select = this.select(kind)
      select.innerHTML = catalog
        .map(
          (item) =>
            `<option value="${item.id}" ${isUnlocked(this.profile, kind, item.id) ? "" : "disabled"}>${esc(("icon" in item ? item.icon : undefined) || (kind === "character" ? "✦" : kind === "stage" ? "☾" : "◷"))} ${esc(item.name)}${isUnlocked(this.profile, kind, item.id) ? "" : " · locked"}</option>`
        )
        .join("")
      select.value = String(initial[kind])
      on(select, "change", () => {
        this.updateSetup()
        this.callbacks.onSetupChange?.(this.setup())
      })
    }
    this.updateSetup()
    on(this.$("#coop-setup-preview"), "click", (event) => this.selectSetup(event))
    on(this.$("#coop-host"), "click", () => this.invoke(() => this.callbacks.onHost?.(this.setup())))
    on(this.$("#coop-start"), "click", () => this.invoke(() => this.callbacks.onStart?.()))
    on(this.$("#coop-invite-again"), "click", () => this.openInvitation())
    on(this.$("#coop-invite-close"), "click", () => this.closeInvitation())
    on(this.$("#coop-invitation"), "click", (event) => {
      if (event.target === this.$("#coop-invitation")) this.closeInvitation()
    })
    on(this.$("#coop-close-room"), "click", () => this.invoke(() => this.callbacks.onLeave?.()))
    on(this.$("#coop-retry"), "click", () => this.invoke(() => this.callbacks.onRetry?.()))
    on(document, "pointerdown", () => this.audio.unlock(), { once: true })
    on(document, "keydown", () => this.audio.unlock(), { once: true })
    on(this.$("#coop-copy"), "click", () => this.copyInvitation())
    on(this.$("#coop-share"), "click", async () => {
      const url = this.$("#coop-invite-link").value
      const navigator = this.window.navigator
      if (navigator.share) {
        try {
          await navigator.share({
            title: "Join my Survivors run",
            text: "Choose your survivor and join my party.",
            url
          })
          this.$("#coop-share-status").textContent = "Invitation shared. Start when your party is ready."
        } catch (error) {
          if ((error instanceof Error ? error.name : "") !== "AbortError") await this.copyInvitation()
        }
      } else await this.copyInvitation()
    })
    on(this.$("#coop-leave"), "click", () => this.invoke(() => this.callbacks.onLeave?.()))
    on(this.$("#coop-map-toggle"), "click", () => this.toggleMap())
    on(this.$("#coop-map-close"), "click", () => this.toggleMap(false))
    enableSecondaryRewardTouch(this.$("#coop-offers"), this.events.signal)
    on(this.$("#coop-offers"), "click", (event) => {
      const button = event.target instanceof Element ? event.target.closest<HTMLButtonElement>("[data-choice]") : null
      if (button && !button.disabled) this.choose(Number(button.dataset.choice))
    })
    on(window, "keydown", (event) => {
      if (event.code === "Escape" && this.pendingUnlock) {
        event.preventDefault()
        const inspected = this.pendingUnlock
        this.pendingUnlock = null
        this.updateSetup()
        this.$("#coop-setup-preview")
          .querySelector<HTMLElement>(`[data-${inspected.kind}="${inspected.id}"]`)
          ?.focus({ preventScroll: true })
        return
      }
      if (/^(INPUT|SELECT|TEXTAREA)$/.test(event.target instanceof Element ? event.target.tagName : "")) return
      if (movementKeys.has(event.code)) {
        event.preventDefault()
        this.keys.add(event.code)
        this.emitInput()
      }
      if (!event.repeat && event.code === "KeyM" && this.frame) {
        event.preventDefault()
        this.toggleMap()
      }
      if (!event.repeat && /^Digit[1-9]$/.test(event.code) && !this.$("#coop-reward").hidden)
        this.choose(Number(event.code.slice(5)) - 1)
      if (event.code === "Escape") this.toggleMap(false)
    })
    on(window, "keyup", (event) => {
      if (movementKeys.has(event.code)) {
        this.keys.delete(event.code)
        this.emitInput()
      }
    })
    on(window, "blur", () => this.clearInput())
    document.addEventListener(
      "visibilitychange",
      () => {
        if (document.hidden) this.clearInput()
      },
      { signal: this.events.signal }
    )
    const pad = this.$("#coop-touch")
    const touchMove = (event: PointerEvent) => {
      const rect = pad.getBoundingClientRect()
      this.touch = touchDirection(
        event.clientX - rect.left - rect.width / 2,
        event.clientY - rect.top - rect.height / 2,
        Math.min(rect.width, rect.height) / 2
      )
      defined(pad.querySelector<HTMLElement>(":scope > *")).style.transform =
        `translate(${this.touch.x * 18}px,${this.touch.y * 18}px)`
      this.emitInput()
    }
    on(pad, "pointerdown", (event) => {
      if (this.touchPointerId !== null) return
      this.audio.unlock()
      this.touchPointerId = event.pointerId
      pad.setPointerCapture(event.pointerId)
      pad.dataset.active = "true"
      touchMove(event)
    })
    on(pad, "pointermove", (event) => {
      if (event.pointerId === this.touchPointerId && pad.hasPointerCapture(event.pointerId)) touchMove(event)
    })
    const touchEnd = (event: PointerEvent) => {
      if (event.pointerId === this.touchPointerId) this.clearTouchInput()
    }
    on(pad, "pointerup", touchEnd)
    on(pad, "pointercancel", touchEnd)
    on(pad, "lostpointercapture", touchEnd)
    this.animate = () => {
      try {
        const now = window.performance.now()
        const delta = Math.max(0, Math.min(100, now - (this.previous || now)))
        this.previous = now
        if (this.frame && !this.renderFailed) {
          const display = this.displayFrame(now) || this.frame
          this.renderer.draw(display, delta / 1000, this.profile.settings || {})
          this.audio.impacts(display)
          this.displayedFrame = display
          if (!this.$("#coop-map-panel").hidden) this.renderer.drawMap(this.$("#coop-map"), display)
          if (delta > 0) this.fps = this.fps === undefined ? 1000 / delta : this.fps * 0.95 + (1000 / delta) * 0.05
          this.$("#coop-fps").textContent = `${Math.round(this.fps || 0)} FPS`
        }
      } catch (error) {
        // Preserve the fatal diagnostic; drawing resumes only after a new session reset.
        this.renderFailed = true
        throw error
      } finally {
        this.animation = window.requestAnimationFrame(this.animate)
      }
    }
    this.animation = window.requestAnimationFrame(this.animate)
  }
  displayFrame(now: number) {
    this.callbacks.onPrepareDisplay?.(now)
    const paintAt = this.window.performance.now()
    const interpolated = this.presentation.sample(paintAt) || this.frame
    return this.callbacks.onDisplay?.(interpolated, paintAt) || interpolated
  }
  select(kind: string): HTMLSelectElement {
    return defined(this.document.querySelector<HTMLSelectElement>(`#coop-${kind}`))
  }
  setup() {
    const selected = Object.fromEntries(kinds.map((kind) => [kind, Number(this.select(kind).value)]))
    return {
      ...validateSetup(this.profile, selected),
      meta: metaCode(this.profile),
      allowedWeapons: allowedWeapons(this.profile)
    }
  }
  updateSetup() {
    const setup = this.setup()
    for (const kind of kinds) this.select(kind).value = String(setup[kind])
    this.$("#coop-setup-preview").innerHTML = renderCoopSetup(
      { profile: this.profile, ...setup, openPanel: this.openPanel, pendingUnlock: this.pendingUnlock },
      this.entryRole === "guest",
      this.roomSetup
    )
    this.$("#coop-wallet").textContent = `◈ ${this.profile.gold.toLocaleString("en-US")} · legacy gold`
    this.$("#coop-setup-detail").textContent =
      `${CHARACTERS[setup.character]?.description || ""} ${ARCANA[setup.arcana]?.description || ""}`
  }
  selectSetup(event: MouseEvent) {
    const button = event.target instanceof Element ? event.target.closest("button") : null
    if (!button || button.disabled || this.$("#coop-setup-fields").disabled) return
    const before = this.setup()
    if (button.dataset.menuPanel) {
      this.openPanel = this.openPanel === button.dataset.menuPanel ? null : button.dataset.menuPanel
      this.pendingUnlock = null
    } else if (button.hasAttribute("data-close-unlock")) {
      const inspected = this.pendingUnlock
      this.pendingUnlock = null
      this.updateSetup()
      if (inspected)
        this.$("#coop-setup-preview")
          .querySelector<HTMLElement>(`[data-${inspected.kind}="${inspected.id}"]`)
          ?.focus({ preventScroll: true })
      return
    } else if (button.dataset.buyKind) {
      if (unlock(this.profile, button.dataset.buyKind, Number(button.dataset.buyId))) {
        const kind = button.dataset.buyKind,
          id = Number(button.dataset.buyId)
        defined(this.select(kind).querySelector<HTMLOptionElement>(`option[value="${id}"]`)).disabled = false
        this.select(kind).value = String(id)
        this.pendingUnlock = null
        this.openPanel = null
      }
    } else
      for (const kind of kinds) {
        if (button.dataset[kind] === undefined) continue
        const id = Number(button.dataset[kind])
        if (isUnlocked(this.profile, kind, id)) {
          this.select(kind).value = String(id)
          this.openPanel = null
          this.pendingUnlock = null
        } else
          this.pendingUnlock = this.pendingUnlock?.kind === kind && this.pendingUnlock.id === id ? null : { kind, id }
        break
      }
    this.updateSetup()
    const after = this.setup()
    if (
      before.stage !== after.stage ||
      before.mode !== after.mode ||
      before.character !== after.character ||
      before.arcana !== after.arcana ||
      before.meta !== after.meta ||
      before.allowedWeapons !== after.allowedWeapons
    )
      this.callbacks.onSetupChange?.(after)
    this.$("#coop-setup-preview").querySelector<HTMLElement>("[data-unlock-details]")?.focus({ preventScroll: true })
  }
  openInvitation() {
    const dialog = this.$("#coop-invitation")
    if (!dialog.open) dialog.showModal()
  }
  closeInvitation() {
    this.$("#coop-invitation").close()
  }
  async copyInvitation() {
    const input = this.$("#coop-invite-link")
    try {
      await this.window.navigator.clipboard.writeText(input.value)
      this.$("#coop-copy").textContent = "Copied"
      this.$("#coop-share-status").textContent = "Link copied. Paste it into your chat and send it to your friend."
    } catch {
      input.focus()
      input.select()
      this.$("#coop-share-status").textContent = "Copy the selected link, then send it to your friend."
    }
  }
  input() {
    return {
      x: Math.sign(
        Number(this.keys.has("KeyD") || this.keys.has("ArrowRight")) -
          Number(this.keys.has("KeyA") || this.keys.has("ArrowLeft")) +
          this.touch.x
      ),
      y: Math.sign(
        Number(this.keys.has("KeyS") || this.keys.has("ArrowDown")) -
          Number(this.keys.has("KeyW") || this.keys.has("ArrowUp")) +
          this.touch.y
      )
    }
  }
  emitInput() {
    const input = this.input(),
      signature = `${input.x},${input.y}`
    if (signature !== this.lastInput) {
      this.lastInput = signature
      this.callbacks.onInput?.(input)
    }
  }
  clearTouchInput() {
    const pad = this.$("#coop-touch"),
      pointer = this.touchPointerId
    // Clear ownership before releasing: lostpointercapture must not clear a
    // subsequent gesture, and a second finger never owns the current gesture.
    this.touchPointerId = null
    if (pointer !== null && pad.hasPointerCapture(pointer)) pad.releasePointerCapture(pointer)
    pad.dataset.active = "false"
    defined(pad.querySelector<HTMLElement>(":scope > *")).style.transform = ""
    this.touch = { x: 0, y: 0 }
    this.emitInput()
  }
  clearInput() {
    this.keys.clear()
    this.clearTouchInput()
  }
  async invoke(action: () => unknown) {
    this.audio.unlock()
    try {
      return await action()
    } catch (error) {
      this.status(errorMessage(error), { error: true })
    }
  }
  status(text: string, { busy = false, error = false } = {}) {
    this.$("#coop-status").textContent = text
    if (this.entryRole === "guest" && !this.frame) {
      this.$("#coop-join-title").textContent = error ? "Could not connect" : busy ? "Joining the party" : "Your party"
      this.$("#coop-join-detail").textContent = text || "Waiting for the host to confirm your place."
    }
    this.$("#coop-status").dataset.error = String(error)
    this.$("#coop-play-status").textContent = text
    this.$("#coop-retry").hidden = !error
    if (error) this.$("#coop-retry").textContent = "Retry connection"
    for (const selector of ["#coop-host", "#coop-retry"])
      defined(this.document.querySelector<HTMLButtonElement>(selector)).disabled = busy
    this.$("#coop-lobby").setAttribute("aria-busy", String(busy))
    if (error && !this.frame && !this.$("#coop-invite-link").value) {
      this.$("#coop-setup-fields").disabled = false
      this.$("#coop-host-actions").hidden = false
    }
  }
  diagnostic(report: unknown) {
    for (const selector of ["#coop-status", "#coop-play-status"]) {
      const status = this.$(selector)
      let panel = status.nextElementSibling instanceof HTMLElement ? status.nextElementSibling : null
      if (!panel?.classList.contains("coop-diagnostic")) {
        panel = this.document.createElement("section")
        panel.className = "coop-diagnostic"
        const heading = this.document.createElement("strong")
        heading.textContent = "Error details"
        const output = this.document.createElement("pre")
        const copy = this.document.createElement("button")
        copy.type = "button"
        copy.textContent = "Copy error"
        copy.addEventListener("click", () => {
          void (async () => {
            try {
              await this.window.navigator.clipboard.writeText(output.textContent)
              copy.textContent = "Copied"
            } catch {
              copy.textContent = "Select and copy the details below"
            }
          })()
        })
        panel.append(heading, copy, output)
        status.after(panel)
      }
      panel.hidden = !report
      defined(panel.querySelector("pre")).textContent = report ? JSON.stringify(report, null, 2) : ""
      defined(panel.querySelector("button")).textContent = "Copy error"
    }
  }
  invitation(ticket: string) {
    let url
    try {
      url = new URL(ticket)
    } catch {
      url = new URL(this.window.location.href)
      url.hash = ""
      url.searchParams.set("join", ticket)
    }
    this.$("#coop-invite-link").value = url.href
    this.$("#coop-host-actions").hidden = true
    this.$("#coop-room-ready").hidden = false
    this.$("#coop-room-title").textContent = "Your party"
    this.$("#coop-host-help").textContent = "Invite up to three friends. You decide when to start."
    this.openInvitation()
    this.status("Room open. Invite friends, then start with two to four players.")
  }
  lobby(lobby: CoopLobby) {
    if (!this.roomSetup || this.roomSetup.stage !== lobby.room.stage || this.roomSetup.mode !== lobby.room.mode) {
      this.roomSetup = lobby.room
      this.updateSetup()
    }
    this.$("#coop-setup-fields").disabled = lobby.started
    const roster = this.$("#coop-party-roster")
    roster.hidden = false
    roster.innerHTML = Array.from({ length: 4 }, (_, player) => {
      const member = lobby.players.find((row) => row.player === player)
      const survivor = member ? CHARACTERS.find((character) => character.id === member.character) : undefined
      const label = member
        ? `${player === 0 ? "Host" : `Player ${player + 1}`} · ${survivor?.name ?? "Survivor"}`
        : "Open seat"
      const status = !member
        ? "Invite a friend"
        : !member.connected
          ? "Disconnected"
          : member.ready
            ? "Ready"
            : "Connecting…"
      return `<div class="coop-room-member" data-player="${player}" data-ready="${member?.ready ?? false}"><span class="coop-member-mark${member ? "" : " empty"}" aria-hidden="true">${member ? player + 1 : "+"}</span><div><strong>${esc(label)}</strong><small>${esc(status)}</small></div></div>`
    }).join("")
    this.$("#coop-party-count").textContent = `${lobby.players.length} / 4 players`
    defined(this.document.querySelector<HTMLButtonElement>("#coop-start")).disabled = !lobby.canStart || lobby.started
    if (!lobby.started)
      this.status(lobby.canStart ? "Party ready. The host can start the run." : "Waiting for the party to be ready.")
    if (this.entryRole === "guest") {
      this.$("#coop-retry").hidden = true
      this.$("#coop-setup-fields").disabled = lobby.started
      this.$("#coop-join-title").textContent = "You’re in the party"
      this.$("#coop-join-detail").textContent = lobby.started
        ? "The run is starting."
        : "Waiting for the host to start."
    }
  }
  role(role: "host" | "guest") {
    this.entryRole = role
    this.document.documentElement.dataset.entry = role
    this.openPanel = null
    this.pendingUnlock = null
    this.updateSetup()
    this.$("#coop-setup-fields").disabled = true
  }
  setChoicePending(pending: boolean) {
    this.choiceBusy = pending
    for (const button of this.$("#coop-offers").querySelectorAll("button")) button.disabled = pending
  }
  choose(index: number) {
    const button = this.document.querySelector<HTMLButtonElement>(`#coop-offers [data-choice="${index}"]`)
    if (!button || button.disabled || this.choiceBusy) return
    this.setChoicePending(true)
    this.audio.event("choose")
    void this.invoke(() =>
      this.callbacks.onChoice?.({ round: this.frame?.roundId ?? this.frame?.rewardRound?.id ?? 0, index })
    )
  }
  toggleMap(open = this.$("#coop-map-panel").hidden) {
    this.$("#coop-map-panel").hidden = !open
    this.$("#coop-map-toggle").setAttribute("aria-expanded", String(open))
    if (open && this.frame) this.renderer.drawMap(this.$("#coop-map"), this.displayedFrame || this.frame)
    // This is a local overlay; it never requests a pause from the controller.
  }
  present(frame: Frame) {
    const previous = this.frame
    // A disconnect arriving after a completed receipt must not replace its result screen.
    if (previous && previous.runId === frame.runId && [3, 4].includes(previous.phase) && frame.phase === 5) return
    this.frame = frame
    this.audio.observe(frame)
    if ((frame.ownPlayerId ?? 0) > 0) this.$("#coop-join-title").textContent = "Your place is ready!"
    this.presentation.push(frame, this.window.performance.now())
    const saved = this.progress.observe(frame)
    this.closeInvitation()
    this.$("#menu").hidden = true
    this.$("#coop-lobby").hidden = true
    this.$("#coop-play").hidden = false
    this.$("#coop-clock").textContent = time(frame.tick || 0)
    this.$("#coop-level").textContent = `Level ${frame.level ?? 1}`
    this.$("#coop-gold").textContent = `◈ ${frame.gold ?? 0}`
    this.$("#coop-xp").style.width = `${Math.max(0, Math.min(100, ((frame.xp || 0) / (frame.xpNeed || 1)) * 100))}%`
    const players = frame.players || [{ id: frame.ownPlayerId ?? 0, ...frame }]
    const playerSignature = JSON.stringify([
      frame.ownPlayerId,
      players.map((player) => [player.id, player.hp, player.maxHp, reviveSeconds(frame, player)])
    ])
    if (playerSignature !== this.playerSignature) {
      this.playerSignature = playerSignature
      this.$("#coop-players").innerHTML = players
        .map(
          (player) =>
            `<div class="player-status" data-own="${player.id === (frame.ownPlayerId ?? 0)}"><span>${player.id === (frame.ownPlayerId ?? 0) ? "You" : `P${player.id + 1}`}</span><span class="health-track"><i style="width:${Math.max(0, Math.min(100, ((player.hp || 0) / (player.maxHp || 1)) * 100))}%"></i></span><small>${playerHealthLabel(frame, player)}</small></div>`
        )
        .join("")
    }
    const offers = frame.offers || []
    const signature = JSON.stringify([frame.phase, frame.roundId, frame.rewardRound, frame.choicePending, offers])
    if (signature !== this.rewardSignature) {
      this.rewardSignature = signature
      this.setChoicePending(false)
      const pausedForReward = frame.phase === 1 || frame.phase === 2
      const ended = frame.phase === 3 || frame.phase === 4
      const aborted = frame.phase === 5
      this.$("#coop-reward").hidden = !pausedForReward && !ended && !aborted
      if (pausedForReward) {
        this.clearInput()
        this.$("#coop-reward-kind").textContent = frame.phase === 1 ? `Level ${frame.level}` : "Chest"
        this.$("#coop-reward-title").textContent =
          offers.length && frame.choicePending !== false ? "Choose your reward" : "Waiting for your teammate"
        this.$("#coop-reward-detail").textContent = "The world is paused until all required choices are complete."
        this.$("#coop-offers").innerHTML =
          frame.choicePending === false
            ? ""
            : offers
                .map((offer, index) => {
                  const item = offerPresentation(offer)
                  return `<button class="reward-offer banner-panel" data-choice="${index}"><span class="banner-heading"><span class="offer-icon" aria-hidden="true">${esc(item.icon)}</span><strong>${esc(item.name)}</strong></span><small>${esc(item.description)}</small><small>${esc(item.detail)} · ${index + 1}</small></button>`
                })
                .join("")
        this.document.querySelector<HTMLButtonElement>("#coop-offers button")?.focus({ preventScroll: true })
      } else if (ended || aborted) {
        this.clearInput()
        this.$("#coop-reward-kind").textContent = aborted ? "Connection closed" : "Run complete"
        this.$("#coop-reward-title").textContent = aborted
          ? "Session ended"
          : frame.phase === 4
            ? "Dawn breaks"
            : "The night is over"
        this.$("#coop-reward-detail").textContent = aborted
          ? "This run ended before completion. Return to the lobby to connect again."
          : `${time(frame.tick || 0)} · Level ${frame.level ?? 1} · ${frame.kills ?? 0} defeated · ${frame.gold ?? 0} gold`
        const awards = saved?.added.map((id) => ACHIEVEMENTS.find((item) => item.id === id)?.name || id) || []
        const saveNote = saved
          ? `Saved to this browser.${awards.length ? ` New achievements: ${awards.join(", ")}.` : ""}`
          : "Run receipt unavailable; progress has not been saved."
        this.$("#coop-offers").innerHTML =
          `${aborted ? "" : `<p class="muted">${esc(saveNote)}</p>`}<button id="coop-finish" class="moon-button">Return to lobby</button>`
        this.$("#coop-finish").addEventListener(
          "click",
          () => {
            void this.invoke(() => this.callbacks.onLeave?.())
          },
          { once: true, signal: this.events.signal }
        )
        this.$("#coop-finish").focus({ preventScroll: true })
        if (aborted) this.audio.stop(true)
      }
    }
    this.audio.update(frame, frame.phase === 0)
    if (!previous) this.canvas.focus({ preventScroll: true })
  }
  reset() {
    this.clearInput()
    this.frame = null
    this.displayedFrame = null
    this.rewardSignature = ""
    this.choiceBusy = false
    this.playerSignature = ""
    this.roomSetup = undefined
    this.renderFailed = false
    this.progress.reset()
    this.presentation.reset()
    this.renderer.reset()
    this.audio.stop(true)
    this.toggleMap(false)
    this.$("#coop-lobby").hidden = false
    this.$("#coop-play").hidden = true
    this.closeInvitation()
    this.$("#menu").hidden = false
    this.$("#coop-host-actions").hidden = false
    this.$("#coop-room-ready").hidden = true
    this.$("#coop-party-roster").hidden = true
    this.$("#coop-party-roster").innerHTML = ""
    this.$("#coop-party-count").textContent = ""
    defined(this.document.querySelector<HTMLButtonElement>("#coop-start")).disabled = true
    this.$("#coop-retry").hidden = true
    this.$("#coop-invite-link").value = ""
    this.$("#coop-room-title").textContent = "Host a run"
    this.$("#coop-host-help").textContent = "You choose the stage. Each friend chooses their survivor."
    this.$("#coop-copy").textContent = "Copy invitation link"
    this.$("#coop-share-status").textContent =
      "Invite up to three friends, then start when everyone is ready. Keep this page open."
    this.$("#coop-setup-fields").disabled = false
    this.openPanel = null
    this.pendingUnlock = null
    this.updateSetup()
    this.status(
      this.entryRole === "guest"
        ? "Choose your survivor, then select Join party to connect."
        : "Choose your survivor to begin."
    )
    if (this.entryRole === "guest") {
      this.$("#coop-retry").textContent = "Join party"
      this.$("#coop-retry").hidden = false
    }
  }
  dispose() {
    this.clearInput()
    this.events.abort()
    this.window.cancelAnimationFrame(this.animation)
    this.renderer.resizeObserver?.disconnect()
    this.window.removeEventListener("resize", this.renderer.handleResize)
    this.audio.stop(true)
  }
}
