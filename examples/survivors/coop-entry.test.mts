import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"
import { runInNewContext } from "node:vm"
import { transform } from "esbuild"
import type { CoopCallbacks } from "./coop-ui.mts"
import * as values from "./host-values.mts"

const source = await readFile(new URL("./coop-browser.mts", import.meta.url), "utf8")
const compiled = await transform(source, { loader: "ts", format: "cjs", target: "es2023" })

for (const invitation of ["?session=7&join=ticket", "?session=7#join=ticket", "?session=7&join=ticket&seat=2"]) {
  await test(`invitation waits for explicit join ${invitation}`, async () => {
    let callbacks: CoopCallbacks = {}
    const connections: string[] = []
    const replacements: string[] = []
    const statuses: string[] = []
    const core = { fresh: () => ({}), empty: () => ({}), playback: () => ({}) }
    const modules: Record<string, unknown> = {
      "./coop-ui.mts": {
        CoopUI: class {
          constructor(actions: CoopCallbacks) {
            callbacks = actions
          }
          setup() {
            return { character: 0, stage: 0, mode: 0, arcana: 0, meta: 0, allowedWeapons: 0 }
          }
          reset() {}
          role() {}
          diagnostic() {}
          status(message: string) {
            statuses.push(message)
          }
        }
      },
      "./host-values.mts": values,
      "./coop-snapshot-codec.mts": { SnapshotDecoder: class {} },
      "./coop-party-wire.mts": { invitationSeats: () => [{ player: 2, ticket: "seat-ticket" }] },
      "./coop-transport.mts": {
        CoopTransport: {
          create: async () => {
            connections.push("create")
            return {
              joinCandidates: async (tickets: string[]) => {
                connections.push(values.defined(tickets[0]))
                return 0
              }
            }
          }
        }
      }
    }
    runInNewContext(compiled.code, {
      require: (name: string) => modules[name] ?? { __esModule: true, default: core },
      location: { href: `https://example.test/coop.html${invitation}` },
      URL,
      URLSearchParams,
      AbortController,
      fetch: async () => ({ json: async () => null }),
      history: { replaceState: (_state: unknown, _title: string, url: URL) => replacements.push(url.href) },
      setInterval: () => 1,
      clearInterval() {},
      setTimeout: () => 1,
      clearTimeout() {},
      addEventListener() {}
    })
    await new Promise<void>((resolve) => setImmediate(resolve))
    assert.equal(connections.length, 0, "loading the invitation must not create a transport or join a seat")
    assert.equal(replacements.length, 0, "loading the invitation must not reserve a seat")
    assert.equal(statuses.length, 0, "loading the invitation must not report an active connection")
    assert.equal(typeof callbacks.onRetry, "function")
    await callbacks.onRetry?.()
    assert.deepEqual(connections, ["create", "seat-ticket"])
    assert.equal(replacements.length, 1)
    assert.equal(new URL(values.defined(replacements[0])).searchParams.get("seat"), "2")
    assert.ok(statuses.includes("Connecting to Iroh…"))
  })
}
