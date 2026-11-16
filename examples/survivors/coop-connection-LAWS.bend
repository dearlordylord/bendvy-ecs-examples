import Base
import ./coop-connection.bend as C
import ./coop-protocol.bend as Wire

# Connection laws cover pure event admission and emitted actions. IO must deliver
# authenticated epochs, execute the returned actions, and report actual snapshot
# application. The world remains outside this value and is not reconstructed here.
def starts(action:C.Action) -> Bool:
  match action:
    case C.StartAndConfirm{_}: True{}
    case _: False{}
def expected_start(state:C.State,event:C.Signal) -> Bool:
  match state event:
    case C.HostReady{epoch,observation} C.ReadyAck{token,received}: Bool.and(U32.is_eq(token,epoch),U32.is_eq(received,observation))
    case _ _: False{}

# Guarantees: the current handshake version is one.
# Why it matters: mixed published clients must not silently start different simulation contracts.
law protocol_version_exact:
  {C.protocol_version() == 1 : U32}

# Guarantees: a host transport connection sends Hello and remains outside Running.
# Why it matters: an Iroh connection alone must not start the game.
law host_transport_only_negotiates:
  for +epoch:U32
  {C.begin(C.Host{},epoch) == C.Out{C.HostHello{epoch},C.SendHello{1,epoch}} : C.Out}

# Guarantees: a guest transport connection waits without sending gameplay setup.
# Why it matters: an incompatible host must be rejected before creating a player.
law guest_transport_waits_for_hello:
  for +epoch:U32
  {C.begin(C.Guest{},epoch) == C.Out{C.GuestHello{epoch},C.Nothing{}} : C.Out}

# Guarantees: a guest accepts only version one and then echoes the token before setup.
# Why it matters: a stale game build needs a clear version error rather than starting and dropping.
law guest_hello_exact:
  for +epoch:U32
  for +version:U32
  for +token:U32
  {C.transition(C.GuestHello{epoch},C.Hello{version,token}) == Bool.pick(C.Out,U32.is_eq(version,1),C.Out{C.GuestSnapshot{epoch,token},C.HelloAckAndSetup{1,token}},C.Out{C.Failed{C.Guest{},epoch,C.VersionMismatch{}},C.CloseConnection{C.VersionMismatch{}}}) : C.Out}

# Guarantees: host setup opens only after version one and its own connection token are echoed.
# Why it matters: old peers and acknowledgements from another connection cannot prepare the world.
law host_hello_exact:
  for +epoch:U32
  for +version:U32
  for +token:U32
  {C.transition(C.HostHello{epoch},C.HelloAck{version,token}) == Bool.pick(C.Out,U32.is_eq(version,1),Bool.pick(C.Out,U32.is_eq(epoch,token),C.Out{C.HostSetup{epoch},C.Nothing{}},C.Out{C.Failed{C.Host{},epoch,C.ProtocolError{}},C.CloseConnection{C.ProtocolError{}}}),C.Out{C.Failed{C.Host{},epoch,C.VersionMismatch{}},C.CloseConnection{C.VersionMismatch{}}}) : C.Out}

# Guarantees: Setup before HelloAck fails with VersionMismatch.
# Why it matters: an old guest must not start the host and disconnect before receiving a frame.
law legacy_setup_rejected:
  for +epoch:U32
  {C.transition(C.HostHello{epoch},C.Setup{}) == C.Out{C.Failed{C.Host{},epoch,C.VersionMismatch{}},C.CloseConnection{C.VersionMismatch{}}} : C.Out}

# Guarantees: verified setup requests world preparation and remains in HostPreparing.
# Why it matters: creating a player is not proof that the guest received the world.
law setup_prepares_without_running:
  for +epoch:U32
  {C.transition(C.HostSetup{epoch},C.Setup{}) == C.Out{C.HostPreparing{epoch},C.PrepareWorld{}} : C.Out}

# Guarantees: preparing the world publishes its exact initial observation and waits.
# Why it matters: the host must not tick while the guest is still loading or cannot apply the snapshot.
law prepared_waits_for_snapshot_ack:
  for +epoch:U32
  for +observation:U32
  {C.transition(C.HostPreparing{epoch},C.Prepared{observation}) == C.Out{C.HostReady{epoch,observation},C.PublishInitial{epoch,observation}} : C.Out}

# Guarantees: successful initial snapshot application echoes exactly its token and observation.
# Why it matters: receipt of bytes alone must not be treated as a usable guest world.
law applied_snapshot_ack_exact:
  for +epoch:U32
  for +token:U32
  for +received:U32
  for +observation:U32
  {C.transition(C.GuestSnapshot{epoch,token},C.SnapshotSeen{received,observation}) == Bool.pick(C.Out,U32.is_eq(received,token),C.Out{C.GuestStart{epoch,token,observation},C.SendReadyAck{token,observation}},C.Out{C.Failed{C.Guest{},epoch,C.ProtocolError{}},C.CloseConnection{C.ProtocolError{}}}) : C.Out}

# Guarantees: only the matching connection token and initial observation start the host once.
# Why it matters: a stale snapshot ACK must not start or resume a different connection.
law ready_ack_exact:
  for +epoch:U32
  for +observation:U32
  for +token:U32
  for +received:U32
  {C.transition(C.HostReady{epoch,observation},C.ReadyAck{token,received}) == Bool.pick(C.Out,Bool.and(U32.is_eq(token,epoch),U32.is_eq(received,observation)),C.Out{C.HostRunning{epoch},C.StartAndConfirm{epoch}},C.Out{C.HostReady{epoch,observation},C.Nothing{}}) : C.Out}

# Guarantees: the guest becomes ready only when the host confirms the same handshake token.
# Why it matters: guest input must not run ahead while its initial ACK is still pending.
law guest_starts_after_confirmation:
  for +epoch:U32
  for +token:U32
  for +observation:U32
  for +received:U32
  {C.transition(C.GuestStart{epoch,token,observation},C.Started{received}) == Bool.pick(C.Out,U32.is_eq(received,token),C.Out{C.GuestRunning{epoch,token},C.GuestReady{}},C.Out{C.GuestStart{epoch,token,observation},C.Nothing{}}) : C.Out}

# Guarantees: the sole StartAndConfirm action is a matching ReadyAck in HostReady.
# Why it matters: neither transport, version agreement, setup, preparation, frame arrival nor an unrelated event starts the game.
law start_has_only_one_cause:
  for +state:C.State
  for +event:C.Signal
  {starts(C.action(C.transition(state,event))) == expected_start(state,event) : Bool}

# Guarantees: every ReadyAck in an already running host is ignored.
# Why it matters: a duplicate ACK cannot restart timers or reset a live run.
law duplicate_ready_does_not_restart:
  for +epoch:U32
  for token:U32
  for observation:U32
  {C.transition(C.HostRunning{epoch},C.ReadyAck{token,observation}) == C.Out{C.HostRunning{epoch},C.Nothing{}} : C.Out}

# Guarantees: an old connection deadline does nothing to a running host.
# Why it matters: a delayed timer must not disconnect a successfully joined game.
law late_host_timeout_ignored:
  for +epoch:U32
  {C.transition(C.HostRunning{epoch},C.Timeout{}) == C.Out{C.HostRunning{epoch},C.Nothing{}} : C.Out}

# Guarantees: an old connection deadline does nothing to a running guest.
# Why it matters: a late timer after readiness must not replace the live screen with a connection error.
law late_guest_timeout_ignored:
  for +epoch:U32
  for +token:U32
  {C.transition(C.GuestRunning{epoch,token},C.Timeout{}) == C.Out{C.GuestRunning{epoch,token},C.Nothing{}} : C.Out}

# Guarantees: a host awaiting the initial ACK times out with a specific failure.
# Why it matters: a guest that never applies its first frame must not leave the host silently running.
law waiting_timeout_reports_failure:
  for +epoch:U32
  for observation:U32
  {C.transition(C.HostReady{epoch,observation},C.Timeout{}) == C.Out{C.Failed{C.Host{},epoch,C.HandshakeTimeout{}},C.CloseConnection{C.HandshakeTimeout{}}} : C.Out}

# Guarantees: a failed connection retains its original reason and emits no further action.
# Why it matters: close callbacks must not overwrite a useful version error with a generic disconnect.
law failure_reason_survives_late_events:
  for +role:C.Role
  for +epoch:U32
  for +reason:C.Reason
  for event:C.Signal
  {C.transition(C.Failed{role,epoch,reason},event) == C.Out{C.Failed{role,epoch,reason},C.Nothing{}} : C.Out}

# Guarantees: host transport loss suspends the current handshake without starting or rebuilding the world.
# Why it matters: reload must preserve the prepared game for a later connection.
law live_loss_suspends:
  for +epoch:U32
  {C.transition(C.HostRunning{epoch},C.ConnectionLost{}) == C.Out{C.Suspended{C.Host{},epoch},C.Suspend{}} : C.Out}

# Guarantees: an event from a different local connection epoch leaves the entire handshake unchanged.
# Why it matters: old async callbacks must not start or close a replacement connection.
law stale_events_unchanged:
  for +state:C.State
  for +eventEpoch:U32
  for event:C.Signal
  for stale:{False{} == U32.is_eq(eventEpoch,C.epoch(state)) : Bool}
  {C.step(state,eventEpoch,event) == C.Out{state,C.Nothing{}} : C.Out}

# Guarantees: a current-epoch event executes the declared transition exactly.
# Why it matters: the public entry point cannot bypass handshake admission.
law current_event_dispatch_exact:
  for +state:C.State
  for +eventEpoch:U32
  for +event:C.Signal
  for current:{True{} == U32.is_eq(eventEpoch,C.epoch(state)) : Bool}
  {C.step(state,eventEpoch,event) == C.transition(state,event) : C.Out}

# Guarantees: only a strictly newer local epoch resets the handshake for its existing role.
# Why it matters: retry must clear failure without replaying stale connection completion.
law reconnect_newer_exact:
  for +state:C.State
  for +newEpoch:U32
  {C.reconnect(state,newEpoch) == Bool.pick(C.Out,U32.is_gt(newEpoch,C.epoch(state)),C.begin(C.role(state),newEpoch),C.Out{state,C.Nothing{}}) : C.Out}

# Guarantees: a negotiated guest presents a frame only for version one and its negotiated token.
# Why it matters: mixed builds and snapshots from another connection must fail before applying game state.
law frame_version_and_token_exact:
  for +epoch:U32
  for +expected:U32
  for +version:U32
  for +token:U32
  for +observation:U32
  {C.transition(C.GuestSnapshot{epoch,expected},C.Frame{version,token,observation}) == Bool.pick(C.Out,U32.is_eq(version,1),Bool.pick(C.Out,U32.is_eq(expected,token),C.Out{C.GuestSnapshot{epoch,expected},C.PresentSnapshot{token,observation}},C.Out{C.Failed{C.Guest{},epoch,C.ProtocolError{}},C.CloseConnection{C.ProtocolError{}}}),C.Out{C.Failed{C.Guest{},epoch,C.VersionMismatch{}},C.CloseConnection{C.VersionMismatch{}}}) : C.Out}

# Guarantees: control text over 160 characters is refused before field parsing.
# Why it matters: a malformed handshake cannot force unbounded decoder work.
law oversized_control_refused:
  for +text:String
  for oversized:{False{} == Nat.is_le(String.length(text),160n) : Bool}
  {C.decode(text) == None{} : Maybe<&2,C.Signal>}

# Guarantees: each declared rejection reason survives its numeric control encoding.
# Why it matters: a version mismatch must remain distinguishable from setup, snapshot and runtime failures.
law reason_codes_roundtrip:
  for +reason:C.Reason
  {C.decode_reason(C.reason_code(reason)) == Some{reason} : Maybe<&2,C.Reason>}

# Guarantees: the hello action retains its tag and every handshake identifier on the wire.
# Why it matters: the receiver must acknowledge the same negotiated connection and observation.
law hello_wire_exact:
  for +version:U32
  for +token:U32
  {C.encode_action(C.SendHello{version,token}) == "BSC-HS1|H|" ++ U32.show(version) ++ "|" ++ U32.show(token) : String}

# Guarantees: the hello_ack action retains its tag and every handshake identifier on the wire.
# Why it matters: the receiver must acknowledge the same negotiated connection and observation.
law hello_ack_wire_exact:
  for +version:U32
  for +token:U32
  {C.encode_action(C.HelloAckAndSetup{version,token}) == "BSC-HS1|A|" ++ U32.show(version) ++ "|" ++ U32.show(token) : String}

# Guarantees: the ready_ack action retains its tag and every handshake identifier on the wire.
# Why it matters: the receiver must acknowledge the same negotiated connection and observation.
law ready_ack_wire_exact:
  for +token:U32
  for +observation:U32
  {C.encode_action(C.SendReadyAck{token,observation}) == "BSC-HS1|R|" ++ U32.show(token) ++ "|" ++ U32.show(observation) : String}

# Guarantees: the started action retains its tag and every handshake identifier on the wire.
# Why it matters: the receiver must acknowledge the same negotiated connection and observation.
law started_wire_exact:
  for +token:U32
  {C.encode_action(C.StartAndConfirm{token}) == "BSC-HS1|S|" ++ U32.show(token) : String}

def hello_fields(version:String,token:String) -> Maybe<&2,C.Signal>:
  do Maybe<&2,C.Signal>:
    v : U32 <- Wire.number(version)
    t : U32 <- Wire.number(token)
    return C.Hello{v,t}

# Guarantees: the hello control decodes all fields canonically into its declared signal.
# Why it matters: malformed numbers must not become a default version, connection or snapshot identifier.
law hello_fields_exact:
  for +version:String
  for +token:String
  {C.decode_fields(["BSC-HS1","H",version,token]) == hello_fields(version,token) : Maybe<&2,C.Signal>}

def hello_ack_fields(version:String,token:String) -> Maybe<&2,C.Signal>:
  do Maybe<&2,C.Signal>:
    v : U32 <- Wire.number(version)
    t : U32 <- Wire.number(token)
    return C.HelloAck{v,t}

# Guarantees: the hello_ack control decodes all fields canonically into its declared signal.
# Why it matters: malformed numbers must not become a default version, connection or snapshot identifier.
law hello_ack_fields_exact:
  for +version:String
  for +token:String
  {C.decode_fields(["BSC-HS1","A",version,token]) == hello_ack_fields(version,token) : Maybe<&2,C.Signal>}

def ready_ack_fields(token:String,observation:String) -> Maybe<&2,C.Signal>:
  do Maybe<&2,C.Signal>:
    t : U32 <- Wire.number(token)
    o : U32 <- Wire.number(observation)
    return C.ReadyAck{t,o}

# Guarantees: the ready_ack control decodes all fields canonically into its declared signal.
# Why it matters: malformed numbers must not become a default version, connection or snapshot identifier.
law ready_ack_fields_exact:
  for +token:String
  for +observation:String
  {C.decode_fields(["BSC-HS1","R",token,observation]) == ready_ack_fields(token,observation) : Maybe<&2,C.Signal>}

def started_fields(token:String) -> Maybe<&2,C.Signal>:
  do Maybe<&2,C.Signal>:
    t : U32 <- Wire.number(token)
    return C.Started{t}

# Guarantees: the started control decodes all fields canonically into its declared signal.
# Why it matters: malformed numbers must not become a default version, connection or snapshot identifier.
law started_fields_exact:
  for +token:String
  {C.decode_fields(["BSC-HS1","S",token]) == started_fields(token) : Maybe<&2,C.Signal>}

# Guarantees: a wire timeout request is not a handshake signal.
# Why it matters: only the local IO deadline may expire a connection.
law peer_cannot_send_local_timeout:
  for suffix:String
  {C.decode_fields(["BSC-HS1","Timeout",suffix]) == None{} : Maybe<&2,C.Signal>}

def is_running(state:C.State) -> Bool:
  match state:
    case C.HostRunning{_}: True{}
    case C.GuestRunning{_,_}: True{}
    case _: False{}
def expected_guest_start(state:C.State,event:C.Signal) -> Bool:
  match state event:
    case C.GuestStart{_,token,_} C.Started{received}: U32.is_eq(received,token)
    case _ _: False{}

# Guarantees: the scheduler readiness query is true exactly for the two Running phases.
# Why it matters: the worker must not tick a merely connected, prepared or failed game.
law running_query_exact:
  for +state:C.State
  {C.running(state) == is_running(state) : Bool}

# Guarantees: a not-yet-running connection enters Running only for the exact
# host snapshot ACK or matching guest Started confirmation, and both succeed.
# Why it matters: the worker gates ticks on the resulting state, so returning
# HostRunning with a harmless-looking action must not bypass readiness.
law running_entry_has_only_confirmed_causes:
  for +state:C.State
  for +event:C.Signal
  {Bool.and(Bool.not(C.running(state)),C.running(C.state(C.transition(state,event)))) == Bool.or(expected_start(state,event),expected_guest_start(state,event)) : Bool}

def stored_epoch(state:C.State) -> U32:
  match state:
    case C.Idle{role,epoch}: epoch
    case C.HostHello{epoch}: epoch
    case C.HostSetup{epoch}: epoch
    case C.HostPreparing{epoch}: epoch
    case C.HostReady{epoch,observation}: epoch
    case C.HostRunning{epoch}: epoch
    case C.GuestHello{epoch}: epoch
    case C.GuestSnapshot{epoch,token}: epoch
    case C.GuestStart{epoch,token,observation}: epoch
    case C.GuestRunning{epoch,token}: epoch
    case C.Suspended{role,epoch}: epoch
    case C.Failed{role,epoch,reason}: epoch

def phase_role(state:C.State) -> C.Role:
  match state:
    case C.Idle{role,epoch}: role
    case C.HostHello{epoch}: C.Host{}
    case C.HostSetup{epoch}: C.Host{}
    case C.HostPreparing{epoch}: C.Host{}
    case C.HostReady{epoch,observation}: C.Host{}
    case C.HostRunning{epoch}: C.Host{}
    case C.GuestHello{epoch}: C.Guest{}
    case C.GuestSnapshot{epoch,token}: C.Guest{}
    case C.GuestStart{epoch,token,observation}: C.Guest{}
    case C.GuestRunning{epoch,token}: C.Guest{}
    case C.Suspended{role,epoch}: role
    case C.Failed{role,epoch,reason}: role

def phase_waiting(state:C.State) -> Bool:
  match state:
    case C.Idle{role,epoch}: True{}
    case C.HostHello{epoch}: True{}
    case C.HostSetup{epoch}: True{}
    case C.HostPreparing{epoch}: True{}
    case C.HostReady{epoch,observation}: True{}
    case C.HostRunning{epoch}: False{}
    case C.GuestHello{epoch}: True{}
    case C.GuestSnapshot{epoch,token}: True{}
    case C.GuestStart{epoch,token,observation}: True{}
    case C.GuestRunning{epoch,token}: False{}
    case C.Suspended{role,epoch}: False{}
    case C.Failed{role,epoch,reason}: False{}

# Guarantees: each phase exposes its actual stored local connection epoch.
# Why it matters: stale-event refusal must not compare two copies of an incorrect epoch projection.
law epoch_projection_exact:
  for +state:C.State
  {C.epoch(state) == stored_epoch(state) : U32}

# Guarantees: Host phases map to Host, Guest phases to Guest, and neutral/failure phases retain their stored role.
# Why it matters: retry must recreate the same side of the handshake after suspension or failure.
law role_projection_exact:
  for +state:C.State
  {C.role(state) == phase_role(state) : C.Role}

# Guarantees: only Idle and the seven unfinished handshake phases are waiting; Running, Suspended and Failed are not.
# Why it matters: the deadline must cover every unfinished connection without expiring a completed or already stopped one.
law waiting_exact:
  for +state:C.State
  {C.waiting(state) == phase_waiting(state) : Bool}
