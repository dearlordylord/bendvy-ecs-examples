import { chromium, type Page } from "playwright"
import type { WorkerReply } from "./coop-boundary.mts"
import assert from "node:assert/strict"
const browser = await chromium.launch({
  headless: true,
  args: ["--no-sandbox", "--disable-background-timer-throttling", "--disable-renderer-backgrounding"]
})
const departFirstSeat = process.argv.includes("--depart-first-seat")
const stalledReceipt = process.argv.includes("--stalled-receipt") || departFirstSeat
const base = process.argv[2] ?? "http://127.0.0.1:8718/"
try {
  const context = await browser.newContext()
  await context.route("**/coop-worker.mjs", async (route) => {
    const response = await route.fetch()
    const source = await response.text()
    assert.ok(source.includes("const frame = packet(Game.core_step_players(core, rows))"))
    await route.fulfill({
      response,
      body: source.replace(
        "const frame = packet(Game.core_step_players(core, rows))",
        "if (currentWorldTick >= 120) core = { ...core, shared: { ...core.shared, phase: 3 } }; const frame = packet(Game.core_step_players(core, rows))"
      )
    })
  })
  await context.addInitScript(() => {
    const native = window.Worker
    window.Worker = class extends native {
      constructor(url: string | URL, options?: WorkerOptions) {
        super(url, options)
        this.addEventListener("message", (event: MessageEvent<WorkerReply>) => {
          if (event.data.type === "finished") document.documentElement.dataset.workerFinished = "true"
        })
      }
      override terminate() {
        document.documentElement.dataset.workerTerminated = "true"
        super.terminate()
      }
    }
  })
  async function open(url: string, stall = false) {
    const p = await context.newPage()
    p.on("pageerror", (error) => console.log("PAGEERROR", error.message))
    await p.goto(url)
    await p.evaluate(async (stall) => {
      const { CoopTransport } = await import("./coop-transport.mjs")
      // oxlint-disable-next-line typescript/unbound-method
      const close = CoopTransport.prototype.close
      // oxlint-disable-next-line typescript/unbound-method
      const send = CoopTransport.prototype.send
      CoopTransport.prototype.close = function () {
        document.documentElement.dataset.closes = String(Number(document.documentElement.dataset.closes ?? 0) + 1)
        return close.call(this)
      }
      CoopTransport.prototype.send = function (...args: Parameters<typeof send>) {
        document.documentElement.dataset.sends = String(Number(document.documentElement.dataset.sends ?? 0) + 1)
        if (
          stall &&
          document.querySelector("#coop-reward-kind")?.textContent === "Run complete" &&
          typeof args[0] === "string"
        ) {
          args[0] = args[0].replace(/BSA1\|(\d+)\|(\d+)/, (_receipt, token: string) => `BSA1|${token}|4294967295`)
        }
        return send.apply(this, args)
      }
    }, stall)
    return p
  }
  const host = await open(new URL("coop.html", base).href)
  await host.locator("#coop-host").click()
  await host.waitForFunction(() => document.querySelector<HTMLInputElement>("#coop-invite-link")?.value, null, {
    timeout: 90000
  })
  const invitation = await host.locator("#coop-invite-link").inputValue()
  await host.locator("#coop-invite-close").click()
  const guests: Page[] = []
  for (let i = 0; i < 3; i++) {
    const guest = await open(invitation, stalledReceipt && i === (departFirstSeat ? 1 : 0))
    guests.push(guest)
    await guest.getByRole("button", { name: "Join party", exact: true }).click()
    await host.waitForFunction(
      (n) => document.querySelectorAll('#coop-party-roster [data-ready="true"]').length === n,
      i + 2,
      { timeout: 90000 }
    )
  }
  await host.locator("#coop-start").click()
  for (const p of [host, ...guests]) {
    await p.waitForFunction(() => document.querySelector("#coop-reward-kind")?.textContent === "Run complete", null, {
      timeout: 30000
    })
    assert.match(await p.locator("#coop-offers").innerText(), /Saved to this browser/)
  }
  if (departFirstSeat) await guests[0]?.close()
  const remainingGuests = departFirstSeat ? guests.slice(1) : guests
  const remainingPages = [host, ...remainingGuests]
  if (stalledReceipt) {
    await new Promise((resolve) => setTimeout(resolve, 6500))
    assert.equal(
      await host.evaluate(() => Number(document.documentElement.dataset.closes ?? 0)),
      0,
      "Forged final receipt cannot close the room"
    )
    for (const p of remainingGuests)
      assert.doesNotMatch(await p.locator("#coop-play-status").innerText(), /waiting|disconnected|paused|failed/i)
  }
  await host.waitForFunction(() => Number(document.documentElement.dataset.closes) === 3, null, { timeout: 25000 })
  assert.equal(await host.evaluate(() => document.documentElement.dataset.workerFinished), "true")
  assert.equal(await host.evaluate(() => document.documentElement.dataset.workerTerminated), "true")
  for (const p of remainingGuests)
    await p.waitForFunction(() => Number(document.documentElement.dataset.closes) >= 1, null, { timeout: 25000 })
  const after = await Promise.all(
    remainingPages.map(async (p) =>
      p.evaluate(() => ({
        profile: localStorage.getItem("nightfall-survivors-v1"),
        sends: document.documentElement.dataset.sends
      }))
    )
  )
  await new Promise((resolve) => setTimeout(resolve, 1500))
  for (const [i, p] of remainingPages.entries()) {
    assert.equal(await p.locator("#coop-reward-kind").textContent(), "Run complete")
    assert.equal(
      await p.evaluate(() => localStorage.getItem("nightfall-survivors-v1")),
      after[i]?.profile,
      "Result progression is settled exactly once"
    )
    assert.equal(
      await p.evaluate(() => document.documentElement.dataset.sends),
      after[i]?.sends,
      "Terminal rooms send no further inputs or snapshots"
    )
    assert.doesNotMatch(await p.locator("#coop-play-status").innerText(), /disconnected|paused|failed/i)
  }
  console.log(
    departFirstSeat
      ? "Room drain survived first-seat departure and another forged final receipt"
      : stalledReceipt
        ? "Bounded deadline with forged final receipt passed"
        : "All final application receipts admitted"
  )
  console.log(
    "Real Iroh terminal delivery passed for all three guests; results and profiles preserved; three host endpoints closed; worker terminated; traffic stopped"
  )
} finally {
  await browser.close()
}
