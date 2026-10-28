import ./game-observation.bend as Model
import Base
import enemy-effects.bend as Effect
import enemy-combat.bend as Enemy
import game-components.bend as Components
import projectile-state.bend as Shot
import ./game.bend as G
import ./enemy-spatial.bend as Space
import ./coop-prediction.bend as P
import ./coop-session.bend as Session
import ./coop-combat-codec.bend as W
import ./coop-prediction-replay.bend as Replay
import ./coop-combat-prediction-policy.bend as Policy
import ./projectile-contact.bend as Contact
import ./projectile.bend as Projectile
import ./projectile-pool.bend as SP
import ./body-index.bend as BI
import ./entity-role.bend as Role
import ./pools.bend as Pool
import ./coop-combat-broadphase.bend as Broadphase

# No ECS World or durable progression API is reachable through a Scene value.
# All currently known combat actors advance together from one received anchor.
# Only sampled directions cross this boundary; admission clocks and leases stay
# authoritative. Speculative world time cannot expire a remote input heartbeat.
type Scene is Data: Scene{own:U32,players:List<&2,G.PlayerSnapshot>,snapshots:List<&2,Model.Snapshot>,births:BI.Index<U32>,directions:Session.Directions,contacts:List<&2,Policy.Witness>,tick:U32,diagnostics:Bool}
def active(snapshot:Model.Snapshot) -> Bool:
  match snapshot:
    case Model.EnemySnapshot{Enemy.State{_,_,_,Components.Vitals{health,_},_}}: U32.is_gt(health,0)
    case Model.ProjectileSnapshot{state}: Shot.active(state)
    case _: False{}
def add_snapshot(allowed:Bool,row:Model.Snapshot,tail:List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match allowed:
    case False{}: tail
    case True{}: row <> tail
def active_snapshots(rows:List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case +head <> tail: add_snapshot(active(head),head,active_snapshots(tail))

def initialize_active(own:U32,+tick:U32,players:List<&2,G.PlayerSnapshot>,+snapshots:List<&2,Model.Snapshot>) -> Scene:
  Scene{own,players,snapshots,W.birth_map(snapshots,tick,BI.Empty{},BI.Empty{},BI.Empty{}),Session.Directions{0.0,0.0,0.0,0.0},[],tick,False{}}
def initialize(own:U32,tick:U32,players:List<&2,G.PlayerSnapshot>,snapshots:List<&2,Model.Snapshot>) -> Scene:
  initialize_active(own,tick,players,active_snapshots(snapshots))
def normalize_run(+run:Model.Run) -> Model.Run:
  G.with_py(G.with_px(run,Policy.normalize(G.run_px(run))),Policy.normalize(G.run_py(run)))
def normalize_players(rows:List<&2,G.PlayerSnapshot>) -> List<&2,G.PlayerSnapshot>:
  match rows:
    case []: []
    case G.PlayerSnapshot{id,run,connected} <> tail: G.PlayerSnapshot{id,normalize_run(run),connected} <> normalize_players(tail)
def normalize_snapshot(value:Model.Snapshot) -> Model.Snapshot:
  match value:
    case Model.ProjectileSnapshot{Shot.State{Space.Spatial{x,y,age,radius},identity,side,payload,Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,+sourcePlayer}}}: Model.ProjectileSnapshot{Shot.State{Space.Spatial{Policy.normalize(x),Policy.normalize(y),age,Policy.normalize(radius)},identity,side,payload,Components.Trajectory{Policy.normalize(vx),Policy.normalize(vy),life,pierce,visited,owner,slot,sourcePlayer}}}
    case Model.EnemySnapshot{Enemy.State{Space.Spatial{x,y,age,radius},archetype,identity,vitals,status}}: Model.EnemySnapshot{Enemy.State{Space.Spatial{Policy.normalize(x),Policy.normalize(y),age,Policy.normalize(radius)},archetype,identity,vitals,status}}
    case Model.PickupSnapshot{pickup}: Model.PickupSnapshot{pickup}
def normalize_snapshots(rows:List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case head <> tail: normalize_snapshot(head) <> normalize_snapshots(tail)
def receive(scene:Scene,session:Session.State) -> Scene:
  match scene:
    case Scene{own,players,snapshots,births,_,contacts,tick,diagnostics}: Scene{own,normalize_players(players),normalize_snapshots(snapshots),births,Policy.remote_input(session),contacts,tick,diagnostics}
def diagnostic_history(enabled:Bool,contacts:List<&2,Policy.Witness>) -> List<&2,Policy.Witness>:
  match enabled:
    case False{}: []
    case True{}: contacts
def with_diagnostics(scene:Scene,+enabled:Bool) -> Scene:
  match scene:
    case Scene{own,players,snapshots,births,directions,contacts,tick,_}: Scene{own,players,snapshots,births,directions,diagnostic_history(enabled,contacts),tick,enabled}
def find_run(players:List<&2,G.PlayerSnapshot>,+id:U32) -> Maybe<&2,Model.Run>:
  match players:
    case []: None{}
    case G.PlayerSnapshot{+player,run,_} <> tail: Bool.pick(Maybe<&2,Model.Run>,U32.is_eq(player,id),Some{run},find_run(tail,id))
def allowed_run(run:Maybe<&2,Model.Run>,x:U32,y:U32) -> Bool:
  match run:
    case None{}: False{}
    case Some{+run}: Replay.eligible(G.run_phase(run),G.run_hp(run),x,y)
def allowed(scene:Scene,x:U32,y:U32) -> Bool:
  match scene:
    case Scene{own,players,_,_,_,_,_,_}: allowed_run(find_run(players,own),x,y)
def hinted_x(+player:U32,directions:Session.Directions) -> F32:
  match directions:
    case Session.Directions{x0,_,x1,_}: Bool.pick(F32,U32.is_eq(player,0),x0,Bool.pick(F32,U32.is_eq(player,1),x1,0.0))
def hinted_y(+player:U32,directions:Session.Directions) -> F32:
  match directions:
    case Session.Directions{_,y0,_,y1}: Bool.pick(F32,U32.is_eq(player,0),y0,Bool.pick(F32,U32.is_eq(player,1),y1,0.0))
def view(+own:U32,+x:U32,+y:U32,+directions:Session.Directions,tick:U32,player:G.PlayerSnapshot) -> G.PlayerView:
  match player:
    case G.PlayerSnapshot{+id,+run,connected}:
      G.PlayerView{id,G.with_tick(run,tick),Bool.pick(F32,U32.is_eq(id,own),Session.axis(x),hinted_x(id,directions)),Bool.pick(F32,U32.is_eq(id,own),Session.axis(y),hinted_y(id,directions)),connected}
def views(rows:List<&2,G.PlayerSnapshot>,+own:U32,+x:U32,+y:U32,+directions:Session.Directions,+tick:U32) -> List<&2,G.PlayerView>:
  match rows:
    case []: []
    case +head <> tail: view(own,x,y,directions,tick,head) <> views(tail,own,x,y,directions,tick)
def any_request(rows:List<&2,SP.Request>) -> Bool:
  match rows:
    case []: False{}
    case _: True{}
def may_fire(view:G.PlayerView) -> Bool:
  match view:
    case G.PlayerView{id,+run,_,_,_}: any_request(G.shot_requests(24n,(G.run_tick(run) % Pool.owner_count() : U32),G.shot_schedule_for(id,run),G.empty_owner_counts()))
def may_fire_any(rows:List<&2,G.PlayerView>) -> Bool:
  match rows:
    case []: False{}
    case head <> tail: Bool.or(may_fire(head),may_fire_any(tail))
def future_plan_selected(required:Bool,players:List<&2,G.PlayerView>,snapshots:List<&2,Model.Snapshot>) -> SP.Plan:
  match required:
    case False{}: G.empty_shot_plan()
    case True{}: G.team_plan(players,snapshots)
# Future volleys of every observed player affect enemy survival and therefore
# which target a later projectile reaches. Their known loadouts/cooldowns must
# be forecast together, under the same held-input assumption as their movement.
# Empty locks admit a superset of scheduled requests. Only an empty superset
# skips allocation; every other case uses the complete game allocator.
def future_plan(reference:Bool,+players:List<&2,G.PlayerView>,snapshots:List<&2,Model.Snapshot>) -> SP.Plan:
  match reference:
    case True{}: G.team_plan(players,snapshots)
    case False{}: future_plan_selected(may_fire_any(G.living_views(players)),players,snapshots)
def raw_team(reference:Bool,+players:List<&2,G.PlayerView>,+snapshots:List<&2,Model.Snapshot>,own:U32,+fallback:Model.Run) -> G.Team:
  G.Team{players,G.Args{G.view_run(G.first_view(players,fallback)),G.enemy_targets(snapshots),0.0,0.0,snapshots,[]},future_plan(reference,players,snapshots),G.effect_origin_index(snapshots)}
type Moving is Data: Moving{targets:List<&2,Contact.Target>,bodies:BI.Index<Space.Spatial>}
type Prepared is Data: Prepared{team:G.Team,targets:List<&2,Contact.Target>,moved:BI.Index<Space.Spatial>,next:BI.Index<Projectile.Shot>}
def freeze_moved(+seed:U32,+previous:Space.Spatial,+moved:Space.Spatial,state:Moving) -> Moving:
  match state:
    case Moving{targets,index}: Moving{G.contact_spatial(seed,previous,moved) <> targets,BI.insert(~Space.Spatial,index,seed,moved)}
def freeze_enemy(+team:G.Team,enemy:Enemy.State,state:Moving) -> Moving:
  match enemy:
    case Enemy.State{+space,archetype,identity,_,Components.Status{slow,_}}: freeze_moved(identity,space,G.team_move_space(team,space,archetype,slow),state)
def freeze_movement(rows:List<&2,Model.Snapshot>,+team:G.Team) -> Moving:
  match rows:
    case []: Moving{[],BI.Empty{}}
    case Model.EnemySnapshot{enemy} <> tail: freeze_enemy(team,enemy,freeze_movement(tail,team))
    case _ <> tail: freeze_movement(tail,team)
def freeze_shot(+team:G.Team,+state:Shot.State,index:BI.Index<Projectile.Shot>) -> BI.Index<Projectile.Shot>:
  match state:
    case Shot.State{Space.Spatial{x,y,_,_},seed,_,_,Components.Trajectory{_,_,_,_,_,_,slot,Some{sourcePlayer}}}: BI.insert(~Projectile.Shot,index,seed,Shot.next(state,G.contact_shot_input(G.team_args(team,G.team_for_id(team,sourcePlayer)),G.nearest_from_args(G.team_base(team),x,y))))
    case _: index

def freeze_next(rows:List<&2,Model.Snapshot>,+team:G.Team) -> BI.Index<Projectile.Shot>:
  match rows:
    case []: BI.Empty{}
    case Model.ProjectileSnapshot{Shot.State{+space,+identity,Shot.PlayerShot{},+payload,+trajectory}} <> tail: freeze_shot(team,Shot.State{space,identity,Shot.PlayerShot{},payload,trajectory},freeze_next(tail,team))
    case _ <> tail: freeze_next(tail,team)

def contact_candidates(unlimited:Bool,index:Broadphase.Index,+x:F32,+y:F32,+radius:F32,+pierce:U32,visited:List<&2,U32>,+next:Projectile.Shot) -> List<&2,U32>:
  match unlimited next:
    case True{} _: G.contact_shot_targets(True{},[],x,y,radius,pierce,visited,next)
    case False{} Projectile.Shot{x1,y1,_,_,_,_,_}: G.contact_shot_targets(False{},Broadphase.query(index,x,y,x1,y1,radius,visited),x,y,radius,pierce,[],next)
def contact_cached(allowed:Bool,state:Shot.State,index:Broadphase.Index,next:Projectile.Shot,tail:List<&2,G.HitPlan>) -> List<&2,G.HitPlan>:
  match allowed state:
    case False{} _: tail
    case True{} Shot.State{Space.Spatial{+x,+y,_,+radius},seed,_,Components.ShotPayload{id,damage,_},Components.Trajectory{_,_,_,+pierce,visited,_,_,_}}: G.HitPlan{seed,id,damage,x,y,radius,U32.is_le(9999,pierce),contact_candidates(U32.is_le(9999,pierce),index,x,y,radius,pierce,visited,next)} <> tail

def contact_next(found:Maybe<&2,Projectile.Shot>,+team:G.Team,+state:Shot.State,targets:List<&2,Contact.Target>,index:Broadphase.Index,tail:List<&2,G.HitPlan>) -> List<&2,G.HitPlan>:
  match found state:
    case None{} Shot.State{Space.Spatial{_,_,age,_},_,_,Components.ShotPayload{id,_,_},_}: G.contact_shot_plan(Bool.and(Projectile.active_hit(id,age),Shot.active(state)),state,team,targets,tail)
    case Some{next} Shot.State{Space.Spatial{_,_,age,_},_,_,Components.ShotPayload{id,_,_},_}: contact_cached(Bool.and(Projectile.active_hit(id,age),Shot.active(state)),state,index,next,tail)

def contact_cached_rows(rows:List<&2,Model.Snapshot>,+team:G.Team,+targets:List<&2,Contact.Target>,+next:BI.Index<Projectile.Shot>,+index:Broadphase.Index) -> List<&2,G.HitPlan>:
  match rows:
    case []: []
    case Model.ProjectileSnapshot{Shot.State{+space,+identity,Shot.PlayerShot{},+payload,+trajectory}} <> tail: contact_next(BI.find(~Projectile.Shot,next,identity),team,Shot.State{space,identity,Shot.PlayerShot{},payload,trajectory},targets,index,contact_cached_rows(tail,team,targets,next,index))
    case _ <> tail: contact_cached_rows(tail,team,targets,next,index)

def prepared_contacts(reference:Bool,+team:G.Team,+snapshots:List<&2,Model.Snapshot>,+targets:List<&2,Contact.Target>,moved:BI.Index<Space.Spatial>,+next:BI.Index<Projectile.Shot>) -> Prepared:
  match reference:
    case True{}: Prepared{G.contact_team(team),targets,moved,next}
    case False{}: Prepared{G.contact_team_ready(team,contact_cached_rows(snapshots,team,targets,next,Broadphase.prepare(targets))),targets,moved,next}
def prepared_movement(reference:Bool,+team:G.Team,+snapshots:List<&2,Model.Snapshot>,state:Moving) -> Prepared:
  match state:
    case Moving{targets,moved}: prepared_contacts(reference,team,snapshots,targets,moved,freeze_next(snapshots,team))
def prepared_raw(reference:Bool,+team:G.Team,+snapshots:List<&2,Model.Snapshot>) -> Prepared:
  prepared_movement(reference,team,snapshots,freeze_movement(snapshots,team))
def make_team(+reference:Bool,players:List<&2,G.PlayerView>,+snapshots:List<&2,Model.Snapshot>,own:U32,fallback:Model.Run) -> Prepared:
  prepared_raw(reference,raw_team(reference,players,snapshots,own,fallback),snapshots)
def prepared_team(state:Prepared) -> G.Team:
  match state:
    case Prepared{team,_,_,_}: team
def prepared_targets(state:Prepared) -> List<&2,Contact.Target>:
  match state:
    case Prepared{_,targets,_,_}: targets
def prepared_moved(state:Prepared) -> BI.Index<Space.Spatial>:
  match state:
    case Prepared{_,_,moved,_}: moved
def prepared_next(state:Prepared) -> BI.Index<Projectile.Shot>:
  match state:
    case Prepared{_,_,_,next}: next
def row_snapshot(row:G.EntityRow,tail:List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match row:
    case G.NoEntityRow{}: tail
    case G.ProjectileRow{Shot.Outcome{+state,_}}: add_snapshot(active(Model.ProjectileSnapshot{state}),Model.ProjectileSnapshot{state},tail)
    case G.EnemyRow{outcome,_}: G.enemy_snapshot(outcome,tail)
    case G.PickupRow{_}: tail
def projectile_row(+team:G.Team,snapshot:Model.Snapshot) -> G.EntityRow:
  match snapshot:
    case Model.ProjectileSnapshot{+state}: G.team_projectile_role(Role.assigned(Shot.identity(state)),team,state)
    case _: G.missing_row()

def existing_projectiles(rows:List<&2,Model.Snapshot>,+team:G.Team) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case Model.ProjectileSnapshot{state} <> tail: row_snapshot(projectile_row(team,Model.ProjectileSnapshot{state}),existing_projectiles(tail,team))
    case _ <> tail: existing_projectiles(tail,team)

def projectile_cached(next:Projectile.Shot,+state:Shot.State,team:G.Team) -> G.EntityRow:
  match team:
    case G.Team{_,G.Args{_,_,_,_,_,hits},_,_}: G.ProjectileRow{Shot.contacted(state,G.hit_targets(hits,Shot.identity(state)),next)}

def projectile_next(found:Maybe<&2,Projectile.Shot>,+snapshot:Model.Snapshot,+team:G.Team) -> G.EntityRow:
  match found snapshot:
    case None{} _: projectile_row(team,snapshot)
    case Some{next} Model.ProjectileSnapshot{state}: projectile_cached(next,state,team)
    case _ _: G.missing_row()

def existing_projectiles_cached(rows:List<&2,Model.Snapshot>,+team:G.Team,+next:BI.Index<Projectile.Shot>) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case Model.ProjectileSnapshot{+state} <> tail: row_snapshot(projectile_next(BI.find(~Projectile.Shot,next,Shot.identity(state)),Model.ProjectileSnapshot{state},team),existing_projectiles_cached(tail,team,next))
    case _ <> tail: existing_projectiles_cached(tail,team,next)

def choose_projectiles(reference:Bool,rows:List<&2,Model.Snapshot>,team:G.Team,next:BI.Index<Projectile.Shot>) -> List<&2,Model.Snapshot>:
  match reference:
    case True{}: existing_projectiles(rows,team)
    case False{}: existing_projectiles_cached(rows,team,next)
def spawned_assignments(index:BI.Index<SP.Request>,+team:G.Team) -> List<&2,Model.Snapshot>:
  match index:
    case BI.Empty{}: []
    case BI.Item{seed,request}: row_snapshot(G.team_shot_spawn(team,seed,Some{request}),[])
    case BI.Fork{_,_,zero,one}: List.append(&2,Model.Snapshot,spawned_assignments(zero,team),spawned_assignments(one,team))
def spawned_projectiles(team:G.Team) -> List<&2,Model.Snapshot>:
  match team:
    case G.Team{+players,+args,SP.Plan{+index,+count},+origins}: spawned_assignments(index,G.Team{players,args,SP.Plan{index,count},origins})
def moved_enemy(+team:G.Team,+enemy:Enemy.State) -> G.EntityRow:
  match enemy:
    case Enemy.State{Space.Spatial{x,y,_,_},_,_,_,_}: G.enemy_row(G.enemy_effects_indexed(G.effect_players(G.team_views(team)),x,y,enemy,G.team_hits(team),G.team_origins(team)))
def enemy_combat_input(+team:G.Team,enemy:Enemy.State) -> Enemy.State:
  match enemy:
    case Enemy.State{space,+archetype,identity,vitals,+status}: Enemy.State{G.team_move_space(team,space,archetype,G.enemy_status_slow(status)),archetype,identity,vitals,status}
def enemy_row(+team:G.Team,enemy:Enemy.State) -> G.EntityRow:
  moved_enemy(team,enemy_combat_input(team,enemy))
def existing_enemies(rows:List<&2,Model.Snapshot>,+team:G.Team) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case Model.EnemySnapshot{enemy} <> tail: row_snapshot(enemy_row(team,enemy),existing_enemies(tail,team))
    case _ <> tail: existing_enemies(tail,team)
type Recipients is Data: Recipients{all:List<&2,G.HitPlan>,index:BI.Index<List<&2,G.HitPlan>>,areas:Bool}
def hit_plan_targets(plan:G.HitPlan) -> List<&2,U32>:
  match plan:
    case G.HitPlan{_,_,_,_,_,_,_,targets}: targets
def has_area(rows:List<&2,G.HitPlan>) -> Bool:
  match rows:
    case []: False{}
    case G.HitPlan{_,_,_,_,_,_,area,_} <> tail: Bool.or(area,has_area(tail))
# Existing BI.insert deliberately keeps the first value. Updating one recipient
# bucket therefore replaces that already-found leaf along its original path.
def replace_recipient(fuel:Nat,index:BI.Index<List<&2,G.HitPlan>>,+key:U32,+value:List<&2,G.HitPlan>,one:Bool) -> BI.Index<List<&2,G.HitPlan>>:
  match fuel index one:
    case _ BI.Empty{} _: BI.Item{key,value}
    case _ BI.Item{+old,rows} _: Bool.pick(BI.Index<List<&2,G.HitPlan>>,U32.is_eq(old,key),BI.Item{key,value},BI.Item{old,rows})
    case 0n index _: index
    case 1n+rest BI.Fork{sample,mask,+zero,one} False{}: BI.Fork{sample,mask,replace_recipient(rest,zero,key,value,BI.branch(~List<&2,G.HitPlan>,zero,key)),one}
    case 1n+rest BI.Fork{sample,mask,zero,+one} True{}: BI.Fork{sample,mask,zero,replace_recipient(rest,one,key,value,BI.branch(~List<&2,G.HitPlan>,one,key))}
def recipient_found(found:Maybe<&2,List<&2,G.HitPlan>>,+index:BI.Index<List<&2,G.HitPlan>>,+key:U32,plan:G.HitPlan) -> BI.Index<List<&2,G.HitPlan>>:
  match found:
    case None{}: BI.insert(~List<&2,G.HitPlan>,index,key,[plan])
    case Some{rows}: replace_recipient(32n,index,key,plan <> rows,BI.branch(~List<&2,G.HitPlan>,index,key))
def prepend_recipient(+index:BI.Index<List<&2,G.HitPlan>>,+key:U32,plan:G.HitPlan) -> BI.Index<List<&2,G.HitPlan>>:
  recipient_found(BI.find(~List<&2,G.HitPlan>,index,key),index,key,plan)
def add_recipient(duplicate:Bool,index:BI.Index<List<&2,G.HitPlan>>,key:U32,plan:G.HitPlan) -> BI.Index<List<&2,G.HitPlan>>:
  match duplicate:
    case True{}: index
    case False{}: prepend_recipient(index,key,plan)
def index_recipient_ids(ids:List<&2,U32>,+plan:G.HitPlan,index:BI.Index<List<&2,G.HitPlan>>) -> BI.Index<List<&2,G.HitPlan>>:
  match ids:
    case []: index
    case +head <> +tail: index_recipient_ids(tail,plan,add_recipient(Contact.contains(tail,head),index,head,plan))
def index_recipient_rows(rows:List<&2,G.HitPlan>) -> BI.Index<List<&2,G.HitPlan>>:
  match rows:
    case []: BI.Empty{}
    case +head <> tail: index_recipient_ids(hit_plan_targets(head),head,index_recipient_rows(tail))
def recipients_selected(areas:Bool,+rows:List<&2,G.HitPlan>) -> Recipients:
  match areas:
    case True{}: Recipients{rows,BI.Empty{},True{}}
    case False{}: Recipients{rows,index_recipient_rows(rows),False{}}
def recipients(+rows:List<&2,G.HitPlan>) -> Recipients: recipients_selected(has_area(rows),rows)
def recipient_hits(recipients:Recipients,key:U32) -> List<&2,G.HitPlan>:
  match recipients:
    case Recipients{all,_,True{}}: all
    case Recipients{_,index,False{}}: BI.get(~List<&2,G.HitPlan>,index,key,[])
def recipient_filter(rows:List<&2,G.HitPlan>,+key:U32) -> List<&2,G.HitPlan>:
  match rows:
    case []: []
    case +head <> tail: G.effect_source_hit(Contact.contains(hit_plan_targets(head),key),head,recipient_filter(tail,key))
def recipient_reference_selected(areas:Bool,+rows:List<&2,G.HitPlan>,key:U32) -> List<&2,G.HitPlan>:
  match areas:
    case True{}: rows
    case False{}: recipient_filter(rows,key)
def recipient_hits_reference(+rows:List<&2,G.HitPlan>,key:U32) -> List<&2,G.HitPlan>:
  recipient_reference_selected(has_area(rows),rows,key)
def recipient_point_hit(enemy:Enemy.State,plan:G.HitPlan) -> Bool:
  match enemy plan:
    case Enemy.State{Space.Spatial{ex,ey,_,r},_,identity,_,_} G.HitPlan{_,_,_,x,y,radius,area,targets}: G.hit_recipient(area,targets,identity,ex,ey,r,x,y,radius)
def recipient_point_filter(rows:List<&2,G.HitPlan>,+body:Enemy.State) -> List<&2,G.HitPlan>:
  match rows:
    case []: []
    case +head <> tail: G.effect_source_hit(recipient_point_hit(body,head),head,recipient_point_filter(tail,body))
# The area's exact resolver reads the body AFTER this tick's movement and
# BEFORE hit effects. Filtering preserves original plan order and multiplicity.
def recipient_hits_at(recipients:Recipients,+moved:Enemy.State) -> List<&2,G.HitPlan>:
  match recipients moved:
    case Recipients{all,_,True{}} _: recipient_point_filter(all,moved)
    case Recipients{_,index,False{}} Enemy.State{_,_,identity,_,_}: BI.get(~List<&2,G.HitPlan>,index,identity,[])
def empty_effects(rows:List<&2,G.HitPlan>,status:Components.Status) -> Bool:
  match rows status:
    case [] Components.Status{slow,burn}: Bool.and(Bool.not(Effect.slow_active(slow)),Bool.not(Effect.burn_active(burn)))
    case _ _: False{}
def moved_enemy_selected(fast:Bool,+team:G.Team,enemy:Enemy.State) -> G.EntityRow:
  match fast:
    case True{}: G.enemy_row(Enemy.Alive{enemy,0})
    case False{}: moved_enemy(team,enemy)
def moved_enemy_hits(+team:G.Team,+enemy:Enemy.State,+hits:List<&2,G.HitPlan>) -> G.EntityRow:
  match enemy:
    case Enemy.State{_,_,_,_,status}: moved_enemy_selected(empty_effects(hits,status),G.contact_team_ready(team,hits),enemy)
def moved_enemy_recipients(team:G.Team,+enemy:Enemy.State,recipients:Recipients) -> G.EntityRow:
  moved_enemy_hits(team,enemy,recipient_hits_at(recipients,enemy))
def enemy_row_indexed(+team:G.Team,enemy:Enemy.State,recipients:Recipients) -> G.EntityRow:
  moved_enemy_recipients(team,enemy_combat_input(team,enemy),recipients)
def existing_enemies_indexed(rows:List<&2,Model.Snapshot>,+team:G.Team,+recipients:Recipients) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case Model.EnemySnapshot{enemy} <> tail: row_snapshot(enemy_row_indexed(team,enemy,recipients),existing_enemies_indexed(tail,team,recipients))
    case _ <> tail: existing_enemies_indexed(tail,team,recipients)
def enemy_cached(found:Maybe<&2,Space.Spatial>,+team:G.Team,enemy:Enemy.State,recipients:Recipients) -> G.EntityRow:
  match found enemy:
    case None{} _: enemy_row_indexed(team,enemy,recipients)
    case Some{moved} Enemy.State{_,archetype,identity,vitals,status}: moved_enemy_recipients(team,Enemy.State{moved,archetype,identity,vitals,status},recipients)
def existing_enemies_cached(rows:List<&2,Model.Snapshot>,+team:G.Team,+recipients:Recipients,+moved:BI.Index<Space.Spatial>) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case Model.EnemySnapshot{+enemy} <> tail: row_snapshot(enemy_cached(BI.find(~Space.Spatial,moved,G.enemy_identity(enemy)),team,enemy,recipients),existing_enemies_cached(tail,team,recipients,moved))
    case _ <> tail: existing_enemies_cached(tail,team,recipients,moved)
def moved_view_for(views:List<&2,G.PlayerView>,+id:U32) -> Maybe<&2,Model.Run>:
  match views:
    case []: None{}
    case +view <> rest: Bool.pick(Maybe<&2,Model.Run>,U32.is_eq(G.view_id(view),id),Some{G.moved_run(view)},moved_view_for(rest,id))
def player_after_movement(+player:G.PlayerSnapshot,moved:Maybe<&2,Model.Run>) -> G.PlayerSnapshot:
  match player moved:
    case G.PlayerSnapshot{id,_,connected} Some{run}: G.PlayerSnapshot{id,run,connected}
    case player None{}: player
def moved_players(players:List<&2,G.PlayerSnapshot>,+views:List<&2,G.PlayerView>) -> List<&2,G.PlayerSnapshot>:
  match players:
    case []: []
    case G.PlayerSnapshot{+id,+run,+connected} <> tail: player_after_movement(G.PlayerSnapshot{id,run,connected},moved_view_for(views,id)) <> moved_players(tail,views)
def team_plan(team:G.Team) -> SP.Plan:
  match team:
    case G.Team{_,_,plan,_}: plan
def team_views(team:G.Team) -> List<&2,G.PlayerView>:
  match team:
    case G.Team{players,_,_,_}: players
def team_hits(team:G.Team) -> List<&2,G.HitPlan>:
  match team:
    case G.Team{_,G.Args{_,_,_,_,_,hits},_,_}: hits
def choose_enemies(reference:Bool,+rows:List<&2,Model.Snapshot>,+team:G.Team,moved:BI.Index<Space.Spatial>) -> List<&2,Model.Snapshot>:
  match reference:
    case True{}: existing_enemies(rows,team)
    case False{}: existing_enemies_cached(rows,team,recipients(team_hits(team)),moved)
def snapshot_index(rows:List<&2,Model.Snapshot>) -> BI.Index<Model.Snapshot>:
  match rows:
    case []: BI.Empty{}
    case +snapshot <> tail: BI.insert(~Model.Snapshot,snapshot_index(tail),G.snapshot_identity(snapshot),snapshot)

def target_index(rows:List<&2,Contact.Target>) -> BI.Index<Contact.Target>:
  match rows:
    case []: BI.Empty{}
    case Contact.Target{+seed,+x0,+y0,+x1,+y1,+radius} <> tail: BI.insert(~Contact.Target,target_index(tail),seed,Contact.Target{seed,x0,y0,x1,y1,radius})
def add_witness(value:Maybe<&2,Policy.Witness>,tail:List<&2,Policy.Witness>) -> List<&2,Policy.Witness>:
  match value:
    case None{}: tail
    case Some{item}: item <> tail
def witness_paths(tick:U32,shot:U32,x:F32,y:F32,radius:F32,next:Projectile.Shot,target:Contact.Target) -> Maybe<&2,Policy.Witness>:
  match next target:
    case Projectile.Shot{x1,y1,_,_,_,_,_} Contact.Target{seed,ex0,ey0,ex1,ey1,r}: Policy.witness(tick,shot,seed,x,y,x1,y1,ex0,ey0,ex1,ey1,(radius + r : F32))
def witness_target(tick:U32,shot:U32,x:F32,y:F32,radius:F32,next:Projectile.Shot,target:Maybe<&2,Contact.Target>) -> Maybe<&2,Policy.Witness>:
  match target:
    case None{}: None{}
    case Some{path}: witness_paths(tick,shot,x,y,radius,next,path)
def witnesses_for_targets(ids:List<&2,U32>,+tick:U32,+shot:U32,+x:F32,+y:F32,+radius:F32,+next:Projectile.Shot,+targets:BI.Index<Contact.Target>) -> List<&2,Policy.Witness>:
  match ids:
    case []: []
    case head <> tail: add_witness(witness_target(tick,shot,x,y,radius,next,BI.find(~Contact.Target,targets,head)),witnesses_for_targets(tail,tick,shot,x,y,radius,next,targets))
def witness_shot(+tick:U32,+team:G.Team,ids:List<&2,U32>,targets:BI.Index<Contact.Target>,snapshot:Model.Snapshot) -> List<&2,Policy.Witness>:
  match snapshot:
    case Model.ProjectileSnapshot{Shot.State{Space.Spatial{+x,+y,+age,+radius},+seed,+side,+payload,Components.Trajectory{+vx,+vy,+life,+pierce,+visited,+owner,+slot,Some{+sourcePlayer}}}}:
      witnesses_for_targets(ids,tick,seed,x,y,radius,Shot.next(Shot.State{Space.Spatial{x,y,age,radius},seed,side,payload,Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,Some{sourcePlayer}}},G.contact_shot_input(G.team_args(team,G.team_for_id(team,sourcePlayer)),G.nearest_from_args(G.team_base(team),x,y))),targets)
    case _: []

def witness_next(found:Maybe<&2,Projectile.Shot>,tick:U32,team:G.Team,ids:List<&2,U32>,targets:BI.Index<Contact.Target>,snapshot:Model.Snapshot) -> List<&2,Policy.Witness>:
  match found snapshot:
    case None{} _: witness_shot(tick,team,ids,targets,snapshot)
    case Some{next} Model.ProjectileSnapshot{Shot.State{Space.Spatial{x,y,_,radius},seed,_,_,_}}: witnesses_for_targets(ids,tick,seed,x,y,radius,next,targets)
    case _ _: []

def witness_source(tick:U32,team:G.Team,ids:List<&2,U32>,targets:BI.Index<Contact.Target>,next:BI.Index<Projectile.Shot>,snapshot:Maybe<&2,Model.Snapshot>) -> List<&2,Policy.Witness>:
  match snapshot:
    case None{}: []
    case Some{+shot}: witness_next(BI.find(~Projectile.Shot,next,G.snapshot_identity(shot)),tick,team,ids,targets,shot)
def area_witnesses(targets:List<&2,Contact.Target>,+tick:U32,+shot:U32,+x:F32,+y:F32,+radius:F32) -> List<&2,Policy.Witness>:
  match targets:
    case []: []
    case Contact.Target{+seed,_,_,+ex,+ey,+r} <> tail: add_witness(Policy.point_record(G.hit_recipient(True{},[],seed,ex,ey,r,x,y,radius),tick,shot,seed,x,y,ex,ey,(radius + r : F32)),area_witnesses(tail,tick,shot,x,y,radius))
def area_plans(rows:List<&2,G.HitPlan>,+tick:U32,+targets:List<&2,Contact.Target>) -> List<&2,Policy.Witness>:
  match rows:
    case []: []
    case G.HitPlan{shot,_,_,x,y,radius,True{},_} <> tail: List.append(&2,Policy.Witness,area_witnesses(targets,tick,shot,x,y,radius),area_plans(tail,tick,targets))
    case _ <> tail: area_plans(tail,tick,targets)
def witnesses(rows:List<&2,G.HitPlan>,+tick:U32,+team:G.Team,+shots:BI.Index<Model.Snapshot>,+targets:BI.Index<Contact.Target>,+next:BI.Index<Projectile.Shot>) -> List<&2,Policy.Witness>:
  match rows:
    case []: []
    case G.HitPlan{_,_,_,_,_,_,False{},Nil{}} <> tail: witnesses(tail,tick,team,shots,targets,next)
    case G.HitPlan{shot,_,_,_,_,_,False{},ids} <> tail: List.append(&2,Policy.Witness,witness_source(tick,team,ids,targets,next,BI.find(~Model.Snapshot,shots,shot)),witnesses(tail,tick,team,shots,targets,next))
    case _ <> tail: witnesses(tail,tick,team,shots,targets,next)
def stamp_witnesses(rows:List<&2,Policy.Witness>,+births:BI.Index<U32>) -> List<&2,Policy.Witness>:
  match rows:
    case []: []
    case head <> tail: Policy.stamp_births(births,head) <> stamp_witnesses(tail,births)
def add_recent(keep:Bool,value:Policy.Witness,tail:List<&2,Policy.Witness>) -> List<&2,Policy.Witness>:
  match keep:
    case False{}: tail
    case True{}: value <> tail
def recent_witnesses(rows:List<&2,Policy.Witness>,+now:U32) -> List<&2,Policy.Witness>:
  match rows:
    case []: []
    case +head <> tail: add_recent(Policy.recent(now,head),head,recent_witnesses(tail,now))
def diagnostic_needed(rows:List<&2,G.HitPlan>) -> Bool:
  match rows:
    case []: False{}
    case G.HitPlan{_,_,_,_,_,_,False{},Nil{}} <> tail: diagnostic_needed(tail)
    case _: True{}
def step_witnesses_selected(needed:Bool,+team:G.Team,+tick:U32,previous:List<&2,Model.Snapshot>,births:BI.Index<U32>,+targets:List<&2,Contact.Target>,next:BI.Index<Projectile.Shot>) -> List<&2,Policy.Witness>:
  match needed:
    case False{}: []
    case True{}: stamp_witnesses(List.append(&2,Policy.Witness,witnesses(team_hits(team),tick,team,snapshot_index(previous),target_index(targets),next),area_plans(team_hits(team),tick,targets)),births)
def step_witnesses(+step:Prepared,tick:U32,previous:List<&2,Model.Snapshot>,births:BI.Index<U32>) -> List<&2,Policy.Witness>:
  step_witnesses_selected(diagnostic_needed(team_hits(prepared_team(step))),prepared_team(step),tick,previous,births,prepared_targets(step),prepared_next(step))
def diagnostic_contacts(enabled:Bool,step:Prepared,+tick:U32,previous:List<&2,Model.Snapshot>,births:BI.Index<U32>,contacts:List<&2,Policy.Witness>) -> List<&2,Policy.Witness>:
  match enabled:
    case False{}: []
    case True{}: List.append(&2,Policy.Witness,recent_witnesses(contacts,tick),step_witnesses(step,tick,previous,births))
def advanced_rows(own:U32,+players:List<&2,G.PlayerSnapshot>,+previous:List<&2,Model.Snapshot>,+births:BI.Index<U32>,directions:Session.Directions,contacts:List<&2,Policy.Witness>,+tick:U32,+diagnostics:Bool,+step:Prepared,+updated:List<&2,Model.Snapshot>) -> Scene:
  Scene{own,moved_players(players,team_views(prepared_team(step))),updated,W.birth_map(updated,tick,births,W.plan_births(team_plan(prepared_team(step)),tick),BI.Empty{}),directions,diagnostic_contacts(diagnostics,step,tick,previous,births,contacts),tick,diagnostics}
def advanced_team(+reference:Bool,own:U32,players:List<&2,G.PlayerSnapshot>,+previous:List<&2,Model.Snapshot>,births:BI.Index<U32>,directions:Session.Directions,contacts:List<&2,Policy.Witness>,tick:U32,diagnostics:Bool,+step:Prepared) -> Scene:
  advanced_rows(own,players,previous,births,directions,contacts,tick,diagnostics,step,List.append(&2,Model.Snapshot,choose_enemies(reference,previous,prepared_team(step),prepared_moved(step)),List.append(&2,Model.Snapshot,choose_projectiles(reference,previous,prepared_team(step),prepared_next(step)),spawned_projectiles(prepared_team(step)))))
def clocked_scene(+reference:Bool,+own:U32,+players:List<&2,G.PlayerSnapshot>,+snapshots:List<&2,Model.Snapshot>,births:BI.Index<U32>,+directions:Session.Directions,contacts:List<&2,Policy.Witness>,+tick:U32,diagnostics:Bool,+x:U32,+y:U32) -> Scene:
  match players:
    case []: Scene{own,[],snapshots,births,directions,contacts,tick,diagnostics}
    case G.PlayerSnapshot{+id,+run,+connected} <> +tail: advanced_team(reference,own,G.PlayerSnapshot{id,run,connected} <> tail,snapshots,births,directions,contacts,tick,diagnostics,make_team(reference,views(G.PlayerSnapshot{id,run,connected} <> tail,own,x,y,directions,tick),snapshots,own,run))
def advance_unchecked_mode(reference:Bool,scene:Scene,x:U32,y:U32) -> Scene:
  match scene:
    case Scene{own,players,snapshots,births,directions,contacts,tick,diagnostics}: clocked_scene(reference,own,players,snapshots,births,directions,contacts,Policy.next_tick(tick),diagnostics,x,y)
def advance_unchecked(scene:Scene,x:U32,y:U32) -> Scene: advance_unchecked_mode(False{},scene,x,y)
def advance_reference_unchecked(scene:Scene,x:U32,y:U32) -> Scene: advance_unchecked_mode(True{},scene,x,y)
def advance_reference(+scene:Scene,+x:U32,+y:U32) -> Scene: Replay.guard(~Scene,~advance_reference_unchecked,allowed(scene,x,y),scene,x,y)
def scene_tick(scene:Scene) -> U32:
  match scene:
    case Scene{_,_,_,_,_,_,tick,_}: tick
def forecast_reference_selected(matching:Bool,+scene:Scene,prediction:P.State) -> Scene:
  match matching:
    case False{}: scene
    case True{}: Replay.forecast(~Scene,~advance_reference,scene,prediction)
def forecast_reference(+scene:Scene,+prediction:P.State) -> Scene: forecast_reference_selected(P.matches_anchor(prediction,scene_tick(scene)),scene,prediction)
def advance(+scene:Scene,+x:U32,+y:U32) -> Scene: Replay.guard(~Scene,~advance_unchecked,allowed(scene,x,y),scene,x,y)
def forecast_selected(matching:Bool,+scene:Scene,prediction:P.State) -> Scene:
  match matching:
    case False{}: scene
    case True{}: Replay.forecast(~Scene,~advance,scene,prediction)
def forecast(+scene:Scene,+prediction:P.State) -> Scene: forecast_selected(P.matches_anchor(prediction,scene_tick(scene)),scene,prediction)
def rebase_selected(matching:Bool,previous:Scene,+anchor:Scene,prediction:P.State) -> Scene:
  match matching:
    case False{}: anchor
    case True{}: Policy.rebase(~Scene,~advance,previous,anchor,prediction)
def rebase(previous:Scene,+anchor:Scene,+prediction:P.State) -> Scene: rebase_selected(P.matches_anchor(prediction,scene_tick(anchor)),previous,anchor,prediction)
