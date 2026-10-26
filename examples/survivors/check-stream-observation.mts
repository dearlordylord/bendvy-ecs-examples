import assert from "node:assert/strict"
import Game from "./dist/web/dist/game.mjs"
import Bot from "./dist/web/dist/stream-bot.mjs"
import { list, rows } from "./host-values.mts"

function stateOf(packet: BendABI.Game.Packet) {
  if (packet.$ === "Failed") throw Error(packet.error)
  return packet.state
}
let state = stateOf(Game.start_seed(0, 0, 982451653))
for (let index = 0; index < 100; ++index) state = stateOf(Game.advance_live(state, 0, 0))
const run = state.run
const view: BendABI.StreamBot.View = {
  $: "View",
  px: run.player.px,
  py: run.player.py,
  halfWidth: 512,
  halfHeight: 320
}
const enemy = rows(state.snapshots).find((row) => row.$ === "EnemySnapshot")
assert.ok(enemy && enemy.$ === "EnemySnapshot")
const nearEnemy: BendABI.Game.Snapshot = {
  ...enemy,
  enemy: { ...enemy.enemy, spatial: { ...enemy.enemy.spatial, x: view.px + 300, y: view.py } }
}
const pickup: BendABI.Game.Snapshot = {
  $: "PickupSnapshot",
  pickup: {
    $: "State",
    identity: 2000,
    spatial: { $: "Spatial", x: view.px + 100, y: view.py, age: 0, radius: 5 },
    payload: { $: "Payload", generation: 1, active: true, item: { $: "Xp", amount: 10, accumulator: false } }
  }
}
const crowded = list([...Array.from({ length: 1000 }, () => nearEnemy), pickup])
assert.equal(rows(Bot.seen(crowded, view, 0, 128, list([]))).length, 128)
assert.equal(rows(Bot.seen(crowded, view, 2, 128, list([]))).length, 1)
assert.equal(rows(Bot.known(list([pickup]), view, 128, list([]))).length, 0)
const away = { ...view, px: view.px + 1000 }
assert.equal(rows(Bot.known(list([pickup]), away, 128, list([]))).length, 1)
const plan = Bot.plan(Bot.initial(), run, state.offers, crowded, 1024, 640)
assert.ok(rows(plan.observation.threats).length <= 192)
assert.ok(rows(plan.observation.goals).length <= 8)
assert.equal(rows(plan.memory.pickups).length, 1)
assert.equal("world" in plan.observation, false)
assert.equal(plan.observation.truncated, true)
process.stdout.write("Stream observation: independent caps, discovery memory and bounded actual policy PASS\n")
