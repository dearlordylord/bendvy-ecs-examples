import game-observation.bend as Model
import run-state.bend as RS
import enemy-combat.bend as Enemy
import enemy-spatial.bend as Space
import pickup-state.bend as Pickup
# Native controller over the actual shared co-op world. The public typed Core
# path is retained; full physical-state JSON is optional diagnostic output.
import Base
import game-components.bend as Components
import game-storage.bend as Storage
import coop-core.bend as Core
import native-economy.bend as Economy
import offline-policy.bend as Policy
import offline-coop-step.bend as Step
import offline-coop-control.bend as Control
import offline-coop-observe.bend as O

type Observed is Type: Observed{state:Core.CoreState,shared:RS.Session,p0:Model.Run,p1:Model.Run,snapshots:List<&2,Model.Snapshot>,round:U32,required:List<&2,U32>,offers:List<&2,Core.PlayerOffers>}
type Checked is Type: CoopReady{observed:Observed} CoopBroken{message:String}
type Progress is Type: Progress{cell:Array<Step.Progress>}

def environment(result:Result<&1,&1,U32 & String,String>) -> String: Step.environment(result)
def number(text:String,fallback:U32) -> U32: Step.number(text,fallback)
def profile_character(advanced:Bool) -> U32: Step.profile_character(advanced)
def profile_arcana(advanced:Bool) -> U32: Step.profile_arcana(advanced)
def start(seed:U32,advanced:Bool,character0:U32,character1:U32,arcana0:U32,arcana1:U32) -> Core.CorePacket: Step.start(seed,advanced,character0,character1,arcana0,arcana1)

def observed_players(state: Core.CoreState,+shared: RS.Session,snapshots: List<&2,Model.Snapshot>,round: U32,required: List<&2,U32>,offers: List<&2,Core.PlayerOffers>,p0: Maybe<&2,RS.PlayerState>,p1: Maybe<&2,RS.PlayerState>) -> Checked:
  match p0 p1:
    case Some{p0} Some{p1}: CoopReady{Observed{state,shared,Core.player_step_context(shared,p0),Core.player_step_context(shared,p1),snapshots,round,required,offers}}
    case _ _: CoopBroken{"native co-op requires both player records"}
def observed_loaded(+shared:RS.Session,+refs:List<&2,Core.PlayerRef>,+snapshots:List<&2,Model.Snapshot>,+round:U32,+required:List<&2,U32>,+offers:List<&2,Core.PlayerOffers>,pending:List<&2,Core.Reward>,result:Storage.World() & List<&2,Components.PlayerRecord>) -> Checked:
  match result:
    case (world,+players): observed_players(Core.CoreState{world,shared,refs,snapshots,round,required,offers,pending},shared,snapshots,round,required,offers,Core.find_player(players,0),Core.find_player(players,1))
def observe(packet:Core.CorePacket) -> Checked:
  match packet:
    case Core.CorePacket{Core.CoreState{world,+shared,+refs,snapshots,+round,+required,+offers,pending},_}: observed_loaded(shared,refs,snapshots,round,required,offers,pending,Core.load_players(refs,[],world))
    case Core.CoreRejected{_,message}: CoopBroken{"Co-op command rejected: " ++ message}
    case Core.CoreFailed{message}: CoopBroken{"Co-op game failed: " ++ message}

def shared_action(value:Maybe<&2,Step.Action>) -> Maybe<&2,O.Action>:
  match value:
    case None{}: None{}
    case Some{Step.CoopMove{tick,dx0,dy0,dx1,dy1}}: Some{O.AuditMove{tick,dx0,dy0,dx1,dy1}}
    case Some{Step.CoopChoose{tick,player,round,index}}: Some{O.AuditChoose{tick,player,round,index}}
def choose_or_move(active:Bool,required:List<&2,U32>,state:Core.CoreState,shared:RS.Session,p0:Model.Run,p1:Model.Run,rows:List<&2,Model.Snapshot>,round:U32,offers:List<&2,Core.PlayerOffers>,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32) -> Progress:
  Progress{Step.decide(active,required,ALeaf{Step.Decision{state,p0,p1,rows,round,offers,m0,m1,choices0,choices1,RS.session_tick(shared)}})}

def fields(seed:U32,index:U32,ticks:U32,shared:RS.Session,p0:Model.Run,p1:Model.Run,rows:List<&2,Model.Snapshot>,choices0:U32,choices1:U32) -> String:
  Step.fields(seed,index,ticks,shared,p0,p1,rows,choices0,choices1)

type Mode is Data: Off{} Scheduled{} Dense{} Terminal{}
type Audit is Data: Audit{mode:Mode,actions:U32,checkpoints:U32,nextCapture:Nat}
type AuditResult is Type: AuditResult{audit:Audit,observed:Observed}
def enabled(mode:Mode) -> Bool:
  match mode:
    case Off{}: False{}
    case Scheduled{}: True{}
    case Dense{}: True{}
    case Terminal{}: True{}
def active(value:Audit) -> Bool:
  match value:
    case Audit{mode,_,_,_}: enabled(mode)
def choice_captures(mode:Mode) -> Bool:
  match mode:
    case Off{}: False{}
    case Scheduled{}: True{}
    case Dense{}: True{}
    case Terminal{}: False{}
def period(mode:Mode) -> U32:
  match mode:
    case Off{}: 0
    case Scheduled{}: 600
    case Dense{}: 120
    case Terminal{}: 0
def mode_name(mode:Mode) -> String:
  match mode:
    case Off{}: "off"
    case Scheduled{}: "scheduled"
    case Dense{}: "dense"
    case Terminal{}: "terminal"
def advance(value:Audit) -> Audit:
  match value:
    case Audit{mode,actions,checkpoints,nextCapture}: Audit{mode,(actions + 1 : U32),checkpoints,nextCapture}
def emit_action(active:Bool,ordinal:U32,tick:U32,value:Maybe<&2,O.Action>) -> IO(Unit):
  match active value:
    case True{} Some{+action}: IO.print("{\"type\":\"audit-action\",\"ordinal\":" ++ U32.show(ordinal) ++ ",\"beforeTick\":" ++ U32.show(O.before_tick(action)) ++ ",\"afterTick\":" ++ U32.show(tick) ++ ",\"action\":" ++ O.action(action) ++ "}")
    case _ _: IO.pure(Unit,Unit{})
def ended(audit:Audit,tick:U32,outcome:Control.Outcome) -> IO(Unit):
  match audit:
    case Audit{Off{},_,_,_}: IO.pure(Unit,Unit{})
    case Audit{_,actions,checkpoints,_}: IO.print("{\"type\":\"audit-end\",\"actions\":" ++ U32.show(actions) ++ ",\"checkpoints\":" ++ U32.show(checkpoints) ++ ",\"tick\":" ++ U32.show(tick) ++ ",\"outcome\":\"" ++ Control.name(outcome) ++ "\"}")
def capture_done(reason:String,fuel:Nat,nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,audit:Audit,+shared:RS.Session,p0:Model.Run,p1:Model.Run,rows:List<&2,Model.Snapshot>,round:U32,required:List<&2,U32>,offers:List<&2,Core.PlayerOffers>,capture:O.Capture) -> IO(AuditResult):
  match audit capture:
    case _ O.Unobservable{_}: IO.die(AuditResult,1,"Audit cannot serialize opaque deferred commands")
    case Audit{mode,+actions,checkpoints,+nextCapture} O.Captured{state,text}:
      +ordinal = (checkpoints + 1 : U32)
      do IO<AuditResult>:
        IO.print("{\"type\":\"audit-checkpoint\",\"ordinal\":" ++ U32.show(ordinal) ++ ",\"tick\":" ++ U32.show(RS.session_tick(shared)) ++ ",\"reason\":\"" ++ reason ++ "\",\"state\":" ++ text ++ ",\"memories\":" ++ O.array([O.memory(m0),O.memory(m1)]) ++ ",\"driver\":{\"fuel\":" ++ Nat.show(fuel) ++ ",\"nextSample\":" ++ Nat.show(nextSample) ++ ",\"nextCapture\":" ++ Nat.show(nextCapture) ++ ",\"actions\":" ++ U32.show(actions) ++ ",\"choices\":" ++ O.array([U32.show(choices0),U32.show(choices1)]) ++ "}}")
        return AuditResult{Audit{mode,actions,ordinal,nextCapture},Observed{state,shared,p0,p1,rows,round,required,offers}}
def capture(reason:String,fuel:Nat,nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,audit:Audit,value:Observed) -> IO(AuditResult):
  match value:
    case Observed{state,shared,p0,p1,rows,round,required,offers}: capture_done(reason,fuel,nextSample,m0,m1,choices0,choices1,audit,shared,p0,p1,rows,round,required,offers,O.snapshot(state))
def capture_many(reasons:List<&2,String>,+fuel:Nat,+nextSample:Nat,+m0:Policy.Memory,+m1:Policy.Memory,+choices0:U32,+choices1:U32,value:AuditResult) -> IO(AuditResult):
  match reasons value:
    case [] value: IO.pure(AuditResult,value)
    case reason <> rest AuditResult{audit,observed}:
      do IO<AuditResult>:
        next : AuditResult <- capture(reason,fuel,nextSample,m0,m1,choices0,choices1,audit,observed)
        capture_many(rest,fuel,nextSample,m0,m1,choices0,choices1,next)
def required_choice(value:List<&2,U32>) -> Bool:
  match value:
    case []: False{}
    case _ <> _: True{}
def reason_if(test:Bool,reason:String) -> List<&2,String>:
  match test:
    case False{}: []
    case True{}: [reason]
def middle_reasons(stopped:Bool,start:Bool,due:Bool) -> List<&2,String>:
  match stopped start due:
    case True{} _ _: ["terminal"]
    case False{} True{} _: ["start"]
    case False{} False{} True{}: ["periodic"]
    case False{} False{} False{}: []
def capture_due(due:Bool,tick:U32,interval:U32,current:Nat) -> Nat:
  match due:
    case False{}: current
    case True{}: U32.to_nat((tick + interval : U32))
def audit_active(fuel:Nat,nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,+stopped:Bool,+lastAction:Maybe<&2,O.Action>,audit:Audit,value:Observed) -> IO(AuditResult):
  match audit value:
    case Audit{+mode,+actions,checkpoints,+nextCapture} Observed{state,+shared,p0,p1,rows,round,+required,offers}:
      +tick = RS.session_tick(shared)
      +choices = choice_captures(mode)
      +due = Bool.and(Bool.not(stopped),Bool.and(Bool.not(U32.is_eq(actions,0)),Bool.and(U32.is_lt(0,period(mode)),Nat.is_ge(U32.to_nat(tick),nextCapture))))
      reasons = List.append(&2,String,reason_if(Bool.and(choices,O.was_choice(lastAction)),"after-choice"),List.append(&2,String,middle_reasons(stopped,U32.is_eq(actions,0),due),reason_if(Bool.and(choices,Bool.and(Bool.not(stopped),required_choice(required))),"before-choice")))
      do IO<AuditResult>:
        emit_action(True{},actions,tick,lastAction)
        capture_many(reasons,fuel,nextSample,m0,m1,choices0,choices1,AuditResult{Audit{mode,actions,checkpoints,capture_due(due,tick,period(mode),nextCapture)},Observed{state,shared,p0,p1,rows,round,required,offers}})
def audit_observation(fuel:Nat,nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,stopped:Bool,lastAction:Maybe<&2,O.Action>,audit:Audit,value:Observed) -> IO(AuditResult):
  match audit:
    case Audit{Off{},actions,checkpoints,nextCapture}: IO.pure(AuditResult,AuditResult{Audit{Off{},actions,checkpoints,nextCapture},value})
    case audit: audit_active(fuel,nextSample,m0,m1,choices0,choices1,stopped,lastAction,audit,value)

def sampled(emit:Bool,text:String,nextSample:Nat,progress:Progress,next:Progress -> Nat -> IO(Unit)) -> IO(Unit):
  match emit:
    case True{}:
      do IO<Unit>:
        IO.print("{\"type\":\"sample\"," ++ text ++ "}")
        IO.print_err("Co-op balance sample")
        next(progress,nextSample)
    case False{}: next(progress,nextSample)
def next_sample(emit:Bool,tick:U32,current:Nat) -> Nat: Bool.pick(Nat,emit,Nat.add(U32.to_nat(tick),60n),current)
def run_observed(stopped:Bool,+outcome:Control.Outcome,+seed:U32,index:U32,+ticks:U32,started:Nat,+nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,+choices0:U32,+choices1:U32,audit:Audit,observed:Observed,next:Progress -> Nat -> IO(Unit)) -> IO(Unit):
  match stopped observed:
    case True{} Observed{_,+shared,p0,p1,rows,_,_,_}:
      do IO<Unit>:
        now : Nat <- IO.now()
        IO.print("{\"type\":\"summary\"," ++ fields(seed,index,ticks,shared,p0,p1,rows,choices0,choices1) ++ ",\"outcome\":\"" ++ Control.name(outcome) ++ "\",\"wallMs\":" ++ Nat.show(Nat.sub(now,started)) ++ "}")
        IO.print_err("Completed native co-op seed " ++ U32.show(seed) ++ " at tick " ++ U32.show(RS.session_tick(shared)))
        ended(audit,RS.session_tick(shared),outcome)
    case False{} Observed{state,+shared,+p0,+p1,+rows,round,+required,offers}:
      +emit = Nat.is_ge(U32.to_nat(RS.session_tick(shared)),nextSample)
      sampled(emit,fields(seed,index,ticks,shared,p0,p1,rows,choices0,choices1),next_sample(emit,RS.session_tick(shared),nextSample),choose_or_move(active(audit),required,state,shared,p0,p1,rows,round,offers,m0,m1,choices0,choices1),next)
def inspect(seed:U32,index:U32,+ticks:U32,started:Nat,nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,value:AuditResult,next:Audit -> Progress -> Nat -> IO(Unit)) -> IO(Unit):
  match value:
    case AuditResult{+audit,Observed{state,+shared,p0,p1,rows,round,required,offers}}:
      +result = Control.outcome(RS.session_phase(shared),RS.session_tick(shared),ticks)
      run_observed(Control.stopped(result),result,seed,index,ticks,started,nextSample,m0,m1,choices0,choices1,audit,Observed{state,shared,p0,p1,rows,round,required,offers},(progress => nextSample => next(advance(audit))(progress)(nextSample)))
def inspect_observation(seed:U32,index:U32,+ticks:U32,started:Nat,fuel:Nat,+nextSample:Nat,+m0:Policy.Memory,+m1:Policy.Memory,+choices0:U32,+choices1:U32,audit:Audit,action:Maybe<&2,O.Action>,value:Observed,next:Audit -> Progress -> Nat -> IO(Unit)) -> IO(Unit):
  match value:
    case Observed{state,+shared,p0,p1,rows,round,required,offers}:
      do IO<Unit>:
        captured : AuditResult <- audit_observation(fuel,nextSample,m0,m1,choices0,choices1,Control.stopped(Control.outcome(RS.session_phase(shared),RS.session_tick(shared),ticks)),action,audit,Observed{state,shared,p0,p1,rows,round,required,offers})
        inspect(seed,index,ticks,started,nextSample,m0,m1,choices0,choices1,captured,next)
def inspect_ready(ready:Checked,seed:U32,index:U32,ticks:U32,started:Nat,fuel:Nat,nextSample:Nat,m0:Policy.Memory,m1:Policy.Memory,choices0:U32,choices1:U32,audit:Audit,action:Maybe<&2,O.Action>,next:Audit -> Progress -> Nat -> IO(Unit)) -> IO(Unit):
  match ready:
    case CoopBroken{message}: IO.die(Unit,1,message)
    case CoopReady{observed}: inspect_observation(seed,index,ticks,started,fuel,nextSample,m0,m1,choices0,choices1,audit,action,observed,next)
def loop(fuel:Nat,+seed:U32,+index:U32,+ticks:U32,+started:Nat,nextSample:Nat,audit:Audit,progress:Progress) -> IO(Unit):
  match fuel progress:
    case 0n _: IO.die(Unit,1,"Native co-op exhausted safety fuel")
    case 1n+ +rest Progress{ALeaf{Step.Progress{packet,m0,m1,choices0,choices1,action}}}: inspect_ready(observe(packet),seed,index,ticks,started,rest,nextSample,m0,m1,choices0,choices1,audit,shared_action(action),(audit => progress => nextSample => loop(rest,seed,index,ticks,started,nextSample,audit,progress)))
    case _ _: IO.die(Unit,1,"Native co-op progress carrier must be one leaf")

def audit_start(mode:Mode,seed:U32,index:U32,ticks:U32,advanced:Bool,character0:U32,character1:U32,arcana0:U32,arcana1:U32) -> IO(Unit):
  match mode:
    case Off{}: IO.pure(Unit,Unit{})
    case +mode: IO.print("{\"type\":\"audit-start\",\"schema\":\"bendvy-coop-observer-v3\",\"mode\":\"" ++ mode_name(mode) ++ "\",\"seed\":" ++ U32.show(seed) ++ ",\"index\":" ++ U32.show(index) ++ ",\"requestedTicks\":" ++ U32.show(ticks) ++ ",\"profile\":\"" ++ Bool.pick(String,advanced,"advanced","fresh") ++ "\",\"characters\":" ++ O.array([U32.show(character0),U32.show(character1)]) ++ ",\"arcanas\":" ++ O.array([U32.show(arcana0),U32.show(arcana1)]) ++ ",\"period\":" ++ U32.show(period(mode)) ++ "}")
def launch_mode(+mode:Mode,+seed:U32,+index:U32,+ticks:U32,+advanced:Bool,+character0:U32,+character1:U32,+arcana0:U32,+arcana1:U32,started:Nat) -> IO(Unit):
  do IO<Unit>:
    audit_start(mode,seed,index,ticks,advanced,character0,character1,arcana0,arcana1)
    loop(U32.to_nat((ticks * 8 + 100 : U32)),seed,index,ticks,started,0n,Audit{mode,0,0,U32.to_nat(period(mode))},Progress{Step.initial(seed,advanced,character0,character1,arcana0,arcana1)})
def parsed_mode(text:String,seed:U32,index:U32,ticks:U32,advanced:Bool,character0:U32,character1:U32,arcana0:U32,arcana1:U32,started:Nat) -> IO(Unit):
  match text:
    case "": launch_mode(Off{},seed,index,ticks,advanced,character0,character1,arcana0,arcana1,started)
    case "off": launch_mode(Off{},seed,index,ticks,advanced,character0,character1,arcana0,arcana1,started)
    case "scheduled": launch_mode(Scheduled{},seed,index,ticks,advanced,character0,character1,arcana0,arcana1,started)
    case "dense": launch_mode(Dense{},seed,index,ticks,advanced,character0,character1,arcana0,arcana1,started)
    case "terminal": launch_mode(Terminal{},seed,index,ticks,advanced,character0,character1,arcana0,arcana1,started)
    case _: IO.die(Unit,1,"Unknown NIGHTFALL_COOP_AUDIT mode")
def launch(seedText:String,indexText:String,ticksText:String,profileText:String,character0Text:String,character1Text:String,arcana0Text:String,arcana1Text:String,auditText:String,started:Nat) -> IO(Unit):
  +advanced = String.eq(profileText,"advanced")
  seed = number(seedText,12345)
  index = number(indexText,0)
  ticks = U32.max(1,U32.min(37000,number(ticksText,7200)))
  parsed_mode(auditText,seed,index,ticks,advanced,number(character0Text,profile_character(advanced)),number(character1Text,profile_character(advanced)),number(arcana0Text,profile_arcana(advanced)),number(arcana1Text,profile_arcana(advanced)),started)
def main() -> IO(Unit):
  do IO<Unit>:
    seedText : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_SEED")
    indexText : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_INDEX")
    ticksText : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_TICKS")
    profileText : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_PROFILE")
    character0Text : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_CHARACTER0")
    character1Text : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_CHARACTER1")
    arcana0Text : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_ARCANA0")
    arcana1Text : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_ARCANA1")
    auditText : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_COOP_AUDIT")
    started : Nat <- IO.now()
    launch(environment(seedText),environment(indexText),environment(ticksText),environment(profileText),environment(character0Text),environment(character1Text),environment(arcana0Text),environment(arcana1Text),environment(auditText),started)
