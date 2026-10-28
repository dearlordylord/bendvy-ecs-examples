import game-observation.bend as Model
import pickup-state.bend as Pickup
import run-state.bend as RS
# Native, unpaced simulation. No browser, Node, classifier, or frame parsing.
import Base
import game-components.bend as Components
import game.bend as G
import bot-profile.bend as B
import offline-policy.bend as Policy
import bot-driver.bend as Driver

def environment(result: Result<&1,&1,U32 & String,String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: ""
def parsed(value: Maybe<&2,U32>,+default: U32) -> U32:
  match value:
    case Some{value}: value
    case None{}: default
def number(+text: String,+default: U32) -> U32: parsed(U32.read(text),default)
def profile_name(+profile: U32) -> String:
  match profile:
    case 1: "advanced"
    case _: "fresh"
def select_profile(+name: String,+index: U32) -> U32:
  match name:
    case "advanced": 1
    case "both": (index % 2 : U32)
    case _: 0
def start(+profile: U32,+seed: U32) -> G.Packet:
  match profile:
    case 1: B.advanced_start_seed(seed)
    case _: B.fresh_start_seed(seed)
def tick(+run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,value,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: value
def outcome(terminal: Bool) -> String:
  match terminal:
    case True{}: "terminal"
    case False{}: "bounded-observation"
def phase(+run: Model.Run) -> U32: G.run_phase(run)
def piles(rows: List<&2,Model.Snapshot>) -> U32:
  match rows:
    case []: 0
    case Model.PickupSnapshot{Pickup.State{_,Pickup.Payload{Pickup.Xp{_,_},_,True{}},_}} <> rest: (1 + piles(rest) : U32)
    case _ <> rest: piles(rest)
def xp_sum(rows: List<&2,Model.Snapshot>) -> U32:
  match rows:
    case []: 0
    case Model.PickupSnapshot{Pickup.State{_,Pickup.Payload{Pickup.Xp{amount,_},_,True{}},_}} <> rest: (amount + xp_sum(rest) : U32)
    case _ <> rest: xp_sum(rest)
def report(+index: U32,+seed: U32,+profile: U32,+choices: U32,+started: Nat,+ticks: U32,+run: Model.Run,+rows: List<&2,Model.Snapshot>) -> IO(Unit):
  match run:
    case Model.Run{RS.Session{+phase,+tick,xp,xpNeed,level,kills,gold,_,_,_,_,_,_},RS.PlayerState{_,_,hp,_,_,_,_,_,_,_,_,_,_,_,_,_}}:
      do IO<Unit>:
        now : Nat <- IO.now()
        IO.print("{\"type\":\"summary\",\"backend\":\"native\",\"policy\":\"bend-resource-memory-v1\",\"index\":" ++ U32.show(index) ++ ",\"seed\":" ++ U32.show(seed) ++ ",\"profile\":\"" ++ profile_name(profile) ++ "\",\"status\":\"completed\",\"tick\":" ++ U32.show(tick) ++ ",\"requestedTicks\":" ++ U32.show(ticks) ++ ",\"outcome\":\"" ++ outcome(U32.is_le(3,phase)) ++ "\",\"phase\":" ++ U32.show(phase) ++ ",\"hp\":" ++ U32.show(hp) ++ ",\"level\":" ++ U32.show(level) ++ ",\"xp\":" ++ U32.show(xp) ++ ",\"xpNeed\":" ++ U32.show(xpNeed) ++ ",\"kills\":" ++ U32.show(kills) ++ ",\"gold\":" ++ U32.show(gold) ++ ",\"choices\":" ++ U32.show(choices) ++ ",\"xpPiles\":" ++ U32.show(piles(rows)) ++ ",\"uncollectedBaseXp\":" ++ U32.show(xp_sum(rows)) ++ ",\"wallMs\":" ++ Nat.show(Nat.sub(now,started)) ++ "}")
        # Bend buffers stdout; stderr progress flushes the completed JSONL record.
        IO.print_err("Completed native seed " ++ U32.show(seed) ++ " at tick " ++ U32.show(tick))
type BatchReady is Type: BatchReady{finished: Bool,progress: Driver.Progress}
def gate(+ticks: U32,result: Driver.Progress) -> BatchReady:
  match result:
    case Driver.Progress{memory,G.Packet{G.State{world,+run,offers,snapshots,pending}},choices}: BatchReady{Bool.or(U32.is_le(ticks,tick(run)),U32.is_le(3,phase(run))),Driver.Progress{memory,G.Packet{G.State{world,run,offers,snapshots,pending}},choices}}
    case result: BatchReady{True{},result}
def loop(+fuel: Nat,+ticks: U32,+index: U32,+seed: U32,+profile: U32,+started: Nat,observed: BatchReady) -> IO(Unit):
  match fuel observed:
    case _ BatchReady{_,Driver.Progress{_,G.Failed{error},_}}: IO.die(Unit,1,"Native batch game failure: " ++ error)
    case _ BatchReady{True{},Driver.Progress{_,G.Packet{G.State{_,run,_,snapshots,_}},choices}}: report(index,seed,profile,choices,started,ticks,run,snapshots)
    case 0n _: IO.die(Unit,1,"Native batch exhausted safety fuel before requested tick horizon")
    case 1n+rest BatchReady{False{},progress}:
      loop(rest,ticks,index,seed,profile,started,gate(ticks,Driver.step(progress)))
def batch(+left: Nat,+index: U32,+stride: U32,+seed: U32,+profile: String,+ticks: U32) -> IO(Unit):
  match left:
    case 0n:
      do IO<Unit>:
        return Unit{}
    case 1n+rest:
      do IO<Unit>:
        started : Nat <- IO.now()
        loop(U32.to_nat((ticks * 4 + 100 : U32)),ticks,index,(seed + index : U32),select_profile(profile,index),started,gate(ticks,Driver.Progress{Policy.initial(),start(select_profile(profile,index),(seed + index : U32)),0}))
        batch(rest,(index + stride : U32),stride,seed,profile,ticks)
def main() -> IO(Unit):
  do IO<Unit>:
    count : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_COUNT")
    ticks : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_TICKS")
    seed : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_SEED")
    profile : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_PROFILE")
    index : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_INDEX")
    stride : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_STRIDE")
    batch(U32.to_nat(number(environment(count),1)),number(environment(index),0),number(environment(stride),1),number(environment(seed),12345),environment(profile),number(environment(ticks),1800))
