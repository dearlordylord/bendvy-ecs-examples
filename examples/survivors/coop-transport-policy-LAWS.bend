import Base
import ./coop-transport-policy.bend as T
import ./coop-lobby.bend as L

def out_state(out:T.Out) -> T.State:
  match out:
    case T.Out{state,_}: state

law budgets_exact:
  (({T.max_frame_bytes() == 1048576 : U32} & {T.max_pending_bytes() == 4194304 : U32}) & ({T.max_pending_messages() == 16n : Nat} & ({T.max_bridge_events() == 64 : U32} & {T.max_bridge_bytes() == 4194304 : U32})))
law fresh_empty:
  ({T.pending_count(T.fresh()) == 0n : Nat} & {T.pending_bytes(T.fresh()) == 0 : U32})
law close_idempotent:
  for +next:U32
  for +epoch:U32
  for +admission:Bool
  {T.close(T.State{T.Closed{},next,epoch,[],None{},None{},None{},admission},T.Cancelled{}) == T.Out{T.State{T.Closed{},next,epoch,[],None{},None{},None{},admission},[]} : T.Out}
law closing_discards_queued_bytes:
  for +state:T.State
  for +reason:T.Reason
  {T.pending_bytes(out_state(T.close_selected(False{},state,reason))) == 0 : U32}
law closing_discards_queued_messages:
  for +state:T.State
  for +reason:T.Reason
  {T.pending_count(out_state(T.close_selected(False{},state,reason))) == 0n : Nat}
law stale_write_outcome_preserves:
  for +state:T.State
  for +success:Bool
  {T.written_selected(False{},state,success) == T.Out{state,[]} : T.Out}
law stale_attempt_failure_preserves:
  for +state:T.State
  {T.failed_attempt_selected(False{},state) == T.Out{state,[]} : T.Out}
law duplicate_connection_preserves:
  for +state:T.State
  for operation:U32
  for connection:U32
  for peer:String
  {T.connected_duplicate(True{},state,operation,connection,peer) == T.Out{state,[]} : T.Out}
law stale_success_disposes_its_connection:
  for +state:T.State
  for +connection:U32
  for peer:String
  {T.connected_selected(False{},state,connection,peer) == T.Out{state,[T.Disconnect{connection}]} : T.Out}
law rejected_message_never_notifies:
  for +state:T.State
  for request:U32
  for peer:String
  {T.received_selected(False{},state,request,peer) == T.Out{state,[]} : T.Out}
law stale_departure_preserves:
  for +state:T.State
  {T.departed_selected(False{},state) == T.Out{state,[]} : T.Out}
law refused_enqueue_preserves:
  for +state:T.State
  for +request:U32
  for +bytes:U32
  for confirm:Bool
  {T.enqueue_selected(False{},state,request,bytes,confirm) == T.Out{state,[T.Settle{request,False{},T.send_reason(state,bytes)}]} : T.Out}
law writer_prevents_another_write:
  for +connection:U32
  for +peer:String
  for +next:U32
  for +epoch:U32
  for +rows:List<&2,T.Pending>
  for +writer:T.Writer
  for +handshake:Maybe<&2,T.Timer>
  for +drain:Maybe<&2,T.Timer>
  for +admission:Bool
  {T.pump_selected(True{},T.State{T.Connected{connection,peer},next,epoch,rows,Some{writer},handshake,drain,admission}) == T.Out{T.State{T.Connected{connection,peer},next,epoch,rows,Some{writer},handshake,drain,admission},[]} : T.Out}
law busy_offer_refused:
  for +connection:U32
  for +peer:String
  for +next:U32
  for +epoch:U32
  for +rows:List<&2,T.Pending>
  for +writer:Maybe<&2,T.Writer>
  for +handshake:Maybe<&2,T.Timer>
  for +drain:Maybe<&2,T.Timer>
  for +admission:Bool
  for +offer:U32
  {T.incoming_selected(True{},T.State{T.Connected{connection,peer},next,epoch,rows,writer,handshake,drain,admission},offer) == T.Out{T.State{T.Connected{connection,peer},next,epoch,rows,writer,handshake,drain,admission},[T.Refuse{offer}]} : T.Out}
law denied_offer_refused:
  for +state:T.State
  for +offer:U32
  {T.incoming_selected(False{},state,offer) == T.Out{state,[T.Refuse{offer}]} : T.Out}
law deadlines_exact:
  ({T.duration(T.Handshake{}) == 45000 : U32} & ({T.duration(T.Drain{}) == 20000 : U32} & {T.duration(T.GuestDrain{}) == 25000 : U32}))
law unmatched_deadline_preserves:
  for +state:T.State
  for now:Nat
  {T.deadline_selected(False{},False{},state,now) == T.Out{state,[]} : T.Out}
law native_completion_has_no_receipt_effect:
  for +success:Bool
  {T.write_reason(success) == Bool.pick(T.Reason,success,T.NoError{},T.NativeFailure{}) : T.Reason}
law terminal_closes_future_admission:
  for +next:U32
  for +epoch:U32
  for +rows:List<&2,T.Pending>
  for +writer:Maybe<&2,T.Writer>
  for +handshake:Maybe<&2,T.Timer>
  for +drain:Maybe<&2,T.Timer>
  for +admission:Bool
  for lobby:L.State
  for seat:U32
  {T.incoming_allowed(out_state(T.room(T.State{T.Available{},next,epoch,rows,writer,handshake,drain,admission},True{},lobby,seat))) == False{} : Bool}
law terminal_keeps_connected_drain:
  for +connection:U32
  for +peer:String
  for +next:U32
  for +epoch:U32
  for +rows:List<&2,T.Pending>
  for +writer:Maybe<&2,T.Writer>
  for +handshake:Maybe<&2,T.Timer>
  for +drain:Maybe<&2,T.Timer>
  for +admission:Bool
  for lobby:L.State
  for seat:U32
  {T.room(T.State{T.Connected{connection,peer},next,epoch,rows,writer,handshake,drain,admission},True{},lobby,seat) == T.Out{T.State{T.Connected{connection,peer},next,epoch,rows,writer,handshake,drain,False{}},[]} : T.Out}
law idle_disconnect_preserves:
  for +next:U32
  for +epoch:U32
  for +admission:Bool
  {T.disconnect(T.State{T.Available{},next,epoch,[],None{},None{},None{},admission}) == T.Out{T.State{T.Available{},next,epoch,[],None{},None{},None{},admission},[]} : T.Out}
law overflow_disconnect_closes:
  for +state:T.State
  {T.disconnect_selected(False{},state) == T.close(state,T.IdentifierExhausted{}) : T.Out}
law roles_exact:
  ({T.host_role(T.HostEndpoint{}) == True{} : Bool} & {T.host_role(T.GuestEndpoint{}) == False{} : Bool})
law guest_endpoint_refuses_offer:
  for +offer:U32
  {T.step(T.State{T.Available{},2,0,[],None{},None{},None{},False{}},T.Incoming{offer},0n) == T.Out{T.State{T.Available{},2,0,[],None{},None{},None{},False{}},[T.Refuse{offer}]} : T.Out}
law full_message_budget_refuses:
  for +connection:U32
  for +peer:String
  for +row:T.Pending
  for +writer:T.Writer
  {T.can_send(T.State{T.Connected{connection,peer},0,0,[row,row,row,row,row,row,row,row,row,row,row,row,row,row,row],Some{writer},None{},None{},True{}},0) == False{} : Bool}
law full_byte_budget_refuses:
  for +connection:U32
  for +peer:String
  {T.can_send(T.State{T.Connected{connection,peer},0,0,[T.Pending{1,1048576,False{}},T.Pending{2,1048576,False{}},T.Pending{3,1048576,False{}}],Some{T.Writer{4,connection,T.Pending{4,1048576,False{}}}},None{},None{},True{}},1) == False{} : Bool}
law maximum_frame_admitted:
  for connection:U32
  for peer:String
  {T.can_send(T.State{T.Connected{connection,peer},0,0,[],None{},None{},None{},True{}},1048576) == True{} : Bool}
law oversized_frame_refused:
  for connection:U32
  for peer:String
  {T.can_send(T.State{T.Connected{connection,peer},0,0,[],None{},None{},None{},True{}},1048577) == False{} : Bool}

law disconnect_retains_room_drain:
  for +connection:U32
  for +peer:String
  for +next:U32
  for +drain:Maybe<&2,T.Timer>
  {out_state(T.disconnect_selected(True{},T.State{T.Connected{connection,peer},next,1,[],None{},None{},drain,False{}})) == T.State{T.Available{},next,2,[],None{},None{},drain,False{}} : T.State}

law guest_creation_keeps_attempt_budget:
  for +state:T.State
  {T.endpoint_ready(T.GuestEndpoint{},state) == T.Out{state,[]} : T.Out}
