import assert from "node:assert/strict"
import { test } from "node:test"
import { measuredTrace, type InputResolution, type RenderRow, type Trace } from "./coop-browser-trace.mts"
import { authorityLag } from "./coop-motion-oracle.mts"

const window = { start: 1000, end: 7000 }
const input = (wall: number, worldTick: number): InputResolution => ({
  wall,
  worldTick,
  phase: 0,
  round: 0,
  eligible: true,
  applied: true,
  x: 1,
  y: 0,
  seq: worldTick
})
const render = (wall: number, tick: number): RenderRow => ({
  wall,
  tick,
  phase: 0,
  round: 0,
  runId: "run",
  choicePending: false,
  remotePresentation: undefined,
  players: [],
  enemies: []
})
const trace = (): Trace => ({
  workerInitializations: [],
  workerErrors: [],
  inputResolutions: [],
  renders: [],
  transportStates: [],
  nativeSends: [],
  lastFrame: null
})

await test("frames recorded during extraction cannot dilute measured authority lag", () => {
  const captured = trace()
  captured.inputResolutions = [input(5999, 80)]
  captured.renders = [render(6000, 40), ...Array.from({ length: 20 }, (_, index) => render(7001 + index, 1000))]
  const bounded = measuredTrace(captured, window)
  const lag = authorityLag(bounded.inputResolutions, bounded.renders, window.start)
  assert.equal(lag.p95Ticks, 40)
  assert.equal(lag.samples, 1)
})

await test("source timestamps retain in-window worker steps delivered after newer rows", () => {
  const captured = trace()
  captured.inputResolutions = [input(500, 1), input(5999, 80), input(9000, 200), input(6800, 120)]
  const bounded = measuredTrace(captured, window)
  assert.deepEqual(
    bounded.inputResolutions.map((row) => row.worldTick),
    [80, 120]
  )
  assert.equal(captured.inputResolutions.length, 4)
})

await test("resource observations keep setup history and exclude completions after the measurement", () => {
  const captured = trace()
  captured.transportStates = [
    { wall: 500, pendingSends: 16, pendingBytes: 4096 },
    { wall: 6500, pendingSends: 1, pendingBytes: 32 },
    { wall: 7001, pendingSends: 2, pendingBytes: 64 }
  ]
  captured.nativeSends = [
    { start: 400, end: 500, byteLength: 64, confirmDelivery: false },
    { start: 6400, end: 6500, byteLength: 32, confirmDelivery: false },
    { start: 6900, end: 7100, byteLength: 128, confirmDelivery: false }
  ]
  const bounded = measuredTrace(captured, window)
  assert.deepEqual(
    bounded.transportStates.map((row) => row.pendingSends),
    [16, 1]
  )
  assert.deepEqual(
    bounded.nativeSends.map((row) => row.byteLength),
    [64, 32]
  )
})
