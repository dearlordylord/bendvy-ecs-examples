import game-observation.bend as Model
import pickup-state.bend as Pickup
import enemy-spatial.bend as PickupSpace
import run-state.bend as RS
import Base
import enemy-combat.bend as Enemy
import game-components.bend as Components
import projectile-state.bend as Shot
import enemy-spatial.bend as Space
import game-storage.bend as Storage
import coop-hit-journal.bend as Journal
import coop-combat-prediction-policy.bend as ContactPolicy
import projectile-contact.bend as Contact
import coop-reward-policy.bend as RP
import coop-attach.bend as Attach
import personal-totals.bend as Personal
import game.bend as G
import coop-prediction.bend as Prediction
import coop-combat-prediction.bend as CombatPrediction
import arena.bend as A
import entity-role.bend as Role
import spawn-policy.bend as S
import pools.bend as PL
import projectile-pool.bend as SP
import body-index.bend as BI
import bendvy-ecs-core@0.1.0.2/world.bend as W
import bendvy-ecs-core@0.1.0.2/component.bend as C
import bendvy-ecs-core@0.1.0.2/transaction.bend as T
import bendvy-ecs-core@0.1.0.2/compose.bend as Q
import bendvy-ecs-core@0.1.0.2/capabilities.bend as Cap

type PlayerRef is Data: PlayerRef{id: U32,handle: W.Handle<Storage.Schema>}
type PlayerOffers is Data: PlayerOffers{id: U32,offers: List<&2,Model.Offer>}
type Reward is Data: Reward{kind: U32,collector: U32}
type CoreState is Type:
  CoreState{world: Storage.World(),shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>}
# Observations are immutable outputs, never a serialized simulation result.
type Observation is Data:
  NoObservation{}
  ViewObservation{game: G.Observation,predictionAllowed: Bool,stepDistance: F32,ownPlayerId: U32,choicePending: Bool,round: U32,required: List<&2,U32>,players: List<&2,Components.PlayerRecord>,forecast: CombatPrediction.Scene}
  StepObservation{tick: U32,phase: U32,advanced: Bool,contacts: List<&2,Journal.HitEvent>,contactsOmitted: U32}
type CorePacket is Type:
  CorePacket{state: CoreState,observation: Observation}
  CoreRejected{state: CoreState,message: String}
  CoreFailed{message: String}
def run_phase(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{phase,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: phase
def run_tick(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: tick
def run_px(run: Model.Run) -> F32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{px,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: px
def run_py(run: Model.Run) -> F32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,py,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: py
def run_hp(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,hp,_,_,_,_,_,_,_,_,_,_,_,_,_}}: hp
def run_maxHp(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,maxHp,_,_,_,_,_,_,_,_,_,_,_,_}}: maxHp
def run_xp(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,xp,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: xp
def run_xpNeed(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,xpNeed,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: xpNeed
def run_level(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,level,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: level
def run_kills(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,kills,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: kills
def run_gold(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,gold,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: gold
def run_character(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,character,_,_,_,_,_,_,_,_,_,_,_}}: character
def run_weapons(run: Model.Run) -> List<&2,U32>:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,weapons,_,_,_,_,_,_,_,_,_,_}}: weapons
def run_passives(run: Model.Run) -> List<&2,U32>:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,passives,_,_,_,_,_,_,_,_,_}}: passives
def run_invuln(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,invuln,_,_,_,_,_,_,_,_}}: invuln
def run_seed(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,seed,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: seed
def run_stage(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,stage,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: stage
def run_arcana(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,arcana,_,_,_,_,_,_,_}}: arcana
def run_meta(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,meta,_,_,_,_,_,_}}: meta
def run_revivals(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,revivals,_,_,_,_,_}}: revivals
def run_bosses(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,bosses,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: bosses
def run_mode(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,mode,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: mode
def run_rerolls(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,rerolls,_,_,_,_}}: rerolls
def run_banishes(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,banishes,_,_,_}}: banishes
def run_skips(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,skips,_,_}}: skips
def run_bannedWeapons(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,bannedWeapons,_}}: bannedWeapons
def run_bannedPassives(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,bannedPassives}}: bannedPassives
def run_enemyKinds(run: Model.Run) -> List<&2,U32>:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,enemyKinds,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: enemyKinds
def run_relicCollected(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,relicCollected},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: relicCollected
def with_phase(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{_,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{value,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_tick(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,_,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,value,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_xp(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,_,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,value,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_xpNeed(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,_,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,value,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_level(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,_,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,value,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_gold(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,_,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,value,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_seed(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,_,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,value,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_hp(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,_,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,value,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_invuln(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,_,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,value,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_revivals(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,_,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,value,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_px(run: Model.Run,value: F32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{_,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{value,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_py(run: Model.Run,value: F32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,_,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,value,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_relicCollected(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,_},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,value},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
# Immutable phase input combines the two actual authorities without copying fields.
def player_step_context(shared: RS.Session,personal: RS.PlayerState) -> Model.Run: Model.Run{shared,personal}
def player_replaced(result: C.Replacement<Storage.World(),Components.PlayerRecord>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def save_player(world: Storage.World(),ref: PlayerRef,player: Components.PlayerRecord) -> Storage.World():
  match ref:
    case PlayerRef{_,handle}: player_replaced(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PlayerRest,~Components.PlayerRecord,~Components.PlayerRecord,~Storage.PlayerToken,~Storage.take_players,~Storage.put_players,~Storage.project_player,Storage.player_family(),world,handle,Some{player}))
def save_players(refs: List<&2,PlayerRef>,players: List<&2,Components.PlayerRecord>,world: Storage.World()) -> Storage.World():
  match refs players:
    case ref <> refs player <> players: save_players(refs,players,save_player(world,ref,player))
    case _ _: world
def load_player_result(next: List<&2,Components.PlayerRecord> -> Storage.World() -> Storage.World() & List<&2,Components.PlayerRecord>,loaded: List<&2,Components.PlayerRecord>,result: Storage.World() & C.Access<Components.PlayerRecord>) -> Storage.World() & List<&2,Components.PlayerRecord>:
  match result:
    case (world,C.Found{player}): next(player <> loaded,world)
    case (world,_): next(loaded,world)
def load_players(refs: List<&2,PlayerRef>,loaded: List<&2,Components.PlayerRecord>,world: Storage.World()) -> Storage.World() & List<&2,Components.PlayerRecord>:
  match refs:
    case []: (world,List.reverse(&2,Components.PlayerRecord,loaded))
    case PlayerRef{_,handle} <> rest: load_player_result(load_players(rest),loaded,C.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PlayerRest,~Components.PlayerRecord,~Components.PlayerRecord,~Storage.PlayerToken,~Storage.take_players,~Storage.put_players,~Storage.project_player,Storage.player_family(),world,handle))

def record_id(player: Components.PlayerRecord) -> U32:
  match player:
    case Components.PlayerRecord{id,_,_,_}: id
def record_player(player: Components.PlayerRecord) -> RS.PlayerState:
  match player:
    case Components.PlayerRecord{_,personal,_,_}: personal
def record_connected(player: Components.PlayerRecord) -> Bool:
  match player:
    case Components.PlayerRecord{_,_,connected,_}: connected
def find_player(players: List<&2,Components.PlayerRecord>,+id: U32) -> Maybe<&2,RS.PlayerState>:
  match players:
    case []: None{}
    case Components.PlayerRecord{+pid,personal,_,_} <> rest: Bool.pick(Maybe<&2,RS.PlayerState>,U32.is_eq(pid,id),Some{personal},find_player(rest,id))
def offers_for(rows: List<&2,PlayerOffers>,+id: U32) -> List<&2,Model.Offer>:
  match rows:
    case []: []
    case PlayerOffers{+pid,offers} <> rest: Bool.pick(List<&2,Model.Offer>,U32.is_eq(pid,id),offers,offers_for(rest,id))
def player_connected(players: List<&2,Components.PlayerRecord>,+id: U32) -> Bool:
  match players:
    case []: False{}
    case Components.PlayerRecord{+pid,_,connected,_} <> rest: Bool.pick(Bool,U32.is_eq(pid,id),connected,player_connected(rest,id))
def spectator_target(players: List<&2,Components.PlayerRecord>,fallback: RS.PlayerState) -> RS.PlayerState:
  match players:
    case []: fallback
    case Components.PlayerRecord{_,+personal,+connected,_} <> rest: Bool.pick(RS.PlayerState,Bool.and(connected,U32.is_lt(0,RS.player_hp(personal))),personal,spectator_target(rest,fallback))
# Camera selection is presentation-only; it never writes another player's facts.
def observer_context(shared: RS.Session,+players: List<&2,Components.PlayerRecord>,+own: RS.PlayerState) -> Model.Run:
  +target = spectator_target(players,own)
  Model.Run{shared,Bool.pick(RS.PlayerState,U32.is_eq(RS.player_hp(own),0),RS.player_with_py(RS.player_with_px(own,RS.player_px(target)),RS.player_py(target)),own)}
# The detached cohort receives every player's shared clock/configuration together
# with personal movement/stats, exactly as the authoritative team step does.
def forecast_players(+shared: RS.Session,players: List<&2,Components.PlayerRecord>) -> List<&2,G.PlayerSnapshot>:
  match players:
    case []: []
    case Components.PlayerRecord{id,personal,connected,_} <> tail: G.PlayerSnapshot{id,player_step_context(shared,personal),connected} <> forecast_players(shared,tail)
def view_observation(+shared: RS.Session,+players: List<&2,Components.PlayerRecord>,+snapshots: List<&2,Model.Snapshot>,+id: U32,round: U32,+required: List<&2,U32>,offers: List<&2,Model.Offer>,+personal: RS.PlayerState) -> Observation:
  ViewObservation{G.observation(observer_context(shared,players,personal),offers,snapshots),Prediction.allowed(RS.session_phase(shared),RS.player_hp(personal),player_connected(players,id)),G.run_step_distance(player_step_context(shared,personal)),id,G.contains(required,id),round,required,players,CombatPrediction.initialize(id,RS.session_tick(shared),forecast_players(shared,players),snapshots)}
def observe_player(+shared: RS.Session,+refs: List<&2,PlayerRef>,+snapshots: List<&2,Model.Snapshot>,+round: U32,+required: List<&2,U32>,+offers: List<&2,PlayerOffers>,+pending: List<&2,Reward>,+id: U32,world: Storage.World(),+players: List<&2,Components.PlayerRecord>,own: Maybe<&2,RS.PlayerState>) -> CorePacket:
  match own:
    case None{}: CoreRejected{CoreState{world,shared,refs,snapshots,round,required,offers,pending},"Unknown observing player"}
    case Some{+personal}: CorePacket{CoreState{world,shared,refs,snapshots,round,required,offers,pending},view_observation(shared,players,snapshots,id,round,required,offers_for(offers,id),personal)}
def observe_loaded(+shared: RS.Session,+refs: List<&2,PlayerRef>,+snapshots: List<&2,Model.Snapshot>,+round: U32,+required: List<&2,U32>,+offers: List<&2,PlayerOffers>,+pending: List<&2,Reward>,+id: U32,result: Storage.World() & List<&2,Components.PlayerRecord>) -> CorePacket:
  match result:
    case (world,+players): observe_player(shared,refs,snapshots,round,required,offers,pending,id,world,players,find_player(players,id))
def core_observe(state: CoreState,+id: U32) -> CorePacket:
  match state:
    case CoreState{world,+shared,+refs,+snapshots,+round,+required,+offers,+pending}: observe_loaded(shared,refs,snapshots,round,required,offers,pending,id,load_players(refs,[],world))
type NetworkView is Data: NetworkView{shared: RS.Session,players: List<&2,Components.PlayerRecord>,snapshots: List<&2,Model.Snapshot>,own: U32,round: U32,required: List<&2,U32>,offers: List<&2,Model.Offer>}
type NetworkPacket is Type: NetworkPacket{state: CoreState,view: NetworkView}
def network_visible(snapshot: Model.Snapshot) -> Bool:
  match snapshot:
    case Model.EnemySnapshot{_}: True{}
    case Model.ProjectileSnapshot{projectile}: Shot.present(projectile)
    case Model.PickupSnapshot{pickup}: Pickup.active(pickup)
def network_snapshots(rows: List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case +head <> tail: List.filter.put(Model.Snapshot,head,network_snapshots(tail),network_visible(head))
def network_loaded(+shared: RS.Session,+refs: List<&2,PlayerRef>,+snapshots: List<&2,Model.Snapshot>,+round: U32,+required: List<&2,U32>,+offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,+id: U32,result: Storage.World() & List<&2,Components.PlayerRecord>) -> NetworkPacket:
  match result:
    case (world,players): NetworkPacket{CoreState{world,shared,refs,snapshots,round,required,offers,pending},NetworkView{shared,players,network_snapshots(snapshots),id,round,required,offers_for(offers,id)}}
def core_network_observe(state: CoreState,id: U32) -> NetworkPacket:
  match state:
    case CoreState{world,+shared,+refs,+snapshots,+round,+required,+offers,+pending}: network_loaded(shared,refs,snapshots,round,required,offers,pending,id,load_players(refs,[],world))
def restore_network_own(+shared: RS.Session,+players: List<&2,Components.PlayerRecord>,+snapshots: List<&2,Model.Snapshot>,+id: U32,round: U32,+required: List<&2,U32>,offers: List<&2,Model.Offer>,own: Maybe<&2,RS.PlayerState>) -> Observation:
  match own:
    case None{}: NoObservation{}
    case Some{personal}: view_observation(shared,players,snapshots,id,round,required,offers,personal)
def network_allowed_own(shared: RS.Session,+players: List<&2,Components.PlayerRecord>,id: U32,own: Maybe<&2,RS.PlayerState>) -> Bool:
  match own:
    case None{}: False{}
    case Some{personal}: Prediction.allowed(RS.session_phase(shared),RS.player_hp(personal),player_connected(players,id))
def network_prediction_allowed(view: NetworkView) -> Bool:
  match view:
    case NetworkView{shared,+players,_,+own,_,_,_}: network_allowed_own(shared,players,own,find_player(players,own))
def restore_network(view: NetworkView) -> Observation:
  match view:
    case NetworkView{shared,+players,snapshots,+own,round,required,offers}: restore_network_own(shared,players,snapshots,own,round,required,offers,find_player(players,own))
def completed(state: CoreState) -> CorePacket: CorePacket{state,NoObservation{}}
type PlayerCreated is Type:
  PlayerCreated{world: Storage.World(),ref: PlayerRef}
  PlayerCreateFailed{world: Storage.World()}
def player_activated(+id: U32,run: RS.PlayerState,+handle: W.Handle<Storage.Schema>,result: Storage.World() & W.Status) -> PlayerCreated:
  match result:
    case (world,W.Accepted{}): PlayerCreated{save_player(world,PlayerRef{id,handle},Components.PlayerRecord{id,run,True{},0}),PlayerRef{id,handle}}
    case (world,_): PlayerCreateFailed{world}
def player_reserved(+id: U32,run: RS.PlayerState,result: Storage.World() & W.Reservation<Storage.Schema>) -> PlayerCreated:
  match result:
    case (world,W.Reserved{+handle}): player_activated(id,run,handle,W.activate(~Storage.Schema,~Storage.Store,~Unit,~Unit,world,handle))
    case (world,_): PlayerCreateFailed{world}
def create_player(world: Storage.World(),id: U32,run: RS.PlayerState) -> PlayerCreated:
  player_reserved(id,run,W.reserve_id(~Storage.Schema,~Storage.Store,~Unit,~Unit,world))
def core_started(shared: RS.Session,snapshots: List<&2,Model.Snapshot>,result: PlayerCreated) -> CorePacket:
  match result:
    case PlayerCreated{world,ref}: completed(CoreState{world,shared,[ref],snapshots,0,[],[],[]})
    case PlayerCreateFailed{_}: CoreFailed{"Player entity allocation failed"}
def core_started_packet(packet: G.Packet) -> CorePacket:
  match packet:
    case G.Packet{G.State{world,Model.Run{session,personal},_,snapshots,_}}: core_started(session,snapshots,create_player(world,0,personal))
    case G.Failed{message}: CoreFailed{message}
def core_start(character: U32,meta: U32,seed: U32) -> CorePacket: core_started_packet(G.start_seed(character,meta,seed))

def unlock_run(+mask: U32,run: Model.Run) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+kinds,+relic},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,kinds,relic},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,U32.or(bannedWeapons,U32.and(16777215,U32.xor(mask,16777215))),bannedPassives}}
type PlayerEdit is Data:
  EditConfigure{stage: U32,mode: U32,arcana: U32}
  EditUnlock{mask: U32}
def apply_edit(+shared: RS.Session,edit: PlayerEdit,personal: RS.PlayerState) -> RS.PlayerState:
  match edit:
    case EditConfigure{stage,mode,arcana}: G.run_player(G.mode_configured(G.configured(Model.Run{shared,personal},stage,arcana),mode))
    case EditUnlock{mask}: G.run_player(unlock_run(mask,Model.Run{shared,personal}))
def edit_player(+shared: RS.Session,+id: U32,+edit: PlayerEdit,players: List<&2,Components.PlayerRecord>) -> List<&2,Components.PlayerRecord>:
  match players:
    case []: []
    case Components.PlayerRecord{+pid,+personal,connected,+reviveTick} <> rest: Components.PlayerRecord{pid,Bool.pick(RS.PlayerState,U32.is_eq(pid,id),apply_edit(shared,edit,personal),personal),connected,reviveTick} <> edit_player(shared,id,edit,rest)
def edit_loaded(+id: U32,edit: PlayerEdit,+shared: RS.Session,+refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,result: Storage.World() & List<&2,Components.PlayerRecord>) -> CorePacket:
  match result:
    case (world,players): completed(CoreState{save_players(refs,edit_player(shared,id,edit,players),world),shared,refs,snapshots,round,required,offers,pending})
def edit_core(state: CoreState,+id: U32,edit: PlayerEdit) -> CorePacket:
  match state:
    case CoreState{world,+shared,+refs,snapshots,round,required,offers,pending}: edit_loaded(id,edit,shared,refs,snapshots,round,required,offers,pending,load_players(refs,[],world))
def configure_allowed(allowed: Bool,state: CoreState,+stage: U32,+mode: U32,+arcana: U32) -> CorePacket:
  match allowed state:
    case True{} CoreState{world,+shared,+refs,snapshots,round,required,offers,pending}: edit_loaded(0,EditConfigure{stage,mode,arcana},RS.session_with_mode(RS.session_with_stage(shared,stage),mode),refs,snapshots,round,required,offers,pending,load_players(refs,[],world))
    case False{} state: CoreRejected{state,"Match setup is closed"}
def core_configure(state: CoreState,+stage: U32,+mode: U32,+arcana: U32) -> CorePacket:
  match state:
    case CoreState{world,+shared,refs,snapshots,round,required,offers,pending}: configure_allowed(U32.is_eq(RS.session_tick(shared),0),CoreState{world,shared,refs,snapshots,round,required,offers,pending},U32.min(4,stage),U32.min(3,mode),U32.min(11,arcana))
def unlock_allowed(allowed: Bool,state: CoreState,id: U32,mask: U32) -> CorePacket:
  match allowed:
    case True{}: edit_core(state,id,EditUnlock{mask})
    case False{}: CoreRejected{state,"Match setup is closed"}
def core_configure_unlocks(state: CoreState,id: U32,mask: U32) -> CorePacket:
  match state:
    case CoreState{world,+shared,refs,snapshots,round,required,offers,pending}: unlock_allowed(U32.is_eq(RS.session_tick(shared),0),CoreState{world,shared,refs,snapshots,round,required,offers,pending},id,mask)
def guest_player(+shared: RS.Session,+character: U32,+meta: U32,+arcana: U32) -> RS.PlayerState:
  G.run_player(G.mode_configured(G.configured(Model.Run{shared,RS.PlayerState{(A.center() + 32.0 : F32),A.center(),G.initial_health(character,meta),G.initial_health(character,meta),character,G.bump([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],G.starter(character)),[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],0,arcana,meta,0,3,3,3,0,0}},RS.session_stage(shared),arcana),RS.session_mode(shared)))
def joined(shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,result: PlayerCreated) -> CorePacket:
  match result:
    case PlayerCreated{world,ref}: completed(CoreState{world,shared,List.append(&2,PlayerRef,refs,[ref]),snapshots,round,required,offers,pending})
    case PlayerCreateFailed{world}: CoreRejected{CoreState{world,shared,refs,snapshots,round,required,offers,pending},"Player allocation failed"}
def join_allowed(allowed: Bool,state: CoreState,character: U32,meta: U32,arcana: U32) -> CorePacket:
  match allowed state:
    case True{} CoreState{world,+shared,refs,snapshots,round,required,offers,pending}: joined(shared,refs,snapshots,round,required,offers,pending,create_player(world,1,guest_player(shared,character,meta,arcana)))
    case False{} state: CoreRejected{state,"Join is only allowed before the two-player match starts"}
def core_join(state: CoreState,character: U32,meta: U32,arcana: U32) -> CorePacket:
  match state:
    case CoreState{world,+shared,+refs,snapshots,round,required,offers,pending}: join_allowed(Bool.and(U32.is_eq(RS.session_tick(shared),0),Nat.is_eq(List.length(&2,PlayerRef,refs),1n)),CoreState{world,shared,refs,snapshots,round,required,offers,pending},U32.min(7,character),meta,U32.min(11,arcana))

# A returning guest occupies the existing player record. Setup belongs only to
# the first attachment: reload must not replace equipment, health or reward state.
def attach_configured(mask: U32,packet: CorePacket) -> CorePacket:
  match packet:
    case CorePacket{state,_}: core_configure_unlocks(state,1,mask)
    case packet: packet
def attach_initial(state: CoreState,character: U32,meta: U32,arcana: U32,mask: U32) -> CorePacket:
  attach_configured(mask,core_join(state,character,meta,arcana))
def core_attach(state: CoreState,character: U32,meta: U32,arcana: U32,mask: U32) -> CorePacket:
  match state:
    case CoreState{world,shared,+refs,snapshots,round,required,offers,pending}: Attach.dispatch(~CoreState,~CorePacket,~completed,~attach_initial,List.length(&2,PlayerRef,refs),CoreState{world,shared,refs,snapshots,round,required,offers,pending},character,meta,arcana,mask)

def has_player(refs: List<&2,PlayerRef>,+id: U32) -> Bool:
  match refs:
    case []: False{}
    case PlayerRef{+pid,_} <> rest: Bool.or(U32.is_eq(pid,id),has_player(rest,id))
def join_player_allowed(allowed: Bool,state: CoreState,id: U32,character: U32,meta: U32,arcana: U32) -> CorePacket:
  match allowed state:
    case True{} CoreState{world,+shared,refs,snapshots,round,required,offers,pending}: joined(shared,refs,snapshots,round,required,offers,pending,create_player(world,id,guest_player(shared,character,meta,arcana)))
    case False{} state: CoreRejected{state,"The party is full or the match has started"}
def attach_player_configured(+id: U32,mask: U32,packet: CorePacket) -> CorePacket:
  match packet:
    case CorePacket{state,_}: core_configure_unlocks(state,id,mask)
    case packet: packet
def attach_player_selected(exists: Bool,state: CoreState,+id: U32,character: U32,meta: U32,arcana: U32,mask: U32) -> CorePacket:
  match exists state:
    case True{} state: completed(state)
    case False{} CoreState{world,+shared,+refs,snapshots,round,required,offers,pending}: attach_player_configured(id,mask,join_player_allowed(Bool.and(U32.is_eq(RS.session_tick(shared),0),Bool.and(U32.is_gt(id,0),U32.is_lt(id,4))),CoreState{world,shared,refs,snapshots,round,required,offers,pending},id,U32.min(7,character),meta,U32.min(11,arcana)))
def core_attach_player(state: CoreState,+id: U32,character: U32,meta: U32,arcana: U32,mask: U32) -> CorePacket:
  match state:
    case CoreState{world,shared,+refs,snapshots,round,required,offers,pending}: attach_player_selected(has_player(refs,id),CoreState{world,shared,refs,snapshots,round,required,offers,pending},id,character,meta,arcana,mask)

type Movement is Data: Movement{id: U32,x: F32,y: F32}
def movement_at(rows: List<&2,Movement>,+id: U32) -> Movement:
  match rows:
    case []: Movement{id,0.0,0.0}
    case Movement{+pid,x,y} <> rest: Bool.pick(Movement,U32.is_eq(pid,id),Movement{pid,x,y},movement_at(rest,id))
def player_movement_view(+shared: RS.Session,player: Components.PlayerRecord,movement: Movement) -> G.PlayerView:
  match player movement:
    case Components.PlayerRecord{id,personal,connected,_} Movement{_,x,y}: G.PlayerView{id,player_step_context(RS.session_with_tick(shared,(RS.session_tick(shared) + 1 : U32)),personal),x,y,connected}
def player_movement_views(+shared: RS.Session,+moves: List<&2,Movement>,players: List<&2,Components.PlayerRecord>) -> List<&2,G.PlayerView>:
  match players:
    case []: []
    case +player <> rest: player_movement_view(shared,player,movement_at(moves,record_id(player))) <> player_movement_views(shared,moves,rest)
# Views are immutable per-tick projections, never another gameplay authority.
# Connected eligibility is explicit; every owner retains its real health and loadout.
def player_view(+shared: RS.Session,+dx0: F32,+dy0: F32,+dx1: F32,+dy1: F32,player: Components.PlayerRecord) -> G.PlayerView:
  match player:
    case Components.PlayerRecord{+id,personal,connected,_}: G.PlayerView{id,player_step_context(RS.session_with_tick(shared,(RS.session_tick(shared) + 1 : U32)),personal),Bool.pick(F32,U32.is_eq(id,0),dx0,dx1),Bool.pick(F32,U32.is_eq(id,0),dy0,dy1),connected}
def add_view(eligible: Bool,view: G.PlayerView,tail: List<&2,G.PlayerView>) -> List<&2,G.PlayerView>:
  match eligible:
    case True{}: view <> tail
    case False{}: tail
def player_views(+shared: RS.Session,+dx0: F32,+dy0: F32,+dx1: F32,+dy1: F32,players: List<&2,Components.PlayerRecord>) -> List<&2,G.PlayerView>:
  match players:
    case []: []
    case +player <> rest: player_view(shared,dx0,dy0,dx1,dy1,player) <> player_views(shared,dx0,dy0,dx1,dy1,rest)
# Contact damage is evaluated for each living player, independently of chase
# target. Pickup payloads are assigned once, by nearest eligible G.collector.
def projectile_contact(+run: Model.Run,projectile: Shot.State) -> U32:
  match projectile:
    case Shot.State{Space.Spatial{x,y,_,radius},_,Shot.HostileShot{},_,_}: Bool.to_u32(G.close(x,y,run_px(run),run_py(run),(radius + 10.0 : F32)))
    case _: 0
def enemy_kill_credit(id: U32,owner: Maybe<&2,U32>,kills: U32) -> U32:
  match owner:
    case Some{owner}: (kills * Bool.to_u32(U32.is_eq(id,owner)) : U32)
    case None{}: (kills * Bool.to_u32(U32.is_eq(id,0)) : U32)
def enemy_personal_credit(+run: Model.Run,id: U32,outcome: Enemy.Outcome,credit: Enemy.Credit) -> Enemy.Credit:
  match outcome credit:
    case Enemy.Alive{Enemy.State{space,archetype,_,_,_},_} _: Enemy.Credit{Enemy.contact(space,archetype,run_px(run),run_py(run)),0}
    case Enemy.Killed{_,Enemy.DeathReward{_,_,_,_,_,_,owner}} Enemy.Credit{_,kills}: Enemy.Credit{0,enemy_kill_credit(id,owner,kills)}
    case Enemy.Born{_} _: Enemy.Credit{0,0}
    case Enemy.Sleeping{_} _: Enemy.Credit{0,0}
def pickup_reward_for(own: Bool,reward: Pickup.Reward) -> Pickup.Reward:
  match own:
    case True{}: reward
    case False{}: Pickup.Reward{0,0,0,0,0}
def pickup_credit_at(+team: G.Team,+id: U32,state: Pickup.State,reward: Pickup.Reward) -> G.EntityRow:
  match state:
    case Pickup.State{+space,payload,identity}:
      match space:
        case PickupSpace.Spatial{x,y,_,_}: G.PickupRow{Pickup.Outcome{Pickup.State{space,payload,identity},pickup_reward_for(U32.is_eq(id,G.view_id(G.collector(team,x,y))),reward)}}
def pickup_credit(+team: G.Team,+id: U32,state: Pickup.State,reward: Pickup.Reward) -> G.EntityRow:
  match state reward:
    case state Pickup.Reward{0,0,0,0,0}: G.PickupRow{Pickup.Outcome{state,Pickup.Reward{0,0,0,0,0}}}
    case state reward: pickup_credit_at(team,id,state,reward)
def owned_row_values(+id: U32,+run: Model.Run,row: G.EntityRow,collectorId: U32) -> G.EntityRow:
  match row:
    case G.NoEntityRow{}: G.NoEntityRow{}
    case G.ProjectileRow{Shot.Outcome{+projectile,_}}: G.ProjectileRow{Shot.Outcome{projectile,projectile_contact(run,projectile)}}
    case G.EnemyRow{+outcome,credit}: G.EnemyRow{outcome,enemy_personal_credit(run,id,outcome,credit)}
    case G.PickupRow{outcome}: G.PickupRow{outcome}
def owned_row(+team: G.Team,id: U32,run: Model.Run,+row: G.EntityRow) -> G.EntityRow:
  match row:
    case G.NoEntityRow{}: G.NoEntityRow{}
    case G.EnemyRow{+outcome,credit}: G.EnemyRow{outcome,enemy_personal_credit(run,id,outcome,credit)}
    case G.PickupRow{Pickup.Outcome{state,reward}}: pickup_credit(team,id,state,reward)
    case G.ProjectileRow{_}: owned_row_values(id,run,row,0)
def personal_totals(totals:Personal.Totals) -> G.Totals:
  match totals:
    case Personal.Totals{h,x,g,he,c,k}: G.Totals{h,x,g,he,c,k,[],0}
def personal_count(row:G.EntityRow) -> Personal.Delta:
  match row:
    case G.NoEntityRow{}: Personal.Empty{}
    case G.ProjectileRow{Shot.Outcome{_,h}}: Personal.Projectile{h}
    case G.EnemyRow{_,Enemy.Credit{h,k}}: Personal.Enemy{h,k}
    case G.PickupRow{Pickup.Outcome{_,Pickup.Reward{x,g,he,c,_}}}: Personal.Pickup{x,g,he,c}
type OwnedRowsContext is Data: OwnedRowsContext{team:G.Team,id:U32,run:Model.Run}
def owned_row_context(context:OwnedRowsContext,row:G.EntityRow) -> G.EntityRow:
  match context:
    case OwnedRowsContext{team,id,run}: owned_row(team,id,run,row)
def totals_xp(totals: G.Totals) -> U32:
  match totals:
    case G.Totals{_,xp,_,_,_,_,_,_}: xp
def totals_gold(totals: G.Totals) -> U32:
  match totals:
    case G.Totals{_,_,gold,_,_,_,_,_}: gold
def totals_chests(totals: G.Totals) -> U32:
  match totals:
    case G.Totals{_,_,_,_,chests,_,_,_}: chests
def credit_xp(+run: Model.Run,earned: U32) -> U32: G.earned_xp(earned,run_passives(run),run_meta(run),run_arcana(run))
def credit_gold(+run: Model.Run,earned: U32) -> U32: (earned * (100 + G.at(run_passives(run),15) * 15 + G.at(run_passives(run),14) * 10 + 50 * Bool.to_u32(U32.is_eq(run_mode(run),1)) + G.meta_rank(run_meta(run),8) * 10 + 25 * Bool.to_u32(U32.is_eq(run_arcana(run),6))) / 100 : U32)
def chest_rewards(fuel: Nat,+id: U32,tail: List<&2,Reward>) -> List<&2,Reward>:
  match fuel:
    case 0n: tail
    case 1n+rest: Reward{2,id} <> chest_rewards(rest,id,tail)
type PlayersFinalized is Type:
  FinalizeFailed{message: String}
  PlayersFinalized{world: Storage.World(),players: List<&2,Components.PlayerRecord>,xp: U32,gold: U32,chests: List<&2,Reward>}
def scheduled_record(old: Components.PlayerRecord,+personal: RS.PlayerState,+tick: U32) -> Components.PlayerRecord:
  match old:
    case Components.PlayerRecord{id,+prior,connected,+reviveTick}:
      +newDeath = Bool.and(U32.is_lt(0,RS.player_hp(prior)),U32.is_eq(RS.player_hp(personal),0))
      Components.PlayerRecord{id,personal,connected,Bool.pick(U32,newDeath,(tick + 300 : U32),reviveTick)}
def finalize_living(next: Storage.World() -> List<&2,Components.PlayerRecord> -> U32 -> U32 -> List<&2,Reward> -> PlayersFinalized,+player: Components.PlayerRecord,+view: G.PlayerView,+totals: G.Totals,world: Storage.World(),done: List<&2,Components.PlayerRecord>,xp: U32,gold: U32,chests: List<&2,Reward>) -> PlayersFinalized:
  next(world,scheduled_record(player,G.finish_personal_tick(G.moved_run(view),totals),G.run_tick(G.view_run(view))) <> done,(xp + credit_xp(G.view_run(view),totals_xp(totals)) : U32),(gold + credit_gold(G.view_run(view),totals_gold(totals)) : U32),chest_rewards(U32.to_nat(totals_chests(totals)),record_id(player),chests))
def finalize_eligible(eligible: Bool,next: Storage.World() -> List<&2,Components.PlayerRecord> -> U32 -> U32 -> List<&2,Reward> -> PlayersFinalized,+player: Components.PlayerRecord,+team: G.Team,+rows: List<&2,G.EntityRow>,world: Storage.World(),done: List<&2,Components.PlayerRecord>,xp: U32,gold: U32,chests: List<&2,Reward>) -> PlayersFinalized:
  match eligible:
    case False{}: next(world,player <> done,xp,gold,chests)
    case True{}: finalize_living(next,player,G.team_for_id(team,record_id(player)),personal_totals(Personal.fold(~G.EntityRow,~OwnedRowsContext,~owned_row_context,~personal_count,OwnedRowsContext{team,record_id(player),G.view_run(G.team_for_id(team,record_id(player)))},rows,Personal.Totals{0,0,0,0,0,0})),world,done,xp,gold,chests)
def finalize_players(players: List<&2,Components.PlayerRecord>,+team: G.Team,+rows: List<&2,G.EntityRow>,world: Storage.World(),done: List<&2,Components.PlayerRecord>,xp: U32,gold: U32,chests: List<&2,Reward>) -> PlayersFinalized:
  match players:
    case []: PlayersFinalized{world,List.reverse(&2,Components.PlayerRecord,done),xp,gold,List.reverse(&2,Reward,chests)}
    case +player <> rest: finalize_eligible(Bool.and(record_connected(player),U32.is_lt(0,RS.player_hp(record_player(player)))),finalize_players(rest,team,rows),player,team,rows,world,done,xp,gold,chests)
def living_ids(players: List<&2,Components.PlayerRecord>) -> List<&2,U32>:
  match players:
    case []: []
    case Components.PlayerRecord{+id,personal,+connected,_} <> rest: G.free_slot(Bool.and(connected,U32.is_lt(0,RS.player_hp(personal))),id,living_ids(rest))
def revive_due(player: Components.PlayerRecord,+tick: U32,+teamAlive: Bool) -> Components.PlayerRecord:
  match player:
    case Components.PlayerRecord{id,+personal,+connected,+reviveTick}:
      +due = Bool.and(teamAlive,Bool.and(connected,Bool.and(U32.is_lt(0,reviveTick),Bool.and(U32.is_le(reviveTick,tick),U32.is_eq(RS.player_hp(personal),0)))))
      +restored = RS.player_with_invuln(RS.player_with_hp(personal,U32.max(1,(RS.player_maxHp(personal) * 30 / 100 : U32))),180)
      Components.PlayerRecord{id,Bool.pick(RS.PlayerState,due,restored,personal),connected,Bool.pick(U32,due,0,reviveTick)}
def revive_players(players: List<&2,Components.PlayerRecord>,+tick: U32,+teamAlive: Bool) -> List<&2,Components.PlayerRecord>:
  match players:
    case []: []
    case player <> rest: revive_due(player,tick,teamAlive) <> revive_players(rest,tick,teamAlive)
def resolve_revives(+players: List<&2,Components.PlayerRecord>,+tick: U32) -> List<&2,Components.PlayerRecord>:
  revive_players(players,tick,Bool.not(Nat.is_eq(List.length(&2,U32,living_ids(players)),0n)))
def insert_level(chests: List<&2,Reward>) -> List<&2,Reward>:
  match chests:
    case []: [Reward{1,0}]
    case first <> rest: first <> Reward{1,0} <> rest
def level_rewards(levelup: Bool,chests: List<&2,Reward>) -> List<&2,Reward>:
  match levelup:
    case False{}: chests
    case True{}: insert_level(chests)
def eligible_reward(kind: U32,+collector: U32,players: List<&2,Components.PlayerRecord>) -> List<&2,U32>:
  match kind:
    case 1: living_ids(players)
    case _: Bool.pick(List<&2,U32>,G.contains(living_ids(players),collector),[collector],[])
def offers_for_personal(+shared: RS.Session,+kind: U32,+round: U32,+id: U32,personal: Maybe<&2,RS.PlayerState>) -> List<&2,Model.Offer>:
  match personal:
    case None{}: []
    case Some{+player}: G.filter_offers(G.phase_offers(U32.is_eq(kind,2),(RS.session_seed(shared) + RS.session_level(shared) * 13 + id * 31 + round * 7 : U32),RS.player_weapons(player),RS.player_passives(player)),RS.player_bannedWeapons(player),U32.or(8192,RS.player_bannedPassives(player)))
def make_offers(ids: List<&2,U32>,+players: List<&2,Components.PlayerRecord>,+shared: RS.Session,+kind: U32,+round: U32) -> List<&2,PlayerOffers>:
  match ids:
    case []: []
    case +id <> rest: PlayerOffers{id,offers_for_personal(shared,kind,round,id,find_player(players,id))} <> make_offers(rest,players,shared,kind,round)
def open_reward_eligible(next: Storage.World() -> @+shared: RS.Session -> @+refs:List<&2,PlayerRef> -> List<&2,Model.Snapshot> -> @+round:U32 -> @+players:List<&2,Components.PlayerRecord> -> CorePacket,+required: List<&2,U32>,pending: List<&2,Reward>,world: Storage.World(),+shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,+round: U32,+players: List<&2,Components.PlayerRecord>,+kind: U32) -> CorePacket:
  match required:
    case []: next(world,shared,refs,snapshots,round,players)
    case _: completed(CoreState{world,RS.session_with_phase(shared,kind),refs,snapshots,(round + 1 : U32),required,make_offers(required,players,shared,kind,(round + 1 : U32)),pending})

def open_rewards_go(rewards: List<&2,Reward>,world: Storage.World(),+shared: RS.Session,+refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,+round: U32,+players: List<&2,Components.PlayerRecord>) -> CorePacket:
  match rewards:
    case []: completed(CoreState{world,RS.session_with_phase(shared,0),refs,snapshots,round,[],[],[]})
    case Reward{+kind,collector} <> +rest: open_reward_eligible(open_rewards_go(rest),eligible_reward(kind,collector,players),rest,world,shared,refs,snapshots,round,players,kind)

def finish_shared(run: RS.Session,+earned: U32,coins: U32,killed: U32,bossesKilled: U32,kinds: List<&2,U32>,relic: U32,+dead: Bool) -> RS.Session:
  match run:
    case RS.Session{_,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,stage,+bosses,+mode,_,+relicCollected}: RS.Session{Bool.pick(U32,dead,Bool.pick(U32,Bool.and(Bool.not(U32.is_eq(mode,2)),U32.is_le(G.run_length(mode),(tick + 1 : U32))),4,3),0),(tick + 1 : U32),G.remainder_xp((xp + earned : U32),xpNeed),Bool.pick(U32,U32.is_le(xpNeed,(xp + earned : U32)),G.next_xp_need(level),xpNeed),(level + Bool.to_u32(U32.is_le(xpNeed,(xp + earned : U32))) : U32),(kills + killed : U32),(gold + coins + 300 * Bool.to_u32(Bool.and(U32.is_eq(mode,3),U32.is_eq((tick + 1 : U32),18000))) + (50 + level * 5 + kills / 20) * Bool.to_u32(dead) : U32),(seed + 1 : U32),stage,(bosses + bossesKilled : U32),mode,kinds,U32.max(relicCollected,relic)}
def finish_match(dead: Bool,world: Storage.World(),+shared: RS.Session,+refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,+players: List<&2,Components.PlayerRecord>,rewards: List<&2,Reward>) -> CorePacket:
  match dead:
    case True{}: completed(CoreState{save_players(refs,players,world),shared,refs,snapshots,round,[],[],[]})
    case False{}: open_rewards_go(rewards,save_players(refs,players,world),shared,refs,snapshots,round,players)
def finalized_totals(+shared: RS.Session,+refs: List<&2,PlayerRef>,+rows: List<&2,G.EntityRow>,round: U32,world: Storage.World(),+players: List<&2,Components.PlayerRecord>,+earned: U32,+gold: U32,chests: List<&2,Reward>,totals: G.Totals) -> CorePacket:
  match totals:
    case G.Totals{_,_,_,_,_,killed,snapshots,relic}: finish_match(Nat.is_eq(List.length(&2,U32,living_ids(players)),0n),world,finish_shared(shared,earned,gold,killed,G.boss_kills(rows),G.killed_kinds(rows,RS.session_enemyKinds(shared)),relic,Nat.is_eq(List.length(&2,U32,living_ids(players)),0n)),refs,snapshots,round,players,level_rewards(U32.is_le(RS.session_xpNeed(shared),(RS.session_xp(shared) + earned : U32)),chests))
def finalized_all(+shared: RS.Session,refs: List<&2,PlayerRef>,+rows: List<&2,G.EntityRow>,round: U32,result: PlayersFinalized) -> CorePacket:
  match result:
    case PlayersFinalized{world,players,xp,gold,chests}: finalized_totals(shared,refs,rows,round,world,resolve_revives(players,(RS.session_tick(shared) + 1 : U32)),xp,gold,chests,G.accumulate(rows,0,0,0,0,0,0,[],0))
    case FinalizeFailed{message}: CoreFailed{message}
# Receipts use the exact prepared authoritative contact plans. Existing enemy
# preimages retain pre-loot-clamp geometry; newborns bypass contact effects.
def journal_event(value:ContactPolicy.Witness,sourcePlayer:U32,source:Shot.State,target:Model.Snapshot,selected:Nat) -> Journal.HitEvent:
  match value source:
    case ContactPolicy.Witness{+kind,+tick,+shot,+targetSeed,_,_,+x0,+y0,+x1,+y1,+ex0,+ey0,+ex1,+ey1,radius,+time} Shot.State{Space.Spatial{_,_,age,_},_,_,_,Components.Trajectory{_,_,_,pierce,_,owner,+slot,_}}:
      +eventKind = Journal.contact_kind(kind,pierce,selected)
      +shotId = Journal.shot_id(sourcePlayer,(tick - 1 - age : U32),owner,slot)
      +targetBorn = (tick - 1 - G.snapshot_age(target) : U32)
      Journal.HitEvent{Journal.event_id(tick,eventKind,shotId,targetSeed,targetBorn),tick,eventKind,shotId,shot,targetSeed,targetBorn,Bool.pick(F32,U32.is_eq(kind,1),1.0,time),Bool.pick(F32,U32.is_eq(kind,1),ex1,(x0 + (x1 - x0) * time : F32)),Bool.pick(F32,U32.is_eq(kind,1),ey1,(y0 + (y1 - y0) * time : F32)),(ex0 + (ex1 - ex0) * time : F32),(ey0 + (ey1 - ey0) * time : F32),radius,0}
def journal_source(value:ContactPolicy.Witness,sourcePlayer:Maybe<&2,U32>,source:Shot.State,target:Model.Snapshot,selected:Nat,tail:List<&2,Journal.HitEvent>) -> List<&2,Journal.HitEvent>:
  match sourcePlayer:
    case None{}: tail
    case Some{player}: journal_event(value,player,source,target,selected) <> tail
def journal_lookup(value:ContactPolicy.Witness,source:Maybe<&2,Model.Snapshot>,target:Maybe<&2,Model.Snapshot>,selected:Nat,tail:List<&2,Journal.HitEvent>) -> List<&2,Journal.HitEvent>:
  match source target:
    case Some{Model.ProjectileSnapshot{+shot}} Some{enemy}: journal_source(value,Shot.source_player(shot),shot,enemy,selected,tail)
    case _ _: tail
def journal_events_go(rows:List<&2,ContactPolicy.Witness>,+index:BI.Index<Model.Snapshot>,+counts:BI.Index<Nat>,acc:List<&2,Journal.HitEvent>) -> List<&2,Journal.HitEvent>:
  match rows:
    case []: List.reverse(&2,Journal.HitEvent,acc)
    case ContactPolicy.Witness{+kind,+tick,+shot,+target,+sb,+tb,+x0,+y0,+x1,+y1,+ex0,+ey0,+ex1,+ey1,+radius,+time} <> tail:
      journal_events_go(tail,index,counts,journal_lookup(ContactPolicy.Witness{kind,tick,shot,target,sb,tb,x0,y0,x1,y1,ex0,ey0,ex1,ey1,radius,time},BI.find(~Model.Snapshot,index,shot),BI.find(~Model.Snapshot,index,target),BI.value_or(~Nat,BI.find(~Nat,counts,shot),0n),acc))
def journal_events(rows:List<&2,ContactPolicy.Witness>,index:BI.Index<Model.Snapshot>,counts:BI.Index<Nat>) -> List<&2,Journal.HitEvent>:
  journal_events_go(rows,index,counts,[])
def journal_counts(rows:List<&2,G.HitPlan>,acc:BI.Index<Nat>) -> BI.Index<Nat>:
  match rows:
    case []: acc
    case G.HitPlan{shot,_,_,_,_,_,_,targets} <> tail: journal_counts(tail,BI.insert(~Nat,acc,shot,List.length(&2,U32,targets)))
def journal_team_paths(+team:G.Team,+hits:List<&2,G.HitPlan>,+tick:U32,+index:BI.Index<Model.Snapshot>,+paths:List<&2,Contact.Target>) -> List<&2,Journal.HitEvent>:
  journal_events(List.append(&2,ContactPolicy.Witness,CombatPrediction.witnesses(hits,tick,team,index,CombatPrediction.target_index(paths),BI.Empty{}),CombatPrediction.area_plans(hits,tick,paths)),index,journal_counts(hits,BI.Empty{}))
def journal_team(+team:G.Team) -> List<&2,Journal.HitEvent>:
  match team:
    case G.Team{+players,G.Args{+run,+targets,+dx,+dy,+snapshots,+hits},+plan,+origins}:
      journal_team_paths(G.Team{players,G.Args{run,targets,dx,dy,snapshots,hits},plan,origins},hits,G.run_tick(run),CombatPrediction.snapshot_index(snapshots),G.contact_targets(snapshots,G.Team{players,G.Args{run,targets,dx,dy,snapshots,hits},plan,origins}))
def journal_capped_clock(emission:Journal.Emission,packet:CorePacket) -> CorePacket:
  match emission packet:
    case Journal.Emission{events,omitted} CorePacket{CoreState{world,+shared,refs,snapshots,round,required,offers,pending},_}: CorePacket{CoreState{world,shared,refs,snapshots,round,required,offers,pending},StepObservation{RS.session_tick(shared),RS.session_phase(shared),True{},events,omitted}}
    case _ packet: packet
def journal_clock(events:List<&2,Journal.HitEvent>,packet:CorePacket) -> CorePacket:
  journal_capped_clock(Journal.emit_capped(events),packet)
def core_executed(+shared: RS.Session,+refs: List<&2,PlayerRef>,+team: G.Team,round: U32,players: List<&2,Components.PlayerRecord>,result: Q.Executed<Storage.World(),Q.Error<G.Error>,G.EntityRow>) -> CorePacket:
  match result:
    case Q.Executed{world,T.Success{},+rows}: journal_clock(journal_team(team),finalized_all(shared,refs,rows,round,finalize_players(players,team,rows,world,[],0,0,[])))
    case Q.Executed{_,T.Failure{_},_}: CoreFailed{"Shared ECS query failed"}
def core_team_prepared(shared: RS.Session,refs: List<&2,PlayerRef>,round: U32,world: Storage.World(),players: List<&2,Components.PlayerRecord>,+team: G.Team) -> CorePacket: core_executed(shared,refs,team,round,players,G.team_execute_contacts(world,team))
def core_team_ready(shared: RS.Session,refs:List<&2,PlayerRef>,round:U32,world:Storage.World(),players:List<&2,Components.PlayerRecord>,team:G.Team) -> CorePacket:
  core_team_prepared(shared,refs,round,world,players,G.contact_team(team))
def core_team(+shared: RS.Session,+refs: List<&2,PlayerRef>,+snapshots: List<&2,Model.Snapshot>,round: U32,world: Storage.World(),+players: List<&2,Components.PlayerRecord>,views: List<&2,G.PlayerView>) -> CorePacket:
  match views:
    case []: CoreFailed{"No connected player in active match"}
    case +first <> +rest: core_team_ready(shared,refs,round,world,players,G.Team{first <> rest,G.combat_args(G.view_run(G.first_view(first <> rest,G.view_run(first))),0.0,0.0,snapshots),G.team_plan(first <> rest,snapshots),G.effect_origin_index(snapshots)})
def step_loaded(+shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,dx0: F32,dy0: F32,dx1: F32,dy1: F32,result: Storage.World() & List<&2,Components.PlayerRecord>) -> CorePacket:
  match result:
    case (world,+players): core_team(shared,refs,snapshots,round,world,players,player_views(shared,dx0,dy0,dx1,dy1,players))
def core_clock(state: CoreState) -> CorePacket:
  match state:
    case CoreState{world,+shared,refs,snapshots,round,required,offers,pending}: CorePacket{CoreState{world,shared,refs,snapshots,round,required,offers,pending},StepObservation{RS.session_tick(shared),RS.session_phase(shared),False{},[],0}}
def step_allowed(allowed: Bool,state: CoreState,dx0: F32,dy0: F32,dx1: F32,dy1: F32) -> CorePacket:
  match allowed state:
    case False{} state: core_clock(state)
    case True{} CoreState{world,+shared,+refs,snapshots,round,_,_,_}: step_loaded(shared,refs,snapshots,round,dx0,dy0,dx1,dy1,load_players(refs,[],world))
def core_step(state: CoreState,dx0: F32,dy0: F32,dx1: F32,dy1: F32) -> CorePacket:
  match state:
    case CoreState{world,+shared,refs,snapshots,round,required,offers,pending}: step_allowed(U32.is_eq(RS.session_phase(shared),0),CoreState{world,shared,refs,snapshots,round,required,offers,pending},dx0,dy0,dx1,dy1)

def players_step_loaded(+shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,moves: List<&2,Movement>,result: Storage.World() & List<&2,Components.PlayerRecord>) -> CorePacket:
  match result:
    case (world,+players): core_team(shared,refs,snapshots,round,world,players,player_movement_views(shared,moves,players))
def players_step_allowed(allowed: Bool,state: CoreState,moves: List<&2,Movement>) -> CorePacket:
  match allowed state:
    case False{} state: core_clock(state)
    case True{} CoreState{world,+shared,+refs,snapshots,round,_,_,_}: players_step_loaded(shared,refs,snapshots,round,moves,load_players(refs,[],world))
def core_step_players(state: CoreState,moves: List<&2,Movement>) -> CorePacket:
  match state:
    case CoreState{world,+shared,refs,snapshots,round,required,offers,pending}: players_step_allowed(U32.is_eq(RS.session_phase(shared),0),CoreState{world,shared,refs,snapshots,round,required,offers,pending},moves)

def remove_offers(offers: List<&2,PlayerOffers>,+id: U32) -> List<&2,PlayerOffers>:
  match offers:
    case []: []
    case PlayerOffers{+pid,choices} <> +rest: Bool.pick(List<&2,PlayerOffers>,U32.is_ne(pid,id),PlayerOffers{pid,choices} <> remove_offers(rest,id),remove_offers(rest,id))
def replace_personal(players: List<&2,Components.PlayerRecord>,+id: U32,+replacement: RS.PlayerState) -> List<&2,Components.PlayerRecord>:
  match players:
    case []: []
    case Components.PlayerRecord{+pid,personal,connected,+reviveTick} <> rest: Components.PlayerRecord{pid,Bool.pick(RS.PlayerState,U32.is_eq(id,pid),replacement,personal),connected,reviveTick} <> replace_personal(rest,id,replacement)
def resume_control(remaining: List<&2,U32>,world: Storage.World(),+shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,+players: List<&2,Components.PlayerRecord>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>) -> CorePacket:
  match remaining:
    case []: open_rewards_go(pending,world,shared,refs,snapshots,round,players)
    case remaining: completed(CoreState{world,shared,refs,snapshots,round,remaining,offers,pending})
def choice_upgraded(+id: U32,+shared: RS.Session,+refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,world: Storage.World(),+players: List<&2,Components.PlayerRecord>,+upgraded: Model.Run) -> CorePacket:
  resume_control(required,save_players(refs,replace_personal(players,id,G.run_player(upgraded)),world),RS.session_with_gold(shared,run_gold(upgraded)),refs,snapshots,round,replace_personal(players,id,G.run_player(upgraded)),remove_offers(offers,id),pending)
def choice_player(+id: U32,choice: U32,+shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,+offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,world: Storage.World(),players: List<&2,Components.PlayerRecord>,personal: Maybe<&2,RS.PlayerState>) -> CorePacket:
  match personal:
    case None{}: CoreRejected{CoreState{world,shared,refs,snapshots,round,required,offers,pending},"Unknown choosing player"}
    case Some{player}: choice_upgraded(id,shared,refs,snapshots,round,required,offers,pending,world,players,G.upgrade(G.offer_at(offers_for(offers,id),choice),player_step_context(shared,player)))
def choice_loaded(+id: U32,choice: U32,+shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,+offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,result: Storage.World() & List<&2,Components.PlayerRecord>) -> CorePacket:
  match result:
    case (world,+players): choice_player(id,choice,shared,refs,snapshots,round,required,offers,pending,world,players,find_player(players,id))
def choice_decided(decision: RP.Decision,state: CoreState,id: U32,choice: U32) -> CorePacket:
  match decision state:
    case RP.Decision{False{},_} state: CoreRejected{state,"Stale, duplicate, ineligible or invalid reward choice"}
    case RP.Decision{True{},remaining} CoreState{world,shared,+refs,snapshots,round,_,offers,pending}:
      choice_loaded(id,choice,shared,refs,snapshots,round,remaining,offers,pending,load_players(refs,[],world))
def core_choose(state: CoreState,+id: U32,+requestedRound: U32,+choice: U32) -> CorePacket:
  match state:
    case CoreState{world,+shared,refs,snapshots,+round,+required,+offers,pending}: choice_decided(RP.decide(round,requestedRound,id,choice,U32.from_nat(List.length(&2,Model.Offer,offers_for(offers,id))),required),CoreState{world,shared,refs,snapshots,round,required,offers,pending},id,choice)
def disconnect_players(players: List<&2,Components.PlayerRecord>,+id: U32) -> List<&2,Components.PlayerRecord>:
  match players:
    case []: []
    case Components.PlayerRecord{+pid,run,+connected,+reviveTick} <> rest: Components.PlayerRecord{pid,run,Bool.and(connected,U32.is_ne(id,pid)),reviveTick} <> disconnect_players(rest,id)
# Completed run receipts survive later transport teardown. An unfinished match
# stopped by connection loss is an abort, never a bankable defeat/victory.
def disconnect_phase(+shared: RS.Session) -> U32:
  Bool.pick(U32,Bool.or(U32.is_eq(RS.session_phase(shared),3),U32.is_eq(RS.session_phase(shared),4)),RS.session_phase(shared),5)
def disconnect_terminal(terminal: Bool,+shared: RS.Session,refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,world: Storage.World(),players: List<&2,Components.PlayerRecord>,+id: U32) -> CorePacket:
  match terminal:
    case True{}: completed(CoreState{world,RS.session_with_phase(shared,disconnect_phase(shared)),refs,snapshots,round,[],[],[]})
    case False{}: resume_control(RP.remove(required,id),world,shared,refs,snapshots,round,players,remove_offers(offers,id),pending)
def disconnected(+id: U32,+shared: RS.Session,+refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,world: Storage.World(),+players: List<&2,Components.PlayerRecord>) -> CorePacket:
  disconnect_terminal(Bool.or(U32.is_le(3,RS.session_phase(shared)),Bool.or(U32.is_eq(id,0),Nat.is_eq(List.length(&2,U32,living_ids(players)),0n))),shared,refs,snapshots,round,required,offers,pending,save_players(refs,players,world),players,id)
def disconnect_loaded(+id: U32,+shared: RS.Session,+refs: List<&2,PlayerRef>,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,PlayerOffers>,pending: List<&2,Reward>,result: Storage.World() & List<&2,Components.PlayerRecord>) -> CorePacket:
  match result:
    case (world,players): disconnected(id,shared,refs,snapshots,round,required,offers,pending,world,disconnect_players(players,id))
def core_disconnect(state: CoreState,id: U32) -> CorePacket:
  match state:
    case CoreState{world,shared,+refs,snapshots,round,required,offers,pending}: disconnect_loaded(id,shared,refs,snapshots,round,required,offers,pending,load_players(refs,[],world))
