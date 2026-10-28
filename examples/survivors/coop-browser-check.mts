import { chromium, type Page } from "playwright"
import { defined } from "./host-values.mts"
import assert from "node:assert/strict"
import type { WorkerReply } from "./coop-boundary.mts"
import type { Profile } from "./profile.mts"
declare global {
  interface Window {
    coopCheckFrame?: { stage: number; mode: number; tick: number; players: { id: number; character: number }[] }
  }
}
const browser = await chromium.launch({
  headless: true,
  args: [
    "--no-sandbox",
    "--disable-background-timer-throttling",
    "--disable-renderer-backgrounding",
    "--disable-backgrounding-occluded-windows"
  ]
})
const pages: Page[] = []
const nativeLoads = new WeakMap<Page, { count: number }>()
async function page(url: string, profile?: Profile) {
  const context = await browser.newContext()
  if (profile)
    await context.addInitScript(
      (value) => localStorage.setItem("nightfall-survivors-v1", JSON.stringify(value)),
      profile
    )
  await context.addInitScript(() => {
    const NativeWorker = window.Worker
    window.Worker = class extends NativeWorker {
      constructor(url: string | URL, options?: WorkerOptions) {
        super(url, options)
        this.addEventListener("message", (event: MessageEvent<WorkerReply>) => {
          if (event.data.type !== "frame") return
          window.coopCheckFrame = {
            tick: event.data.frame.tick,
            stage: event.data.frame.stage,
            mode: event.data.frame.mode,
            players: event.data.frame.players.map(({ id, character }) => ({ id, character }))
          }
        })
      }
    }
  })
  const page = await context.newPage()
  const loads = { count: 0 }
  nativeLoads.set(page, loads)
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.endsWith("/iroh/iroh_transport.js")) loads.count++
  })
  pages.push(page)
  page.on("pageerror", (e) => console.log("PAGEERROR", e.message))
  await page.goto(url)
  return page
}
async function status(p: Page) {
  return p.locator("#coop-status").innerText()
}
try {
  const host = await page(new URL("coop.html", process.argv[2] ?? "http://127.0.0.1:8714/").href)
  await host.evaluate(async () => {
    const { loadProfile } = await import("./progression.mjs")
    const profile = loadProfile()
    localStorage.setItem(
      "nightfall-survivors-v1",
      JSON.stringify({ ...profile, characters: [0, 1], stages: [0, 1, 2], stats: { ...profile.stats, levels: 20 } })
    )
  })
  await host.reload()
  await host.locator("#coop-host").click()
  await host.waitForFunction(() => document.querySelector<HTMLInputElement>("#coop-invite-link")?.value, null, {
    timeout: 90000
  })
  const invite = await host.locator("#coop-invite-link").inputValue()
  console.log("room ready")
  await host.locator("#coop-invite-close").click()
  await host.locator('[data-menu-panel="stage"]').click()
  await host.locator('[data-stage="1"]').click()
  await host.waitForFunction(() => window.coopCheckFrame?.stage === 1)
  const guestProfile = await host.evaluate(async () => {
    const { loadProfile } = await import("./progression.mjs")
    return { ...loadProfile(), characters: [0, 1] }
  })
  const guests: Page[] = []
  for (let i = 0; i < 3; i++) {
    const invitation = new URL(invite)
    if (i === 1) {
      invitation.hash = new URLSearchParams({ join: defined(invitation.searchParams.get("join")) }).toString()
      invitation.searchParams.delete("join")
    }
    const guest = await page(invitation.href, i === 0 ? guestProfile : undefined)
    await guest.getByRole("button", { name: "Join party", exact: true }).waitFor()
    await new Promise((resolve) => setTimeout(resolve, 1000))
    assert.equal(await host.locator('#coop-party-roster [data-ready="true"]').count(), i + 1)
    assert.equal(new URL(guest.url()).searchParams.has("seat"), false)
    assert.equal(
      defined(nativeLoads.get(guest)).count,
      0,
      "Invitation previews must not load the native endpoint factory"
    )
    await guest.getByRole("button", { name: "Join party", exact: true }).click()
    guests.push(guest)
    await host.waitForFunction(
      (n) => document.querySelectorAll('#coop-party-roster [data-ready="true"]').length >= n,
      i + 2,
      { timeout: 90000 }
    )
    console.log("joined", i + 1, await status(guest))
    assert.ok(defined(nativeLoads.get(guest)).count > 0, "Joining must execute the real Iroh adapter")
    if (i === 0) {
      await guest.waitForFunction(() => document.querySelector("#coop-setup-preview .stage-art-1"))
      await host.locator('[data-menu-panel="stage"]').click()
      await host.locator('[data-stage="2"]').click()
      await host.waitForFunction(() => window.coopCheckFrame?.stage === 2)
    }
  }
  await host.locator('[data-menu-panel="character"]').click()
  await host.locator('[data-character="1"]').click()
  await host.locator('[data-menu-panel="stage"]').click()
  await host.locator('[data-stage="1"]').click()
  await host.locator('[data-menu-panel="mode"]').click()
  await host.locator('[data-mode="1"]').click()
  await host.waitForFunction(
    () =>
      window.coopCheckFrame?.stage === 1 &&
      window.coopCheckFrame?.mode === 1 &&
      window.coopCheckFrame.players.some((player) => player.id === 0 && player.character === 1)
  )
  for (const guest of guests) {
    await guest.waitForFunction(() => document.querySelector("#coop-room-settings")?.textContent.includes("Inverse"))
    assert.equal(await guest.locator('[data-menu-panel="stage"]').count(), 0)
    assert.equal(await guest.locator('[data-menu-panel="mode"]').count(), 0)
    assert.equal(await guest.locator("#coop-setup-preview .stage-art-1").count(), 1)
  }
  console.log("host survivor, stage and mode changed after guests joined; all guests see host settings")
  await defined(guests[0]).locator('[data-menu-panel="character"]').click()
  await defined(guests[0]).locator('[data-character="1"]').click()
  await host.waitForFunction(() =>
    window.coopCheckFrame?.players.some((player) => player.id === 1 && player.character === 1)
  )
  assert.match(await host.locator('#coop-party-roster [data-player="1"]').innerText(), /Corvin/)
  console.log("guest survivor update reached roster and authoritative lobby world")
  assert.equal(await defined(guests[0]).locator("#coop-setup-fields").isEnabled(), true)
  await new Promise((r) => setTimeout(r, 2000))
  assert.equal(await host.locator("#coop-play").isVisible(), false)
  assert.equal(await host.locator("#coop-start").isEnabled(), true)
  const fifth = await page(invite)
  await fifth.getByRole("button", { name: "Join party", exact: true }).click()
  await fifth.waitForFunction(
    () =>
      document.querySelector("#coop-status")?.textContent.includes("full") ||
      document.querySelector("#coop-status")?.textContent.includes("unavailable"),
    null,
    { timeout: 90000 }
  )
  console.log("fifth refused")
  await host.locator("#coop-start").click()
  for (const p of [host, ...guests]) {
    await p.locator("#coop-play").waitFor({ state: "visible", timeout: 30000 })
    await p.waitForFunction(() => document.querySelectorAll("#coop-players .player-status").length === 4)
  }
  await host.waitForFunction(() =>
    window.coopCheckFrame?.players.some((player) => player.id === 1 && player.character === 1)
  )
  assert.equal(await host.evaluate(() => window.coopCheckFrame?.stage), 1)
  assert.equal(await host.evaluate(() => window.coopCheckFrame?.mode), 1)
  assert.equal(
    await host.locator("#coop-setup-fields").evaluate((fields: HTMLFieldSetElement) => fields.disabled),
    true
  )
  await defined(guests[0]).keyboard.down("ArrowRight")
  await defined(guests[1]).keyboard.down("ArrowDown")
  await defined(guests[2]).keyboard.down("ArrowLeft")
  await host.keyboard.down("ArrowUp")
  await new Promise((r) => setTimeout(r, 1500))
  for (const p of [host, ...guests]) await p.keyboard.up("ArrowRight").catch(() => {})
  for (const p of [host, ...guests]) await p.keyboard.up("ArrowDown").catch(() => {})
  for (const p of [host, ...guests]) await p.keyboard.up("ArrowLeft").catch(() => {})
  await host.keyboard.up("ArrowUp")
  console.log(
    "four running clocks",
    await Promise.all([host, ...guests].map((p) => p.locator("#coop-clock").innerText()))
  )
  const rejoin = defined(guests[2]).url()
  await defined(guests[2]).close()
  await host.waitForFunction(() => document.querySelector("#coop-play-status")?.textContent.includes("paused"), null, {
    timeout: 15000
  })
  const stopped = await host.locator("#coop-clock").innerText()
  await defined(guests[0]).keyboard.down("ArrowRight")
  await new Promise((r) => setTimeout(r, 2500))
  await defined(guests[0]).keyboard.up("ArrowRight")
  assert.equal(await host.locator("#coop-clock").innerText(), stopped)
  console.log("shared paused", stopped)
  const returned = await page(rejoin)
  await returned.getByRole("button", { name: "Join party", exact: true }).waitFor()
  assert.equal(defined(nativeLoads.get(returned)).count, 0, "Reserved-seat previews must not create an endpoint")
  await new Promise((resolve) => setTimeout(resolve, 1000))
  assert.equal(await host.locator("#coop-clock").innerText(), stopped)
  await returned.getByRole("button", { name: "Join party", exact: true }).click()
  await returned.locator("#coop-play").waitFor({ state: "visible", timeout: 45000 })
  await host.waitForFunction(() => !document.querySelector("#coop-play-status")?.textContent.includes("paused"), null, {
    timeout: 30000
  })
  console.log("rejoined reserved seat", new URL(returned.url()).searchParams.get("seat"))
  await new Promise((r) => setTimeout(r, 1500))
  console.log(
    "resumed clocks",
    await host.locator("#coop-clock").innerText(),
    await returned.locator("#coop-clock").innerText()
  )
  for (const p of [host, defined(guests[0]), defined(guests[1]), returned]) {
    assert.equal(await p.locator(".coop-diagnostic:visible").count(), 0)
    await p.screenshot({ path: `/tmp/network4-${pages.indexOf(p)}.png` })
  }
  console.log(
    "PASS real Iroh four-player lobby, explicit join and start, capacity, shared pause and reserved-seat rejoin"
  )
} finally {
  await browser.close()
}
