import game-observation.bend as Model
import Base
import game.bend as G
import bot-profile.bend as B
import bot-driver.bend as Driver
import offline-policy.bend as Policy
import native.bend as N
import native-economy.bend as P
import bot-pacing.bend as Pacing
import bot-metrics.bend as Metrics
import native_draw.bend as D
import bot-window-loop.bend as WindowLoop

type Bot is Type: Bot{progress: Driver.Progress,last: Nat,started: Nat,ticks: U32,seconds: U32,pacing: Pacing.Mode}

def environment(result: Result<&1,&1,U32 & String,String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: ""
def parsed(value: Maybe<&2,U32>,fallback: U32) -> U32:
  match value:
    case Some{n}: n
    case None{}: fallback
def number(text: String,fallback: U32) -> U32: parsed(U32.read(text),fallback)
def closes(events: List<Event>) -> Bool:
  match events:
    case []: False{}
    case Close{} <> _: True{}
    case Key{27,True{}} <> _: True{}
    case _ <> rest: closes(rest)
def bounded(progress: Driver.Progress,+ticks: U32) -> Driver.Progress & Bool:
  match progress:
    case Driver.Progress{memory,G.Packet{G.State{world,+run,offers,snapshots,pending}},choices}:
      (Driver.Progress{memory,G.Packet{G.State{world,run,offers,snapshots,pending}},choices},Bool.or(U32.is_le(3,G.run_phase(run)),Bool.and(U32.is_lt(0,ticks),U32.is_le(ticks,G.run_tick(run)))))
    case progress: (progress,False{})
def advanced(ready: Bool,progress: Driver.Progress) -> Driver.Progress:
  match ready:
    case True{}: Driver.step(progress)
    case False{}: progress
def continued(stopped: Bool,ready: Bool,progress: Driver.Progress,last: Nat,started: Nat,ticks: U32,seconds: U32,pacing: Pacing.Mode) -> Maybe<Bot>:
  match stopped:
    case True{}: None{}
    case False{}: Some{Bot{advanced(ready,progress),last,started,ticks,seconds,pacing}}
def timed(+now: Nat,started: Nat,+seconds: U32) -> Bool: Bool.and(U32.is_lt(0,seconds),Nat.is_le(U32.to_nat((seconds * 1000 : U32)),Nat.sub(now,started)))
def update_bounded(+now: Nat,+last: Nat,+started: Nat,ticks: U32,+seconds: U32,+pacing: Pacing.Mode,result: Driver.Progress & Bool) -> Maybe<Bot>:
  (progress,finished) = result
  +ready=Pacing.ready(pacing,now,last)
  continued(Bool.or(finished,timed(now,started,seconds)),ready,progress,Bool.pick(Nat,ready,now,last),started,ticks,seconds,pacing)
def update(+now: Nat,state: Bot) -> Maybe<Bot>:
  match state:
    case Bot{progress,last,started,+ticks,seconds,pacing}: update_bounded(now,last,started,ticks,seconds,pacing,bounded(progress,ticks))
def checked(tick: U32,choices: U32,x: F32,y: F32,result: Maybe<Bot>) -> IO(Maybe<Bot>):
  match result:
    case Some{Bot{Driver.Progress{_,G.Failed{error},_},_,_,_,_,_}}: IO.die(Maybe<Bot>,1,"Native bot game failure: " ++ error)
    case None{}:
      do IO<Maybe<Bot>>:
        IO.print("Native Bend bot completed at tick " ++ U32.show(tick) ++ ", choices " ++ U32.show(choices) ++ ", position " ++ F32.show(x) ++ ", " ++ F32.show(y))
        return None{}
    case result: IO.pure(Maybe<Bot>,result)
def continue_packet(memory: Policy.Memory,+choices: U32,last: Nat,started: Nat,ticks: U32,seconds: U32,pacing: Pacing.Mode,packet: G.Packet) -> IO(Maybe<Bot>):
  match packet:
    case G.Failed{error}: IO.die(Maybe<Bot>,1,"Native bot game failure: " ++ error)
    case G.Packet{G.State{world,+run,offers,snapshots,pending}}:
      do IO<Maybe<Bot>>:
        now : Nat <- IO.now()
        checked(G.run_tick(run),choices,G.run_px(run),G.run_py(run),update(now,Bot{Driver.Progress{memory,G.Packet{G.State{world,run,offers,snapshots,pending}},choices},last,started,ticks,seconds,pacing}))
def continue(state: Bot) -> IO(Maybe<Bot>):
  match state:
    case Bot{Driver.Progress{memory,packet,choices},last,started,ticks,seconds,pacing}: continue_packet(memory,choices,last,started,ticks,seconds,pacing,packet)
def tick_closed(closed: Bool,state: Bot) -> IO(Maybe<Bot>):
  match closed:
    case True{}: IO.pure(Maybe<Bot>,None{})
    case False{}: continue(state)
def tick(events: List<Event>,state: Bot) -> IO(Maybe<Bot>): tick_closed(closes(events),state)
def rendering_run(+run: Model.Run,packet: G.Packet) -> N.Native:
  N.Native{packet,N.set_character(N.set_paused(N.set_screen(N.initial_ui(),1),(Bool.to_u32(Bool.or(U32.is_eq(G.run_phase(run),1),U32.is_eq(G.run_phase(run),2))) * 2 : U32)),G.run_character(run)),P.fresh()}
def rendering_native(packet: G.Packet) -> N.Native:
  match packet:
    case G.Packet{G.State{world,+run,offers,snapshots,pending}}: rendering_run(run,G.Packet{G.State{world,run,offers,snapshots,pending}})
    case packet: N.Native{packet,N.set_screen(N.initial_ui(),1),P.fresh()}
def viewed(memory: Policy.Memory,choices: U32,last: Nat,started: Nat,ticks: U32,seconds: U32,pacing: Pacing.Mode,native: N.Native,image: Image) -> Bot & Image:
  match native:
    case N.Native{game,_,_}: (Bot{Driver.Progress{memory,game,choices},last,started,ticks,seconds,pacing},image)
def image(memory: Policy.Memory,choices: U32,last: Nat,started: Nat,ticks: U32,seconds: U32,pacing: Pacing.Mode,result: N.Native & Image) -> Bot & Image:
  (native,picture) = result
  viewed(memory,choices,last,started,ticks,seconds,pacing,native,picture)
def metrics_native(text: String,native: N.Native) -> N.Native & Image:
  match native:
    case N.Native{G.Packet{G.State{world,+run,+offers,+snapshots,pending}},+ui,profile}:
      (N.Native{G.Packet{G.State{world,run,offers,snapshots,pending}},ui,profile},D.image(D.text(text,12.0,52.0,1.0,15196103,D.rect(0.0,48.0,512.0,16.0,724763,N.gameplay_rows(run,offers,ui,snapshots)))))
    case native: N.view(native)
def mode_label(mode: Pacing.Mode) -> String:
  match mode:
    case Pacing.Realtime{}: "  REALTIME"
    case Pacing.Unlimited{}: "  UNLIMITED"
def view(text: String,state: Bot) -> Bot & Image:
  match state:
    case Bot{Driver.Progress{memory,game,choices},last,started,ticks,seconds,+pacing}: image(memory,choices,last,started,ticks,seconds,pacing,metrics_native(text ++ mode_label(pacing),rendering_native(game)))

type Monitor is Type: Monitor{bot: Bot,metrics: Metrics.State}
def monitor_drawn(metrics: Metrics.State,drawn: Bot & Image) -> Monitor & Image:
  (bot,picture) = drawn
  (Monitor{bot,metrics},picture)
def monitor_view(state: Monitor) -> Monitor & Image:
  match state:
    case Monitor{bot,+metrics}: monitor_drawn(metrics,view(Metrics.label(metrics),bot))
def bot_tick(state: Bot) -> Bot & U32:
  match state:
    case Bot{Driver.Progress{memory,G.Packet{G.State{world,+run,offers,snapshots,pending}},choices},last,started,ticks,seconds,pacing}:
      (Bot{Driver.Progress{memory,G.Packet{G.State{world,run,offers,snapshots,pending}},choices},last,started,ticks,seconds,pacing},G.run_tick(run))
    case state: (state,0)
def monitor_measured(metrics: Metrics.State,result: Bot & U32) -> IO(Maybe<Monitor>):
  (bot,tick) = result
  do IO<Maybe<Monitor>>:
    now : Nat <- IO.now()
    return Some{Monitor{bot,Metrics.sample(now,tick,metrics)}}
def monitor_next(metrics: Metrics.State,result: Maybe<Bot>) -> IO(Maybe<Monitor>):
  match result:
    case None{}: IO.pure(Maybe<Monitor>,None{})
    case Some{bot}: monitor_measured(metrics,bot_tick(bot))
def monitor_tick(events: List<Event>,state: Monitor) -> IO(Maybe<Monitor>):
  match state:
    case Monitor{bot,metrics}:
      do IO<Maybe<Monitor>>:
        next : Maybe<Bot> <- tick(events,bot)
        monitor_next(metrics,next)
def monitor_progress(metrics: Metrics.State,next: Maybe<Bot>) -> Maybe<Monitor>:
  match next:
    case None{}: None{}
    case Some{bot}: Some{Monitor{bot,metrics}}
def monitor_advance(state: Monitor) -> IO(Maybe<Monitor>):
  match state:
    case Monitor{bot,metrics}:
      do IO<Maybe<Monitor>>:
        next : Maybe<Bot> <- continue(bot)
        return monitor_progress(metrics,next)
def presented_closed(closed: Bool,state: Monitor) -> IO(Maybe<Monitor>):
  match closed state:
    case True{} _: IO.pure(Maybe<Monitor>,None{})
    case False{} Monitor{bot,metrics}: monitor_measured(metrics,bot_tick(bot))
def monitor_presented(events: List<Event>,state: Monitor) -> IO(Maybe<Monitor>): presented_closed(closes(events),state)
def run_mode(mode: Pacing.Mode,state: Monitor) -> IO(Unit):
  match mode:
    case Pacing.Realtime{}: App.run(~Monitor,~App{monitor_view,monitor_tick},"Nightfall - Bend Bot",1024,768,state)
    case Pacing.Unlimited{}: WindowLoop.run(~Monitor,~App{monitor_view,monitor_presented},~monitor_advance,"Nightfall - Bend Bot",1024,768,state)
def initial_game(mode: String,seed: U32) -> G.Packet:
  match mode:
    case "advanced": B.advanced_start_seed(seed)
    case _: B.fresh_start_seed(seed)
def main() -> IO(Unit):
  do IO<Unit>:
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BOT_PROFILE")
    seed : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BOT_SEED")
    ticks : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BOT_TICKS")
    seconds : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BOT_SECONDS")
    pacing : Result<&1,&1,U32 & String,String> <- IO.get_env("NIGHTFALL_BOT_PACING")
    +chosen : Pacing.Mode <- IO.pure(Pacing.Mode,Pacing.parse(environment(pacing)))
    +now : Nat <- IO.now()
    run_mode(chosen,Monitor{Bot{Driver.Progress{Policy.initial(),initial_game(environment(mode),number(environment(seed),12345)),0},now,now,number(environment(ticks),0),number(environment(seconds),0),chosen},Metrics.initial()})
