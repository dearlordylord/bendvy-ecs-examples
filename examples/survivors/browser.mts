import type { BrowserStream } from "./browser-stream.mts"
import { gameFrame } from "./observations.mts"
import { escapeHtml as esc, displayText, defined, errorMessage, at, text } from "./host-values.mts"
import { element, enableSecondaryRewardTouch } from "./dom.mts"
import type { AudioEngine } from "./audio.mts"
import type { Renderer } from "./renderer.mts"
import { type Frame } from "./frame.mts"
import { MENU_TABS, renderMenuContent } from "./menu-content.mts"
import { WEAPONS, PASSIVES, CHARACTERS, STAGES, ACHIEVEMENTS, UNIONS } from "./content.mts"
import { renderExpeditionAction } from "./expedition-menu.mts"
import {
  loadProfile,
  isolatedStreamProfile,
  saveProfile,
  buyUpgrade,
  metaCode,
  recordRun,
  isUnlocked,
  unlock,
  requirementsMet,
  allowedWeapons,
  validateSetup,
  observeRun
} from "./progression.mts"
interface DeferredAudio {
  engine: AudioEngine | null
  context: AudioContext | null
  master: GainNode | null
  unlock(): void
  stop: AudioEngine["stop"]
  event: AudioEngine["event"]
  update: AudioEngine["update"]
  observe: AudioEngine["observe"]
  setMuted: AudioEngine["setMuted"]
  setVolume: AudioEngine["setVolume"]
}

const $ = element,
  canvas = $("#game"),
  audio: DeferredAudio = {
    engine: null,
    context: null,
    master: null,
    unlock() {
      if (this.engine) return this.engine.unlock()
      // Keep the browser gesture even when the simulation is still downloading.
      try {
        const Context = globalThis.AudioContext || globalThis.webkitAudioContext
        if (!this.context && Context) {
          this.context = new Context()
          this.master = this.context.createGain()
          this.master.gain.value = 0
          this.master.connect(this.context.destination)
        }
        if (this.context?.state === "suspended") this.context.resume().catch(() => {})
      } catch {}
    },
    stop(...args: Parameters<AudioEngine["stop"]>) {
      this.engine?.stop(...args)
    },
    event(...args: Parameters<AudioEngine["event"]>) {
      this.engine?.event(...args)
    },
    update(...args: Parameters<AudioEngine["update"]>) {
      this.engine?.update(...args)
    },
    observe(...args: Parameters<AudioEngine["observe"]>) {
      this.engine?.observe(...args)
    },
    setMuted(...args: Parameters<AudioEngine["setMuted"]>) {
      this.engine?.setMuted(...args)
    },
    setVolume(...args: Parameters<AudioEngine["setVolume"]>) {
      this.engine?.setVolume(...args)
    }
  }
let Game: BendABI.Game.API,
  renderer: Renderer,
  runtimeTask: Promise<void> | null,
  starting = false
function prepareRuntime() {
  if (!runtimeTask)
    runtimeTask = Promise.all([import("./dist/game.mjs"), import("./renderer.mts"), import("./audio.mts")])
      .then(([game, graphics, sound]) => {
        Game = game.default
        renderer = new graphics.Renderer(canvas)
        audio.engine = new sound.AudioEngine()
        if (audio.context) {
          audio.engine.context = audio.context
          audio.engine.master = audio.master
          audio.engine.nextNote = audio.context.currentTime + 0.1
        }
        settings()
      })
      .catch((error) => {
        runtimeTask = null
        throw error
      })
  return runtimeTask
}
const streamMode = new URL(location.href).searchParams.get("stream") === "1"
const profile = streamMode
  ? isolatedStreamProfile(loadProfile(), new URL(location.href).searchParams.get("persist") === "1")
  : loadProfile()
let stream: BrowserStream | undefined
let state: BendABI.Game.State | undefined,
  frame: Frame,
  running = false,
  paused = false,
  upgradeOpen = false,
  accumulator = 0,
  previous = 0,
  tab: string = MENU_TABS.includes(new URL(location.href).searchParams.get("tab") ?? "")
    ? (new URL(location.href).searchParams.get("tab") ?? "expedition")
    : "expedition",
  collectionTab = "weapons",
  character = 0,
  stage = 0,
  arcana = 0,
  mode = 0,
  shownPhase = -1,
  toastTimer: ReturnType<typeof setTimeout> | undefined,
  runId = ""
let openPanel: string | null = null,
  pendingUnlock: { kind: string; id: number } | null = null
let loadoutSignature = ""
let runHistory = observeRun({}, {})
const runResult = () => ({ ...frame, runId, ...runHistory })
const keys = new Set(),
  touch = { x: 0, y: 0 },
  STEP = 1000 / 60
const time = (t: number) =>
  `${Math.floor(t / 60)
    .toString()
    .padStart(2, "0")}:${Math.floor(t % 60)
    .toString()
    .padStart(2, "0")}`
function toast(message: string) {
  $("#toast").textContent = message
  $("#toast").classList.add("visible")
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 3000)
}
function settings() {
  audio.setMuted(profile.settings.muted)
  audio.setVolume(profile.settings.volume)
}
function card(
  item: { color?: string; icon?: string; name?: string; description?: string },
  attributes = "",
  extra = "",
  selected = false
) {
  const pressed = /data-(stage|arcana|mode)=/.test(attributes) ? `aria-pressed="${selected}"` : ""
  return `<button class="card banner-panel ${selected ? "selected" : ""}" ${attributes} ${pressed}><div class="banner-heading"><span class="icon" style="color:${item.color || "var(--gold)"}">${item.icon || "✦"}</span><h3>${esc(item?.name)}</h3></div><p>${esc(item?.description)}</p>${extra}</button>`
}
function menu() {
  const returningToMenu = $("#menu").hidden
  const activeElement = document.activeElement
  const previousFocus =
    activeElement instanceof HTMLElement && $("#menu").contains(activeElement)
      ? { id: activeElement.id, data: Object.fromEntries(Object.entries(activeElement.dataset)) }
      : null
  running = false
  paused = false
  keys.clear()
  touch.x = touch.y = 0
  audio.stop(true)
  $("#menu").hidden = false
  $("#overlay").hidden = true
  $("#hud").hidden = true
  $("#joystick").hidden = true
  $("#wallet").textContent = `◈ ${profile.gold.toLocaleString("en-US")} · legacy gold`
  document
    .querySelectorAll<HTMLButtonElement>("#tabs button")
    .forEach((b) => b.classList.toggle("active", b.dataset.tab === tab))
  document.documentElement.dataset.menuTab = tab
  const html = renderMenuContent(
    tab,
    { profile, character, stage, arcana, mode, openPanel, pendingUnlock },
    collectionTab
  )
  $("#menuContent").innerHTML = html
  // The dock is a sibling of the scroller, so it cannot cover picker content.
  $("#menuDock").innerHTML = tab === "expedition" ? renderExpeditionAction({ character, stage }) : ""
  $("#menuDock").hidden = tab !== "expedition"
  if (previousFocus) {
    const match = [...$("#menu").querySelectorAll<HTMLElement>("button,input")].find((element) =>
      previousFocus.id
        ? element.id === previousFocus.id
        : Object.keys(previousFocus.data).length &&
          Object.entries(previousFocus.data).every(([key, value]) => element.dataset[key] === value)
    )
    match?.focus({ preventScroll: true })
  } else if (returningToMenu) {
    $("#tabs .active")?.focus({ preventScroll: true })
  }
}
type NoArgTransition = "skip" | "reroll"
function consume(method: NoArgTransition): void
function consume(method: "choose" | "banish" | "set_mode" | "configure_unlocks", value: number): void
function consume(method: "configure" | "advance_live", a: number, b: number): void
function consume(
  method: NoArgTransition | "choose" | "banish" | "set_mode" | "configure_unlocks" | "configure" | "advance_live",
  a?: number,
  b?: number
) {
  const owner = defined(state)
  state = undefined
  switch (method) {
    case "skip":
      accept(Game.skip(owner))
      break
    case "reroll":
      accept(Game.reroll(owner))
      break
    case "choose":
      accept(Game.choose(owner, defined(a)))
      break
    case "banish":
      accept(Game.banish(owner, defined(a)))
      break
    case "set_mode":
      accept(Game.set_mode(owner, defined(a)))
      break
    case "configure_unlocks":
      accept(Game.configure_unlocks(owner, defined(a)))
      break
    case "configure":
      accept(Game.configure(owner, defined(a), defined(b)))
      break
    case "advance_live":
      accept(Game.advance_live(owner, defined(a), defined(b)))
      break
  }
  if (["choose", "skip", "banish"].includes(method) && [1, 2].includes(frame.phase)) upgradeOpen = true
}
function accept(packet: BendABI.Game.Packet | { $: "Failed"; error: string }) {
  if (packet.$ === "Failed") throw Error(packet.error)
  if (packet.$ !== "Packet") throw Error("Invalid simulation response")
  const observed = Game.observe(packet.state)
  state = observed.state
  stream?.observed(state)
  const old = frame
  frame = gameFrame(observed.observation)
  if (old?.phase === 0 && [1, 2].includes(frame.phase)) upgradeOpen = true
  runHistory = observeRun(runHistory, { weapons: frame.weapons })
  frame.stage ??= stage
  if (running) audio.observe({ ...frame, runId })
  if (frame.phase !== shownPhase) {
    shownPhase = frame.phase
    phase()
  }
}
async function start(streamSeed?: number) {
  if (starting) return
  starting = true
  const buttons = [...document.querySelectorAll<HTMLButtonElement>("#start,#start-top,#restart")]
  buttons.forEach((button) => {
    button.disabled = true
    button.setAttribute("aria-busy", "true")
  })
  const status = $("#engineStatus")
  status.textContent = "Preparing game…"
  try {
    await prepareRuntime()
  } catch (error) {
    status.textContent = "Could not load the game. Check your connection and reload."
    console.error(error)
    if (streamSeed !== undefined) throw error
    return
  } finally {
    starting = false
    buttons.forEach((button) => {
      button.disabled = false
      button.removeAttribute("aria-busy")
    })
  }
  if (streamSeed !== undefined && !stream?.runningSession) return
  status.textContent = ""
  ;({ character, stage, arcana, mode } = validateSetup(profile, { character, stage, arcana, mode }))
  upgradeOpen = false
  banishing = false
  runId = crypto.randomUUID?.() || `${Date.now()}-${Math.random()}`
  audio.unlock()
  audio.stop(true)
  settings()
  renderer.reset()
  runHistory = observeRun({}, {})
  shownPhase = -1
  running = true
  paused = false
  accumulator = 0
  previous = 0
  $("#menu").hidden = true
  $("#hud").hidden = false
  $("#joystick").hidden = !matchMedia("(pointer:coarse)").matches
  accept(
    streamSeed === undefined
      ? Game.start(character, metaCode(profile))
      : Game.start_seed(character, metaCode(profile), streamSeed)
  )
  consume("configure", stage, arcana)
  consume("set_mode", mode)
  consume("configure_unlocks", allowedWeapons(profile))
  canvas.focus()
}
function focusDialog() {
  const dialog = $("#dialog")
  ;(dialog.querySelector<HTMLElement>("button:not(:disabled),input:not(:disabled),[tabindex='0']") || dialog).focus({
    preventScroll: true
  })
}
function phase() {
  if (!running) return
  banishing = false
  if (!streamMode) paused = false
  if (![1, 2].includes(frame.phase)) upgradeOpen = false
  if (frame.phase === 0 || ([1, 2].includes(frame.phase) && !upgradeOpen)) {
    const wasOpen = !$("#overlay").hidden
    $("#overlay").hidden = true
    if (wasOpen) canvas.focus({ preventScroll: true })
    return
  }
  keys.clear()
  touch.x = touch.y = 0
  $("#overlay").hidden = false
  const d = $("#dialog")
  if (frame.phase === 1 || frame.phase === 2) {
    audio.stop()
    const offers = frame.offers || []
    d.innerHTML = `<div class="banner-heading"><div class="eyebrow">${frame.phase === 1 ? `LEVEL ${frame.level}` : "TREASURE OF THE NIGHT"}</div><h2 id="dialog-title">${frame.phase === 1 ? "Power awakens" : "A fallen lord’s gift"}</h2></div><p>${frame.phase === 1 ? "Choose an ability for the next wave." : "Choose your reward. A matching weapon may evolve."}</p><div class="grid choices">${offers
      .map((o, index) => {
        const isW = o.kind === 0 || o.kind === 3,
          item =
            o.kind === 5
              ? UNIONS[o.id]
              : isW
                ? WEAPONS[o.id]
                : o.kind === 1
                  ? PASSIVES[o.id]
                  : o.kind === 4
                    ? { name: "Golden gift", icon: "◈", description: "Gain gold for this run." }
                    : { name: "Restorative elixir", icon: "♥", description: "Restore health." }
        const chosen = defined(item)
        return card(
          {
            ...item,
            name: text(o.kind === 3 && "evolvedName" in chosen ? chosen.evolvedName : chosen.name),
            description: text(
              o.kind === 3 && "evolvedDescription" in chosen ? chosen.evolvedDescription : chosen.description
            )
          },
          `data-choice="${index}"`,
          `<small>${o.kind === 5 ? "UNION" : o.kind === 3 ? "EVOLUTION" : o.kind === 2 ? "Healing" : o.kind === 4 ? "Gold" : `Level ${o.level}`} · key ${index + 1}</small>`
        )
      })
      .join(
        ""
      )}</div>${frame.phase === 1 ? `<div class="dialog-actions"><button data-run="reroll" ${frame.rerolls === 0 ? "disabled" : ""}>↻ Reroll${frame.rerolls !== undefined ? ` (${frame.rerolls})` : ""}</button><button id="banish">Banish an offer…</button><button data-run="skip">Skip</button></div>` : ""}`
  } else if (frame.phase === 3 || frame.phase === 4) {
    const awards = recordRun(profile, runResult())
    saveProfile(profile)
    d.innerHTML = `<div class="banner-heading"><div class="eyebrow">${at(STAGES, stage).name.toUpperCase()}</div><h2 id="dialog-title">${frame.phase === 4 ? "The dawn is yours" : "The night will remember"}</h2></div><p>${frame.phase === 4 ? "The horde has fallen. Your legacy grows stronger." : "Every shard of power brings the next dawn closer."}</p><div class="summary"><div><strong>${time(frame.tick / 60)}</strong><span>TIME</span></div><div><strong>${frame.kills}</strong><span>DEFEATED</span></div><div><strong>${frame.level}</strong><span>LEVEL</span></div><div><strong>+${frame.gold} ◈</strong><span>LEGACY</span></div></div>${awards.length ? `<p>New achievements: ${awards.map((id) => ACHIEVEMENTS.find((a) => a.id === id)?.name || id).join(", ")}</p>` : ""}<div class="dialog-actions"><button class="primary" id="restart">Another night</button><button id="return">Return to menu</button></div>`
  }
  focusDialog()
}
function openUpgrade() {
  if (!running || ![1, 2].includes(frame?.phase)) return
  upgradeOpen = true
  accumulator = 0
  phase()
}
function pause(value?: boolean) {
  if (streamMode) {
    stream?.pause(value ?? !stream.paused)
    return
  }
  if (upgradeOpen) {
    if (value === true) return
    upgradeOpen = false
    phase()
    return
  }
  if (!running || ![0, 1, 2].includes(frame?.phase)) return
  paused = value ?? !paused
  keys.clear()
  touch.x = touch.y = 0
  accumulator = 0
  if (paused) {
    audio.stop()
    $("#overlay").hidden = false
    $("#dialog").innerHTML =
      '<div class="banner-heading"><div class="eyebrow">THE WORLD STANDS STILL</div><h2 id="dialog-title">Arena map</h2></div><p>The world is paused · M / Esc to return</p><canvas id="worldmap" class="world-map" width="360" height="360" role="img"></canvas><p class="map-legend"><span>● You</span><span>□ View</span><span class="map-chest">■ Chest</span><span class="map-relic">◆ Stage relic</span></p><p class="map-note">The whole arena · Enemies and XP are not shown</p><div class="dialog-actions"><button class="primary" id="resume">Resume</button><button id="abandon">End run</button></div><p>Keep moving with WASD / arrow keys. Walk over experience shards to collect XP; shards stay on the ground.<br>Collect chests manually; press E to choose a ready reward.<br>Carry up to 6 weapons and 6 relics.</p>'
    renderer.drawMap($("#worldmap"), frame)
    focusDialog()
  } else {
    $("#overlay").hidden = true
    canvas.focus()
  }
}
function hud() {
  if (!frame) return
  canvas.dataset.playerX = String(frame.px)
  canvas.dataset.playerY = String(frame.py)
  canvas.dataset.tick = String(frame.tick)
  $("#clock").textContent = time(frame.tick / 60)
  $("#gold").textContent = `◈ ${frame.gold}`
  $("#level").textContent = [1, 2].includes(frame.phase)
    ? `LEVEL ${frame.level} · ${frame.phase === 2 ? "TREASURE" : "UPGRADE"} READY [E]`
    : `LEVEL ${frame.level}`
  $("#level").style.cursor = [1, 2].includes(frame.phase) ? "pointer" : ""
  $("#level").onclick = openUpgrade
  $("#level").setAttribute("role", [1, 2].includes(frame.phase) ? "button" : "status")
  $("#level").tabIndex = [1, 2].includes(frame.phase) ? 0 : -1
  $("#level").onkeydown = (event) => {
    if (event.code === "Enter" || event.code === "Space") {
      event.preventDefault()
      event.stopPropagation()
      openUpgrade()
    }
  }
  $("#xpFill").style.width = `${Math.min(100, (frame.xp / Math.max(1, frame.xpNeed)) * 100)}%`
  $("#hpFill").style.width = `${Math.max(0, (frame.hp / Math.max(1, frame.maxHp)) * 100)}%`
  $("#healthText").textContent = `♥ ${frame.hp} / ${frame.maxHp}`
  $("#runStats").textContent = `☠ ${frame.kills}`
  const signature = JSON.stringify([frame.weapons, frame.passives])
  if (signature === loadoutSignature) return
  loadoutSignature = signature
  const slots = [
    ...(frame.weapons || []).flatMap((n, i) => (n ? [{ ...WEAPONS[i], ...(n >= 10 ? UNIONS[n - 10] : {}), n }] : [])),
    ...(frame.passives || []).flatMap((n, i) => (n ? [{ ...PASSIVES[i], n }] : []))
  ]
  $("#loadout").innerHTML = slots
    .map(
      (w) =>
        `<span class="slot" title="${esc(w.n >= 10 ? w.name : w.n > 8 ? ("evolvedName" in w ? w.evolvedName : undefined) : w.name)}" style="color:${displayText(("color" in w ? w.color : undefined) || "#d9d0b7")}">${w.icon}<small>${w.n > 8 ? "✦" : w.n}</small></span>`
    )
    .join("")
}
function fail(error: unknown) {
  paused = true
  audio.stop()
  $("#error").hidden = false
  $("#error").textContent =
    `Unable to continue the game: ${errorMessage(error)}\nReload the page to return to the menu.`
  console.error(error)
}
function animation(now: number) {
  const dt = Math.min(100, now - (previous || now))
  previous = now
  try {
    if (running && frame) {
      stream?.frame(now, state)
      if (streamMode) paused = stream?.paused ?? true
      if (!paused && !upgradeOpen && [0, 1, 2].includes(frame.phase)) {
        accumulator += dt
        while (accumulator >= STEP) {
          const dx =
              Number(keys.has("KeyD") || keys.has("ArrowRight")) -
              Number(keys.has("KeyA") || keys.has("ArrowLeft")) +
              touch.x,
            dy =
              Number(keys.has("KeyS") || keys.has("ArrowDown")) -
              Number(keys.has("KeyW") || keys.has("ArrowUp")) +
              touch.y,
            l = Math.max(1, Math.hypot(dx, dy))
          if (stream) {
            if (!stream.canMove) {
              accumulator = 0
              break
            }
            const movement = stream.movement(defined(state))
            consume("advance_live", movement.x, movement.y)
          } else consume("advance_live", dx / l, dy / l)
          accumulator -= STEP
          if (![0, 1, 2].includes(frame.phase) || upgradeOpen) {
            accumulator = 0
            break
          }
        }
      } else accumulator = 0
      audio.update(frame, !paused && !upgradeOpen && [0, 1, 2].includes(frame.phase))
      renderer.draw(frame, dt / 1000, profile.settings)
      hud()
    }
  } catch (e) {
    if (stream) stream.fail(e)
    else fail(e)
  }
  if (!running) stream?.frame(now, undefined)
  requestAnimationFrame(animation)
}
let banishing = false
enableSecondaryRewardTouch($("#dialog"))
document.addEventListener("click", (event) => {
  const b = event.target instanceof Element ? event.target.closest("button") : null
  if (!b || b.disabled) return
  audio.unlock()
  try {
    if (b.dataset.tab) {
      tab = b.dataset.tab
      menu()
      $("#menuScroll").scrollTop = 0
    } else if (b.dataset.menuPanel !== undefined) {
      openPanel = openPanel === b.dataset.menuPanel ? null : b.dataset.menuPanel
      pendingUnlock = null
      menu()
    } else if (b.hasAttribute("data-close-unlock")) {
      const inspected = pendingUnlock
      pendingUnlock = null
      menu()
      if (inspected)
        document
          .querySelector<HTMLElement>(`[data-${inspected.kind}="${inspected.id}"]`)
          ?.focus({ preventScroll: true })
    } else if (b.dataset.buyKind !== undefined) {
      const kind = b.dataset.buyKind,
        id = Number(b.dataset.buyId)
      const item = (kind === "character" ? CHARACTERS : kind === "stage" ? STAGES : []).find((x) => x.id === id)
      if (!item) return
      if (unlock(profile, kind, id)) {
        if (kind === "character") character = id
        else stage = id
        pendingUnlock = null
        openPanel = null
        audio.event("choose")
        menu()
      } else toast(requirementsMet(profile, item) ? "Not enough legacy gold" : (item.hint ?? "Requirement not met"))
    } else if (b.dataset.character !== undefined || b.dataset.stage !== undefined || b.dataset.mode !== undefined) {
      const kind = b.dataset.character !== undefined ? "character" : b.dataset.stage !== undefined ? "stage" : "mode"
      const id = Number(b.dataset[kind])
      if (isUnlocked(profile, kind, id)) {
        if (kind === "character") character = id
        else if (kind === "stage") stage = id
        else mode = id
        pendingUnlock = null
        openPanel = null
        menu()
      } else {
        pendingUnlock = pendingUnlock?.kind === kind && pendingUnlock.id === id ? null : { kind, id }
        openPanel = kind
        menu()
        const details = document.querySelector<HTMLElement>("[data-unlock-details]")
        details?.focus({ preventScroll: true })
        details?.scrollIntoView({ block: "nearest" })
      }
    } else if (b.dataset.arcana !== undefined) {
      arcana = Number(b.dataset.arcana)
      pendingUnlock = null
      openPanel = null
      menu()
    } else if (b.dataset.upgrade !== undefined) {
      if (buyUpgrade(profile, +b.dataset.upgrade)) {
        saveProfile(profile)
        audio.event("choose")
        menu()
      }
    } else if (b.dataset.collection) {
      collectionTab = b.dataset.collection
      menu()
    } else if (b.dataset.choice !== undefined) {
      if (streamMode) return
      audio.event("choose")
      upgradeOpen = false
      consume(banishing ? "banish" : "choose", Number(b.dataset.choice))
      banishing = false
      shownPhase = -1
      phase()
      shownPhase = frame.phase
    } else if (b.dataset.run) {
      if (streamMode) return
      if (b.dataset.run === "skip") upgradeOpen = false
      if (b.dataset.run !== "reroll" && b.dataset.run !== "skip") throw new Error("Unknown run action")
      consume(b.dataset.run)
      shownPhase = -1
      phase()
      shownPhase = frame.phase
    } else if (b.id === "banish") {
      if (streamMode) return
      banishing = !banishing
      b.textContent = banishing ? "Choose an ability to banish" : "Banish an offer…"
    } else if (b.id === "start" || b.id === "start-top" || b.id === "restart") {
      if (streamMode) document.querySelector<HTMLButtonElement>("#stream-start")?.click()
      else start().catch(fail)
    } else if (b.id === "map") pause(true)
    else if (b.id === "pause" || b.id === "resume") pause()
    else if (b.id === "return") {
      if (stream) stream.stop()
      else menu()
    } else if (b.id === "abandon") {
      if (stream) {
        stream.stop()
        return
      }
      recordRun(profile, { ...runResult(), phase: 3 })
      saveProfile(profile)
      menu()
    }
  } catch (e) {
    fail(e)
  }
})
document.addEventListener("change", (e) => {
  if (!(e.target instanceof HTMLInputElement)) return
  const id = e.target.id
  if (id === "sound") profile.settings.muted = !e.target.checked
  else if (id === "motion") profile.settings.reducedMotion = e.target.checked
  else if (id === "damage") profile.settings.showDamage = e.target.checked
  else if (id === "volume") profile.settings.volume = +e.target.value
  else return
  settings()
  saveProfile(profile)
})
window.addEventListener("keydown", (e) => {
  if (e.code === "Escape" && pendingUnlock && !running) {
    e.preventDefault()
    const inspected = pendingUnlock
    pendingUnlock = null
    menu()
    document.querySelector<HTMLElement>(`[data-${inspected.kind}="${inspected.id}"]`)?.focus({ preventScroll: true })
    return
  }
  if (e.code === "KeyM" && running && !document.activeElement?.matches("input,select,textarea")) {
    e.preventDefault()
    if (!e.repeat && !upgradeOpen) pause()
    return
  }
  if (!streamMode && !$("#overlay").hidden && e.code === "Tab") {
    const controls = [
      ...$("#dialog").querySelectorAll<HTMLElement>("button:not(:disabled),input:not(:disabled),[tabindex='0']")
    ]
    const first = controls[0],
      last = controls.at(-1)
    if (!first) {
      e.preventDefault()
      $("#dialog").focus()
      return
    }
    if (!$("#dialog").contains(document.activeElement)) {
      e.preventDefault()
      defined(e.shiftKey ? last : first).focus()
    } else if ((e.shiftKey && document.activeElement === first) || (!e.shiftKey && document.activeElement === last)) {
      e.preventDefault()
      defined(e.shiftKey ? last : first).focus()
    }
    return
  }
  // Preserve native keyboard activation and text/range controls.
  if (
    e.code !== "Escape" &&
    (document.activeElement?.matches("input,select,textarea") ||
      (document.activeElement?.matches("button") && !/^Digit[123]$/.test(e.code)))
  )
    return
  if (
    [
      "ArrowUp",
      "ArrowDown",
      "ArrowLeft",
      "ArrowRight",
      "Space",
      "Escape",
      "KeyW",
      "KeyA",
      "KeyS",
      "KeyD",
      "KeyE",
      "Digit1",
      "Digit2",
      "Digit3"
    ].includes(e.code)
  ) {
    if (running) e.preventDefault()
    if (e.repeat) return
    if (e.code === "KeyE") openUpgrade()
    else if (e.code === "Escape" || e.code === "Space") pause()
    else if (/^Digit[123]$/.test(e.code) && running && !paused && [1, 2].includes(frame.phase) && upgradeOpen)
      document.querySelector<HTMLButtonElement>(`[data-choice="${+e.code.slice(-1) - 1}"]`)?.click()
    else keys.add(e.code)
  }
})
window.addEventListener("keyup", (e) => keys.delete(e.code))
window.addEventListener("blur", () => {
  keys.clear()
  if (!streamMode) pause(true)
})
document.addEventListener("visibilitychange", () => {
  if (document.hidden) pause(true)
})
const joy = $("#joystick")
let pointer: number | null = null
function joystick(e: PointerEvent) {
  const r = joy.getBoundingClientRect(),
    x = e.clientX - r.left - r.width / 2,
    y = e.clientY - r.top - r.height / 2,
    l = Math.max(35, Math.hypot(x, y))
  touch.x = x / l
  touch.y = y / l
  $("#stick").style.transform = `translate(${touch.x * 33}px,${touch.y * 33}px)`
  e.preventDefault()
}
joy.addEventListener("pointerdown", (e) => {
  audio.unlock()
  pointer = e.pointerId
  joy.setPointerCapture(pointer)
  joystick(e)
})
joy.addEventListener("pointermove", (e) => {
  if (e.pointerId === pointer) joystick(e)
})
for (const type of ["pointerup", "pointercancel"])
  joy.addEventListener(type, () => {
    pointer = null
    touch.x = touch.y = 0
    $("#stick").style.transform = ""
  })
;({ character, stage, arcana, mode } = validateSetup(profile, {}))
settings()
menu()
requestAnimationFrame(animation)
// Fetch the simulation after the independent menu has mounted.
prepareRuntime().catch(() => {
  /* Keep the menu usable if the game download fails. */
})

if (streamMode) {
  document.body.classList.add("stream-mode")
  import("./browser-stream.mts")
    .then(({ BrowserStream }) => {
      stream = new BrowserStream({
        start: async (seed) => {
          await start(seed)
        },
        choose: (index) => {
          upgradeOpen = false
          audio.event("choose")
          consume("choose", index)
          shownPhase = -1
          phase()
          shownPhase = frame.phase
        },
        stop: () => {
          running = false
          paused = false
          accumulator = 0
          audio.stop(true)
          menu()
        },
        audio: () => audio.engine?.context?.state ?? audio.context?.state ?? "locked",
        unlock: () => audio.unlock(),
        audioStop: () => audio.stop()
      })
    })
    .catch(fail)
}
