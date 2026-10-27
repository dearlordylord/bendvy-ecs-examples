import Base
import ./preference.bend as Nav
import ./preference-LAWS.bend as L
import ../offline-policy.bend as P
import ../game.bend as G
import ../enemy-spatial.bend as Space
import ../stream-bot.bend as Bot

def L.public_plan_composition(memory,run,offers,rows,width,height):
  match memory:
    case Bot.Memory{nav,pickups}: {==}
def L.initial_empty(): {==}
def L.default_preserves_native(policy,pref): {==}
def L.default_idempotent(nav): 
  match nav:
    case Nav.Navigation{policy,pref}: {==}
def L.preferred_selected(policy,choice,at): {==}
def L.native_selected(policy): {==}
def L.preferred_choices(policy,choice,at): {==}
def L.native_choices(policy): {==}
def L.current_pick_idempotent(policy,pref): {==}
def L.missing_pick_unchanged(nav): 
  match nav:
    case Nav.Navigation{policy,pref}: {==}
def L.pick_wiring(nav,index): 
  match nav:
    case Nav.Navigation{policy,pref}: {==}
def L.advance_native_wiring(policy,pref,run,rows): {==}
def L.cardinal_endpoint_pinned(seed,gen,x,y,reward,cluster,observed): {==}
def L.physical_identity_lookup(seed,gen,x,y,reward,cluster,observed): {==}
def L.physical_not_proximity_complete(seed,gen,x,y,reward,cluster,here): {==}
def L.failed_route_releases(goal,score,tick,path,length,risk,expanded): {==}
def L.successful_route_keeps_goal(goal,score,tick,point,rest,length,risk,expanded): {==}
def L.stream_steering_uses_selected(nav,run,rows): {==}
def L.public_choose_wiring(nav,pickups,index): {==}
def L.public_fallback_wiring(nav,pickups): {==}
def L.take_zero(rows):
  match rows:
    case Nil{}: {==}
    case Con{row,rest}: {==}
def L.take_empty(fuel):
  match fuel:
    case 0n: {==}
    case 1n++rest: {==}
def L.take_cons(row,rest,fuel): {==}
def L.take_bound(rows,fuel):
  match rows fuel:
    case Nil{} 0n: {==}
    case Nil{} 1n++n: {==}
    case Con{row,rest} 0n: {==}
    case Con{row,rest} 1n++n: L.take_bound(rest,n)
def L.remove_same_empty(goal): {==}
def L.remove_same_cons(row,rest,goal): {==}
def L.at_empty(index): {==}
def L.at_zero(row,rest): {==}
def L.at_cons(row,rest,index): {==}
def L.pick_exact(policy,pref,index): {==}
def L.has_preference_some(pref): {==}
def L.has_preference_none(): {==}
def L.pick_retained(nav,index): {==}
def L.pick_resolves_published(nav,index): {==}
def L.install_choice(policy,pref,choice): {==}
def L.cardinal_classification(kind): {==}
def L.goal_cardinal_classification(seed,gen,kind,x,y,reward,cluster): {==}
def L.live_goal_exact(goal,observed): {==}
def L.reached_exact(goal,here): {==}
def L.empty_route_releases(goal,score,tick,length,risk,expanded): {==}
def L.finish_advance_exact(policy,pref,run,rows,next,dx,dy): {==}
def L.advance_none(old,next,run,rows): {==}
def L.advance_some(old,next,choice,at,run,rows): {==}
def L.advance_missing(pref,here,tick,old,next,rows): {==}
def L.advance_live_exact(goal,pref,here,tick,old,next,rows): {==}
def L.advance_completed(goal,pref,here,tick,old,next,rows): {==}
def L.advance_incomplete(goal,pref,here,tick,old,next,rows): {==}
def L.trim_preferred_exact(previous,path,score,at,goal,here): {==}
def L.advance_trimmed_exact(pref,here,tick,old,next,rows): {==}
def L.replan_due_exact(choice,at,tick,old,next,rows): {==}
def L.waypoint_missing(rows): {==}
def L.waypoint_danger_exact(point,rows): {==}
def L.blocked_exact(blocked,risk): {==}
def L.route_cached(pref,here,tick,rows): {==}
def L.route_triggered(goal,path,score,at,here,tick,rows): {==}
def L.native_accessors(current,at,hp,anchor,since,init,keys,rows): {==}
def L.current_accessor(memory): {==}
def L.last_plan_accessor(memory): {==}
def L.candidates_accessor(memory): {==}
def L.field_current(current,tick,rows): {==}
def L.field_tick(current,tick,rows): {==}
def L.field_rows(current,tick,rows): {==}
def L.threats_empty(acc): {==}
def L.threats_hostile(x,y,speed,radius,identity,payload,trajectory,rest,acc): {==}
def L.threats_enemy(x,y,speed,radius,archetype,identity,vitals,status,rest,acc): {==}
def L.published_choice_exact(index,seed,gen,kind,x,y,reward,cluster,path,score): {==}
def L.published_identity_exact(i,s,g,k,x,y,r,score,j,t,h,l,u,v,q,otherScore): {==}
def L.same_goals_empty(): {==}
def L.same_goals_left_empty(row,rest): {==}
def L.same_goals_right_empty(row,rest): {==}
def L.same_goals_cons(a,as,b,bs): {==}
def L.public_candidates_wiring(nav): {==}
def L.public_choices_zero(rows,index):
  match rows:
    case Nil{}: {==}
    case Con{row,rest}: {==}
def L.public_choices_empty(index,fuel): {==}
def L.public_choices_cons(row,rest,index,fuel): {==}
def L.planned_advance_wiring(nav,run,offers,visible,knowledge,truncated,view): {==}
def L.finalize_direction_wiring(nav,run,offers,visible,knowledge,truncated): {==}
def L.final_output_direction(nav,observation,knowledge,dx,dy): {==}
def L.choices_bound(nav):
  match nav:
    case Nav.Navigation{policy,None{}}: L.take_bound(Nav.candidates(policy),8n)
    case Nav.Navigation{policy,Some{Nav.Preferred{choice,at}}}: L.take_bound(Nav.remove_same(Nav.candidates(policy),P.choice_goal(choice)),7n)
def L.threats_player_shot(spatial,identity,payload,trajectory,rest,acc):
  match spatial:
    case Space.Spatial{x,y,age,radius}: {==}
def L.threats_pickup(pickup,rest,acc): {==}
def L.observation_candidates_wiring(run,offers,nav,visible,truncated): {==}
