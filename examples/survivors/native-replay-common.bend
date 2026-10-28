import game-observation.bend as Model
import run-state.bend as RS
import Base
import game.bend as G
import bot-profile.bend as B
import native-replay-format.bend as F

# Shared plumbing is outside benchmark clock boundaries. No Policy import.
def environment(result: Result<&1,&1,U32 & String,String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: ""
def parsed(value: Maybe<&2,U32>,fallback: U32) -> U32:
  match value:
    case Some{value}: value
    case None{}: fallback
def number(text: String,fallback: U32) -> U32: parsed(U32.read(text),fallback)
def default_text(text: String,fallback: String) -> String:
  match text:
    case "": fallback
    case text: text
def start(profile: U32,seed: U32) -> G.Packet:
  match profile:
    case 1: B.advanced_start_seed(seed)
    case _: B.fresh_start_seed(seed)
def tick(run: Model.Run) -> U32:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: tick
def is_terminal(run: Model.Run) -> Bool: U32.is_le(3,G.run_phase(run))
def action_tick(action: F.Action) -> U32:
  match action:
    case F.ReplayMove{tick,_,_,_}: tick
    case F.ReplayUpgrade{tick,_,_}: tick
def action_phase(action: F.Action) -> U32:
  match action:
    case F.ReplayMove{_,phase,_,_}: phase
    case F.ReplayUpgrade{_,phase,_}: phase
def choose_valid(valid: Bool,state: G.State,choice: U32) -> G.Packet:
  match valid:
    case True{}: G.choose(state,choice)
    case False{}: G.Failed{"Replay upgrade index is not an offered action"}
def apply_checked(valid: Bool,action: F.Action,state: G.State,offers: List<&2,Model.Offer>) -> G.Packet:
  match valid action:
    case False{} _: G.Failed{"Replay action tick/phase differs from actual game state"}
    case True{} F.ReplayMove{_,_,dx,dy}: G.advance(state,F.from_bits(dx),F.from_bits(dy))
    case True{} F.ReplayUpgrade{_,_,+choice}: choose_valid(Nat.is_lt(U32.to_nat(choice),List.length(&2,Model.Offer,offers)),state,choice)
def apply(+action: F.Action,state: G.State) -> G.Packet:
  match state:
    case G.State{world,+run,+offers,snapshots,pending}:
      apply_checked(Bool.and(U32.is_eq(action_tick(action),tick(run)),U32.is_eq(action_phase(action),G.run_phase(run))),action,G.State{world,run,offers,snapshots,pending},offers)

def loaded_length(valid: Bool,text: String) -> IO(String):
  match valid:
    case True{}:
      do IO<String>:
        return text
    case False{}: IO.die(String,1,"Replay trace was not read in full")
def loaded(result: File & Result<&1,&1,U32 & String,String>,+expected: U32) -> IO(String):
  match result:
    case (file,Done{+text}):
      do IO<String>:
        File.close(file)
        loaded_length(Nat.is_eq(String.length(text),U32.to_nat(expected)),text)
    case (file,Fail{_}):
      do IO<String>:
        File.close(file)
        IO.die(String,1,"Replay trace read failed")
def load_sized(valid: Bool,file: File,+size: U32) -> IO(String):
  match valid:
    case False{}:
      do IO<String>:
        File.close(file)
        IO.die(String,1,"Replay trace exceeds 32 MiB limit")
    case True{}:
      do IO<String>:
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,size)
        loaded(result,size)
def load_size(result: File & Result<&1,&1,U32 & String,U32>) -> IO(String):
  match result:
    case (file,Done{+size}): load_sized(U32.is_le(size,33554432),file,size)
    case (file,Fail{_}):
      do IO<String>:
        File.close(file)
        IO.die(String,1,"Replay trace size failed")
def load(path: String) -> IO(String):
  do IO<String>:
    file : File <- IO.try(File,File.open(path,"r"))
    sized : File & Result<&1,&1,U32 & String,U32> <- File.size(file)
    load_size(sized)
def saved(result: File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  match result:
    case (file,Done{_}): File.close(file)
    case (file,Fail{_}):
      do IO<Unit>:
        File.close(file)
        IO.die(Unit,1,"Replay trace write failed")
def save(path: String,text: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,text)
    saved(result)

def escape(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{34},rest}: "\\\"" ++ escape(rest)
    case SCon{Chr{92},rest}: "\\\\" ++ escape(rest)
    case SCon{Chr{10},rest}: "\\n" ++ escape(rest)
    case SCon{Chr{13},rest}: "\\r" ++ escape(rest)
    case SCon{Chr{9},rest}: "\\t" ++ escape(rest)
    case SCon{Chr{8},rest}: "\\b" ++ escape(rest)
    case SCon{Chr{12},rest}: "\\f" ++ escape(rest)
    case SCon{char,rest}: SCon{char,escape(rest)}
def fixture(+seed: U32,+profile: U32,+warmup: U32,endTick: U32) -> String:
  "seed" ++ U32.show(seed) ++ "-profile" ++ U32.show(profile) ++ "-warm" ++ U32.show(warmup) ++ "-end" ++ U32.show(endTick)
