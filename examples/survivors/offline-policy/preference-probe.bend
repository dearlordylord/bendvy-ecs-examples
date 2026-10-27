import Base
import ./preference.bend as N
import ../offline-policy.bend as P
import ../offline-threats.bend as T

def goal(kind:U32,generation:U32,x:F32) -> P.Goal: P.Goal{41,generation,kind,x,100.0,5.0,P.Point{100.0,100.0}}
def choice(kind:U32) -> P.Choice: P.Choice{goal(kind,1,260.0),[P.Point{260.0,100.0}],1.0}
def preferred(kind:U32) -> N.Navigation: N.Navigation{P.initial(),Some{N.Preferred{choice(kind),7}}}
def pinned_cardinal() -> {N.live_goal(goal(13,1,260.0),[goal(13,1,999.0)]) == Some{goal(13,1,260.0)} : Maybe<&2,P.Goal>}: {==}
def live_xp_refresh() -> {N.live_goal(goal(2,1,260.0),[goal(2,1,290.0)]) == Some{goal(2,1,290.0)} : Maybe<&2,P.Goal>}: {==}
def recycled_xp_disappears() -> {N.live_goal(goal(2,1,260.0),[goal(2,2,260.0)]) == None{} : Maybe<&2,P.Goal>}: {==}
def collected_chest_disappears() -> {N.live_goal(goal(5,1,260.0),[]) == None{} : Maybe<&2,P.Goal>}: {==}
def collected_relic_disappears() -> {N.live_goal(goal(9,1,260.0),[]) == None{} : Maybe<&2,P.Goal>}: {==}
def xp_near_is_not_collected() -> {N.reached(goal(2,1,100.0),P.Point{100.0,100.0}) == False{} : Bool}: {==}
def chest_near_is_not_collected() -> {N.reached(goal(5,1,100.0),P.Point{100.0,100.0}) == False{} : Bool}: {==}
def relic_near_is_not_collected() -> {N.reached(goal(9,1,100.0),P.Point{100.0,100.0}) == False{} : Bool}: {==}
def same_pick_preserves_age() -> {N.step(preferred(13),N.Pick{0}) == preferred(13) : N.Navigation}: {==}
def invalid_pick_preserves() -> {N.step(preferred(13),N.Pick{99}) == preferred(13) : N.Navigation}: {==}
def default_preserves_policy() -> {N.step(preferred(13),N.Default{}) == N.Navigation{P.initial(),None{}} : N.Navigation}: {==}
def empty_waypoint_needs_route() -> {N.waypoint_danger(None{},[]) == True{} : Bool}: {==}
def route_age_29_cached() -> {N.replan_due(N.Preferred{choice(13),1},30,P.initial(),P.initial(),[]) == False{} : Bool}: {==}
def route_age_30_due() -> {N.replan_due(N.Preferred{choice(13),1},31,P.initial(),P.initial(),[]) == True{} : Bool}: {==}
