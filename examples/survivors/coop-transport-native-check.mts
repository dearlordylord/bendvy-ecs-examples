import assert from "node:assert/strict"
import { chromium } from "playwright"

const target = process.argv[2]
if (!target) throw Error("Usage: node coop-transport-native-check.mts HTTP_URL/coop.html")
const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] })
try {
  const page = await browser.newPage()
  await page.goto(target)
  const result = await page.evaluate(async () => {
    interface Fact {
      type: string
      offerId?: number
      connectionId?: number
      operationId?: number
      bytes?: Uint8Array
    }
    function method(owner: object, name: string, ...args: unknown[]): unknown {
      const value: unknown = Reflect.get(owner, name)
      if (typeof value !== "function") throw Error(`Missing native method ${name}`)
      return Reflect.apply(value, owner, args)
    }
    function fact(value: unknown): Fact {
      if (typeof value !== "object" || value === null || !("type" in value) || typeof value.type !== "string")
        throw Error("Invalid native fact")
      const result: Fact = { type: value.type }
      for (const key of ["offerId", "connectionId", "operationId"] as const) {
        const id: unknown = Reflect.get(value, key)
        if (id !== undefined) {
          if (typeof id !== "number" || !Number.isInteger(id) || id <= 0) throw Error("Invalid native identity")
          result[key] = id
        }
      }
      const bytes: unknown = Reflect.get(value, "bytes")
      if (bytes !== undefined) {
        if (!(bytes instanceof Uint8Array)) throw Error("Invalid native bytes")
        result.bytes = bytes
      }
      return result
    }
    async function until(predicate: () => boolean) {
      const deadline = performance.now() + 25000
      while (!predicate()) {
        if (performance.now() > deadline) throw Error("Native fact timed out")
        await new Promise((resolve) => setTimeout(resolve, 10))
      }
    }
    async function rejected(operation: unknown) {
      try {
        await operation
      } catch {
        return true
      }
      return false
    }
    const module: unknown = await import(new URL("./iroh/iroh_transport.js", location.href).href)
    if (typeof module !== "object" || module === null) throw Error("Invalid native module")
    await method(module, "default")
    const factory: unknown = Reflect.get(module, "Transport")
    if (typeof factory !== "function") throw Error("Invalid native factory")
    const create = async (events: Fact[]) => {
      const value = await method(factory, "create", (value: unknown) => events.push(fact(value)))
      if (typeof value !== "object" || value === null) throw Error("Invalid native endpoint")
      return value
    }
    const hosts: Fact[] = [],
      guests: Fact[] = []
    const host = await create(hosts),
      guest = await create(guests)
    function offer(index: number) {
      const value = hosts.filter((event) => event.type === "incoming")[index]?.offerId
      if (value === undefined) throw Error("Missing offer")
      return value
    }
    try {
      const invitation = method(host, "invitation")
      const refused = rejected(method(guest, "join", invitation, 1))
      await until(() => hosts.some((event) => event.type === "incoming"))
      await new Promise((resolve) => setTimeout(resolve, 100))
      const previewConnected = hosts.some((event) => event.type === "connected")
      method(host, "refuseOffer", offer(0))
      method(host, "refuseOffer", offer(0))
      const refusedOnce = await refused
      const consumedOfferRejected = await rejected(method(host, "acceptOffer", offer(0), 1))
      const joined = method(guest, "join", invitation, 2)
      await until(() => hosts.filter((event) => event.type === "incoming").length === 2)
      await method(host, "acceptOffer", offer(1), 10)
      await joined
      await until(() => guests.some((event) => event.type === "connected"))
      const authenticatedIdentity =
        hosts.find((event) => event.type === "connected")?.operationId === 10 &&
        hosts.find((event) => event.type === "connected")?.connectionId === 10 &&
        guests.find((event) => event.type === "connected")?.connectionId === 2
      const payload = new Uint8Array([0, 255, 1, 128, 42])
      await method(guest, "send", payload, true, 2)
      await until(() => hosts.some((event) => event.type === "message"))
      const exactBytes = hosts.find((event) => event.type === "message")?.bytes
      const staleWriteRejected = await rejected(method(guest, "send", payload, false, 1))
      const oversizedRejected = await rejected(method(guest, "send", new Uint8Array(1048577), false, 2))
      const burst = Array.from({ length: 5 }, () => method(guest, "send", new Uint8Array(1048576), true, 2))
      const bounded = await Promise.allSettled(burst)
      await until(() => hosts.filter((event) => event.type === "message").length === 5)
      const countBurst = await Promise.allSettled(
        Array.from({ length: 17 }, () => method(guest, "send", new Uint8Array([7]), true, 2))
      )
      method(guest, "disconnectPeer", 1)
      await method(guest, "send", payload, true, 2)
      method(host, "disconnectPeer", 10)
      await until(() => guests.some((event) => event.type === "disconnected" && event.connectionId === 2))
      const preservedInvitation = method(host, "invitation") === invitation
      const cancelled = rejected(method(guest, "join", invitation, 3))
      await until(() => hosts.filter((event) => event.type === "incoming").length === 3)
      method(guest, "disconnectPeer", 3)
      const replacement = method(guest, "join", invitation, 4)
      await until(() => hosts.filter((event) => event.type === "incoming").length === 4)
      method(host, "refuseOffer", offer(2))
      await method(host, "acceptOffer", offer(3), 11)
      await replacement
      const cancelledRejected = await cancelled
      await method(guest, "send", payload, true, 4)
      return {
        previewConnected,
        refusedOnce,
        consumedOfferRejected,
        authenticatedIdentity,
        exactBytes: Array.from(exactBytes ?? []),
        staleWriteRejected,
        oversizedRejected,
        burstAccepted: bounded.filter((value) => value.status === "fulfilled").length,
        burstRejected: bounded.filter((value) => value.status === "rejected").length,
        countAccepted: countBurst.filter((value) => value.status === "fulfilled").length,
        countRejected: countBurst.filter((value) => value.status === "rejected").length,
        preservedInvitation,
        cancelledRejected,
        staleConnected: guests.some((event) => event.type === "connected" && event.connectionId === 3)
      }
    } finally {
      method(host, "close")
      method(guest, "close")
      method(host, "close")
      method(guest, "disconnectPeer", 0)
    }
  })
  assert.deepEqual(result, {
    previewConnected: false,
    refusedOnce: true,
    consumedOfferRejected: true,
    authenticatedIdentity: true,
    exactBytes: [0, 255, 1, 128, 42],
    staleWriteRejected: true,
    oversizedRejected: true,
    burstAccepted: 4,
    burstRejected: 1,
    countAccepted: 16,
    countRejected: 1,
    preservedInvitation: true,
    cancelledRejected: true,
    staleConnected: false
  })
  console.log(
    "PASS raw Iroh offers, single consumption, identities, exact bytes, 1 MiB frames, 4 MiB budget and cancellation"
  )
} finally {
  await browser.close()
}
