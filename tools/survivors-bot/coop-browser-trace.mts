import type { Frame, Player } from "../../examples/survivors/frame.mts"
export type Role = "host" | "guest"
export interface MeasurementWindow {
  start: number
  end: number
}
export interface LastFrame {
  wall: number
  tick: number
  phase: number
  round: number
  runId: string
  choicePending: boolean
}
export interface RenderRow extends LastFrame {
  remotePresentation: Frame["remotePresentation"]
  players: Player[]
  enemies: { x: number; y: number; lifetime: string }[]
}
export interface InputResolution {
  wall: number
  worldTick: number
  phase: number
  round: number
  eligible: boolean
  applied: boolean
  x: number
  y: number
  seq: number
}
export interface Trace {
  workerInitializations: { requestedSeed: number; seed: number }[]
  workerErrors: string[]
  inputResolutions: InputResolution[]
  renders: RenderRow[]
  transportStates: { wall: number; pendingSends: number; pendingBytes: number }[]
  nativeSends: { start: number; end: number; byteLength: number; confirmDelivery: boolean }[]
  lastFrame: LastFrame | null
}
export function measuredTrace(trace: Trace, window: MeasurementWindow): Trace {
  const inside = (wall: number) => wall >= window.start && wall <= window.end
  return {
    ...trace,
    inputResolutions: trace.inputResolutions.filter((row) => inside(row.wall)),
    renders: trace.renders.filter((row) => inside(row.wall)),
    transportStates: trace.transportStates.filter((row) => row.wall <= window.end),
    nativeSends: trace.nativeSends.filter((row) => row.end <= window.end),
    lastFrame: trace.lastFrame && inside(trace.lastFrame.wall) ? trace.lastFrame : null
  }
}
declare global {
  var __transportQualification: Trace
  var __transportQualificationDraw: (frame: Frame) => void
  var __transportQualificationWindow: MeasurementWindow | null
  var __transportQualificationRecording: (wall: number) => boolean
  var __transportQualificationMeasuredFrame: LastFrame | null
  var __transportQualificationWorker: Worker | null
}
