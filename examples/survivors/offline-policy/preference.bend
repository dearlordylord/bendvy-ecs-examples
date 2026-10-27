import Base
import ../offline-policy.bend as P
import ../game.bend as G
import ../offline-threats.bend as T
import ../projectile-state.bend as Shot
import ../enemy-combat.bend as Enemy
import ../enemy-spatial.bend as Space

type Preferred is Data: Preferred{choice:P.Choice,plannedAt:U32}
type Navigation is Data: Navigation{policy:P.Memory,preferred:Maybe<&2,Preferred>}
type Input is Data:
  Pick{index:U32}
  Default{}
  Advance{run:G.Run,snapshots:List<&2,G.Snapshot>}


def fields(memory:P.Memory) -> Maybe<&2,P.Choice> & (U32 & List<&2,P.Choice>):
  match memory:
    case P.Memory{current,at,_,_,_,_,_,rows}: (current,(at,rows))
def field_current(value:Maybe<&2,P.Choice> & (U32 & List<&2,P.Choice>)) -> Maybe<&2,P.Choice>:
  P.bind(~Maybe<&2,P.Choice>,~(U32 & List<&2,P.Choice>),~Maybe<&2,P.Choice>,value,(current => _ => current))
def field_tick(value:Maybe<&2,P.Choice> & (U32 & List<&2,P.Choice>)) -> U32:
  P.bind(~Maybe<&2,P.Choice>,~(U32 & List<&2,P.Choice>),~U32,value,(_ => pair => P.bind(~U32,~List<&2,P.Choice>,~U32,pair,(tick => _ => tick))))
def field_rows(value:Maybe<&2,P.Choice> & (U32 & List<&2,P.Choice>)) -> List<&2,P.Choice>:
  P.bind(~Maybe<&2,P.Choice>,~(U32 & List<&2,P.Choice>),~List<&2,P.Choice>,value,(_ => pair => P.bind(~U32,~List<&2,P.Choice>,~List<&2,P.Choice>,pair,(_ => rows => rows))))
def current(memory:P.Memory) -> Maybe<&2,P.Choice>: field_current(fields(memory))
def last_plan(memory:P.Memory) -> U32: field_tick(fields(memory))
def candidates(memory:P.Memory) -> List<&2,P.Choice>: field_rows(fields(memory))
def take(rows:List<&2,P.Choice>,fuel:Nat) -> List<&2,P.Choice>:
  match rows fuel:
    case _ 0n: []
    case [] _: []
    case row <> rest 1n++fuel: row <> take(rest,fuel)
def remove_same(rows:List<&2,P.Choice>,+goal:P.Goal) -> List<&2,P.Choice>:
  match rows:
    case []: []
    case +row <> +rest: P.branch(~List<&2,P.Choice>,P.same(P.choice_goal(row),goal),(_ => remove_same(rest,goal)),(_ => row <> remove_same(rest,goal)))
def at(rows:List<&2,P.Choice>,+index:U32) -> Maybe<&2,P.Choice>:
  match rows:
    case []: None{}
    case +row <> +rest: P.branch(~Maybe<&2,P.Choice>,U32.is_eq(index,0),(_ => Some{row}),(_ => at(rest,(index - 1 : U32))))
def has_preference(pref:Maybe<&2,Preferred>) -> Bool:
  match pref:
    case Some{_}: True{}
    case None{}: False{}
def choices(nav:Navigation) -> List<&2,P.Choice>:
  match nav:
    case Navigation{policy,None{}}: take(candidates(policy),8n)
    case Navigation{policy,Some{Preferred{+choice,_}}}: choice <> take(remove_same(candidates(policy),P.choice_goal(choice)),7n)
def selected(nav:Navigation) -> Maybe<&2,P.Choice>:
  match nav:
    case Navigation{policy,None{}}: current(policy)
    case Navigation{_,Some{Preferred{choice,_}}}: Some{choice}
def install(nav:Navigation,choice:Maybe<&2,P.Choice>) -> Navigation:
  match nav choice:
    case +navigation None{}: navigation
    case Navigation{+policy,_} Some{choice}: Navigation{policy,Some{Preferred{choice,last_plan(policy)}}}
def pick_decided(retain:Bool,+nav:Navigation,index:U32) -> Navigation:
  match retain:
    case True{}: nav
    case False{}: install(nav,at(choices(nav),index))
def pick(nav:Navigation,+index:U32) -> Navigation:
  match nav:
    case Navigation{+policy,+pref}: pick_decided(Bool.and(has_preference(pref),U32.is_eq(index,0)),Navigation{policy,pref},index)
def cardinal_kind(+kind:U32) -> Bool: Bool.and(U32.is_ge(kind,12),U32.is_le(kind,15))
def is_cardinal(goal:P.Goal) -> Bool: cardinal_kind(P.goal_kind(goal))
def live_goal(+goal:P.Goal,+observed:List<&2,P.Goal>) -> Maybe<&2,P.Goal>: P.branch(~Maybe<&2,P.Goal>,is_cardinal(goal),(_ => Some{goal}),(_ => P.find_goal(observed,goal)))
def reached(+goal:P.Goal,here:P.Point) -> Bool: Bool.and(is_cardinal(goal),F32.is_lt(P.distance(here,P.goal_point(goal)),35.0))
def routed(goal:P.Goal,score:F32,tick:U32,route:P.Route) -> Maybe<&2,Preferred>:
  match route:
    case P.Route{False{},_,_,_,_}: None{}
    case P.Route{True{},[],_,_,_}: None{}
    case P.Route{True{},point <> rest,_,_,_}: Some{Preferred{P.Choice{goal,point <> rest,score},tick}}
def threats(rows:List<&2,G.Snapshot>,acc:List<&2,T.Threat>) -> List<&2,T.Threat>:
  match rows:
    case []: acc
    case G.EnemySnapshot{Enemy.State{Space.Spatial{x,y,_,radius},_,_,_,_}} <> rest: threats(rest,T.Threat{x,y,radius,False{}} <> acc)
    case G.ProjectileSnapshot{Shot.State{Space.Spatial{x,y,_,radius},_,Shot.HostileShot{},_,_}} <> rest: threats(rest,T.Threat{x,y,radius,True{}} <> acc)
    case _ <> rest: threats(rest,acc)
def blocked(value:Bool & F32) -> Bool:
  P.bind(~Bool,~F32,~Bool,value,(result => _ => result))
def waypoint_danger(target:Maybe<&2,P.Point>,rows:List<&2,T.Threat>) -> Bool:
  match target:
    case None{}: True{}
    case Some{point}: blocked(P.danger(rows,point,False{},0.0))
def replan_due(pref:Preferred,+tick:U32,old:P.Memory,next:P.Memory,rows:List<&2,T.Threat>) -> Bool:
  match pref:
    case Preferred{choice,at}: Bool.or(U32.is_ge((tick - at : U32),30),Bool.or(Bool.not(U32.is_eq(last_plan(old),last_plan(next))),waypoint_danger(P.target(Some{choice}),rows)))
def route_decided(due:Bool,pref:Preferred,here:P.Point,tick:U32,rows:List<&2,T.Threat>) -> Maybe<&2,Preferred>:
  match due pref:
    case False{} value: Some{value}
    case True{} Preferred{P.Choice{+goal,_,score},_}: routed(goal,score,tick,P.route(here,P.goal_point(goal),rows,150))
def trim_preferred(pref:Preferred,goal:P.Goal,here:P.Point) -> Preferred:
  match pref:
    case Preferred{P.Choice{_,path,score},at}: Preferred{P.Choice{goal,P.trim(path,here),score},at}
def advance_trimmed(+pref:Preferred,+here:P.Point,+tick:U32,old:P.Memory,next:P.Memory,+rows:List<&2,T.Threat>) -> Maybe<&2,Preferred>: route_decided(replan_due(pref,tick,old,next,rows),pref,here,tick,rows)
def advance_reached(done:Bool,goal:P.Goal,pref:Preferred,+here:P.Point,tick:U32,old:P.Memory,next:P.Memory,rows:List<&2,T.Threat>) -> Maybe<&2,Preferred>:
  match done:
    case True{}: None{}
    case False{}: advance_trimmed(trim_preferred(pref,goal,here),here,tick,old,next,rows)
def advance_live(live:Maybe<&2,P.Goal>,pref:Preferred,+here:P.Point,tick:U32,old:P.Memory,next:P.Memory,rows:List<&2,T.Threat>) -> Maybe<&2,Preferred>:
  match live:
    case None{}: None{}
    case Some{+goal}: advance_reached(reached(goal,here),goal,pref,here,tick,old,next,rows)
def advance_preferred(old:P.Memory,next:P.Memory,pref:Maybe<&2,Preferred>,+run:G.Run,+rows:List<&2,G.Snapshot>) -> Maybe<&2,Preferred>:
  match pref:
    case None{}: None{}
    case Some{Preferred{+choice,+at}}: advance_live(live_goal(P.choice_goal(choice),P.goals_at(rows,G.run_tick(run))),Preferred{choice,at},P.Point{G.run_px(run),G.run_py(run)},G.run_tick(run),old,next,threats(rows,[]))
def finish_advance(nav:Navigation,run:G.Run,rows:List<&2,G.Snapshot>,result:P.Memory & (F32 & F32)) -> Navigation:
  match nav:
    case Navigation{policy,pref}: P.bind(~P.Memory,~(F32 & F32),~Navigation,result,(+next => _ => Navigation{next,advance_preferred(policy,next,pref,run,rows)}))
def initial() -> Navigation: Navigation{P.initial(),None{}}
def step(nav:Navigation,input:Input) -> Navigation:
  match nav input:
    case navigation Pick{index}: pick(navigation,index)
    case Navigation{policy,_} Default{}: Navigation{policy,None{}}
    case Navigation{+policy,+pref} Advance{+run,+rows}: finish_advance(Navigation{policy,pref},run,rows,P.movement(policy,run,rows))
