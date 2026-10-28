import game-observation.bend as Model
import pickup-state.bend as Pickup
import run-state.bend as RS
# Native complete-run consumer: only public start/configure/choose/advance inputs.
# No injected clock, inventory, entity, health or terminal state.
import Base
import game-components.bend as Components
import game.bend as G
import enemy-combat.bend as Enemy
import enemy-presentation.bend as EnemyView
import offline-policy.bend as Policy

def report_numbers(rows: List<&2,U32>) -> String:
  match rows:
    case []: ""
    case n <> []: U32.show(n)
    case n <> rest: U32.show(n) ++ "," ++ report_numbers(rest)

type Stats is Data: Stats{boss: Bool,chest: Bool,level: Bool,decisions: U32}
type Controlled is Type: Controlled{memory: Policy.Memory,packet: G.Packet}
def phase(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{phase,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: phase
def tick(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: tick
def hp(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,hp,_,_,_,_,_,_,_,_,_,_,_,_,_}}: hp
def maxHp(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,maxHp,_,_,_,_,_,_,_,_,_,_,_,_}}: maxHp
def weapons(run: Model.Run) -> List<&2,U32>:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,weapons,_,_,_,_,_,_,_,_,_,_}}: weapons
def passives(run: Model.Run) -> List<&2,U32>:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,passives,_,_,_,_,_,_,_,_,_}}: passives
def level(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,level,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: level
def kills(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,kills,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: kills
def gold(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,gold,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: gold
def contains(values: List<&2,U32>,+id: U32) -> Bool:
  match values:
    case []: False{}
    case value <> rest: Bool.or(U32.is_eq(value,id),contains(rest,id))
# Qualification follows the starter's engine-owned recipe before expanding the
# build. This reserves passive capacity and keeps movement's self-field model
# applicable until the first real evolution has been collected.
def witness_weapon() -> U32: G.starter(2)
def required_passive() -> U32: G.evolution_passive(witness_weapon())
def starter_evolved(run: Model.Run) -> Bool: U32.is_le(9,G.at(weapons(run),witness_weapon()))
def missing_prerequisite(run: Model.Run) -> Bool: U32.is_eq(G.at(passives(run),required_passive()),0)
def seed(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,seed,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: seed
def banned_weapons(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,banned,_}}: banned
def banned_passives(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,banned}}: banned
def rerolls(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,rerolls,_,_,_,_}}: rerolls
def preferred_weapon(id: U32) -> Bool: contains([4,19,10,0,2,17],id)
def passive_rank(id: U32) -> U32: G.at([4,1,3,99,99,99,2,5,99,99,99,0,99,99,99,99,99,99],id)
def broad_offer_score(offer: Model.Offer,+run: Model.Run) -> U32:
  match offer:
    case Model.Offer{3,_,_}: 1000
    case Model.Offer{5,_,_}: 1000
    case Model.Offer{0,+id,_}: ((170 + 90 * Bool.to_u32(U32.is_eq(id,4)) + 30 * Bool.to_u32(U32.is_lt(0,G.at(weapons(run),id)))) * Bool.to_u32(preferred_weapon(id)) : U32)
    case Model.Offer{1,+id,_}: ((210 - U32.min(99,passive_rank(id)) * 5 + 20 * Bool.to_u32(U32.is_eq(G.at(passives(run),id),0))) * Bool.to_u32(U32.is_lt(passive_rank(id),6)) : U32)
    case Model.Offer{2,_,_}: (10 + 290 * Bool.to_u32(U32.is_lt((hp(run) * 10 : U32),(maxHp(run) * 7 : U32))) : U32)
    case Model.Offer{4,_,_}: 5
    case _: 0
def recipe_slot_available(offer: Model.Offer) -> Bool:
  match offer:
    case Model.Offer{1,_,_}: True{}
    case _: False{}
def support_keeps_slot(id: U32,+run: Model.Run) -> Bool:
  +before = passives(run)
  +after = G.bump(before,id)
  Bool.or(Bool.not(missing_prerequisite(run)),Bool.or(U32.is_eq(G.owned(before),G.owned(after)),recipe_slot_available(G.passive_offer(required_passive(),after))))
def focused_offer_score(offer: Model.Offer,+run: Model.Run) -> U32:
  match offer:
    case Model.Offer{3,_,_}: 1000
    case Model.Offer{5,_,_}: 1000
    case Model.Offer{0,id,_}: (800 * Bool.to_u32(U32.is_eq(id,witness_weapon())) : U32)
    case Model.Offer{1,+id,rank}: G.choose_id(Bool.and(U32.is_eq(id,required_passive()),missing_prerequisite(run)),900,(broad_offer_score(Model.Offer{1,id,rank},run) * Bool.to_u32(support_keeps_slot(id,run)) : U32))
    case Model.Offer{2,_,_}: 1
    case Model.Offer{4,_,_}: 1
    case _: 0
def scored_offer(evolved: Bool,offer: Model.Offer,run: Model.Run) -> U32:
  match evolved:
    case True{}: broad_offer_score(offer,run)
    case False{}: focused_offer_score(offer,run)
def offer_score(offer: Model.Offer,+run: Model.Run) -> U32: scored_offer(starter_evolved(run),offer,run)
def best_offer(offers: List<&2,Model.Offer>,+run: Model.Run,+index: U32,+best: U32,+score: U32) -> U32:
  match offers:
    case []: best
    case +offer <> rest: best_offer(rest,run,(index + 1 : U32),G.choose_id(U32.is_lt(score,offer_score(offer,run)),index,best),U32.max(score,offer_score(offer,run)))
# Forecast only public deterministic offers. Actual execution still consumes
# the original World once through G.reroll; no speculative World is constructed.
def recipe_offered(offers: List<&2,Model.Offer>) -> Bool:
  match offers:
    case []: False{}
    case Model.Offer{1,id,_} <> rest: Bool.or(U32.is_eq(id,required_passive()),recipe_offered(rest))
    case _ <> rest: recipe_offered(rest)
def reroll_offers(nextSeed: U32,+run: Model.Run) -> List<&2,Model.Offer>:
  G.filter_offers(G.make_offers(nextSeed,weapons(run),passives(run)),banned_weapons(run),banned_passives(run))
def reroll_reaches_recipe(fuel: Nat,+nextSeed: U32,+run: Model.Run) -> Bool:
  match fuel:
    case 0n: False{}
    case 1n+rest: Bool.or(recipe_offered(reroll_offers(G.reroll_seed(nextSeed),run)),reroll_reaches_recipe(rest,G.reroll_seed(nextSeed),run))
type RewardAction is Data: Choose{index: U32} Reroll{}
def selected_reward(reroll: Bool,offers: List<&2,Model.Offer>,run: Model.Run) -> RewardAction:
  match reroll:
    case True{}: Reroll{}
    case False{}: Choose{best_offer(offers,run,0,0,0)}
def reward_action(+offers: List<&2,Model.Offer>,+run: Model.Run) -> RewardAction:
  selected_reward(Bool.and(U32.is_eq(phase(run),1),Bool.and(Bool.not(starter_evolved(run)),Bool.and(missing_prerequisite(run),Bool.and(Bool.not(recipe_offered(offers)),reroll_reaches_recipe(U32.to_nat(rerolls(run)),seed(run),run))))),offers,run)
def apply_reward(state: G.State,action: RewardAction) -> G.Packet:
  match action:
    case Choose{index}: G.choose(state,index)
    case Reroll{}: G.reroll(state)
def evolution_ready(offer: Model.Offer) -> Bool:
  match offer:
    case Model.Offer{3,_,_}: True{}
    case _: False{}
def chest_ready(+run: Model.Run) -> Bool:
  Bool.or(starter_evolved(run),evolution_ready(G.evolution_offer(weapons(run),0,passives(run))))
def chest_goal_keep(ready: Bool,+snapshot: Model.Snapshot,+rest: List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match snapshot:
    case Model.PickupSnapshot{Pickup.State{_,Pickup.Payload{Pickup.Chest{},_,_},_}}: Bool.pick(List<&2,Model.Snapshot>,ready,snapshot <> rest,rest)
    case _: snapshot <> rest
def movement_snapshots(+ready: Bool,rows: List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case body <> rest: chest_goal_keep(ready,body,movement_snapshots(ready,rest))
# Reuse the ordinary controller's retained spatial-planning memory. Movement
# observes the real run and typed snapshots and feeds only public gameplay input.
# Full game observations remain unchanged; only planner goals defer early chests.
def move(state: G.State,result: Policy.Memory & (F32 & F32)) -> Controlled:
  (memory,direction) = result
  (dx,dy) = direction
  Controlled{memory,G.advance(state,dx,dy)}
def step(phase: U32,state: G.State,+run: Model.Run,offers: List<&2,Model.Offer>,memory: Policy.Memory,snapshots: List<&2,Model.Snapshot>) -> Controlled:
  match phase:
    case 1: Controlled{memory,apply_reward(state,reward_action(offers,run))}
    case 2: Controlled{memory,apply_reward(state,reward_action(offers,run))}
    case _: move(state,Policy.movement(memory,run,movement_snapshots(chest_ready(run),snapshots)))
def saw_boss(rows: List<&2,Enemy.State>) -> Bool: EnemyView.boss_seen(rows)
def observe(stats: Stats,+run: Model.Run,rows: List<&2,Enemy.State>) -> Stats:
  match stats:
    case Stats{boss,chest,level,decisions}: Stats{Bool.or(boss,saw_boss(rows)),Bool.or(chest,U32.is_eq(phase(run),2)),Bool.or(level,U32.is_eq(phase(run),1)),(decisions + Bool.to_u32(Bool.or(U32.is_eq(phase(run),1),U32.is_eq(phase(run),2))) : U32)}
def evolved(weapons: List<&2,U32>) -> Bool:
  match weapons:
    case []: False{}
    case level <> rest: Bool.or(U32.is_le(9,level),evolved(rest))
def build_observation(+run: Model.Run,stats: Stats) -> String:
  match stats:
    case Stats{boss,chest,seenLevel,decisions}: " boss=" ++ U32.show(Bool.to_u32(boss)) ++ " chest=" ++ U32.show(Bool.to_u32(chest)) ++ " seenLevel=" ++ U32.show(Bool.to_u32(seenLevel)) ++ " evolved=" ++ U32.show(Bool.to_u32(evolved(weapons(run)))) ++ " weapons=[" ++ report_numbers(weapons(run)) ++ "] passives=[" ++ report_numbers(passives(run)) ++ "]"
def finish(ok: Bool,message: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS native full run " ++ message)
    case False{}: IO.die(Unit,1,"FAIL native full run " ++ message)
def report(+run: Model.Run,+stats: Stats) -> IO(Unit):
  match stats:
    case Stats{boss,chest,seenLevel,decisions}: finish(Bool.and(Bool.and(U32.is_eq(phase(run),4),U32.is_eq(hp(run),0)),Bool.and(Bool.and(U32.is_le(36000,tick(run)),U32.is_le(tick(run),37000)),Bool.and(boss,Bool.and(chest,Bool.and(seenLevel,evolved(weapons(run))))))),"tick=" ++ U32.show(tick(run)) ++ " phase=" ++ U32.show(phase(run)) ++ " hp=" ++ U32.show(hp(run)) ++ " level=" ++ U32.show(level(run)) ++ " kills=" ++ U32.show(kills(run)) ++ " gold=" ++ U32.show(gold(run)) ++ " decisions=" ++ U32.show(decisions) ++ build_observation(run,stats))
def remaining(active: Bool,fuel: Nat) -> Nat:
  match active:
    case True{}: fuel
    case False{}: 0n
def progress(log: Bool,+run: Model.Run,stats: Stats) -> IO(Unit):
  match log:
    case True{}: IO.print_err("checkpoint tick=" ++ U32.show(tick(run)) ++ " level=" ++ U32.show(level(run)) ++ " hp=" ++ U32.show(hp(run)) ++ " kills=" ++ U32.show(kills(run)) ++ build_observation(run,stats))
    case False{}:
      do IO<Unit>:
        return Unit{}
def action_observation(action: RewardAction) -> String:
  match action:
    case Choose{index}: "choose index=" ++ U32.show(index)
    case Reroll{}: "reroll"
def reward_progress(log: Bool,+run: Model.Run,offers: List<&2,Model.Offer>) -> IO(Unit):
  match log:
    case True{}: IO.print_err("reward tick=" ++ U32.show(tick(run)) ++ " action=" ++ action_observation(reward_action(offers,run)) ++ " rerollsLeft=" ++ U32.show(rerolls(run)) ++ " starterRank=" ++ U32.show(G.at(weapons(run),witness_weapon())) ++ " prerequisite=" ++ U32.show(required_passive()) ++ " prerequisiteRank=" ++ U32.show(G.at(passives(run),required_passive())) ++ " passiveSlots=" ++ U32.show(G.owned(passives(run))) ++ " chestReady=" ++ U32.show(Bool.to_u32(chest_ready(run))))
    case False{}:
      do IO<Unit>:
        return Unit{}
def loop(fuel: Nat,active: Bool,controlled: Controlled,+stats: Stats) -> IO(Unit):
  match fuel active controlled:
    case 0n _ Controlled{_,G.Packet{G.State{_,run,_,_,_}}}: report(run,stats)
    case _ False{} Controlled{_,G.Packet{G.State{_,run,_,_,_}}}: report(run,stats)
    case 1n+rest True{} Controlled{memory,G.Packet{G.State{world,+run,+offers,+snapshots,+pending}}}:
      do IO<Unit>:
        progress(Bool.and(U32.is_eq(phase(run),0),U32.is_eq((tick(run) % 3600 : U32),0)),run,stats)
        reward_progress(Bool.or(U32.is_eq(phase(run),1),U32.is_eq(phase(run),2)),run,offers)
        loop(rest,Bool.not(Bool.or(U32.is_eq(phase(run),3),U32.is_eq(phase(run),4))),step(phase(run),G.State{world,run,offers,snapshots,pending},run,offers,memory,snapshots),observe(stats,run,G.enemy_observations(snapshots)))
    case _ _ _: IO.die(Unit,1,"Game packet failure")
def configured(packet: G.Packet) -> G.Packet:
  match packet:
    case G.Packet{state}: G.configure(state,0,9)
    case packet: packet
def main() -> IO(Unit): loop(42000n,True{},Controlled{Policy.initial(),configured(G.start(2,364304237))},Stats{False{},False{},False{},0})
