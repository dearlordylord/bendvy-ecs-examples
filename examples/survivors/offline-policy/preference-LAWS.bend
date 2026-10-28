import Base
import ./preference.bend as Nav
import ../offline-policy.bend as P
import ../game-observation.bend as G
import ../stream-bot.bend as Bot
import ../offline-threats.bend as T
import ../projectile-state.bend as Shot
import ../enemy-combat.bend as Enemy
import ../enemy-spatial.bend as Space
import ../game-components.bend as C
import ../pickup-state.bend as Pickup


def plan_reference(memory:Bot.Memory,+run:G.Run,offers:List<&2,G.Offer>,+snapshots:List<&2,G.Snapshot>,width:F32,height:F32) -> Bot.Planned:
  match memory:
    case Bot.Memory{navigation,old}:
      +view : Bot.View = Bot.View{G.run_px(run),G.run_py(run),(width / 2.0 : F32),(height / 2.0 : F32)}
      +enemies=Bot.seen(snapshots,view,0,128,[])
      +shots=Bot.seen(snapshots,view,1,64,[])
      +items=Bot.seen(snapshots,view,2,128,[])
      +visible=List.append(&2,G.Snapshot,enemies,List.append(&2,G.Snapshot,shots,items))
      +fresh=Bot.pickups(visible,128,[])
      +knowledge=Bot.known(old,view,(128 - U32.from_nat(List.length(&2,G.Snapshot,fresh)) : U32),fresh)
      Bot.planned(navigation,run,offers,visible,knowledge,Bool.or(Nat.is_ge(List.length(&2,G.Snapshot,enemies),128n),Bool.or(Nat.is_ge(List.length(&2,G.Snapshot,shots),64n),Bool.or(Nat.is_ge(List.length(&2,G.Snapshot,items),128n),Nat.is_ge(List.length(&2,G.Snapshot,knowledge),128n)))),view)

# Guarantees: The public host entrypoint uses the bounded observer projection and the preference-aware planned path.
# Why it matters: An unused correct helper chain cannot hide Bot.plan bypassing requested goals.
law public_plan_composition:
  for +memory:Bot.Memory for +run:G.Run for +offers:List<&2,G.Offer> for +rows:List<&2,G.Snapshot> for +width:F32 for +height:F32
  {Bot.plan(memory,run,offers,rows,width,height) == plan_reference(memory,run,offers,rows,width,height) : Bot.Planned}

# Guarantees: A fresh navigation session has no preferred goal and native initial state.
# Why it matters: Starting a new streamed run cannot reuse the previous run's destination.
law initial_empty:
  {Nav.initial() == Nav.Navigation{P.initial(),None{}} : Nav.Navigation}

# Guarantees: Default clears only preference, preserving every autonomous policy field.
# Why it matters: Recurring fallback advice must not restart the native planner each half second.
law default_preserves_native:
  for +policy:P.Memory for pref:Maybe<&2,Nav.Preferred>
  {Nav.step(Nav.Navigation{policy,pref},Nav.Default{}) == Nav.Navigation{policy,None{}} : Nav.Navigation}

# Guarantees: Repeated Default is idempotent for the full navigation state.
# Why it matters: Repeated Worker fallback cannot discard warm autonomous history.
law default_idempotent:
  for +nav:Nav.Navigation
  {Nav.step(Nav.step(nav,Nav.Default{}),Nav.Default{}) == Nav.step(nav,Nav.Default{}) : Nav.Navigation}

# Guarantees: An explicit preference supplies the selected choice regardless of autonomous current or score.
# Why it matters: Healthy cardinal advice and lower scoring physical targets must reach movement.
law preferred_selected:
  for policy:P.Memory for +choice:P.Choice for at:U32
  {Nav.selected(Nav.Navigation{policy,Some{Nav.Preferred{choice,at}}}) == Some{choice} : Maybe<&2,P.Choice>}

# Guarantees: Without preference the current warm native choice is selected.
# Why it matters: Routing failure must fall back during the same frame.
law native_selected:
  for +policy:P.Memory
  {Nav.selected(Nav.Navigation{policy,None{}}) == Nav.current(policy) : Maybe<&2,P.Choice>}

# Guarantees: Publication retains the preferred choice first and at most seven distinct native alternatives.
# Why it matters: The current intention remains selectable without exceeding the eight-choice observation limit.
law preferred_choices:
  for +policy:P.Memory for +choice:P.Choice for at:U32
  {Nav.choices(Nav.Navigation{policy,Some{Nav.Preferred{choice,at}}}) == choice <> Nav.take(Nav.remove_same(Nav.candidates(policy),P.choice_goal(choice)),7n) : List<&2,P.Choice>}

# Guarantees: Without preference publication contains at most eight native candidates.
# Why it matters: Worker indices must address the same bounded list as the observation.
law native_choices:
  for +policy:P.Memory
  {Nav.choices(Nav.Navigation{policy,None{}}) == Nav.take(Nav.candidates(policy),8n) : List<&2,P.Choice>}

# Guarantees: Selecting the existing first preferred row preserves route and its planning age exactly.
# Why it matters: Repeated advice for the same goal must not postpone periodic rerouting forever.
law current_pick_idempotent:
  for +policy:P.Memory for +pref:Nav.Preferred
  {Nav.step(Nav.Navigation{policy,Some{pref}},Nav.Pick{0}) == Nav.Navigation{policy,Some{pref}} : Nav.Navigation}

# Guarantees: A missing indexed candidate preserves the entire navigation state.
# Why it matters: An obsolete or out-of-range choice cannot erase an active intention.
law missing_pick_unchanged:
  for +nav:Nav.Navigation
  {Nav.install(nav,None{}) == nav : Nav.Navigation}

# Guarantees: Pick events pass the admitted index to the production picker.
# Why it matters: Observation and selection cannot use unrelated candidate lists.
law pick_wiring:
  for +nav:Nav.Navigation for +index:U32
  {Nav.step(nav,Nav.Pick{index}) == Nav.pick(nav,index) : Nav.Navigation}

# Guarantees: Every Advance warms the original native policy using the same run and snapshots.
# Why it matters: Preferred navigation must not replace or reset autonomous fallback computation.
law advance_native_wiring:
  for +policy:P.Memory for +pref:Maybe<&2,Nav.Preferred> for +run:G.Run for +rows:List<&2,G.Snapshot>
  {Nav.step(Nav.Navigation{policy,pref},Nav.Advance{run,rows}) == Nav.finish_advance(Nav.Navigation{policy,pref},run,rows,P.movement(policy,run,rows)) : Nav.Navigation}

# Guarantees: A cardinal keeps its original endpoint rather than refreshing from a newly centered candidate.
# Why it matters: An east target must not move east again whenever the player advances.
law cardinal_endpoint_pinned:
  for +seed:U32 for +gen:U32 for +x:F32 for +y:F32 for +reward:F32 for +cluster:P.Point for observed:List<&2,P.Goal>
  {Nav.live_goal(P.Goal{seed,gen,13,x,y,reward,cluster},observed) == Some{P.Goal{seed,gen,13,x,y,reward,cluster}} : Maybe<&2,P.Goal>}

# Guarantees: Physical goal availability is exactly the live identity lookup.
# Why it matters: Recycled or collected XP cannot remain a preferred destination.
law physical_identity_lookup:
  for +seed:U32 for +gen:U32 for +x:F32 for +y:F32 for +reward:F32 for +cluster:P.Point for +observed:List<&2,P.Goal>
  {Nav.live_goal(P.Goal{seed,gen,2,x,y,reward,cluster},observed) == P.find_goal(observed,P.Goal{seed,gen,2,x,y,reward,cluster}) : Maybe<&2,P.Goal>}

# Guarantees: XP preference never completes merely because the player is near it.
# Why it matters: XP must be physically collected, not silently released before collection.
law physical_not_proximity_complete:
  for seed:U32 for gen:U32 for x:F32 for y:F32 for reward:F32 for cluster:P.Point for here:P.Point
  {Nav.reached(P.Goal{seed,gen,2,x,y,reward,cluster},here) == False{} : Bool}

# Guarantees: Failed bounded routing releases the preference.
# Why it matters: An unreachable destination cannot suppress autonomous movement indefinitely.
law failed_route_releases:
  for goal:P.Goal for score:F32 for tick:U32 for path:List<&2,P.Point> for length:F32 for risk:F32 for expanded:U32
  {Nav.routed(goal,score,tick,P.Route{False{},path,length,risk,expanded}) == None{} : Maybe<&2,Nav.Preferred>}

# Guarantees: A successful nonempty route retains the resolved goal and records the current planning tick.
# Why it matters: Routing cannot silently replace the requested goal with the autonomous winner.
law successful_route_keeps_goal:
  for +goal:P.Goal for +score:F32 for +tick:U32 for +point:P.Point for +rest:List<&2,P.Point> for length:F32 for risk:F32 for expanded:U32
  {Nav.routed(goal,score,tick,P.Route{True{},point <> rest,length,risk,expanded}) == Some{Nav.Preferred{P.Choice{goal,point <> rest,score},tick}} : Maybe<&2,Nav.Preferred>}

# Guarantees: Stream steering consumes the selected preference and projectile-aware visible threats.
# Why it matters: Accepted goals must affect actual steering while hostile shots still trigger avoidance.
law stream_steering_uses_selected:
  for +nav:Nav.Navigation for +run:G.Run for +rows:List<&2,G.Snapshot>
  {Bot.direction(nav,run,rows) == P.steer(run,Nav.threats(rows,[]),G.enemy_observations(rows),P.target(Nav.selected(nav))) : F32 & F32}

# Guarantees: Choosing through the public stream API preserves discovered pickup memory.
# Why it matters: A strategy change cannot make offscreen discovered XP disappear from knowledge.
law public_choose_wiring:
  for +nav:Nav.Navigation for +pickups:List<&2,G.Snapshot> for +index:U32
  {Bot.choose(Bot.Memory{nav,pickups},index) == Bot.Memory{Nav.step(nav,Nav.Pick{index}),pickups} : Bot.Memory}

# Guarantees: Public fallback clears preference through the same navigation transition.
# Why it matters: Active strategy failure and explicit Default must share fallback semantics.
law public_fallback_wiring:
  for +nav:Nav.Navigation for +pickups:List<&2,G.Snapshot>
  {Bot.fallback(Bot.Memory{nav,pickups}) == Bot.Memory{Nav.step(nav,Nav.Default{}),pickups} : Bot.Memory}

# Guarantees: Zero publication budget returns no candidates.
# Why it matters: The preferred row leaves exactly seven alternative slots.
law take_zero:
  for rows:List<&2,P.Choice>
  {Nav.take(rows,0n) == [] : List<&2,P.Choice>}

# Guarantees: An empty source remains empty for every budget.
# Why it matters: Missing native alternatives cannot create synthetic choices.
law take_empty:
  for fuel:Nat
  {Nav.take([],fuel) == [] : List<&2,P.Choice>}

# Guarantees: Each published row consumes exactly one slot.
# Why it matters: Recursive publication cannot exceed its specified cap.
law take_cons:
  for +row:P.Choice for +rest:List<&2,P.Choice> for +fuel:Nat
  {Nav.take(row <> rest,(1n + fuel : Nat)) == row <> Nav.take(rest,fuel) : List<&2,P.Choice>}

# Guarantees: Taking a budget cannot produce more rows than that budget.
# Why it matters: A Worker can never receive an unbounded goal list.
law take_bound:
  for rows:List<&2,P.Choice> for +fuel:Nat
  {Nat.is_le(List.length(&2,P.Choice,Nav.take(rows,fuel)),fuel) == True{} : Bool}

# Guarantees: Identity deduplication of an empty list remains empty.
# Why it matters: Retaining a preferred goal cannot manufacture native alternatives.
law remove_same_empty:
  for goal:P.Goal
  {Nav.remove_same([],goal) == [] : List<&2,P.Choice>}

# Guarantees: Deduplication drops exactly matching seed, generation and kind identities.
# Why it matters: A preferred candidate must not occupy two published rows.
law remove_same_cons:
  for +row:P.Choice for +rest:List<&2,P.Choice> for +goal:P.Goal
  {Nav.remove_same(row <> rest,goal) == P.branch(~List<&2,P.Choice>,P.same(P.choice_goal(row),goal),(_ => Nav.remove_same(rest,goal)),(_ => row <> Nav.remove_same(rest,goal))) : List<&2,P.Choice>}

# Guarantees: An index into an empty list is unavailable.
# Why it matters: An out-of-range Pick must not invent a destination.
law at_empty:
  for index:U32
  {Nav.at([],index) == None{} : Maybe<&2,P.Choice>}

# Guarantees: Index zero addresses the first published row.
# Why it matters: Preferred-first publication and selection must agree.
law at_zero:
  for +row:P.Choice for rest:List<&2,P.Choice>
  {Nav.at(row <> rest,0) == Some{row} : Maybe<&2,P.Choice>}

# Guarantees: Nonzero indices descend one row; zero selects that row.
# Why it matters: Picking a later alternative must use its published index.
law at_cons:
  for +row:P.Choice for +rest:List<&2,P.Choice> for +index:U32
  {Nav.at(row <> rest,index) == P.branch(~Maybe<&2,P.Choice>,U32.is_eq(index,0),(_ => Some{row}),(_ => Nav.at(rest,(index - 1 : U32)))) : Maybe<&2,P.Choice>}

# Guarantees: Existing preference plus index zero is the only idempotent pick shortcut.
# Why it matters: Every other Pick resolves the exact list the Worker observed.
law pick_exact:
  for +policy:P.Memory for +pref:Maybe<&2,Nav.Preferred> for +index:U32
  {Nav.pick(Nav.Navigation{policy,pref},index) == Nav.pick_decided(Bool.and(Nav.has_preference(pref),U32.is_eq(index,0)),Nav.Navigation{policy,pref},index) : Nav.Navigation}

# Guarantees: Presence is true exactly for Some preference.
# Why it matters: The current-row shortcut cannot suppress all advice.
law has_preference_some:
  for pref:Nav.Preferred
  {Nav.has_preference(Some{pref}) == True{} : Bool}

# Guarantees: An absent preference has no current-row shortcut.
# Why it matters: Initial Pick0 must select the first native candidate.
law has_preference_none:
  {Nav.has_preference(None{}) == False{} : Bool}

# Guarantees: The current-row shortcut preserves all state.
# Why it matters: Re-selecting a goal must not refresh its route age.
law pick_retained:
  for +nav:Nav.Navigation for index:U32
  {Nav.pick_decided(True{},nav,index) == nav : Nav.Navigation}

# Guarantees: All other picks use exactly choices, indexed lookup and install.
# Why it matters: Invalid indices cannot accidentally select a hidden native row.
law pick_resolves_published:
  for +nav:Nav.Navigation for +index:U32
  {Nav.pick_decided(False{},nav,index) == Nav.install(nav,Nav.at(Nav.choices(nav),index)) : Nav.Navigation}

# Guarantees: Installing a chosen row retains autonomous history and its existing plan tick.
# Why it matters: External advice cannot reset the warm fallback planner.
law install_choice:
  for +policy:P.Memory for pref:Maybe<&2,Nav.Preferred> for +choice:P.Choice
  {Nav.install(Nav.Navigation{policy,pref},Some{choice}) == Nav.Navigation{policy,Some{Nav.Preferred{choice,Nav.last_plan(policy)}}} : Nav.Navigation}

# Guarantees: Only kinds12 through15 are cardinal destinations.
# Why it matters: Physical pickups must never use cardinal proximity completion.
law cardinal_classification:
  for +kind:U32
  {Nav.cardinal_kind(kind) == Bool.and(U32.is_ge(kind,12),U32.is_le(kind,15)) : Bool}

# Guarantees: Goal classification reads the actual goal kind.
# Why it matters: Cardinal retention cannot be disabled by an unrelated helper flag.
law goal_cardinal_classification:
  for seed:U32 for gen:U32 for +kind:U32 for x:F32 for y:F32 for reward:F32 for cluster:P.Point
  {Nav.is_cardinal(P.Goal{seed,gen,kind,x,y,reward,cluster}) == Nav.cardinal_kind(kind) : Bool}

# Guarantees: Cardinals keep their admitted endpoint; every other kind uses live identity lookup.
# Why it matters: Kinds12..15 cannot rebase and physical kinds2,5,9 cannot outlive their actor.
law live_goal_exact:
  for +goal:P.Goal for +observed:List<&2,P.Goal>
  {Nav.live_goal(goal,observed) == P.branch(~Maybe<&2,P.Goal>,Nav.is_cardinal(goal),(_ => Some{goal}),(_ => P.find_goal(observed,goal))) : Maybe<&2,P.Goal>}

# Guarantees: Completion is exactly cardinal classification plus distance below35.
# Why it matters: XP, chests and relics require physical collection regardless of proximity.
law reached_exact:
  for +goal:P.Goal for +here:P.Point
  {Nav.reached(goal,here) == Bool.and(Nav.is_cardinal(goal),F32.is_lt(P.distance(here,P.goal_point(goal)),35.0)) : Bool}

# Guarantees: A found route with no waypoint also releases preference.
# Why it matters: A nominal successful search cannot leave movement permanently targetless.
law empty_route_releases:
  for goal:P.Goal for score:F32 for tick:U32 for length:F32 for risk:F32 for expanded:U32
  {Nav.routed(goal,score,tick,P.Route{True{},[],length,risk,expanded}) == None{} : Maybe<&2,Nav.Preferred>}

# Guarantees: Advance installs the exact warm native result and separately advances preference.
# Why it matters: Autonomous scoring is never allowed to overwrite external preference.
law finish_advance_exact:
  for +policy:P.Memory for +pref:Maybe<&2,Nav.Preferred> for +run:G.Run for +rows:List<&2,G.Snapshot> for +next:P.Memory for dx:F32 for dy:F32
  {Nav.finish_advance(Nav.Navigation{policy,pref},run,rows,(next,(dx,dy))) == Nav.Navigation{next,Nav.advance_preferred(policy,next,pref,run,rows)} : Nav.Navigation}

# Guarantees: Autonomous Advance does not manufacture explicit preference.
# Why it matters: Native fallback stays native until new advice is admitted.
law advance_none:
  for old:P.Memory for next:P.Memory for run:G.Run for rows:List<&2,G.Snapshot>
  {Nav.advance_preferred(old,next,None{},run,rows) == None{} : Maybe<&2,Nav.Preferred>}

# Guarantees: Preferred Advance resolves the actual live observations and actual run position.
# Why it matters: A collected or recycled physical actor must invalidate its retained goal.
law advance_some:
  for +old:P.Memory for +next:P.Memory for +choice:P.Choice for +at:U32 for +run:G.Run for +rows:List<&2,G.Snapshot>
  {Nav.advance_preferred(old,next,Some{Nav.Preferred{choice,at}},run,rows) == Nav.advance_live(Nav.live_goal(P.choice_goal(choice),P.goals_at(rows,G.run_tick(run))),Nav.Preferred{choice,at},P.Point{G.run_px(run),G.run_py(run)},G.run_tick(run),old,next,Nav.threats(rows,[])) : Maybe<&2,Nav.Preferred>}

# Guarantees: A disappeared identity releases preference immediately.
# Why it matters: Collected XP cannot remain selected offscreen.
law advance_missing:
  for pref:Nav.Preferred for here:P.Point for tick:U32 for old:P.Memory for next:P.Memory for rows:List<&2,T.Threat>
  {Nav.advance_live(None{},pref,here,tick,old,next,rows) == None{} : Maybe<&2,Nav.Preferred>}

# Guarantees: A live goal is checked for completion before its retained route is used.
# Why it matters: A reached cardinal must release while a nearby physical pickup must remain.
law advance_live_exact:
  for +goal:P.Goal for +pref:Nav.Preferred for +here:P.Point for +tick:U32 for +old:P.Memory for +next:P.Memory for +rows:List<&2,T.Threat>
  {Nav.advance_live(Some{goal},pref,here,tick,old,next,rows) == Nav.advance_reached(Nav.reached(goal,here),goal,pref,here,tick,old,next,rows) : Maybe<&2,Nav.Preferred>}

# Guarantees: Completed cardinal navigation releases preference.
# Why it matters: The bot must not orbit an already reached fixed endpoint forever.
law advance_completed:
  for goal:P.Goal for pref:Nav.Preferred for here:P.Point for tick:U32 for old:P.Memory for next:P.Memory for rows:List<&2,T.Threat>
  {Nav.advance_reached(True{},goal,pref,here,tick,old,next,rows) == None{} : Maybe<&2,Nav.Preferred>}

# Guarantees: An incomplete goal trims its existing route before deciding whether to route again.
# Why it matters: Rerouting preserves goal identity and uses the next actual waypoint for danger.
law advance_incomplete:
  for +goal:P.Goal for +pref:Nav.Preferred for +here:P.Point for +tick:U32 for +old:P.Memory for +next:P.Memory for +rows:List<&2,T.Threat>
  {Nav.advance_reached(False{},goal,pref,here,tick,old,next,rows) == Nav.advance_trimmed(Nav.trim_preferred(pref,goal,here),here,tick,old,next,rows) : Maybe<&2,Nav.Preferred>}

# Guarantees: Trimming changes only the resolved goal and route prefix, retaining score and route age.
# Why it matters: Frequent frames must not postpone the30tick route refresh.
law trim_preferred_exact:
  for previous:P.Goal for +path:List<&2,P.Point> for +score:F32 for +at:U32 for +goal:P.Goal for +here:P.Point
  {Nav.trim_preferred(Nav.Preferred{P.Choice{previous,path,score},at},goal,here) == Nav.Preferred{P.Choice{goal,P.trim(path,here),score},at} : Nav.Preferred}

# Guarantees: Reroute decisions use retained route age, native planning events and next-waypoint danger.
# Why it matters: Native damage/stuck replans and newly dangerous paths also refresh preferred routing.
law advance_trimmed_exact:
  for +pref:Nav.Preferred for +here:P.Point for +tick:U32 for +old:P.Memory for +next:P.Memory for +rows:List<&2,T.Threat>
  {Nav.advance_trimmed(pref,here,tick,old,next,rows) == Nav.route_decided(Nav.replan_due(pref,tick,old,next,rows),pref,here,tick,rows) : Maybe<&2,Nav.Preferred>}

# Guarantees: Periodic age30, native lastPlan change, or unsafe/missing next waypoint each trigger rerouting.
# Why it matters: A preferred route cannot stay stale merely because its goal remains valid.
law replan_due_exact:
  for +choice:P.Choice for +at:U32 for +tick:U32 for +old:P.Memory for +next:P.Memory for +rows:List<&2,T.Threat>
  {Nav.replan_due(Nav.Preferred{choice,at},tick,old,next,rows) == Bool.or(U32.is_ge((tick - at : U32),30),Bool.or(Bool.not(U32.is_eq(Nav.last_plan(old),Nav.last_plan(next))),Nav.waypoint_danger(P.target(Some{choice}),rows))) : Bool}

# Guarantees: A missing waypoint requires routing rather than silent idle.
# Why it matters: Empty cached routes must recover or release in the same frame.
law waypoint_missing:
  for rows:List<&2,T.Threat>
  {Nav.waypoint_danger(None{},rows) == True{} : Bool}

# Guarantees: Waypoint danger uses the original shared danger geometry on projectile-aware threats.
# Why it matters: A hostile shot crossing the route must trigger the same routing safety response.
law waypoint_danger_exact:
  for +point:P.Point for +rows:List<&2,T.Threat>
  {Nav.waypoint_danger(Some{point},rows) == Nav.blocked(P.danger(rows,point,False{},0.0)) : Bool}

# Guarantees: Danger consumes the blocked component, not its unrelated numeric risk score.
# Why it matters: The reroute predicate must be the shared collision-danger decision.
law blocked_exact:
  for +blocked:Bool for risk:F32
  {Nav.blocked((blocked,risk)) == blocked : Bool}

# Guarantees: Cached routing preserves the entire preferred route and age.
# Why it matters: A frame without a trigger cannot rewrite the admitted destination.
law route_cached:
  for +pref:Nav.Preferred for here:P.Point for tick:U32 for rows:List<&2,T.Threat>
  {Nav.route_decided(False{},pref,here,tick,rows) == Some{pref} : Maybe<&2,Nav.Preferred>}

# Guarantees: Triggered routing targets the same resolved goal using the shared search with budget150.
# Why it matters: Preferred routing must not substitute autonomous scoring or an unbounded search.
law route_triggered:
  for +goal:P.Goal for path:List<&2,P.Point> for +score:F32 for at:U32 for +here:P.Point for +tick:U32 for +rows:List<&2,T.Threat>
  {Nav.route_decided(True{},Nav.Preferred{P.Choice{goal,path,score},at},here,tick,rows) == Nav.routed(goal,score,tick,P.route(here,P.goal_point(goal),rows,150)) : Maybe<&2,Nav.Preferred>}

# Guarantees: Native current, candidates and lastPlan are read from their actual stored fields.
# Why it matters: Correct-looking preference laws cannot be satisfied by constant native projections.
law native_accessors:
  for +current:Maybe<&2,P.Choice> for +at:U32 for +hp:U32 for +anchor:P.Point for +since:U32 for +init:Bool for +keys:List<&2,P.Goal> for +rows:List<&2,P.Choice>
  {Nav.fields(P.Memory{current,at,hp,anchor,since,init,keys,rows}) == (current,(at,rows)) : Maybe<&2,P.Choice> & (U32 & List<&2,P.Choice>)}

# Guarantees: The native current accessor returns the current component of the stored-field projection.
# Why it matters: Same-frame fallback cannot read a fabricated choice.
law current_accessor:
  for +memory:P.Memory
  {Nav.current(memory) == Nav.field_current(Nav.fields(memory)) : Maybe<&2,P.Choice>}

# Guarantees: The native lastPlan accessor returns the stored plan tick.
# Why it matters: Native replanning events cannot be hidden by a constant timestamp.
law last_plan_accessor:
  for +memory:P.Memory
  {Nav.last_plan(memory) == Nav.field_tick(Nav.fields(memory)) : U32}

# Guarantees: The native candidates accessor returns the stored list.
# Why it matters: Publication and selection must expose the actual autonomous alternatives.
law candidates_accessor:
  for +memory:P.Memory
  {Nav.candidates(memory) == Nav.field_rows(Nav.fields(memory)) : List<&2,P.Choice>}

# Guarantees: Field projection helpers preserve every selected component exactly.
# Why it matters: Accessor wiring cannot be satisfied by helpers that silently change stored values.
law field_current:
  for +current:Maybe<&2,P.Choice> for tick:U32 for rows:List<&2,P.Choice>
  {Nav.field_current((current,(tick,rows))) == current : Maybe<&2,P.Choice>}

# Guarantees: The stored tick projection is exact.
# Why it matters: Periodic and native replan triggers must use real timestamps.
law field_tick:
  for current:Maybe<&2,P.Choice> for +tick:U32 for rows:List<&2,P.Choice>
  {Nav.field_tick((current,(tick,rows))) == tick : U32}

# Guarantees: The stored candidate list projection is exact.
# Why it matters: Published alternatives cannot be replaced with a hidden list.
law field_rows:
  for current:Maybe<&2,P.Choice> for tick:U32 for +rows:List<&2,P.Choice>
  {Nav.field_rows((current,(tick,rows))) == rows : List<&2,P.Choice>}

# Guarantees: Empty threat projection returns the accumulated stream threats.
# Why it matters: A hostile shot already discovered cannot be dropped at recursion termination.
law threats_empty:
  for +acc:List<&2,T.Threat>
  {Nav.threats([],acc) == acc : List<&2,T.Threat>}

# Guarantees: Each hostile projectile contributes its exact position, radius and hostile flag.
# Why it matters: Preferred navigation must retain the stream's hostile-shot avoidance.
law threats_hostile:
  for +x:F32 for +y:F32 for speed:U32 for +radius:F32 for identity:U32 for payload:C.ShotPayload for trajectory:C.Trajectory for +rest:List<&2,G.Snapshot> for +acc:List<&2,T.Threat>
  {Nav.threats(G.ProjectileSnapshot{Shot.State{Space.Spatial{x,y,speed,radius},identity,Shot.HostileShot{},payload,trajectory}} <> rest,acc) == Nav.threats(rest,T.Threat{x,y,radius,True{}} <> acc) : List<&2,T.Threat>}

# Guarantees: Each observed enemy contributes its exact position and radius.
# Why it matters: Keeping explicit preference cannot bypass immediate enemy avoidance.
law threats_enemy:
  for +x:F32 for +y:F32 for speed:U32 for +radius:F32 for archetype:U32 for identity:U32 for vitals:C.Vitals for status:C.Status for +rest:List<&2,G.Snapshot> for +acc:List<&2,T.Threat>
  {Nav.threats(G.EnemySnapshot{Enemy.State{Space.Spatial{x,y,speed,radius},archetype,identity,vitals,status}} <> rest,acc) == Nav.threats(rest,T.Threat{x,y,radius,False{}} <> acc) : List<&2,T.Threat>}

# Guarantees: Public goal projection preserves actor identity and every displayed choice field.
# Why it matters: Recycled actors at the same location must invalidate an old advice request.
law published_choice_exact:
  for +index:U32 for +seed:U32 for +gen:U32 for +kind:U32 for +x:F32 for +y:F32 for +reward:F32 for cluster:P.Point for path:List<&2,P.Point> for +score:F32
  {Bot.project_choice(P.Choice{P.Goal{seed,gen,kind,x,y,reward,cluster},path,score},index) == Bot.Goal{index,seed,gen,kind,x,y,reward,score} : Bot.Goal}

# Guarantees: Published equality compares all selectable fields and deliberately excludes score.
# Why it matters: A recycled actor or moved goal cannot reuse a stale request identity.
law published_identity_exact:
  for +i:U32 for +s:U32 for +g:U32 for +k:U32 for +x:F32 for +y:F32 for +r:F32 for score:F32
  for +j:U32 for +t:U32 for +h:U32 for +l:U32 for +u:F32 for +v:F32 for +q:F32 for otherScore:F32
  {Bot.same_goal(Bot.Goal{i,s,g,k,x,y,r,score},Bot.Goal{j,t,h,l,u,v,q,otherScore}) == Bool.and(U32.is_eq(i,j),Bool.and(U32.is_eq(s,t),Bool.and(U32.is_eq(g,h),Bool.and(U32.is_eq(k,l),Bool.and(U32.is_eq(F32.bits(x),F32.bits(u)),Bool.and(U32.is_eq(F32.bits(y),F32.bits(v)),U32.is_eq(F32.bits(r),F32.bits(q)))))))) : Bool}

# Guarantees: Empty published lists compare equal.
# Why it matters: No-candidate frames must not manufacture identity changes.
law same_goals_empty:
  {Bot.same_goals([],[]) == True{} : Bool}

# Guarantees: A missing candidate on either side changes published identity.
# Why it matters: Removed goals must obsolete an outstanding Worker request.
law same_goals_left_empty:
  for row:Bot.Goal for rest:List<&2,Bot.Goal>
  {Bot.same_goals([],row <> rest) == False{} : Bool}

# Guarantees: An added candidate also changes published identity.
# Why it matters: Candidate set length is part of the published choice contract.
law same_goals_right_empty:
  for row:Bot.Goal for rest:List<&2,Bot.Goal>
  {Bot.same_goals(row <> rest,[]) == False{} : Bool}

# Guarantees: List equality compares each full row in order and the full remaining tail.
# Why it matters: Reordering an index or recycling a later actor must invalidate stale advice.
law same_goals_cons:
  for +a:Bot.Goal for +as:List<&2,Bot.Goal> for +b:Bot.Goal for +bs:List<&2,Bot.Goal>
  {Bot.same_goals(a <> as,b <> bs) == Bool.and(Bot.same_goal(a,b),Bot.same_goals(as,bs)) : Bool}

# Guarantees: Public candidate projection starts from the exact navigation choices list.
# Why it matters: The observation cannot advertise indices from a different source than Pick.
law public_candidates_wiring:
  for +nav:Nav.Navigation
  {Bot.candidates(nav) == Bot.choices(Nav.choices(nav),0,8) : List<&2,Bot.Goal>}

# Guarantees: Goal projection stops when its public budget reaches zero.
# Why it matters: Public observation cannot exceed eight entries.
law public_choices_zero:
  for rows:List<&2,P.Choice> for index:U32
  {Bot.choices(rows,index,0) == [] : List<&2,Bot.Goal>}

# Guarantees: Goal projection of an empty source is empty.
# Why it matters: A missing candidate cannot become an invented advice option.
law public_choices_empty:
  for index:U32 for fuel:U32
  {Bot.choices([],index,fuel) == [] : List<&2,Bot.Goal>}

# Guarantees: Each positive-budget projection uses the exact row and increments its public index.
# Why it matters: Public identity fields and Pick indices must address the same row.
law public_choices_cons:
  for +row:P.Choice for +rest:List<&2,P.Choice> for +index:U32 for +fuel:U32
  {Bot.choices(row <> rest,index,fuel) == P.branch(~List<&2,Bot.Goal>,U32.is_eq(fuel,0),(_ => []),(_ => Bot.project_choice(row,index) <> Bot.choices(rest,(index + 1 : U32),(fuel - 1 : U32)))) : List<&2,Bot.Goal>}

# Guarantees: The production planned path advances navigation before final steering is computed.
# Why it matters: A correct but unused direction helper cannot satisfy preference authority.
law planned_advance_wiring:
  for +nav:Nav.Navigation for +run:G.Run for +offers:List<&2,G.Offer> for +visible:List<&2,G.Snapshot> for +knowledge:List<&2,G.Snapshot> for +truncated:Bool for +view:Bot.View
  {Bot.planned(nav,run,offers,visible,knowledge,truncated,view) == Bot.finalize(Nav.step(nav,Nav.Advance{run,List.append(&2,G.Snapshot,visible,Bot.known(knowledge,view,128,[]))}),run,offers,visible,knowledge,truncated) : Bot.Planned}

# Guarantees: Final production output gets its direction from the preference-aware direction operation.
# Why it matters: The old autonomous movement vector cannot silently replace selected-target steering.
law finalize_direction_wiring:
  for +nav:Nav.Navigation for +run:G.Run for +offers:List<&2,G.Offer> for +visible:List<&2,G.Snapshot> for +knowledge:List<&2,G.Snapshot> for +truncated:Bool
  {Bot.finalize(nav,run,offers,visible,knowledge,truncated) == Bot.with_direction(nav,Bot.observation(run,offers,nav,visible,truncated),knowledge,Bot.direction(nav,run,visible)) : Bot.Planned}

# Guarantees: The returned Planned value contains the actual computed steering vector and updated memory.
# Why it matters: A correct steering calculation must reach the host's physical movement output.
law final_output_direction:
  for +nav:Nav.Navigation for +observation:Bot.Observation for +knowledge:List<&2,G.Snapshot> for +dx:F32 for +dy:F32
  {Bot.with_direction(nav,observation,knowledge,(dx,dy)) == Bot.Planned{Bot.Memory{nav,knowledge},observation,dx,dy} : Bot.Planned}

# Guarantees: Navigation publishes no more than eight selectable goals in all states.
# Why it matters: The advice bound holds for preferred and autonomous publication alike.
law choices_bound:
  for nav:Nav.Navigation
  {Nat.is_le(List.length(&2,P.Choice,Nav.choices(nav)),8n) == True{} : Bool}

# Guarantees: Player shots do not become hostile navigation threats.
# Why it matters: Own weapons cannot spuriously repel the stream bot.
law threats_player_shot:
  for spatial:Space.Spatial for identity:U32 for payload:C.ShotPayload for trajectory:C.Trajectory for +rest:List<&2,G.Snapshot> for +acc:List<&2,T.Threat>
  {Nav.threats(G.ProjectileSnapshot{Shot.State{spatial,identity,Shot.PlayerShot{},payload,trajectory}} <> rest,acc) == Nav.threats(rest,acc) : List<&2,T.Threat>}

# Guarantees: Pickups do not become navigation threats.
# Why it matters: Remembered XP must stay collectible rather than act as an obstacle.
law threats_pickup:
  for pickup:Pickup.State for +rest:List<&2,G.Snapshot> for +acc:List<&2,T.Threat>
  {Nav.threats(G.PickupSnapshot{pickup} <> rest,acc) == Nav.threats(rest,acc) : List<&2,T.Threat>}

# Guarantees: The observation publishes the exact preferred-aware candidate list and visible threats.
# Why it matters: A correct picker cannot compensate for advertising a different list to the Worker.
law observation_candidates_wiring:
  for +run:G.Run for +offers:List<&2,G.Offer> for +nav:Nav.Navigation for +visible:List<&2,G.Snapshot> for +truncated:Bool
  {Bot.observation(run,offers,nav,visible,truncated) == Bot.Observation{G.run_tick(run),G.run_phase(run),G.run_px(run),G.run_py(run),G.run_hp(run),G.run_maxHp(run),G.run_level(run),G.run_weapons(run),G.run_passives(run),Bot.live_offers(G.run_phase(run),offers),Bot.candidates(nav),Nav.threats(visible,[]),P.upgrade(run,offers),truncated} : Bot.Observation}
