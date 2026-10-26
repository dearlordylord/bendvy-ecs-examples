import { object, text, number, errorMessage, rows } from "./host-values.mts"
import { boundedMemory, decision } from "./stream-strategy-values.mts"
import type { Strategy, WorkerInput, WorkerOutput } from "./stream-strategy-types.mts"
let strategy: Strategy | undefined
const send = (message: WorkerOutput) => self.postMessage(message)
self.addEventListener("message", (event: MessageEvent<WorkerInput>) => {
  void handle(event.data).catch((error: unknown) =>
    send({ kind: "failure", message: errorMessage(error).slice(0, 500) })
  )
})
async function handle(input: WorkerInput) {
  if (input.kind === "prepare") {
    const imported: unknown = await import(input.url)
    const module = object(imported)
    const revision = text(module.revision)
    const memoryVersion = number(module.memoryVersion)
    if (
      revision.length < 1 ||
      revision.length > 128 ||
      !Number.isInteger(memoryVersion) ||
      memoryVersion < 0 ||
      memoryVersion > 0xffffffff
    )
      throw Error("Invalid strategy revision or memoryVersion")
    const fn = module.decide
    if (typeof fn !== "function") throw Error("Strategy must export decide")
    strategy = {
      revision,
      memoryVersion,
      decide: async (observation, memory) => {
        const result: unknown = await Reflect.apply(fn, undefined, [observation, boundedMemory(memory)])
        return decision(result)
      }
    }
    const smoke = await strategy.decide(input.observation, input.memoryVersion === memoryVersion ? input.memory : null)
    const intent = smoke.intention
    const upgrading = input.observation.phase === 1 || input.observation.phase === 2
    if (
      (intent.$ === "UpgradeChoice" && (!upgrading || intent.index >= rows(input.observation.offers).length)) ||
      (intent.$ === "GoalChoice" && (upgrading || intent.index >= rows(input.observation.goals).length))
    )
      throw Error("Strategy smoke decision is unavailable in the supplied observation")
    send({ kind: "ready", revision, memoryVersion, reset: input.memoryVersion !== memoryVersion })
  } else {
    if (!strategy) throw Error("Strategy is not prepared")
    const result = await strategy.decide(input.observation, input.memory)
    send({ kind: "decision", identity: input.identity, decision: result })
  }
}
