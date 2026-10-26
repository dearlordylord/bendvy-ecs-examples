import Base
import ./stream-session.bend as C

def identity() -> C.Identity: C.Identity{1n,2n,3n,4n,5n,1}
def advice() -> C.State: C.State{identity(),C.Advice{3,2,2,False{}},False{},10n,0n,5n,15n,40n}
def dwell() -> C.State: C.State{identity(),C.Dwell{3,1},False{},10n,4n,5n,15n,40n}
def out_state(out:C.Out) -> C.State:
  match out:
    case C.Out{state,_,_}: state
def effect(out:C.Out) -> C.Effect:
  match out:
    case C.Out{_,effect,_}: effect
def accepted(out:C.Out) -> Bool:
  match out:
    case C.Out{_,_,accepted}: accepted

def current_reply_provisional() -> {accepted(C.step(advice(),C.Reply{identity(),0,12n})) == True{} : Bool}: {==}
def expired_without_frame() -> {accepted(C.step(advice(),C.Reply{identity(),0,15n})) == False{} : Bool}: {==}
def stale_run_reply() -> {accepted(C.step(advice(),C.Reply{C.Identity{1n,9n,3n,4n,5n,1},0,12n})) == False{} : Bool}: {==}
def stale_generation_reply() -> {accepted(C.step(advice(),C.Reply{C.Identity{1n,2n,3n,9n,5n,1},0,12n})) == False{} : Bool}: {==}
def invalid_offer_reply() -> {accepted(C.step(advice(),C.Reply{identity(),3,12n})) == False{} : Bool}: {==}
def early_dwell_no_commit() -> {effect(C.step(dwell(),C.Frame{20n})) == C.Idle{} : C.Effect}: {==}
def full_dwell_commits() -> {effect(C.step(dwell(),C.Frame{21n})) == C.Commit{1} : C.Effect}: {==}
def committed_no_second_commit() -> {effect(C.step(out_state(C.step(dwell(),C.Frame{21n})),C.Frame{21n})) == C.Idle{} : C.Effect}: {==}
def long_pause_no_commit() -> {effect(C.step(out_state(C.step(dwell(),C.Pause{11n})),C.Frame{120n})) == C.Idle{} : C.Effect}: {==}
def resumed_remaining_dwell() -> {effect(C.step(out_state(C.step(out_state(C.step(dwell(),C.Pause{11n})),C.Resume{120n})),C.Frame{129n})) == C.Idle{} : C.Effect}: {==}
def resumed_deadline_commits() -> {effect(C.step(out_state(C.step(out_state(C.step(dwell(),C.Pause{11n})),C.Resume{120n})),C.Frame{130n})) == C.Commit{1} : C.Effect}: {==}
def paused_old_reply_rejected() -> {accepted(C.step(out_state(C.step(out_state(C.step(advice(),C.Pause{11n})),C.Resume{120n})),C.Reply{identity(),0,120n})) == False{} : Bool}: {==}
def frozen_late_reply_rejected() -> {accepted(C.step(dwell(),C.Reply{identity(),0,10n})) == False{} : Bool}: {==}
def frozen_reload_deferred() -> {accepted(C.step(dwell(),C.Activate{9n})) == False{} : Bool}: {==}
def stopped_never_restarts() -> {effect(C.step(out_state(C.step(out_state(C.step(dwell(),C.Stop{})),C.Ended{11n})),C.Frame{120n})) == C.Idle{} : C.Effect}: {==}
def between() -> C.State: C.State{identity(),C.BetweenRuns{},False{},10n,0n,5n,15n,40n}
def next_run_once() -> {effect(C.step(between(),C.Frame{50n})) == C.NextRun{} : C.Effect}: {==}
def next_run_not_twice() -> {effect(C.step(out_state(C.step(between(),C.Frame{50n})),C.Frame{50n})) == C.Idle{} : C.Effect}: {==}
def movement() -> C.State: C.State{identity(),C.Playing{},False{},10n,0n,5n,15n,40n}
def movement_reply_current() -> {accepted(C.step(movement(),C.MovementReply{identity(),0,2,12n})) == True{} : Bool}: {==}
def movement_reply_stale() -> {accepted(C.step(movement(),C.MovementReply{C.Identity{1n,2n,2n,4n,5n,1},0,2,12n})) == False{} : Bool}: {==}
def movement_reply_expired() -> {accepted(C.step(movement(),C.MovementReply{identity(),0,2,15n})) == False{} : Bool}: {==}
def movement_reply_not_twice() -> {accepted(C.step(out_state(C.step(movement(),C.MovementReply{identity(),0,2,12n})),C.MovementReply{identity(),1,2,12n})) == False{} : Bool}: {==}
