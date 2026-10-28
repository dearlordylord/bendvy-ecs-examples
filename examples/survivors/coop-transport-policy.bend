import Base
import ./coop-connection.bend as C
import ./coop-finish.bend as F
import ./coop-lobby.bend as L

type EndpointRole is Data: HostEndpoint{} GuestEndpoint{}
type DeadlineKind is Data: Handshake{} Drain{} GuestDrain{}
type Reason is Data: NoError{} NotConnected{} ClosedError{} QueueFull{} FrameTooLarge{} Cancelled{} NativeFailure{} IdentifierExhausted{}
type Pending is Data: Pending{request:U32,bytes:U32,confirm:Bool}
type Writer is Data: Writer{operation:U32,connection:U32,pending:Pending}
type Timer is Data: Timer{id:U32,started:Nat,duration:U32,kind:DeadlineKind}
type Phase is Data:
  Dormant{}
  Creating{operation:U32,request:U32,role:EndpointRole}
  Available{}
  Connecting{operation:U32,request:U32,candidate:U32,remaining:List<&2,U32>}
  Accepting{operation:U32,offer:U32}
  Connected{connection:U32,peer:String}
  Closed{}
type State is Data: State{phase:Phase,next:U32,epoch:U32,pending:List<&2,Pending>,writer:Maybe<&2,Writer>,handshake:Maybe<&2,Timer>,drain:Maybe<&2,Timer>,allowIncoming:Bool}
type Signal is Data:
  Begin{request:U32,role:EndpointRole}
  Created{operation:U32,success:Bool}
  Join{request:U32,candidates:List<&2,U32>}
  Incoming{offer:U32}
  Room{terminal:Bool,lobby:L.State,seat:U32}
  ConnectedEvent{operation:U32,connection:U32,peer:String}
  AttemptFailed{operation:U32}
  Send{request:U32,bytes:U32,confirm:Bool}
  Written{operation:U32,connection:U32,success:Bool}
  Received{connection:U32,peer:String,request:U32}
  Departed{connection:U32,peer:String}
  DisconnectRequest{}
  CloseRequest{}
  Arm{kind:DeadlineKind}
  Readiness{state:C.State}
  Deadline{id:U32}
type Effect is Data:
  Create{operation:U32}
  Connect{operation:U32,request:U32,candidate:U32}
  Accept{offer:U32,operation:U32}
  Refuse{offer:U32}
  Write{operation:U32,connection:U32,request:U32,confirm:Bool}
  Disconnect{connection:U32}
  CloseEndpoint{}
  Settle{request:U32,success:Bool,reason:Reason}
  SettleJoin{request:U32,success:Bool,selected:U32,reason:Reason}
  NotifyConnected{peer:String,candidate:U32}
  NotifyDisconnected{peer:String}
  NotifyMessage{request:U32,peer:String}
  NotifyClosed{}
  NotifyTimeout{kind:DeadlineKind}
  Schedule{id:U32,after:U32}
  CancelTimer{id:U32}
type Out is Data: Out{state:State,effects:List<&2,Effect>}

def fresh() -> State: State{Dormant{},0,0,[],None{},None{},None{},False{}}
def max_frame_bytes() -> U32: 1048576
def max_pending_bytes() -> U32: 4194304
def max_pending_messages() -> Nat: 16n
def max_bridge_events() -> U32: 64
def max_bridge_bytes() -> U32: 4194304
def phase(state:State) -> Phase:
  match state:
    case State{phase,_,_,_,_,_,_,+allowIncoming}: phase
def epoch(state:State) -> U32:
  match state:
    case State{_,_,epoch,_,_,_,_,+allowIncoming}: epoch
def connected(state:State) -> Bool:
  match state:
    case State{Connected{_,_},_,_,_,_,_,_,+allowIncoming}: True{}
    case _: False{}
def closed(state:State) -> Bool:
  match state:
    case State{Closed{},_,_,_,_,_,_,+allowIncoming}: True{}
    case _: False{}
def peer(state:State) -> String:
  match state:
    case State{Connected{_,peer},_,_,_,_,_,_,+allowIncoming}: peer
    case _: ""
def pending_size(row:Pending) -> U32:
  match row:
    case Pending{_,bytes,_}: bytes
def rows_bytes(rows:List<&2,Pending>) -> U32:
  match rows:
    case []: 0
    case row <> rest: U32.add(pending_size(row),rows_bytes(rest))
def writer_bytes(writer:Maybe<&2,Writer>) -> U32:
  match writer:
    case None{}: 0
    case Some{Writer{_,_,row}}: pending_size(row)
def pending_bytes(state:State) -> U32:
  match state:
    case State{_,_,_,rows,writer,_,_,+allowIncoming}: U32.add(rows_bytes(rows),writer_bytes(writer))
def writer_count(writer:Maybe<&2,Writer>) -> Nat:
  match writer:
    case None{}: 0n
    case Some{_}: 1n
def pending_count(state:State) -> Nat:
  match state:
    case State{_,_,_,rows,writer,_,_,+allowIncoming}: Nat.add(List.length(&2,Pending,rows),writer_count(writer))
def allocation_available(state:State) -> Bool:
  match state:
    case State{_,next,epoch,_,_,_,_,+allowIncoming}: Bool.and(U32.is_lt(next,4294967295),U32.is_lt(epoch,4294967295))
def append_effects(+out:Out,effects:List<&2,Effect>) -> Out:
  match out:
    case Out{state,old}: Out{state,List.append(&2,Effect,old,effects)}
def prepend_effects(effects:List<&2,Effect>,out:Out) -> Out:
  match out:
    case Out{state,old}: Out{state,List.append(&2,Effect,effects,old)}
def timer_cancel(timer:Maybe<&2,Timer>) -> List<&2,Effect>:
  match timer:
    case None{}: []
    case Some{Timer{id,_,_,_}}: [CancelTimer{id}]
def rejected_rows(rows:List<&2,Pending>,+reason:Reason) -> List<&2,Effect>:
  match rows:
    case []: []
    case Pending{request,_,_} <> rest: Settle{request,False{},reason} <> rejected_rows(rest,reason)
def rejected_writer(writer:Maybe<&2,Writer>,reason:Reason) -> List<&2,Effect>:
  match writer:
    case None{}: []
    case Some{Writer{_,_,Pending{request,_,_}}}: [Settle{request,False{},reason}]
def rejected_attempt(phase:Phase,+reason:Reason) -> List<&2,Effect>:
  match phase:
    case Creating{_,request,_}: [Settle{request,False{},reason}]
    case Connecting{_,request,_,_}: [SettleJoin{request,False{},0,reason}]
    case _: []
def cancelled_work(+state:State,+reason:Reason) -> List<&2,Effect>:
  match state:
    case State{phase,_,_,rows,writer,handshake,drain,+allowIncoming}:
      List.append(&2,Effect,rejected_attempt(phase,reason),List.append(&2,Effect,rejected_rows(rows,reason),List.append(&2,Effect,rejected_writer(writer,reason),List.append(&2,Effect,timer_cancel(handshake),timer_cancel(drain)))))
def close_selected(already:Bool,+state:State,reason:Reason) -> Out:
  match already state:
    case True{} _: Out{state,[]}
    case False{} State{_,next,epoch,_,_,_,_,+allowIncoming}: Out{State{Closed{},next,epoch,[],None{},None{},None{},allowIncoming},List.append(&2,Effect,cancelled_work(state,reason),[CloseEndpoint{},NotifyClosed{}])}
def close(+state:State,reason:Reason) -> Out: close_selected(closed(state),state,reason)
def exhausted(state:State) -> Out: close(state,IdentifierExhausted{})
def host_role(role:EndpointRole) -> Bool:
  match role:
    case HostEndpoint{}: True{}
    case GuestEndpoint{}: False{}
def begin_selected(allowed:Bool,+state:State,+request:U32,+role:EndpointRole) -> Out:
  match allowed state:
    case True{} State{Dormant{},+next,epoch,rows,writer,handshake,drain,+allowIncoming}: Out{State{Creating{U32.add(next,1),request,role},U32.add(next,1),epoch,rows,writer,handshake,drain,host_role(role)},[Create{U32.add(next,1)}]}
    case _ _: Out{state,[Settle{request,False{},ClosedError{}}]}
def ready(state:State) -> Out:
  match state:
    case State{phase,next,epoch,rows,writer,handshake,drain,+allowIncoming}: Out{State{phase,next,epoch,rows,writer,None{},drain,allowIncoming},timer_cancel(handshake)}
def endpoint_ready(role:EndpointRole,+state:State) -> Out:
  match role:
    case HostEndpoint{}: ready(state)
    case GuestEndpoint{}: Out{state,[]}
def created_selected(role:EndpointRole,matching:Bool,+state:State,+success:Bool,+request:U32) -> Out:
  match matching state success:
    case True{} State{_,next,epoch,rows,writer,handshake,drain,+allowIncoming} True{}: append_effects(endpoint_ready(role,State{Available{},next,epoch,rows,writer,handshake,drain,allowIncoming}),[Settle{request,True{},NoError{}}])
    case True{} _ False{}: append_effects(close(state,NativeFailure{}),[])
    case False{} _ True{}: Out{state,[CloseEndpoint{}]}
    case _ _ _: Out{state,[]}
def created_other(+state:State,success:Bool) -> Out:
  match state success:
    case State{Closed{},_,_,_,_,_,_,+allowIncoming} True{}: Out{state,[CloseEndpoint{}]}
    case _ _: Out{state,[]}
def created(+state:State,+operation:U32,success:Bool) -> Out:
  match state:
    case State{Creating{current,+request,role},_,_,_,_,_,_,+allowIncoming}: created_selected(role,U32.is_eq(current,operation),state,success,request)
    case _: created_other(state,success)
def join_candidates(+state:State,+request:U32,candidates:List<&2,U32>) -> Out:
  match state candidates:
    case State{Available{},+next,epoch,rows,writer,handshake,drain,+allowIncoming} +candidate <> remaining: Out{State{Connecting{U32.add(next,1),request,candidate,remaining},U32.add(next,1),epoch,rows,writer,handshake,drain,allowIncoming},[Connect{U32.add(next,1),request,candidate}]}
    case _ _: Out{state,[SettleJoin{request,False{},0,NotConnected{}}]}
def join_bounded(allowed:Bool,+state:State,+request:U32,candidates:List<&2,U32>) -> Out:
  match allowed:
    case True{}: join_candidates(state,request,candidates)
    case False{}: Out{state,[SettleJoin{request,False{},0,QueueFull{}}]}
def join_selected(available:Bool,+state:State,request:U32,+candidates:List<&2,U32>) -> Out:
  match available:
    case True{}: join_bounded(Nat.is_le(List.length(&2,U32,candidates),3n),state,request,candidates)
    case False{}: append_effects(exhausted(state),[SettleJoin{request,False{},0,IdentifierExhausted{}}])
def incoming_allowed(state:State) -> Bool:
  match state:
    case State{_,_,_,_,_,_,_,allowIncoming}: allowIncoming
def incoming_selected(available:Bool,+state:State,+offer:U32) -> Out:
  match available state:
    case True{} State{Available{},+next,epoch,rows,writer,handshake,drain,+allowIncoming}: Out{State{Accepting{U32.add(next,1),offer},U32.add(next,1),epoch,rows,writer,handshake,drain,allowIncoming},[Accept{offer,U32.add(next,1)}]}
    case _ _: Out{state,[Refuse{offer}]}
def attempt_matches(state:State,+operation:U32) -> Bool:
  match state:
    case State{Connecting{current,_,_,_},_,_,_,_,_,_,+allowIncoming}: U32.is_eq(current,operation)
    case State{Accepting{current,_},_,_,_,_,_,_,+allowIncoming}: U32.is_eq(current,operation)
    case _: False{}
def connected_selected(matching:Bool,+state:State,+connection:U32,+peer:String) -> Out:
  match matching state:
    case True{} State{Connecting{_,request,candidate,_},next,+epoch,rows,writer,handshake,drain,+allowIncoming}: Out{State{Connected{connection,peer},next,U32.add(epoch,1),rows,writer,handshake,drain,allowIncoming},[SettleJoin{request,True{},candidate,NoError{}},NotifyConnected{peer,candidate}]}
    case True{} State{Accepting{_,_},next,+epoch,rows,writer,handshake,drain,+allowIncoming}: Out{State{Connected{connection,peer},next,U32.add(epoch,1),rows,writer,handshake,drain,allowIncoming},[NotifyConnected{peer,0}]}
    case _ _: Out{state,[Disconnect{connection}]}
def connected_duplicate(duplicate:Bool,+state:State,+operation:U32,+connection:U32,+peer:String) -> Out:
  match duplicate:
    case True{}: Out{state,[]}
    case False{}: connected_selected(Bool.and(attempt_matches(state,operation),U32.is_eq(operation,connection)),state,connection,peer)
def current_connection(state:State,+connection:U32,+peer:String) -> Bool:
  match state:
    case State{Connected{current,identity},_,_,_,_,_,_,+allowIncoming}: Bool.and(U32.is_eq(current,connection),String.eq(identity,peer))
    case _: False{}
def connected_event(+state:State,+operation:U32,+connection:U32,+peer:String) -> Out: connected_duplicate(current_connection(state,connection,peer),state,operation,connection,peer)
def failed_attempt_selected(matching:Bool,+state:State) -> Out:
  match matching state:
    case True{} State{Connecting{_,+request,_,remaining},next,epoch,rows,writer,handshake,drain,+allowIncoming}: join_selected(allocation_available(state),State{Available{},next,epoch,rows,writer,handshake,drain,allowIncoming},request,remaining)
    case True{} State{Accepting{_,_},next,epoch,rows,writer,handshake,drain,+allowIncoming}: Out{State{Available{},next,epoch,rows,writer,handshake,drain,allowIncoming},[]}
    case _ _: Out{state,[]}
def failed_attempt(+state:State,operation:U32) -> Out: failed_attempt_selected(attempt_matches(state,operation),state)
def can_send(+state:State,+bytes:U32) -> Bool: Bool.and(connected(state),Bool.and(U32.is_le(bytes,max_frame_bytes()),Bool.and(Nat.is_lt(pending_count(state),max_pending_messages()),U32.is_le(bytes,U32.sub(max_pending_bytes(),pending_bytes(state))))))
def send_reason_selected(connected:Bool,bounded:Bool) -> Reason:
  match connected bounded:
    case False{} _: NotConnected{}
    case True{} False{}: FrameTooLarge{}
    case True{} True{}: QueueFull{}
def send_reason(+state:State,bytes:U32) -> Reason: send_reason_selected(connected(state),U32.is_le(bytes,max_frame_bytes()))
def pump_exhausted(+state:State) -> Out:
  match state:
    case State{Connected{_,_},_,_,_ <> _,None{},_,_,+allowIncoming}: exhausted(state)
    case _: Out{state,[]}
def pump_selected(available:Bool,+state:State) -> Out:
  match available state:
    case True{} State{Connected{+connection,peer},+next,epoch,Pending{+request,bytes,+confirm} <> rest,None{},handshake,drain,+allowIncoming}: Out{State{Connected{connection,peer},U32.add(next,1),epoch,rest,Some{Writer{U32.add(next,1),connection,Pending{request,bytes,confirm}}},handshake,drain,allowIncoming},[Write{U32.add(next,1),connection,request,confirm}]}
    case False{} _: pump_exhausted(state)
    case _ _: Out{state,[]}
def pump(+state:State) -> Out:
  match state:
    case State{_,next,_,_,_,_,_,+allowIncoming}: pump_selected(U32.is_lt(next,4294967295),state)
def enqueue_selected(allowed:Bool,+state:State,+request:U32,+bytes:U32,confirm:Bool) -> Out:
  match allowed state:
    case True{} State{phase,next,epoch,rows,writer,handshake,drain,+allowIncoming}: pump(State{phase,next,epoch,List.append(&2,Pending,rows,[Pending{request,bytes,confirm}]),writer,handshake,drain,allowIncoming})
    case _ _: Out{state,[Settle{request,False{},send_reason(state,bytes)}]}
def writer_matches(state:State,+operation:U32,+connection:U32) -> Bool:
  match state:
    case State{Connected{current,_},_,_,_,Some{Writer{writing,owner,_}},_,_,+allowIncoming}: Bool.and(U32.is_eq(current,connection),Bool.and(U32.is_eq(owner,connection),U32.is_eq(writing,operation)))
    case _: False{}
def write_reason(success:Bool) -> Reason:
  match success:
    case True{}: NoError{}
    case False{}: NativeFailure{}
def written_selected(matching:Bool,+state:State,+success:Bool) -> Out:
  match matching state:
    case True{} State{phase,next,epoch,rows,Some{Writer{_,_,Pending{request,_,_}}},handshake,drain,+allowIncoming}: prepend_effects([Settle{request,success,write_reason(success)}],pump(State{phase,next,epoch,rows,None{},handshake,drain,allowIncoming}))
    case _ _: Out{state,[]}
def written(+state:State,operation:U32,connection:U32,success:Bool) -> Out: written_selected(writer_matches(state,operation,connection),state,success)
def authenticated(state:State,+connection:U32,+peer:String) -> Bool:
  match state:
    case State{Connected{current,identity},_,_,_,_,_,_,+allowIncoming}: Bool.and(U32.is_eq(current,connection),String.eq(identity,peer))
    case _: False{}
def received_selected(allowed:Bool,state:State,request:U32,peer:String) -> Out:
  match allowed:
    case True{}: Out{state,[NotifyMessage{request,peer}]}
    case False{}: Out{state,[]}
def disconnected_peer(phase:Phase) -> List<&2,Effect>:
  match phase:
    case Connected{_,peer}: [NotifyDisconnected{peer}]
    case _: []
def disconnect_selected(available:Bool,+state:State) -> Out:
  match available state:
    case False{} _: exhausted(state)
    case True{} State{+phase,next,+epoch,rows,writer,handshake,+drain,+allowIncoming}: Out{State{Available{},next,U32.add(epoch,1),[],None{},None{},drain,allowIncoming},List.append(&2,Effect,cancelled_work(State{phase,next,epoch,rows,writer,handshake,None{},allowIncoming},Cancelled{}),Disconnect{0} <> disconnected_peer(phase))}
def disconnect(+state:State) -> Out:
  match state:
    case State{Closed{},_,_,_,_,_,_,_}: Out{state,[]}
    case State{Dormant{},_,_,_,_,_,_,_}: Out{state,[]}
    case State{Creating{_,_,_},_,_,_,_,_,_,_}: close(state,Cancelled{})
    case State{Available{},_,_,_,_,None{},_,_}: Out{state,[]}
    case State{_,_,epoch,_,_,_,_,_}: disconnect_selected(U32.is_lt(epoch,4294967295),state)
def departed_selected(matching:Bool,+state:State) -> Out:
  match matching:
    case True{}: disconnect(state)
    case False{}: Out{state,[]}
def duration(kind:DeadlineKind) -> U32:
  match kind:
    case Handshake{}: 45000
    case Drain{}: F.drain_milliseconds()
    case GuestDrain{}: U32.add(F.drain_milliseconds(),5000)
def arm_selected(allowed:Bool,+state:State,+kind:DeadlineKind,+now:Nat) -> Out:
  match allowed state kind:
    case True{} State{phase,+next,epoch,rows,writer,handshake,drain,+allowIncoming} Handshake{}: Out{State{phase,U32.add(next,1),epoch,rows,writer,Some{Timer{U32.add(next,1),now,duration(kind),kind}},drain,allowIncoming},List.append(&2,Effect,timer_cancel(handshake),[Schedule{U32.add(next,1),duration(kind)}])}
    case True{} State{phase,+next,epoch,rows,writer,handshake,drain,+allowIncoming} _: Out{State{phase,U32.add(next,1),epoch,rows,writer,handshake,Some{Timer{U32.add(next,1),now,duration(kind),kind}},allowIncoming},List.append(&2,Effect,timer_cancel(drain),[Schedule{U32.add(next,1),duration(kind)}])}
    case _ _ _: Out{state,[]}
def operation_available(state:State) -> Bool:
  match state:
    case State{_,next,_,_,_,_,_,_}: U32.is_lt(next,4294967295)
def arm(+state:State,kind:DeadlineKind,now:Nat) -> Out: arm_selected(Bool.and(Bool.not(closed(state)),operation_available(state)),state,kind,now)
def readiness_selected(waiting:Bool,+state:State,+now:Nat) -> Out:
  match waiting state:
    case True{} State{_,_,_,_,_,None{},_,+allowIncoming}: arm(state,Handshake{},now)
    case True{} _: Out{state,[]}
    case False{} _: ready(state)
def timer_matches(timer:Maybe<&2,Timer>,+id:U32) -> Bool:
  match timer:
    case Some{Timer{current,_,_,_}}: U32.is_eq(current,id)
    case None{}: False{}
def timer_elapsed(+now:Nat,+started:Nat) -> Nat: Nat.sub(now,started)
def expire_selected(due:Bool,+state:State,+timer:Timer,+now:Nat) -> Out:
  match due state timer:
    case True{} State{Creating{_,_,_},_,_,_,_,_,_,+allowIncoming} Timer{_,_,_,Handshake{}}: close(state,NativeFailure{})
    case True{} State{Connecting{_,_,_,_},_,_,_,_,_,_,+allowIncoming} Timer{_,_,_,Handshake{}}: append_effects(disconnect(state),[NotifyTimeout{Handshake{}}])
    case True{} State{Accepting{_,_},_,_,_,_,_,_,+allowIncoming} Timer{_,_,_,Handshake{}}: append_effects(disconnect(state),[NotifyTimeout{Handshake{}}])
    case True{} State{phase,next,epoch,rows,writer,_,drain,+allowIncoming} Timer{_,_,_,Handshake{}}: Out{State{phase,next,epoch,rows,writer,None{},drain,allowIncoming},[NotifyTimeout{Handshake{}}]}
    case True{} State{phase,next,epoch,rows,writer,handshake,_,+allowIncoming} Timer{_,_,_,kind}: Out{State{phase,next,epoch,rows,writer,handshake,None{},allowIncoming},[NotifyTimeout{kind}]}
    case False{} _ Timer{id,started,duration,_}: Out{state,[Schedule{id,U32.from_nat(Nat.sub(U32.to_nat(duration),timer_elapsed(now,started)))}]}
def expire_timer(+state:State,+timer:Timer,+now:Nat) -> Out:
  match timer:
    case Timer{_,started,duration,_}: expire_selected(Nat.is_le(U32.to_nat(duration),timer_elapsed(now,started)),state,timer,now)
def deadline_selected(handshakeMatches:Bool,drainMatches:Bool,+state:State,+now:Nat) -> Out:
  match handshakeMatches drainMatches state:
    case True{} _ State{_,_,_,_,_,Some{timer},_,+allowIncoming}: expire_timer(state,timer,now)
    case _ True{} State{_,_,_,_,_,_,Some{timer},+allowIncoming}: expire_timer(state,timer,now)
    case _ _ _: Out{state,[]}
def deadline(+state:State,+id:U32,now:Nat) -> Out:
  match state:
    case State{_,_,_,_,_,handshake,drain,+allowIncoming}: deadline_selected(timer_matches(handshake,id),timer_matches(drain,id),state,now)
def available(state:State) -> Bool:
  match state:
    case State{Available{},_,_,_,_,_,_,+allowIncoming}: True{}
    case _: False{}
def timed_selected(timed:Bool,+out:Out,+now:Nat) -> Out:
  match timed out:
    case True{} Out{state,effects}: append_effects(arm(state,Handshake{},now),effects)
    case False{} _: out
def join_timed(+out:Out,+now:Nat) -> Out:
  match out:
    case Out{State{Connecting{_,_,_,_},_,_,_,_,None{},_,_},_}: timed_selected(True{},out,now)
    case _: out
def room_selected(allowed:Bool,+state:State) -> Out:
  match allowed state:
    case False{} State{Accepting{_,_},next,epoch,rows,writer,handshake,drain,_}: disconnect(State{phase(state),next,epoch,rows,writer,handshake,drain,False{}})
    case _ State{phase,next,epoch,rows,writer,handshake,drain,_}: Out{State{phase,next,epoch,rows,writer,handshake,drain,allowed},[]}
def room(state:State,terminal:Bool,lobby:L.State,seat:U32) -> Out: room_selected(Bool.and(Bool.not(terminal),L.admit(lobby,seat)),state)
def step(+state:State,event:Signal,+now:Nat) -> Out:
  match event:
    case Begin{request,role}: timed_selected(True{},begin_selected(allocation_available(state),state,request,role),now)
    case Created{operation,success}: created(state,operation,success)
    case Join{request,candidates}: join_timed(join_selected(allocation_available(state),state,request,candidates),now)
    case Room{terminal,lobby,seat}: room(state,terminal,lobby,seat)
    case Incoming{offer}: incoming_selected(Bool.and(allocation_available(state),incoming_allowed(state)),state,offer)
    case ConnectedEvent{+operation,+connection,peer}: timed_selected(Bool.and(attempt_matches(state,operation),U32.is_eq(operation,connection)),connected_event(state,operation,connection,peer),now)
    case AttemptFailed{operation}: failed_attempt(state,operation)
    case Send{+request,+bytes,confirm}: enqueue_selected(can_send(state,bytes),state,request,bytes,confirm)
    case Written{operation,connection,success}: written(state,operation,connection,success)
    case Received{+connection,+peer,request}: received_selected(authenticated(state,connection,peer),state,request,peer)
    case Departed{connection,peer}: departed_selected(authenticated(state,connection,peer),state)
    case DisconnectRequest{}: disconnect(state)
    case CloseRequest{}: close(state,Cancelled{})
    case Arm{kind}: arm(state,kind,now)
    case Readiness{gate}: readiness_selected(C.waiting(gate),state,now)
    case Deadline{id}: deadline(state,id,now)
