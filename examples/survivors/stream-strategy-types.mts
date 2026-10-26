export type Decision = { intention: BendABI.StreamBot.Intention; memory: unknown; label: string }
export type Strategy = {
  revision: string
  memoryVersion: number
  decide(observation: BendABI.StreamBot.Observation, memory: unknown): Decision | Promise<Decision>
}
export type RequestIdentity = BendABI.StreamSession.Identity
export type WorkerInput =
  | { kind: "prepare"; url: string; observation: BendABI.StreamBot.Observation; memory: unknown; memoryVersion: number }
  | { kind: "decide"; identity: RequestIdentity; observation: BendABI.StreamBot.Observation; memory: unknown }
export type WorkerOutput =
  | { kind: "ready"; revision: string; memoryVersion: number; reset: boolean }
  | { kind: "decision"; identity: RequestIdentity; decision: Decision }
  | { kind: "failure"; message: string }
