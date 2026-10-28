import Base
import ./coop-transport-policy.bend as T
import ./coop-transport-policy-LAWS.bend as L

def L.budgets_exact(): (({==},{==}),({==},({==},{==})))
def L.fresh_empty(): ({==},{==})
def L.close_idempotent(next,epoch,admission): {==}
def L.closing_discards_queued_bytes(state,reason):
  match state:
    case T.State{_,_,_,_,_,_,_,_}: {==}
def L.closing_discards_queued_messages(state,reason):
  match state:
    case T.State{_,_,_,_,_,_,_,_}: {==}
def L.stale_write_outcome_preserves(state,success): {==}
def L.stale_attempt_failure_preserves(state): {==}
def L.duplicate_connection_preserves(state,operation,connection,peer): {==}
def L.stale_success_disposes_its_connection(state,connection,peer): {==}
def L.rejected_message_never_notifies(state,request,peer): {==}
def L.stale_departure_preserves(state): {==}
def L.refused_enqueue_preserves(state,request,bytes,confirm):
  match state:
    case T.State{_,_,_,_,_,_,_,_}: {==}
def L.writer_prevents_another_write(connection,peer,next,epoch,rows,writer,handshake,drain,admission):
  match rows:
    case []: {==}
    case T.Pending{_,_,_} <> _: {==}
def L.busy_offer_refused(connection,peer,next,epoch,rows,writer,handshake,drain,admission,offer): {==}
def L.denied_offer_refused(state,offer): {==}
def L.deadlines_exact(): ({==},({==},{==}))
def L.unmatched_deadline_preserves(state,now): {==}
def L.native_completion_has_no_receipt_effect(success):
  match success:
    case False{}: {==}
    case True{}: {==}
def L.terminal_closes_future_admission(next,epoch,rows,writer,handshake,drain,admission,lobby,seat): {==}
def L.terminal_keeps_connected_drain(connection,peer,next,epoch,rows,writer,handshake,drain,admission,lobby,seat): {==}
def L.idle_disconnect_preserves(next,epoch,admission): {==}
def L.overflow_disconnect_closes(state): {==}
def L.roles_exact(): ({==},{==})
def L.guest_endpoint_refuses_offer(offer): {==}
def L.full_message_budget_refuses(connection,peer,row,writer): {==}
def L.full_byte_budget_refuses(connection,peer): {==}
def L.maximum_frame_admitted(connection,peer): {==}
def L.oversized_frame_refused(connection,peer): {==}

def L.disconnect_retains_room_drain(connection,peer,next,drain): {==}

def L.guest_creation_keeps_attempt_budget(state): {==}
def L.waiting_offer_budget_exact(): {==}
def L.accepting_retains_another_offer(operation,current,offer): {==}
def L.full_offer_budget_refuses(operation,current,waiting,offer): {==}
def L.failed_accept_tries_oldest(operation,current,offer,waiting): {==}
def L.authenticated_accept_refuses_waiting(operation,current,waiting,connection,peer): {==}
def L.cancelled_accept_refuses_waiting(operation,current,waiting):
  match waiting:
    case Nil{}: {==}
    case Con{offer,rest}: Equal.cong(List<&2,T.Effect>,List<&2,T.Effect>,effects => T.Refuse{offer} <> effects,List.append(&2,T.Effect,List.append(&2,T.Effect,T.refused_offers(rest),[]),[]),List.append(&2,T.Effect,T.refused_offers(rest),[]),L.cancelled_accept_refuses_waiting(operation,current,rest))
