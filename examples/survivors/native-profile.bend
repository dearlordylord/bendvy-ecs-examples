import game-observation.bend as Model
import run-state.bend as RS
# Native run observations and file IO adapt the proved profile economy.
import Base
import native-economy.bend as E
import native-record.bend as R
import native-profile-codec.bend as Codec

def receipt(run: Model.Run) -> R.Receipt:
  match run:
    case Model.Run{RS.Session{phase,tick,_,_,level,kills,gained,seed,stage,bosses,_,enemies,relic},RS.PlayerState{_,_,_,_,character,weapons,_,_,_,_,revivals,_,_,_,_,_}}:
      R.Receipt{phase,tick,level,kills,gained,character,weapons,seed,stage,revivals,bosses,enemies,relic}
def record(profile: E.Profile,run: Model.Run) -> E.Profile: R.record(profile,receipt(run))
def loaded_text(result: Result<&1,&1,U32 & String,String>) -> E.Profile:
  match result:
    case Fail{_}: E.fresh()
    case Done{text}: Codec.decode(text)
def loaded_read(read: File & Result<&1,&1,U32 & String,String>) -> IO(E.Profile):
  match read:
    case (file,result):
      do IO<E.Profile>:
        File.close(file)
        return loaded_text(result)
def loaded(opened: Result<&1,&1,U32 & String,File>) -> IO(E.Profile):
  match opened:
    case Fail{_}: IO.pure(E.Profile,E.fresh())
    case Done{file}:
      do IO<E.Profile>:
        read : File & Result<&1,&1,U32 & String,String> <- File.read(file,8192)
        loaded_read(read)
def load() -> IO(E.Profile):
  do IO<E.Profile>:
    opened : Result<&1,&1,U32 & String,File> <- File.open("nightfall-profile.txt","r")
    loaded(opened)
type SaveResult is Data:
  Saved{}
  SaveFailed{error: String}
def save_failed(stage: String,code: U32,error: String) -> SaveResult:
  SaveFailed{"Could not save native profile: " ++ stage ++ " failed (" ++ U32.show(code) ++ "): " ++ error}
def verified_matches(matches: Bool) -> SaveResult:
  match matches:
    case True{}: Saved{}
    case False{}: SaveFailed{"Could not save native profile: saved file contents differ."}
def verified_text(result: Result<&1,&1,U32 & String,String>,expected: String) -> SaveResult:
  match result:
    case Fail{(code,error)}: save_failed("reading saved file",code,error)
    case Done{text}: verified_matches(String.eq(text,expected))
def verified_read(read: File & Result<&1,&1,U32 & String,String>,expected: String) -> IO(SaveResult):
  match read:
    case (file,result):
      do IO<SaveResult>:
        File.close(file)
        return verified_text(result,expected)
def verified(opened: Result<&1,&1,U32 & String,File>,expected: String) -> IO(SaveResult):
  match opened:
    case Fail{(code,error)}: IO.pure(SaveResult,save_failed("opening saved file",code,error))
    case Done{file}:
      do IO<SaveResult>:
        read : File & Result<&1,&1,U32 & String,String> <- File.read(file,8192)
        verified_read(read,expected)
def moved_status(result: Result<&1,&1,U32 & String,U32 & (String & String)>,expected: String) -> IO(SaveResult):
  match result:
    case Fail{(code,error)}: IO.pure(SaveResult,save_failed("replacing file",code,error))
    case Done{(0,_)}:
      do IO<SaveResult>:
        opened : Result<&1,&1,U32 & String,File> <- File.open("nightfall-profile.txt","r")
        verified(opened,expected)
    case Done{(status,(_,error))}: IO.pure(SaveResult,save_failed("replacing file",status,error))
def saved_result(result: Result<&1,&1,U32 & String,Unit>,expected: String) -> IO(SaveResult):
  match result:
    case Fail{(code,error)}: IO.pure(SaveResult,save_failed("writing file",code,error))
    case Done{_}:
      do IO<SaveResult>:
        result : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run("/bin/mv",["-f","nightfall-profile.tmp","nightfall-profile.txt"],"",4096,2000)
        moved_status(result,expected)
def saved_write(written: File & Result<&1,&1,U32 & String,Unit>,expected: String) -> IO(SaveResult):
  match written:
    case (file,result):
      do IO<SaveResult>:
        File.close(file)
        saved_result(result,expected)
def saved(opened: Result<&1,&1,U32 & String,File>,+text: String) -> IO(SaveResult):
  match opened:
    case Fail{(code,error)}: IO.pure(SaveResult,save_failed("opening file",code,error))
    case Done{file}:
      do IO<SaveResult>:
        written : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,text)
        saved_write(written,text)
def save(profile: E.Profile) -> IO(SaveResult):
  do IO<SaveResult>:
    opened : Result<&1,&1,U32 & String,File> <- File.open("nightfall-profile.tmp","w")
    saved(opened,Codec.encode(profile))
