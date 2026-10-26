import Base

type Identity is Data: Identity{session:Nat,run:Nat,request:Nat,generation:Nat,decision:Nat,phase:U32}
type Mode is Data:
  Stopped{}
  Playing{}
  Advice{count:U32,fallback:U32,recommendation:U32,received:Bool}
  Dwell{count:U32,index:U32}
  Committed{}
  BetweenRuns{}
type State is Data: State{identity:Identity,mode:Mode,paused:Bool,lastAt:Nat,elapsed:Nat,adviceMs:Nat,dwellMs:Nat,betweenMs:Nat}
type Effect is Data:
  Idle{}
  Commit{index:U32}
  NextRun{}
type Out is Data: Out{state:State,effect:Effect,accepted:Bool}
type Input is Data:
  Start{session:Nat,run:Nat,generation:Nat,now:Nat}
  Stop{}
  Pause{now:Nat}
  Resume{now:Nat}
  Offers{decision:Nat,phase:U32,count:U32,fallback:U32,now:Nat}
  Reply{identity:Identity,index:U32,now:Nat}
  Frame{now:Nat}
  Activate{generation:Nat}
  Played{}
  Ended{now:Nat}
  Invalidate{}
  Request{decision:Nat,phase:U32,now:Nat}
  MovementReply{identity:Identity,index:U32,count:U32,now:Nat}

def initial_id() -> Identity: Identity{0n,0n,0n,0n,0n,0}
def fresh(adviceMs:Nat,dwellMs:Nat,betweenMs:Nat) -> State: State{initial_id(),Stopped{},False{},0n,0n,adviceMs,dwellMs,betweenMs}
def outcome(state:State) -> Out: Out{state,Idle{},False{}}
def new_request(identity:Identity) -> Identity:
  match identity:
    case Identity{session,run,request,generation,decision,phase}: Identity{session,run,Nat.add(request,1n),generation,decision,phase}
def same_id(a:Identity,b:Identity) -> Bool:
  match a b:
    case Identity{s,r,q,g,d,p} Identity{t,u,v,h,e,k}: Bool.and(Nat.is_eq(s,t),Bool.and(Nat.is_eq(r,u),Bool.and(Nat.is_eq(q,v),Bool.and(Nat.is_eq(g,h),Bool.and(Nat.is_eq(d,e),U32.is_eq(p,k))))))
def latest(+now:Nat,+lastAt:Nat) -> Nat: Bool.pick(Nat,Nat.is_ge(now,lastAt),now,lastAt)
def elapsed_at(+now:Nat,+lastAt:Nat) -> Nat: Nat.sub(latest(now,lastAt),lastAt)
def elapsed_when(paused:Bool,elapsed:Nat,now:Nat,lastAt:Nat) -> Nat:
  match paused:
    case True{}: elapsed
    case False{}: Nat.add(elapsed,elapsed_at(now,lastAt))
def clock(state:State,+now:Nat) -> State:
  match state:
    case State{id,mode,+paused,+lastAt,elapsed,a,d,b}: State{id,mode,paused,latest(now,lastAt),elapsed_when(paused,elapsed,now,lastAt),a,d,b}
def moving(mode:Mode) -> Bool:
  match mode:
    case Playing{}: True{}
    case _: False{}
def can_move(state:State) -> Bool:
  match state:
    case State{_,mode,paused,_,_,_,_,_}: Bool.and(Bool.not(paused),moving(mode))
def start(state:State,session:Nat,run:Nat,generation:Nat,now:Nat) -> Out:
  match state:
    case State{_,_,_,_,_,a,d,b}: Out{State{Identity{session,run,0n,generation,0n,0},Playing{},False{},now,0n,a,d,b},Idle{},True{}}
def stop(state:State) -> Out:
  match state:
    case State{id,_,_,last,_,a,d,b}: Out{State{new_request(id),Stopped{},False{},last,0n,a,d,b},Idle{},True{}}
def pause_clocked(state:State) -> Out:
  match state:
    case State{id,mode,_,last,elapsed,a,d,b}: Out{State{new_request(id),mode,True{},last,elapsed,a,d,b},Idle{},True{}}
def resume(state:State,+now:Nat) -> Out:
  match state:
    case State{id,mode,_,last,elapsed,a,d,b}: Out{State{new_request(id),mode,False{},latest(now,last),elapsed,a,d,b},Idle{},True{}}
def valid_fallback(+count:U32,+fallback:U32) -> U32: Bool.pick(U32,U32.is_lt(fallback,count),fallback,0)
def begin_offers(state:State,decision:Nat,phase:U32,+count:U32,+fallback:U32,now:Nat) -> Out:
  match state:
    case State{Identity{s,r,q,g,_,_},_,paused,_,_,a,d,b}: Out{State{Identity{s,r,Nat.add(q,1n),g,decision,phase},Advice{count,valid_fallback(count,fallback),valid_fallback(count,fallback),False{}},paused,now,0n,a,d,b},Idle{},True{}}
def offers_decided(allowed:Bool,state:State,decision:Nat,phase:U32,count:U32,fallback:U32,now:Nat) -> Out:
  match allowed:
    case True{}: begin_offers(state,decision,phase,count,fallback,now)
    case False{}: outcome(state)
def offer_mode(mode:Mode) -> Bool:
  match mode:
    case Stopped{}: False{}
    case BetweenRuns{}: False{}
    case _: True{}
def offers(+state:State,+decision:Nat,+phase:U32,+count:U32,fallback:U32,now:Nat) -> Out:
  match state:
    case State{Identity{_,_,_,_,oldDecision,_},mode,_,_,_,_,_,_}: offers_decided(Bool.and(offer_mode(mode),Bool.and(Nat.is_gt(decision,oldDecision),Bool.and(U32.is_gt(count,0),Bool.or(U32.is_eq(phase,1),U32.is_eq(phase,2))))),state,decision,phase,count,fallback,now)
def reply_allowed(+expected:Identity,claimed:Identity,index:U32,count:U32,paused:Bool,elapsed:Nat,cutoff:Nat) -> Bool: Bool.and(Bool.not(paused),Bool.and(same_id(expected,claimed),Bool.and(U32.is_lt(index,count),Nat.is_lt(elapsed,cutoff))))
def reply_decided(allowed:Bool,state:State,index:U32) -> Out:
  match allowed state:
    case True{} State{id,Advice{count,fallback,_,_},paused,last,elapsed,a,d,b}: Out{State{id,Advice{count,fallback,index,True{}},paused,last,elapsed,a,d,b},Idle{},True{}}
    case _ state: outcome(state)
def reply(+state:State,claimed:Identity,+index:U32) -> Out:
  match state:
    case State{expected,Advice{count,_,_,_},paused,_,elapsed,a,_,_}: reply_decided(reply_allowed(expected,claimed,index,count,paused,elapsed,a),state,index)
    case _: outcome(state)
def freeze_decided(due:Bool,state:State) -> Out:
  match due state:
    case True{} State{id,Advice{count,_,index,_},paused,last,_,a,d,b}: Out{State{id,Dwell{count,index},paused,last,0n,a,d,b},Idle{},True{}}
    case _ state: outcome(state)
def commit_decided(due:Bool,state:State) -> Out:
  match due state:
    case True{} State{id,Dwell{count,+index},paused,last,elapsed,a,d,b}: Out{State{new_request(id),Committed{},paused,last,elapsed,a,d,b},Commit{index},True{}}
    case _ state: outcome(state)
def next_decided(due:Bool,state:State) -> Out:
  match due state:
    case True{} State{id,BetweenRuns{},paused,last,_,a,d,b}: Out{State{new_request(id),Stopped{},paused,last,0n,a,d,b},NextRun{},True{}}
    case _ state: outcome(state)
def frame(+state:State) -> Out:
  match state:
    case State{_,_,True{},_,_,_,_,_}: outcome(state)
    case State{_,Advice{_,_,_,_},False{},_,elapsed,a,_,_}: freeze_decided(Nat.is_ge(elapsed,a),state)
    case State{_,Dwell{count,index},False{},_,elapsed,_,d,_}: commit_decided(Bool.and(U32.is_lt(index,count),Nat.is_ge(elapsed,d)),state)
    case State{_,BetweenRuns{},False{},_,elapsed,_,_,b}: next_decided(Nat.is_ge(elapsed,b),state)
    case _: outcome(state)
def activation_mode(mode:Mode) -> Bool:
  match mode:
    case Dwell{_,_}: False{}
    case Stopped{}: False{}
    case Committed{}: False{}
    case _: True{}
def activated(state:State,generation:Nat) -> Out:
  match state:
    case State{Identity{s,r,q,_,decision,phase},mode,paused,last,elapsed,a,d,b}: Out{State{Identity{s,r,Nat.add(q,1n),generation,decision,phase},mode,paused,last,elapsed,a,d,b},Idle{},True{}}
def activate_decided(allowed:Bool,state:State,generation:Nat) -> Out:
  match allowed:
    case True{}: activated(state,generation)
    case False{}: outcome(state)
def activate(+state:State,generation:Nat) -> Out:
  match state:
    case State{_,mode,paused,_,_,_,_,_}: activate_decided(Bool.and(Bool.not(paused),activation_mode(mode)),state,generation)
def played(state:State) -> Out:
  match state:
    case State{id,Committed{},paused,last,_,a,d,b}: Out{State{new_request(id),Playing{},paused,last,0n,a,d,b},Idle{},True{}}
    case state: outcome(state)
def ending_mode(mode:Mode) -> Bool:
  match mode:
    case Stopped{}: False{}
    case BetweenRuns{}: False{}
    case _: True{}
def end_started(state:State,now:Nat) -> Out:
  match state:
    case State{id,_,paused,_,_,a,d,b}: Out{State{new_request(id),BetweenRuns{},paused,now,0n,a,d,b},Idle{},True{}}
def end_decided(allowed:Bool,state:State,now:Nat) -> Out:
  match allowed:
    case True{}: end_started(state,now)
    case False{}: outcome(state)
def ended(+state:State,now:Nat) -> Out:
  match state:
    case State{_,mode,_,_,_,_,_,_}: end_decided(ending_mode(mode),state,now)
def invalidate(state:State) -> Out:
  match state:
    case State{id,mode,paused,last,elapsed,a,d,b}: Out{State{new_request(id),mode,paused,last,elapsed,a,d,b},Idle{},True{}}
def request(state:State,decision:Nat,phase:U32,now:Nat) -> Out:
  match state:
    case State{Identity{s,r,q,g,_,_},Playing{},False{},_,_,a,d,b}: Out{State{Identity{s,r,Nat.add(q,1n),g,decision,phase},Playing{},False{},now,0n,a,d,b},Idle{},True{}}
    case state: outcome(state)
def identity_generation(identity:Identity) -> Nat:
  match identity:
    case Identity{_,_,_,generation,_,_}: generation
def movement_reply(+state:State,claimed:Identity,+index:U32,count:U32) -> Out:
  match state:
    case State{expected,Playing{},paused,_,elapsed,a,_,_}: activate_decided(reply_allowed(expected,claimed,index,count,paused,elapsed,a),state,identity_generation(expected))
    case _: outcome(state)
def step(state:State,event:Input) -> Out:
  match event:
    case Start{session,run,generation,now}: start(state,session,run,generation,now)
    case Stop{}: stop(state)
    case Pause{now}: pause_clocked(clock(state,now))
    case Resume{now}: resume(state,now)
    case Offers{decision,phase,count,fallback,now}: offers(state,decision,phase,count,fallback,now)
    case Reply{id,index,now}: reply(clock(state,now),id,index)
    case Frame{now}: frame(clock(state,now))
    case Activate{generation}: activate(state,generation)
    case Played{}: played(state)
    case Ended{now}: ended(state,now)
    case Invalidate{}: invalidate(state)
    case Request{decision,phase,now}: request(state,decision,phase,now)
    case MovementReply{id,index,count,now}: movement_reply(clock(state,now),id,index,count)
