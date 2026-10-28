import pickup-state.bend as Pickup
import run-state.bend as RS
import Base
import game-components.bend as Components
import game-observation.bend as G
import enemy-combat.bend as Enemy
import enemy-spatial.bend as Space
import offline-threats.bend as Threats
import projectile.bend as Shots
import offline-policy/risk-grid.bend as R
import offline-policy/primitives.bend as Primitive

# Native controller: typed observations only; no serialization or classifier.
# The bounded spatial planner uses F32 arithmetic and deterministic frontier ties.
type Point is Data: Point{x: F32,y: F32}
type Goal is Data: Goal{seed: U32,generation: U32,kind: U32,x: F32,y: F32,reward: F32,cluster: Point}
type Choice is Data: Choice{goal: Goal,path: List<&2,Point>,score: F32}
type Memory is Data: Memory{current: Maybe<&2,Choice>,lastPlan: U32,lastHp: U32,anchor: Point,stuckSince: U32,initialized: Bool,objectKeys: List<&2,Goal>,candidates: List<&2,Choice>}
type Node is Data: Node{index: U32,cost: F32,priority: F32}
type Route is Data: Route{found: Bool,path: List<&2,Point>,length: F32,risk: F32,expanded: U32}

def branch(~T: Type,+test: Bool,a: Unit -> T,b: Unit -> T) -> T:
  match test:
    case True{}: a(Unit{})
    case False{}: b(Unit{})

def bind(~A: Type,~B: Type,~R: Type,pair: A & B,use: A -> B -> R) -> R:
  (a,b) = pair
  use(a)(b)

def initial() -> Memory: Memory{None{},0,0,Point{0.0,0.0},0,False{},[],[]}
def hypot(+x: F32,+y: F32) -> F32: F32.sqrt((x * x + y * y : F32))
def distance(+a: Point,+b: Point) -> F32:
  match a b:
    case Point{x,y} Point{u,v}: hypot((x - u : F32),(y - v : F32))
def yes(+test: Bool,+a: F32,+b: F32) -> F32:
  branch(~(F32),test,(_ =>
      a
  ),(_ =>
      b

  ))
def preference(+id: U32,+rows: List<&2,U32>,+index: U32) -> U32:
  match rows:
    case []: 999
    case item <> rest:
      branch(~(U32),U32.is_eq(id,item),(_ =>
          index
      ),(_ =>
          preference(id,rest,(index + 1 : U32))
      ))
def offer_score(offer: G.Offer,weapons: List<&2,U32>,passives: List<&2,U32>,hp: U32,maxHp: U32) -> F32:
  match offer:
    case G.Offer{kind,id,_}: Primitive.offer_score(kind,id,weapons,passives,hp,maxHp)

def best_offer(+rows: List<&2,G.Offer>,+weapons: List<&2,U32>,+passives: List<&2,U32>,+hp: U32,+maxHp: U32,+index: U32,+best: U32,+score: F32) -> U32:
  match rows:
    case []: best
    case offer <> rest:
      +next=offer_score(offer,weapons,passives,hp,maxHp)
      branch(~(U32),F32.is_lt(score,next),(_ =>
          best_offer(rest,weapons,passives,hp,maxHp,(index + 1 : U32),index,next)
      ),(_ =>
          best_offer(rest,weapons,passives,hp,maxHp,(index + 1 : U32),best,score)
      ))
def upgrade(+run: G.Run,+offers: List<&2,G.Offer>) -> U32:
  match run:
    case G.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,hp,maxHp,_,weapons,passives,_,_,_,_,_,_,_,_,_}}: best_offer(offers,weapons,passives,hp,maxHp,0,0,(0.0 - 10000.0 : F32))

def goal_point(+goal: Goal) -> Point:
  match goal:
    case Goal{_,_,_,x,y,_,_}: Point{x,y}
def same(+a: Goal,+b: Goal) -> Bool:
  match a b:
    case Goal{s,g,k,_,_,_,_} Goal{t,h,l,_,_,_,_}: Bool.and(U32.is_eq(s,t),Bool.and(U32.is_eq(g,h),U32.is_eq(k,l)))
def find_goal(+rows: List<&2,Goal>,+wanted: Goal) -> Maybe<&2,Goal>:
  match rows:
    case []: None{}
    case +goal <> rest:
      branch(~(Maybe<&2,Goal>),same(goal,wanted),(_ =>
          Some{goal}
      ),(_ =>
          find_goal(rest,wanted)
      ))
# Separate signed coordinates avoid packed-key collisions for off-arena XP.
def floor_cell(+value: F32) -> F32:
  +scaled=(value / 120.0 : F32)
  +absolute=F32.max(scaled,(0.0 - scaled : F32))
  +whole=U32.to_f32(F32.to_u32(absolute))
  yes(F32.is_lt(scaled,0.0),(0.0 - whole - yes(F32.is_lt(whole,absolute),1.0,0.0) : F32),whole)
def same_cluster(+a: Point,+b: Point) -> Bool:
  match a b:
    case Point{x,y} Point{u,v}: Bool.and(F32.is_eq(x,u),F32.is_eq(y,v))
def pickup_goal(+x: F32,+y: F32,+seed: U32,+generation: U32,item: Pickup.Item,tail: List<&2,Goal>) -> List<&2,Goal>:
  match item:
    case Pickup.Xp{amount,_}: Goal{seed,generation,2,x,y,U32.to_f32(amount),Point{floor_cell(x),floor_cell(y)}} <> tail
    case Pickup.Chest{}: Goal{seed,generation,5,x,y,14.0,Point{floor_cell(x),floor_cell(y)}} <> tail
    case Pickup.Relic{_}: Goal{seed,0,9,x,y,9.0,Point{floor_cell(x),floor_cell(y)}} <> tail
    case _: tail
def goals_at(rows: List<&2,G.Snapshot>,+tick: U32) -> List<&2,Goal>:
  match rows:
    case []: []
    case G.PickupSnapshot{Pickup.State{Space.Spatial{x,y,_,_},Pickup.Payload{item,generation,True{}},seed}} <> rest: pickup_goal(x,y,seed,generation,item,goals_at(rest,tick))
    case _ <> rest: goals_at(rest,tick)
def goals(rows: List<&2,G.Snapshot>) -> List<&2,Goal>: goals_at(rows,0)

# Omniscient refresh removes collected XP; pool members retain seed + generation.
# Aggregate reward per 120px XP cluster; use its nearest live member as target.
def cluster_insert(+rows: List<&2,Goal>,+goal: Goal,+here: Point) -> List<&2,Goal>:
  match rows goal:
    case [] +g: [g]
    case +old <> rest +g:
      match old g:
        case Goal{+s,+a,+k,+x,+y,+r,+c} Goal{+t,+b,+l,+u,+v,+q,+d}:
          branch(~(List<&2,Goal>),Bool.and(U32.is_eq(k,2),Bool.and(U32.is_eq(l,2),same_cluster(c,d))),(_ =>
              branch(~(List<&2,Goal>),F32.is_lt(distance(here,Point{u,v}),distance(here,Point{x,y})),(_ =>
                  Goal{t,b,l,u,v,(r + q : F32),d} <> rest
              ),(_ =>
                  Goal{s,a,k,x,y,(r + q : F32),c} <> rest
              ))
          ),(_ =>
              old <> cluster_insert(rest,g,here)
          ))
def clusters(+rows: List<&2,Goal>,+acc: List<&2,Goal>,+here: Point) -> List<&2,Goal>:
  match rows:
    case []: acc
    case goal <> rest: clusters(rest,cluster_insert(acc,goal,here),here)
def goal_kind(+goal: Goal) -> U32:
  match goal:
    case Goal{_,_,kind,_,_,_,_}: kind
def goal_cluster(+goal: Goal) -> Point:
  match goal:
    case Goal{_,_,_,_,_,_,cluster}: cluster
def goal_name(kind: U32) -> String:
  match kind:
    case 2: "approach_experience"
    case 5: "approach_chest"
    case 9: "approach_relic"
    case 12: "move_north"
    case 13: "move_east"
    case 14: "move_south"
    case _: "move_west"
def goal_id(+goal: Goal) -> String:
  match goal:
    case Goal{seed,_,kind,_,_,_,_}: goal_name(kind) ++ ":" ++ U32.show(seed)
def priority(+goal: Goal,+here: Point) -> F32:
  match goal:
    case Goal{_,_,kind,x,y,reward,_}: yes(U32.is_eq(kind,2),(reward / (60.0 + distance(here,Point{x,y})) : F32),0.0)
def before_goal(+a: Goal,+b: Goal,+here: Point) -> Bool:
  +pa=priority(a,here)
  +pb=priority(b,here)
  +da=distance(here,goal_point(a))
  +db=distance(here,goal_point(b))
  Bool.or(F32.is_lt(pb,pa),Bool.and(F32.is_eq(pa,pb),Bool.or(F32.is_lt(da,db),Bool.and(F32.is_eq(da,db),String.is_lt(goal_id(a),goal_id(b))))))
def insert_goal(+goal: Goal,+rows: List<&2,Goal>,+here: Point) -> List<&2,Goal>:
  match rows:
    case []: [goal]
    case +old <> rest: branch(~List<&2,Goal>,before_goal(goal,old,here),(_ => goal <> old <> rest),(_ => old <> insert_goal(goal,rest,here)))
def sort_goals(+rows: List<&2,Goal>,+acc: List<&2,Goal>,+here: Point) -> List<&2,Goal>:
  match rows:
    case []: acc
    case goal <> rest: sort_goals(rest,insert_goal(goal,acc,here),here)
def cardinals(+px: F32,+py: F32) -> List<&2,Goal>:
  [Goal{12,0,12,px,F32.max(G.world_margin(),(py - 160.0 : F32)),0.1,Point{0.0,0.0}},Goal{13,0,13,F32.min((G.world_size() - G.world_margin() : F32),(px + 160.0 : F32)),py,0.1,Point{0.0,0.0}},Goal{14,0,14,px,F32.min((G.world_size() - G.world_margin() : F32),(py + 160.0 : F32)),0.1,Point{0.0,0.0}},Goal{15,0,15,F32.max(G.world_margin(),(px - 160.0 : F32)),py,0.1,Point{0.0,0.0}}]
def only_xp(+rows: List<&2,Goal>) -> List<&2,Goal>:
  match rows:
    case []: []
    case +goal <> rest: branch(~List<&2,Goal>,U32.is_eq(goal_kind(goal),2),(_ => goal <> only_xp(rest)),(_ => only_xp(rest)))
def same_keys(+a: List<&2,Goal>,+b: List<&2,Goal>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x,xs} Con{y,ys}: Bool.and(same(x,y),same_keys(xs,ys))
    case _ _: False{}
def no_choice(current: Maybe<&2,Choice>) -> Bool:
  match current:
    case None{}: True{}
    case _: False{}

# Grid cell contact and risk.
def cell_point(+index: U32) -> Point: Point{(U32.to_f32((index % 60 : U32)) * 60.0 + 30.0 : F32),(U32.to_f32((index / 60 : U32)) * 60.0 + 30.0 : F32)}
def cell_index(+point: Point) -> U32:
  match point:
    case Point{x,y}: (U32.min(59,F32.to_u32((F32.max(0.0,y) / 60.0 : F32))) * 60 + U32.min(59,F32.to_u32((F32.max(0.0,x) / 60.0 : F32))) : U32)
# The completed snapshot supplies threat order exactly; separate enemy and
# projectile lists are never concatenated or sorted into a guessed order.
def threats(rows: List<&2,G.Snapshot>) -> List<&2,Threats.Threat>:
  match rows:
    case []: []
    case G.EnemySnapshot{Enemy.State{Space.Spatial{x,y,_,radius},_,_,Components.Vitals{health,_},_}} <> rest:
      Threats.keep(U32.is_lt(0,health),Threats.Threat{x,y,radius,False{}},threats(rest))
    case _ <> rest: threats(rest)
def danger(+rows: List<&2,Threats.Threat>,+point: Point,+blocked: Bool,+risk: F32) -> Bool & F32:
  match rows:
    case []: (blocked,risk)
    case Threats.Threat{+x,+y,+radius,+hostile} <> rest:
      +r=(radius + yes(hostile,12.0,18.0) : F32)
      +d=distance(point,Point{x,y})
      danger(rest,point,Bool.or(blocked,F32.is_lt(d,(r + 21.0 : F32))),(risk + F32.max(0.0,(1.0 - d / (r + 120.0) : F32)) * yes(hostile,8.0,4.0) : F32))
def node_priority(+node: Node) -> F32:
  match node:
    case Node{_,_,priority}: priority
def enqueue(+node: Node,+rows: List<&2,Node>) -> List<&2,Node>:
  match rows:
    case []: [node]
    case +old <> rest:
      branch(~List<&2,Node>,F32.is_lt(node_priority(node),node_priority(old)),(_ => node <> old <> rest),(_ => old <> enqueue(node,rest)))
def heuristic(+index: U32,+end: U32) -> F32: (distance(cell_point(index),cell_point(end)) / 60.0 : F32)
def adjacent_xy(+direction: U32,+x: U32,+y: U32) -> U32:
  match direction:
    case 0: ((y * 60) + (x + 1) : U32)
    case 1: (((y + 1) * 60) + x : U32)
    case 2: ((y * 60) + (x - 1) : U32)
    case 3: (((y - 1) * 60) + x : U32)
    case 4: (((y + 1) * 60) + (x + 1) : U32)
    case 5: (((y + 1) * 60) + (x - 1) : U32)
    case 6: (((y - 1) * 60) + (x - 1) : U32)
    case _: (((y - 1) * 60) + (x + 1) : U32)
def valid_neighbor_xy(+direction: U32,+x: U32,+y: U32) -> Bool:
  match direction:
    case 0: U32.is_lt(x,59)
    case 1: U32.is_lt(y,59)
    case 2: U32.is_lt(0,x)
    case 3: U32.is_lt(0,y)
    case 4: Bool.and(U32.is_lt(x,59),U32.is_lt(y,59))
    case 5: Bool.and(U32.is_lt(0,x),U32.is_lt(y,59))
    case 6: Bool.and(U32.is_lt(0,x),U32.is_lt(0,y))
    case _: Bool.and(U32.is_lt(x,59),U32.is_lt(0,y))

def adjacent(+index: U32,+direction: U32) -> U32: adjacent_xy(direction,(index % 60 : U32),(index / 60 : U32))
def valid_neighbor(+index: U32,+direction: U32) -> Bool: valid_neighbor_xy(direction,(index % 60 : U32),(index / 60 : U32))
def grid_danger(+grid: R.Frozen,index: U32) -> Bool & F32:
  +cell=R.lookup(grid,index)
  (R.is_blocked(cell),R.risk(cell))
def corner_clear(+direction: U32,+index: U32,+grid: R.Frozen) -> Bool:
  branch(~(Bool),U32.is_lt(direction,4),(_ =>
      True{}
  ),(_ =>
      +horizontal=(index / 60 * 60 + (adjacent(index,direction) % 60) : U32)
      +vertical=(adjacent(index,direction) / 60 * 60 + index % 60 : U32)
      bind(~(Bool),~(F32),~(Bool),grid_danger(grid,horizontal),(+a => +ignored =>
        bind(~(Bool),~(F32),~(Bool),grid_danger(grid,vertical),(+b => +ignored =>
          Bool.not(Bool.or(a,b))
      ))
      ))
  ))
def apply_neighbor(accepted: Bool,+j: U32,+index: U32,+next: F32,+end: U32,costs: Array<F32>,previous: Array<U32>,open: List<&2,Node>) -> Array<F32> & (Array<U32> & List<&2,Node>):
  match accepted:
    case True{}: (Array.set(F32,costs,j,next),(Array.set(U32,previous,j,index),enqueue(Node{j,next,(next + heuristic(j,end) : F32)},open)))
    case False{}: (costs,(previous,open))
def neighbor_old(pair: Array<F32> & F32,+allowed: Bool,+j: U32,+index: U32,+next: F32,+end: U32,previous: Array<U32>,open: List<&2,Node>) -> Array<F32> & (Array<U32> & List<&2,Node>):
  (costs,old) = pair
  apply_neighbor(Bool.and(allowed,F32.is_lt(next,old)),j,index,next,end,costs,previous,open)
def neighbor_danger(pair: Bool & F32,+direction: U32,+j: U32,+index: U32,+cost: F32,+end: U32,+start: U32,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,open: List<&2,Node>) -> Array<F32> & (Array<U32> & List<&2,Node>):
  (blocked,risk) = pair
  neighbor_old(Array.get(F32,costs,j),Bool.and(Bool.or(Bool.not(blocked),U32.is_eq(j,start)),corner_clear(direction,index,grid)),j,index,(cost + yes(U32.is_lt(direction,4),1.0,1.41421356237) * (1.0 + risk * 2.0) : F32),end,previous,open)
def neighbor_valid(valid: Bool,+direction: U32,+index: U32,+cost: F32,+end: U32,+start: U32,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,open: List<&2,Node>) -> Array<F32> & (Array<U32> & List<&2,Node>):
  match valid:
    case False{}: (costs,(previous,open))
    case True{}:
      +j=adjacent(index,direction)
      neighbor_danger(grid_danger(grid,j),direction,j,index,cost,end,start,grid,costs,previous,open)
def expand_neighbors(fuel: Nat,+direction: U32,+index: U32,+cost: F32,+end: U32,+start: U32,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,open: List<&2,Node>) -> Array<F32> & (Array<U32> & List<&2,Node>):
  match fuel:
    case 0n: (costs,(previous,open))
    case 1n+rest:
      bind(~Array<F32>,~(Array<U32> & List<&2,Node>),~(Array<F32> & (Array<U32> & List<&2,Node>)),neighbor_valid(valid_neighbor(index,direction),direction,index,cost,end,start,grid,costs,previous,open),(costs => tail =>
        bind(~Array<U32>,~List<&2,Node>,~(Array<F32> & (Array<U32> & List<&2,Node>)),tail,(previous => open => expand_neighbors(rest,(direction + 1 : U32),index,cost,end,start,grid,costs,previous,open)))
      ))
def backtrack_loop(fuel: Nat,done: Bool,+index: U32,+start: U32,previous: Array<U32>,path: List<&2,Point>) -> List<&2,Point>:
  match fuel done:
    case 0n _: path
    case _ True{}: path
    case 1n+rest False{}:
      bind(~Array<U32>,~U32,~List<&2,Point>,Array.get(U32,previous,index),(previous => +next => backtrack_loop(rest,U32.is_eq(next,start),next,start,previous,cell_point(index) <> path)))
def backtrack(fuel: Nat,+index: U32,+start: U32,previous: Array<U32>,path: List<&2,Point>) -> List<&2,Point>:
  backtrack_loop(fuel,U32.is_eq(index,start),index,start,previous,path)
def route_metrics(+path: List<&2,Point>,+here: Point,+grid: R.Frozen,+length: F32,+risk: F32,+count: U32) -> F32 & F32:
  match path:
    case []: (length,(risk / F32.max(1.0,U32.to_f32(count)) : F32))
    case +point <> []: ((length + distance(here,point) : F32),(risk / F32.max(1.0,U32.to_f32(count)) : F32))
    case +point <> rest:
      bind(~(Bool),~(F32),~(F32 & F32),grid_danger(grid,cell_index(point)),(+ignored => +hazard =>
        route_metrics(rest,point,grid,(length + distance(here,point) : F32),(risk + hazard : F32),(count + 1 : U32))
      ))
type SearchStep is Type:
  SearchContinue{costs: Array<F32>,previous: Array<U32>,closed: Array<U32>,open: List<&2,Node>,expanded: U32}
  SearchFinished{route: Route}
def search_reached(reached: Bool,+index: U32,+cost: F32,+end: U32,+start: U32,+target: Point,+here: Point,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,closed: Array<U32>,tail: List<&2,Node>,+expanded: U32) -> SearchStep:
  match reached:
    case True{}:
      +path=backtrack(3600n,index,start,previous,[target])
      bind(~F32,~F32,~SearchStep,route_metrics(path,here,grid,0.0,0.0,0),(length => risk => SearchFinished{Route{True{},path,length,risk,(expanded + 1 : U32)}}))
    case False{}:
      closed=Array.set(U32,closed,index,1)
      bind(~Array<F32>,~(Array<U32> & List<&2,Node>),~SearchStep,expand_neighbors(8n,0,index,cost,end,start,grid,costs,previous,tail),(costs => nested =>
        bind(~Array<U32>,~List<&2,Node>,~SearchStep,nested,(previous => open => SearchContinue{costs,previous,closed,open,(expanded + 1 : U32)}))
      ))
def search_limit(exhausted: Bool,+index: U32,+cost: F32,+end: U32,+start: U32,+target: Point,+here: Point,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,closed: Array<U32>,tail: List<&2,Node>,+expanded: U32,+budget: U32) -> SearchStep:
  match exhausted:
    case True{}: SearchFinished{Route{False{},[],0.0,0.0,expanded}}
    case False{}: search_reached(U32.is_eq(index,end),index,cost,end,start,target,here,grid,costs,previous,closed,tail,expanded)
def search_visited(visited: Bool,+index: U32,+cost: F32,+end: U32,+start: U32,+target: Point,+here: Point,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,closed: Array<U32>,tail: List<&2,Node>,+expanded: U32,+budget: U32) -> SearchStep:
  match visited:
    case True{}: SearchContinue{costs,previous,closed,tail,expanded}
    case False{}: search_limit(U32.is_le(budget,expanded),index,cost,end,start,target,here,grid,costs,previous,closed,tail,expanded,budget)
def search_read(pair: Array<U32> & U32,+index: U32,+cost: F32,+end: U32,+start: U32,+target: Point,+here: Point,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,tail: List<&2,Node>,+expanded: U32,+budget: U32) -> SearchStep:
  (closed,visited) = pair
  search_visited(U32.is_eq(visited,1),index,cost,end,start,target,here,grid,costs,previous,closed,tail,expanded,budget)
def search_resume(step: SearchStep,use: Array<F32> -> Array<U32> -> Array<U32> -> List<&2,Node> -> U32 -> Route) -> Route:
  match step:
    case SearchFinished{route}: route
    case SearchContinue{costs,previous,closed,open,expanded}: use(costs)(previous)(closed)(open)(expanded)
def search(fuel: Nat,+start: U32,+end: U32,+target: Point,+here: Point,+grid: R.Frozen,costs: Array<F32>,previous: Array<U32>,closed: Array<U32>,open: List<&2,Node>,+expanded: U32,+budget: U32) -> Route:
  match fuel open:
    case 0n _: Route{False{},[],0.0,0.0,expanded}
    case _ Nil{}: Route{False{},[],0.0,0.0,expanded}
    case 1n+rest Con{Node{+index,+cost,_},tail}:
      search_resume(search_read(Array.get(U32,closed,index),index,cost,end,start,target,here,grid,costs,previous,tail,expanded,budget),(costs => previous => closed => open => expanded => search(rest,start,end,target,here,grid,costs,previous,closed,open,expanded,budget)))
def route_grid(+here: Point,+target: Point,+grid: R.Frozen,+budget: U32) -> Route:
  +start=cell_index(here)
  +end=cell_index(target)
  bind(~Bool,~F32,~Route,grid_danger(grid,end),(+blocked => ignored =>
    branch(~Route,Bool.and(blocked,Bool.not(U32.is_eq(start,end))),(_ => Route{False{},[],0.0,0.0,0}),(_ =>
      costs=Array.set(F32,[1.0e30 : F32*4096n],start,0.0)
      search(U32.to_nat((budget * 9 + 1 : U32)),start,end,target,here,grid,costs,[0 : U32*4096n],[0 : U32*4096n],[Node{start,0.0,heuristic(start,end)}],0,budget)
    ))
  ))
def shifted_point(point:Point,+ox:F32,+oy:F32) -> Point:
  match point:
    case Point{x,y}: Point{(x - ox : F32),(y - oy : F32)}
def projected_point(point:Point) -> Point:
  match point:
    case Point{x,y}: Point{F32.clamp(x,0.0,3600.0),F32.clamp(y,0.0,3600.0)}
def world_path(path:List<&2,Point>,+ox:F32,+oy:F32) -> List<&2,Point>:
  match path:
    case []: []
    case Point{x,y} <> rest: Point{(x + ox : F32),(y + oy : F32)} <> world_path(rest,ox,oy)
def world_route(result:Route,+ox:F32,+oy:F32,remaining:F32) -> Route:
  match result:
    case Route{found,path,length,risk,expanded}: Route{found,world_path(path,ox,oy),(length + remaining : F32),risk,expanded}
def route_window(+here:Point,+target:Point,window:R.RiskWindow,budget:U32) -> Route:
  match window:
    case R.RiskWindow{+x,+y,cells}:
      +localTarget=shifted_point(target,x,y)
      +projected=projected_point(localTarget)
      world_route(route_grid(shifted_point(here,x,y),projected,cells,budget),x,y,distance(localTarget,projected))
def here_window(here:Point,rows:List<&2,Threats.Threat>) -> R.RiskWindow:
  match here:
    case Point{x,y}: R.window(rows,x,y,G.world_size(),G.world_margin())
def route(+here: Point,+target: Point,rows: List<&2,Threats.Threat>,budget: U32) -> Route: route_window(here,target,here_window(here,rows),budget)

type Attempt is Data: Attempt{result: Route,goal: Goal,expanded: U32}
def insert_near(+goal: Goal,+rows: List<&2,Goal>,+here: Point) -> List<&2,Goal>:
  match rows:
    case []: [goal]
    case +old <> rest:
      +a=distance(here,goal_point(goal))
      +b=distance(here,goal_point(old))
      branch(~List<&2,Goal>,Bool.or(F32.is_lt(a,b),Bool.and(F32.is_eq(a,b),String.is_lt(goal_id(goal),goal_id(old)))),(_ => goal <> old <> rest),(_ => old <> insert_near(goal,rest,here)))
def sorted_representatives(+rows: List<&2,Goal>,+goal: Goal,+here: Point,+acc: List<&2,Goal>) -> List<&2,Goal>:
  match rows:
    case []: acc
    case +member <> rest:
      +relevant=Bool.and(U32.is_eq(goal_kind(goal),2),Bool.and(U32.is_eq(goal_kind(member),2),same_cluster(goal_cluster(goal),goal_cluster(member))))
      branch(~List<&2,Goal>,relevant,(_ => sorted_representatives(rest,goal,here,insert_near(member,acc,here))),(_ => sorted_representatives(rest,goal,here,acc)))
def representatives(+observed: List<&2,Goal>,+goal: Goal,+here: Point) -> List<&2,Goal>:
  branch(~List<&2,Goal>,U32.is_eq(goal_kind(goal),2),(_ => sorted_representatives(observed,goal,here,[])),(_ => [goal]))
def try_representatives(+fuel: Nat,+result: Route,+last: Goal,+reps: List<&2,Goal>,+here: Point,+grid: R.RiskWindow,+budget: U32,+used: U32) -> Attempt:
  match fuel result reps:
    case _ Route{True{},+path,+length,+risk,+expanded} _: Attempt{Route{True{},path,length,risk,expanded},last,(used + expanded : U32)}
    case 0n Route{False{},_,_,_,+expanded} _: Attempt{Route{False{},[],0.0,0.0,expanded},last,(used + expanded : U32)}
    case _ Route{False{},_,_,_,+expanded} Nil{}: Attempt{Route{False{},[],0.0,0.0,expanded},last,(used + expanded : U32)}
    case 1n+rest Route{False{},_,_,_,+expanded} Con{+next,tail}:
      +spent=(used + expanded : U32)
      branch(~Attempt,U32.is_lt(spent,budget),(_ => try_representatives(rest,route_window(here,goal_point(next),grid,(budget - spent : U32)),next,tail,here,grid,budget,spent)),(_ => Attempt{Route{False{},[],0.0,0.0,0},last,spent}))
def choice_score(+choice: Choice) -> F32:
  match choice:
    case Choice{_,_,score}: score
def goal_reward(+goal: Goal) -> F32:
  match goal:
    case Goal{_,_,_,_,_,reward,_}: reward
def choose(+new: Choice,+old: Maybe<&2,Choice>) -> Maybe<&2,Choice>:
  match old:
    case None{}: Some{new}
    case Some{+prior}: branch(~Maybe<&2,Choice>,F32.is_lt(choice_score(prior),choice_score(new)),(_ => Some{new}),(_ => Some{prior}))
def scored_route(+result: Route,+goal: Goal,+reward: F32,+speed: F32,+fragile: Bool) -> Maybe<&2,Choice>:
  match result:
    case Route{False{},_,_,_,_}: None{}
    case Route{True{},path,length,risk,_}:
      Some{Choice{goal,path,(reward / (1.0 + length / (2.5 * F32.max(0.1,speed)) / 60.0) / (1.0 + risk * yes(fragile,4.0,1.0)) : F32)}}
def matches_current(+current: Maybe<&2,Choice>,+goal: Goal) -> Bool:
  match current:
    case None{}: False{}
    case Some{Choice{old,_,_}}: same(old,goal)
def penalty(+result: Maybe<&2,Choice>,+current: Maybe<&2,Choice>,+stuck: Bool) -> Maybe<&2,Choice>:
  match result:
    case None{}: None{}
    case Some{Choice{+goal,path,score}}: Some{Choice{goal,path,(score * yes(Bool.and(stuck,matches_current(current,goal)),0.2,1.0) : F32)}}
def retain(+test: Bool,+candidate: Choice,+old: Maybe<&2,Choice>) -> Maybe<&2,Choice>:
  branch(~(Maybe<&2,Choice>),test,(_ =>
      Some{candidate}
  ),(_ =>
      old

  ))
def choice_goal(+choice: Choice) -> Goal:
  match choice:
    case Choice{goal,_,_}: goal
def merge_candidate(+result: Maybe<&2,Choice>,+current: Maybe<&2,Choice>,+best: Maybe<&2,Choice>,+retained: Maybe<&2,Choice>) -> Maybe<&2,Choice> & Maybe<&2,Choice>:
  match result:
    case None{}: (best,retained)
    case Some{+candidate}: (choose(candidate,best),retain(matches_current(current,choice_goal(candidate)),candidate,retained))
type Plan is Data: Plan{best: Maybe<&2,Choice>,retained: Maybe<&2,Choice>,choices: List<&2,Choice>}
def add_prepared(+candidate: Maybe<&2,Choice>,+prior: List<&2,Choice>) -> List<&2,Choice>:
  match candidate:
    case None{}: prior
    case Some{choice}: choice <> prior
def score_attempt(attempt: Attempt,+aggregate: Goal,+speed: F32,+fragile: Bool) -> Maybe<&2,Choice>:
  match attempt:
    case Attempt{result,actual,_}: scored_route(result,actual,goal_reward(aggregate),speed,fragile)
def candidates(+fuel: Nat,+goals: List<&2,Goal>,+here: Point,+observed: List<&2,Goal>,+grid: R.RiskWindow,+speed: F32,+fragile: Bool,+stuck: Bool,+current: Maybe<&2,Choice>,+best: Maybe<&2,Choice>,+retained: Maybe<&2,Choice>,+prepared: List<&2,Choice>) -> Plan:
  match fuel goals:
    case 0n _: Plan{best,retained,prepared}
    case _ Nil{}: Plan{best,retained,prepared}
    case 1n+rest Con{+goal,tail}:
      +attempt=try_representatives(3n,Route{False{},[],0.0,0.0,0},goal,representatives(observed,goal,here),here,grid,150,0)
      +candidate=penalty(score_attempt(attempt,goal,speed,fragile),current,stuck)
      bind(~(Maybe<&2,Choice>),~(Maybe<&2,Choice>),~Plan,merge_candidate(candidate,current,best,retained),(+best => +retained => candidates(rest,tail,here,observed,grid,speed,fragile,stuck,current,best,retained,add_prepared(candidate,prepared))))
def plan_best(plan: Plan) -> Maybe<&2,Choice>:
  match plan:
    case Plan{best,_,_}: best
def plan_retained(plan: Plan) -> Maybe<&2,Choice>:
  match plan:
    case Plan{_,retained,_}: retained
def plan_choices(plan: Plan) -> List<&2,Choice>:
  match plan:
    case Plan{_,_,choices}: choices
def select_retained(+best: Maybe<&2,Choice>,+retained: Maybe<&2,Choice>,+force: Bool) -> Maybe<&2,Choice>:
  match best retained force:
    case Some{+new} Some{+old} False{}: branch(~Maybe<&2,Choice>,F32.is_lt(choice_score(new),(choice_score(old) * 1.35 : F32)),(_ => Some{old}),(_ => Some{new}))
    case +new _ _: new

def trim(+path: List<&2,Point>,+here: Point) -> List<&2,Point>:
  match path:
    case []: []
    case point <> []: [point]
    case +point <> rest:
      branch(~(List<&2,Point>),F32.is_lt(distance(here,point),35.0),(_ =>
          trim(rest,here)
      ),(_ =>
          point <> rest
      ))
def refreshed(+goal: Maybe<&2,Goal>,+path: List<&2,Point>,+score: F32,+here: Point) -> Maybe<&2,Choice>:
  match goal:
    case None{}: None{}
    case Some{fresh}: Some{Choice{fresh,trim(path,here),score}}
def refresh(+current: Maybe<&2,Choice>,+observed: List<&2,Goal>,+here: Point) -> Maybe<&2,Choice>:
  match current:
    case None{}: None{}
    case Some{Choice{goal,path,score}}: refreshed(find_goal(observed,goal),path,score,here)
def first_non_xp(+rows: List<&2,Goal>) -> Maybe<&2,Goal>:
  match rows:
    case []: None{}
    case +goal <> rest: branch(~Maybe<&2,Goal>,Bool.and(Bool.not(U32.is_eq(goal_kind(goal),2)),U32.is_lt(goal_kind(goal),12)),(_ => Some{goal}),(_ => first_non_xp(rest)))
def first_cardinal(+rows: List<&2,Goal>) -> Maybe<&2,Goal>:
  match rows:
    case []: None{}
    case +goal <> rest: branch(~Maybe<&2,Goal>,U32.is_le(12,goal_kind(goal)),(_ => Some{goal}),(_ => first_cardinal(rest)))
def same_pool(+a: Goal,+b: Goal) -> Bool:
  Bool.or(same(a,b),Bool.and(U32.is_eq(goal_kind(a),2),Bool.and(U32.is_eq(goal_kind(b),2),same_cluster(goal_cluster(a),goal_cluster(b)))))
def remove_pool(+rows: List<&2,Goal>,+goal: Goal) -> List<&2,Goal>:
  match rows:
    case []: []
    case +old <> rest: branch(~List<&2,Goal>,same_pool(old,goal),(_ => remove_pool(rest,goal)),(_ => old <> remove_pool(rest,goal)))
def reserve(+extra: Maybe<&2,Goal>,+rows: List<&2,Goal>) -> List<&2,Goal>:
  match extra:
    case None{}: rows
    case Some{+goal}: goal <> remove_pool(rows,goal)
def find_pool(+pool: List<&2,Goal>,+wanted: Goal) -> Maybe<&2,Goal>:
  match pool:
    case []: None{}
    case +goal <> rest: branch(~Maybe<&2,Goal>,same_pool(goal,wanted),(_ => Some{goal}),(_ => find_pool(rest,wanted)))
def current_pool(+pool: List<&2,Goal>,+current: Maybe<&2,Goal>) -> Maybe<&2,Goal>:
  match current:
    case None{}: None{}
    case Some{goal}: find_pool(pool,goal)
def suppress_cardinal(+choice: Maybe<&2,Choice>,+damaged: Bool,+fragile: Bool) -> Maybe<&2,Choice>:
  match choice:
    case None{}: None{}
    case Some{+candidate}: branch(~Maybe<&2,Choice>,Bool.and(U32.is_le(12,goal_kind(choice_goal(candidate))),Bool.not(Bool.or(damaged,fragile))),(_ => None{}),(_ => Some{candidate}))

def nearest(+rows: List<&2,Enemy.State>,+here: Point,+best: Space.Spatial,+bestDistance: F32,+count: U32) -> Space.Spatial & U32:
  match rows:
    case []: (best,count)
    case Enemy.State{Space.Spatial{+x,+y,+age,+radius},_,_,Components.Vitals{health,_},_} <> rest:
          branch(~(Space.Spatial & U32),U32.is_lt(0,health),(_ =>
              +d=distance(here,Point{x,y})
              branch(~(Space.Spatial & U32),F32.is_lt(d,bestDistance),(_ =>
                  nearest(rest,here,Space.Spatial{x,y,age,radius},d,(count + 1 : U32))
              ),(_ =>
                  nearest(rest,here,best,bestDistance,(count + 1 : U32))
              ))
          ),(_ => nearest(rest,here,best,bestDistance,count)))
def shot_radius(shot: Shots.Shot) -> F32:
  match shot:
    case Shots.Shot{_,_,_,_,radius,_,_}: radius

def self_field_radius(enabled: Bool,id: U32,rank: U32,speed: F32,area: F32,duration: F32) -> F32:
  match enabled:
    case False{}: 0.0
    case True{}: shot_radius(Shots.spawn(id,rank,0,0.0,0.0,0.0,0.0,1.0,0.0,speed,area,duration))

def aura(+rows: List<&2,U32>,+index: U32,+passives: List<&2,U32>,+arcana: U32,+all: Bool,+maximum: F32,+count: U32) -> Bool & F32:
  match rows:
    case []: (Bool.and(all,U32.is_lt(0,count)),maximum)
    case 0 <> rest: aura(rest,(index + 1 : U32),passives,arcana,all,maximum,count)
    case +rank <> rest:
      +radius=self_field_radius(Bool.and(U32.is_lt(rank,9),Bool.or(U32.is_eq(index,4),U32.is_eq(index,22))),index,rank,G.projectile_speed(passives,arcana),G.area_bonus(passives,arcana,rank),G.duration_bonus(passives,arcana))
      aura(rest,(index + 1 : U32),passives,arcana,Bool.and(all,F32.is_lt(0.0,radius)),F32.max(maximum,radius),(count + 1 : U32))
def point_x(+point: Point) -> F32:
  match point:
    case Point{x,_}: x
def point_y(+point: Point) -> F32:
  match point:
    case Point{_,y}: y
def avoid(+rows: List<&2,Threats.Threat>,+here: Point,+close: Bool,+dx: F32,+dy: F32) -> F32 & F32:
  match rows:
    case []: (dx,dy)
    case Threats.Threat{+x,+y,+radius,hostile} <> rest:
      +px=point_x(here)
      +py=point_y(here)
      +u=(px - x : F32)
      +v=(py - y : F32)
      +d=F32.max(1.0,hypot(u,v))
      +contact=Bool.and(close,Bool.not(hostile))
      +force=(F32.max(0.0,(yes(contact,(radius + 26.0 : F32),140.0) - d : F32)) * yes(contact,12.0,4.0) : F32)
      avoid(rest,here,close,(dx + u / d * force : F32),(dy + v / d * force : F32))
def initial_vector(+target: Maybe<&2,Point>,+px: F32,+py: F32,+nx: F32,+ny: F32,+nd: F32,+radial: F32,+close: Bool) -> F32 & F32:
  match target:
    case Some{Point{tx,ty}}: ((tx - px : F32),(ty - py : F32))
    case None{}: ((nx / nd * radial * 6.0 + ny / nd * yes(close,12.0,35.0) + (G.world_center() - px) * 0.05 : F32),(ny / nd * radial * 6.0 - nx / nd * yes(close,12.0,35.0) + (G.world_center() - py) * 0.05 : F32))
def steer_enemy(+enemy: Space.Spatial,+rows: List<&2,Threats.Threat>,+target: Maybe<&2,Point>,+px: F32,+py: F32,+here: Point,+close: Bool,+radius: F32) -> F32 & F32:
  match enemy:
    case Space.Spatial{x,y,_,r}:
      +nx=(px - x : F32)
      +ny=(py - y : F32)
      +nd=F32.max(1.0,hypot(nx,ny))
      +desired=yes(close,F32.max((r + 26.0 : F32),(radius + r - 6.0 : F32)),220.0)
      +radial=yes(close,F32.max((0.0 - 30.0 : F32),F32.min(30.0,(desired - nd : F32))),F32.max(0.0,(220.0 - nd : F32)))
      bind(~(F32),~(F32),~(F32 & F32),initial_vector(target,px,py,nx,ny,nd,radial,close),(+dx => +dy =>
        bind(~(F32),~(F32),~(F32 & F32),avoid(rows,here,close,dx,dy),(+dx => +dy =>
          +dx=(dx + yes(F32.is_lt(px,(G.world_margin() + 180.0 : F32)),1000.0,0.0) - yes(F32.is_lt((G.world_size() - G.world_margin() - 180.0 : F32),px),1000.0,0.0) : F32)
          +dy=(dy + yes(F32.is_lt(py,(G.world_margin() + 180.0 : F32)),1000.0,0.0) - yes(F32.is_lt((G.world_size() - G.world_margin() - 180.0 : F32),py),1000.0,0.0) : F32)
          +length=F32.max(1.0,hypot(dx,dy))
          ((dx / length : F32),(dy / length : F32))
      ))
      ))
def steer(+run: G.Run,+rows: List<&2,Threats.Threat>,enemies: List<&2,Enemy.State>,+target: Maybe<&2,Point>) -> F32 & F32:
  match run:
    case G.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{+px,+py,_,_,_,weapons,+passives,_,+arcana,_,_,_,_,_,_,_}}:
      +here : Point = Point{px,py}
      bind(~(Space.Spatial),~(U32),~(F32 & F32),nearest(enemies,here,Space.Spatial{(px + 300.0 : F32),py,0,12.0},1000000.0,0),(+enemy => +count =>
        bind(~(Bool),~(F32),~(F32 & F32),aura(weapons,0,passives,arcana,True{},0.0,0),(+fields => +radius =>
          +close=Bool.and(fields,U32.is_lt(0,count))
          steer_enemy(enemy,rows,target,px,py,here,close,radius)
      ))
      ))
def target(+choice: Maybe<&2,Choice>) -> Maybe<&2,Point>:
  match choice:
    case Some{Choice{_,point <> _,_}}: Some{point}
    case _: None{}
def current_goal(+choice: Maybe<&2,Choice>) -> Maybe<&2,Goal>:
  match choice:
    case Some{Choice{goal,_,_}}: Some{goal}
    case None{}: None{}
def invalidated(+old: Maybe<&2,Choice>,+fresh: Maybe<&2,Choice>) -> Bool:
  match old fresh:
    case Some{_} None{}: True{}
    case _ _: False{}
def movement(+memory: Memory,+run: G.Run,+snapshots: List<&2,G.Snapshot>) -> Memory & (F32 & F32):
  match memory run:
    case Memory{+old,lastPlan,lastHp,+anchor,stuckSince,+initialized,+previousKeys,+prepared} G.Run{RS.Session{_,+tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{+px,+py,+hp,+maxHp,+character,_,+passives,_,+arcana,+meta,_,_,_,_,_,_}}:
      +dangerRows = threats(snapshots)
      +enemies = G.enemy_observations(snapshots)
      +here : Point = Point{px,py}
      +moved=F32.is_lt(12.0,distance(here,anchor))
      +since=branch(~(U32),Bool.or(moved,Bool.not(initialized)),(_ =>
          tick
      ),(_ =>
          stuckSince
      ))
      +anchor=branch(~(Point),Bool.or(moved,Bool.not(initialized)),(_ =>
          here
      ),(_ =>
          anchor
      ))
      +stuck=U32.is_le(120,(tick - since : U32))
      +damaged=Bool.and(initialized,U32.is_lt(hp,lastHp))
      +observed=List.append(&2,Goal,cardinals(px,py),goals_at(snapshots,tick))
      +keys=only_xp(observed)
      +fresh=refresh(old,observed,here)
      +invalid=invalidated(old,fresh)
      +due=Bool.or(Bool.not(initialized),Bool.or(Bool.and(no_choice(old),Bool.not(same_keys(previousKeys,keys))),Bool.or(invalid,Bool.or(damaged,Bool.or(stuck,U32.is_le(30,(tick - lastPlan : U32)))))))
      +fragile=F32.is_lt(U32.to_f32(hp),(U32.to_f32(maxHp) * 0.35 : F32))
      +plan=branch(~Plan,due,(_ =>
          +pool=sort_goals(clusters(observed,[],here),[],here)
          +pool=reserve(current_pool(pool,current_goal(fresh)),reserve(first_non_xp(pool),reserve(first_cardinal(pool),pool)))
          candidates(8n,pool,here,observed,here_window(here,dangerRows),G.speed_bonus(passives,meta,arcana,character),fragile,stuck,fresh,None{},None{},[])
      ),(_ => Plan{fresh,None{},prepared}))
      +chosen=suppress_cardinal(select_retained(plan_best(plan),plan_retained(plan),Bool.or(damaged,stuck)),damaged,fragile)
      +nextPlan=branch(~(U32),due,(_ =>
          tick
      ),(_ =>
          lastPlan
      ))
      +nextSince=branch(~(U32),stuck,(_ =>
          tick
      ),(_ =>
          since
      ))
      (Memory{chosen,nextPlan,hp,branch(~Point,stuck,(_ => here),(_ => anchor)),nextSince,True{},keys,plan_choices(plan)},steer(run,dangerRows,enemies,target(chosen)))
