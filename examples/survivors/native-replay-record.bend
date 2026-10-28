import game-observation.bend as Model
import Base
import game-components.bend as Components
import game.bend as G
import offline-policy.bend as Policy
import native-replay-format.bend as F
import native-replay-common.bend as C
import native-replay-observe.bend as O

# Ordinary native-policy recorder. Trace generation and snapshots are not a
# benchmark. Replay consumes exactly these recorded directions and offer indices.
type Recorded is Type: Recorded{memory: Policy.Memory,packet: G.Packet,action: F.Action}
type Progress is Type: Progress{memory: Policy.Memory,packet: G.Packet,actions: List<&2,F.Action>,step: U32,begun: Bool}
type RecordReady is Type: RecordReady{stop: Bool,progress: Progress}

def checkpoint_result(result: G.State & String,+fixture: String,+step: U32,use: G.State -> IO(Unit)) -> IO(Unit):
  match result:
    case (state,+payload):
      do IO<Unit>:
        IO.print("{\"type\":\"checkpoint\",\"fixture\":\"" ++ C.escape(fixture) ++ "\",\"step\":" ++ U32.show(step) ++ ",\"payload\":" ++ payload ++ "}")
        use(state)
def checkpoint(enabled: Bool,state: G.State,+fixture: String,+step: U32,use: G.State -> IO(Unit)) -> IO(Unit):
  match enabled:
    case True{}: checkpoint_result(O.snapshot(state),fixture,step,use)
    case False{}: use(state)
def recorded_direction(direction: F32 & F32,memory: Policy.Memory,state: G.State,+run: Model.Run) -> Recorded:
  (+dx,+dy)=direction
  +action : F.Action = F.ReplayMove{C.tick(run),G.run_phase(run),F.float_bits(dx),F.float_bits(dy)}
  Recorded{memory,C.apply(action,state),action}
def recorded_move(result: Policy.Memory & (F32 & F32),state: G.State,run: Model.Run) -> Recorded:
  (memory,direction)=result
  recorded_direction(direction,memory,state,run)
def next(phase: U32,state: G.State,+run: Model.Run,+offers: List<&2,Model.Offer>,memory: Policy.Memory,snapshots: List<&2,Model.Snapshot>) -> Recorded:
  match phase:
    case 1:
      +action : F.Action = F.ReplayUpgrade{C.tick(run),1,Policy.upgrade(run,offers)}
      Recorded{memory,C.apply(action,state),action}
    case 2:
      +action : F.Action = F.ReplayUpgrade{C.tick(run),2,Policy.upgrade(run,offers)}
      Recorded{memory,C.apply(action,state),action}
    case _: recorded_move(Policy.movement(memory,run,snapshots),state,run)
def progressed(result: Recorded,actions: List<&2,F.Action>,step: U32,begun: Bool) -> Progress:
  match result:
    case Recorded{memory,packet,action}: Progress{memory,packet,action <> actions,(step + 1 : U32),begun}
def gate(+endTick: U32,progress: Progress) -> RecordReady:
  match progress:
    case Progress{memory,G.Packet{G.State{world,+run,offers,snapshots,pending}},actions,step,begun}:
      RecordReady{Bool.or(U32.is_le(endTick,C.tick(run)),C.is_terminal(run)),Progress{memory,G.Packet{G.State{world,run,offers,snapshots,pending}},actions,step,begun}}
    case progress: RecordReady{True{},progress}
def final_saved(valid: Bool,+fixture: String,+path: String,+profile: U32,+seed: U32,+warmup: U32,+endTick: U32,+actualEnd: U32,+finalPhase: U32,+actions: List<&2,F.Action>,+step: U32,+begun: Bool,state: G.State) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,1,"Policy terminated before requested warmup tick; dense fixture not produced")
    case True{}:
      checkpoint(Bool.not(begun),state,fixture,step,(state => checkpoint(True{},state,fixture,step,(state =>
        do IO<Unit>:
          C.save(path,F.encode(F.Trace{profile,seed,warmup,endTick,actualEnd,finalPhase,List.reverse(&2,F.Action,actions)}))
          IO.print("{\"type\":\"summary\",\"fixture\":\"" ++ C.escape(fixture) ++ "\",\"actions\":" ++ U32.show(step) ++ ",\"firstTick\":" ++ U32.show(warmup) ++ ",\"endTick\":" ++ U32.show(actualEnd) ++ ",\"phase\":" ++ U32.show(finalPhase) ++ "}")
          IO.print_err("Recorded native actions to " ++ path)
      ))))
def loop(+fuel: Nat,+fixture: String,+path: String,+profile: U32,+seed: U32,+warmup: U32,+endTick: U32,+every: U32,ready: RecordReady) -> IO(Unit):
  match fuel ready:
    case _ RecordReady{_,Progress{_,G.Failed{error},_,_,_}}: IO.die(Unit,1,"Native action recording failed: " ++ error)
    case _ RecordReady{True{},Progress{_,G.Packet{G.State{world,+run,offers,snapshots,pending}},actions,step,+begun}}:
      final_saved(U32.is_le(warmup,C.tick(run)),fixture,path,profile,seed,warmup,endTick,C.tick(run),G.run_phase(run),actions,step,begun,G.State{world,run,offers,snapshots,pending})
    case 0n _: IO.die(Unit,1,"Native recorder exhausted safety fuel")
    case 1n+rest RecordReady{False{},Progress{memory,G.Packet{G.State{world,+run,+offers,+snapshots,pending}},+actions,+step,+begun}}:
      +active=U32.is_le(warmup,C.tick(run))
      +observe=Bool.and(active,Bool.or(Bool.not(begun),Bool.and(U32.is_lt(0,every),U32.is_eq((step % U32.max(1,every) : U32),0))))
      checkpoint(observe,G.State{world,run,offers,snapshots,pending},fixture,step,(state => loop(rest,fixture,path,profile,seed,warmup,endTick,every,gate(endTick,progressed(next(G.run_phase(run),state,run,offers,memory,snapshots),actions,step,Bool.or(begun,active))))))
def begin(valid: Bool,+path: String,+profile: U32,+seed: U32,+warmup: U32,+endTick: U32,+every: U32) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,1,"Invalid native recording profile/warmup/endTick")
    case True{}:
      do IO<Unit>:
        IO.print("{\"type\":\"start\",\"schemaVersion\":1,\"fixture\":\"" ++ C.fixture(seed,profile,warmup,endTick) ++ "\",\"seed\":" ++ U32.show(seed) ++ ",\"profile\":" ++ U32.show(profile) ++ ",\"warmup\":" ++ U32.show(warmup) ++ ",\"endTick\":" ++ U32.show(endTick) ++ "}")
        loop(U32.to_nat((endTick * 4 + 100 : U32)),C.fixture(seed,profile,warmup,endTick),path,profile,seed,warmup,endTick,every,gate(endTick,Progress{Policy.initial(),C.start(profile,seed),[],0,False{}}))
def main() -> IO(Unit):
  do IO<Unit>:
    path : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_REPLAY_TRACE")
    profile : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_REPLAY_PROFILE")
    seed : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_REPLAY_SEED")
    warmup : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_REPLAY_WARMUP")
    endTick : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_REPLAY_END_TICK")
    every : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_REPLAY_CHECKPOINT_EVERY")
    +profile : U32 = C.number(C.environment(profile),0)
    +warmup : U32 = C.number(C.environment(warmup),0)
    +endTick : U32 = C.number(C.environment(endTick),1200)
    begin(Bool.and(U32.is_le(profile,1),Bool.and(U32.is_le(warmup,endTick),U32.is_le(endTick,1000000))),C.default_text(C.environment(path),"/tmp/nightfall-actions.trace"),profile,C.number(C.environment(seed),100),warmup,endTick,C.number(C.environment(every),0))
