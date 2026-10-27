import Base
import ./stream-session.bend as C
import ./stream-session-LAWS.bend as L

def L.paused_no_movement(id,mode,last,elapsed,a,d,b): {==}
def L.paused_no_effect(id,mode,last,elapsed,a,d,b):
  match mode:
    case C.Stopped{}: {==}
    case C.Playing{}: {==}
    case C.Advice{count,fallback,index,received}: {==}
    case C.Dwell{count,index}: {==}
    case C.Committed{}: {==}
    case C.BetweenRuns{}: {==}
def L.paused_elapsed(elapsed,now,last): {==}
def L.running_elapsed(elapsed,now,last): {==}
def L.admission_exact(expected,claimed,index,count,paused,elapsed,cutoff): {==}
def L.identity_exact(s,r,q,g,decision,phase,t,u,v,h,e,p): {==}
def L.rejected_reply_unchanged(state,index): {==}
def L.advice_received(id,count,fallback,previous,received,paused,last,elapsed,a,d,b,index): {==}
def L.freeze_starts_full_dwell(id,count,fallback,index,received,paused,last,elapsed,a,d,b): {==}
def L.frozen_reply_ignored(id,count,index,paused,last,elapsed,a,d,b,claimed,choice): {==}
def L.dwell_gate(id,count,index,last,elapsed,a,d,b): {==}
def L.early_commit_refused(state): {==}
def L.commit_leaves_dwell(id,count,index,paused,last,elapsed,a,d,b): {==}
def L.committed_no_duplicate(id,paused,last,elapsed,a,d,b):
  match paused:
    case True{}: {==}
    case False{}: {==}
def L.dwell_defers_activation(id,count,index,paused,last,elapsed,a,d,b,generation):
  match paused:
    case True{}: {==}
    case False{}: {==}
def L.pause_invalidates(id,mode,paused,last,elapsed,a,d,b): {==}
def L.stop_invalidates(id,mode,paused,last,elapsed,a,d,b): {==}
def L.stopped_end_ignored(id,paused,last,elapsed,a,d,b,now): {==}
def L.restart_once(id,paused,last,elapsed,a,d,b): {==}
def L.stopped_no_effect(id,paused,last,elapsed,a,d,b):
  match paused:
    case True{}: {==}
    case False{}: {==}
def L.step_frame_clock(state,now): {==}
def L.step_reply_clock(state,id,index,now): {==}
def L.step_movement_clock(state,id,index,count,now): {==}
def L.step_pause_clock(state,now): {==}
def L.step_resume_clock(state,now): {==}
def L.resume_remaining(id,mode,paused,last,elapsed,a,d,b,now): {==}
def L.reply_admission_exact(id,count,fallback,previous,received,paused,last,elapsed,a,d,b,claimed,index): {==}
def L.movement_admission_exact(id,paused,last,elapsed,a,d,b,claimed,index,count): {==}
def L.advice_cutoff_gate(id,count,fallback,index,received,last,elapsed,a,d,b): {==}
def L.paused_activation_refused(id,mode,last,elapsed,a,d,b,generation): {==}
def L.offer_identity_reset(s,r,q,g,oldDecision,oldPhase,mode,paused,last,elapsed,a,d,b,decision,phase,count,fallback,now): {==}
def L.step_offers_boundary(state,decision,phase,count,fallback,now): {==}
def L.offers_admission_exact(s,r,q,g,oldDecision,oldPhase,mode,paused,last,elapsed,a,d,b,decision,phase,count,fallback,now): {==}
def L.stopped_offers_ignored(id,paused,last,elapsed,a,d,b,decision,phase,count,fallback,now):
  match id:
    case C.Identity{s,r,q,g,oldDecision,oldPhase}: {==}
