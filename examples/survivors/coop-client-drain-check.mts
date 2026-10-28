import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"
import { runInNewContext } from "node:vm"
import { transform } from "esbuild"
import ClientDelivery from "./dist/coop-client-delivery.mjs"
import Connection from "./dist/coop-connection.mjs"
import * as values from "./host-values.mts"

interface Driver {
  connect(channel: { send(payload: string): Promise<unknown> }, generation: number): void
  choose(index: number): void
}

const source = await readFile(new URL("./coop-browser.mts", import.meta.url), "utf8")
const compiled = await transform(source, { loader: "ts", format: "cjs", target: "es2023" })

function guest(): Driver {
  const core = { fresh: () => ({}), empty: () => ({}), playback: () => ({}) }
  const modules: Record<string, unknown> = {
    "./host-values.mts": values,
    "./dist/coop-client-delivery.mjs": { __esModule: true, default: ClientDelivery },
    "./dist/coop-connection.mjs": { __esModule: true, default: Connection },
    "./coop-ui.mts": { CoopUI: class {} }
  }
  const result: unknown = runInNewContext(
    compiled.code +
      `
      ({
        connect(channel,generation){
          role='guest';connected=true;transport=channel;epoch=generation;connectionEpoch=generation;
          sessionId=1;sequence=0;tick=20;runFinished=false;
          connectionState={$:'GuestRunning',epoch:generation,token:7};
          clientDelivery=ClientDelivery.fresh(generation);
        },
        choose(index){sendAction({$:'Choice',round:0,index});}
      })
    `,
    {
      require: (name: string) => modules[name] ?? { __esModule: true, default: core },
      location: { href: "https://example.test/coop.html" },
      URL,
      URLSearchParams,
      AbortController,
      ClientDelivery,
      performance,
      fetch: async () => ({ json: async () => null }),
      setInterval: () => 1,
      clearInterval() {},
      addEventListener() {}
    }
  )
  const { connect, choose } = values.object(result)
  if (typeof connect !== "function" || typeof choose !== "function") throw Error("Missing guest test driver")
  return {
    connect(channel, generation) {
      Reflect.apply(connect, undefined, [channel, generation])
    },
    choose(index) {
      Reflect.apply(choose, undefined, [index])
    }
  }
}

function channel() {
  const sent: string[] = []
  const completions: (() => void)[] = []
  return {
    sent,
    completions,
    send(payload: string) {
      sent.push(payload)
      return new Promise<void>((resolve) => completions.push(resolve))
    }
  }
}

await test("guest sends queued work when the preceding native write completes", async () => {
  const driver = guest()
  const transport = channel()
  driver.connect(transport, 1)
  driver.choose(0)
  driver.choose(1)
  assert.equal(transport.sent.length, 1)
  values.defined(transport.completions[0])()
  await new Promise<void>((resolve) => setImmediate(resolve))
  assert.equal(transport.sent.length, 2)
  const packet = ClientDelivery.decode(values.defined(transport.sent[1]))
  assert.equal(packet.$, "Some")
  if (packet.$ === "Some")
    assert.deepEqual(
      values.rows(packet.value.commands).map((row) => row.seq),
      [2]
    )
  values.defined(transport.completions[1])()
  await new Promise<void>((resolve) => setImmediate(resolve))
  assert.equal(transport.sent.length, 2, "completed commands must not be retransmitted")
})

await test("an old native completion cannot drain a replacement guest connection", async () => {
  const driver = guest()
  const transport = channel()
  driver.connect(transport, 1)
  driver.choose(0)
  driver.connect(transport, 2)
  driver.choose(1)
  driver.choose(2)
  values.defined(transport.completions[0])()
  await new Promise<void>((resolve) => setImmediate(resolve))
  assert.equal(transport.sent.length, 2)
  values.defined(transport.completions[1])()
  await new Promise<void>((resolve) => setImmediate(resolve))
  assert.equal(transport.sent.length, 3)
  values.defined(transport.completions[2])()
  await new Promise<void>((resolve) => setImmediate(resolve))
  assert.equal(transport.sent.length, 3)
})
