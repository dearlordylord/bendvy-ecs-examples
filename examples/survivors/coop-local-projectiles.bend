import ./game-observation.bend as Model
import run-state.bend as RS
import Base
import game-components.bend as Components
import projectile-state.bend as Shot
import enemy-spatial.bend as Space
import ./game.bend as G
import ./enemy-targets.bend as Targets
import ./projectile.bend as Projectile
import ./projectile-contact.bend as Contact
import ./projectile-pool.bend as SP
import ./body-index.bend as BI
import ./coop-prediction.bend as Prediction
import ./coop-session.bend as Session
import ./player-movement.bend as Move
import ./coop-combat-broadphase.bend as Broadphase
import ./coop-prediction-replay.bend as Replay
import ./coop-hit-journal.bend as Journal
import ./coop-local-projectiles-policy.bend as Policy

# Visual-only local anticipation. No World, HP, loot, or progression state is
# reachable here. Remote targets are observations from one displayed cohort.
type Target is Data: Target{seed:U32,generation:U32,x:F32,y:F32,radius:F32,alive:Bool}
type Point is Data: Point{x:F32,y:F32}
type Geometry is Data: Geometry{targets:List<&2,Target>,aims:Targets.Targets,contacts:List<&2,Contact.Target>,index:Broadphase.Index,policyTargets:List<&2,Policy.Target>}
type Visual is Data:
  Visual{id:String,weaponOwner:U32,slot:SP.Emission,weapon:U32,poolSeed:U32,age:U32,originX:F32,originY:F32,shot:Projectile.Shot,pending:Bool,predictedSeed:U32,predictedGeneration:U32,predictedX:F32,predictedY:F32,pendingAge:U32,confirmed:Bool,late:Bool,event:Maybe<&2,Journal.HitEvent>,guideTick:U32,guideX:F32,guideY:F32,fade:U32}
type RenderShot is Data: RenderShot{id:String,player:U32,kind:U32,weapon:U32,seed:U32,age:U32,x:F32,y:F32,radius:F32,life:U32,fade:U32,opacity:F32}
type ContactFx is Data: ContactFx{id:String,tick:U32,kind:U32,targetSeed:U32,targetGeneration:U32,x:F32,y:F32,radius:F32,age:U32,opacity:F32}
type TargetFade is Data: TargetFade{id:String,seed:U32,generation:U32,x:F32,y:F32,radius:F32,lastSeen:U32}
type RenderFrame is Data: RenderFrame{shots:List<&2,RenderShot>,contacts:List<&2,ContactFx>,corpses:List<&2,TargetFade>}
type Tombstone is Data: Tombstone{shotId:String,target:Target,lastSeen:U32}
type Effect is Data: Effect{event:Journal.HitEvent,started:U32}
type KnownShot is Data: KnownShot{player:U32,id:String,seenTick:U32}
type BootstrapResult is Data: BootstrapResult{state:State,started:Bool}
type State is Data:
  State{shots:List<&2,Visual>,known:List<&2,KnownShot>,events:List<&2,Journal.HitEvent>,tombstones:List<&2,Tombstone>,effects:List<&2,Effect>,hasAccepted:Bool,lastAccepted:U32,displayTick:U32,dropped:U32,knownDropped:U32}

def shot_cap() -> Nat: 512n
def event_cap() -> Nat: 512n
def history_window() -> U32: 64
def bootstrap_cap() -> U32: 54
def pending_cap() -> U32: 8
def fade_ticks() -> U32: 4
def empty() -> State: State{[],[],[],[],[],False{},0,0,0,0}
def observed_target(seed:U32,kind:U32,age:U32,sourceTick:U32,x:F32,y:F32,radius:F32,hp:U32) -> Maybe<&2,Target>:
  Bool.pick(Maybe<&2,Target>,Bool.and(U32.is_eq(kind,0),U32.is_gt(hp,0)),Some{Target{seed,(sourceTick - age : U32),Prediction.normalize(x),Prediction.normalize(y),Prediction.normalize(radius),True{}}},None{})
def shots(state:State) -> List<&2,Visual>:
  match state:
    case State{rows,_,_,_,_,_,_,_,_,_}: rows
def known_shots(state:State) -> List<&2,KnownShot>:
  match state:
    case State{_,rows,_,_,_,_,_,_,_,_}: rows
def events(state:State) -> List<&2,Journal.HitEvent>:
  match state:
    case State{_,_,rows,_,_,_,_,_,_,_}: rows
def tombstones(state:State) -> List<&2,Tombstone>:
  match state:
    case State{_,_,_,rows,_,_,_,_,_,_}: rows
def effects(state:State) -> List<&2,Effect>:
  match state:
    case State{_,_,_,_,rows,_,_,_,_,_}: rows
def accepted_tick(state:State) -> U32:
  match state:
    case State{_,_,_,_,_,_,tick,_,_,_}: tick
def display_tick(state:State) -> U32:
  match state:
    case State{_,_,_,_,_,_,_,tick,_,_}: tick
def has_accepted(state:State) -> Bool:
  match state:
    case State{_,_,_,_,_,accepted,_,_,_,_}: accepted
def dropped(state:State) -> U32:
  match state:
    case State{_,_,_,_,_,_,_,_,count,_}: count
def known_dropped(state:State) -> U32:
  match state:
    case State{_,_,_,_,_,_,_,_,_,count}: count

def identity(player:U32,bornTick:U32,owner:U32,slot:SP.Emission) -> String:
  Replay.generation(player,bornTick,0,owner,SP.emission_slot(slot))
def request_identity(bornTick:U32,request:SP.Request) -> String:
  match request:
    case SP.Request{owner,+slot,_}: identity(SP.emission_player(slot),bornTick,owner,slot)
def origin_x(value:Visual) -> F32:
  match value:
    case Visual{_,_,_,_,_,_,x,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: x
def origin_y(value:Visual) -> F32:
  match value:
    case Visual{_,_,_,_,_,_,_,y,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: y
def run_point(run:Model.Run) -> Point:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{x,y,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: Point{x,y}
def shot_id(value:Visual) -> String:
  match value:
    case Visual{id,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: id
def visual_age(value:Visual) -> U32:
  match value:
    case Visual{_,_,_,_,_,age,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: age
def pool_seed(value:Visual) -> U32:
  match value:
    case Visual{_,_,_,_,seed,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: seed
def event_id(value:Journal.HitEvent) -> String:
  match value:
    case Journal.HitEvent{id,_,_,_,_,_,_,_,_,_,_,_,_,_}: id
def event_shot_id(value:Journal.HitEvent) -> String:
  match value:
    case Journal.HitEvent{_,_,_,shotId,_,_,_,_,_,_,_,_,_,_}: shotId
def event_tick(value:Journal.HitEvent) -> U32:
  match value:
    case Journal.HitEvent{_,tick,_,_,_,_,_,_,_,_,_,_,_,_}: tick
def event_kind(value:Journal.HitEvent) -> U32:
  match value:
    case Journal.HitEvent{_,_,kind,_,_,_,_,_,_,_,_,_,_,_}: kind
def event_outcome(value:Journal.HitEvent) -> U32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,_,_,_,_,_,outcome}: outcome
def event_radius(value:Journal.HitEvent) -> F32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,_,_,_,_,radius,_}: radius
def event_target_seed(value:Journal.HitEvent) -> U32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,seed,_,_,_,_,_,_,_,_}: seed
def event_target_generation(value:Journal.HitEvent) -> U32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,generation,_,_,_,_,_,_,_}: generation
def event_impact(value:Journal.HitEvent) -> Point:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,x,y,_,_,_,_}: Point{x,y}
def event_target_at_impact(value:Journal.HitEvent) -> Point:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,_,_,x,y,_,_}: Point{x,y}
def event_impact_x(value:Journal.HitEvent) -> F32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,x,_,_,_,_,_}: x
def event_impact_y(value:Journal.HitEvent) -> F32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,_,y,_,_,_,_}: y
def event_target_at_impact_x(value:Journal.HitEvent) -> F32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,_,_,x,_,_,_}: x
def event_target_at_impact_y(value:Journal.HitEvent) -> F32:
  match value:
    case Journal.HitEvent{_,_,_,_,_,_,_,_,_,_,_,y,_,_}: y
def policy_event(value:Journal.HitEvent) -> Policy.Hit:
  match value:
    case Journal.HitEvent{_,tick,kind,shotId,_,targetSeed,targetGeneration,_,impactX,impactY,targetAtImpactX,targetAtImpactY,radius,outcome}:
      Policy.Hit{shotId,tick,kind,targetSeed,targetGeneration,impactX,impactY,targetAtImpactX,targetAtImpactY,radius,outcome}
def policy_events(rows:List<&2,Journal.HitEvent>) -> List<&2,Policy.Hit>:
  match rows:
    case []: []
    case +head <> tail: policy_event(head) <> policy_events(tail)
def point_offset_x(impact:Point,target:Point) -> F32:
  match impact target:
    case Point{x,_} Point{tx,_}: (x - tx : F32)
def point_offset_y(impact:Point,target:Point) -> F32:
  match impact target:
    case Point{_,y} Point{_,ty}: (y - ty : F32)
def event_offset_x(+value:Journal.HitEvent) -> F32:
  point_offset_x(event_impact(value),event_target_at_impact(value))
def event_offset_y(+value:Journal.HitEvent) -> F32:
  point_offset_y(event_impact(value),event_target_at_impact(value))
def target_contact_point(+event:Journal.HitEvent,+x:F32,+y:F32) -> Point:
  Point{(x + event_offset_x(event) : F32),(y + event_offset_y(event) : F32)}

def target_seed(value:Target) -> U32:
  match value:
    case Target{seed,_,_,_,_,_}: seed
def target_generation(value:Target) -> U32:
  match value:
    case Target{_,generation,_,_,_,_}: generation
def target_x(value:Target) -> F32:
  match value:
    case Target{_,_,x,_,_,_}: x
def target_y(value:Target) -> F32:
  match value:
    case Target{_,_,_,y,_,_}: y
def target_radius(value:Target) -> F32:
  match value:
    case Target{_,_,_,_,radius,_}: radius
def target_by_seed(rows:List<&2,Target>,+seed:U32) -> Maybe<&2,Target>:
  match rows:
    case []: None{}
    case +head <> tail:
      Bool.pick(Maybe<&2,Target>,U32.is_eq(target_seed(head),seed),Some{head},target_by_seed(tail,seed))
def target_life(rows:List<&2,Target>,+seed:U32,+generation:U32) -> Maybe<&2,Target>:
  match rows:
    case []: None{}
    case +head <> tail:
      Bool.pick(Maybe<&2,Target>,Bool.and(U32.is_eq(target_seed(head),seed),U32.is_eq(target_generation(head),generation)),Some{head},target_life(tail,seed,generation))
def current_target_life(rows:List<&2,Target>,+seed:U32,+generation:U32) -> Maybe<&2,Target>:
  match rows:
    case []: None{}
    case Target{+storedSeed,+storedGeneration,x,y,radius,+alive} <> tail:
      Bool.pick(Maybe<&2,Target>,Bool.and(alive,Bool.and(U32.is_eq(storedSeed,seed),U32.is_eq(storedGeneration,generation))),Some{Target{storedSeed,storedGeneration,x,y,radius,alive}},current_target_life(tail,seed,generation))
def target_point(value:Target) -> Point:
  match value:
    case Target{_,_,x,y,_,_}: Point{x,y}
def policy_target(value:Target) -> Policy.Target:
  match value:
    case Target{seed,generation,x,y,radius,alive}: Policy.Target{seed,generation,x,y,radius,alive}
def policy_targets(rows:List<&2,Target>) -> List<&2,Policy.Target>:
  match rows:
    case []: []
    case +head <> tail: policy_target(head) <> policy_targets(tail)
def policy_point(value:Policy.Point) -> Point:
  match value:
    case Policy.Point{x,y}: Point{x,y}
def fallback_impact(found:Maybe<&2,Target>,+event:Journal.HitEvent) -> Point:
  match found event:
    case None{} _: event_impact(event)
    case Some{+target} _:
      target_contact_point(event,target_x(target),target_y(target))
def event_contact(+event:Journal.HitEvent,targets:List<&2,Target>) -> Point:
  policy_point(Policy.event_contact(policy_event(event),policy_targets(targets)))
def contact_x(point:Point) -> F32:
  match point:
    case Point{x,_}: x
def contact_y(point:Point) -> F32:
  match point:
    case Point{_,y}: y
def effect_point(event:Journal.HitEvent,targets:List<&2,Target>) -> Point:
  event_contact(event,targets)

def visual_position(value:Visual) -> Point:
  match value:
    case Visual{_,_,_,_,_,_,_,_,Projectile.Shot{x,y,_,_,_,_,_},pending,_,_,px,py,_,_,_,_,_,_,_,_}:
      Bool.pick(Point,pending,Point{px,py},Point{x,y})
def shot_x(value:Projectile.Shot) -> F32:
  match value:
    case Projectile.Shot{x,_,_,_,_,_,_}: x
def shot_y(value:Projectile.Shot) -> F32:
  match value:
    case Projectile.Shot{_,y,_,_,_,_,_}: y
def shot_radius(value:Projectile.Shot) -> F32:
  match value:
    case Projectile.Shot{_,_,_,_,radius,_,_}: radius
def shot_alive(value:Projectile.Shot) -> Bool:
  match value:
    case Projectile.Shot{_,_,_,_,_,life,_}: U32.is_gt(life,0)
def visual_weapon(value:Visual) -> U32:
  match value:
    case Visual{_,_,_,weapon,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: weapon
def visual_slot(value:Visual) -> SP.Emission:
  match value:
    case Visual{_,_,slot,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: slot
def with_position(value:Projectile.Shot,point:Point) -> Projectile.Shot:
  match value point:
    case Projectile.Shot{_,_,vx,vy,radius,life,pierce} Point{x,y}: Projectile.Shot{x,y,vx,vy,radius,life,pierce}
def with_life(value:Projectile.Shot,life:U32) -> Projectile.Shot:
  match value:
    case Projectile.Shot{x,y,vx,vy,radius,_,pierce}: Projectile.Shot{x,y,vx,vy,radius,life,pierce}
def shot_life(value:Projectile.Shot) -> U32:
  match value:
    case Projectile.Shot{_,_,_,_,_,life,_}: life
def policy_visual(value:Visual) -> Policy.VisibleShot:
  match value:
    case Visual{id,_,slot,_,_,_,_,_,shot,pending,_,_,_,_,_,confirmed,late,_,_,_,_,fade}:
      Policy.VisibleShot{id,SP.emission_player(slot),shot_life(shot),pending,confirmed,late,fade}
def policy_visuals(rows:List<&2,Visual>) -> List<&2,Policy.VisibleShot>:
  match rows:
    case []: []
    case +head <> tail: policy_visual(head) <> policy_visuals(tail)
def lerp(+a:F32,+b:F32,+t:F32) -> F32:
  (a + (b - a) * t : F32)
def lerp_point(start:Point,finish:Point,+t:F32) -> Point:
  match start finish:
    case Point{x0,y0} Point{x1,y1}: Point{lerp(x0,x1,t),lerp(y0,y1,t)}
def guide_progress(+start:U32,+finish:U32,+current:U32) -> F32:
  Bool.pick(F32,U32.is_le(current,start),0.0,Bool.pick(F32,U32.is_ge(current,finish),1.0,(U32.to_f32((current - start : U32)) / F32.max(1.0,U32.to_f32((finish - start : U32))) : F32)))
def guided_point(+event:Journal.HitEvent,startTick:U32,startX:F32,startY:F32,currentTick:U32,+targets:List<&2,Policy.Target>) -> Point:
  lerp_point(Point{startX,startY},policy_point(Policy.event_contact(policy_event(event),targets)),guide_progress(startTick,event_tick(event),currentTick))
def shown_point_selected(pending:Bool,confirmed:Bool,late:Bool,event:Maybe<&2,Journal.HitEvent>,predicted:Point,current:Point,guideTick:U32,guideX:F32,guideY:F32,presentationTick:U32,+targets:List<&2,Policy.Target>) -> Point:
  match pending confirmed late event:
    case True{} _ _ _: predicted
    case _ True{} True{} Some{hit}: policy_point(Policy.event_contact(policy_event(hit),targets))
    case _ True{} False{} Some{hit}: guided_point(hit,guideTick,guideX,guideY,presentationTick,targets)
    case _ _ _ _: current
def shown_point_prepared(value:Visual,presentationTick:U32,+targets:List<&2,Policy.Target>) -> Point:
  match value:
    case Visual{_,_,_,_,_,_,_,_,Projectile.Shot{x,y,_,_,_,_,_},pending,_,_,px,py,_,confirmed,late,event,guideTick,guideX,guideY,_}:
      shown_point_selected(pending,confirmed,late,event,Point{px,py},Point{x,y},guideTick,guideX,guideY,presentationTick,targets)
def shown_point(value:Visual,presentationTick:U32,+targets:List<&2,Target>) -> Point:
  shown_point_prepared(value,presentationTick,policy_targets(targets))
def visual_shot(value:Visual) -> Projectile.Shot:
  match value:
    case Visual{_,_,_,_,_,_,_,_,shot,_,_,_,_,_,_,_,_,_,_,_,_,_}: shot
def shown_shot(+value:Visual,presentationTick:U32,+targets:List<&2,Target>) -> Projectile.Shot:
  with_position(visual_shot(value),shown_point(value,presentationTick,targets))
def shown_shot_prepared(+value:Visual,presentationTick:U32,+targets:List<&2,Policy.Target>) -> Projectile.Shot:
  with_position(visual_shot(value),shown_point_prepared(value,presentationTick,targets))

# Pool-backed plan is rebuilt from the current local Run and latest observed
# projectile occupancy, with exactly one PlayerView. Nothing is replayed.
def live_aim_target(target:Target,tail:Targets.Targets) -> Targets.Targets:
  match target:
    case Target{seed,_,x,y,_,True{}}: Targets.add_aim(Targets.Target{x,y,seed},tail)
    case _: tail
def aim_targets(rows:List<&2,Target>) -> Targets.Targets:
  match rows:
    case []: Targets.empty()
    case head <> tail: live_aim_target(head,aim_targets(tail))
def attached_weapon(id:U32) -> Bool:
  match id:
    case 3: True{}
    case 4: True{}
    case 11: True{}
    case 19: True{}
    case 21: True{}
    case _: False{}
def attached_position(id:U32,+age:U32,+shot:Projectile.Shot,+x:F32,+y:F32) -> Projectile.Shot:
  match id:
    case 3: with_life(Projectile.orbit_step(shot,age,x,y,0.055),shot_life(shot))
    case 4: with_life(Projectile.anchored(shot,x,y),shot_life(shot))
    case 11: with_life(Projectile.anchored(shot,x,y),shot_life(shot))
    case 19: with_life(Projectile.orbit_step(shot,age,x,y,0.027),shot_life(shot))
    case 21: with_life(Projectile.orbit_step(shot,age,x,y,0.035),shot_life(shot))
    case _: shot
def reposition_attached(+value:Visual,+x:F32,+y:F32) -> Visual:
  match value:
    case Visual{id,owner,slot,weapon,poolSeed,age,originX,originY,shot,pending,seed,generation,px,py,pendingAge,confirmed,late,event,guideTick,guideX,guideY,fade}:
      Visual{id,owner,slot,weapon,poolSeed,age,originX,originY,attached_position(weapon,age,shot,x,y),pending,seed,generation,px,py,pendingAge,confirmed,late,event,guideTick,guideX,guideY,fade}
def reposition_attached_rows(rows:List<&2,Visual>,+x:F32,+y:F32) -> List<&2,Visual>:
  match rows:
    case []: []
    case head <> tail: reposition_attached(head,x,y) <> reposition_attached_rows(tail,x,y)
def released_run(+value:Visual,+run:Model.Run) -> Model.Run:
  match value run:
    case Visual{_,_,_,_,_,_,+originX,+originY,_,_,_,_,_,_,_,_,_,_,_,_,_,_} Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{_,_,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}:
      Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{originX,originY,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def owner_run(attached:Bool,+value:Visual,run:Model.Run) -> Model.Run:
  match attached value:
    case True{} _: run
    case False{} _: released_run(value,run)
def shot_state(value:Visual) -> Shot.State:
  match value:
    case Visual{_,owner,+slot,weapon,poolSeed,age,_,_,Projectile.Shot{x,y,vx,vy,radius,life,pierce},_,_,_,_,_,_,_,_,_,_,_,_,_}: Shot.State{Space.Spatial{x,y,age,radius},poolSeed,Shot.PlayerShot{},Components.ShotPayload{weapon,0,True{}},Components.Trajectory{vx,vy,life,pierce,[],owner,SP.emission_slot(slot),Some{SP.emission_player(slot)}}}
def shot_pierce(value:Projectile.Shot) -> U32:
  match value:
    case Projectile.Shot{_,_,_,_,_,_,pierce}: pierce
def requires_nearest(+id:U32) -> Bool:
  Bool.or(U32.is_eq(id,0),U32.is_eq(id,16))
def aim_for_shot(needsNearest:Bool,+args:G.Args,+value:Visual) -> G.Aim:
  match needsNearest:
    case True{}: G.nearest_from_args(args,shot_x(visual_shot(value)),shot_y(visual_shot(value)))
    case False{}: G.Aim{(shot_x(visual_shot(value)) + 180.0 : F32),shot_y(visual_shot(value)),0,10000000.0}
def step_point(+value:Visual,run:Model.Run,+geometry:Geometry) -> Projectile.Shot:
  match geometry:
    case Geometry{_,bodies,_,_,_}:
      +args:G.Args = G.Args{run,bodies,0.0,0.0,[],[]}
      Shot.next(shot_state(value),G.contact_shot_input(args,aim_for_shot(requires_nearest(visual_weapon(value)),args,value)))
def live_contact_target(alive:Bool,target:Contact.Target,tail:List<&2,Contact.Target>) -> List<&2,Contact.Target>:
  match alive:
    case True{}: target <> tail
    case False{}: tail
def contact_targets(rows:List<&2,Target>) -> List<&2,Contact.Target>:
  match rows:
    case []: []
    case Target{seed,_,+x,+y,radius,alive} <> tail:
      live_contact_target(alive,Contact.Target{seed,x,y,x,y,radius},contact_targets(tail))
def prepare_geometry(+rows:List<&2,Target>) -> Geometry:
  +contacts:List<&2,Contact.Target> = contact_targets(rows)
  Geometry{rows,aim_targets(rows),contacts,Broadphase.prepare(contacts),policy_targets(rows)}
def geometry_aims(geometry:Geometry) -> Targets.Targets:
  match geometry:
    case Geometry{_,bodies,_,_,_}: bodies
def first_contact(rows:List<&2,Contact.Contact>) -> Maybe<&2,Contact.Contact>:
  match rows:
    case []: None{}
    case head <> _: Some{head}
def contact_seed(value:Contact.Contact) -> U32:
  match value:
    case Contact.Contact{seed,_}: seed
def contact_time(value:Contact.Contact) -> F32:
  match value:
    case Contact.Contact{_,time}: time
def contact_point(+start:Projectile.Shot,+finish:Projectile.Shot,+time:F32) -> Point:
  Point{lerp(shot_x(start),shot_x(finish),time),lerp(shot_y(start),shot_y(finish),time)}
def with_step(value:Visual,+next:Projectile.Shot,+pending:Bool,targetSeed:U32,targetGeneration:U32,predicted:Point) -> Visual:
  match value predicted:
    case Visual{id,owner,slot,weapon,born,age,originX,originY,_,_,_,_,_,_,pendingAge,confirmed,late,event,guideTick,guideX,guideY,fade} Point{x,y}:
      Visual{id,owner,slot,weapon,born,(age + 1 : U32),originX,originY,next,pending,targetSeed,targetGeneration,x,y,(pendingAge + Bool.to_u32(pending) : U32),confirmed,late,event,guideTick,guideX,guideY,fade}
def provisional_hold(value:Visual) -> Bool:
  match value:
    case Visual{_,_,_,weapon,_,_,_,_,shot,_,_,_,_,_,_,_,_,_,_,_,_,_}:
      Bool.and(Bool.not(attached_weapon(weapon)),U32.is_eq(shot_pierce(shot),1))
def predict_target(hold:Bool,found:Maybe<&2,Target>,+value:Visual,+next:Projectile.Shot,+hit:Contact.Contact) -> Visual:
  match hold found:
    case False{} _: with_step(value,next,False{},0,0,Point{0.0,0.0})
    case True{} None{}: with_step(value,next,False{},0,0,Point{0.0,0.0})
    case True{} Some{+target}:
      with_step(value,with_position(next,contact_point(visual_shot(value),next,contact_time(hit))),True{},target_seed(target),target_generation(target),contact_point(visual_shot(value),next,contact_time(hit)))
def predicted_state(found:Maybe<&2,Contact.Contact>,+value:Visual,next:Projectile.Shot,+targets:List<&2,Target>) -> Visual:
  match found:
    case None{}: with_step(value,next,False{},0,0,Point{0.0,0.0})
    case Some{+hit}:
      predict_target(provisional_hold(value),target_by_seed(targets,contact_seed(hit)),value,next,hit)
def geometry_targets(geometry:Geometry) -> List<&2,Target>:
  match geometry:
    case Geometry{targets,_,_,_,_}: targets
def geometry_policy_targets(geometry:Geometry) -> List<&2,Policy.Target>:
  match geometry:
    case Geometry{_,_,_,_,targets}: targets
def active_contact(value:Visual) -> Bool:
  match value:
    case Visual{_,_,_,weapon,_,age,_,_,+shot,_,_,_,_,_,_,_,_,_,_,_,_,_}:
      Bool.and(Projectile.active_hit(weapon,age),Bool.and(shot_alive(shot),U32.is_gt(shot_pierce(shot),0)))
def contact_rows(active:Bool,+geometry:Geometry,+start:Projectile.Shot,+finish:Projectile.Shot) -> List<&2,Contact.Contact>:
  match active geometry:
    case False{} _: []
    case True{} Geometry{_,_,targets,index,_}:
      Contact.contacts(Broadphase.query(index,shot_x(start),shot_y(start),shot_x(finish),shot_y(finish),shot_radius(start),[]),shot_x(start),shot_y(start),shot_x(finish),shot_y(finish),shot_radius(start),[])
def flight_step(+value:Visual,run:Model.Run,+geometry:Geometry) -> Visual:
  +next = step_point(value,owner_run(attached_weapon(visual_weapon(value)),value,run),geometry)
  +contacts = contact_rows(active_contact(value),geometry,visual_shot(value),next)
  predicted_state(first_contact(contacts),value,next,geometry_targets(geometry))
def fading(remaining:U32,value:Visual) -> Visual:
  match value:
    case Visual{id,owner,slot,weapon,born,age,x,y,shot,pending,seed,generation,px,py,pendingAge,confirmed,late,event,guideTick,guideX,guideY,_}:
      Visual{id,owner,slot,weapon,born,age,x,y,shot,pending,seed,generation,px,py,pendingAge,confirmed,late,event,guideTick,guideX,guideY,remaining}
def visual_fading(done:Bool,value:Visual) -> Visual:
  match done value:
    case True{} _: fading(0,value)
    case False{} Visual{id,owner,slot,weapon,born,age,x,y,shot,pending,seed,generation,px,py,pendingAge,confirmed,late,event,guideTick,guideX,guideY,fade}:
      Visual{id,owner,slot,weapon,born,age,x,y,shot,pending,seed,generation,px,py,pendingAge,confirmed,late,event,guideTick,guideX,guideY,(fade - 1 : U32)}
def flight_or_fade(hasFade:Bool,fade:U32,value:Visual,run:Model.Run,+geometry:Geometry) -> Visual:
  match hasFade:
    case True{}: visual_fading(U32.is_le(fade,1),value)
    case False{}: flight_step(value,run,geometry)
def advance_flight_or_fade(+fade:U32,+value:Visual,+run:Model.Run,+geometry:Geometry) -> Visual:
  flight_or_fade(U32.is_gt(fade,0),fade,value,run,geometry)
def pending_step(+age:U32,value:Visual) -> Visual:
  match value:
    case Visual{id,owner,slot,weapon,born,tick,x,y,+shot,_,seed,generation,+px,+py,pendingAge,confirmed,late,event,guideTick,guideX,guideY,fade}:
      +hold = U32.is_lt(age,pending_cap())
      +positioned = with_position(shot,Point{px,py})
      Visual{id,owner,slot,weapon,born,tick,x,y,Bool.pick(Projectile.Shot,hold,positioned,with_life(positioned,0)),hold,seed,generation,px,py,(pendingAge + 1 : U32),confirmed,late,event,guideTick,guideX,guideY,Bool.pick(U32,hold,fade,fade_ticks())}
def visual_event(value:Visual) -> Maybe<&2,Journal.HitEvent>:
  match value:
    case Visual{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,event,_,_,_,_}: event
def visual_guide_tick(value:Visual) -> U32:
  match value:
    case Visual{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,tick,_,_,_}: tick
def visual_guide_x(value:Visual) -> F32:
  match value:
    case Visual{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,x,_,_}: x
def visual_guide_y(value:Visual) -> F32:
  match value:
    case Visual{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,y,_}: y
def final_shot(done:Bool,next:Projectile.Shot) -> Projectile.Shot:
  match done:
    case True{}: with_life(next,0)
    case False{}: next
def update_guided(value:Visual,next:Projectile.Shot,tick:U32,+event:Journal.HitEvent) -> Visual:
  match value:
    case Visual{id,owner,slot,weapon,born,age,x,y,_,pending,seed,generation,px,py,pendingAge,confirmed,_,_,guideTick,guideX,guideY,fade}:
      +done = U32.is_ge(tick,event_tick(event))
      Visual{id,owner,slot,weapon,born,(age + 1 : U32),x,y,final_shot(done,next),pending,seed,generation,px,py,pendingAge,confirmed,done,Some{event},guideTick,guideX,guideY,Bool.pick(U32,done,fade_ticks(),fade)}
def guided_step_found(found:Maybe<&2,Journal.HitEvent>,+value:Visual,+run:Model.Run,+tick:U32,+geometry:Geometry) -> Visual:
  match found:
    case None{}: flight_step(value,run,geometry)
    case Some{+event}:
      +point = guided_point(event,visual_guide_tick(value),visual_guide_x(value),visual_guide_y(value),tick,geometry_policy_targets(geometry))
      +next = step_point(value,owner_run(attached_weapon(visual_weapon(value)),value,run),geometry)
      update_guided(value,with_position(next,point),tick,event)
def guided_step(+value:Visual,+run:Model.Run,tick:U32,+geometry:Geometry) -> Visual:
  guided_step_found(visual_event(value),value,run,tick,geometry)
def advance_selected(pending:Bool,confirmed:Bool,late:Bool,pendingAge:U32,fade:U32,+value:Visual,+run:Model.Run,tick:U32,+geometry:Geometry) -> Visual:
  match pending confirmed late:
    case True{} _ _: pending_step(pendingAge,value)
    case _ True{} False{}: guided_step(value,run,tick,geometry)
    case _ True{} True{}: visual_fading(U32.is_le(fade,1),value)
    case _ _ _: advance_flight_or_fade(fade,value,run,geometry)
def advance_visual(+value:Visual,run:Model.Run,tick:U32,+geometry:Geometry) -> Visual:
  match value:
    case Visual{_,_,_,_,_,_,_,_,_,pending,_,_,_,_,pendingAge,confirmed,late,_,_,_,_,fade}:
      advance_selected(pending,confirmed,late,pendingAge,fade,value,run,tick,geometry)
def keep_visual(value:Visual) -> Bool:
  match value:
    case Visual{_,_,_,_,_,_,_,_,shot,pending,_,_,_,_,_,confirmed,late,_,_,_,_,fade}:
      Bool.or(shot_alive(shot),Bool.or(pending,Bool.or(Bool.and(confirmed,Bool.not(late)),U32.is_gt(fade,0))))
def keep_advanced(keep:Bool,value:Visual,tail:List<&2,Visual>) -> List<&2,Visual>:
  match keep:
    case True{}: value <> tail
    case False{}: tail
def advance_visuals(rows:List<&2,Visual>,+run:Model.Run,+tick:U32,+geometry:Geometry) -> List<&2,Visual>:
  match rows:
    case []: []
    case head <> tail:
      +next = advance_visual(head,run,tick,geometry)
      keep_advanced(keep_visual(next),next,advance_visuals(tail,run,tick,geometry))

def shot_from_row(row:G.EntityRow) -> Projectile.Shot:
  match row:
    case G.ProjectileRow{Shot.Outcome{Shot.State{Space.Spatial{x,y,_,radius},_,_,_,Components.Trajectory{vx,vy,life,pierce,_,_,_,_}},_}}: Projectile.Shot{x,y,vx,vy,radius,life,pierce}
    case _: Projectile.Shot{0.0,0.0,0.0,0.0,0.0,0,0}

def row_weapon(row:G.EntityRow) -> U32:
  match row:
    case G.ProjectileRow{Shot.Outcome{Shot.State{_,_,_,Components.ShotPayload{weapon,_,_},_},_}}: weapon
    case _: 0

def canonical_visual_match(+player:U32,sourceTick:U32,+visual:Visual,snapshot:Model.Snapshot) -> Bool:
  match snapshot:
    case Model.ProjectileSnapshot{Shot.State{Space.Spatial{_,_,age,_},_,Shot.PlayerShot{},_,Components.Trajectory{_,_,_,_,_,owner,+slot,Some{+sourcePlayer}}}}: Bool.and(U32.is_eq(player,sourcePlayer),String.eq(shot_id(visual),identity(player,(sourceTick - age : U32),owner,SP.Emission{sourcePlayer,slot})))
    case _: False{}

def canonical_visual_present(rows:List<&2,Model.Snapshot>,+player:U32,+sourceTick:U32,+visual:Visual) -> Bool:
  match rows:
    case []: False{}
    case head <> tail: Bool.or(canonical_visual_match(player,sourceTick,visual,head),canonical_visual_present(tail,player,sourceTick,visual))
def planned_snapshot(value:Visual) -> Model.Snapshot: Model.ProjectileSnapshot{shot_state(value)}

def planned_visual(keep:Bool,value:Visual,+tail:List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match keep:
    case False{}: tail
    case True{}: planned_snapshot(value) <> tail
def plan_visuals(rows:List<&2,Visual>,+player:U32,+sourceTick:U32,+canonical:List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case +head <> tail:
      +allowed = Bool.and(U32.is_eq(player,SP.emission_player(visual_slot(head))),Bool.and(shot_alive(visual_shot(head)),U32.is_gt(shot_pierce(visual_shot(head)),0)))
      +collision = canonical_visual_present(canonical,player,sourceTick,head)
      planned_visual(Bool.and(allowed,Bool.not(collision)),head,plan_visuals(tail,player,sourceTick,canonical))
def planning_snapshots(player:U32,sourceTick:U32,+canonical:List<&2,Model.Snapshot>,visuals:List<&2,Visual>) -> List<&2,Model.Snapshot>:
  List.append(&2,Model.Snapshot,canonical,plan_visuals(visuals,player,sourceTick,canonical))
def new_visual(+bornTick:U32,+originX:F32,+originY:F32,team:G.Team,+seed:U32,+request:SP.Request) -> Visual:
  match request:
    case SP.Request{+owner,+slot,level}:
      +id = request_identity(bornTick,request)
      +row = G.team_shot_spawn(team,seed,Some{SP.Request{owner,slot,level}})
      +shot = shot_from_row(row)
      +weapon = row_weapon(row)
      Visual{id,owner,slot,weapon,seed,0,originX,originY,shot,False{},0,0,0.0,0.0,0,False{},False{},None{},0,0.0,0.0,0}
def spawn_index(index:BI.Index<SP.Request>,+team:G.Team,+bornTick:U32,+originX:F32,+originY:F32,+tail:List<&2,Visual>) -> List<&2,Visual>:
  match index:
    case BI.Empty{}: tail
    case BI.Item{seed,request}: new_visual(bornTick,originX,originY,team,seed,request) <> tail
    case BI.Fork{_,_,zero,one}:
      List.append(&2,Visual,spawn_index(zero,team,bornTick,originX,originY,[]),spawn_index(one,team,bornTick,originX,originY,tail))
def local_team(+player:U32,run:Model.Run,+dx:F32,+dy:F32,+originX:F32,+originY:F32,+worldTick:U32,sourceTick:U32,+geometry:Geometry,+snapshots:List<&2,Model.Snapshot>,visuals:List<&2,Visual>) -> G.Team:
  +positioned = G.with_py(G.with_px(G.with_tick(run,worldTick),originX),originY)
  +occupied = planning_snapshots(player,sourceTick,snapshots,visuals)
  +view: G.PlayerView = G.PlayerView{player,positioned,dx,dy,True{}}
  +args: G.Args = G.Args{positioned,geometry_aims(geometry),dx,dy,occupied,[]}
  G.Team{[view],args,G.team_plan([view],occupied),BI.Empty{}}
def spawn_from_team(+team:G.Team,+bornTick:U32,+originX:F32,+originY:F32) -> List<&2,Visual>:
  match team:
    case G.Team{_,_,SP.Plan{index,_},_}: spawn_index(index,team,bornTick,originX,originY,[])
def spawn_tick(accepted:Bool,player:U32,run:Model.Run,dx:F32,dy:F32,+originX:F32,+originY:F32,+worldTick:U32,sourceTick:U32,+geometry:Geometry,+snapshots:List<&2,Model.Snapshot>,visuals:List<&2,Visual>) -> List<&2,Visual>:
  match accepted:
    case False{}: []
    case True{}:
      spawn_from_team(local_team(player,run,dx,dy,originX,originY,worldTick,sourceTick,geometry,snapshots,visuals),worldTick,originX,originY)
def contains_shot(rows:List<&2,Visual>,+id:String) -> Bool:
  match rows:
    case []: False{}
    case +head <> tail: Bool.or(String.eq(shot_id(head),id),contains_shot(tail,id))
def append_unique(duplicate:Bool,shot:Visual,+rows:List<&2,Visual>) -> List<&2,Visual>:
  match duplicate:
    case True{}: rows
    case False{}: shot <> rows
def unique_append(incoming:List<&2,Visual>,+existing:List<&2,Visual>) -> List<&2,Visual>:
  match incoming:
    case []: existing
    case +head <> tail:
      unique_append(tail,append_unique(contains_shot(existing,shot_id(head)),head,existing))
def known_id(value:KnownShot) -> String:
  match value:
    case KnownShot{_,id,_}: id
def known_player(value:KnownShot) -> U32:
  match value:
    case KnownShot{player,_,_}: player
def known_seen(value:KnownShot) -> U32:
  match value:
    case KnownShot{_,_,tick}: tick
def same_known(value:KnownShot,+player:U32,+id:String) -> Bool:
  match value:
    case KnownShot{storedPlayer,storedId,_}:
      Bool.and(U32.is_eq(storedPlayer,player),String.eq(storedId,id))
def contains_known(rows:List<&2,KnownShot>,+player:U32,+id:String) -> Bool:
  match rows:
    case []: False{}
    case +head <> tail: Bool.or(same_known(head,player,id),contains_known(tail,player,id))
def append_known(duplicate:Bool,value:KnownShot,+rows:List<&2,KnownShot>) -> List<&2,KnownShot>:
  match duplicate:
    case True{}: rows
    case False{}: value <> rows
def record_known_rows(rows:List<&2,Visual>,+player:U32,+tick:U32,+known:List<&2,KnownShot>) -> List<&2,KnownShot>:
  match rows:
    case []: known
    case +head <> tail:
      +id = shot_id(head)
      +next = append_known(contains_known(known,player,id),KnownShot{player,id,tick},known)
      record_known_rows(tail,player,tick,next)
def known_age_near(+now:U32,+seen:U32) -> Bool:
  Bool.or(Bool.and(U32.is_le(seen,now),U32.is_lt((now - seen : U32),history_window())),Bool.and(U32.is_gt(seen,now),U32.is_lt((seen - now : U32),history_window())))
def keep_known(keep:Bool,value:KnownShot,+tail:List<&2,KnownShot>) -> List<&2,KnownShot>:
  Bool.pick(List<&2,KnownShot>,keep,value <> tail,tail)
def recent_known(rows:List<&2,KnownShot>,+now:U32) -> List<&2,KnownShot>:
  match rows:
    case []: []
    case +head <> tail: keep_known(known_age_near(now,known_seen(head)),head,recent_known(tail,now))
def bounded_known(+rows:List<&2,KnownShot>) -> List<&2,KnownShot>:
  List.take(&2,KnownShot,rows,shot_cap())
def bounded_visuals(+rows:List<&2,Visual>) -> List<&2,Visual>:
  +size = List.length(&2,Visual,rows)
  List.take(&2,Visual,rows,shot_cap())
def bounded_events(+rows:List<&2,Journal.HitEvent>) -> List<&2,Journal.HitEvent>:
  +size = List.length(&2,Journal.HitEvent,rows)
  List.take(&2,Journal.HitEvent,rows,event_cap())
def event_recent(+now:U32,event:Journal.HitEvent) -> Bool:
  +tick = event_tick(event)
  Policy.event_recent(now,tick)
def keep_recent_event(keep:Bool,event:Journal.HitEvent,+tail:List<&2,Journal.HitEvent>) -> List<&2,Journal.HitEvent>:
  Bool.pick(List<&2,Journal.HitEvent>,keep,event <> tail,tail)
def recent_events(rows:List<&2,Journal.HitEvent>,+now:U32) -> List<&2,Journal.HitEvent>:
  match rows:
    case []: []
    case +head <> tail: keep_recent_event(event_recent(now,head),head,recent_events(tail,now))
def tombstone_target(value:Tombstone) -> Target:
  match value:
    case Tombstone{_,target,_}: target
def tombstone_shot(value:Tombstone) -> String:
  match value:
    case Tombstone{id,_,_}: id
def tombstone_generation(value:Tombstone) -> U32:
  match value:
    case Tombstone{_,Target{_,generation,_,_,_,_},_}: generation
def tombstone_seed(value:Tombstone) -> U32:
  match value:
    case Tombstone{_,Target{seed,_,_,_,_,_},_}: seed
def same_tombstone(value:Tombstone,shotId:String,seed:U32,generation:U32) -> Bool:
  match value:
    case Tombstone{id,Target{targetSeed,targetGeneration,_,_,_,_},_}:
      Bool.and(String.eq(id,shotId),Bool.and(U32.is_eq(targetSeed,seed),U32.is_eq(targetGeneration,generation)))
def contains_tombstone(rows:List<&2,Tombstone>,+shotId:String,+seed:U32,+generation:U32) -> Bool:
  match rows:
    case []: False{}
    case head <> tail: Bool.or(same_tombstone(head,shotId,seed,generation),contains_tombstone(tail,shotId,seed,generation))
def tombstone_add(duplicate:Bool,value:Tombstone,+rows:List<&2,Tombstone>) -> List<&2,Tombstone>:
  match duplicate:
    case True{}: rows
    case False{}: List.take(&2,Tombstone,value <> rows,512n)
def tombstone_rows(rows:List<&2,Tombstone>) -> List<&2,Target>:
  match rows:
    case []: []
    case +head <> tail: tombstone_target(head) <> tombstone_rows(tail)
def targets_with_tombstones(+state:State,+targets:List<&2,Target>) -> List<&2,Target>:
  List.append(&2,Target,targets,tombstone_rows(tombstones(state)))
def tombstone_for_pending(pending:Bool,found:Maybe<&2,Target>,+visual:Visual,+tick:U32,+tail:List<&2,Tombstone>) -> List<&2,Tombstone>:
  match pending found visual:
    case False{} _ _: tail
    case True{} None{} _: tail
    case True{} Some{+target} Visual{id,_,_,_,_,_,_,_,_,_,seed,generation,_,_,_,_,_,_,_,_,_,_}:
      tombstone_add(contains_tombstone(tail,id,seed,generation),Tombstone{id,Target{target_seed(target),target_generation(target),target_x(target),target_y(target),target_radius(target),False{}},tick},tail)
def collect_pending_tombstones(rows:List<&2,Visual>,+targets:List<&2,Target>,+tick:U32,+tail:List<&2,Tombstone>) -> List<&2,Tombstone>:
  match rows:
    case []: tail
    case +head <> rest:
      match head:
        case Visual{_,_,_,_,_,_,_,_,_,pending,seed,generation,_,_,_,_,_,_,_,_,_,_}:
          collect_pending_tombstones(rest,targets,tick,tombstone_for_pending(pending,target_life(targets,seed,generation),head,tick,tail))
def add_event_tombstone(found:Maybe<&2,Target>,+event:Journal.HitEvent,+tick:U32,+tail:List<&2,Tombstone>) -> List<&2,Tombstone>:
  match found:
    case None{}: tail
    case Some{+target}:
      +shot = event_shot_id(event)
      +seed = event_target_seed(event)
      +generation = event_target_generation(event)
      tombstone_add(contains_tombstone(tail,shot,seed,generation),Tombstone{shot,Target{target_seed(target),target_generation(target),target_x(target),target_y(target),target_radius(target),False{}},tick},tail)
def refresh_tombstone(found:Maybe<&2,Target>,+value:Tombstone,+tick:U32) -> Tombstone:
  match found value:
    case None{} value: value
    case Some{+target} Tombstone{id,_,_}: Tombstone{id,Target{target_seed(target),target_generation(target),target_x(target),target_y(target),target_radius(target),False{}},tick}
def refresh_tombstones(rows:List<&2,Tombstone>,+targets:List<&2,Target>,+tick:U32) -> List<&2,Tombstone>:
  match rows:
    case []: []
    case +head <> tail:
      refresh_tombstone(target_life(targets,tombstone_seed(head),tombstone_generation(head)),head,tick) <> refresh_tombstones(tail,targets,tick)
def clear_played_tombstone(keep:Bool,head:Tombstone,+tail:List<&2,Tombstone>) -> List<&2,Tombstone>:
  Bool.pick(List<&2,Tombstone>,keep,head <> tail,tail)
def remove_played_tombstone(rows:List<&2,Tombstone>,+event:Journal.HitEvent) -> List<&2,Tombstone>:
  match rows:
    case []: []
    case +head <> tail:
      clear_played_tombstone(Bool.not(same_tombstone(head,event_shot_id(event),event_target_seed(event),event_target_generation(event))),head,remove_played_tombstone(tail,event))
def contains_event(rows:List<&2,Journal.HitEvent>,+id:String) -> Bool:
  match rows:
    case []: False{}
    case head <> tail: Bool.or(String.eq(event_id(head),id),contains_event(tail,id))
def append_event(duplicate:Bool,+event:Journal.HitEvent,+rows:List<&2,Journal.HitEvent>) -> List<&2,Journal.HitEvent>:
  match duplicate:
    case True{}: rows
    case False{}: bounded_events(event <> rows)
def effect_event(value:Effect) -> Journal.HitEvent:
  match value:
    case Effect{event,_}: event
def effect_started(value:Effect) -> U32:
  match value:
    case Effect{_,tick}: tick
def effect_id(value:Effect) -> String:
  event_id(effect_event(value))
def effect_recent(+now:U32,value:Effect) -> Bool:
  +started = effect_started(value)
  Bool.and(U32.is_le(started,now),U32.is_lt((now - started : U32),history_window()))
def keep_effect(keep:Bool,value:Effect,+tail:List<&2,Effect>) -> List<&2,Effect>:
  Bool.pick(List<&2,Effect>,keep,value <> tail,tail)
def recent_effects(rows:List<&2,Effect>,+now:U32) -> List<&2,Effect>:
  match rows:
    case []: []
    case +head <> tail: keep_effect(effect_recent(now,head),head,recent_effects(tail,now))
def contains_effect(rows:List<&2,Effect>,+id:String) -> Bool:
  match rows:
    case []: False{}
    case +head <> tail: Bool.or(String.eq(effect_id(head),id),contains_effect(tail,id))
def effect_append(eligible:Bool,duplicate:Bool,+event:Journal.HitEvent,+tick:U32,+tail:List<&2,Effect>) -> List<&2,Effect>:
  match eligible duplicate:
    case False{} _: tail
    case True{} True{}: tail
    case True{} False{}: List.take(&2,Effect,Effect{event,tick} <> tail,event_cap())
def append_played_effects(rows:List<&2,Journal.HitEvent>,+tick:U32,+effects:List<&2,Effect>) -> List<&2,Effect>:
  match rows:
    case []: effects
    case +head <> tail:
      +eligible = Bool.and(U32.is_eq(event_outcome(head),0),U32.is_le(event_tick(head),tick))
      +next = effect_append(eligible,contains_effect(effects,event_id(head)),head,tick,effects)
      append_played_effects(tail,tick,next)
def append_effect_existing(duplicate:Bool,value:Effect,+rows:List<&2,Effect>) -> List<&2,Effect>:
  match duplicate:
    case True{}: rows
    case False{}: List.take(&2,Effect,value <> rows,event_cap())
def merge_effect_rows(incoming:List<&2,Effect>,+existing:List<&2,Effect>) -> List<&2,Effect>:
  match incoming:
    case []: existing
    case +head <> tail:
      +next = append_effect_existing(contains_effect(existing,effect_id(head)),head,existing)
      merge_effect_rows(tail,next)
def merge_known_rows(incoming:List<&2,KnownShot>,+existing:List<&2,KnownShot>) -> List<&2,KnownShot>:
  match incoming:
    case []: existing
    case +head <> tail:
      +next = append_known(contains_known(existing,known_player(head),known_id(head)),head,existing)
      merge_known_rows(tail,next)
def merge_tombstone_rows(incoming:List<&2,Tombstone>,+existing:List<&2,Tombstone>) -> List<&2,Tombstone>:
  match incoming:
    case []: existing
    case +head <> tail:
      +next = tombstone_add(contains_tombstone(existing,tombstone_shot(head),tombstone_seed(head),tombstone_generation(head)),head,existing)
      merge_tombstone_rows(tail,next)
def merge_event_rows(incoming:List<&2,Journal.HitEvent>,+existing:List<&2,Journal.HitEvent>) -> List<&2,Journal.HitEvent>:
  match incoming:
    case []: existing
    case +head <> tail:
      +next = append_event(contains_event(existing,event_id(head)),head,existing)
      merge_event_rows(tail,next)
def effect_elapsed(now:U32,value:Effect) -> U32:
  match value:
    case Effect{_,+started}: (now - started : U32)
def effect_active(+now:U32,+value:Effect) -> Bool:
  Bool.and(U32.is_le(effect_started(value),now),U32.is_lt(effect_elapsed(now,value),fade_ticks()))
def active_effects(rows:List<&2,Effect>,+now:U32) -> List<&2,Effect>:
  match rows:
    case []: []
    case +head <> tail: keep_effect(effect_active(now,head),head,active_effects(tail,now))
def accepted_before(accepted:Bool,has:Bool,last:U32,tick:U32) -> Bool:
  Bool.and(accepted,Bool.or(Bool.not(has),U32.is_gt(tick,last)))
def overflow_added(before:Nat,after:Nat) -> U32:
  Policy.overflow_added(before,after)
def cohort_run(run:Model.Run,+originX:F32,+originY:F32,+worldTick:U32) -> Model.Run:
  G.with_py(G.with_px(G.with_tick(run,worldTick),originX),originY)
def accept_allowed(allowed:Bool,state:State,+player:U32,+run:Model.Run,dx:F32,dy:F32,+originX:F32,+originY:F32,+worldTick:U32,+presentationTick:U32,sourceTick:U32,+targets:List<&2,Target>,snapshots:List<&2,Model.Snapshot>) -> State:
  match allowed state:
    case False{} state: state
    case True{} State{+oldShots,oldKnown,history,+oldTombstones,historyEffects,_,_,display,dropped,knownDropped}:
      +cursor = U32.max(display,presentationTick)
      +presentedRun = cohort_run(run,originX,originY,worldTick)
      +geometry = prepare_geometry(targets)
      +repositioned = reposition_attached_rows(oldShots,originX,originY)
      +spawned = spawn_tick(True{},player,presentedRun,dx,dy,originX,originY,worldTick,sourceTick,geometry,snapshots,oldShots)
      +joined = unique_append(spawned,repositioned)
      +bounded = bounded_visuals(joined)
      +knownBase = recent_known(oldKnown,cursor)
      +knownAll = record_known_rows(spawned,player,cursor,knownBase)
      +knownBounded = bounded_known(knownAll)
      +knownOverflow = overflow_added(List.length(&2,KnownShot,knownAll),List.length(&2,KnownShot,knownBounded))
      +pendingTombstones = refresh_tombstones(oldTombstones,geometry_targets(geometry),cursor)
      State{bounded,knownBounded,recent_events(history,cursor),pendingTombstones,recent_effects(historyEffects,cursor),True{},worldTick,cursor,(dropped + overflow_added(List.length(&2,Visual,joined),List.length(&2,Visual,bounded)) : U32),(knownDropped + knownOverflow : U32)}
def accept_tick(+state:State,accepted:Bool,player:U32,+run:Model.Run,dx:F32,dy:F32,+originX:F32,+originY:F32,+worldTick:U32,+presentationTick:U32,sourceTick:U32,+targets:List<&2,Target>,+snapshots:List<&2,Model.Snapshot>) -> State:
  match state:
    case State{_,_,_,_,_,has,last,_,_,_}:
      accept_allowed(accepted_before(accepted,has,last,worldTick),state,player,run,dx,dy,originX,originY,worldTick,presentationTick,sourceTick,targets,snapshots)

# Wall-animation time advances visuals once per ClientClock budget unit. The
# caller owns exactly-once clock consumption; remote presentation ticks only
# determine guide progress and event expiry.
def advance_tick(+state:State,+run:Model.Run,+originX:F32,+originY:F32,+presentationTick:U32,+targets:List<&2,Target>) -> State:
  match state:
    case State{shots,known,history,tombstones,historyEffects,has,last,_,dropped,knownDropped}:
      +presentedRun = G.with_py(G.with_px(run,originX),originY)
      +geometry = prepare_geometry(targets)
      +advanced = advance_visuals(shots,presentedRun,presentationTick,geometry)
      +refreshed = refresh_tombstones(tombstones,geometry_targets(geometry),presentationTick)
      +pendingTombstones = collect_pending_tombstones(advanced,geometry_targets(geometry),presentationTick,refreshed)
      State{bounded_visuals(advanced),recent_known(known,presentationTick),recent_events(history,presentationTick),pendingTombstones,recent_effects(historyEffects,presentationTick),has,last,presentationTick,dropped,knownDropped}

# Startup prediction has already moved only the local avatar over this bounded
# prefix. Reconstruct the same local ticks to seed automatic weapon visuals;
# enemy/projectile snapshots and their target geometry remain frozen inputs.
def direction_x(direction:Prediction.Direction) -> F32:
  match direction:
    case Prediction.Direction{x,_}: Session.axis(x)
def direction_y(direction:Prediction.Direction) -> F32:
  match direction:
    case Prediction.Direction{_,y}: Session.axis(y)
def bootstrap_finish(enabled:Bool,+state:State,+anchor:U32,+finalTick:U32) -> State:
  match enabled state:
    case False{} State{shots,known,events,tombstones,effects,_,_,display,dropped,knownDropped}: State{shots,known,events,tombstones,effects,False{},anchor,display,dropped,knownDropped}
    case True{} State{shots,known,events,tombstones,effects,_,_,_,dropped,knownDropped}: State{shots,known,events,tombstones,effects,True{},finalTick,finalTick,dropped,knownDropped}
def bootstrap_step(state:State,+player:U32,+baseRun:Model.Run,+sourceTick:U32,+geometry:Geometry,+snapshots:List<&2,Model.Snapshot>,+tick:U32,+direction:Prediction.Direction,point:Move.Point) -> State:
  match state point:
    case State{+oldShots,oldKnown,history,+oldTombstones,historyEffects,_,_,_,dropped,knownDropped} Move.Point{+x,+y}:
      +run = cohort_run(baseRun,x,y,tick)
      +advanced = advance_visuals(oldShots,run,tick,geometry)
      +spawned = spawn_tick(True{},player,run,direction_x(direction),direction_y(direction),x,y,tick,sourceTick,geometry,snapshots,oldShots)
      +joined = unique_append(spawned,advanced)
      +bounded = bounded_visuals(joined)
      +knownBase = recent_known(oldKnown,tick)
      +knownAll = record_known_rows(spawned,player,tick,knownBase)
      +knownBounded = bounded_known(knownAll)
      +knownOverflow = overflow_added(List.length(&2,KnownShot,knownAll),List.length(&2,KnownShot,knownBounded))
      +pendingTombstones = collect_pending_tombstones(advanced,geometry_targets(geometry),tick,oldTombstones)
      State{bounded,knownBounded,recent_events(history,tick),pendingTombstones,recent_effects(historyEffects,tick),True{},tick,tick,(dropped + overflow_added(List.length(&2,Visual,joined),List.length(&2,Visual,bounded)) : U32),(knownDropped + knownOverflow : U32)}
def bootstrap_ticks(fuel:Nat,+player:U32,+baseRun:Model.Run,+sourceTick:U32,+inputs:List<&2,Prediction.Input>,+distance:F32,+geometry:Geometry,+snapshots:List<&2,Model.Snapshot>,+tick:U32,+point:Move.Point,state:State) -> State:
  match fuel:
    case 0n: state
    case 1n+rest:
      +nextTick = Prediction.after(tick,1)
      +direction = Prediction.input_at(inputs,nextTick)
      +nextPoint = Prediction.advance_point(point,distance,direction)
      +nextState:State = bootstrap_step(state,player,baseRun,sourceTick,geometry,snapshots,nextTick,direction,nextPoint)
      bootstrap_ticks(rest,player,baseRun,sourceTick,inputs,distance,geometry,snapshots,nextTick,nextPoint,nextState)
def bootstrap(+player:U32,+run:Model.Run,+sourceTick:U32,+targets:List<&2,Target>,+snapshots:List<&2,Model.Snapshot>,prediction:Prediction.State) -> State:
  match prediction:
    case Prediction.State{_,_,distance,enabled,inputs,+anchor,display,_,_}:
      +count = U32.min(bootstrap_cap(),Prediction.world_count(anchor,display))
      +geometry = prepare_geometry(targets)
      +initialPoint:Move.Point = Move.Point{G.run_px(run),G.run_py(run)}
      +initial:State = State{[],[],[],[],[],False{},anchor,anchor,0,0}
      +stepped = bootstrap_ticks(U32.to_nat(count),player,run,sourceTick,inputs,distance,geometry,snapshots,anchor,initialPoint,initial)
      bootstrap_finish(enabled,stepped,anchor,Prediction.after(anchor,count))
def shown_point_from(pending:Bool,+shot:Projectile.Shot,x:F32,y:F32) -> Point:
  Bool.pick(Point,pending,Point{x,y},Point{shot_x(shot),shot_y(shot)})
def guided_state(id:String,owner:U32,slot:SP.Emission,weapon:U32,born:U32,age:U32,x:F32,y:F32,shot:Projectile.Shot,pending:Bool,seed:U32,generation:U32,px:F32,py:F32,pendingAge:U32,event:Journal.HitEvent,presentationTick:U32,start:Point,fade:U32) -> Visual:
  match start:
    case Point{sx,sy}: Visual{id,owner,slot,weapon,born,age,x,y,shot,False{},seed,generation,px,py,pendingAge,True{},False{},Some{event},presentationTick,sx,sy,fade}
def reconcile_visual_selected(ahead:Bool,id:String,owner:U32,slot:SP.Emission,weapon:U32,born:U32,age:U32,x:F32,y:F32,+shot:Projectile.Shot,+pending:Bool,seed:U32,generation:U32,+px:F32,+py:F32,pendingAge:U32,+event:Journal.HitEvent,fade:U32,presentationTick:U32,+targets:List<&2,Target>) -> Visual:
  match ahead:
    case True{}:
      +start = shown_point_from(pending,shot,px,py)
      guided_state(id,owner,slot,weapon,born,age,x,y,shot,pending,seed,generation,px,py,pendingAge,event,presentationTick,start,fade)
    case False{}:
      +point = event_contact(event,targets)
      Visual{id,owner,slot,weapon,born,age,x,y,with_life(with_position(shot,point),0),False{},seed,generation,px,py,pendingAge,True{},True{},Some{event},presentationTick,contact_x(point),contact_y(point),fade_ticks()}
def reconcile_visual(+event:Journal.HitEvent,+presentationTick:U32,+targets:List<&2,Target>,value:Visual) -> Visual:
  match value:
    case Visual{id,owner,slot,weapon,born,age,x,y,shot,pending,seed,generation,px,py,pendingAge,_,_,_,_,_,_,fade}:
      reconcile_visual_selected(U32.is_gt(event_tick(event),presentationTick),id,owner,slot,weapon,born,age,x,y,shot,pending,seed,generation,px,py,pendingAge,event,fade,presentationTick,targets)
def reconcile_row(matches:Bool,+event:Journal.HitEvent,presentationTick:U32,+targets:List<&2,Target>,value:Visual) -> Visual:
  match matches:
    case True{}: reconcile_visual(event,presentationTick,targets,value)
    case False{}: value
def reconcile_visuals(rows:List<&2,Visual>,+event:Journal.HitEvent,+presentationTick:U32,+targets:List<&2,Target>) -> List<&2,Visual>:
  match rows:
    case []: []
    case +head <> tail:
      reconcile_row(String.eq(shot_id(head),event_shot_id(event)),event,presentationTick,targets,head) <> reconcile_visuals(tail,event,presentationTick,targets)
def terminal_event(+event:Journal.HitEvent) -> Bool:
  Policy.terminal_event(policy_event(event))
def confirm_shots(duplicate:Bool,confirmed:Bool,+shots:List<&2,Visual>,+event:Journal.HitEvent,+presentationTick:U32,+targets:List<&2,Target>) -> List<&2,Visual>:
  match duplicate confirmed:
    case True{} _: shots
    case False{} False{}: shots
    case False{} True{}: reconcile_visuals(shots,event,presentationTick,targets)
def apply_pending_event(recent:Bool,+shots:List<&2,Visual>,+event:Journal.HitEvent,+tick:U32,+targets:List<&2,Target>) -> List<&2,Visual>:
  match recent:
    case False{}: shots
    case True{}: confirm_shots(False{},terminal_event(event),shots,event,tick,targets)
def apply_pending_events(rows:List<&2,Journal.HitEvent>,+shots:List<&2,Visual>,+tick:U32,+targets:List<&2,Target>) -> List<&2,Visual>:
  match rows:
    case []: shots
    case +head <> tail:
      +next = apply_pending_event(event_recent(tick,head),shots,head,tick,targets)
      apply_pending_events(tail,next,tick,targets)
def confirm(+state:State,+event:Journal.HitEvent,+presentationTick:U32,+targets:List<&2,Target>) -> State:
  match state:
    case State{shots,known,history,tombstones,effects,has,last,display,dropped,knownDropped}:
      +recent:List<&2,Journal.HitEvent> = recent_events(history,presentationTick)
      +knownTargets = targets_with_tombstones(state,targets)
      +refreshed = refresh_tombstones(tombstones,knownTargets,presentationTick)
      +addedTombstones = add_event_tombstone(target_life(knownTargets,event_target_seed(event),event_target_generation(event)),event,presentationTick,refreshed)
      +duplicate = contains_event(recent,event_id(event))
      +terminal = terminal_event(event)
      +knownTargetsNext = targets_with_tombstones(State{shots,known,recent,addedTombstones,recent_effects(effects,presentationTick),has,last,display,dropped,knownDropped},targets)
      State{confirm_shots(duplicate,terminal,shots,event,presentationTick,knownTargetsNext),known,append_event(duplicate,event,recent),addedTombstones,recent_effects(effects,presentationTick),has,last,display,dropped,knownDropped}
def play_effects(+state:State,+newDue:List<&2,Journal.HitEvent>,+presentationTick:U32) -> State:
  match state:
    case State{shots,oldKnown,history,tombstones,oldEffects,has,last,display,dropped,knownDropped}:
      +recent = recent_events(history,presentationTick)
      +activeHistory = recent_effects(oldEffects,presentationTick)
      +added = append_played_effects(newDue,presentationTick,activeHistory)
      State{shots,recent_known(oldKnown,presentationTick),recent,tombstones,added,has,last,display,dropped,knownDropped}
def bootstrap_result_state(result:BootstrapResult) -> State:
  match result:
    case BootstrapResult{state,_}: state
def bootstrap_result_started(result:BootstrapResult) -> Bool:
  match result:
    case BootstrapResult{_,started}: started
def prediction_enabled(prediction:Prediction.State) -> Bool:
  match prediction:
    case Prediction.State{_,_,_,enabled,_,_,_,_,_}: enabled
def bootstrap_should_start(already:Bool,enabled:Bool) -> Bool:
  Bool.and(Bool.not(already),enabled)
def merge_bootstrap_states(+prior:State,+freshState:State,+targets:List<&2,Target>) -> State:
  match prior freshState:
    case State{priorShots,priorKnown,priorEvents,priorTombstones,priorEffects,_,_,_,priorDropped,priorKnownDropped} State{freshShots,freshKnown,freshEvents,freshTombstones,freshEffects,has,last,display,freshDropped,freshKnownDropped}:
      +joinedShots = unique_append(priorShots,freshShots)
      +boundedShots = bounded_visuals(joinedShots)
      +knownRows = recent_known(merge_known_rows(priorKnown,recent_known(freshKnown,display)),display)
      +currentKnown = bounded_known(knownRows)
      +knownOverflow = overflow_added(List.length(&2,KnownShot,knownRows),List.length(&2,KnownShot,currentKnown))
      +eventRows = recent_events(merge_event_rows(priorEvents,freshEvents),display)
      +tombstoneRows = refresh_tombstones(merge_tombstone_rows(priorTombstones,freshTombstones),targets,display)
      +effectRows = recent_effects(merge_effect_rows(priorEffects,freshEffects),display)
      +knownTargets = List.append(&2,Target,targets,tombstone_rows(tombstoneRows))
      +reconciled = apply_pending_events(eventRows,boundedShots,display,knownTargets)
      State{bounded_visuals(reconciled),currentKnown,eventRows,tombstoneRows,effectRows,has,last,display,(priorDropped + freshDropped + overflow_added(List.length(&2,Visual,joinedShots),List.length(&2,Visual,boundedShots)) : U32),(priorKnownDropped + freshKnownDropped + knownOverflow : U32)}
def ensure_bootstrap_selected(already:Bool,+enabled:Bool,+state:State,+player:U32,+run:Model.Run,+sourceTick:U32,+targets:List<&2,Target>,+snapshots:List<&2,Model.Snapshot>,+prediction:Prediction.State) -> BootstrapResult:
  match already:
    case True{}: BootstrapResult{state,bootstrap_should_start(already,enabled)}
    case False{}:
      +freshState = bootstrap(player,run,sourceTick,targets,snapshots,prediction)
      BootstrapResult{merge_bootstrap_states(state,freshState,targets),bootstrap_should_start(already,enabled)}
def ensure_bootstrap_enabled(already:Bool,+state:State,+player:U32,+run:Model.Run,+sourceTick:U32,+targets:List<&2,Target>,+snapshots:List<&2,Model.Snapshot>,+prediction:Prediction.State) -> BootstrapResult:
  match prediction:
    case Prediction.State{_,_,_,enabled,_,_,_,_,_}:
      ensure_bootstrap_selected(already,enabled,state,player,run,sourceTick,targets,snapshots,prediction)
def ensure_bootstrap(+state:State,+player:U32,+run:Model.Run,+sourceTick:U32,+targets:List<&2,Target>,+snapshots:List<&2,Model.Snapshot>,+prediction:Prediction.State) -> BootstrapResult:
  ensure_bootstrap_enabled(has_accepted(state),state,player,run,sourceTick,targets,snapshots,prediction)
def should_draw(value:Visual) -> Bool:
  Policy.should_draw(policy_visual(value))

def visual_fade(value:Visual) -> U32:
  match value:
    case Visual{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,fade}: fade
def target_active_in(rows:List<&2,Target>,+seed:U32,+generation:U32) -> Bool:
  match rows:
    case []: False{}
    case Target{targetSeed,targetGeneration,_,_,_,alive} <> tail:
      Bool.pick(Bool,Bool.and(U32.is_eq(seed,targetSeed),U32.is_eq(generation,targetGeneration)),alive,target_active_in(tail,seed,generation))
def target_name(+seed:U32,+generation:U32) -> String:
  "enemy:" ++ U32.show(seed) ++ ":" ++ U32.show(generation)
def corpse_recent(+tick:U32,value:Tombstone) -> Bool:
  match value:
    case Tombstone{_,_,+lastSeen}: Bool.and(U32.is_le(lastSeen,tick),U32.is_lt((tick - lastSeen : U32),8))
def terminal_corpse_matches(+tick:U32,+tombstone:Tombstone,+event:Journal.HitEvent) -> Bool:
  Bool.and(terminal_event(event),Bool.and(event_recent(tick,event),same_tombstone(tombstone,event_shot_id(event),event_target_seed(event),event_target_generation(event))))
def terminal_corpse_event(rows:List<&2,Journal.HitEvent>,+tick:U32,+tombstone:Tombstone) -> Maybe<&2,Journal.HitEvent>:
  match rows:
    case []: None{}
    case +head <> tail:
      Bool.pick(Maybe<&2,Journal.HitEvent>,terminal_corpse_matches(tick,tombstone,head),Some{head},terminal_corpse_event(tail,tick,tombstone))
def corpse_target_point(found:Maybe<&2,Journal.HitEvent>,value:Tombstone) -> Point:
  match found value:
    case None{} Tombstone{_,target,_}: target_point(target)
    case Some{+event} _: event_target_at_impact(event)
def corpse_row(show:Bool,point:Point,+tick:U32,value:Tombstone) -> List<&2,TargetFade>:
  match show point value:
    case False{} _ _: []
    case True{} Point{x,y} Tombstone{_,Target{+seed,+generation,_,_,radius,_},lastSeen}: [TargetFade{target_name(seed,generation),seed,generation,x,y,radius,lastSeen}]
def corpse_rows(rows:List<&2,Tombstone>,+tick:U32,+targets:List<&2,Target>,+events:List<&2,Journal.HitEvent>) -> List<&2,TargetFade>:
  match rows:
    case []: []
    case +head <> tail:
      List.append(&2,TargetFade,corpse_row(Bool.and(corpse_recent(tick,head),Bool.not(target_active_in(targets,tombstone_seed(head),tombstone_generation(head)))),corpse_target_point(terminal_corpse_event(events,tick,head),head),tick,head),corpse_rows(tail,tick,targets,events))
def fade_opacity(+fade:U32) -> F32:
  Bool.pick(F32,U32.is_gt(fade,0),(U32.to_f32(U32.min(fade,fade_ticks())) / U32.to_f32(fade_ticks()) : F32),1.0)
def render_shown(value:Visual,+player:U32,shown:Projectile.Shot) -> RenderShot:
  match value shown:
    case Visual{id,_,_,weapon,poolSeed,age,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,+fade} Projectile.Shot{x,y,_,_,radius,life,_}:
      RenderShot{id,player,1,weapon,poolSeed,age,x,y,radius,life,fade,fade_opacity(fade)}
def render_shot_row(+visual:Visual,+player:U32,+presentationTick:U32,+targets:List<&2,Target>) -> RenderShot:
  render_shown(visual,player,shown_shot(visual,presentationTick,targets))
def render_shot_row_prepared(+visual:Visual,+player:U32,+presentationTick:U32,+targets:List<&2,Policy.Target>) -> RenderShot:
  render_shown(visual,player,shown_shot_prepared(visual,presentationTick,targets))
def render_shot(show:Bool,+visual:Visual,+player:U32,+presentationTick:U32,+targets:List<&2,Target>) -> List<&2,RenderShot>:
  match show:
    case False{}: []
    case True{}: [render_shot_row(visual,player,presentationTick,targets)]
def render_shot_prepared(show:Bool,+visual:Visual,+player:U32,+presentationTick:U32,+targets:List<&2,Policy.Target>) -> List<&2,RenderShot>:
  match show:
    case False{}: []
    case True{}: [render_shot_row_prepared(visual,player,presentationTick,targets)]
def render_shots(rows:List<&2,Visual>,+player:U32,+presentationTick:U32,+targets:List<&2,Target>) -> List<&2,RenderShot>:
  match rows:
    case []: []
    case +head <> tail:
      +show = Bool.and(should_draw(head),U32.is_eq(player,SP.emission_player(visual_slot(head))))
      List.append(&2,RenderShot,render_shot(show,head,player,presentationTick,targets),render_shots(tail,player,presentationTick,targets))
def render_shots_prepared(rows:List<&2,Visual>,+player:U32,+presentationTick:U32,+targets:List<&2,Policy.Target>) -> List<&2,RenderShot>:
  match rows:
    case []: []
    case +head <> tail:
      +show = Bool.and(should_draw(head),U32.is_eq(player,SP.emission_player(visual_slot(head))))
      List.append(&2,RenderShot,render_shot_prepared(show,head,player,presentationTick,targets),render_shots_prepared(tail,player,presentationTick,targets))
def effect_opacity(+age:U32) -> F32:
  fade_opacity((fade_ticks() - U32.min(age,fade_ticks()) : U32))
def rendered_contact(effect:Effect,+presentationTick:U32,+targets:List<&2,Target>) -> ContactFx:
  match effect:
    case Effect{+event,+started}:
      +point = effect_point(event,targets)
      +age = (presentationTick - started : U32)
      ContactFx{event_id(event),event_tick(event),event_kind(event),event_target_seed(event),event_target_generation(event),contact_x(point),contact_y(point),event_radius(event),age,effect_opacity(age)}
def rendered_contact_prepared(effect:Effect,+presentationTick:U32,+targets:List<&2,Policy.Target>) -> ContactFx:
  match effect:
    case Effect{+event,+started}:
      +point = policy_point(Policy.event_contact(policy_event(event),targets))
      +age = (presentationTick - started : U32)
      ContactFx{event_id(event),event_tick(event),event_kind(event),event_target_seed(event),event_target_generation(event),contact_x(point),contact_y(point),event_radius(event),age,effect_opacity(age)}
def contact_fx(show:Bool,+effect:Effect,+presentationTick:U32,+targets:List<&2,Target>) -> List<&2,ContactFx>:
  match show:
    case False{}: []
    case True{}: [rendered_contact(effect,presentationTick,targets)]
def contact_fx_prepared(show:Bool,+effect:Effect,+presentationTick:U32,+targets:List<&2,Policy.Target>) -> List<&2,ContactFx>:
  match show:
    case False{}: []
    case True{}: [rendered_contact_prepared(effect,presentationTick,targets)]
def render_contacts(rows:List<&2,Effect>,+presentationTick:U32,+targets:List<&2,Target>) -> List<&2,ContactFx>:
  match rows:
    case []: []
    case +head <> tail:
      List.append(&2,ContactFx,contact_fx(effect_active(presentationTick,head),head,presentationTick,targets),render_contacts(tail,presentationTick,targets))
def render_contacts_prepared(rows:List<&2,Effect>,+presentationTick:U32,+targets:List<&2,Policy.Target>) -> List<&2,ContactFx>:
  match rows:
    case []: []
    case +head <> tail:
      List.append(&2,ContactFx,contact_fx_prepared(effect_active(presentationTick,head),head,presentationTick,targets),render_contacts_prepared(tail,presentationTick,targets))
def render_frame(+state:State,+player:U32,+presentationTick:U32,+targets:List<&2,Target>) -> RenderFrame:
  +knownTargets = targets_with_tombstones(state,targets)
  +policyKnownTargets = policy_targets(knownTargets)
  RenderFrame{render_shots_prepared(shots(state),player,presentationTick,policyKnownTargets),render_contacts_prepared(active_effects(effects(state),presentationTick),presentationTick,policyKnownTargets),corpse_rows(tombstones(state),presentationTick,targets,events(state))}
def visible_id(rows:List<&2,Visual>,+player:U32,+id:String) -> Bool:
  Policy.visible_id(policy_visuals(rows),player,id)
def terminal_receipt_matches(+now:U32,+shotId:String,+event:Journal.HitEvent) -> Bool:
  Policy.terminal_receipt_matches(now,shotId,policy_event(event))
def contains_terminal_receipt(rows:List<&2,Journal.HitEvent>,+now:U32,+shotId:String) -> Bool:
  Policy.contains_terminal_receipt(policy_events(rows),now,shotId)
def prepare_visibility(+state:State) -> Policy.Visibility:
  Policy.Visibility{display_tick(state),policy_visuals(shots(state)),policy_events(events(state))}
def should_show_prepared(context:Policy.Visibility,+player:U32,+kind:U32,+owner:U32,+shotId:String) -> Bool:
  Policy.should_show_prepared(context,player,kind,owner,shotId)
def should_show_authoritative(+state:State,+player:U32,+kind:U32,+owner:U32,+shotId:String) -> Bool:
  should_show_prepared(prepare_visibility(state),player,kind,owner,shotId)
