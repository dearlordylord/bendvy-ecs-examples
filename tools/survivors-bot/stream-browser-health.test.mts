import assert from "node:assert/strict"
import { test } from "node:test"
import { boundedProbe, initialHealth, observeProgress } from "./stream-browser-health.mts"

const limits = { maxProbeGapMs: 15000, maxSimulationGapMs: 15000 }
const first = { frames: 1, tick: 1, run: 1, commits: 0 }

await test("a delayed probe cannot erase a thirty-second stall with one new frame and tick", () => {
  assert.throws(
    () => observeProgress(initialHealth(first, 0), { ...first, frames: 2, tick: 2 }, 30000, limits),
    /probe exceeded/
  )
})
await test("regular render samples cannot hide stalled simulation", () => {
  let health = initialHealth(first, 0)
  for (let now = 1000; now < 15000; now += 1000)
    health = observeProgress(health, { ...first, frames: now }, now, limits)
  assert.throws(() => observeProgress(health, { ...first, frames: 15000 }, 15000, limits), /simulation stopped/)
})
await test("regular simulation samples cannot hide stopped rendering", () => {
  let health = initialHealth(first, 0)
  for (let now = 1000; now < 15000; now += 1000) health = observeProgress(health, { ...first, tick: now }, now, limits)
  assert.throws(() => observeProgress(health, { ...first, tick: 15000 }, 15000, limits), /stopped rendering/)
})
await test("healthy progress and real decision commits refresh their respective clocks", () => {
  const health = observeProgress(initialHealth(first, 0), { ...first, frames: 2, commits: 1 }, 1000, limits)
  assert.equal(health.frameAt, 1000)
  assert.equal(health.simulationAt, 1000)
  assert.throws(() => observeProgress(health, first, 999, limits), /clock regressed/)
})
await test("an unresolved actual probe hits its response deadline", async () => {
  await assert.rejects(boundedProbe(new Promise<never>(() => {}), 20), /response deadline/)
  assert.equal(await boundedProbe(Promise.resolve(42), 1000), 42)
})
