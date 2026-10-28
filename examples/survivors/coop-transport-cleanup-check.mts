import assert from "node:assert/strict"
import { chromium } from "playwright"

interface ProbeTransport {
  readonly native: object
  close(): void
  disconnectPeer(): void
  invitation(): string
  join(invitation: string): Promise<unknown>
}
declare global {
  var cleanupProbe: {
    createNative(callback: (event: { type: string }) => void): Promise<ProbeTransport>
    coop: WeakRef<object>[]
    raw: WeakRef<object>[]
  }
}

const target = process.argv[2]
if (!target) throw Error("Usage: node coop-transport-cleanup-check.mts HTTP_URL/coop.html")
const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] })
try {
  const page = await browser.newPage()
  await page.goto(target)
  const lifecycle = await page.evaluate(async () => {
    const url = new URL("./iroh/iroh_transport.js", location.href).href
    const module: unknown = await import(url)
    if (typeof module !== "object" || module === null) throw Error("Invalid Iroh module")
    function method(owner: object, name: string) {
      const value: unknown = Reflect.get(owner, name)
      if (typeof value !== "function") throw Error(`Missing method ${name}`)
      return (...args: unknown[]): unknown => Reflect.apply(value, owner, args)
    }
    await method(module, "default")()
    const factory: unknown = Reflect.get(module, "Transport")
    if (typeof factory !== "function") throw Error("Missing Transport factory")
    globalThis.cleanupProbe = {
      coop: [],
      raw: [],
      async createNative(callback) {
        const endpoint: { native?: object } = {}
        let operation = 0
        const value: unknown = await method(
          factory,
          "create"
        )((event: unknown) => {
          if (typeof event !== "object" || event === null || !("type" in event) || typeof event.type !== "string")
            throw Error("Invalid transport event")
          if (event.type === "incoming") {
            const native = endpoint.native
            if (!native || !("offerId" in event) || typeof event.offerId !== "number")
              throw Error("Invalid incoming offer")
            void Promise.resolve(method(native, "acceptOffer")(event.offerId, ++operation)).catch(() =>
              callback({ type: "error" })
            )
            return
          }
          callback({ type: event.type })
        })
        if (typeof value !== "object" || value === null) throw Error("Invalid Transport instance")
        endpoint.native = value
        return {
          native: value,
          close: () => {
            method(value, "close")()
          },
          disconnectPeer: () => {
            method(value, "disconnectPeer")()
          },
          invitation: () => {
            const result = method(value, "invitation")()
            if (typeof result !== "string") throw Error("Invalid invitation")
            return result
          },
          join: async (invitation) => method(value, "join")(invitation, ++operation)
        }
      }
    }
    const events: string[] = []
    const transport = await globalThis.cleanupProbe.createNative((event) => {
      events.push(event.type)
      if (event.type === "closed") transport.close()
    })
    transport.disconnectPeer()
    const invitation = transport.invitation()
    transport.close()
    transport.close()
    transport.disconnectPeer()
    await new Promise((resolve) => setTimeout(resolve, 100))
    return { events, invitation: typeof invitation }
  })
  assert.deepEqual(lifecycle, { events: ["ready", "closed"], invitation: "string" })
  const rejoined = await page.evaluate(async () => {
    const hostEvents: string[] = [],
      guestEvents: string[] = []
    const host = await globalThis.cleanupProbe.createNative((event) => hostEvents.push(event.type))
    const guest = await globalThis.cleanupProbe.createNative((event) => guestEvents.push(event.type))
    async function until(predicate: () => boolean) {
      const deadline = Date.now() + 20000
      while (!predicate()) {
        if (Date.now() > deadline) throw Error("Peer lifecycle event timed out")
        await new Promise((resolve) => setTimeout(resolve, 20))
      }
    }
    try {
      const invitation = host.invitation()
      await guest.join(invitation)
      await until(() => hostEvents.includes("connected"))
      host.disconnectPeer()
      await until(() => guestEvents.includes("disconnected"))
      if (host.invitation() !== invitation) throw Error("Disconnect changed invitation")
      await guest.join(invitation)
      await until(() => hostEvents.filter((event) => event === "connected").length === 2)
      return { hostEvents, guestEvents }
    } finally {
      host.close()
      guest.close()
    }
  })
  assert.equal(rejoined.hostEvents.filter((event) => event === "connected").length, 2)
  assert.equal(rejoined.guestEvents.filter((event) => event === "connected").length, 2)
  const cdp = await page.context().newCDPSession(page)
  const cycles = []
  for (let cycle = 0; cycle < 3; cycle++) {
    await page.evaluate(async () => {
      const { CoopTransport } = await import("./coop-transport.mjs")
      for (let i = 0; i < 3; i++) {
        const transport = await CoopTransport.create(() => {})
        transport.close()
        globalThis.cleanupProbe.coop.push(new WeakRef(transport))
      }
      for (let i = 0; i < 3; i++) {
        const transport = await globalThis.cleanupProbe.createNative(() => {})
        transport.close()
        globalThis.cleanupProbe.raw.push(new WeakRef(transport.native))
      }
    })
    await new Promise((resolve) => setTimeout(resolve, 2000))
    for (let i = 0; i < 4; i++) {
      await cdp.send("HeapProfiler.collectGarbage")
      await new Promise((resolve) => setTimeout(resolve, 200))
    }
    const retained = await page.evaluate(() => ({
      coop: globalThis.cleanupProbe.coop.filter((ref) => ref.deref()).length,
      raw: globalThis.cleanupProbe.raw.filter((ref) => ref.deref()).length,
      createdPerGroup: globalThis.cleanupProbe.coop.length
    }))
    cycles.push(retained)
    assert.equal(retained.coop, 0, "Closed CoopTransport instances must be collectible")
    assert.equal(retained.raw, 0, "Closed Wasm Transport wrappers must be collectible")
  }
  console.log(JSON.stringify({ lifecycle, rejoined, cycles }))
} finally {
  await browser.close()
}
