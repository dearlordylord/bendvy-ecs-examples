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
const nearEnemy: BendABI.GameObservation.Snapshot = {
  ...enemy,
  enemy: { ...enemy.enemy, spatial: { ...enemy.enemy.spatial, x: view.px + 300, y: view.py } }
}
const pickup: BendABI.GameObservation.Snapshot = {
  $: "PickupSnapshot",
  pickup: {
    $: "State",
    identity: 2000,
    spatial: { $: "Spatial", x: view.px + 100, y: view.py, age: 0, radius: 5 },
    payload: { $: "Payload", generation: 1, active: true, item: { $: "Xp", amount: 10, accumulator: false } }
  }
}
const shot = rows(state.snapshots).find((row) => row.$ === "ProjectileSnapshot")
assert.ok(shot && shot.$ === "ProjectileSnapshot")
const hostile: BendABI.GameObservation.Snapshot = {
  ...shot,
  projectile: {
    ...shot.projectile,
    spatial: { ...shot.projectile.spatial, x: view.px + 50, y: view.py, radius: 4 },
    side: { $: "HostileShot" },
    payload: { ...shot.projectile.payload, active: true },
    trajectory: { ...shot.projectile.trajectory, vx: 1, life: 300 }
  }
}
const inactive: BendABI.GameObservation.Snapshot = {
  ...nearEnemy,
  enemy: { ...nearEnemy.enemy, vitals: { ...nearEnemy.enemy.vitals, health: 0 } }
}
const crowded = list([
  ...Array.from({ length: 500 }, () => inactive),
  ...Array.from({ length: 1000 }, () => nearEnemy),
  pickup,
  hostile
])
assert.equal(rows(Bot.seen(crowded, view, 0, 128, list([]))).length, 128)
assert.equal(rows(Bot.seen(crowded, view, 2, 128, list([]))).length, 1)
assert.equal(rows(Bot.known(list([pickup]), view, 128, list([]))).length, 0)
const away = { ...view, px: view.px + 1000 }
assert.equal(rows(Bot.known(list([pickup]), away, 128, list([]))).length, 1)
const plan = Bot.plan(Bot.initial(), run, state.offers, crowded, 1024, 640)
assert.ok(rows(plan.observation.threats).length <= 192)
assert.equal(rows(plan.observation.threats).filter((threat) => threat.hostile).length, 1)
assert.equal(rows(plan.observation.offers).length, 0)
assert.ok(rows(plan.observation.goals).length <= 8)
assert.equal(rows(plan.memory.pickups).length, 1)
assert.equal("world" in plan.observation, false)
assert.equal(plan.observation.truncated, true)
process.stdout.write("Stream observation: independent caps, discovery memory and bounded actual policy PASS\n")

const clear = Bot.plan(Bot.initial(), run, state.offers, list([]), 1024, 640)
const east = rows(clear.observation.goals).find((goal) => goal.kind === 13)
assert.ok(east, "Clear native candidates must include east")
const eastChosen = Bot.choose(clear.memory, east.index)
assert.equal(eastChosen.navigation.preferred.$, "Some")
assert.deepEqual(Bot.choose(eastChosen, 0), eastChosen, "Picking the retained row preserves route age")
assert.deepEqual(Bot.choose(eastChosen, 99), eastChosen, "An unavailable index preserves all memory")
const movedRun = { ...run, player: { ...run.player, px: run.player.px + 60 } }
const afterMove = Bot.plan(eastChosen, movedRun, state.offers, list([]), 1024, 640)
assert.equal(afterMove.memory.navigation.preferred.$, "Some")
if (afterMove.memory.navigation.preferred.$ === "Some") {
  assert.equal(
    afterMove.memory.navigation.preferred.value.choice.goal.x,
    east.x,
    "Cardinal endpoint must not rebase after movement"
  )
  assert.equal(afterMove.memory.navigation.preferred.value.choice.goal.y, east.y)
}
const atEast = { ...run, player: { ...run.player, px: east.x, py: east.y } }
assert.equal(
  Bot.plan(eastChosen, atEast, state.offers, list([]), 1024, 640).memory.navigation.preferred.$,
  "None",
  "Reached cardinal releases preference"
)

for (const item of [
  { $: "Xp", amount: 10, accumulator: false },
  { $: "Chest" },
  { $: "Relic", stage: 0 }
] satisfies BendABI.PickupState.Item[]) {
  const physical: Extract<BendABI.GameObservation.Snapshot, { $: "PickupSnapshot" }> = {
    ...pickup,
    pickup: { ...pickup.pickup, payload: { ...pickup.pickup.payload, item } }
  }
  const discovery = Bot.plan(Bot.initial(), run, state.offers, list([physical]), 1024, 640)
  const available = rows(discovery.observation.goals).find(
    (goal) => goal.seed === physical.pickup.identity && goal.generation === (item.$ === "Relic" ? 0 : 1)
  )
  assert.ok(available, `${item.$}: discovered actor must be selectable`)
  const selected = Bot.choose(discovery.memory, available.index)
  const atItem: BendABI.GameObservation.Run = {
    ...run,
    player: { ...run.player, px: physical.pickup.spatial.x, py: physical.pickup.spatial.y }
  }
  const near = Bot.plan(selected, atItem, state.offers, list([physical]), 1024, 640)
  assert.equal(near.memory.navigation.preferred.$, "Some", `${item.$}: proximity cannot simulate collection`)
  const collected = Bot.plan(near.memory, atItem, state.offers, list([]), 1024, 640)
  assert.equal(collected.memory.navigation.preferred.$, "None", `${item.$}: observed disappearance releases preference`)
  const recycled: typeof physical = {
    ...physical,
    pickup: {
      ...physical.pickup,
      identity: item.$ === "Relic" ? physical.pickup.identity + 1 : physical.pickup.identity,
      payload: { ...physical.pickup.payload, generation: 2 }
    }
  }
  assert.equal(
    Bot.plan(selected, atItem, state.offers, list([recycled]), 1024, 640).memory.navigation.preferred.$,
    "None",
    `${item.$}: recycled identity releases old preference`
  )
}
assert.ok(Bot.same_goals(clear.observation.goals, clear.observation.goals))
assert.equal(Bot.same_goals(list([{ ...east, generation: east.generation + 1 }]), list([east])), false)
assert.equal(Bot.same_goals(list([{ ...east, score: east.score + 1 }]), list([east])), true)
process.stdout.write(
  "Stream preferences: fixed cardinal endpoint, physical XP/chest/relic collection identity, public picks and published identity PASS\n"
)

if (eastChosen.navigation.preferred.$ === "Some") {
  const route = rows(eastChosen.navigation.preferred.value.choice.path)
  while (route.length > 1 && route[0] && Math.hypot(route[0].x - run.player.px, route[0].y - run.player.py) < 35)
    route.shift()
  const waypoint = route[0]
  assert.ok(waypoint)
  const crossingShot = {
    ...hostile,
    projectile: { ...hostile.projectile, spatial: { ...hostile.projectile.spatial, x: waypoint.x, y: waypoint.y } }
  }
  const dangerRun = { ...run, session: { ...run.session, tick: run.session.tick + 1 } }
  const dangerous = Bot.plan(eastChosen, dangerRun, state.offers, list([crossingShot]), 1024, 640)
  assert.equal(
    dangerous.memory.navigation.policy.lastPlan,
    eastChosen.navigation.policy.lastPlan,
    "Hostile-only danger must not be explained by an autonomous replan event"
  )
  const preferred = dangerous.memory.navigation.preferred
  if (preferred.$ === "Some") {
    assert.equal(
      preferred.value.plannedAt,
      dangerRun.session.tick,
      "Hostile waypoint danger must replan before the periodic deadline"
    )
    assert.equal(preferred.value.choice.goal.x, east.x)
    assert.equal(preferred.value.choice.goal.y, east.y)
  }
  process.stdout.write(
    "Stream preferences: hostile-only waypoint danger reroutes to the same endpoint or releases bounded failure PASS\n"
  )
}
