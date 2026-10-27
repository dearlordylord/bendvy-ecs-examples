import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { execFileSync } from "node:child_process"
import { readFile } from "node:fs/promises"
import path from "node:path"

export type Position = { tick: number; x: number; y: number }
export type GoalTrack = {
  direction: "east" | "west"
  positions: Position[]
  startX: number
  startY: number
  targetX: number
  targetY: number
  suppliedTick: number
  acceptedTick: number
}
export const goalCaptureProtocol = {
  window: [80, 100],
  maxDisplacementPerTick: 6,
  transitionTolerance: 1e-8,
  selection: ["absolute tick gap", "maximum tick", "east tick", "west tick"],
  directionThreshold: 30,
  separationThreshold: 60,
  approachThreshold: 20
}
export function safeNatural(value: number, label: string): number {
  assert(Number.isSafeInteger(value) && value >= 0, `${label} must be a nonnegative safe integer`)
  return value
}
export function arenaCoordinate(value: number): number {
  assert(Number.isFinite(value) && value >= 128 && value <= 14272, "Coordinate outside audited finite arena")
  return value
}
export function validatedPositions(positions: Position[]): Position[] {
  const result: Position[] = []
  for (const point of positions) {
    safeNatural(point.tick, "Projection tick")
    arenaCoordinate(point.x)
    arenaCoordinate(point.y)
    const previous = result.at(-1)
    if (previous) {
      assert(point.tick >= previous.tick, "Projection tick moved backwards/reset")
      if (point.tick === previous.tick) {
        assert.deepEqual(point, previous, "Conflicting duplicate projection tick")
        continue
      }
      assert(
        Math.hypot(point.x - previous.x, point.y - previous.y) <=
          goalCaptureProtocol.maxDisplacementPerTick * (point.tick - previous.tick) +
            goalCaptureProtocol.transitionTolerance,
        "Observed transition exceeds audited motion bound"
      )
    }
    result.push(point)
  }
  assert.equal(result[0]?.tick, 0, "Trajectory must begin at actual tick zero")
  return result
}
export function boundedGoalContrast(east: GoalTrack, west: GoalTrack) {
  assert.equal(east.direction, "east")
  assert.equal(west.direction, "west")
  const tracks = [east, west].map((track) => ({ ...track, positions: validatedPositions(track.positions) }))
  assert.deepEqual(
    tracks[0]?.positions[0],
    tracks[1]?.positions[0],
    "Fresh same-seed runs must share exact initial projection"
  )
  const candidates = tracks.map((track) => track.positions.filter((p) => p.tick >= 80 && p.tick <= 100))
  const pairs = (candidates[0] ?? []).flatMap((e) =>
    (candidates[1] ?? []).map((w) => ({
      east: e,
      west: w,
      key: [Math.abs(e.tick - w.tick), Math.max(e.tick, w.tick), e.tick, w.tick]
    }))
  )
  pairs.sort((a, b) => {
    for (let i = 0; i < 4; i++) {
      const d = (a.key[i] ?? 0) - (b.key[i] ?? 0)
      if (d) return d
    }
    return 0
  })
  const selected = pairs[0]
  assert(selected, "Each trajectory needs an actual endpoint in [80,100]")
  const referenceTick = Math.min(selected.east.tick, selected.west.tick)
  const outcomes = tracks.map((track) => {
    safeNatural(track.suppliedTick, "Supplied tick")
    safeNatural(track.acceptedTick, "Accepted tick")
    assert(
      track.suppliedTick < 60 && track.suppliedTick <= track.acceptedTick && track.acceptedTick < referenceTick,
      "Goal must be supplied then accepted before reference tick"
    )
    for (const coordinate of [track.startX, track.startY, track.targetX, track.targetY]) arenaCoordinate(coordinate)
    const observed = track.direction === "east" ? selected.east : selected.west
    const initial = track.positions[0]
    assert(initial)
    const uncertainty = 6 * Math.abs(observed.tick - referenceTick)
    const dx = observed.x - initial.x
    const distanceBefore = Math.hypot(track.targetX - track.startX, track.targetY - track.startY)
    const distanceAfter = Math.hypot(track.targetX - observed.x, track.targetY - observed.y)
    return {
      direction: track.direction,
      observed,
      initial,
      suppliedPoint: { x: track.startX, y: track.startY },
      fixedTarget: { x: track.targetX, y: track.targetY },
      suppliedTick: track.suppliedTick,
      acceptedTick: track.acceptedTick,
      dx,
      uncertainty,
      distanceBefore,
      distanceAfter,
      directionMargin: (track.direction === "east" ? dx : -dx) - uncertainty - 30,
      approachMargin: distanceBefore - distanceAfter - uncertainty - 20
    }
  })
  const [e, w] = outcomes
  assert(e && w)
  const separationMargin = e.dx - w.dx - e.uncertainty - w.uncertainty - 60
  return {
    protocol: goalCaptureProtocol,
    endpointTicks: candidates.map((points) => points.map((p) => p.tick)),
    selectionKey: selected.key,
    referenceTick,
    outcomes,
    separationMargin,
    spatialPass: outcomes.every((o) => o.directionMargin > 0 && o.approachMargin > 0) && separationMargin > 0
  }
}
export async function verifyGoalBoundSources(identity: unknown, applicationRoot: string) {
  assert(identity !== null && typeof identity === "object" && "revision" in identity && "dirty" in identity)
  assert.equal(identity.dirty, false, "Audited bound requires a clean source build")
  assert(typeof identity.revision === "string" && /^[a-f0-9]{40}$/.test(identity.revision))
  const pins: unknown = JSON.parse(await readFile(new URL("./stream-goal-bound-pins.json", import.meta.url), "utf8"))
  assert(
    pins !== null && typeof pins === "object" && identity.revision in pins,
    "Source revision needs motion-bound re-audit"
  )
  const approved: unknown = Reflect.get(pins, identity.revision)
  assert(approved !== null && typeof approved === "object" && "sources" in approved && "emitted" in approved)
  const hash = (bytes: Buffer) => createHash("sha256").update(bytes).digest("hex")
  for (const [kind, manifest] of [
    ["sources", approved.sources],
    ["emitted", approved.emitted]
  ] as const) {
    assert(manifest !== null && typeof manifest === "object")
    for (const [file, expected] of Object.entries(manifest)) {
      const bytes: Buffer =
        kind === "sources"
          ? execFileSync("git", ["show", `${identity.revision}:${file}`], {
              cwd: path.resolve(import.meta.dirname, "../..")
            })
          : await readFile(path.join(applicationRoot, file))
      assert.equal(hash(bytes), expected, `Audited motion-bound ${kind} drift: ${file}; re-audit required`)
    }
  }
  return { revision: identity.revision, approved, protocol: goalCaptureProtocol }
}
