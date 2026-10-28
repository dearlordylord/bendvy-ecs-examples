import type { Frame, Player } from "../../examples/survivors/frame.mts"
export type Role = "host" | "guest"
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
  transportStates: { pendingSends: number; pendingBytes: number }[]
  nativeSends: { start: number; end: number; byteLength: number; confirmDelivery: boolean }[]
  lastFrame: LastFrame | null
}
declare global {
  var __transportQualification: Trace
  var __transportQualificationDraw: (frame: Frame) => void
}
