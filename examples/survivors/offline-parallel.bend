import game-observation.bend as Model
import run-state.bend as RS
# Independent native Bend worlds. No Node, classifier, rendering or per-job IO.
import Base
import game-components.bend as Components
import game.bend as G
import offline-policy.bend as Policy
import bot-driver.bend as Driver
import offline-batch.bend as Serial
import parallel/scheduler.bend as Scheduler

# GPU workers return only detached numeric result fields on successful jobs.
# JSON construction and error-message prefixes belong to the host emitter.
type NumericSummary is Data:
  NumericSummary{index: U32,seed: U32,profile: U32,choices: U32,requestedTicks: U32,phase: U32,tick: U32,hp: U32,level: U32,xp: U32,xpNeed: U32,kills: U32,gold: U32,xpPiles: U32,uncollectedBaseXp: U32}

def capture(+index: U32,+seed: U32,+profile: U32,+choices: U32,+ticks: U32,+run: Model.Run,+rows: List<&2,Model.Snapshot>) -> NumericSummary:
  match run:
    case Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,_,_,_,_,_,_},RS.PlayerState{_,_,hp,_,_,_,_,_,_,_,_,_,_,_,_,_}}:
      NumericSummary{index,seed,profile,choices,ticks,phase,tick,hp,level,xp,xpNeed,kills,gold,Serial.piles(rows),Serial.xp_sum(rows)}
def summary(result: NumericSummary) -> String:
  match result:
    case NumericSummary{index,seed,profile,choices,requestedTicks,+phase,tick,hp,level,xp,xpNeed,kills,gold,xpPiles,uncollectedBaseXp}:
      "{\"type\":\"summary\",\"backend\":\"native\",\"policy\":\"bend-resource-memory-v1\",\"index\":" ++ U32.show(index) ++ ",\"seed\":" ++ U32.show(seed) ++ ",\"profile\":\"" ++ Serial.profile_name(profile) ++ "\",\"status\":\"completed\",\"tick\":" ++ U32.show(tick) ++ ",\"requestedTicks\":" ++ U32.show(requestedTicks) ++ ",\"outcome\":\"" ++ Serial.outcome(U32.is_le(3,phase)) ++ "\",\"phase\":" ++ U32.show(phase) ++ ",\"hp\":" ++ U32.show(hp) ++ ",\"level\":" ++ U32.show(level) ++ ",\"xp\":" ++ U32.show(xp) ++ ",\"xpNeed\":" ++ U32.show(xpNeed) ++ ",\"kills\":" ++ U32.show(kills) ++ ",\"gold\":" ++ U32.show(gold) ++ ",\"choices\":" ++ U32.show(choices) ++ ",\"xpPiles\":" ++ U32.show(xpPiles) ++ ",\"uncollectedBaseXp\":" ++ U32.show(uncollectedBaseXp) ++ ",\"wallMs\":" ++ "null" ++ "}"

type Finished is Data:
  Complete{result: NumericSummary}
  Failed{error: String}
  SafetyFuel{}

def simulate(+fuel: Nat,+ticks: U32,+index: U32,+seed: U32,+profile: U32,observed: Serial.BatchReady) -> Finished:
  match fuel observed:
    case _ Serial.BatchReady{_,Driver.Progress{_,G.Failed{error},_}}: Failed{error}
    case _ Serial.BatchReady{True{},Driver.Progress{_,G.Packet{G.State{_,run,_,snapshots,_}},choices}}: Complete{capture(index,seed,profile,choices,ticks,run,snapshots)}
    case 0n _: SafetyFuel{}
    case 1n+rest Serial.BatchReady{False{},progress}:
      simulate(rest,ticks,index,seed,profile,Serial.gate(ticks,Driver.step(progress)))
# Parse profile names on the host once; mode 2 alternates by global job index.
def profile_mode(name: String) -> U32:
  match name:
    case "advanced": 1
    case "both": 2
    case _: 0
def select_profile(+mode: U32,+index: U32) -> U32:
  match mode:
    case 2: (index % 2 : U32)
    case _: mode
def job(+ticks: U32,+seed: U32,+profile: U32,+index: U32) -> Finished:
  simulate(U32.to_nat((ticks * 4 + 100 : U32)),ticks,index,(seed + index : U32),select_profile(profile,index),Serial.gate(ticks,Driver.Progress{Policy.initial(),Serial.start(select_profile(profile,index),(seed + index : U32)),0}))
def emit(result: Finished) -> IO(Unit):
  match result:
    case Failed{error}: IO.die(Unit,1,"Native batch game failure: " ++ error)
    case SafetyFuel{}: IO.die(Unit,1,"Native batch exhausted safety fuel before requested tick horizon")
    case Complete{result}:
      do IO<Unit>:
        IO.print(summary(result))
        IO.print_err("Completed native Bend parallel result")

type JobContext is Data: JobContext{ticks: U32,seed: U32,profile: U32}
def run_job(context: JobContext,index: U32) -> Finished:
  match context:
    case JobContext{ticks,seed,profile}: job(ticks,seed,profile,index)
def emit_all(results: List<&2,Finished>) -> IO(Unit):
  match results:
    case []:
      do IO<Unit>:
        return Unit{}
    case first <> rest:
      do IO<Unit>:
        emit(first)
        emit_all(rest)
def batch(count: U32,index: U32,stride: U32,seed: U32,profile: String,ticks: U32) -> IO(Unit):
  emit_all(Scheduler.to_list(~Finished,Scheduler.map_parallel(~JobContext,~Finished,~run_job,JobContext{ticks,seed,profile_mode(profile)},Scheduler.build(count,index,stride))))
def main() -> IO(Unit):
  do IO<Unit>:
    count : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_COUNT")
    ticks : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_TICKS")
    seed : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_SEED")
    profile : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_PROFILE")
    index : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_INDEX")
    stride : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BATCH_STRIDE")
    batch(Serial.number(Serial.environment(count),1),Serial.number(Serial.environment(index),0),Serial.number(Serial.environment(stride),1),Serial.number(Serial.environment(seed),12345),Serial.environment(profile),Serial.number(Serial.environment(ticks),1800))
