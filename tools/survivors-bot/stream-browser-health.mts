import assert from "node:assert/strict"

export type Progress = { frames: number; tick: number; run: number; commits: number }
export type Health = { observedAt: number; frameAt: number; simulationAt: number; progress: Progress }
export type HealthLimits = { maxProbeGapMs: number; maxSimulationGapMs: number }
export function initialHealth(progress: Progress, now: number): Health {
  return { observedAt: now, frameAt: now, simulationAt: now, progress }
}
export function observeProgress(previous: Health, current: Progress, now: number, limits: HealthLimits): Health {
  assert(now >= previous.observedAt, "Probe clock regressed")
  assert(now - previous.observedAt < limits.maxProbeGapMs, "Browser probe exceeded the progress deadline")
  assert(now - previous.frameAt < limits.maxProbeGapMs, "Foreground stream stopped rendering")
  assert(now - previous.simulationAt < limits.maxSimulationGapMs, "Stream simulation stopped progressing")
  return {
    observedAt: now,
    frameAt: current.frames > previous.progress.frames ? now : previous.frameAt,
    simulationAt:
      current.tick !== previous.progress.tick ||
      current.run !== previous.progress.run ||
      current.commits !== previous.progress.commits
        ? now
        : previous.simulationAt,
    progress: current
  }
}
export async function boundedProbe<T>(probe: Promise<T>, deadlineMs: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined
  try {
    return await Promise.race([
      probe,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("Browser probe exceeded its response deadline")), deadlineMs)
      })
    ])
  } finally {
    clearTimeout(timer)
  }
}
