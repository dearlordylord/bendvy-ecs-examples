import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises"
import { resolve, relative } from "node:path"
import { chromium, type Page } from "playwright"
import { authorityLag, inputCoverage, motionOracle } from "./coop-motion-oracle.mts"
import type { Role, Trace } from "./coop-browser-trace.mts"
import { defined, errorMessage } from "../../examples/survivors/host-values.mts"

const base = process.env.COOP_URL ?? "http://127.0.0.1:8723/coop.html"
const artifact = resolve(process.env.COOP_SOURCE_ARTIFACT_DIR ?? "examples/survivors/dist/web")
const output = process.env.COOP_QA_DIR ?? "/tmp/coop-transport-qualification"
const duration = Number(process.env.COOP_DURATION_MS ?? 32000)
const observationDelay = Number(process.env.COOP_OBSERVATION_DELAY_MS ?? 300)
const seed = Number(process.env.COOP_TEST_SEED ?? 1729)
const delays = (process.env.COOP_SEND_COMPLETION_MS ?? "0,200,600").split(",").map(Number)
assert.ok(Number.isInteger(seed) && seed >= 0 && seed <= 4294967295)
assert.ok(duration >= 30000 && observationDelay >= 0)
assert.ok(delays.length > 0 && delays.every((delay) => Number.isFinite(delay) && delay >= 0))
await mkdir(output, { recursive: true })
const files = (await readdir(artifact, { recursive: true, withFileTypes: true }))
  .filter((entry) => entry.isFile())
  .map((entry) => relative(artifact, resolve(entry.parentPath, entry.name)))
  .sort()
const digest = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex")
const expectedHashes = Object.fromEntries<string>(
  await Promise.all(
    files.map(async (file) => [file, digest(await readFile(resolve(artifact, file)))] satisfies [string, string])
  )
)
async function source() {
  const hashes: Record<string, string> = {}
  for (const file of files) {
    const response = await fetch(new URL(file, base), { cache: "no-store" })
    assert.equal(response.status, 200, file)
    hashes[file] = digest(new Uint8Array(await response.arrayBuffer()))
  }
  return hashes
}
function replaceRequired(source: string, marker: string, replacement: string, label: string) {
  assert.equal(source.split(marker).length, 2, `Expected one ${label} hook`)
  return source.replace(marker, replacement)
}
async function instrument(page: Page, role: Role, delay: number, errors: string[]) {
  page.on("pageerror", (error) => errors.push(`${role}: ${error.message}`))
  page.on("console", (message) => {
    if (message.type() === "error" && !message.location().url.endsWith("/favicon.ico"))
      errors.push(`${role}: ${message.text()}`)
  })
  await page.addInitScript((selectedSeed) => {
    const trace: Trace = (globalThis.__transportQualification = {
      workerInitializations: [],
      workerErrors: [],
      inputResolutions: [],
      renders: [],
      nativeSends: [],
      transportStates: [],
      lastFrame: null
    })
    globalThis.__transportQualificationDraw = (frame) => {
      trace.renders.push({
        wall: Date.now(),
        tick: frame.tick,
        phase: frame.phase,
        round: frame.roundId ?? 0,
        runId: frame.runId ?? "",
        choicePending: frame.choicePending ?? false,
        remotePresentation: frame.remotePresentation,
        players: frame.players,
        enemies: frame.enemies.slice(0, 16).map(({ x, y, lifetime }) => ({ x, y, lifetime }))
      })
      if (trace.renders.length > 5000) trace.renders.shift()
    }
    const NativeWorker = Worker
    globalThis.Worker = class extends NativeWorker {
      constructor(...args: ConstructorParameters<typeof Worker>) {
        super(...args)
        this.addEventListener("message", (event: MessageEvent<unknown>) => {
          const value = event.data
          if (typeof value !== "object" || value === null || !("type" in value)) return
          if (value.type === "error") trace.workerErrors.push(JSON.stringify(value))
          if (value.type === "qualification-input" && "row" in value) {
            const row = value.row
            if (typeof row !== "object" || row === null) throw Error("Invalid input observation")
            if (
              !("wall" in row) ||
              typeof row.wall !== "number" ||
              !("worldTick" in row) ||
              typeof row.worldTick !== "number" ||
              !("phase" in row) ||
              typeof row.phase !== "number" ||
              !("round" in row) ||
              typeof row.round !== "number" ||
              !("eligible" in row) ||
              typeof row.eligible !== "boolean" ||
              !("applied" in row) ||
              typeof row.applied !== "boolean" ||
              !("x" in row) ||
              typeof row.x !== "number" ||
              !("y" in row) ||
              typeof row.y !== "number" ||
              !("seq" in row) ||
              typeof row.seq !== "number"
            )
              throw Error("Invalid input observation fields")
            trace.inputResolutions.push({
              wall: row.wall,
              worldTick: row.worldTick,
              phase: row.phase,
              round: row.round,
              eligible: row.eligible,
              applied: row.applied,
              x: row.x,
              y: row.y,
              seq: row.seq
            })
          }
        })
        this.addEventListener("error", (event) => trace.workerErrors.push(event.message))
      }
      override postMessage(message: unknown, options: Transferable[] | StructuredSerializeOptions = []) {
        if (
          typeof message === "object" &&
          message !== null &&
          "type" in message &&
          message.type === "init" &&
          "seed" in message &&
          typeof message.seed === "number"
        ) {
          trace.workerInitializations.push({ requestedSeed: message.seed, seed: selectedSeed })
          message = { ...message, seed: selectedSeed }
        }
        if (Array.isArray(options)) super.postMessage(message, options)
        else super.postMessage(message, options)
      }
    }
  }, seed)
  if (role === "host")
    await page.route("**/coop-worker.mjs", async (route) => {
      const response = await route.fetch(),
        source = await response.text()
      const marker = "peer.session = Session.applied(frame.tick, peer.session);"
      const body = replaceRequired(
        source,
        marker,
        marker +
          `
      if(peer.player===1){const receipt=InputQueue.receipt(frame.tick,taken.tick);postMessage({type:'qualification-input',row:{wall:Date.now(),worldTick:frame.tick,phase:frame.phase,round:currentRound,eligible:peer.eligible,applied:receipt.applied,x:receipt.x,y:receipt.y,seq:receipt.seq}});}
    `,
        "advanced worker input"
      )
      await route.fulfill({ response, body })
    })
  await page.route("**/coop-ui.mjs", async (route) => {
    const response = await route.fetch(),
      source = await response.text()
    const marker = "this.frame = frame;"
    const body = replaceRequired(
      source,
      marker,
      marker +
        `globalThis.__transportQualification.lastFrame={wall:Date.now(),tick:frame.tick,phase:frame.phase,round:frame.roundId??0,runId:frame.runId??'',choicePending:frame.choicePending??false};`,
      "presented frame"
    )
    await route.fulfill({ response, body })
  })
  await page.route("**/renderer.mjs", async (route) => {
    const response = await route.fetch(),
      source = await response.text()
    const marker = "draw(frame, dt = 1 / 60, options = {}) {"
    await route.fulfill({
      response,
      body: replaceRequired(
        source,
        marker,
        marker + "globalThis.__transportQualificationDraw(frame);",
        "rendered frame"
      )
    })
  })
  await page.route("**/iroh/iroh_transport.js", async (route) => {
    const response = await route.fetch(),
      source = await response.text()
    await route.fulfill({
      response,
      body:
        source +
        `
      const qualificationSend=Transport.prototype.send;
      Transport.prototype.send=async function(bytes,...args){
        ${role === "guest" && delay > 0 ? `await new Promise(resolve=>setTimeout(resolve,${delay}));` : ""}
        const start=Date.now();try{return await qualificationSend.call(this,bytes,...args);}
        finally{globalThis.__transportQualification.nativeSends.push({start,end:Date.now(),byteLength:bytes.byteLength,confirmDelivery:!!args[0]});}
      };
    `
    })
  })
  await page.route("**/coop-transport.mjs", async (route) => {
    const response = await route.fetch(),
      source = await response.text()
    await route.fulfill({
      response,
      body:
        source +
        `
      const qualificationCreate=CoopTransport.create;
      CoopTransport.create=function(callback,...args){return qualificationCreate.call(this,event=>{
        const state=event.state;if(!state||!Number.isFinite(state.pendingSends)||!Number.isFinite(state.pendingBytes))throw Error('Missing transport queue observation');
        const rows=globalThis.__transportQualification.transportStates;rows.push({pendingSends:state.pendingSends,pendingBytes:state.pendingBytes});if(rows.length>5000)rows.shift();
        ${role === "guest" ? `if(event.type==='message')setTimeout(()=>callback(event),${observationDelay});else callback(event);` : `callback(event);`}
      },...args);};
    `
    })
  })
}
async function join(page: Page) {
  await page.getByRole("button", { name: "Join party", exact: true }).click()
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
const summaries = []
let failures = 0
try {
  for (const delay of delays) {
    console.log(JSON.stringify({ delay, stage: "starting" }))
    const context = await browser.newContext({ viewport: { width: 1000, height: 700 } })
    const host = await context.newPage(),
      guest = await context.newPage(),
      errors: string[] = []
    try {
      assert.deepEqual(await source(), expectedHashes, "served artifact must match frozen source before scenario")
      await instrument(host, "host", 0, errors)
      await instrument(guest, "guest", delay, errors)
      await host.goto(base)
      await host.locator("#coop-host").click()
      await host.waitForFunction(
        () => document.querySelector<HTMLInputElement>("#coop-invite-link")?.value.includes("join="),
        null,
        { timeout: 90000 }
      )
      const invitation = await host.locator("#coop-invite-link").inputValue()
      await host.locator("#coop-invite-close").click()
      await guest.goto(invitation)
      await join(guest)
      await host.waitForFunction(
        () => document.querySelectorAll('#coop-party-roster [data-ready="true"]').length === 2,
        null,
        { timeout: 90000 }
      )
      await host.locator("#coop-start").click()
      for (const page of [host, guest])
        await page.waitForFunction(() => (globalThis.__transportQualification.lastFrame?.tick ?? 0) > 0, null, {
          timeout: 90000
        })
      console.log(JSON.stringify({ delay, stage: "running" }))
      const start = Date.now()
      let previousDirection: string | undefined
      while (Date.now() - start < duration) {
        const direction = Math.floor((Date.now() - start) / 3000) % 2 ? "ArrowLeft" : "ArrowRight"
        for (const [role, page] of [
          ["host", host],
          ["guest", guest]
        ] as const) {
          const choice = page.locator('[data-choice="0"]')
          if (await choice.isVisible()) {
            const prior = await page.evaluate(() => globalThis.__transportQualification.lastFrame)
            await choice.click()
            await page.waitForFunction(
              (round) =>
                globalThis.__transportQualification.lastFrame?.round !== round ||
                globalThis.__transportQualification.lastFrame?.choicePending === false,
              defined(prior).round,
              { timeout: 15000 }
            )
          }
          if (direction !== previousDirection) {
            await page.keyboard.up("ArrowLeft")
            await page.keyboard.up("ArrowRight")
          }
          await page.keyboard.down(
            role === "host" ? direction : direction === "ArrowRight" ? "ArrowLeft" : "ArrowRight"
          )
        }
        previousDirection = direction
        await guest.waitForTimeout(250)
      }
      for (const page of [host, guest]) {
        await page.keyboard.up("ArrowLeft")
        await page.keyboard.up("ArrowRight")
      }
      const hostTrace = await host.evaluate(() => globalThis.__transportQualification)
      const guestTrace = await guest.evaluate(() => globalThis.__transportQualification)
      const lag = authorityLag(hostTrace.inputResolutions, guestTrace.renders, start)
      const motion = motionOracle(guestTrace.renders, start)
      const coverage = inputCoverage(hostTrace.inputResolutions)
      await writeFile(
        resolve(output, `measured-${delay}.json`),
        JSON.stringify({
          delay,
          observationDelay,
          seed,
          duration,
          lag,
          motion,
          coverage,
          errors,
          host: hostTrace,
          guest: guestTrace,
          sourceHashes: expectedHashes
        })
      )
      console.log(JSON.stringify({ delay, stage: "measured", lag, motion: motion.host, coverage, errors }))
      summaries.push({ delay, lag, motion: motion.host, coverage })
      assert.deepEqual(errors, [])
      assert.deepEqual(hostTrace.workerErrors, [])
      assert.deepEqual(guestTrace.workerErrors, [])
      for (const trace of [hostTrace, guestTrace]) {
        assert.ok(trace.transportStates.length > 0, "transport queue bounds are observed")
        assert.ok(
          trace.transportStates.every(
            (state) =>
              Number.isInteger(state.pendingSends) &&
              state.pendingSends >= 0 &&
              state.pendingSends <= 16 &&
              Number.isInteger(state.pendingBytes) &&
              state.pendingBytes >= 0 &&
              state.pendingBytes <= 4 * 1024 * 1024
          ),
          "transport pending work stays within 16 messages and 4 MiB"
        )
        assert.ok(
          trace.nativeSends.every((send) => send.byteLength <= 1024 * 1024),
          "native messages stay within 1 MiB"
        )
      }
      assert.ok(
        hostTrace.nativeSends.length > 0 && guestTrace.nativeSends.length > 0,
        "real native send outcomes observed"
      )
      assert.ok(
        hostTrace.workerInitializations.every((row) => row.seed === seed),
        "fixed host worker seed"
      )
      if (delay === 0 || delay === 200) {
        assert.ok(coverage.nonneutralAppliedSteps > 0, "nonneutral guest input applies")
        assert.ok(coverage.appliedRatio >= 0.5, "at least half eligible gameplay steps apply guest input")
        assert.ok(motion.host.samples >= 100, "remote-host motion has 100 post-warmup pairs")
        assert.equal(
          motion.host.violationCount,
          0,
          "remote-host motion stays within 4 units/wall-tick plus 1 tolerance"
        )
        assert.ok(lag.activePhaseZeroMs >= 15000, "lag includes sustained active gameplay")
        assert.ok(lag.measuredMs >= 10000 && lag.samples >= 100, "lag has post-warmup gameplay samples")
        assert.ok(lag.maxTicks <= 60, "maximum lag is at most 60 ticks")
        assert.ok(lag.p95Ticks <= 30, "p95 lag is at most 30 ticks")
        assert.ok(
          lag.windows.every((window) => window.maxTicks <= 60 && window.p95Ticks <= 30),
          "every five-second active window meets lag bounds"
        )
      }
      assert.ok((hostTrace.lastFrame?.tick ?? 0) > 100 && (guestTrace.lastFrame?.tick ?? 0) > 100, "both roles advance")
      const beforeReload = defined(hostTrace.lastFrame).tick
      const reserved = guest.url()
      await guest.reload()
      await host.waitForFunction(
        () => document.querySelector("#coop-play-status")?.textContent.includes("paused"),
        null,
        { timeout: 15000 }
      )
      await join(guest)
      await guest.waitForFunction(
        (tick) => (globalThis.__transportQualification.lastFrame?.tick ?? 0) >= tick,
        beforeReload,
        { timeout: 90000 }
      )
      assert.equal(guest.url(), reserved, "reconnect preserves reserved-seat invitation")
      assert.deepEqual(await source(), expectedHashes, "served artifact remains identical after scenario")
      const summary = {
        delay,
        observationDelay,
        seed,
        duration,
        qualification: delay <= 200 ? "interactive-regression" : "bounded-overload-only",
        lag,
        motion,
        coverage,
        errors,
        host: hostTrace,
        guest: guestTrace,
        beforeReload,
        rejoined: await guest.evaluate(() => globalThis.__transportQualification.lastFrame),
        sourceHashes: expectedHashes,
        unavailableMetrics: [
          "snapshot application receipt latency and input rejection counts are not collected by this harness"
        ]
      }
      await writeFile(resolve(output, `completion-${delay}.json`), JSON.stringify(summary))
      console.log(JSON.stringify({ delay, lag, motion: motion.host, coverage, errors }))
    } catch (error) {
      await writeFile(
        resolve(output, `failure-${delay}.json`),
        JSON.stringify({
          message: errorMessage(error),
          errors,
          host: await host.evaluate(() => globalThis.__transportQualification).catch(() => null),
          guest: await guest.evaluate(() => globalThis.__transportQualification).catch(() => null)
        })
      )
      failures++
      console.error(JSON.stringify({ delay, stage: "failed", message: errorMessage(error) }))
    } finally {
      await context.close()
    }
  }
  await writeFile(
    resolve(output, "summary.json"),
    JSON.stringify({ kind: "fixed-input actual-Iroh qualification", failures, summaries }, null, 2)
  )
  assert.equal(failures, 0, "Every requested qualification case must pass")
} finally {
  await browser.close()
}
