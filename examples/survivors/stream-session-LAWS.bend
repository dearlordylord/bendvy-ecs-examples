import Base
import ./stream-session.bend as C

# Guarantees: Paused sessions cannot advance movement regardless of mode or clock.
# Why it matters: A queued animation callback must not move a paused recording.
law paused_no_movement:
  for id:C.Identity for mode:C.Mode for last:Nat for elapsed:Nat for a:Nat for d:Nat for b:Nat
  {C.can_move(C.State{id,mode,True{},last,elapsed,a,d,b}) == False{} : Bool}

# Guarantees: Paused presentation frames retain elapsed dwell and emit no action.
# Why it matters: Waiting while the operator pauses cannot confirm an upgrade.
law paused_no_effect:
  for +id:C.Identity for +mode:C.Mode for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.frame(C.State{id,mode,True{},last,elapsed,a,d,b}) == C.Out{C.State{id,mode,True{},last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}

# Guarantees: No presentation time accumulates while paused.
# Why it matters: A hidden tab must resume with its recommendation wait remaining.
law paused_elapsed:
  for +elapsed:Nat for now:Nat for last:Nat
  {C.elapsed_when(True{},elapsed,now,last) == elapsed : Nat}

# Guarantees: Active elapsed time adds only the nonnegative monotonic clock delta.
# Why it matters: An out-of-order clock observation cannot rewind or double count dwell.
law running_elapsed:
  for +elapsed:Nat for +now:Nat for +last:Nat
  {C.elapsed_when(False{},elapsed,now,last) == Nat.add(elapsed,Nat.sub(Bool.pick(Nat,Nat.is_ge(now,last),now,last),last)) : Nat}

# Guarantees: Advice admission requires exact identity, a legal index, active playback and time before cutoff.
# Why it matters: Late Worker messages after a new run or replacement cannot select an upgrade.
law admission_exact:
  for +expected:C.Identity for +claimed:C.Identity for +index:U32 for +count:U32 for +paused:Bool for +elapsed:Nat for +cutoff:Nat
  {C.reply_allowed(expected,claimed,index,count,paused,elapsed,cutoff) == Bool.and(Bool.not(paused),Bool.and(C.same_id(expected,claimed),Bool.and(U32.is_lt(index,count),Nat.is_lt(elapsed,cutoff)))) : Bool}

# Guarantees: All six identity fields participate in reply matching.
# Why it matters: A matching request number alone cannot revive old-run advice.
law identity_exact:
  for +s:Nat for +r:Nat for +q:Nat for +g:Nat for +decision:Nat for +phase:U32
  for +t:Nat for +u:Nat for +v:Nat for +h:Nat for +e:Nat for +p:U32
  {C.same_id(C.Identity{s,r,q,g,decision,phase},C.Identity{t,u,v,h,e,p}) == Bool.and(Nat.is_eq(s,t),Bool.and(Nat.is_eq(r,u),Bool.and(Nat.is_eq(q,v),Bool.and(Nat.is_eq(g,h),Bool.and(Nat.is_eq(decision,e),U32.is_eq(phase,p)))))) : Bool}

# Guarantees: A rejected reply retains every state field and emits no action.
# Why it matters: An invalid offer must not replace an already considered recommendation.
law rejected_reply_unchanged:
  for +state:C.State for index:U32
  {C.reply_decided(False{},state,index) == C.Out{state,C.Idle{},False{}} : C.Out}

# Guarantees: Advice accepted before cutoff changes only the provisional recommendation.
# Why it matters: Receiving a Worker result must not bypass the visible recommendation dwell.
law advice_received:
  for +id:C.Identity for +count:U32 for +fallback:U32 for previous:U32 for received:Bool for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for +index:U32
  {C.reply_decided(True{},C.State{id,C.Advice{count,fallback,previous,received},paused,last,elapsed,a,d,b},index) == C.Out{C.State{id,C.Advice{count,fallback,index,True{}},paused,last,elapsed,a,d,b},C.Idle{},True{}} : C.Out}

# Guarantees: The advice cutoff begins a fresh full dwell for the frozen legal recommendation.
# Why it matters: A delayed render callback cannot consume recommendation display time before it appeared.
law freeze_starts_full_dwell:
  for +id:C.Identity for +count:U32 for fallback:U32 for +index:U32 for received:Bool for +paused:Bool for +last:Nat for elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.freeze_decided(True{},C.State{id,C.Advice{count,fallback,index,received},paused,last,elapsed,a,d,b}) == C.Out{C.State{id,C.Dwell{count,index},paused,last,0n,a,d,b},C.Idle{},True{}} : C.Out}

# Guarantees: Replies cannot alter a frozen recommendation even if their identity matches.
# Why it matters: A slow strategy must not make the highlighted choice jump during dwell.
law frozen_reply_ignored:
  for +id:C.Identity for +count:U32 for +index:U32 for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for claimed:C.Identity for choice:U32
  {C.reply(C.State{id,C.Dwell{count,index},paused,last,elapsed,a,d,b},claimed,choice) == C.Out{C.State{id,C.Dwell{count,index},paused,last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}

# Guarantees: Every active dwell frame checks both offer membership and minimum display duration.
# Why it matters: The render loop cannot bypass the presentation gate or choose an unavailable offer.
law dwell_gate:
  for +id:C.Identity for +count:U32 for +index:U32 for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.frame(C.State{id,C.Dwell{count,index},False{},last,elapsed,a,d,b}) == C.commit_decided(Bool.and(U32.is_lt(index,count),Nat.is_ge(elapsed,d)),C.State{id,C.Dwell{count,index},False{},last,elapsed,a,d,b}) : C.Out}

# Guarantees: Before the dwell gate permits commitment, the whole state remains unchanged.
# Why it matters: An early animation callback cannot confirm an upgrade.
law early_commit_refused:
  for +state:C.State
  {C.commit_decided(False{},state) == C.Out{state,C.Idle{},False{}} : C.Out}

# Guarantees: A permitted commitment invalidates advice and leaves the dwell mode once.
# Why it matters: Repeated frames must not apply the same upgrade twice.
law commit_leaves_dwell:
  for +id:C.Identity for count:U32 for +index:U32 for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.commit_decided(True{},C.State{id,C.Dwell{count,index},paused,last,elapsed,a,d,b}) == C.Out{C.State{C.new_request(id),C.Committed{},paused,last,elapsed,a,d,b},C.Commit{index},True{}} : C.Out}

# Guarantees: Subsequent frames in committed mode cannot emit another choice.
# Why it matters: A delayed game acknowledgement must not duplicate a reward.
law committed_no_duplicate:
  for +id:C.Identity for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.frame(C.State{id,C.Committed{},paused,last,elapsed,a,d,b}) == C.Out{C.State{id,C.Committed{},paused,last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}

# Guarantees: Strategy activation is deferred throughout frozen recommendation dwell.
# Why it matters: Hot reload cannot invalidate a visible choice before its one commitment.
law dwell_defers_activation:
  for +id:C.Identity for +count:U32 for +index:U32 for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for generation:Nat
  {C.activate(C.State{id,C.Dwell{count,index},paused,last,elapsed,a,d,b},generation) == C.Out{C.State{id,C.Dwell{count,index},paused,last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}

# Guarantees: Pausing invalidates prior requests while preserving the presentation mode and elapsed dwell.
# Why it matters: Advice queued before operator pause must not commit on resume.
law pause_invalidates:
  for +id:C.Identity for +mode:C.Mode for paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.pause_clocked(C.State{id,mode,paused,last,elapsed,a,d,b}) == C.Out{C.State{C.new_request(id),mode,True{},last,elapsed,a,d,b},C.Idle{},True{}} : C.Out}

# Guarantees: Stopping discards pending presentation and invalidates advice without a commit or restart.
# Why it matters: Closing a stream must not leave a hidden new-run timer alive.
law stop_invalidates:
  for +id:C.Identity for mode:C.Mode for paused:Bool for +last:Nat for elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.stop(C.State{id,mode,paused,last,elapsed,a,d,b}) == C.Out{C.State{C.new_request(id),C.Stopped{},False{},last,0n,a,d,b},C.Idle{},True{}} : C.Out}

# Guarantees: A delayed terminal notification cannot restart a stopped session.
# Why it matters: Stopping between game callbacks must remain stopped.
law stopped_end_ignored:
  for +id:C.Identity for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for now:Nat
  {C.ended(C.State{id,C.Stopped{},paused,last,elapsed,a,d,b},now) == C.Out{C.State{id,C.Stopped{},paused,last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}

# Guarantees: The between-run wait emits one restart and moves to stopped mode.
# Why it matters: Several callbacks at the deadline cannot start multiple worlds.
law restart_once:
  for +id:C.Identity for +paused:Bool for +last:Nat for elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.next_decided(True{},C.State{id,C.BetweenRuns{},paused,last,elapsed,a,d,b}) == C.Out{C.State{C.new_request(id),C.Stopped{},paused,last,0n,a,d,b},C.NextRun{},True{}} : C.Out}

# Guarantees: A stopped presentation frame emits neither a restart nor a choice.
# Why it matters: An already queued frame after stopping cannot resume the stream.
law stopped_no_effect:
  for +id:C.Identity for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.frame(C.State{id,C.Stopped{},paused,last,elapsed,a,d,b}) == C.Out{C.State{id,C.Stopped{},paused,last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}

# Guarantees: The production frame boundary advances the presentation clock before evaluating effects.
# Why it matters: A stopped gameplay tick cannot prevent recommendation dwell from finishing.
law step_frame_clock:
  for +state:C.State for +now:Nat
  {C.step(state,C.Frame{now}) == C.frame(C.clock(state,now)) : C.Out}

# Guarantees: Production advice admission samples presentation time before checking expiry.
# Why it matters: A Worker response arriving after cutoff must not exploit a missing frame callback.
law step_reply_clock:
  for +state:C.State for +id:C.Identity for +index:U32 for +now:Nat
  {C.step(state,C.Reply{id,index,now}) == C.reply(C.clock(state,now),id,index) : C.Out}

# Guarantees: Production movement advice uses the same current presentation clock.
# Why it matters: Late movement advice cannot reuse a deadline from its previous callback.
law step_movement_clock:
  for +state:C.State for +id:C.Identity for +index:U32 for +count:U32 for +now:Nat
  {C.step(state,C.MovementReply{id,index,count,now}) == C.movement_reply(C.clock(state,now),id,index,count) : C.Out}

# Guarantees: Production pause first credits the active interval and then freezes it.
# Why it matters: Pausing halfway through visible dwell must preserve that elapsed portion.
law step_pause_clock:
  for +state:C.State for +now:Nat
  {C.step(state,C.Pause{now}) == C.pause_clocked(C.clock(state,now)) : C.Out}

# Guarantees: Production resume uses the resume transition rather than spending the hidden interval.
# Why it matters: A long operator pause cannot expire the remaining recommendation dwell.
law step_resume_clock:
  for +state:C.State for +now:Nat
  {C.step(state,C.Resume{now}) == C.resume(state,now) : C.Out}

# Guarantees: Resume retains mode and elapsed time, renews request identity and resets the clock anchor.
# Why it matters: The remaining visible wait survives a pause and prior replies become stale.
law resume_remaining:
  for +id:C.Identity for +mode:C.Mode for paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for +now:Nat
  {C.resume(C.State{id,mode,paused,last,elapsed,a,d,b},now) == C.Out{C.State{C.new_request(id),mode,False{},C.latest(now,last),elapsed,a,d,b},C.Idle{},True{}} : C.Out}

# Guarantees: Actual advice handling uses the complete admission gate before setting a provisional choice.
# Why it matters: A stale response cannot bypass admission merely by reaching the upgrade handler.
law reply_admission_exact:
  for +id:C.Identity for +count:U32 for +fallback:U32 for +previous:U32 for +received:Bool for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for +claimed:C.Identity for +index:U32
  {C.reply(C.State{id,C.Advice{count,fallback,previous,received},paused,last,elapsed,a,d,b},claimed,index) == C.reply_decided(Bool.and(Bool.not(paused),Bool.and(C.same_id(id,claimed),Bool.and(U32.is_lt(index,count),Nat.is_lt(elapsed,a)))),C.State{id,C.Advice{count,fallback,previous,received},paused,last,elapsed,a,d,b},index) : C.Out}

# Guarantees: Actual movement reply handling checks identity, expiry and goal membership before invalidating the request.
# Why it matters: A delayed goal selection after reload cannot redirect the bot.
law movement_admission_exact:
  for +id:C.Identity for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for +claimed:C.Identity for +index:U32 for +count:U32
  {C.movement_reply(C.State{id,C.Playing{},paused,last,elapsed,a,d,b},claimed,index,count) == C.activate_decided(Bool.and(Bool.not(paused),Bool.and(C.same_id(id,claimed),Bool.and(U32.is_lt(index,count),Nat.is_lt(elapsed,a)))),C.State{id,C.Playing{},paused,last,elapsed,a,d,b},C.identity_generation(id)) : C.Out}

# Guarantees: Advice freezes only after its own presentation cutoff.
# Why it matters: Gameplay phase changes cannot replace the independent advice window.
law advice_cutoff_gate:
  for +id:C.Identity for +count:U32 for +fallback:U32 for +index:U32 for +received:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat
  {C.frame(C.State{id,C.Advice{count,fallback,index,received},False{},last,elapsed,a,d,b}) == C.freeze_decided(Nat.is_ge(elapsed,a),C.State{id,C.Advice{count,fallback,index,received},False{},last,elapsed,a,d,b}) : C.Out}

# Guarantees: Paused sessions cannot activate a prepared strategy generation.
# Why it matters: Operator pause must not silently replace pending decision identity.
law paused_activation_refused:
  for +id:C.Identity for +mode:C.Mode for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for generation:Nat
  {C.activate(C.State{id,mode,True{},last,elapsed,a,d,b},generation) == C.Out{C.State{id,mode,True{},last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}

# Guarantees: Starting a new offered decision renews identity and begins with a legal fallback recommendation.
# Why it matters: Replacing an offer set must not reuse the previous set's chosen index.
law offer_identity_reset:
  for +s:Nat for +r:Nat for +q:Nat for +g:Nat for oldDecision:Nat for oldPhase:U32 for mode:C.Mode for +paused:Bool for last:Nat for elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for +decision:Nat for +phase:U32 for +count:U32 for +fallback:U32 for +now:Nat
  {C.begin_offers(C.State{C.Identity{s,r,q,g,oldDecision,oldPhase},mode,paused,last,elapsed,a,d,b},decision,phase,count,fallback,now) == C.Out{C.State{C.Identity{s,r,Nat.add(q,1n),g,decision,phase},C.Advice{count,C.valid_fallback(count,fallback),C.valid_fallback(count,fallback),False{}},paused,now,0n,a,d,b},C.Idle{},True{}} : C.Out}

# Guarantees: Production offer events use the offer freshness and legality boundary.
# Why it matters: The host cannot accidentally skip new-offer admission when replacing a phase.
law step_offers_boundary:
  for +state:C.State for +decision:Nat for +phase:U32 for +count:U32 for +fallback:U32 for +now:Nat
  {C.step(state,C.Offers{decision,phase,count,fallback,now}) == C.offers(state,decision,phase,count,fallback,now) : C.Out}

# Guarantees: Offered decisions require a live mode, a newer serial, a nonempty set and an upgrade phase.
# Why it matters: A queued old offer notification cannot reopen a stopped session or reset frozen dwell.
law offers_admission_exact:
  for +s:Nat for +r:Nat for +q:Nat for +g:Nat for +oldDecision:Nat for +oldPhase:U32 for +mode:C.Mode for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for +decision:Nat for +phase:U32 for +count:U32 for +fallback:U32 for +now:Nat
  {C.offers(C.State{C.Identity{s,r,q,g,oldDecision,oldPhase},mode,paused,last,elapsed,a,d,b},decision,phase,count,fallback,now) == C.offers_decided(Bool.and(C.offer_mode(mode),Bool.and(Nat.is_gt(decision,oldDecision),Bool.and(U32.is_gt(count,0),Bool.or(U32.is_eq(phase,1),U32.is_eq(phase,2))))),C.State{C.Identity{s,r,q,g,oldDecision,oldPhase},mode,paused,last,elapsed,a,d,b},decision,phase,count,fallback,now) : C.Out}

# Guarantees: Stopped sessions reject all offered-decision notifications.
# Why it matters: An asynchronous menu observation after stop cannot restart presentation.
law stopped_offers_ignored:
  for +id:C.Identity for +paused:Bool for +last:Nat for +elapsed:Nat for +a:Nat for +d:Nat for +b:Nat for decision:Nat for phase:U32 for count:U32 for fallback:U32 for now:Nat
  {C.offers(C.State{id,C.Stopped{},paused,last,elapsed,a,d,b},decision,phase,count,fallback,now) == C.Out{C.State{id,C.Stopped{},paused,last,elapsed,a,d,b},C.Idle{},False{}} : C.Out}
