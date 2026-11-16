# Connection readiness is separate from transport connectivity and game state.
# IO supplies authenticated per-connection events and performs the returned action.
import Base
import ./coop-protocol.bend as Protocol

type Role is Data: Host{} Guest{}
type Reason is Data:
  VersionMismatch{}
  ProtocolError{}
  HandshakeTimeout{}
  SetupFailed{}
  SnapshotFailed{}
  TransportFailed{}
  RuntimeFailed{}
  PresentationFailed{}
type State is Data:
  Idle{role:Role,epoch:U32}
  HostHello{epoch:U32}
  HostSetup{epoch:U32}
  HostPreparing{epoch:U32}
  HostReady{epoch:U32,observation:U32}
  HostRunning{epoch:U32}
  GuestHello{epoch:U32}
  GuestSnapshot{epoch:U32,token:U32}
  GuestStart{epoch:U32,token:U32,observation:U32}
  GuestRunning{epoch:U32,token:U32}
  Suspended{role:Role,epoch:U32}
  Failed{role:Role,epoch:U32,reason:Reason}
type Signal is Data:
  Hello{version:U32,token:U32}
  Frame{version:U32,token:U32,observation:U32}
  HelloAck{version:U32,token:U32}
  Setup{}
  Prepared{observation:U32}
  SnapshotSeen{token:U32,observation:U32}
  ReadyAck{token:U32,observation:U32}
  Started{token:U32}
  Timeout{}
  ConnectionLost{}
  Reject{reason:Reason}
type Action is Data:
  Nothing{}
  SendHello{version:U32,token:U32}
  HelloAckAndSetup{version:U32,token:U32}
  PrepareWorld{}
  PublishInitial{token:U32,observation:U32}
  SendReadyAck{token:U32,observation:U32}
  StartAndConfirm{token:U32}
  GuestReady{}
  PresentSnapshot{token:U32,observation:U32}
  Suspend{}
  CloseConnection{reason:Reason}
type Out is Data: Out{state:State,action:Action}

def protocol_version() -> U32: 1
def fresh(role:Role) -> State: Idle{role,0}
def role(state:State) -> Role:
  match state:
    case Idle{role,_}: role
    case HostHello{_}: Host{}
    case HostSetup{_}: Host{}
    case HostPreparing{_}: Host{}
    case HostReady{_,_}: Host{}
    case HostRunning{_}: Host{}
    case GuestHello{_}: Guest{}
    case GuestSnapshot{_,_}: Guest{}
    case GuestStart{_,_,_}: Guest{}
    case GuestRunning{_,_}: Guest{}
    case Suspended{role,_}: role
    case Failed{role,_,_}: role
def epoch(state:State) -> U32:
  match state:
    case Idle{_,epoch}: epoch
    case HostHello{epoch}: epoch
    case HostSetup{epoch}: epoch
    case HostPreparing{epoch}: epoch
    case HostReady{epoch,_}: epoch
    case HostRunning{epoch}: epoch
    case GuestHello{epoch}: epoch
    case GuestSnapshot{epoch,_}: epoch
    case GuestStart{epoch,_,_}: epoch
    case GuestRunning{epoch,_}: epoch
    case Suspended{_,epoch}: epoch
    case Failed{_,epoch,_}: epoch
def reason(state:State) -> Maybe<&2,Reason>:
  match state:
    case Failed{_,_,reason}: Some{reason}
    case _: None{}
def running(state:State) -> Bool:
  match state:
    case HostRunning{_}: True{}
    case GuestRunning{_,_}: True{}
    case _: False{}
def allows_setup(state:State) -> Bool:
  match state:
    case HostSetup{_}: True{}
    case _: False{}
def waiting(state:State) -> Bool:
  match state:
    case Idle{_,_}: True{}
    case HostHello{_}: True{}
    case HostSetup{_}: True{}
    case HostPreparing{_}: True{}
    case HostReady{_,_}: True{}
    case GuestHello{_}: True{}
    case GuestSnapshot{_,_}: True{}
    case GuestStart{_,_,_}: True{}
    case _: False{}
def begin(role:Role,+epoch:U32) -> Out:
  match role:
    case Host{}: Out{HostHello{epoch},SendHello{protocol_version(),epoch}}
    case Guest{}: Out{GuestHello{epoch},Nothing{}}
def unchanged(state:State) -> Out: Out{state,Nothing{}}
def reconnect_selected(newer:Bool,+state:State,newEpoch:U32) -> Out:
  match newer:
    case True{}: begin(role(state),newEpoch)
    case False{}: unchanged(state)
def reconnect(+state:State,+newEpoch:U32) -> Out:
  reconnect_selected(U32.is_gt(newEpoch,epoch(state)),state,newEpoch)
def failed(+state:State,+reason:Reason) -> Out: Out{Failed{role(state),epoch(state),reason},CloseConnection{reason}}
def timeout_selected(expired:Bool,state:State) -> Out:
  match expired:
    case True{}: failed(state,HandshakeTimeout{})
    case False{}: unchanged(state)
def guest_hello_selected(compatible:Bool,epoch:U32,+token:U32) -> Out:
  match compatible:
    case True{}: Out{GuestSnapshot{epoch,token},HelloAckAndSetup{protocol_version(),token}}
    case False{}: failed(GuestHello{epoch},VersionMismatch{})
def host_ack_token(matching:Bool,epoch:U32) -> Out:
  match matching:
    case True{}: Out{HostSetup{epoch},Nothing{}}
    case False{}: failed(HostHello{epoch},ProtocolError{})
def host_hello_selected(compatible:Bool,+epoch:U32,token:U32) -> Out:
  match compatible:
    case True{}: host_ack_token(U32.is_eq(epoch,token),epoch)
    case False{}: failed(HostHello{epoch},VersionMismatch{})
def snapshot_selected(matching:Bool,epoch:U32,+token:U32,+observation:U32) -> Out:
  match matching:
    case True{}: Out{GuestStart{epoch,token,observation},SendReadyAck{token,observation}}
    case False{}: failed(GuestSnapshot{epoch,token},ProtocolError{})
def ready_selected(matching:Bool,+epoch:U32,observation:U32) -> Out:
  match matching:
    case True{}: Out{HostRunning{epoch},StartAndConfirm{epoch}}
    case False{}: unchanged(HostReady{epoch,observation})
def started_selected(matching:Bool,epoch:U32,token:U32,observation:U32) -> Out:
  match matching:
    case True{}: Out{GuestRunning{epoch,token},GuestReady{}}
    case False{}: unchanged(GuestStart{epoch,token,observation})
def frame_token(matching:Bool,state:State,token:U32,observation:U32) -> Out:
  match matching:
    case True{}: Out{state,PresentSnapshot{token,observation}}
    case False{}: failed(state,ProtocolError{})
def frame_version(compatible:Bool,state:State,expected:U32,+token:U32,observation:U32) -> Out:
  match compatible:
    case True{}: frame_token(U32.is_eq(expected,token),state,token,observation)
    case False{}: failed(state,VersionMismatch{})
def early_frame(compatible:Bool,state:State) -> Out:
  match compatible:
    case True{}: failed(state,ProtocolError{})
    case False{}: failed(state,VersionMismatch{})
def transition(+state:State,event:Signal) -> Out:
  match state event:
    case Failed{role,epoch,reason} _: unchanged(Failed{role,epoch,reason})
    case state ConnectionLost{}: Out{Suspended{role(state),epoch(state)},Suspend{}}
    case state Reject{reason}: failed(state,reason)
    case state Timeout{}: timeout_selected(waiting(state),state)
    case GuestHello{epoch} Hello{version,token}: guest_hello_selected(U32.is_eq(version,protocol_version()),epoch,token)
    case HostHello{epoch} HelloAck{version,token}: host_hello_selected(U32.is_eq(version,protocol_version()),epoch,token)
    case HostHello{epoch} Setup{}: failed(HostHello{epoch},VersionMismatch{})
    case GuestHello{epoch} Frame{version,_,_}: early_frame(U32.is_eq(version,protocol_version()),GuestHello{epoch})
    case GuestSnapshot{epoch,+expected} Frame{version,token,observation}: frame_version(U32.is_eq(version,protocol_version()),GuestSnapshot{epoch,expected},expected,token,observation)
    case GuestStart{epoch,+expected,prior} Frame{version,token,observation}: frame_version(U32.is_eq(version,protocol_version()),GuestStart{epoch,expected,prior},expected,token,observation)
    case GuestRunning{epoch,+expected} Frame{version,token,observation}: frame_version(U32.is_eq(version,protocol_version()),GuestRunning{epoch,expected},expected,token,observation)
    case HostSetup{epoch} Setup{}: Out{HostPreparing{epoch},PrepareWorld{}}
    case HostPreparing{+epoch} Prepared{+observation}: Out{HostReady{epoch,observation},PublishInitial{epoch,observation}}
    case GuestSnapshot{epoch,+token} SnapshotSeen{received,observation}: snapshot_selected(U32.is_eq(received,token),epoch,token,observation)
    case HostReady{+epoch,+observation} ReadyAck{token,received}: ready_selected(Bool.and(U32.is_eq(token,epoch),U32.is_eq(received,observation)),epoch,observation)
    case GuestStart{epoch,+token,observation} Started{received}: started_selected(U32.is_eq(received,token),epoch,token,observation)
    case state _: unchanged(state)
def step_selected(current:Bool,state:State,event:Signal) -> Out:
  match current:
    case False{}: unchanged(state)
    case True{}: transition(state,event)
def step(+state:State,eventEpoch:U32,event:Signal) -> Out:
  step_selected(U32.is_eq(eventEpoch,epoch(state)),state,event)
def state(output:Out) -> State:
  match output:
    case Out{state,_}: state
def action(output:Out) -> Action:
  match output:
    case Out{_,action}: action

# These controls are the only peer-authored handshake events. Local scheduling,
# worker completion, snapshot application and timeout events cannot be decoded.
def reason_code(reason:Reason) -> U32:
  match reason:
    case VersionMismatch{}: 1
    case ProtocolError{}: 2
    case HandshakeTimeout{}: 3
    case SetupFailed{}: 4
    case SnapshotFailed{}: 5
    case TransportFailed{}: 6
    case RuntimeFailed{}: 7
    case PresentationFailed{}: 8
def decode_reason(code:U32) -> Maybe<&2,Reason>:
  match code:
    case 1: Some{VersionMismatch{}}
    case 2: Some{ProtocolError{}}
    case 3: Some{HandshakeTimeout{}}
    case 4: Some{SetupFailed{}}
    case 5: Some{SnapshotFailed{}}
    case 6: Some{TransportFailed{}}
    case 7: Some{RuntimeFailed{}}
    case 8: Some{PresentationFailed{}}
    case _: None{}
def reason_text(reason:Reason) -> String:
  match reason:
    case VersionMismatch{}: "The host and guest use different game versions. Reload both pages and create a new invitation."
    case ProtocolError{}: "The party handshake was invalid. Rejoin using the invitation."
    case HandshakeTimeout{}: "The party did not become ready in time. Keep the host tab open, then join again."
    case SetupFailed{}: "The host could not prepare your survivor. Rejoin using the invitation."
    case SnapshotFailed{}: "The initial game state could not be applied. Reload and rejoin the party."
    case TransportFailed{}: "The connection failed. Check that the host still has the party open, then join again."
    case RuntimeFailed{}: "The host simulation failed. Close this party and create a new invitation."
    case PresentationFailed{}: "A game view failed. Copy the error details, then reload and rejoin."
def encode_action(action:Action) -> String:
  match action:
    case SendHello{version,token}: "BSC-HS1|H|" ++ U32.show(version) ++ "|" ++ U32.show(token)
    case HelloAckAndSetup{version,token}: "BSC-HS1|A|" ++ U32.show(version) ++ "|" ++ U32.show(token)
    case SendReadyAck{token,observation}: "BSC-HS1|R|" ++ U32.show(token) ++ "|" ++ U32.show(observation)
    case StartAndConfirm{token}: "BSC-HS1|S|" ++ U32.show(token)
    case CloseConnection{reason}: "BSC-HS1|E|" ++ U32.show(reason_code(reason))
    case _: ""
def decode_fields(fields:List<String>) -> Maybe<&2,Signal>:
  match fields:
    case ["BSC-HS1","H",version,token]:
      do Maybe<&2,Signal>:
        v : U32 <- Protocol.number(version)
        t : U32 <- Protocol.number(token)
        return Hello{v,t}
    case ["BSC-HS1","A",version,token]:
      do Maybe<&2,Signal>:
        v : U32 <- Protocol.number(version)
        t : U32 <- Protocol.number(token)
        return HelloAck{v,t}
    case ["BSC-HS1","R",token,observation]:
      do Maybe<&2,Signal>:
        t : U32 <- Protocol.number(token)
        o : U32 <- Protocol.number(observation)
        return ReadyAck{t,o}
    case ["BSC-HS1","S",token]:
      do Maybe<&2,Signal>:
        t : U32 <- Protocol.number(token)
        return Started{t}
    case ["BSC-HS1","E",reason]:
      do Maybe<&2,Signal>:
        code : U32 <- Protocol.number(reason)
        r : Reason <- decode_reason(code)
        return Reject{r}
    case _: None{}
def decode_bounded(allowed:Bool,text:String) -> Maybe<&2,Signal>:
  match allowed:
    case True{}: decode_fields(Protocol.fields(text,""))
    case False{}: None{}
def decode(+text:String) -> Maybe<&2,Signal>:
  decode_bounded(Nat.is_le(String.length(text),160n),text)
