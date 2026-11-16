import Base
import ./coop-connection.bend as C
import ./coop-connection-LAWS.bend as L

def guest_hello_out(+flag:Bool,+epoch:U32,+token:U32) -> {C.guest_hello_selected(flag,epoch,token) == Bool.pick(C.Out,flag,C.Out{C.GuestSnapshot{epoch,token},C.HelloAckAndSetup{1,token}},C.Out{C.Failed{C.Guest{},epoch,C.VersionMismatch{}},C.CloseConnection{C.VersionMismatch{}}}) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def host_token_out(+flag:Bool,+epoch:U32) -> {C.host_ack_token(flag,epoch) == Bool.pick(C.Out,flag,C.Out{C.HostSetup{epoch},C.Nothing{}},C.Out{C.Failed{C.Host{},epoch,C.ProtocolError{}},C.CloseConnection{C.ProtocolError{}}}) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def snapshot_out(+flag:Bool,+epoch:U32,+token:U32,+observation:U32) -> {C.snapshot_selected(flag,epoch,token,observation) == Bool.pick(C.Out,flag,C.Out{C.GuestStart{epoch,token,observation},C.SendReadyAck{token,observation}},C.Out{C.Failed{C.Guest{},epoch,C.ProtocolError{}},C.CloseConnection{C.ProtocolError{}}}) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def ready_out(+flag:Bool,+epoch:U32,+observation:U32) -> {C.ready_selected(flag,epoch,observation) == Bool.pick(C.Out,flag,C.Out{C.HostRunning{epoch},C.StartAndConfirm{epoch}},C.Out{C.HostReady{epoch,observation},C.Nothing{}}) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def started_out(+flag:Bool,+epoch:U32,+token:U32,+observation:U32) -> {C.started_selected(flag,epoch,token,observation) == Bool.pick(C.Out,flag,C.Out{C.GuestRunning{epoch,token},C.GuestReady{}},C.Out{C.GuestStart{epoch,token,observation},C.Nothing{}}) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def frame_token_out(+flag:Bool,+state:C.State,+token:U32,+observation:U32) -> {C.frame_token(flag,state,token,observation) == Bool.pick(C.Out,flag,C.Out{state,C.PresentSnapshot{token,observation}},C.failed(state,C.ProtocolError{})) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def host_hello_out(+flag:Bool,+epoch:U32,+token:U32) -> {C.host_hello_selected(flag,epoch,token) == Bool.pick(C.Out,flag,Bool.pick(C.Out,U32.is_eq(epoch,token),C.Out{C.HostSetup{epoch},C.Nothing{}},C.Out{C.Failed{C.Host{},epoch,C.ProtocolError{}},C.CloseConnection{C.ProtocolError{}}}),C.Out{C.Failed{C.Host{},epoch,C.VersionMismatch{}},C.CloseConnection{C.VersionMismatch{}}}) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: host_token_out(U32.is_eq(epoch,token),epoch)

def frame_version_out(+flag:Bool,+state:C.State,+expected:U32,+token:U32,+observation:U32) -> {C.frame_version(flag,state,expected,token,observation) == Bool.pick(C.Out,flag,Bool.pick(C.Out,U32.is_eq(expected,token),C.Out{state,C.PresentSnapshot{token,observation}},C.failed(state,C.ProtocolError{})),C.failed(state,C.VersionMismatch{})) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: frame_token_out(U32.is_eq(expected,token),state,token,observation)

def reconnect_out(+flag:Bool,+state:C.State,+newEpoch:U32) -> {C.reconnect_selected(flag,state,newEpoch) == Bool.pick(C.Out,flag,C.begin(C.role(state),newEpoch),C.Out{state,C.Nothing{}}) : C.Out}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def guest_hello_no_start(flag:Bool,+epoch:U32,+token:U32) -> {L.starts(C.action(C.guest_hello_selected(flag,epoch,token))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def guest_hello_not_running(flag:Bool,+epoch:U32,+token:U32) -> {C.running(C.state(C.guest_hello_selected(flag,epoch,token))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def host_token_no_start(flag:Bool,+epoch:U32) -> {L.starts(C.action(C.host_ack_token(flag,epoch))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def host_token_not_running(flag:Bool,+epoch:U32) -> {C.running(C.state(C.host_ack_token(flag,epoch))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def snapshot_no_start(flag:Bool,+epoch:U32,+token:U32,+observation:U32) -> {L.starts(C.action(C.snapshot_selected(flag,epoch,token,observation))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def snapshot_not_running(flag:Bool,+epoch:U32,+token:U32,+observation:U32) -> {C.running(C.state(C.snapshot_selected(flag,epoch,token,observation))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def ready_start(+flag:Bool,+epoch:U32,+observation:U32) -> {L.starts(C.action(C.ready_selected(flag,epoch,observation))) == flag : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def ready_entry(+flag:Bool,+epoch:U32,+observation:U32) -> {C.running(C.state(C.ready_selected(flag,epoch,observation))) == Bool.or(flag,False{}) : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def started_no_start(flag:Bool,+epoch:U32,+token:U32,+observation:U32) -> {L.starts(C.action(C.started_selected(flag,epoch,token,observation))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def started_entry(+flag:Bool,+epoch:U32,+token:U32,+observation:U32) -> {C.running(C.state(C.started_selected(flag,epoch,token,observation))) == flag : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def frame_token_no_start(flag:Bool,+state:C.State,+token:U32,+observation:U32) -> {L.starts(C.action(C.frame_token(flag,state,token,observation))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def host_hello_no_start(flag:Bool,+epoch:U32,token:U32) -> {L.starts(C.action(C.host_hello_selected(flag,epoch,token))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: host_token_no_start(U32.is_eq(epoch,token),epoch)

def host_hello_not_running(flag:Bool,+epoch:U32,token:U32) -> {C.running(C.state(C.host_hello_selected(flag,epoch,token))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: host_token_not_running(U32.is_eq(epoch,token),epoch)

def frame_version_no_start(flag:Bool,+state:C.State,expected:U32,+token:U32,observation:U32) -> {L.starts(C.action(C.frame_version(flag,state,expected,token,observation))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: frame_token_no_start(U32.is_eq(expected,token),state,token,observation)

def frame_token_not_running(flag:Bool,+state:C.State,token:U32,observation:U32,idle:{C.running(state) == False{} : Bool}) -> {C.running(C.state(C.frame_token(flag,state,token,observation))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: idle

def frame_version_not_running(flag:Bool,+state:C.State,expected:U32,+token:U32,observation:U32,idle:{C.running(state) == False{} : Bool}) -> {C.running(C.state(C.frame_version(flag,state,expected,token,observation))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: frame_token_not_running(U32.is_eq(expected,token),state,token,observation,idle)

def early_frame_no_start(flag:Bool,state:C.State) -> {L.starts(C.action(C.early_frame(flag,state))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def early_frame_not_running(flag:Bool,state:C.State) -> {C.running(C.state(C.early_frame(flag,state))) == False{} : Bool}:
  match flag:
    case False{}: {==}
    case True{}: {==}

def L.protocol_version_exact(): {==}

def L.host_transport_only_negotiates(epoch): {==}

def L.guest_transport_waits_for_hello(epoch): {==}

def L.guest_hello_exact(epoch,version,token): guest_hello_out(U32.is_eq(version,1),epoch,token)

def L.host_hello_exact(epoch,version,token): host_hello_out(U32.is_eq(version,1),epoch,token)

def L.legacy_setup_rejected(epoch): {==}

def L.setup_prepares_without_running(epoch): {==}

def L.prepared_waits_for_snapshot_ack(epoch,observation): {==}

def L.applied_snapshot_ack_exact(epoch,token,received,observation): snapshot_out(U32.is_eq(received,token),epoch,token,observation)

def L.ready_ack_exact(epoch,observation,token,received): ready_out(Bool.and(U32.is_eq(token,epoch),U32.is_eq(received,observation)),epoch,observation)

def L.guest_starts_after_confirmation(epoch,token,observation,received): started_out(U32.is_eq(received,token),epoch,token,observation)

def L.duplicate_ready_does_not_restart(epoch,token,observation): {==}

def L.late_host_timeout_ignored(epoch): {==}

def L.late_guest_timeout_ignored(epoch,token): {==}

def L.waiting_timeout_reports_failure(epoch,observation): {==}

def L.failure_reason_survives_late_events(role,epoch,reason,event):
  match event:
    case C.Hello{_,_}: {==}
    case C.Frame{_,_,_}: {==}
    case C.HelloAck{_,_}: {==}
    case C.Setup{}: {==}
    case C.Prepared{_}: {==}
    case C.SnapshotSeen{_,_}: {==}
    case C.ReadyAck{_,_}: {==}
    case C.Started{_}: {==}
    case C.Timeout{}: {==}
    case C.ConnectionLost{}: {==}
    case C.Reject{_}: {==}


def L.live_loss_suspends(epoch): {==}

def L.stale_events_unchanged(state,eventEpoch,event,stale):
  %stale : {C.step_selected(_,state,event) == C.Out{state,C.Nothing{}} : C.Out}
  {==}

def L.current_event_dispatch_exact(state,eventEpoch,event,current):
  %current : {C.step_selected(_,state,event) == C.transition(state,event) : C.Out}
  {==}

def L.reconnect_newer_exact(state,newEpoch): reconnect_out(U32.is_gt(newEpoch,C.epoch(state)),state,newEpoch)

def L.frame_version_and_token_exact(epoch,expected,version,token,observation): frame_version_out(U32.is_eq(version,1),C.GuestSnapshot{epoch,expected},expected,token,observation)

def L.oversized_control_refused(text,oversized):
  %oversized : {C.decode_bounded(_,text) == None{} : Maybe<&2,C.Signal>}
  {==}

def L.hello_wire_exact(version,token): {==}

def L.hello_ack_wire_exact(version,token): {==}

def L.ready_ack_wire_exact(token,observation): {==}

def L.started_wire_exact(token): {==}

def L.hello_fields_exact(version,token): {==}

def L.hello_ack_fields_exact(version,token): {==}

def L.ready_ack_fields_exact(token,observation): {==}

def L.started_fields_exact(token): {==}

def L.peer_cannot_send_local_timeout(suffix): {==}

def L.reason_codes_roundtrip(reason):
  match reason:
    case C.VersionMismatch{}: {==}
    case C.ProtocolError{}: {==}
    case C.HandshakeTimeout{}: {==}
    case C.SetupFailed{}: {==}
    case C.SnapshotFailed{}: {==}
    case C.TransportFailed{}: {==}
    case C.RuntimeFailed{}: {==}
    case C.PresentationFailed{}: {==}

def L.running_query_exact(state):
  match state:
    case C.Idle{role,epoch}: {==}
    case C.HostHello{epoch}: {==}
    case C.HostSetup{epoch}: {==}
    case C.HostPreparing{epoch}: {==}
    case C.HostReady{epoch,observation}: {==}
    case C.HostRunning{epoch}: {==}
    case C.GuestHello{epoch}: {==}
    case C.GuestSnapshot{epoch,expected}: {==}
    case C.GuestStart{epoch,expected,observation}: {==}
    case C.GuestRunning{epoch,expected}: {==}
    case C.Suspended{role,epoch}: {==}
    case C.Failed{role,epoch,reason}: {==}

def L.start_has_only_one_cause(state,event):
  match state event:
    case C.Idle{role,epoch} C.Hello{version,token}: {==}
    case C.Idle{role,epoch} C.Frame{version,token,received}: {==}
    case C.Idle{role,epoch} C.HelloAck{version,token}: {==}
    case C.Idle{role,epoch} C.Setup{}: {==}
    case C.Idle{role,epoch} C.Prepared{received}: {==}
    case C.Idle{role,epoch} C.SnapshotSeen{token,received}: {==}
    case C.Idle{role,epoch} C.ReadyAck{token,received}: {==}
    case C.Idle{role,epoch} C.Started{token}: {==}
    case C.Idle{role,epoch} C.Timeout{}: {==}
    case C.Idle{role,epoch} C.ConnectionLost{}: {==}
    case C.Idle{role,epoch} C.Reject{why}: {==}
    case C.HostHello{epoch} C.Hello{version,token}: {==}
    case C.HostHello{epoch} C.Frame{version,token,received}: {==}
    case C.HostHello{epoch} C.HelloAck{version,token}: host_hello_no_start(U32.is_eq(version,1),epoch,token)
    case C.HostHello{epoch} C.Setup{}: {==}
    case C.HostHello{epoch} C.Prepared{received}: {==}
    case C.HostHello{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostHello{epoch} C.ReadyAck{token,received}: {==}
    case C.HostHello{epoch} C.Started{token}: {==}
    case C.HostHello{epoch} C.Timeout{}: {==}
    case C.HostHello{epoch} C.ConnectionLost{}: {==}
    case C.HostHello{epoch} C.Reject{why}: {==}
    case C.HostSetup{epoch} C.Hello{version,token}: {==}
    case C.HostSetup{epoch} C.Frame{version,token,received}: {==}
    case C.HostSetup{epoch} C.HelloAck{version,token}: {==}
    case C.HostSetup{epoch} C.Setup{}: {==}
    case C.HostSetup{epoch} C.Prepared{received}: {==}
    case C.HostSetup{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostSetup{epoch} C.ReadyAck{token,received}: {==}
    case C.HostSetup{epoch} C.Started{token}: {==}
    case C.HostSetup{epoch} C.Timeout{}: {==}
    case C.HostSetup{epoch} C.ConnectionLost{}: {==}
    case C.HostSetup{epoch} C.Reject{why}: {==}
    case C.HostPreparing{epoch} C.Hello{version,token}: {==}
    case C.HostPreparing{epoch} C.Frame{version,token,received}: {==}
    case C.HostPreparing{epoch} C.HelloAck{version,token}: {==}
    case C.HostPreparing{epoch} C.Setup{}: {==}
    case C.HostPreparing{epoch} C.Prepared{received}: {==}
    case C.HostPreparing{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostPreparing{epoch} C.ReadyAck{token,received}: {==}
    case C.HostPreparing{epoch} C.Started{token}: {==}
    case C.HostPreparing{epoch} C.Timeout{}: {==}
    case C.HostPreparing{epoch} C.ConnectionLost{}: {==}
    case C.HostPreparing{epoch} C.Reject{why}: {==}
    case C.HostReady{epoch,observation} C.Hello{version,token}: {==}
    case C.HostReady{epoch,observation} C.Frame{version,token,received}: {==}
    case C.HostReady{epoch,observation} C.HelloAck{version,token}: {==}
    case C.HostReady{epoch,observation} C.Setup{}: {==}
    case C.HostReady{epoch,observation} C.Prepared{received}: {==}
    case C.HostReady{epoch,observation} C.SnapshotSeen{token,received}: {==}
    case C.HostReady{epoch,observation} C.ReadyAck{token,received}: ready_start(Bool.and(U32.is_eq(token,epoch),U32.is_eq(received,observation)),epoch,observation)
    case C.HostReady{epoch,observation} C.Started{token}: {==}
    case C.HostReady{epoch,observation} C.Timeout{}: {==}
    case C.HostReady{epoch,observation} C.ConnectionLost{}: {==}
    case C.HostReady{epoch,observation} C.Reject{why}: {==}
    case C.HostRunning{epoch} C.Hello{version,token}: {==}
    case C.HostRunning{epoch} C.Frame{version,token,received}: {==}
    case C.HostRunning{epoch} C.HelloAck{version,token}: {==}
    case C.HostRunning{epoch} C.Setup{}: {==}
    case C.HostRunning{epoch} C.Prepared{received}: {==}
    case C.HostRunning{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostRunning{epoch} C.ReadyAck{token,received}: {==}
    case C.HostRunning{epoch} C.Started{token}: {==}
    case C.HostRunning{epoch} C.Timeout{}: {==}
    case C.HostRunning{epoch} C.ConnectionLost{}: {==}
    case C.HostRunning{epoch} C.Reject{why}: {==}
    case C.GuestHello{epoch} C.Hello{version,token}: guest_hello_no_start(U32.is_eq(version,1),epoch,token)
    case C.GuestHello{epoch} C.Frame{version,token,received}: early_frame_no_start(U32.is_eq(version,1),C.GuestHello{epoch})
    case C.GuestHello{epoch} C.HelloAck{version,token}: {==}
    case C.GuestHello{epoch} C.Setup{}: {==}
    case C.GuestHello{epoch} C.Prepared{received}: {==}
    case C.GuestHello{epoch} C.SnapshotSeen{token,received}: {==}
    case C.GuestHello{epoch} C.ReadyAck{token,received}: {==}
    case C.GuestHello{epoch} C.Started{token}: {==}
    case C.GuestHello{epoch} C.Timeout{}: {==}
    case C.GuestHello{epoch} C.ConnectionLost{}: {==}
    case C.GuestHello{epoch} C.Reject{why}: {==}
    case C.GuestSnapshot{epoch,expected} C.Hello{version,token}: {==}
    case C.GuestSnapshot{epoch,expected} C.Frame{version,token,received}: frame_version_no_start(U32.is_eq(version,1),C.GuestSnapshot{epoch,expected},expected,token,received)
    case C.GuestSnapshot{epoch,expected} C.HelloAck{version,token}: {==}
    case C.GuestSnapshot{epoch,expected} C.Setup{}: {==}
    case C.GuestSnapshot{epoch,expected} C.Prepared{received}: {==}
    case C.GuestSnapshot{epoch,expected} C.SnapshotSeen{token,received}: snapshot_no_start(U32.is_eq(token,expected),epoch,expected,received)
    case C.GuestSnapshot{epoch,expected} C.ReadyAck{token,received}: {==}
    case C.GuestSnapshot{epoch,expected} C.Started{token}: {==}
    case C.GuestSnapshot{epoch,expected} C.Timeout{}: {==}
    case C.GuestSnapshot{epoch,expected} C.ConnectionLost{}: {==}
    case C.GuestSnapshot{epoch,expected} C.Reject{why}: {==}
    case C.GuestStart{epoch,expected,observation} C.Hello{version,token}: {==}
    case C.GuestStart{epoch,expected,observation} C.Frame{version,token,received}: frame_version_no_start(U32.is_eq(version,1),C.GuestStart{epoch,expected,observation},expected,token,received)
    case C.GuestStart{epoch,expected,observation} C.HelloAck{version,token}: {==}
    case C.GuestStart{epoch,expected,observation} C.Setup{}: {==}
    case C.GuestStart{epoch,expected,observation} C.Prepared{received}: {==}
    case C.GuestStart{epoch,expected,observation} C.SnapshotSeen{token,received}: {==}
    case C.GuestStart{epoch,expected,observation} C.ReadyAck{token,received}: {==}
    case C.GuestStart{epoch,expected,observation} C.Started{token}: started_no_start(U32.is_eq(token,expected),epoch,expected,observation)
    case C.GuestStart{epoch,expected,observation} C.Timeout{}: {==}
    case C.GuestStart{epoch,expected,observation} C.ConnectionLost{}: {==}
    case C.GuestStart{epoch,expected,observation} C.Reject{why}: {==}
    case C.GuestRunning{epoch,expected} C.Hello{version,token}: {==}
    case C.GuestRunning{epoch,expected} C.Frame{version,token,received}: frame_version_no_start(U32.is_eq(version,1),C.GuestRunning{epoch,expected},expected,token,received)
    case C.GuestRunning{epoch,expected} C.HelloAck{version,token}: {==}
    case C.GuestRunning{epoch,expected} C.Setup{}: {==}
    case C.GuestRunning{epoch,expected} C.Prepared{received}: {==}
    case C.GuestRunning{epoch,expected} C.SnapshotSeen{token,received}: {==}
    case C.GuestRunning{epoch,expected} C.ReadyAck{token,received}: {==}
    case C.GuestRunning{epoch,expected} C.Started{token}: {==}
    case C.GuestRunning{epoch,expected} C.Timeout{}: {==}
    case C.GuestRunning{epoch,expected} C.ConnectionLost{}: {==}
    case C.GuestRunning{epoch,expected} C.Reject{why}: {==}
    case C.Suspended{role,epoch} C.Hello{version,token}: {==}
    case C.Suspended{role,epoch} C.Frame{version,token,received}: {==}
    case C.Suspended{role,epoch} C.HelloAck{version,token}: {==}
    case C.Suspended{role,epoch} C.Setup{}: {==}
    case C.Suspended{role,epoch} C.Prepared{received}: {==}
    case C.Suspended{role,epoch} C.SnapshotSeen{token,received}: {==}
    case C.Suspended{role,epoch} C.ReadyAck{token,received}: {==}
    case C.Suspended{role,epoch} C.Started{token}: {==}
    case C.Suspended{role,epoch} C.Timeout{}: {==}
    case C.Suspended{role,epoch} C.ConnectionLost{}: {==}
    case C.Suspended{role,epoch} C.Reject{why}: {==}
    case C.Failed{role,epoch,reason} C.Hello{version,token}: {==}
    case C.Failed{role,epoch,reason} C.Frame{version,token,received}: {==}
    case C.Failed{role,epoch,reason} C.HelloAck{version,token}: {==}
    case C.Failed{role,epoch,reason} C.Setup{}: {==}
    case C.Failed{role,epoch,reason} C.Prepared{received}: {==}
    case C.Failed{role,epoch,reason} C.SnapshotSeen{token,received}: {==}
    case C.Failed{role,epoch,reason} C.ReadyAck{token,received}: {==}
    case C.Failed{role,epoch,reason} C.Started{token}: {==}
    case C.Failed{role,epoch,reason} C.Timeout{}: {==}
    case C.Failed{role,epoch,reason} C.ConnectionLost{}: {==}
    case C.Failed{role,epoch,reason} C.Reject{why}: {==}

def L.running_entry_has_only_confirmed_causes(state,event):
  match state event:
    case C.Idle{role,epoch} C.Hello{version,token}: {==}
    case C.Idle{role,epoch} C.Frame{version,token,received}: {==}
    case C.Idle{role,epoch} C.HelloAck{version,token}: {==}
    case C.Idle{role,epoch} C.Setup{}: {==}
    case C.Idle{role,epoch} C.Prepared{received}: {==}
    case C.Idle{role,epoch} C.SnapshotSeen{token,received}: {==}
    case C.Idle{role,epoch} C.ReadyAck{token,received}: {==}
    case C.Idle{role,epoch} C.Started{token}: {==}
    case C.Idle{role,epoch} C.Timeout{}: {==}
    case C.Idle{role,epoch} C.ConnectionLost{}: {==}
    case C.Idle{role,epoch} C.Reject{why}: {==}
    case C.HostHello{epoch} C.Hello{version,token}: {==}
    case C.HostHello{epoch} C.Frame{version,token,received}: {==}
    case C.HostHello{epoch} C.HelloAck{version,token}: host_hello_not_running(U32.is_eq(version,1),epoch,token)
    case C.HostHello{epoch} C.Setup{}: {==}
    case C.HostHello{epoch} C.Prepared{received}: {==}
    case C.HostHello{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostHello{epoch} C.ReadyAck{token,received}: {==}
    case C.HostHello{epoch} C.Started{token}: {==}
    case C.HostHello{epoch} C.Timeout{}: {==}
    case C.HostHello{epoch} C.ConnectionLost{}: {==}
    case C.HostHello{epoch} C.Reject{why}: {==}
    case C.HostSetup{epoch} C.Hello{version,token}: {==}
    case C.HostSetup{epoch} C.Frame{version,token,received}: {==}
    case C.HostSetup{epoch} C.HelloAck{version,token}: {==}
    case C.HostSetup{epoch} C.Setup{}: {==}
    case C.HostSetup{epoch} C.Prepared{received}: {==}
    case C.HostSetup{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostSetup{epoch} C.ReadyAck{token,received}: {==}
    case C.HostSetup{epoch} C.Started{token}: {==}
    case C.HostSetup{epoch} C.Timeout{}: {==}
    case C.HostSetup{epoch} C.ConnectionLost{}: {==}
    case C.HostSetup{epoch} C.Reject{why}: {==}
    case C.HostPreparing{epoch} C.Hello{version,token}: {==}
    case C.HostPreparing{epoch} C.Frame{version,token,received}: {==}
    case C.HostPreparing{epoch} C.HelloAck{version,token}: {==}
    case C.HostPreparing{epoch} C.Setup{}: {==}
    case C.HostPreparing{epoch} C.Prepared{received}: {==}
    case C.HostPreparing{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostPreparing{epoch} C.ReadyAck{token,received}: {==}
    case C.HostPreparing{epoch} C.Started{token}: {==}
    case C.HostPreparing{epoch} C.Timeout{}: {==}
    case C.HostPreparing{epoch} C.ConnectionLost{}: {==}
    case C.HostPreparing{epoch} C.Reject{why}: {==}
    case C.HostReady{epoch,observation} C.Hello{version,token}: {==}
    case C.HostReady{epoch,observation} C.Frame{version,token,received}: {==}
    case C.HostReady{epoch,observation} C.HelloAck{version,token}: {==}
    case C.HostReady{epoch,observation} C.Setup{}: {==}
    case C.HostReady{epoch,observation} C.Prepared{received}: {==}
    case C.HostReady{epoch,observation} C.SnapshotSeen{token,received}: {==}
    case C.HostReady{epoch,observation} C.ReadyAck{token,received}: ready_entry(Bool.and(U32.is_eq(token,epoch),U32.is_eq(received,observation)),epoch,observation)
    case C.HostReady{epoch,observation} C.Started{token}: {==}
    case C.HostReady{epoch,observation} C.Timeout{}: {==}
    case C.HostReady{epoch,observation} C.ConnectionLost{}: {==}
    case C.HostReady{epoch,observation} C.Reject{why}: {==}
    case C.HostRunning{epoch} C.Hello{version,token}: {==}
    case C.HostRunning{epoch} C.Frame{version,token,received}: {==}
    case C.HostRunning{epoch} C.HelloAck{version,token}: {==}
    case C.HostRunning{epoch} C.Setup{}: {==}
    case C.HostRunning{epoch} C.Prepared{received}: {==}
    case C.HostRunning{epoch} C.SnapshotSeen{token,received}: {==}
    case C.HostRunning{epoch} C.ReadyAck{token,received}: {==}
    case C.HostRunning{epoch} C.Started{token}: {==}
    case C.HostRunning{epoch} C.Timeout{}: {==}
    case C.HostRunning{epoch} C.ConnectionLost{}: {==}
    case C.HostRunning{epoch} C.Reject{why}: {==}
    case C.GuestHello{epoch} C.Hello{version,token}: guest_hello_not_running(U32.is_eq(version,1),epoch,token)
    case C.GuestHello{epoch} C.Frame{version,token,received}: early_frame_not_running(U32.is_eq(version,1),C.GuestHello{epoch})
    case C.GuestHello{epoch} C.HelloAck{version,token}: {==}
    case C.GuestHello{epoch} C.Setup{}: {==}
    case C.GuestHello{epoch} C.Prepared{received}: {==}
    case C.GuestHello{epoch} C.SnapshotSeen{token,received}: {==}
    case C.GuestHello{epoch} C.ReadyAck{token,received}: {==}
    case C.GuestHello{epoch} C.Started{token}: {==}
    case C.GuestHello{epoch} C.Timeout{}: {==}
    case C.GuestHello{epoch} C.ConnectionLost{}: {==}
    case C.GuestHello{epoch} C.Reject{why}: {==}
    case C.GuestSnapshot{epoch,expected} C.Hello{version,token}: {==}
    case C.GuestSnapshot{epoch,expected} C.Frame{version,token,received}: frame_version_not_running(U32.is_eq(version,1),C.GuestSnapshot{epoch,expected},expected,token,received,{==})
    case C.GuestSnapshot{epoch,expected} C.HelloAck{version,token}: {==}
    case C.GuestSnapshot{epoch,expected} C.Setup{}: {==}
    case C.GuestSnapshot{epoch,expected} C.Prepared{received}: {==}
    case C.GuestSnapshot{epoch,expected} C.SnapshotSeen{token,received}: snapshot_not_running(U32.is_eq(token,expected),epoch,expected,received)
    case C.GuestSnapshot{epoch,expected} C.ReadyAck{token,received}: {==}
    case C.GuestSnapshot{epoch,expected} C.Started{token}: {==}
    case C.GuestSnapshot{epoch,expected} C.Timeout{}: {==}
    case C.GuestSnapshot{epoch,expected} C.ConnectionLost{}: {==}
    case C.GuestSnapshot{epoch,expected} C.Reject{why}: {==}
    case C.GuestStart{epoch,expected,observation} C.Hello{version,token}: {==}
    case C.GuestStart{epoch,expected,observation} C.Frame{version,token,received}: frame_version_not_running(U32.is_eq(version,1),C.GuestStart{epoch,expected,observation},expected,token,received,{==})
    case C.GuestStart{epoch,expected,observation} C.HelloAck{version,token}: {==}
    case C.GuestStart{epoch,expected,observation} C.Setup{}: {==}
    case C.GuestStart{epoch,expected,observation} C.Prepared{received}: {==}
    case C.GuestStart{epoch,expected,observation} C.SnapshotSeen{token,received}: {==}
    case C.GuestStart{epoch,expected,observation} C.ReadyAck{token,received}: {==}
    case C.GuestStart{epoch,expected,observation} C.Started{token}: started_entry(U32.is_eq(token,expected),epoch,expected,observation)
    case C.GuestStart{epoch,expected,observation} C.Timeout{}: {==}
    case C.GuestStart{epoch,expected,observation} C.ConnectionLost{}: {==}
    case C.GuestStart{epoch,expected,observation} C.Reject{why}: {==}
    case C.GuestRunning{epoch,expected} C.Hello{version,token}: {==}
    case C.GuestRunning{epoch,expected} C.Frame{version,token,received}: {==}
    case C.GuestRunning{epoch,expected} C.HelloAck{version,token}: {==}
    case C.GuestRunning{epoch,expected} C.Setup{}: {==}
    case C.GuestRunning{epoch,expected} C.Prepared{received}: {==}
    case C.GuestRunning{epoch,expected} C.SnapshotSeen{token,received}: {==}
    case C.GuestRunning{epoch,expected} C.ReadyAck{token,received}: {==}
    case C.GuestRunning{epoch,expected} C.Started{token}: {==}
    case C.GuestRunning{epoch,expected} C.Timeout{}: {==}
    case C.GuestRunning{epoch,expected} C.ConnectionLost{}: {==}
    case C.GuestRunning{epoch,expected} C.Reject{why}: {==}
    case C.Suspended{role,epoch} C.Hello{version,token}: {==}
    case C.Suspended{role,epoch} C.Frame{version,token,received}: {==}
    case C.Suspended{role,epoch} C.HelloAck{version,token}: {==}
    case C.Suspended{role,epoch} C.Setup{}: {==}
    case C.Suspended{role,epoch} C.Prepared{received}: {==}
    case C.Suspended{role,epoch} C.SnapshotSeen{token,received}: {==}
    case C.Suspended{role,epoch} C.ReadyAck{token,received}: {==}
    case C.Suspended{role,epoch} C.Started{token}: {==}
    case C.Suspended{role,epoch} C.Timeout{}: {==}
    case C.Suspended{role,epoch} C.ConnectionLost{}: {==}
    case C.Suspended{role,epoch} C.Reject{why}: {==}
    case C.Failed{role,epoch,reason} C.Hello{version,token}: {==}
    case C.Failed{role,epoch,reason} C.Frame{version,token,received}: {==}
    case C.Failed{role,epoch,reason} C.HelloAck{version,token}: {==}
    case C.Failed{role,epoch,reason} C.Setup{}: {==}
    case C.Failed{role,epoch,reason} C.Prepared{received}: {==}
    case C.Failed{role,epoch,reason} C.SnapshotSeen{token,received}: {==}
    case C.Failed{role,epoch,reason} C.ReadyAck{token,received}: {==}
    case C.Failed{role,epoch,reason} C.Started{token}: {==}
    case C.Failed{role,epoch,reason} C.Timeout{}: {==}
    case C.Failed{role,epoch,reason} C.ConnectionLost{}: {==}
    case C.Failed{role,epoch,reason} C.Reject{why}: {==}

def L.epoch_projection_exact(state):
  match state:
    case C.Idle{role,epoch}: {==}
    case C.HostHello{epoch}: {==}
    case C.HostSetup{epoch}: {==}
    case C.HostPreparing{epoch}: {==}
    case C.HostReady{epoch,observation}: {==}
    case C.HostRunning{epoch}: {==}
    case C.GuestHello{epoch}: {==}
    case C.GuestSnapshot{epoch,token}: {==}
    case C.GuestStart{epoch,token,observation}: {==}
    case C.GuestRunning{epoch,token}: {==}
    case C.Suspended{role,epoch}: {==}
    case C.Failed{role,epoch,reason}: {==}

def L.role_projection_exact(state):
  match state:
    case C.Idle{role,epoch}: {==}
    case C.HostHello{epoch}: {==}
    case C.HostSetup{epoch}: {==}
    case C.HostPreparing{epoch}: {==}
    case C.HostReady{epoch,observation}: {==}
    case C.HostRunning{epoch}: {==}
    case C.GuestHello{epoch}: {==}
    case C.GuestSnapshot{epoch,token}: {==}
    case C.GuestStart{epoch,token,observation}: {==}
    case C.GuestRunning{epoch,token}: {==}
    case C.Suspended{role,epoch}: {==}
    case C.Failed{role,epoch,reason}: {==}

def L.waiting_exact(state):
  match state:
    case C.Idle{role,epoch}: {==}
    case C.HostHello{epoch}: {==}
    case C.HostSetup{epoch}: {==}
    case C.HostPreparing{epoch}: {==}
    case C.HostReady{epoch,observation}: {==}
    case C.HostRunning{epoch}: {==}
    case C.GuestHello{epoch}: {==}
    case C.GuestSnapshot{epoch,token}: {==}
    case C.GuestStart{epoch,token,observation}: {==}
    case C.GuestRunning{epoch,token}: {==}
    case C.Suspended{role,epoch}: {==}
    case C.Failed{role,epoch,reason}: {==}
