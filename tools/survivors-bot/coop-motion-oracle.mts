import assert from "node:assert/strict"
import { defined } from "../../examples/survivors/host-values.mts"
import type { RenderRow, InputResolution } from "./coop-browser-trace.mts"

function p95(values: number[]) {
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.max(0, Math.ceil(sorted.length * 0.95) - 1)] ?? 0
}
export function authorityLag(hostRows: InputResolution[], guestRows: RenderRow[], startWall: number) {
  const hosts = hostRows
    .filter((row) => Number.isFinite(row.wall) && Number.isFinite(row.worldTick))
    .sort((a, b) => a.wall - b.wall)
  const activeGuests = guestRows.filter(
    (row) => row.phase === 0 && Number.isFinite(row.wall) && Number.isFinite(row.tick)
  )
  const measured = activeGuests.filter((row) => row.wall >= startWall + 5000)
  const lagRows = []
  let hostIndex = 0,
    current = null
  for (const guest of measured) {
    while (hostIndex < hosts.length && defined(hosts[hostIndex]).wall <= guest.wall) {
      current = hosts[hostIndex]
      hostIndex++
    }
    if (current && current.phase === 0 && current.round === guest.round)
      lagRows.push({ wall: guest.wall, lag: Math.max(0, current.worldTick - guest.tick) })
  }
  const buckets = new Map<number, number[]>()
  for (const row of lagRows) {
    const index = Math.floor((row.wall - (startWall + 5000)) / 5000),
      values = buckets.get(index) || []
    values.push(row.lag)
    buckets.set(index, values)
  }
  const windows = [...buckets.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([index, values]) => ({
      startMs: 5000 + index * 5000,
      samples: values.length,
      maxTicks: Math.max(...values),
      p95Ticks: p95(values)
    }))
  return {
    reference: "authoritative host worker advanced-step clock",
    hostClockSamples: hosts.length,
    activePhaseZeroMs: activeGuests.length > 1 ? defined(activeGuests.at(-1)).wall - defined(activeGuests[0]).wall : 0,
    measuredMs: measured.length > 1 ? defined(measured.at(-1)).wall - defined(measured[0]).wall : 0,
    samples: lagRows.length,
    maxTicks: lagRows.length ? Math.max(...lagRows.map((row) => row.lag)) : 0,
    p95Ticks: p95(lagRows.map((row) => row.lag)),
    windows
  }
}
// Fixed default-character trajectory oracle, not a universal enemy physics bound.
export function motionOracle(rows: RenderRow[], startWall: number) {
  const warmAt = startWall + 5000,
    hostSteps: number[] = [],
    enemySteps: number[] = [],
    violations: unknown[] = []
  let activeSamples = 0,
    bufferedSamples = 0,
    bufferEntries = 0,
    bufferExits = 0,
    recoveryEntries = 0
  for (let index = 0; index < rows.length; index++) {
    const row = defined(rows[index]),
      previous = rows[index - 1]
    if (row.wall < warmAt || row.phase !== 0) continue
    activeSamples++
    if (row.remotePresentation?.buffering) bufferedSamples++
    const continuous =
      previous &&
      previous.wall >= warmAt &&
      previous.phase === 0 &&
      previous.runId === row.runId &&
      previous.round === row.round
    if (!continuous) continue
    if (row.remotePresentation?.buffering && !previous.remotePresentation?.buffering) bufferEntries++
    if (!row.remotePresentation?.buffering && previous.remotePresentation?.buffering) bufferExits++
    if (row.remotePresentation?.recovered && !previous.remotePresentation?.recovered) recoveryEntries++
    const currentSample = defined(row.remotePresentation).sampledAt,
      previousSample = defined(previous.remotePresentation).sampledAt
    assert.ok(Number.isFinite(currentSample) && Number.isFinite(previousSample), "presentation sample clock required")
    const elapsedMs = currentSample - previousSample
    if (!(elapsedMs > 0 && elapsedMs <= 250)) continue
    const oldHost = previous.players?.find((player) => player.id === 0),
      host = row.players?.find((player) => player.id === 0)
    if (
      host &&
      oldHost &&
      host.character === oldHost.character &&
      host.character === 0 &&
      host.alive &&
      oldHost.alive
    ) {
      const distance = Math.hypot(host.px - oldHost.px, host.py - oldHost.py),
        allowed = 4 * ((elapsedMs * 60) / 1000) + 1
      assert.ok(Number.isFinite(distance), "remote host coordinates must be finite")
      hostSteps.push(distance / ((elapsedMs * 60) / 1000))
      if (distance > allowed)
        violations.push({
          wall: row.wall,
          elapsedMs,
          distance,
          allowed,
          previousTick: previous.tick,
          tick: row.tick,
          previousPresentation: previous.remotePresentation,
          presentation: row.remotePresentation
        })
    }
    const oldEnemies = new Map((previous.enemies || []).map((enemy) => [enemy.lifetime, enemy]))
    for (const enemy of row.enemies || []) {
      const old = oldEnemies.get(enemy.lifetime)
      if (old) {
        const distance = Math.hypot(enemy.x - old.x, enemy.y - old.y)
        if (Number.isFinite(distance)) enemySteps.push(distance / ((elapsedMs * 60) / 1000))
      }
    }
  }
  return {
    warmupMs: 5000,
    maxPairGapMs: 250,
    host: {
      samples: hostSteps.length,
      maxUnitsPerWallTick: hostSteps.length ? Math.max(...hostSteps) : 0,
      p95UnitsPerWallTick: p95(hostSteps),
      violationCount: violations.length,
      violations: violations.slice(0, 12)
    },
    enemies: {
      samples: enemySteps.length,
      maxUnitsPerWallTick: enemySteps.length ? Math.max(...enemySteps) : 0,
      p95UnitsPerWallTick: p95(enemySteps),
      scope: "same-generation diagnostics; monster dash mechanics have no asserted speed bound"
    },
    buffer: { activeSamples, bufferedSamples, bufferEntries, bufferExits, recoveryEntries }
  }
}
export function inputCoverage(rows: InputResolution[], rejections?: { reason: number }[]) {
  let eligible = 0,
    applied = 0,
    nonneutralApplied = 0,
    longestNeutralStreak = 0,
    streak = 0,
    lastTick
  for (const row of rows) {
    if (!row.eligible || row.phase !== 0) {
      streak = 0
      lastTick = undefined
      continue
    }
    eligible++
    if (row.applied) applied++
    if (row.applied && (row.x !== 1 || row.y !== 1)) {
      nonneutralApplied++
      streak = 0
    } else {
      streak = lastTick === row.worldTick - 1 ? streak + 1 : 1
      longestNeutralStreak = Math.max(longestNeutralStreak, streak)
    }
    lastTick = row.worldTick
  }
  return {
    recordedSteps: rows.length,
    eligiblePhaseZeroSteps: eligible,
    appliedSteps: applied,
    nonneutralAppliedSteps: nonneutralApplied,
    appliedRatio: eligible ? applied / eligible : 0,
    nonneutralAppliedRatio: eligible ? nonneutralApplied / eligible : 0,
    longestNeutralStreak,
    lateRejections: rejections ? rejections.filter((row) => row.reason === 5).length : null,
    totalRejections: rejections ? rejections.length : null,
    scope:
      "actual advanced worker steps; neutral streak includes legitimate releases, not a mandatory 60Hz movement guarantee"
  }
}
