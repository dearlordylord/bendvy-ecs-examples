import game-observation.bend as Model
import run-state.bend as RS
import enemy-combat.bend as Enemy
import enemy-spatial.bend as Space
import pickup-state.bend as Pickup
# Shared pure native controller over the actual shared co-op world. The public
# Core transition is retained; only telemetry is encoded for the IO adapter.
import Base
import game-components.bend as Components
import game-storage.bend as Storage
import coop-core.bend as Core
import native-economy.bend as Economy
import offline-policy.bend as Policy
import offline-coop-control.bend as Control

type Observed is Type: Observed{state:Core.CoreState,shared:RS.Session,p0:Model.Run,p1:Model.Run,snapshots:List<&2,Model.Snapshot>,round:U32,required:List<&2,U32>,offers:List<&2,Core.PlayerOffers>}
type Checked is Type: CoopReady{observed:Array<Observed>} CoopBroken{message:String}
type Action is Data: CoopMove{tick:U32,dx0:F32,dy0:F32,dx1:F32,dy1:F32} CoopChoose{tick:U32,player:U32,round:U32,index:U32}
type Progress is Type: Progress{packet:Core.CorePacket,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,action:Maybe<&2,Action>}
type Decision is Type: Decision{state:Core.CoreState,p0:Model.Run,p1:Model.Run,snapshots:List<&2,Model.Snapshot>,round:U32,offers:List<&2,Core.PlayerOffers>,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,tick:U32}
type Work is Type: Work{observed:Array<Observed>,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32}
type Instruction is Type:
  Again{line:Maybe<&2,String>,nextSample:Nat,progress:Array<Progress>}
  Finished{fields:String,outcome:String,tick:U32}
  Broken{message:String}

def environment(result:Result<&1,&1,U32 & String,String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: ""
def parsed(value:Maybe<&2,U32>,fallback:U32) -> U32:
  match value:
    case Some{value}: value
    case None{}: fallback
def number(text:String,fallback:U32) -> U32: parsed(U32.read(text),fallback)
def profile_meta(advanced:Bool) -> U32: Bool.pick(U32,advanced,364304237,Economy.meta(Economy.fresh()))
def profile_character(advanced:Bool) -> U32: Bool.pick(U32,advanced,2,0)
def profile_arcana(advanced:Bool) -> U32: Bool.pick(U32,advanced,9,0)
def unlock(packet:Core.CorePacket,id:U32) -> Core.CorePacket:
  match packet:
    case Core.CorePacket{state,_}: Core.core_configure_unlocks(state,id,Economy.weapon_mask(Economy.fresh()))
    case packet: packet
def unlock_profile(advanced:Bool,packet:Core.CorePacket) -> Core.CorePacket:
  match advanced:
    case True{}: packet
    case False{}: unlock(unlock(packet,0),1)
def join(packet:Core.CorePacket,character:U32,meta:U32,arcana:U32) -> Core.CorePacket:
  match packet:
    case Core.CorePacket{state,_}: Core.core_join(state,character,meta,arcana)
    case packet: packet
def configure(packet:Core.CorePacket,arcana:U32) -> Core.CorePacket:
  match packet:
    case Core.CorePacket{state,_}: Core.core_configure(state,0,0,arcana)
    case packet: packet
def start(seed:U32,+advanced:Bool,character0:U32,character1:U32,arcana0:U32,arcana1:U32) -> Core.CorePacket:
  unlock_profile(advanced,join(configure(Core.core_start(character0,profile_meta(advanced),seed),arcana0),character1,profile_meta(advanced),arcana1))

def observed_players(state: Core.CoreState,+shared: RS.Session,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,Core.PlayerOffers>,p0: Maybe<&2,RS.PlayerState>,p1: Maybe<&2,RS.PlayerState>) -> Checked:
  match p0 p1:
    case Some{p0} Some{p1}: CoopReady{ALeaf{Observed{state,shared,Core.player_step_context(shared,p0),Core.player_step_context(shared,p1),snapshots,round,required,offers}}}
    case _ _: CoopBroken{"native co-op requires both player records"}
def observed_loaded(+shared:RS.Session,+refs:List<&2,Core.PlayerRef>,+snapshots:List<&2,Model.Snapshot>,+round:U32,+required:List<&2,U32>,+offers:List<&2,Core.PlayerOffers>,pending:List<&2,Core.Reward>,result:Storage.World() & List<&2,Components.PlayerRecord>) -> Checked:
  match result:
    case (world,+players): observed_players(Core.CoreState{world,shared,refs,snapshots,round,required,offers,pending},shared,snapshots,round,required,offers,Core.find_player(players,0),Core.find_player(players,1))
def observe(packet:Core.CorePacket) -> Checked:
  match packet:
    case Core.CorePacket{Core.CoreState{world,+shared,+refs,snapshots,+round,+required,+offers,pending},_}: observed_loaded(shared,refs,snapshots,round,required,offers,pending,Core.load_players(refs,[],world))
    case Core.CoreRejected{_,message}: CoopBroken{"Co-op command rejected: " ++ message}
    case Core.CoreFailed{message}: CoopBroken{"Co-op game failed: " ++ message}


def failed(message:String) -> Array<Progress>:
  ALeaf{Progress{Core.CoreFailed{message},Policy.initial(),Policy.initial(),0,0,None{}}}
def move_action(active:Bool,tick:U32,dx0:F32,dy0:F32,dx1:F32,dy1:F32) -> Maybe<&2,Action>:
  match active:
    case False{}: None{}
    case True{}: Some{CoopMove{tick,dx0,dy0,dx1,dy1}}
def choose_action(active:Bool,tick:U32,player:U32,round:U32,index:U32) -> Maybe<&2,Action>:
  match active:
    case False{}: None{}
    case True{}: Some{CoopChoose{tick,player,round,index}}
def moved_xy1(active:Bool,state:Core.CoreState,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,tick:U32,+dx0:F32,+dy0:F32,d1:F32 & F32) -> Array<Progress>:
  (+dx1,+dy1) = d1
  ALeaf{Progress{Core.core_step(state,dx0,dy0,dx1,dy1),m0,m1,choices0,choices1,move_action(active,tick,dx0,dy0,dx1,dy1)}}
def moved_xy0(active:Bool,state:Core.CoreState,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,tick:U32,d0:F32 & F32,d1:F32 & F32) -> Array<Progress>:
  (dx0,dy0) = d0
  moved_xy1(active,state,m0,m1,choices0,choices1,tick,dx0,dy0,d1)
def moved_right(active:Bool,state:Core.CoreState,m0:Policy.Memory,choices0:U32,choices1:U32,tick:U32,d0:F32 & F32,move1:Policy.Memory & (F32 & F32)) -> Array<Progress>:
  (m1,d1) = move1
  moved_xy0(active,state,m0,m1,choices0,choices1,tick,d0,d1)
def moved(active:Bool,state:Core.CoreState,choices0:U32,choices1:U32,tick:U32,move0:Policy.Memory & (F32 & F32),move1:Policy.Memory & (F32 & F32)) -> Array<Progress>:
  (m0,d0) = move0
  moved_right(active,state,m0,choices0,choices1,tick,d0,move1)
def movement(active:Bool,value:Array<Decision>) -> Array<Progress>:
  match value:
    case ALeaf{Decision{state,p0,p1,+rows,_,_,m0,m1,choices0,choices1,tick}}: moved(active,state,choices0,choices1,tick,Policy.movement(m0,p0,rows),Policy.movement(m1,p1,rows))
    case _: failed("native co-op decision carrier must be one leaf")
def chosen(active:Bool,+id:U32,+index:U32,value:Array<Decision>) -> Array<Progress>:
  match value:
    case ALeaf{Decision{state,_,_,_,+round,_,m0,m1,+choices0,+choices1,tick}}: ALeaf{Progress{Core.core_choose(state,id,round,index),m0,m1,(choices0 + Bool.to_u32(U32.is_eq(id,0)) : U32),(choices1 + Bool.to_u32(U32.is_eq(id,1)) : U32),choose_action(active,tick,id,round,index)}}
    case _: failed("native co-op decision carrier must be one leaf")
def choosing(active:Bool,+id:U32,value:Array<Decision>) -> Array<Progress>:
  match value:
    case ALeaf{Decision{state,+p0,+p1,rows,round,+offers,m0,m1,choices0,choices1,tick}}:
      chosen(active,id,Policy.upgrade(Bool.pick(Model.Run,U32.is_eq(id,0),p0,p1),Core.offers_for(offers,id)),ALeaf{Decision{state,p0,p1,rows,round,offers,m0,m1,choices0,choices1,tick}})
    case _: failed("native co-op decision carrier must be one leaf")
def decide(active:Bool,required:List<&2,U32>,value:Array<Decision>) -> Array<Progress>:
  match required:
    case id <> _: choosing(active,id,value)
    case []: movement(active,value)

def initial(seed:U32,advanced:Bool,character0:U32,character1:U32,arcana0:U32,arcana1:U32) -> Array<Progress>:
  ALeaf{Progress{start(seed,advanced,character0,character1,arcana0,arcana1),Policy.initial(),Policy.initial(),0,0,None{}}}
def population_go(rows:List<&2,Model.Snapshot>,+boss:U32,+ordinary:U32) -> U32 & U32:
  match rows:
    case []: (ordinary,boss)
    case Model.EnemySnapshot{Enemy.State{_,+variant,_,Components.Vitals{+hp,_},_}} <> tail: population_go(tail,(boss + Bool.to_u32(Control.boss(0,variant,hp)) : U32),(ordinary + Bool.to_u32(Control.ordinary(0,variant,hp)) : U32))
    case _ <> tail: population_go(tail,boss,ordinary)
def near_go(rows:List<&2,Model.Snapshot>,+px:F32,+py:F32,+count:U32) -> U32:
  match rows:
    case []: count
    case Model.EnemySnapshot{Enemy.State{Space.Spatial{+x,+y,_,_},_,_,Components.Vitals{hp,_},_}} <> tail: near_go(tail,px,py,(count + Bool.to_u32(Bool.and(U32.is_lt(0,hp),F32.is_le(((x - px) * (x - px) + (y - py) * (y - py) : F32),14400.0))) : U32))
    case _ <> tail: near_go(tail,px,py,count)
def xp_go(rows:List<&2,Model.Snapshot>,+piles:U32,+value:U32) -> U32 & U32:
  match rows:
    case []: (piles,value)
    case Model.PickupSnapshot{Pickup.State{_,Pickup.Payload{Pickup.Xp{amount,_},_,True{}},_}} <> tail: xp_go(tail,(piles + 1 : U32),(value + amount : U32))
    case _ <> tail: xp_go(tail,piles,value)
def population_fields(pair:U32 & U32) -> String:
  (+ordinary,+boss) = pair
  "\"population\":" ++ U32.show((ordinary + boss : U32)) ++ ",\"ordinaryPopulation\":" ++ U32.show(ordinary) ++ ",\"bossPopulation\":" ++ U32.show(boss)
def xp_fields(pair:U32 & U32) -> String:
  (piles,value) = pair
  ",\"xpPiles\":" ++ U32.show(piles) ++ ",\"uncollectedBaseXp\":" ++ U32.show(value)
def u32_items(values:List<&2,U32>) -> String:
  match values:
    case []: ""
    case value <> []: U32.show(value)
    case value <> tail: U32.show(value) ++ "," ++ u32_items(tail)
def player_setup(+run:Model.Run) -> String:
  "{\"character\":" ++ U32.show(Core.run_character(run)) ++ ",\"arcana\":" ++ U32.show(Core.run_arcana(run)) ++ ",\"meta\":" ++ U32.show(Core.run_meta(run)) ++ ",\"bannedWeapons\":" ++ U32.show(Core.run_bannedWeapons(run)) ++ ",\"weapons\":[" ++ u32_items(Core.run_weapons(run)) ++ "],\"passives\":[" ++ u32_items(Core.run_passives(run)) ++ "],\"hp\":" ++ U32.show(Core.run_hp(run)) ++ ",\"maxHp\":" ++ U32.show(Core.run_maxHp(run)) ++ "}"
def initial_setup_fields(initial:Bool,+shared:RS.Session,p0:Model.Run,p1:Model.Run) -> String:
  match initial:
    case False{}: ""
    case True{}: ",\"initialSetup\":{\"stage\":" ++ U32.show(RS.session_stage(shared)) ++ ",\"mode\":" ++ U32.show(RS.session_mode(shared)) ++ ",\"players\":[" ++ player_setup(p0) ++ "," ++ player_setup(p1) ++ "]}"
def shared_kills(shared: RS.Session) -> U32:
  match shared:
    case RS.Session{_,_,_,_,_,kills,_,_,_,_,_,_,_}: kills
def shared_gold(shared: RS.Session) -> U32:
  match shared:
    case RS.Session{_,_,_,_,_,_,gold,_,_,_,_,_,_}: gold
def fields(+seed:U32,+index:U32,+ticks:U32,+shared:RS.Session,+p0:Model.Run,+p1:Model.Run,+snapshots:List<&2,Model.Snapshot>,choices0:U32,choices1:U32) -> String:
  "\"seed\":" ++ U32.show(seed) ++ ",\"index\":" ++ U32.show(index) ++ ",\"tick\":" ++ U32.show(RS.session_tick(shared)) ++ ",\"phase\":" ++ U32.show(RS.session_phase(shared)) ++ ",\"requestedTicks\":" ++ U32.show(ticks) ++ "," ++ population_fields(population_go(snapshots,0,0)) ++ ",\"hp0\":" ++ U32.show(Core.run_hp(p0)) ++ ",\"hp1\":" ++ U32.show(Core.run_hp(p1)) ++ ",\"maxHp0\":" ++ U32.show(Core.run_maxHp(p0)) ++ ",\"maxHp1\":" ++ U32.show(Core.run_maxHp(p1)) ++ ",\"px0\":" ++ F32.show(Core.run_px(p0)) ++ ",\"py0\":" ++ F32.show(Core.run_py(p0)) ++ ",\"px1\":" ++ F32.show(Core.run_px(p1)) ++ ",\"py1\":" ++ F32.show(Core.run_py(p1)) ++ ",\"nearEnemies0\":" ++ U32.show(near_go(snapshots,Core.run_px(p0),Core.run_py(p0),0)) ++ ",\"nearEnemies1\":" ++ U32.show(near_go(snapshots,Core.run_px(p1),Core.run_py(p1),0)) ++ ",\"xp\":" ++ U32.show(RS.session_xp(shared)) ++ ",\"xpNeed\":" ++ U32.show(RS.session_xpNeed(shared)) ++ ",\"level\":" ++ U32.show(RS.session_level(shared)) ++ ",\"kills\":" ++ U32.show(shared_kills(shared)) ++ ",\"gold\":" ++ U32.show(shared_gold(shared)) ++ ",\"choices0\":" ++ U32.show(choices0) ++ ",\"choices1\":" ++ U32.show(choices1) ++ xp_fields(xp_go(snapshots,0,0)) ++ initial_setup_fields(U32.is_eq(RS.session_tick(shared),0),shared,p0,p1)


def sample_line(emit:Bool,text:String) -> Maybe<&2,String>:
  match emit:
    case True{}: Some{text}
    case False{}: None{}
def next_sample(emit:Bool,tick:U32,current:Nat) -> Nat: Bool.pick(Nat,emit,Nat.add(U32.to_nat(tick),60n),current)
def finished(seed:U32,index:U32,ticks:U32,outcome:Control.Outcome,work:Array<Work>) -> Array<Instruction>:
  match work:
    case ALeaf{Work{ALeaf{Observed{_,+shared,p0,p1,rows,_,_,_}},_,_,choices0,choices1}}:
      ALeaf{Finished{fields(seed,index,ticks,shared,p0,p1,rows,choices0,choices1),Control.name(outcome),RS.session_tick(shared)}}
    case _: ALeaf{Broken{"native co-op observation carrier must be one leaf"}}
def running(seed:U32,index:U32,ticks:U32,+nextSample:Nat,work:Array<Work>) -> Array<Instruction>:
  match work:
    case ALeaf{Work{ALeaf{Observed{state,+shared,+p0,+p1,+rows,round,+required,+offers}},m0,m1,+choices0,+choices1}}:
      +tick=RS.session_tick(shared)
      +emit=Nat.is_ge(U32.to_nat(tick),nextSample)
      ALeaf{Again{sample_line(emit,fields(seed,index,ticks,shared,p0,p1,rows,choices0,choices1)),next_sample(emit,tick,nextSample),decide(False{},required,ALeaf{Decision{state,p0,p1,rows,round,offers,m0,m1,choices0,choices1,tick}})}}
    case _: ALeaf{Broken{"native co-op observation carrier must be one leaf"}}
def stopped(stop:Bool,outcome:Control.Outcome,seed:U32,index:U32,ticks:U32,nextSample:Nat,work:Array<Work>) -> Array<Instruction>:
  match stop:
    case True{}: finished(seed,index,ticks,outcome,work)
    case False{}: running(seed,index,ticks,nextSample,work)
def inspected(seed:U32,index:U32,+ticks:U32,nextSample:Nat,work:Array<Work>) -> Array<Instruction>:
  match work:
    case ALeaf{Work{ALeaf{Observed{state,+shared,p0,p1,rows,round,required,offers}},m0,m1,choices0,choices1}}:
      +result=Control.outcome(RS.session_phase(shared),RS.session_tick(shared),ticks)
      stopped(Control.stopped(result),result,seed,index,ticks,nextSample,ALeaf{Work{ALeaf{Observed{state,shared,p0,p1,rows,round,required,offers}},m0,m1,choices0,choices1}})
    case _: ALeaf{Broken{"native co-op observation carrier must be one leaf"}}
def prepared(seed:U32,index:U32,ticks:U32,nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,value:Checked) -> Array<Instruction>:
  match value:
    case CoopBroken{message}: ALeaf{Broken{message}}
    case CoopReady{observed}: inspected(seed,index,ticks,nextSample,ALeaf{Work{observed,m0,m1,choices0,choices1}})
def prepare(seed:U32,index:U32,ticks:U32,nextSample:Nat,value:Array<Progress>) -> Array<Instruction>:
  match value:
    case ALeaf{Progress{packet,m0,m1,choices0,choices1,_}}: prepared(seed,index,ticks,nextSample,m0,m1,choices0,choices1,observe(packet))
    case _: ALeaf{Broken{"native co-op progress carrier must be one leaf"}}
