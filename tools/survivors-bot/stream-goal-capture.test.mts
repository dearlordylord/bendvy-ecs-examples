import assert from "node:assert/strict"
import test from "node:test"
import {
  boundedGoalContrast,
  validatedPositions,
  verifyGoalBoundSources,
  type GoalTrack,
  type Position
} from "./stream-goal-capture.mts"

function track(direction: "east" | "west", endpoints: Position[]): GoalTrack {
  return {
    direction,
    positions: [{ tick: 0, x: 7200, y: 7200 }, ...endpoints],
    startX: 7200,
    startY: 7200,
    targetX: direction === "east" ? 7400 : 7000,
    targetY: 7200,
    suppliedTick: 30,
    acceptedTick: 40
  }
}
await test("endpoint ties use ticks only, irrespective of favorable coordinates", () => {
  const result = boundedGoalContrast(
    track("east", [
      { tick: 80, x: 7200, y: 7200 },
      { tick: 82, x: 7210, y: 7200 }
    ]),
    track("west", [{ tick: 81, x: 7200, y: 7200 }])
  )
  assert.deepEqual(result.selectionKey, [1, 81, 80, 81])
  assert.equal(result.spatialPass, false)
})
await test("identical duplicate ticks collapse, conflicting duplicates and resets reject", () => {
  const p = { tick: 0, x: 7200, y: 7200 }
  assert.deepEqual(validatedPositions([p, p]), [p])
  assert.throws(() => validatedPositions([p, { ...p, x: 7201 }]), /Conflicting duplicate/)
  assert.throws(() => validatedPositions([p, { ...p, tick: 2 }, { ...p, tick: 1 }]), /backwards/)
})
await test("raw directional separation cannot pass when timing uncertainty explains it", () => {
  const result = boundedGoalContrast(
    track("east", [{ tick: 80, x: 7231, y: 7200 }]),
    track("west", [{ tick: 100, x: 7169, y: 7200 }])
  )
  assert.equal(result.outcomes[0]?.dx, 31)
  assert.equal(result.outcomes[1]?.dx, -31)
  assert.equal(result.spatialPass, false)
  assert(result.separationMargin < 0)
})
await test("actual opposite motion passes with conservative uncertainty and exact baselines", () => {
  const result = boundedGoalContrast(
    track("east", [{ tick: 81, x: 7285, y: 7200 }]),
    track("west", [{ tick: 83, x: 7127, y: 7200 }])
  )
  assert.equal(result.referenceTick, 81)
  assert.equal(result.outcomes[1]?.uncertainty, 12)
  assert.equal(result.spatialPass, true)
})
await test("oversized uncertainty fails closed and impossible observed motion rejects", () => {
  const result = boundedGoalContrast(
    track("east", [{ tick: 80, x: 7280, y: 7200 }]),
    track("west", [{ tick: 100, x: 7120, y: 7200 }])
  )
  assert.equal(result.spatialPass, false)
  assert.throws(
    () =>
      validatedPositions([
        { tick: 0, x: 7200, y: 7200 },
        { tick: 1, x: 7207, y: 7200 }
      ]),
    /motion bound/
  )
})
await test("post-endpoint intervention and invalid coordinates cannot count", () => {
  const east = track("east", [{ tick: 81, x: 7285, y: 7200 }])
  const west = track("west", [{ tick: 83, x: 7127, y: 7200 }])
  assert.throws(() => boundedGoalContrast({ ...east, acceptedTick: 81 }, west), /before reference/)
  assert.throws(() => validatedPositions([{ tick: 0, x: NaN, y: 7200 }]), /finite arena/)
})
await test("unreviewed source revisions and dirty builds cannot inherit the bound", async () => {
  await assert.rejects(verifyGoalBoundSources({ revision: "0".repeat(40), dirty: false }, "/unused"), /re-audit/)
  await assert.rejects(verifyGoalBoundSources({ revision: "1".repeat(40), dirty: true }, "/unused"), /clean source/)
})
