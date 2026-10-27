import Base
import game.bend as G
import offline-policy.bend as P
import offline-policy/preference.bend as Nav
import offline-threats.bend as T
import pickup-state.bend as Pickup
import enemy-combat.bend as Enemy
import enemy-spatial.bend as Space
import projectile-state.bend as Shot
import game-components.bend as C

type View is Data: View{px:F32,py:F32,halfWidth:F32,halfHeight:F32}
type Goal is Data: Goal{index:U32,seed:U32,generation:U32,kind:U32,x:F32,y:F32,reward:F32,score:F32}
type Observation is Data: Observation{tick:U32,phase:U32,px:F32,py:F32,hp:U32,maxHp:U32,level:U32,weapons:List<&2,U32>,passives:List<&2,U32>,offers:List<&2,G.Offer>,goals:List<&2,Goal>,threats:List<&2,T.Threat>,fallback:U32,truncated:Bool}
type Intention is Data:
  GoalChoice{index:U32}
  UpgradeChoice{index:U32}
  Default{}
type Memory is Data: Memory{navigation:Nav.Navigation,pickups:List<&2,G.Snapshot>}
type Planned is Data: Planned{memory:Memory,observation:Observation,dx:F32,dy:F32}

def initial() -> Memory: Memory{Nav.initial(),[]}
def visible_geometry(geometry:G.SnapshotGeometry,view:View) -> Bool:
  match geometry view:
    case G.SnapshotGeometry{_,x,y,_,_} View{px,py,halfWidth,halfHeight}: Bool.and(F32.is_le(F32.abs((x - px : F32)),halfWidth),F32.is_le(F32.abs((y - py : F32)),halfHeight))
def visible(row:G.Snapshot,view:View) -> Bool: visible_geometry(G.snapshot_geometry(row),view)
def active(row:G.Snapshot) -> Bool:
  match row:
    case G.EnemySnapshot{Enemy.State{_,_,_,C.Vitals{hp,_},_}}: U32.is_gt(hp,0)
    case G.ProjectileSnapshot{Shot.State{_,_,Shot.HostileShot{},C.ShotPayload{_,_,active},_}}: active
    case G.PickupSnapshot{value}: Pickup.active(value)
    case _: False{}
def category(row:G.Snapshot) -> U32:
  match row:
    case G.EnemySnapshot{_}: 0
    case G.ProjectileSnapshot{_}: 1
    case G.PickupSnapshot{_}: 2
def pickup(row:G.Snapshot) -> Bool:
  match row:
    case G.PickupSnapshot{value}: Pickup.active(value)
    case _: False{}
def seen(rows:List<&2,G.Snapshot>,+view:View,+kind:U32,fuel:U32,+acc:List<&2,G.Snapshot>) -> List<&2,G.Snapshot>:
  match rows fuel:
    case _ 0: List.reverse(&2,G.Snapshot,acc)
    case Nil{} _: List.reverse(&2,G.Snapshot,acc)
    case Con{+row,+rest} +n:
      P.branch(~List<&2,G.Snapshot>,Bool.and(active(row),Bool.and(U32.is_eq(category(row),kind),visible(row,view))),(_ => seen(rest,view,kind,(n - 1 : U32),row <> acc)),(_ => seen(rest,view,kind,n,acc)))
def known(rows:List<&2,G.Snapshot>,+view:View,fuel:U32,+acc:List<&2,G.Snapshot>) -> List<&2,G.Snapshot>:
  match rows fuel:
    case _ 0: acc
    case Nil{} _: acc
    case Con{+row,+rest} +n:
      P.branch(~List<&2,G.Snapshot>,Bool.and(pickup(row),Bool.not(visible(row,view))),(_ => known(rest,view,(n - 1 : U32),row <> acc)),(_ => known(rest,view,n,acc)))
def pickups(rows:List<&2,G.Snapshot>,fuel:U32,+acc:List<&2,G.Snapshot>) -> List<&2,G.Snapshot>:
  match rows fuel:
    case _ 0: acc
    case Nil{} _: acc
    case Con{+row,+rest} +n:
      P.branch(~List<&2,G.Snapshot>,pickup(row),(_ => pickups(rest,(n - 1 : U32),row <> acc)),(_ => pickups(rest,n,acc)))
def project_choice(choice:P.Choice,index:U32) -> Goal:
  match choice:
    case P.Choice{P.Goal{seed,gen,kind,x,y,reward,_},_,score}: Goal{index,seed,gen,kind,x,y,reward,score}
def choices(rows:List<&2,P.Choice>,+index:U32,+fuel:U32) -> List<&2,Goal>:
  match rows:
    case []: []
    case +row <> +rest: P.branch(~List<&2,Goal>,U32.is_eq(fuel,0),(_ => []),(_ => project_choice(row,index) <> choices(rest,(index + 1 : U32),(fuel - 1 : U32))))
def candidates(nav:Nav.Navigation) -> List<&2,Goal>: choices(Nav.choices(nav),0,8)
def same_goal(a:Goal,b:Goal) -> Bool:
  match a b:
    case Goal{i,s,g,k,x,y,r,_} Goal{j,t,h,l,u,v,q,_}: Bool.and(U32.is_eq(i,j),Bool.and(U32.is_eq(s,t),Bool.and(U32.is_eq(g,h),Bool.and(U32.is_eq(k,l),Bool.and(U32.is_eq(F32.bits(x),F32.bits(u)),Bool.and(U32.is_eq(F32.bits(y),F32.bits(v)),U32.is_eq(F32.bits(r),F32.bits(q))))))))
def same_goals(a:List<&2,Goal>,b:List<&2,Goal>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case a <> rest b <> tail: Bool.and(same_goal(a,b),same_goals(rest,tail))
    case _ _: False{}
def choose(memory:Memory,index:U32) -> Memory:
  match memory:
    case Memory{navigation,pickups}: Memory{Nav.step(navigation,Nav.Pick{index}),pickups}
def fallback(memory:Memory) -> Memory:
  match memory:
    case Memory{navigation,pickups}: Memory{Nav.step(navigation,Nav.Default{}),pickups}
def live_offers(+phase:U32,offers:List<&2,G.Offer>) -> List<&2,G.Offer>: Bool.pick(List<&2,G.Offer>,Bool.or(U32.is_eq(phase,1),U32.is_eq(phase,2)),offers,[])
def direction(+navigation:Nav.Navigation,+run:G.Run,+snapshots:List<&2,G.Snapshot>) -> F32 & F32:
  P.steer(run,Nav.threats(snapshots,[]),G.enemy_observations(snapshots),P.target(Nav.selected(navigation)))
def observation(+run:G.Run,+offers:List<&2,G.Offer>,navigation:Nav.Navigation,+visible:List<&2,G.Snapshot>,truncated:Bool) -> Observation:
  Observation{G.run_tick(run),G.run_phase(run),G.run_px(run),G.run_py(run),G.run_hp(run),G.run_maxHp(run),G.run_level(run),G.run_weapons(run),G.run_passives(run),live_offers(G.run_phase(run),offers),candidates(navigation),Nav.threats(visible,[]),P.upgrade(run,offers),truncated}
def with_direction(navigation:Nav.Navigation,observation:Observation,knowledge:List<&2,G.Snapshot>,vector:F32 & F32) -> Planned:
  P.bind(~F32,~F32,~Planned,vector,(dx => dy => Planned{Memory{navigation,knowledge},observation,dx,dy}))
def finalize(+navigation:Nav.Navigation,+run:G.Run,offers:List<&2,G.Offer>,+visible:List<&2,G.Snapshot>,knowledge:List<&2,G.Snapshot>,truncated:Bool) -> Planned:
  with_direction(navigation,observation(run,offers,navigation,visible,truncated),knowledge,direction(navigation,run,visible))
def planned(navigation:Nav.Navigation,+run:G.Run,offers:List<&2,G.Offer>,+visible:List<&2,G.Snapshot>,+knowledge:List<&2,G.Snapshot>,truncated:Bool,view:View) -> Planned:
  finalize(Nav.step(navigation,Nav.Advance{run,List.append(&2,G.Snapshot,visible,known(knowledge,view,128,[]))}),run,offers,visible,knowledge,truncated)
def plan(memory:Memory,+run:G.Run,offers:List<&2,G.Offer>,+snapshots:List<&2,G.Snapshot>,width:F32,height:F32) -> Planned:
  match memory:
    case Memory{policy,old}:
      +view : View = View{G.run_px(run),G.run_py(run),(width / 2.0 : F32),(height / 2.0 : F32)}
      +enemies=seen(snapshots,view,0,128,[])
      +shots=seen(snapshots,view,1,64,[])
      +items=seen(snapshots,view,2,128,[])
      +visible=List.append(&2,G.Snapshot,enemies,List.append(&2,G.Snapshot,shots,items))
      +fresh=pickups(visible,128,[])
      +knowledge=known(old,view,(128 - U32.from_nat(List.length(&2,G.Snapshot,fresh)) : U32),fresh)
      planned(policy,run,offers,visible,knowledge,Bool.or(Nat.is_ge(List.length(&2,G.Snapshot,enemies),128n),Bool.or(Nat.is_ge(List.length(&2,G.Snapshot,shots),64n),Bool.or(Nat.is_ge(List.length(&2,G.Snapshot,items),128n),Nat.is_ge(List.length(&2,G.Snapshot,knowledge),128n)))),view)
