import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { chromium } from "playwright"
import type { NativeEvent, TransportEvent, TransportIO } from "./coop-transport.mts"
import type * as FacadeModule from "./coop-transport.mts"

type NativeFact = { type: string; offerId?: number }
interface NativeSlot {
  native?: object
  facts: NativeFact[]
  messages: number
  connectedAt: number
  disconnectedAt: number
  closedAt: number
  operation: number
  errors: string[]
}
interface Probe {
  slots: NativeSlot[]
  method(owner: object, name: string, ...args: unknown[]): unknown
  create(accept: boolean): Promise<number>
  until(predicate: () => boolean): Promise<void>
}
declare global {
  var watchdogProbe: Probe
  var retryFacade: typeof FacadeModule | undefined
  var retryNative: { default(): Promise<unknown>; Transport: Pick<TransportIO, "create"> } | undefined
}
const target = process.argv[2]
const binary = process.argv[3] ?? "/tmp/bendvy-iroh-cargo-target/debug/iroh-native-probe"
if (!target) throw Error("Usage: node coop-transport-watchdog-check.mts HTTP_URL/coop.html [NATIVE_PROBE]")
const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] })
try {
  const page = await browser.newPage()
  await page.goto(target)
  await page.evaluate(async () => {
    function method(owner: object, name: string, ...args: unknown[]): unknown {
      const value: unknown = Reflect.get(owner, name)
      if (typeof value !== "function") throw Error(`Missing native method ${name}`)
      return Reflect.apply(value, owner, args)
    }
    const module: unknown = await import(new URL("./iroh/iroh_transport.js", location.href).href)
    if (typeof module !== "object" || module === null) throw Error("Invalid native module")
    await method(module, "default")
    const factory: unknown = Reflect.get(module, "Transport")
    if (typeof factory !== "function") throw Error("Missing native factory")
    globalThis.watchdogProbe = {
      slots: [],
      method,
      async until(predicate) {
        const deadline = performance.now() + 30000
        while (!predicate()) {
          if (performance.now() > deadline) throw Error("Native watchdog fact timed out")
          await new Promise((resolve) => setTimeout(resolve, 10))
        }
      },
      async create(accept) {
        const slot: NativeSlot = {
          facts: [],
          messages: 0,
          connectedAt: 0,
          disconnectedAt: 0,
          closedAt: 0,
          operation: 0,
          errors: []
        }
        const native: unknown = await method(factory, "create", (value: unknown) => {
          if (typeof value !== "object" || value === null || !("type" in value) || typeof value.type !== "string")
            throw Error("Invalid native fact")
          const fact: NativeFact = { type: value.type }
          if (value.type === "incoming") {
            if (!("offerId" in value) || typeof value.offerId !== "number") throw Error("Invalid offer")
            fact.offerId = value.offerId
            if (accept) {
              if (!slot.native) throw Error("Incoming offer before native creation")
              void Promise.resolve(method(slot.native, "acceptOffer", value.offerId, ++slot.operation)).catch(
                (error: unknown) => slot.errors.push(String(error))
              )
            }
          }
          if (value.type === "connected") slot.connectedAt = performance.now()
          if (value.type === "disconnected") slot.disconnectedAt = performance.now()
          if (value.type === "closed") slot.closedAt = performance.now()
          if (value.type === "message") slot.messages++
          slot.facts.push(fact)
        })
        if (typeof native !== "object" || native === null) throw Error("Invalid native endpoint")
        slot.native = native
        this.slots.push(slot)
        return this.slots.length - 1
      }
    }
  })
  for (const scenario of [
    { mode: "oversized", closeDuringRead: false },
    { mode: "stalled", closeDuringRead: false },
    { mode: "stalled", closeDuringRead: true }
  ]) {
    const { mode, closeDuringRead } = scenario
    const host = await page.evaluate(() => watchdogProbe.create(true))
    const ticket = await page.evaluate((host) => {
      const native = watchdogProbe.slots[host]?.native
      if (!native) throw Error("Missing host")
      const ticket = watchdogProbe.method(native, "invitation")
      if (typeof ticket !== "string") throw Error("Invalid invitation")
      return ticket
    }, host)
    const output = await new Promise<string>((resolve, reject) => {
      const child = spawn(binary, ["--fault", mode], { stdio: ["pipe", "pipe", "pipe"] })
      let stdout = "",
        stderr = ""
      let closing = false
      const timer = setTimeout(() => {
        child.kill()
        reject(Error(`Native ${mode} probe timed out`))
      }, 65000)
      child.stdout.on("data", (value: Buffer) => {
        stdout += value.toString()
        if (closeDuringRead && !closing && stdout.includes("READY raw stalled frame written")) {
          closing = true
          void page
            .evaluate(async (host) => {
              const slot = watchdogProbe.slots[host]
              if (!slot?.native) throw Error("Missing host during read cancellation")
              await new Promise((resolve) => setTimeout(resolve, 200))
              watchdogProbe.method(slot.native, "close")
            }, host)
            .catch((error: unknown) => {
              child.kill()
              reject(error)
            })
        }
      })
      child.stderr.on("data", (value: Buffer) => {
        stderr += value.toString()
      })
      child.on("error", reject)
      child.on("close", (code) => {
        clearTimeout(timer)
        if (code === 0) resolve(stdout)
        else reject(Error(`Native ${mode} probe exited ${code}: ${stderr}`))
      })
      child.stdin.end(ticket)
    })
    assert.match(output, new RegExp(`PASS raw ${mode} frame rejected`))
    const observed = await page.evaluate(
      async ({ host, closeDuringRead }) => {
        const slot = watchdogProbe.slots[host]
        if (!slot?.native) throw Error("Missing host")
        await watchdogProbe.until(() =>
          slot.facts.some((fact) => fact.type === (closeDuringRead ? "closed" : "disconnected"))
        )
        const result = {
          messages: slot.messages,
          elapsed: (closeDuringRead ? slot.closedAt : slot.disconnectedAt) - slot.connectedAt,
          errors: slot.errors
        }
        if (closeDuringRead) return result
        const invitation = watchdogProbe.method(slot.native, "invitation")
        const guestId = await watchdogProbe.create(false)
        const guest = watchdogProbe.slots[guestId]?.native
        if (!guest) throw Error("Missing guest")
        await watchdogProbe.method(guest, "join", invitation, 1)
        await watchdogProbe.method(guest, "send", new Uint8Array([1, 2, 3]), true, 1)
        await watchdogProbe.until(() => slot.messages === 1)
        result.errors.push(...(watchdogProbe.slots[guestId]?.errors ?? []))
        watchdogProbe.method(guest, "close")
        watchdogProbe.method(slot.native, "close")
        return result
      },
      { host, closeDuringRead }
    )
    assert.equal(observed.messages, 0, "Invalid or incomplete frames cannot be admitted")
    assert.deepEqual(observed.errors, [])
    if (closeDuringRead)
      assert.ok(observed.elapsed >= 0 && observed.elapsed < 5000, "Close must cancel the incomplete read promptly")
    if (mode === "stalled" && !closeDuringRead) {
      assert.ok(observed.elapsed >= 19000, "Stalled stream must remain pending until the native watchdog")
      assert.ok(observed.elapsed < 27000, "Native watchdog must bound incomplete frame retention")
    }
    console.log(
      closeDuringRead
        ? "PASS endpoint close during incomplete native receive"
        : `PASS raw ${mode} receive rejection and endpoint reuse`
    )
  }
  await page.addScriptTag({
    type: "module",
    content:
      'import * as facade from "./coop-transport.mjs"; import * as native from "./iroh/iroh_transport.js"; globalThis.retryFacade = facade; globalThis.retryNative = native;'
  })
  await page.waitForFunction(() => retryFacade !== undefined && retryNative !== undefined)
  const timeoutRetry = await page.evaluate(async () => {
    const facade = retryFacade,
      native = retryNative
    if (!facade || !native) throw Error("Missing transport modules")
    await native.default()
    const events: TransportEvent[] = []
    const guestEvents: NativeEvent[] = []
    let delayed: NativeEvent | undefined
    let delayNext = false
    let creates = 0
    const io: TransportIO = {
      now: () => Math.floor(performance.now()),
      schedule: (callback, milliseconds) => setTimeout(callback, milliseconds),
      cancel: (timer) => {
        if (typeof timer !== "number") throw Error("Invalid timer")
        clearTimeout(timer)
      },
      create: async (callback) => {
        creates++
        return native.Transport.create((event: NativeEvent) => {
          if (event.type === "incoming" && delayNext) {
            delayNext = false
            delayed = event
            return
          }
          if (event.type === "incoming" && delayed) {
            const expired = delayed
            delayed = undefined
            callback(expired)
          }
          callback(event)
        })
      }
    }
    const host = await facade.CoopTransport.create((event) => events.push(event), io)
    const guest = await native.Transport.create((event: NativeEvent) => guestEvents.push(event))
    const invitation = host.invitation()
    const identity = guest.endpointId()
    const cycles = []
    try {
      for (const cycle of [0, 1]) {
        delayNext = true
        const started = performance.now()
        const failed = await guest.join(invitation, cycle * 2 + 1).then(
          () => "Unexpected connection",
          (error: unknown) => String(error)
        )
        const elapsed = performance.now() - started
        await guest.join(invitation, cycle * 2 + 2)
        const payload = [0, 255, cycle, 128]
        await guest.send(new Uint8Array(payload), true, cycle * 2 + 2)
        await watchdogProbe.until(() => events.filter((event) => event.type === "message").length === cycle + 1)
        const received = events.filter((event) => event.type === "message")[cycle]
        if (received?.type !== "message") throw Error("Missing retry message")
        cycles.push({ failed, elapsed, payload, received: Array.from(received.bytes) })
        host.disconnectPeer()
        await watchdogProbe.until(() =>
          guestEvents.some((event) => event.type === "disconnected" && event.connectionId === cycle * 2 + 2)
        )
      }
      return {
        cycles,
        creates,
        preserved: host.invitation() === invitation && guest.endpointId() === identity,
        connections: events.filter((event) => event.type === "connected").length
      }
    } finally {
      guest.close()
      host.close()
    }
  })
  assert.equal(timeoutRetry.creates, 1, "Retry must retain the host endpoint")
  assert.equal(timeoutRetry.preserved, true, "Retry must retain the guest endpoint and invitation")
  assert.equal(timeoutRetry.connections, 2)
  for (const cycle of timeoutRetry.cycles) {
    assert.match(cycle.failed, /Connection timed out/)
    assert.ok(cycle.elapsed >= 19000 && cycle.elapsed < 27000, "Native connect watchdog must remain bounded")
    assert.deepEqual(cycle.received, cycle.payload, "Same-endpoint retry must deliver exact bytes")
  }
  console.log("PASS same-endpoint timeout retries through Bend admission with delayed expired offers")
  const offers = await page.evaluate(async () => {
    const hostId = await watchdogProbe.create(false)
    const host = watchdogProbe.slots[hostId]
    if (!host?.native) throw Error("Missing offer host")
    const invitation = watchdogProbe.method(host.native, "invitation")
    const clients: object[] = []
    for (let index = 0; index < 17; index++) {
      const id = await watchdogProbe.create(false)
      const native = watchdogProbe.slots[id]?.native
      if (!native) throw Error("Missing offer client")
      clients.push(native)
    }
    let settled = 0
    const attempts = clients.map((client) =>
      Promise.resolve(watchdogProbe.method(client, "join", invitation, 1)).then(
        () => {
          settled++
          return "connected"
        },
        () => {
          settled++
          return "rejected"
        }
      )
    )
    await watchdogProbe.until(() => host.facts.filter((fact) => fact.type === "incoming").length >= 16 && settled >= 1)
    const incoming = host.facts.filter((fact) => fact.type === "incoming")
    const admittedAtBound = incoming.length
    const first = incoming[0]?.offerId
    if (first === undefined) throw Error("Missing first offer")
    await new Promise((resolve) => setTimeout(resolve, 21000))
    const outcomes = await Promise.all(attempts)
    const connections = host.facts.filter((fact) => fact.type === "connected").length
    const totalOffers = host.facts.filter((fact) => fact.type === "incoming").length
    const replacementClients: object[] = []
    for (let index = 0; index < 16; index++) {
      const id = await watchdogProbe.create(false)
      const native = watchdogProbe.slots[id]?.native
      if (!native) throw Error("Missing replacement client")
      replacementClients.push(native)
    }
    const replacements = replacementClients.map((client) =>
      Promise.resolve(watchdogProbe.method(client, "join", invitation, 1)).then(
        () => "connected",
        () => "rejected"
      )
    )
    await watchdogProbe.until(() => host.facts.filter((fact) => fact.type === "incoming").length === 32)
    let expiredRejected = false
    try {
      await watchdogProbe.method(host.native, "acceptOffer", first, 1)
    } catch {
      expiredRejected = true
    }
    const replacementOffers = host.facts.filter((fact) => fact.type === "incoming").slice(16)
    const replacement = replacementOffers[0]?.offerId
    if (replacement === undefined) throw Error("Missing replacement offer")
    try {
      await watchdogProbe.method(host.native, "acceptOffer", replacement, 2)
    } catch (error) {
      throw Error(`Replacement offer acceptance failed: ${String(error)}`)
    }
    for (const offer of replacementOffers.slice(1)) watchdogProbe.method(host.native, "refuseOffer", offer.offerId)
    const replacementOutcomes = await Promise.all(replacements)
    const admitted = replacementClients[replacementOutcomes.indexOf("connected")]
    if (!admitted) throw Error("No replacement authenticated")
    await watchdogProbe.method(admitted, "send", new Uint8Array([9]), true, 1)
    await watchdogProbe.until(() => host.messages === 1)
    for (const client of [...clients, ...replacementClients]) watchdogProbe.method(client, "close")
    watchdogProbe.method(host.native, "close")
    return {
      admittedAtBound,
      totalOffers,
      expiredRejected,
      outcomes,
      connections,
      recoveredOffers: replacementOffers.length,
      replacementOutcomes
    }
  })
  assert.equal(offers.admittedAtBound, 16, "Native offer storage must stop at sixteen pending offers")
  assert.equal(offers.totalOffers, 16, "Excess raw attempts must not allocate offer handles")
  assert.equal(offers.expiredRejected, true)
  assert.equal(offers.connections, 0, "Pending offers cannot authenticate without explicit acceptance")
  assert.equal(offers.recoveredOffers, 16, "Expiry must release every slot before old handles are consumed")
  assert.equal(offers.replacementOutcomes.filter((outcome) => outcome === "connected").length, 1)
  assert.deepEqual(
    offers.outcomes,
    Array.from({ length: 17 }, () => "rejected")
  )
  console.log("PASS raw native offer saturation, refusal and expiry")
} finally {
  await browser.close()
}
