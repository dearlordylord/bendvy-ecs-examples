import assert from "node:assert/strict"
import { test } from "node:test"
import { boundedMemory, decision } from "./stream-strategy-values.mts"

void test("accepts only finite bounded plain-data strategy memory", () => {
  const memory = { goal: 3, route: [1, 2], note: "XP", nested: { found: true } }
  assert.deepEqual(boundedMemory(memory), memory)
  for (const invalid of [Infinity, NaN, () => 1, new Date(), new Map(), "x".repeat(4097)])
    assert.throws(() => boundedMemory(invalid))
  assert.throws(() => boundedMemory(Array.from({ length: 100 }, () => "☾".repeat(1000))), /64 KiB/)
  const cyclic: { self?: unknown } = {}
  cyclic.self = cyclic
  assert.throws(() => boundedMemory(cyclic))
})

void test("parses strategy intentions without granting world mutation", () => {
  const parsed = decision({ intention: { $: "GoalChoice", index: 2 }, memory: null, label: "Collect XP" })
  assert.deepEqual(parsed.intention, { $: "GoalChoice", index: 2 })
  for (const intention of [{ $: "GoalChoice", index: -1 }, { $: "UpgradeChoice", index: NaN }, { $: "SpawnEnemy" }])
    assert.throws(() => decision({ intention, memory: null, label: "bad" }))
  assert.throws(() => decision({ intention: { $: "Default" }, memory: null, label: "x".repeat(161) }))
})
