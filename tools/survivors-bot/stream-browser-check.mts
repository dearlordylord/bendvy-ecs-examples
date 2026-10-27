import assert from "node:assert/strict"
import { boundedGoalContrast, validatedPositions, safeNatural, arenaCoordinate, verifyGoalBoundSources, type GoalTrack } from "./stream-goal-capture.mts"
import { appendFile, mkdir, readFile, rename, writeFile } from "node:fs/promises"
import path from "node:path"
import { performance } from "node:perf_hooks"
import { execFileSync } from "node:child_process"
import { chromium, webkit, type BrowserType, type Page } from "playwright"
import type { StreamDiagnostic } from "../../examples/survivors/browser-stream.mts"
import { boundedProbe, initialHealth, observeProgress } from "./stream-browser-health.mts"
import { installStreamObservers } from "./stream-browser-observe.mts"
import { browserRuntime } from "./stream-browser-runtime.mts"
import {
  applicationManifest,
  snapshotApplication,
  fixtureServer,
  strategySource,
  goalStrategySource,
  type StrategyFault
} from "./stream-browser-server.mts"

const args = process.argv.slice(2)
function option(name: string, fallback: string): string {
  const index = args.indexOf(name)
  if (index < 0) return fallback
  const value = args[index + 1]
  if (!value || value.startsWith("--")) throw new Error(`${name} needs a value`)
  return value
}
const root = path.resolve(option("--root", "examples/survivors/dist/web"))
const out = path.resolve(option("--out", ".audit/stream-browser-check"))
assert(out !== root && !out.startsWith(`${root}${path.sep}`), "--out must be outside the application root")
const selectedBrowser = option("--browser", "both")
assert(["chromium", "webkit", "both"].includes(selectedBrowser), "--browser must be chromium, webkit or both")
const soakHours = Number(option("--soak-hours", "0"))
assert(Number.isFinite(soakHours) && soakHours >= 0, "--soak-hours must be a nonnegative finite number")
const soakOnly = args.includes("--soak-only")
const audioOnly = args.includes("--audio-only")
const goalsOnly = args.includes("--goals-only")
assert(!goalsOnly || (!audioOnly && !soakOnly && soakHours === 0), "--goals-only requires its own focused run")
assert(
  !goalsOnly || selectedBrowser === "chromium",
  "--goals-only requires --browser chromium for common-tick Canvas capture"
)
assert(!audioOnly || (!soakOnly && soakHours === 0), "--audio-only cannot be combined with soak modes")
const headed = args.includes("--headed")
assert(
  soakHours < 24 || (headed && selectedBrowser === "chromium"),
  "24h foreground qualification requires --browser chromium --headed"
)
const strategyBuilder = path.resolve(
  option("--strategy-builder", path.join(import.meta.dirname, "build-stream-strategy.mts"))
)
await mkdir(out, { recursive: true })
const snapshotRoot = path.join(out, "application")
const application = await snapshotApplication(root, snapshotRoot)
await writeFile(path.join(out, "application-manifest.json"), JSON.stringify(application, null, 2))
const profileKey = "nightfall-survivors-v1"
const started = new Date().toISOString()
const sourceIdentity: unknown = JSON.parse(await readFile(path.join(snapshotRoot, "version.json"), "utf8"))
const fixture = await fixtureServer(snapshotRoot)
const results: { browser: string; scenario: string; elapsedMs: number; evidence: unknown }[] = []
const errors: string[] = []

type Diagnostics = StreamDiagnostic
function record(value: unknown): Record<string, unknown> {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), "Expected diagnostic object")
  return Object.fromEntries(Object.entries(value))
}
function number(value: unknown, name: string): number {
  assert(typeof value === "number" && Number.isFinite(value), `Diagnostic ${name} must be finite`)
  return value
}
function text(value: unknown, name: string): string {
  assert(typeof value === "string", `Diagnostic ${name} must be a string`)
  return value
}
function parseIntention(value: unknown): StreamDiagnostic["logs"][number]["intention"] {
  if (value === null) return null
  const intention = record(value)
  if (intention.$ === "Default") return { $: "Default" }
  assert(intention.$ === "GoalChoice" || intention.$ === "UpgradeChoice", "Unknown logged intention")
  return { $: intention.$, index: number(intention.index, "intention index") }
}
async function diagnostics(page: Page): Promise<Diagnostics> {
  const json: unknown = JSON.parse((await page.locator("#stream-diagnostics").textContent()) ?? "null")
  const d = record(json)
  assert(typeof d.paused === "boolean", "Diagnostic paused must be boolean")
  assert(Array.isArray(d.logs), "Diagnostic logs must be an array")
  return {
    session: number(d.session, "session"),
    run: number(d.run, "run"),
    tick: number(d.tick, "tick"),
    phase: number(d.phase, "phase"),
    mode: text(d.mode, "mode"),
    paused: d.paused,
    frames: number(d.frames, "frames"),
    generation: number(d.generation, "generation"),
    revision: text(d.revision, "revision"),
    status: text(d.status, "status"),
    commits: number(d.commits, "commits"),
    lastError: typeof d.lastError === "string" ? d.lastError : "",
    logs: d.logs.map((value) => {
      const log = record(value)
      return {
        event: text(log.event, "log event"),
        detail: text(log.detail, "log detail"),
        tick: number(log.tick, "log tick"),
        at: number(log.at, "log at"),
        session: number(log.session, "log session"),
        run: number(log.run, "log run"),
        generation: number(log.generation, "log generation"),
        revision: text(log.revision, "log revision"),
        request: number(log.request, "log request"),
        decision: number(log.decision, "log decision"),
        originSession: number(log.originSession, "log originSession"),
        originRun: number(log.originRun, "log originRun"),
        intention: parseIntention(log.intention)
      }
    })
  }
}
async function until(page: Page, predicate: (d: Diagnostics) => boolean, timeout = 30000): Promise<Diagnostics> {
  const deadline = performance.now() + timeout
  let latest: Diagnostics | undefined
  while (performance.now() < deadline) {
    latest = await diagnostics(page)
    if (predicate(latest)) return latest
    await page.waitForTimeout(100)
  }
  throw new Error(`Condition timed out after ${timeout}ms: ${JSON.stringify(latest)}`)
}
async function report() {
  const filename = path.join(out, "report.json")
  await writeFile(
    `${filename}.tmp`,
    JSON.stringify(
      {
        started,
        updated: new Date().toISOString(),
        root,
        snapshotRoot,
        sourceIdentity,
        applicationHash: application.hash,
        soakHours,
        results,
        errors
      },
      null,
      2
    )
  )
  await rename(`${filename}.tmp`, filename)
}
async function scenario(browser: string, name: string, run: () => Promise<unknown>) {
  const begin = performance.now()
  const evidence = await run()
  results.push({ browser, scenario: name, elapsedMs: performance.now() - begin, evidence })
  await report()
  process.stdout.write(`${browser}: PASS ${name}\n`)
}
async function revision(page: Page, label: string, fault: StrategyFault = "healthy", memoryVersion = 1) {
  const hash = fixture.publish(strategySource({ label, fault, memoryVersion }))
  await page.locator("#stream-reload").click()
  return hash
}
function browserRss(rootPid: number): number {
  const rows = execFileSync("ps", ["-eo", "pid=,ppid=,rss="], { encoding: "utf8" })
    .trim()
    .split("\n")
    .map((row) => row.trim().split(/\s+/).map(Number))
  const owned = new Set([rootPid])
  let added = true
  while (added) {
    added = false
    for (const [pid, parent] of rows)
      if (pid !== undefined && parent !== undefined && owned.has(parent) && !owned.has(pid)) {
        owned.add(pid)
        added = true
      }
  }
  return rows.reduce(
    (total, [pid, , rss]) => total + (pid !== undefined && rss !== undefined && owned.has(pid) ? rss * 1024 : 0),
    0
  )
}
async function runBrowser(kind: BrowserType) {
  const browserName = kind.name()
  const runtime = await browserRuntime(kind, headed)
  const { browser, context, pid: browserPid } = runtime
  try {
    await context.addInitScript(installStreamObservers)
    const page = await context.newPage()
    const pageErrors: string[] = []
    page.on("pageerror", (error) => pageErrors.push(error.message))
    let workers = 0
    let maxWorkers = 0
    page.on("worker", (worker) => {
      workers++
      maxWorkers = Math.max(maxWorkers, workers)
      worker.on("close", () => workers--)
    })
    const url = new URL("/", fixture.url)
    url.searchParams.set("stream", "1")
    url.searchParams.set("seed", "982451653")
    const initialHash = fixture.publish(strategySource({ label: "acceptance-initial" }))
    url.searchParams.set("advice", "500")
    url.searchParams.set("dwell", "1500")
    url.searchParams.set("between", "2000")
    let baselineProfile: string | null = null
    try {
      if (goalsOnly) {
        const boundEvidence = await verifyGoalBoundSources(sourceIdentity, snapshotRoot)
        await writeFile(path.join(out, "goal-bound-provenance.json"), JSON.stringify(boundEvidence, null, 2))
        const tracks: GoalTrack[] = []
        url.searchParams.set("stream-goals-check", "1")
        for (const direction of ["east", "west"] satisfies ("east" | "west")[]) {
          await scenario(browserName, `external ${direction} goal matches supplied candidate`, async () => {
            const hash = fixture.publish(goalStrategySource(direction))
            url.searchParams.set("strategy", fixture.manifest)
            await page.goto(url.href)
            assert.equal(await page.evaluate((key) => localStorage.getItem(key), profileKey), null,
              "Goal check requires fresh isolated default profile on each navigation")
            await page.locator("#stream-start").click()
            const accepted = await until(page, (d) =>
              d.logs.some(
                (log) =>
                  log.event === "advice-accepted" &&
                  log.detail === `goal-${direction}` &&
                  log.intention?.$ === "GoalChoice"
              )
            )
            const decision = accepted.logs.find(
              (log) => log.event === "advice-accepted" && log.detail === `goal-${direction}`
            )
            assert(decision?.intention?.$ === "GoalChoice")
            assert.equal(decision.revision, hash)
            const inputs: unknown = JSON.parse(
              await page.evaluate(() => document.documentElement.dataset.checkGoalInputs ?? "[]")
            )
            assert(Array.isArray(inputs))
            for (const field of ["session", "run", "generation", "request", "decision", "tick", "originSession", "originRun"]) {
              safeNatural(number(Reflect.get(decision, field), field), field)
            }
            assert.equal(decision.session, decision.originSession)
            assert.equal(decision.run, decision.originRun)
            const matching = inputs.map(record).filter((input) => {
              const identity = record(input.identity)
              return ["session", "run", "generation", "request", "decision"].every((field) =>
                identity[field] === Reflect.get(decision, field)) && identity.phase === 0
            })
            assert.equal(matching.length, 1, "Accepted goal requires one exact complete supplied identity")
            const supplied = matching[0]
            assert(supplied, "Accepted external goal must match an actual supplied Worker observation")
            let goals: unknown = supplied.goals
            let target: Record<string, unknown> | undefined
            let matchingCandidates = 0
            while (goals !== null && typeof goals === "object") {
              const row = record(goals)
              if (row.$ !== "Con") break
              const goal = record(row.head)
              safeNatural(number(goal.index, "goal index"), "goal index")
              if (goal.index === decision.intention.index) {
                target = goal
                matchingCandidates++
              }
              goals = row.tail
            }
            assert.equal(matchingCandidates, 1, "Candidate index must be unique")
            assert(target, "Accepted index must identify a supplied bounded candidate")
            assert.equal(target.kind, direction === "east" ? 13 : 15)
            const startX = number(supplied.px, "supplied player x"),
              startY = number(supplied.py, "supplied player y")
            const targetX = number(target.x, "goal x"),
              targetY = number(target.y, "goal y")
            for (const coordinate of [startX, startY, targetX, targetY]) arenaCoordinate(coordinate)
            const tick = safeNatural(number(supplied.tick, "supplied tick"), "supplied tick")
            assert(tick <= decision.tick, "Supplied input must precede admission")
            assert(tick < 60, "External goal must be admitted before the common early measurement endpoint")
            await page.waitForFunction(
              () => Number(document.querySelector<HTMLCanvasElement>("#game")?.dataset.tick) >= 105
            )
            await page.locator("#stream-pause").click()
            const trajectory: unknown = JSON.parse(
              await page.evaluate(() => document.documentElement.dataset.checkGoalPositions ?? "[]")
            )
            assert(Array.isArray(trajectory))
            await writeFile(path.join(out, `${browserName}-goal-${direction}-raw-trajectory.json`),
              JSON.stringify(trajectory, null, 2))
            const positions = validatedPositions(trajectory.map(record).map((point) => ({
              tick: number(point.tick, "point tick"), x: number(point.x, "point x"), y: number(point.y, "point y")
            })))
            const terminal = await diagnostics(page)
            assert.equal(terminal.session, decision.session, "Session continuity through capture")
            assert.equal(terminal.run, decision.run, "Run continuity through capture")
            safeNatural(terminal.tick, "Terminal tick")
            assert(terminal.tick >= 105)
            let previousLogTick = 0
            for (const log of terminal.logs) {
              safeNatural(log.tick, "Journal tick")
              assert(log.tick >= previousLogTick && log.tick <= terminal.tick, "Journal tick continuity")
              previousLogTick = log.tick
            }
            assert(terminal.logs.every((log) => log.session === decision.session && log.run === decision.run),
              "Captured logs must retain one actual run")
            await writeFile(path.join(out, `${browserName}-goal-${direction}-journal.json`),
              JSON.stringify({ decision, supplied, terminal }, null, 2))
            await writeFile(
              path.join(out, `${browserName}-goal-${direction}-trajectory.json`),
              JSON.stringify(positions, null, 2)
            )
            const initial = positions.find((point) => point.tick === 0),
              endpoint = positions.find((point) => number(point.tick, "point tick") >= 80)
            assert(initial && endpoint, "Actual canvas projections must contain initial tick0 and early endpoint")
            assert.deepEqual(initial, { tick: 0, x: 7200, y: 7200 }, "Audited setup initial projection")
            tracks.push({
              direction,
              startX,
              startY,
              targetX,
              targetY,
              suppliedTick: tick,
              acceptedTick: decision.tick,
              positions: positions.map((point) => ({
                tick: number(point.tick, "point tick"),
                x: number(point.x, "point x"),
                y: number(point.y, "point y")
              }))
            })
            const position = {
              tick: number(endpoint.tick, "endpoint tick"),
              x: number(endpoint.x, "endpoint x"),
              y: number(endpoint.y, "endpoint y")
            }
            const initialPosition = {
              tick: number(initial.tick, "initial tick"),
              x: number(initial.x, "initial x"),
              y: number(initial.y, "initial y")
            }
            const dx = position.x - initialPosition.x,
              dy = position.y - initialPosition.y
            await writeFile(
              path.join(out, `${browserName}-goal-${direction}-observed.json`),
              JSON.stringify({ decision, supplied, target, initialPosition, position, dx, dy, positions }, null, 2)
            )
            await page.screenshot({ path: path.join(out, `${browserName}-goal-${direction}.png`) })
            return { seed: 982451653, decision, supplied, target, initialPosition, position, dx, dy }
          })
        }
        await scenario(browserName, "opposing external goals control actual navigation", async () => {
          assert.deepEqual(pageErrors, [], "Unexpected page errors during external-goal navigation")
          const [east, west] = tracks
          assert(east && west)
          const contrast = boundedGoalContrast(east, west)
          await writeFile(path.join(out, `${browserName}-goal-contrast.json`), JSON.stringify(contrast, null, 2))
          assert(contrast.spatialPass, "SPATIAL: conservative goal direction, approach and separation margins must all be positive")
          return contrast
        })
        return
      }
      await page.goto(url.href)
      await page.locator("#stream-start").waitFor()
      baselineProfile = await page.evaluate((key) => localStorage.getItem(key), profileKey)
      await page.locator("#stream-start").click()
      await until(page, (d) => d.tick > 5 && d.generation > 0, 120000)
      await scenario(browserName, "shipped default strategy", async () => {
        const live = await until(
          page,
          (d) => d.revision.includes("collector-v1") && d.logs.some((log) => log.event === "advice-accepted"),
          30000
        )
        return { live, sourceIdentity }
      })
      await page.locator("#stream-strategy").fill(fixture.manifest)
      await page.locator("#stream-reload").click()
      await until(page, (d) => d.revision.includes(initialHash.slice(0, 12)))
      if (audioOnly) {
        await scenario(browserName, "public compact controls retain stream status", async () => {
          await page.locator("#stream-compact").click()
          assert.equal(await page.locator("#stream-compact").getAttribute("aria-expanded"), "false")
          assert(await page.locator("#stream-status").isVisible())
          assert(await page.locator("#stream-intention").isVisible())
          assert.equal(await page.locator("#stream-pause").isVisible(), false)
          await page.locator("#stream-compact").click()
          assert.equal(await page.locator("#stream-compact").getAttribute("aria-expanded"), "true")
          assert(await page.locator("#stream-pause").isVisible())
          await page.locator("#stream-controls summary").click()
          assert(await page.locator("#stream-diagnostics").isVisible())
          const expanded = await diagnostics(page)
          await page.locator("#stream-controls summary").click()
          return { expanded, status: await page.locator("#stream-status").innerText() }
        })
        await scenario(browserName, "native audio suspension and public recovery", async () => {
          await page.waitForFunction(() => Number(document.documentElement.dataset.checkAudioRecentPcmPeak) > 0.00001)
          await page.evaluate(() => document.dispatchEvent(new Event("stream-check-suspend-audio")))
          await page.waitForFunction(() =>
            document.querySelector("#stream-status")?.textContent?.includes("audio suspended")
          )
          const suspended = await page.locator("#stream-status").innerText()
          assert.equal(await page.evaluate(() => document.documentElement.dataset.checkAudioState), "suspended")
          await page.waitForTimeout(1200)
          const suspendedPcm = Number(
            await page.evaluate(() => document.documentElement.dataset.checkAudioRecentPcmPeak)
          )
          assert(suspendedPcm < 0.00001, "Suspended audio must clear the actual rolling PCM window before recovery")
          await page.locator("#stream-audio").click()
          await page.waitForFunction(
            () =>
              document.querySelector("#stream-status")?.textContent?.includes("audio running") &&
              Number(document.documentElement.dataset.checkAudioRecentPcmPeak) > 0.00001
          )
          assert.equal(await page.evaluate(() => document.documentElement.dataset.checkAudioContexts), "1")
          assert.equal(await page.evaluate(() => document.documentElement.dataset.checkAudioSuspendError), undefined)
          return { suspended, suspendedPcm, resumed: await page.locator("#stream-status").innerText() }
        })
        await scenario(browserName, "public Settings mute and unmute", async () => {
          await page.locator("#stream-stop").click()
          await page.locator('#tabs [data-tab="settings"]').click()
          await page.locator("#sound").uncheck()
          await page.locator("#stream-start").click()
          await until(page, (d) => d.tick > 60)
          await page.waitForTimeout(2200)
          const muted = Number(await page.evaluate(() => document.documentElement.dataset.checkAudioRecentPcmPeak))
          assert(muted < 0.00001, "Public mute must silence actual master PCM")
          await page.locator("#stream-stop").click()
          await page.locator('#tabs [data-tab="settings"]').click()
          await page.locator("#sound").check()
          baselineProfile = await page.evaluate((key) => localStorage.getItem(key), profileKey)
          await page.locator("#stream-start").click()
          await page.waitForFunction(() => Number(document.documentElement.dataset.checkAudioRecentPcmPeak) > 0.00001)
          assert.equal(await page.evaluate(() => document.documentElement.dataset.checkAudioContexts), "1")
          return {
            muted,
            unmuted: Number(await page.evaluate(() => document.documentElement.dataset.checkAudioRecentPcmPeak)),
            contexts: await page.evaluate(() => document.documentElement.dataset.checkAudioContexts)
          }
        })
      }
      if (!soakOnly && !audioOnly) {
        await scenario(browserName, "real audio context and scheduled sound", async () => {
          await page.waitForFunction(() => Number(document.documentElement.dataset.checkAudioNodes) > 0)
          const audio = await page.evaluate(() => ({
            checkAudioContexts: document.documentElement.dataset.checkAudioContexts,
            checkAudioState: document.documentElement.dataset.checkAudioState,
            checkAudioNodes: document.documentElement.dataset.checkAudioNodes
          }))
          assert.equal(audio.checkAudioContexts, "1", "Stream must reuse a single audio context")
          assert.equal(audio.checkAudioState, "running", "Start gesture must unlock actual browser audio")
          await page.waitForFunction(() => Number(document.documentElement.dataset.checkAudioPcmPeak) > 0.00001)
          const pcmPeak = Number(await page.evaluate(() => document.documentElement.dataset.checkAudioPcmPeak))
          assert(pcmPeak > 0.00001, "Actual master signal must contain nonzero PCM")
          return { ...audio, pcmPeak }
        })
        await scenario(browserName, "real game frames and strategy", async () => {
          const first = await diagnostics(page)
          const firstCanvas = await page.locator("#game").screenshot()
          await page.waitForTimeout(1500)
          const second = await diagnostics(page)
          const secondCanvas = await page.locator("#game").screenshot()
          assert(second.frames > first.frames, "Actual rendering frames must continue")
          assert(second.tick > first.tick || second.phase !== 0, "Actual game must advance or reach a decision")
          assert.notDeepEqual(firstCanvas, secondCanvas, "Rendered game must change")
          await page.screenshot({ path: path.join(out, `${browserName}-playing.png`) })
          return {
            first,
            second,
            browserVersion: browser.version(),
            visibility: await page.evaluate(() => document.visibilityState)
          }
        })
        await scenario(browserName, "operator pause preserves game and profile", async () => {
          await page.locator("#stream-pause").click()
          const paused = await until(page, (d) => d.paused)
          const pausedActualTick = await page.locator("#game").getAttribute("data-tick")
          await page.waitForTimeout(1800)
          const held = await diagnostics(page)
          assert.equal(
            await page.locator("#game").getAttribute("data-tick"),
            pausedActualTick,
            "Pause must hold actual simulation"
          )
          assert.equal(held.commits, paused.commits, "Pause must hold choice commits")
          assert.equal(held.run, paused.run, "Pause must hold run startup")
          assert(held.frames > paused.frames, "Pause must keep rendering")
          assert.equal(await page.evaluate((key) => localStorage.getItem(key), profileKey), baselineProfile)
          await page.locator("#stream-pause").click()
          await until(page, (d) => !d.paused)
          return { paused, pausedActualTick, held }
        })
        if (headed)
          await scenario(browserName, "real browser hide and explicit resume", async () => {
            assert.equal(await page.evaluate(() => document.visibilityState), "visible")
            await page.evaluate(() => window.dispatchEvent(new Event("blur")))
            assert.equal((await diagnostics(page)).paused, false, "Visible focus loss must not pause stream mode")
            await page.evaluate(() => {
              const link = document.createElement("a")
              link.id = "stream-check-open-tab"
              link.href = "about:blank"
              link.target = "_blank"
              link.textContent = "Open lifecycle check tab"
              document.body.append(link)
            })
            const [other] = await Promise.all([
              page.waitForEvent("popup"),
              page.locator("#stream-check-open-tab").click()
            ])
            try {
              await other.bringToFront()
              await page.waitForFunction(() => document.hidden, null, { polling: 100, timeout: 10000 })
              const hidden = await until(page, (d) => d.paused)
              await page.waitForTimeout(1800)
              const held = await diagnostics(page)
              assert.equal(held.tick, hidden.tick)
              assert.equal(held.commits, hidden.commits)
              await page.bringToFront()
              await page.waitForFunction(() => document.visibilityState === "visible")
              assert.equal((await diagnostics(page)).paused, true, "Returning visible requires explicit resume")
              await page.locator("#stream-pause").click()
              const resumed = await until(page, (d) => !d.paused)
              assert(resumed.tick - held.tick < 60, "Returning visible must not catch up hidden gameplay")
              return {
                hidden,
                held,
                resumed,
                visibleBlurEvent: "synthetic window focus event; actual visibility unchanged",
                hideEvent: "actual browser tab activation"
              }
            } finally {
              await other.close()
              await page.locator("#stream-check-open-tab").evaluate((link) => link.remove())
            }
          })
        await scenario(browserName, "live strategy replacement", async () => {
          const before = await diagnostics(page)
          const expected = await revision(page, "acceptance-reloaded")
          const after = await until(
            page,
            (d) => d.revision.includes(expected.slice(0, 12)) && d.generation > before.generation
          )
          assert.equal(after.session, before.session, "Strategy reload must preserve session")
          assert.equal(after.run, before.run, "Strategy reload must preserve run")
          return { before, after }
        })
        await scenario(browserName, "dependency-only strategy edit", async () => {
          const fixtureDir = path.join(out, browserName + "-strategy-source")
          await mkdir(fixtureDir, { recursive: true })
          const entry = path.join(fixtureDir, "entry.mts")
          const dependency = path.join(fixtureDir, "personality.mts")
          const manifestPath = path.join(fixtureDir, "strategy.json")
          await writeFile(
            entry,
            "import { personality } from './personality.mts';\n" +
              strategySource({ label: "dependency" })
                .replace(
                  "decide(observation, memory)",
                  "decide(observation: BendABI.StreamBot.Observation, memory: unknown)"
                )
                .replace("'dependency'", "personality")
                .replaceAll('"dependency"', "personality")
          )
          async function bundle(personality: string) {
            await writeFile(dependency, "export const personality = " + JSON.stringify(personality) + "\n")
            execFileSync(process.execPath, [strategyBuilder, entry, manifestPath], { encoding: "utf8" })
            const manifest = record(JSON.parse(await readFile(manifestPath, "utf8")))
            return fixture.publish(await readFile(path.join(fixtureDir, text(manifest.module, "module")), "utf8"))
          }
          const first = await bundle("dependency-first")
          await page.locator("#stream-reload").click()
          await until(page, (d) => d.revision.includes(first.slice(0, 12)))
          const before = await diagnostics(page)
          const second = await bundle("dependency-second")
          assert.notEqual(second, first, "Dependency-only edit must produce a new immutable bundle")
          await page.locator("#stream-reload").click()
          const after = await until(page, (d) => d.revision.includes(second.slice(0, 12)))
          assert.equal(after.run, before.run)
          assert.equal(after.session, before.session)
          await page.waitForFunction(() =>
            document.querySelector("#stream-intention")?.textContent?.includes("dependency-second")
          )
          return { first, second, before, after }
        })
        await scenario(browserName, "bounded memory migration", async () => {
          await page.waitForFunction(() =>
            /dependency-second:memory=\d+/.test(document.querySelector("#stream-intention")?.textContent ?? "")
          )
          const previousLabel = await page.locator("#stream-intention").innerText()
          const previousCount = Number(previousLabel.split("memory=")[1])
          const compatible = await revision(page, "compatible-memory")
          const compatibleState = await until(page, (d) => d.revision.includes(compatible.slice(0, 12)))
          await page.waitForFunction(() =>
            /compatible-memory:memory=\d+/.test(document.querySelector("#stream-intention")?.textContent ?? "")
          )
          const preservedLabel = await page.locator("#stream-intention").innerText()
          assert(Number(preservedLabel.split("memory=")[1]) >= previousCount, "Compatible memory must survive reload")
          const incompatible = await revision(page, "incompatible-memory", "healthy", 2)
          const resetState = await until(page, (d) => d.revision.includes(incompatible.slice(0, 12)))
          const firstResetAdvice = await until(page, (d) =>
            d.logs.some((log) => log.event === "advice-accepted" && log.detail === "incompatible-memory:memory=1")
          )
          assert(firstResetAdvice.logs.some((log) => log.detail === "incompatible-memory:memory=1"))
          assert(
            resetState.logs.some((log) => log.event === "memory-reset" && log.detail.endsWith("→ 2")),
            "Incompatible memory reset must be visible"
          )
          return { previousLabel, preservedLabel, compatibleState, resetState }
        })
        await scenario(browserName, "Worker constructor failure reclaims candidate Blob", async () => {
          const before = await diagnostics(page)
          const beforeUrls = await page.evaluate(() => ({
            live: Number(document.documentElement.dataset.checkBlobLive),
            created: Number(document.documentElement.dataset.checkBlobCreated)
          }))
          await page.evaluate(() => {
            document.documentElement.dataset.checkWorkerConstructorFailure = "armed"
          })
          const expected = await revision(page, "constructor-failure")
          const after = await until(page, (d) =>
            d.logs.some((log) => log.event === "candidate-failed" && log.detail.includes("Worker construction failure"))
          )
          const afterUrls = await page.evaluate(() => ({
            live: Number(document.documentElement.dataset.checkBlobLive),
            created: Number(document.documentElement.dataset.checkBlobCreated),
            fault: document.documentElement.dataset.checkWorkerConstructorFailure
          }))
          assert.equal(afterUrls.fault, "observed")
          assert.equal(
            afterUrls.created,
            beforeUrls.created + 1,
            "Constructor failure must occur after a real Blob URL is created"
          )
          assert.equal(afterUrls.live, beforeUrls.live, "Unowned candidate Blob must be revoked on constructor failure")
          assert.equal(after.revision, before.revision)
          const source = after.logs.find((log) => log.event === "candidate-failed" && log.revision === expected)
          assert(source, "Retained candidate failure must keep its own source hash")
          assert.equal(source.originSession, before.session)
          assert.equal(source.originRun, before.run)
          return { before, after, beforeUrls, afterUrls }
        })
        for (const fault of ["syntax", "initialize", "smoke-loop", "malformed"] satisfies StrategyFault[]) {
          await scenario(browserName, `candidate ${fault} preserves active strategy`, async () => {
            const before = await diagnostics(page)
            await revision(page, `candidate-${fault}`, fault)
            const after = await until(page, (d) => d.lastError.length > 0 && d.lastError !== before.lastError, 20000)
            await page.waitForTimeout(1000)
            const settled = await diagnostics(page)
            assert.equal(settled.revision, before.revision, "Broken candidate must not replace healthy strategy")
            assert(settled.frames > before.frames, "Candidate failure must not block frames")
            assert.equal(settled.session, before.session)
            return { before, after, settled }
          })
        }
        for (const fault of ["active-crash", "active-loop", "active-large-error"] satisfies StrategyFault[]) {
          await scenario(browserName, `${fault} activates responsive fallback`, async () => {
            const before = await diagnostics(page)
            if (fault === "active-large-error")
              await page.evaluate(() => {
                document.documentElement.dataset.checkWorkerFailureLength = "0"
              })
            await revision(page, fault, fault)
            await until(page, (d) => d.lastError !== before.lastError && /fallback/i.test(d.status), 30000)
            await page.waitForTimeout(1000)
            const after = await diagnostics(page)
            assert(after.frames > before.frames)
            const failureMessageLength = Number(
              await page.evaluate(() => document.documentElement.dataset.checkWorkerFailureLength ?? "0")
            )
            if (fault === "active-large-error")
              assert(
                failureMessageLength > 0 && failureMessageLength <= 500,
                `Actual Worker failure payload must be bounded before host clipping; received ${failureMessageLength} code units`
              )
            const expected = await revision(page, `recovered-${fault}`)
            await until(page, (d) => d.revision.includes(expected.slice(0, 12)), 30000)
            return { before, after, failureMessageLength }
          })
        }
        await scenario(browserName, "rapid reload burst retires obsolete generations", async () => {
          let finalHash = ""
          for (let index = 0; index < 5; index++) finalHash = await revision(page, "burst-" + index)
          const active = await until(page, (d) => d.revision.includes(finalHash.slice(0, 12)))
          const activatedAt = active.logs.filter((log) => log.event === "activated").at(-1)?.at ?? -1
          await page.waitForFunction(() =>
            document.querySelector("#stream-intention")?.textContent?.startsWith("burst-4:")
          )
          await page.waitForTimeout(600)
          const settled = await diagnostics(page)
          assert.equal(settled.revision, active.revision)
          assert(
            settled.logs
              .filter((log) => log.event === "advice-accepted" && log.at > activatedAt)
              .every((log) => log.detail.startsWith("burst-4:")),
            "Retired generations cannot supply accepted advice after final activation"
          )
          return { active, settled }
        })
        await scenario(browserName, "real upgrade recommendation and dwell", async () => {
          const delayed = await revision(page, "delayed-upgrade", "delayed")
          await until(page, (d) => d.revision.includes(delayed.slice(0, 12)))
          const previousUpgradeTick = await page.evaluate(() => document.documentElement.dataset.checkUpgradeTick ?? "")
          const beforeUpgrade = await diagnostics(page)
          const previousEventAt = beforeUpgrade.logs.at(-1)?.at ?? -1
          await page.waitForFunction(
            (previous) => {
              const data = document.documentElement.dataset
              if (
                !data.checkUpgradeTick ||
                data.checkUpgradeTick === previous ||
                !(performance.now() - Number(data.checkUpgradeSentAt) < 150)
              )
                return false
              document.querySelector<HTMLButtonElement>("#stream-pause")?.click()
              return true
            },
            previousUpgradeTick,
            { polling: 10, timeout: 180000 }
          )
          const upgradeTick = Number(await page.evaluate(() => document.documentElement.dataset.checkUpgradeTick))
          const originalIdentity = record(
            JSON.parse((await page.evaluate(() => document.documentElement.dataset.checkUpgradeIdentity)) ?? "null")
          )
          await until(page, (d) => d.paused)
          await page.locator("#stream-pause").click()
          await until(page, (d) => !d.paused)
          const overlapped = await until(
            page,
            (d) =>
              d.logs.some((log) => log.event === "obsolete-advice" && log.at > previousEventAt) &&
              d.logs.some(
                (log) =>
                  log.event === "advice-accepted" &&
                  log.detail.startsWith("delayed-upgrade:") &&
                  log.tick === upgradeTick
              ),
            10000
          )
          const obsolete = overlapped.logs.find(
            (log) => log.event === "obsolete-advice" && log.request === originalIdentity.request
          )
          assert(obsolete, "Actual old pending reply must be rejected after pause/resume")
          assert.equal(obsolete.revision, delayed)
          assert.equal(obsolete.originSession, originalIdentity.session)
          assert.equal(obsolete.originRun, originalIdentity.run)
          const frozen = await until(page, (d) => /dwell/i.test(d.mode), 10000)
          assert.equal(
            await page.locator("#dialog .stream-recommendation").count(),
            1,
            "One actual offered card must be highlighted"
          )
          const recommendedOffer = await page.locator("#dialog .stream-recommendation").getAttribute("data-choice")
          const suppliedUpgrade = await page.evaluate(() => ({
            fallback: Number(document.documentElement.dataset.checkUpgradeFallback),
            count: Number(document.documentElement.dataset.checkUpgradeOfferCount),
            tick: Number(document.documentElement.dataset.checkUpgradeTick)
          }))
          assert(suppliedUpgrade.count > 1, "Counterfactual upgrade check needs multiple actual legal offers")
          assert.equal(suppliedUpgrade.tick, frozen.tick, "Observed strategy input must belong to current upgrade")
          const expectedOffer = suppliedUpgrade.fallback === 0 ? 1 : 0
          assert(
            frozen.logs.some(
              (log) =>
                log.event === "advice-accepted" &&
                log.intention?.$ === "UpgradeChoice" &&
                log.intention.index === expectedOffer
            ),
            "Accepted external upgrade journal must retain actual intention and index"
          )
          assert.equal(Number(recommendedOffer), expectedOffer, "The external choice must differ from Bend fallback")
          const began = performance.now()
          const frozenSeenAt = await page.evaluate(() => performance.now())
          const frames = frozen.frames
          const nextRevision = await revision(page, "dwell-replacement")
          await page.locator("#stream-pause").click()
          const paused = await until(page, (d) => d.paused)
          const pauseBegan = performance.now()
          await page.waitForTimeout(1800)
          const held = await diagnostics(page)
          assert.equal(held.commits, paused.commits, "Pause during dwell must not confirm")
          assert.equal(held.revision, frozen.revision, "Reload activation must wait for frozen recommendation")
          await page.locator("#stream-pause").click()
          await until(page, (d) => !d.paused)
          const pausedMs = performance.now() - pauseBegan
          await page.screenshot({ path: path.join(out, `${browserName}-recommendation.png`) })
          const committed = await until(page, (d) => d.commits > frozen.commits, 10000)
          const timeline: unknown = JSON.parse(
            (await page.evaluate(() => document.documentElement.dataset.checkRecommendationSpans)) ?? "[]"
          )
          assert(Array.isArray(timeline), "Recommendation DOM timeline missing")
          const span = timeline
            .map(record)
            .findLast(
              (entry) =>
                entry.index === recommendedOffer && typeof entry.endedAt === "number" && entry.endedAt >= frozenSeenAt
            )
          assert(span, "Actual recommendation appearance/removal must be observed")
          assert(
            typeof span.frozenAt === "number",
            "Frozen UI boundary must be observed independently from delayed diagnostics"
          )
          assert(
            number(span.activeMs, "recommendation active span") >= 1500 - 34,
            "Actual recommendation must remain selected for configured dwell minus one 30FPS frame"
          )
          assert(
            number(span.frozenActiveMs, "frozen recommendation active span") >= 1500 - 34,
            "Frozen UI recommendation must retain configured active dwell minus one 30FPS frame"
          )
          assert.equal(committed.commits, frozen.commits + 1, "One offered choice must commit once")
          assert.equal(
            committed.logs.filter((log) => log.event === "commit").at(-1)?.detail,
            String(expectedOffer),
            "The highlighted external choice must actually commit"
          )
          assert(committed.frames > frames, "Actual frames must continue through dwell")
          await until(page, (d) => d.revision.includes(nextRevision.slice(0, 12)), 10000)
          return {
            beforeUpgrade,
            upgradeTick,
            overlapped,
            frozen,
            recommendedOffer,
            suppliedUpgrade,
            paused,
            held,
            committed,
            observedActiveDwellMs: performance.now() - began - pausedMs,
            observedDomSpan: span,
            originalIdentity
          }
        })
        await scenario(browserName, "stop and fresh restart", async () => {
          const before = await diagnostics(page)
          await revision(page, "stopped-preparation", "smoke-loop")
          await page.locator("#stream-stop").click()
          const stopped = await until(page, (d) => /stop/i.test(d.mode))
          const audioNodes = await page.evaluate(() => document.documentElement.dataset.checkAudioNodes)
          await page.waitForTimeout(2200)
          const held = await diagnostics(page)
          assert.equal(held.tick, stopped.tick)
          assert.equal(held.commits, stopped.commits)
          assert.equal(held.run, stopped.run)
          assert.equal(
            await page.evaluate(() => document.documentElement.dataset.checkAudioNodes),
            audioNodes,
            "Stopped session must not schedule new sound"
          )
          const stoppedPcmPeak = Number(
            await page.evaluate(() => document.documentElement.dataset.checkAudioRecentPcmPeak)
          )
          assert(stoppedPcmPeak < 0.00001, "Actual master signal must be silent after stop")
          fixture.publish(strategySource({ label: "after-stop" }))
          await page.locator("#stream-start").click()
          const restarted = await until(page, (d) => d.session !== before.session && d.tick > 0, 30000)
          return { before, stopped, held, restarted }
        })
      }
      if (!soakOnly)
        await scenario(browserName, "initial strategy failure and explicit recovery", async () => {
          await page.locator("#stream-stop").click()
          fixture.publish(strategySource({ label: "initial-broken", fault: "syntax" }))
          await page.locator("#stream-start").click()
          const failed = await until(
            page,
            (d) => d.tick > 5 && d.status === "fallback" && d.lastError.length > 0,
            30000
          )
          const expected = await revision(page, "initial-recovered")
          const recovered = await until(page, (d) => d.revision.includes(expected.slice(0, 12)))
          assert.equal(recovered.session, failed.session)
          assert.equal(recovered.run, failed.run)
          assert(recovered.frames > failed.frames)
          return { failed, recovered }
        })
      if (soakHours > 0) {
        const durationMs = soakHours * 3600000
        const began = performance.now()
        const limits = {
          maxProbeGapMs: 15000,
          maxSimulationGapMs: 15000,
          maxWorkers: 3,
          maxLogEntries: 256,
          maxBrowserRssBytes: 2147483648,
          maxRssGrowthBytes: 536870912,
          warmupMs: 900000,
          minRuns: 2,
          minVerifiedRotationsPerKind: 2,
          durationMs
        }
        await writeFile(
          path.join(out, `${browserName}-soak-contract.json`),
          JSON.stringify(
            {
              started: new Date().toISOString(),
              limits,
              browserVersion: browser.version(),
              launch: runtime.launch,
              sourceIdentity,
              capture: `Playwright screenshots in a visible ${headed ? "headed" : "headless"} page; no hidden-tab throttling overrides`
            },
            null,
            2
          )
        )
        let previous = await diagnostics(page)
        let health = initialHealth(previous, performance.now())
        let iterations = 0
        let runChanges = 0
        let automaticRunChanges = 0
        let transitionPauseVerified = false
        let transitionStopVerified = false
        let reloads = 0
        const verifiedRotations = { healthy: 0, rejected: 0, recovered: 0 }
        let baselineRss: number | undefined
        let maxRss = 0
        while (performance.now() - began < durationMs) {
          await page.waitForTimeout(1000)
          let current = await boundedProbe(diagnostics(page), limits.maxProbeGapMs)
          if (current.mode === "BetweenRuns" && !transitionPauseVerified) {
            await page.locator("#stream-pause").click()
            const paused = await until(page, (d) => d.paused)
            await page.waitForTimeout(2500)
            const held = await diagnostics(page)
            assert.equal(held.run, paused.run, "Between-run pause must prevent next run")
            assert.equal(held.commits, paused.commits)
            await page.locator("#stream-pause").click()
            await until(page, (d) => !d.paused)
            transitionPauseVerified = true
            current = await diagnostics(page)
          } else if (current.mode === "BetweenRuns" && automaticRunChanges > 0 && !transitionStopVerified) {
            await page.locator("#stream-stop").click()
            const stopped = await until(page, (d) => d.mode === "Stopped")
            await page.waitForTimeout(2500)
            const held = await diagnostics(page)
            assert.equal(held.run, stopped.run, "Between-run stop must prevent next run")
            assert.equal(held.commits, stopped.commits)
            const session = held.session
            fixture.publish(strategySource({ label: "soak-after-transition-stop" }))
            await page.locator("#stream-start").click()
            current = await until(page, (d) => d.session !== session && d.tick > 0)
            transitionStopVerified = true
          }
          health = observeProgress(health, current, performance.now(), limits)
          assert.equal(current.paused, false, "Foreground soak unexpectedly paused")
          assert(current.logs.length <= limits.maxLogEntries, "Session log exceeded predeclared limit")
          assert(maxWorkers <= limits.maxWorkers, "Owned Worker count exceeded predeclared limit")
          if (current.run !== previous.run) {
            runChanges++
            if (current.session === previous.session) automaticRunChanges++
          }
          if (++iterations % 60 === 0) {
            const currentSource: unknown = JSON.parse(await readFile(path.join(snapshotRoot, "version.json"), "utf8"))
            assert.deepEqual(currentSource, sourceIdentity, "Served build changed during soak")
            const before = await diagnostics(page)
            const lastEventAt = before.logs.at(-1)?.at ?? -1
            const label = "soak-" + reloads
            const fault = reloads % 3 === 1 ? "syntax" : reloads % 3 === 2 ? "active-crash" : "healthy"
            const expected = await revision(page, label, fault)
            let outcome: Diagnostics
            if (fault === "healthy") {
              outcome = await until(
                page,
                (d) =>
                  d.revision.includes(expected.slice(0, 12)) &&
                  d.logs.some((log) => log.event === "advice-accepted" && log.detail.startsWith(label)),
                10000
              )
              verifiedRotations.healthy++
            } else if (fault === "syntax") {
              outcome = await until(
                page,
                (d) => d.logs.some((log) => log.event === "candidate-failed" && log.at > lastEventAt),
                10000
              )
              assert.equal(outcome.revision, before.revision, "Soak rejected candidate must preserve working strategy")
              assert.equal(outcome.status, "active", "Soak rejected candidate must leave healthy strategy active")
              verifiedRotations.rejected++
            } else {
              await until(
                page,
                (d) =>
                  d.status === "fallback" &&
                  d.logs.some((log) => log.event === "active-failed" && log.at > lastEventAt),
                10000
              )
              const recovered = await revision(page, label + "-recovered")
              outcome = await until(
                page,
                (d) =>
                  d.revision.includes(recovered.slice(0, 12)) &&
                  d.logs.some((log) => log.event === "advice-accepted" && log.detail.startsWith(label + "-recovered")),
                10000
              )
              verifiedRotations.recovered++
            }
            await appendFile(
              path.join(out, browserName + "-soak-rotations.jsonl"),
              JSON.stringify({
                elapsedMs: performance.now() - began,
                fault,
                expected,
                outcome: {
                  revision: outcome.revision,
                  generation: outcome.generation,
                  status: outcome.status,
                  run: outcome.run,
                  session: outcome.session,
                  tick: outcome.tick,
                  frames: outcome.frames
                },
                verifiedRotations
              }) + "\n"
            )
            reloads++
          }
          if (iterations % 15 === 0) {
            const visibility = await page.evaluate(() => document.visibilityState)
            assert.equal(visibility, "visible", "Soak page must remain foreground-visible")
            const rss = browserRss(browserPid)
            assert(rss > 0, "Browser process memory sample is missing")
            maxRss = Math.max(maxRss, rss)
            assert(rss <= limits.maxBrowserRssBytes, "Browser RSS exceeded predeclared absolute limit")
            if (performance.now() - began >= limits.warmupMs) {
              baselineRss ??= rss
              assert(rss - baselineRss <= limits.maxRssGrowthBytes, "Browser RSS exceeded post-warmup growth limit")
            }
            await appendFile(
              path.join(out, `${browserName}-soak-samples.jsonl`),
              JSON.stringify({
                elapsedMs: performance.now() - began,
                session: current.session,
                run: current.run,
                tick: current.tick,
                phase: current.phase,
                mode: current.mode,
                frames: current.frames,
                commits: current.commits,
                status: current.status,
                generation: current.generation,
                revision: current.revision,
                workers,
                visibility,
                rss
              }) + "\n"
            )
            const checkpoint = {
              elapsedMs: performance.now() - began,
              current,
              workers,
              maxWorkers,
              runChanges,
              automaticRunChanges,
              transitionPauseVerified,
              transitionStopVerified,
              reloads,
              pageErrors,
              rss,
              baselineRss,
              maxRss,
              verifiedRotations,
              limits
            }
            await writeFile(
              path.join(out, `${browserName}-soak-checkpoint.json.tmp`),
              JSON.stringify(checkpoint, null, 2)
            )
            await rename(
              path.join(out, `${browserName}-soak-checkpoint.json.tmp`),
              path.join(out, `${browserName}-soak-checkpoint.json`)
            )
          }
          if (iterations % 900 === 0)
            await page.screenshot({ path: path.join(out, `${browserName}-soak-${iterations}.png`) })
          previous = current
        }
        const finalProbe = await boundedProbe(diagnostics(page), limits.maxProbeGapMs)
        health = observeProgress(health, finalProbe, performance.now(), limits)
        previous = finalProbe
        assert(
          soakHours < 24 || automaticRunChanges + 1 >= limits.minRuns,
          "24h qualification requires multiple automatic runs"
        )
        assert(
          soakHours < 24 ||
            Object.values(verifiedRotations).every((count) => count >= limits.minVerifiedRotationsPerKind),
          "24h qualification requires repeated verified strategy reload, rejection and recovery"
        )
        assert(
          soakHours < 24 || (transitionPauseVerified && transitionStopVerified),
          "24h qualification requires real between-run pause and stop checks"
        )
        results.push({
          browser: browserName,
          scenario: "foreground soak",
          elapsedMs: performance.now() - began,
          evidence: {
            qualified24h: soakHours >= 24,
            runChanges,
            automaticRunChanges,
            transitionPauseVerified,
            transitionStopVerified,
            reloads,
            maxWorkers,
            baselineRss,
            maxRss,
            verifiedRotations,
            last: previous,
            limits
          }
        })
        await report()
      }
      if (!soakOnly && !audioOnly) {
        await scenario(browserName, "ordinary browser player regression", async () => {
          await page.locator("#stream-stop").click()
          assert.equal(await page.evaluate((key) => localStorage.getItem(key), profileKey), baselineProfile)
          await page.goto(fixture.url)
          await page.locator("#start-top").click()
          await page.waitForFunction(
            () => Number(document.querySelector<HTMLCanvasElement>("#game")?.dataset.tick) > 0,
            null,
            { timeout: 120000 }
          )
          const before = await page.locator("#game").getAttribute("data-player-x")
          await page.keyboard.down("KeyD")
          await page.waitForTimeout(1200)
          await page.keyboard.up("KeyD")
          const after = await page.locator("#game").getAttribute("data-player-x")
          assert(Number(after) > Number(before), "Normal player movement must still work")
          await page.evaluate(() => window.dispatchEvent(new Event("blur")))
          await page.waitForTimeout(300)
          const pausedTick = await page.locator("#game").getAttribute("data-tick")
          await page.waitForTimeout(1000)
          assert.equal(
            await page.locator("#game").getAttribute("data-tick"),
            pausedTick,
            "Normal blur must still pause"
          )
          await page.locator("#resume").click()
          await page.waitForTimeout(500)
          assert(Number(await page.locator("#game").getAttribute("data-tick")) > Number(pausedTick))
          return {
            before,
            after,
            pausedTick,
            audio: await page.evaluate(() => ({
              checkAudioContexts: document.documentElement.dataset.checkAudioContexts,
              checkAudioState: document.documentElement.dataset.checkAudioState,
              checkAudioNodes: document.documentElement.dataset.checkAudioNodes
            }))
          }
        })
      }
      assert.deepEqual(pageErrors, [], "Unexpected page errors")
      assert.equal(
        await page.evaluate((key) => localStorage.getItem(key), profileKey),
        baselineProfile,
        "Stream must preserve normal profile"
      )
    } finally {
      const finalDiagnostics = (await page.locator("#stream-diagnostics").count())
        ? await diagnostics(page).catch(() => null)
        : null
      const observedBoundaries = await page
        .evaluate(() => ({
          failureMessageLength: Number(document.documentElement.dataset.checkWorkerFailureLength ?? "0"),
          audioContexts: document.documentElement.dataset.checkAudioContexts,
          audioNodes: document.documentElement.dataset.checkAudioNodes,
          audioState: document.documentElement.dataset.checkAudioState,
          visibility: document.visibilityState
        }))
        .catch(() => null)
      await writeFile(
        path.join(out, `${browserName}-final-observations.json`),
        JSON.stringify({ finalDiagnostics, observedBoundaries }, null, 2)
      )
      await page.screenshot({ path: path.join(out, `${browserName}-final.png`) }).catch(() => {})
    }
  } finally {
    await runtime.close()
  }
}
try {
  for (const kind of selectedBrowser === "both"
    ? [chromium, webkit]
    : selectedBrowser === "webkit"
      ? [webkit]
      : [chromium])
    await runBrowser(kind)
} catch (error) {
  errors.push(error instanceof Error ? (error.stack ?? error.message) : String(error))
  process.stderr.write(`${errors.at(-1)}\n`)
  process.exitCode = 1
} finally {
  try {
    assert.deepEqual(
      await applicationManifest(snapshotRoot),
      application.files,
      "Served diagnostic snapshot changed during run"
    )
  } catch (error) {
    errors.push(error instanceof Error ? (error.stack ?? error.message) : String(error))
    process.exitCode = 1
  }
  try {
    await report()
  } finally {
    await fixture.close()
  }
}
