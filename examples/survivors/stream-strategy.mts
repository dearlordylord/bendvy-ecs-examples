import type { Strategy } from "./stream-strategy-types.mts"

export const revision = "collector-v1"
export const memoryVersion = 1
export const decide: Strategy["decide"] = (observation, memory) => {
  if (observation.phase === 1 || observation.phase === 2)
    return { intention: { $: "UpgradeChoice", index: observation.fallback }, memory, label: "Strengthen this build" }
  let goals = observation.goals
  let best: BendABI.StreamBot.Goal | undefined
  while (goals.$ === "Con") {
    const goal = goals.head
    if (!best || (goal.kind === 2 && best.kind !== 2) || (goal.kind === best.kind && goal.score > best.score))
      best = goal
    goals = goals.tail
  }
  return {
    intention: best ? { $: "GoalChoice", index: best.index } : { $: "Default" },
    memory,
    label: best?.kind === 2 ? "Return for experience" : best?.kind === 5 ? "Collect the chest" : "Find a safe route"
  }
}
