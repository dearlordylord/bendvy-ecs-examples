import { object, number, text } from "./host-values.mts"
import type { Decision } from "./stream-strategy-types.mts"

export function boundedMemory(value: unknown): unknown {
  let remaining = 8192
  let bytes = 65536
  function visit(item: unknown, depth: number): void {
    bytes -= 8
    if (--remaining < 0 || depth > 12 || bytes < 0) throw Error("Strategy memory exceeds 8192 values or depth 12")
    if (item === null || item === undefined || typeof item === "boolean") return
    if (typeof item === "number" && Number.isFinite(item)) return
    if (typeof item === "string" && item.length <= 4096) {
      bytes -= new TextEncoder().encode(item).byteLength
      if (bytes < 0) throw Error("Strategy memory exceeds 64 KiB")
      return
    }
    if (Array.isArray(item)) {
      for (const child of item) visit(child, depth + 1)
      return
    }
    if (typeof item === "object" && Object.getPrototypeOf(item) === Object.prototype) {
      for (const [key, child] of Object.entries(item)) {
        bytes -= new TextEncoder().encode(key).byteLength
        if (key.length > 256 || bytes < 0) throw Error("Strategy memory key is too long")
        visit(child, depth + 1)
      }
      return
    }
    throw Error("Strategy memory must be finite plain data")
  }
  visit(value, 0)
  const result: unknown = structuredClone(value)
  if (new TextEncoder().encode(JSON.stringify(result) ?? "").byteLength > 65536)
    throw Error("Strategy memory exceeds 64 KiB")
  return result
}
function index(value: unknown): number {
  const result = number(value)
  if (!Number.isInteger(result) || result < 0 || result > 0xffffffff) throw Error("Invalid strategy choice index")
  return result
}
export function decision(value: unknown): Decision {
  const result = object(value)
  const raw = object(result.intention)
  const label = text(result.label)
  if (label.length > 160) throw Error("Strategy intention label exceeds 160 characters")
  let intention: BendABI.StreamBot.Intention
  switch (raw.$) {
    case "GoalChoice":
      intention = { $: "GoalChoice", index: index(raw.index) }
      break
    case "UpgradeChoice":
      intention = { $: "UpgradeChoice", index: index(raw.index) }
      break
    case "Default":
      intention = { $: "Default" }
      break
    default:
      throw Error("Unknown strategy intention")
  }
  return { intention, memory: boundedMemory(result.memory), label }
}
