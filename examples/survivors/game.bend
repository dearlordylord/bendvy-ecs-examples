import game-observation.bend as Model
import run-state.bend as RS
import Base
import enemy-effects.bend as Effect
import pickup-state.bend as Pickup
import pickup-xp-pool.bend as PickupPool
import pickup-from-death.bend as PickupDeath
import pickup-relic.bend as PickupRelic
import enemy-combat.bend as Enemy
import enemy-lifecycle.bend as EnemyLife
import enemy-spawn.bend as EnemySpawn
import combat-policy.bend as Combat
import music.bend as Music
import arena.bend as A
import player-movement.bend as PlayerMovement
import prediction-spawn.bend as PredictionSpawn
import projectile.bend as P
import projectile-state.bend as Shot
import encounters.bend as E
import spawn-policy.bend as S
import persistent-xp.bend as X
import body-index.bend as BI
import pools.bend as PL
import party-difficulty.bend as PartyDifficulty
import movement-membership.bend as MM
import enemy-spatial.bend as Space
import enemy-targets.bend as Targets
import game-components.bend as Components
import game-storage.bend as Storage
import entity-role.bend as Role
import projectile-pool.bend as SP
import loot-visual.bend as LV
import loot-placement.bend as LootPlacement
import projectile-contact.bend as Contact
import pickup-policy.bend as PickupPolicy
import bendvy-ecs-core@0.1.0.2/world.bend as W
import bendvy-ecs-core@0.1.0.2/column.bend as Col
import bendvy-ecs-core@0.1.0.2/component.bend as C
import bendvy-ecs-core@0.1.0.2/commands.bend as Cmd
import bendvy-ecs-core@0.1.0.2/transaction.bend as T
import bendvy-ecs-core@0.1.0.2/compose.bend as Q
import bendvy-ecs-core@0.1.0.2/owned_compose.bend as OwnedQ

# Frame kinds: enemy0, player shot1, XP2, gold3, heal4, chest5, hostile shot7.
# Dormant8 never renders. Health and XP payload fields are presentation views;
# Components.Vitals and Components.Pickup are their independent authoritative components.
# Detached update payload shared by the live pure helpers and snapshots.
# Authoritative storage separates projectile trajectory from enemy status.
# Derived routing metadata contains only issued identities, never gameplay data.
# Enemy/relic position, age and collision radius have one authoritative column.
# Movement advances age once; birth and loot lifecycle may reset it explicitly.
def empty_trajectory() -> Components.Trajectory: Components.Trajectory{0.0,0.0,0,0,[],0,0,None{}}
def empty_status() -> Components.Status: Components.Status{Effect.empty_slow(),Effect.empty_burn()}
def routing_world(result: Storage.World() & Unit) -> Storage.World():
  match result:
    case (world,_): world
# Setup writes components before prepare_movement_roster completes the world.
# Gameplay queries consume prepared handles; lifecycle refreshes active rows.
def vital_populated(result: C.Replacement<Storage.World(),Components.Vitals>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def status_populated(result: C.Replacement<Storage.World(),Components.Status>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def trajectory_populated(result: C.Replacement<Storage.World(),Components.Trajectory>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def role_populated(result: C.Replacement<Storage.World(),Role.Role>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def spatial_populated(result: C.Replacement<Storage.World(),Space.Spatial>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def populate_spatial(world: Storage.World(),handle: W.Handle<Storage.Schema>,space: Space.Spatial) -> Storage.World():
  spatial_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,Storage.spatial_family(),world,handle,Some{space}))
def populate_enemy(world: Storage.World(),+handle: W.Handle<Storage.Schema>) -> Storage.World():
  status_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.StatusRest,~Components.Status,~Components.Status,~Storage.StatusToken,~Storage.take_status,~Storage.put_status,~Storage.project_status,Storage.status_family(),vital_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.VitalRest,~Components.Vitals,~Components.Vitals,~Storage.VitalToken,~Storage.take_vitals,~Storage.put_vitals,~Storage.project_vitals,Storage.vital_family(),world,handle,Some{Components.Vitals{0,0}})),handle,Some{empty_status()}))
def shot_populated(result: C.Replacement<Storage.World(),Components.ShotPayload>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def populate_projectile(world: Storage.World(),+handle: W.Handle<Storage.Schema>) -> Storage.World():
  shot_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.ShotRest,~Components.ShotPayload,~Components.ShotPayload,~Storage.ShotToken,~Storage.take_shot,~Storage.put_shot,~Storage.project_shot,Storage.shot_family(),trajectory_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.TrajectoryRest,~Components.Trajectory,~Components.Trajectory,~Storage.TrajectoryToken,~Storage.take_trajectory,~Storage.put_trajectory,~Storage.project_trajectory,Storage.trajectory_family(),world,handle,Some{empty_trajectory()})),handle,Some{Components.ShotPayload{0,0,False{}}}))
def pickup_populated(result: C.Replacement<Storage.World(),Pickup.Payload>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def populate_pickup(world: Storage.World(),handle: W.Handle<Storage.Schema>) -> Storage.World():
  pickup_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PickupRest,~Pickup.Payload,~Pickup.Payload,~Storage.PickupToken,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,Storage.pickup_family(),world,handle,Some{Pickup.Payload{Pickup.Xp{0,False{}},0,False{}}}))
def identity_populated(result: C.Replacement<Storage.World(),Components.Identity>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def populate_identity(world: Storage.World(),handle: W.Handle<Storage.Schema>,slot: U32) -> Storage.World():
  identity_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.IdentityRest,~Components.Identity,~Components.Identity,~Storage.IdentityToken,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,Storage.identity_family(),world,handle,Some{Components.Identity{slot}}))
def phase_populated(result: C.Replacement<Storage.World(),Enemy.Phase>) -> Storage.World():
  match result:
    case C.Replaced{world,_}: world
    case C.ReplaceRejected{world,_,_}: world
def populate_phase(world: Storage.World(),handle: W.Handle<Storage.Schema>,phase: Enemy.Phase) -> Storage.World():
  phase_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,Storage.phase_family(),world,handle,Some{phase}))
def populate_components(role: Role.Role,world: Storage.World(),+handle: W.Handle<Storage.Schema>,slot: U32) -> Storage.World():
  match role:
    case Role.EnemySlot{}: populate_pickup(populate_phase(populate_enemy(world,handle),handle,Enemy.Dormant{slot}),handle)
    case Role.RelicSlot{}: populate_pickup(populate_phase(world,handle,Enemy.Dormant{0}),handle)
    case Role.PlayerProjectileSlot{}: populate_projectile(world,handle)
    case Role.HostileProjectileSlot{}: populate_projectile(world,handle)
    case Role.XpSlot{}: populate_pickup(world,handle)
    case _: world
def populate_slot(world: Storage.World(),+handle: W.Handle<Storage.Schema>,+slot: U32) -> Storage.World():
  populate_components(Role.assigned(slot),role_populated(C.structural_replace(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,Storage.role_family(),populate_identity(populate_spatial(world,handle,Space.Spatial{0.0,0.0,slot,0.0}),handle,slot),handle,Some{Role.assigned(slot)})),handle,slot)
def populate(world: Storage.World(),handle: W.Handle<Storage.Schema>,slot: U32) -> Storage.World(): populate_slot(world,handle,slot)
def spawn_finish(result: T.Tx<Storage.World(),Unit> & W.Reservation<Storage.Schema>) -> Storage.World():
  match result:
    case (T.Tx{world,_,commands,_,_},W.Reserved{_}): Cmd.enqueue(~Storage.Schema,~Storage.Store,~Unit,~Unit,world,commands)
    case (T.Tx{world,_,_,_,_},W.ReservationRejected{_}): world
def spawn(world: Storage.World(),slot: U32) -> Storage.World():
  spawn_finish(Cmd.tx_spawn(~Storage.Schema,~Storage.Store,~Unit,~Unit,~U32,~populate,T.begin(~Storage.World(),~Unit,world),slot))
# Enemy slots recycle independently of the persistent XP pool.
# Weapons and progression are immutable run data; entity updates use checked queries.
def run_session(value: Model.Run) -> RS.Session: Model.run_session(value)
def run_player(value: Model.Run) -> RS.PlayerState: Model.run_player(value)
# Frozen rule/prediction context; never stored back as authoritative player data.
type PlayerSnapshot is Data: PlayerSnapshot{id: U32,run: Model.Run,connected: Bool}
def snapshot_geometry(snapshot: Model.Snapshot) -> Model.SnapshotGeometry: Model.snapshot_geometry(snapshot)
def geometry_identity(geometry: Model.SnapshotGeometry) -> U32: Model.geometry_identity(geometry)
def snapshot_identity(snapshot: Model.Snapshot) -> U32: Model.snapshot_identity(snapshot)
def geometry_age(geometry: Model.SnapshotGeometry) -> U32: Model.geometry_age(geometry)
def snapshot_age(snapshot: Model.Snapshot) -> U32: Model.snapshot_age(snapshot)
def enemy_observations(snapshots: List<&2,Model.Snapshot>) -> List<&2,Enemy.State>: Model.enemy_observations(snapshots)
def pickup_observations(snapshots: List<&2,Model.Snapshot>) -> List<&2,Pickup.State>: Model.pickup_observations(snapshots)
type State is Type: State{world: Storage.World(),run: Model.Run,offers: List<&2,Model.Offer>,snapshots: List<&2,Model.Snapshot>,pending: List<&2,U32>}
type ActorRef is Data: EnemyRef{identity: U32} ProjectileRef{identity: U32} PickupRef{identity: U32}
def snapshot_render_ref(snapshot: Model.Snapshot) -> Maybe<&2,ActorRef>:
  match snapshot:
    case Model.EnemySnapshot{Enemy.State{_,_,identity,_,_}}: Some{EnemyRef{identity}}
    case Model.ProjectileSnapshot{Shot.State{_,identity,_,Components.ShotPayload{_,_,True{}},_}}: Some{ProjectileRef{identity}}
    case Model.ProjectileSnapshot{_}: None{}
    case Model.PickupSnapshot{Pickup.State{_,Pickup.Payload{_,_,True{}},identity}}: Some{PickupRef{identity}}
    case Model.PickupSnapshot{_}: None{}
def keep_render_ref(reference: Maybe<&2,ActorRef>,tail: List<&2,ActorRef>) -> List<&2,ActorRef>:
  match reference:
    case Some{reference}: reference <> tail
    case None{}: tail
def render_order(snapshots: List<&2,Model.Snapshot>) -> List<&2,ActorRef>:
  match snapshots:
    case []: []
    case snapshot <> rest: keep_render_ref(snapshot_render_ref(snapshot),render_order(rest))
def keep_projectile_observation(present: Bool,projectile: Shot.State,tail: List<&2,Shot.State>) -> List<&2,Shot.State>:
  match present:
    case True{}: projectile <> tail
    case False{}: tail
def projectile_observations(snapshots: List<&2,Model.Snapshot>) -> List<&2,Shot.State>:
  match snapshots:
    case []: []
    case Model.ProjectileSnapshot{+projectile} <> rest: keep_projectile_observation(Shot.present(projectile),projectile,projectile_observations(rest))
    case _ <> rest: projectile_observations(rest)
type PresentationContext is Data: PresentationContext{worldSize: F32,worldMargin: F32,relicX: F32,relicY: F32,runLength: U32}
type Observation is Data: Observation{presentation: PresentationContext,run: Model.Run,offers: List<&2,Model.Offer>,enemies: List<&2,Enemy.State>,order: List<&2,ActorRef>,projectiles: List<&2,Shot.State>,pickups: List<&2,Pickup.State>}

type Observed is Type: Observed{state: State,observation: Observation}

type Packet is Type: Packet{state: State}
  Failed{error: String}
def at(values: List<&2,U32>,index: U32) -> U32: Model.at(values,index)
def bump(values: List<&2,U32>,index: U32) -> List<&2,U32>:
  match values index:
    case Nil{} _: []
    case Con{head,tail} 0: (head + 1 : U32) <> tail
    case Con{head,tail} index: head <> bump(tail,(index - 1 : U32))
def set_at(values: List<&2,U32>,index: U32,+value: U32) -> List<&2,U32>:
  match values index:
    case Nil{} _: []
    case Con{_,rest} 0: value <> rest
    case Con{head,rest} index: head <> set_at(rest,(index - 1 : U32),value)
def dec(+value: U32) -> U32: U32.sub(value,U32.min(value,1))
def distance2(+x: F32,+y: F32,+px: F32,+py: F32) -> F32: ((x - px) * (x - px) + (y - py) * (y - py) : F32)
def close(x: F32,y: F32,px: F32,py: F32,+radius: F32) -> Bool: F32.is_le(distance2(x,y,px,py),(radius * radius : F32))
# Music observes the world at host audio cadence, never in the ECS tick.
def projectile_threats(rows: List<&2,Shot.State>) -> List<&2,Music.ProjectileThreat>:
  match rows:
    case []: []
    case Shot.State{Space.Spatial{x,y,_,_},_,Shot.HostileShot{},Components.ShotPayload{_,_,True{}},_} <> rest: Music.ProjectileThreat{x,y} <> projectile_threats(rest)
    case _ <> rest: projectile_threats(rest)
def music_danger(hp: U32,maxHp: U32,+px: F32,+py: F32,hostiles: List<&2,Music.ProjectileThreat>,enemies: List<&2,Music.Threat>) -> U32:
  Music.danger(hp,maxHp,U32.min(1000,(Music.projectile_pressure(hostiles,px,py) + Music.enemy_pressure(enemies,px,py) : U32)))

# Early growth is quick; quadratic later costs prevent serial upgrade interruptions.
def next_xp_need(+level: U32) -> U32: (40 + level * 6 + level * level / 3 : U32)
# Entity seeds remain stable pool identities; run entropy changes only spawn placement.
# Ordinary waves use a 300 baseline; Curse may raise admission up to 500.
def active_limit(+tick: U32) -> U32: U32.min(PL.normal_enemy_cap(),(96 + tick / 50 : U32))
def boot_pool(remaining: Nat,+slot: U32,world: Storage.World()) -> Storage.World():
  match remaining:
    case 0n: world
    case 1n+rest: boot_pool(rest,(slot + 1 : U32),spawn(world,slot))
# Bootstrap/setup snapshots use real allocator-visible handles and checked Role.
# Only allocation interprets numeric ranges; systems select immutable composition.
# Lifecycle later refreshes active membership during its existing traversal.
def movement_roster_store_fields(handles: List<&2,W.Handle<Storage.Schema>>,store: Storage.StoreFields) -> Storage.Store & Unit:
  match store:
    case Storage.StoreFields{vitals,motions,statuses,pickups,roles,_,candidates,players,spaces,enemyPhases,identities,shots}: (Storage.Owned{Storage.StoreFields{vitals,motions,statuses,pickups,roles,Storage.MovementPrepared{handles},candidates,players,spaces,enemyPhases,identities,shots}},Unit{})
def movement_roster_store(handles: List<&2,W.Handle<Storage.Schema>>,store: Storage.Store) -> Storage.Store & Unit: movement_roster_store_fields(handles,Storage.unseal(store))
def movement_roster_save(world: Storage.World(),handles: List<&2,W.Handle<Storage.Schema>>) -> Storage.World():
  routing_world(W.with_store(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Unit,movement_roster_store(handles),world))
def movement_roster_keep(selected: Bool,handle: W.Handle<Storage.Schema>,reversed: List<&2,W.Handle<Storage.Schema>>) -> List<&2,W.Handle<Storage.Schema>>:
  match selected:
    case True{}: handle <> reversed
    case False{}: reversed
type RoutingCapture is Data: RoutingCapture{projectiles: List<&2,W.Handle<Storage.Schema>>,pool: List<&2,W.Handle<Storage.Schema>>,active: List<&2,W.Handle<Storage.Schema>>}
def routing_capture_store_fields(capture: RoutingCapture,store: Storage.StoreFields) -> Storage.Store & Unit:
  match capture store:
    case RoutingCapture{projectiles,pool,active} Storage.StoreFields{vitals,motions,statuses,pickups,roles,_,_,players,spaces,enemyPhases,identities,shots}: (Storage.Owned{Storage.StoreFields{vitals,motions,statuses,pickups,roles,Storage.MovementPrepared{List.reverse(&2,W.Handle<Storage.Schema>,active)},Storage.CandidatesPrepared{List.reverse(&2,W.Handle<Storage.Schema>,projectiles),List.reverse(&2,W.Handle<Storage.Schema>,pool)},players,spaces,enemyPhases,identities,shots}},Unit{})
def routing_capture_store(capture: RoutingCapture,store: Storage.Store) -> Storage.Store & Unit: routing_capture_store_fields(capture,Storage.unseal(store))
def routing_capture_keep(+role: Role.Role,+handle: W.Handle<Storage.Schema>,active: Bool,capture: RoutingCapture) -> RoutingCapture:
  match capture:
    case RoutingCapture{projectiles,pool,movement}: RoutingCapture{movement_roster_keep(Role.projectile(role),handle,projectiles),movement_roster_keep(Role.pool(role),handle,pool),movement_roster_keep(active,handle,movement)}
def routing_capture_phase_active(role: Role.Role,result: C.Access<Enemy.Phase>) -> Bool:
  match result:
    case C.Found{phase}: Bool.and(Role.enemy(role),Enemy.active(phase))
    case _: False{}
def routing_capture_phase(+role: Role.Role,handle: W.Handle<Storage.Schema>,capture: RoutingCapture,result: Storage.World() & C.Access<Enemy.Phase>) -> Storage.World() & RoutingCapture:
  match result:
    case (world,phase): (world,routing_capture_keep(role,handle,routing_capture_phase_active(role,phase),capture))
def routing_capture_role(+handle: W.Handle<Storage.Schema>,capture: RoutingCapture,result: Storage.World() & C.Access<Role.Role>) -> Storage.World() & RoutingCapture:
  match result:
    case (world,C.Found{+role}): routing_capture_phase(role,handle,capture,C.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,Storage.phase_family(),world,handle))
    case (world,_): (world,capture)
def routing_capture_collect(handles: List<&2,W.Handle<Storage.Schema>>,state: Storage.World() & RoutingCapture) -> Storage.World():
  match handles state:
    case [] Tuple{world,capture}: routing_world(W.with_store(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Unit,routing_capture_store(capture),world))
    case Con{+handle,rest} Tuple{world,capture}: routing_capture_collect(rest,routing_capture_role(handle,capture,C.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,Storage.role_family(),world,handle)))
def routing_capture_visible(result: Storage.World() & List<&2,W.Handle<Storage.Schema>>) -> Storage.World():
  match result:
    case (world,handles): routing_capture_collect(handles,(world,RoutingCapture{[],[],[]}))
def prepare_movement_roster(world: Storage.World()) -> Storage.World():
  routing_capture_visible(W.handles(~Storage.Schema,~Storage.Store,~Unit,~Unit,world))
def world_size() -> F32: Model.world_size()
def world_center() -> F32: Model.world_center()
def world_margin() -> F32: Model.world_margin()
def relic_x(stage: U32) -> F32: U32.to_f32(at([10800,7200,3600,7200,10080],stage))
def relic_y(stage: U32) -> F32: U32.to_f32(at([7200,3600,7200,10800,9360],stage))
def run_length(mode: U32) -> U32:
  match mode:
    case 3: 18000
    case _: 36000
def presentation_context(run: Model.Run) -> PresentationContext:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,+stage,_,mode,_,_},_}: PresentationContext{world_size(),world_margin(),relic_x(stage),relic_y(stage),run_length(mode)}
def observation(+run: Model.Run,offers: List<&2,Model.Offer>,+snapshots: List<&2,Model.Snapshot>) -> Observation:
  Observation{presentation_context(run),run,offers,enemy_observations(snapshots),render_order(snapshots),projectile_observations(snapshots),pickup_observations(snapshots)}
def observe(state: State) -> Observed:
  match state:
    case State{world,+run,+offers,+snapshots,pending}: Observed{State{world,run,offers,snapshots,pending},observation(run,offers,snapshots)}
def wave_tick(+mode: U32,tick: U32) -> U32: (tick * (1 + Bool.to_u32(U32.is_eq(mode,3))) : U32)
def packet(state: State) -> Packet: Packet{state}
def meta_max(id: U32) -> U32: Model.meta_max(id)
def meta_rank(+meta: U32,+id: U32) -> U32: Model.meta_rank(meta,id)
def starter(character: U32) -> U32: at([0,1,4,8,2,10,15,21],(character % 8 : U32))
def character_health(character: U32) -> U32:
  match character:
    case 4: 125
    case _: 100
def initial_health(+character: U32,+meta: U32) -> U32: (character_health(character) * (100 + meta_rank(meta,1) * 10) / 100 : U32)
def stat_bonus(+arcana: U32,+wanted: U32) -> F32: Model.stat_bonus(arcana,wanted)
def speed_bonus(+passives: List<&2,U32>,+meta: U32,+arcana: U32,+character: U32) -> F32: Model.speed_bonus(passives,meta,arcana,character)
def configured(run: Model.Run,+selectedStage: U32,+selectedArcana: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+need,+level,+kills,+gold,+seed,_,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,_,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}:
      Model.Run{RS.Session{phase,tick,xp,need,level,kills,gold,seed,U32.min(selectedStage,4),bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,F32.to_u32((U32.to_f32(initial_health(character,meta)) * (1.0 - 0.30 * stat_bonus(selectedArcana,0) + 0.25 * stat_bonus(selectedArcana,9)) : F32)),F32.to_u32((U32.to_f32(initial_health(character,meta)) * (1.0 - 0.30 * stat_bonus(selectedArcana,0) + 0.25 * stat_bonus(selectedArcana,9)) : F32)),character,weapons,passives,invuln,U32.min(selectedArcana,11),meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def configure(state: State,+stageChoice: U32,+arcanaChoice: U32) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{+phase,0,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,configured(Model.Run{RS.Session{phase,0,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},stageChoice,arcanaChoice),offers,snapshots,pending})
    case state: packet(state)
def period(id: U32) -> U32:
  match id:
    case 0: 40
    case 1: 30
    case 2: 90
    case 3: 14
    case 4: 24
    case 5: 120
    case 6: 70
    case 7: 110
    case 8: 80
    case 9: 65
    case 10: 100
    case 11: 600
    case +id: (35 + (id % 6) * 13 : U32)
type HitPlan is Data: HitPlan{shot: U32,weapon: U32,damage: U32,x: F32,y: F32,radius: F32,area: Bool,targets: List<&2,U32>}
type Args is Data: Args{run: Model.Run,targets: Targets.Targets,dx: F32,dy: F32,snapshots: List<&2,Model.Snapshot>,hits: List<&2,HitPlan>}
def empty_shot_plan() -> SP.Plan: SP.Plan{BI.Empty{},0}
type Error is Data: MissingComponent{}
def pickup_radius(+passives: List<&2,U32>,+meta: U32,+arcana: U32,+character: U32) -> F32:
  (24.0 * (1.0 + U32.to_f32(at(passives,8)) * 0.25 + U32.to_f32(meta_rank(meta,6)) * 0.15 + stat_bonus(arcana,6) + 0.50 * U32.to_f32(Bool.to_u32(U32.is_eq(character,7)))) : F32)
# Age and item kind never authorize collection: only physical reach does.
def pickup_admission(x: F32,y: F32,px: F32,py: F32,radius: F32,age: U32,kind: U32) -> Bool:
  PickupPolicy.admission(x,y,px,py,radius,age,kind)
# Spawn cadence rejects five of six slots before evaluating wave limits or
# passive ranks. Variant and curse are only materialized for admitted spawns.
type EntityRow is Data:
  NoEntityRow{}
  EnemyRow{outcome: Enemy.Outcome,credit: Enemy.Credit}
  ProjectileRow{outcome: Shot.Outcome}
  PickupRow{outcome: Pickup.Outcome}
type EnemyQueryResult is Data: EnemyReady{row: EntityRow} LootRequest{advance: Bool}
# Spatial snapshots are only observations; Q capabilities own all three components.
type Aim is Data: Aim{x: F32,y: F32,id: U32,distance: F32}
def prefer_aim(closer: Bool,+x: F32,+y: F32,+id: U32,+distance: F32,rest: Aim) -> Aim:
  match closer:
    case True{}: Aim{x,y,id,distance}
    case False{}: rest
def aim_distance(aim: Aim) -> F32:
  match aim:
    case Aim{_,_,_,distance}: distance
def nearest_targets(rows: List<&2,Targets.Target>,+x: F32,+y: F32,+best: Aim) -> Aim:
  match rows:
    case []: best
    case Targets.Target{+tx,+ty,seed} <> rest: nearest_targets(rest,x,y,prefer_aim(F32.is_lt(distance2(x,y,tx,ty),aim_distance(best)),tx,ty,seed,distance2(x,y,tx,ty),best))
def nearest(targets: Targets.Targets,x: F32,y: F32,best: Aim) -> Aim:
  match targets:
    case Targets.Targets{aims,_}: nearest_targets(aims,x,y,best)
def contains(rows: List<&2,U32>,+id: U32) -> Bool:
  match rows:
    case []: False{}
    case head <> rest: Bool.or(U32.is_eq(head,id),contains(rest,id))
# Frozen phase targets contain only the facts actually read by aiming/firing.
# This boundary projects the existing observation; actor slices replace its input.
def enemy_targets(rows: List<&2,Model.Snapshot>) -> Targets.Targets:
  match rows:
    case []: Targets.empty()
    case Model.EnemySnapshot{Enemy.State{Space.Spatial{x,y,age,_},archetype,identity,_,_}} <> rest: Targets.add_enemy(x,y,identity,archetype,age,enemy_targets(rest))
    case _ <> rest: enemy_targets(rest)
def combat_args_enemies(run: Model.Run,targets: Targets.Targets,dx: F32,dy: F32,snapshots: List<&2,Model.Snapshot>) -> Args:
  Args{run,targets,dx,dy,snapshots,[]}
def combat_args(run: Model.Run,dx: F32,dy: F32,+snapshots: List<&2,Model.Snapshot>) -> Args:
  combat_args_enemies(run,enemy_targets(snapshots),dx,dy,snapshots)
def select_hit_targets(selected: Bool,targets: List<&2,U32>) -> List<&2,U32>:
  match selected:
    case True{}: targets
    case False{}: []
def hit_targets(rows: List<&2,HitPlan>,+seed: U32) -> List<&2,U32>:
  match rows:
    case []: []
    case HitPlan{+shot,_,_,_,_,_,_,+targets} <> rest: List.append(&2,U32,select_hit_targets(U32.is_eq(shot,seed),targets),hit_targets(rest,seed))
def cooldown_for(+id: U32,+passives: List<&2,U32>,+meta: U32,+arcana: U32,+character: U32) -> U32:
  U32.max(6,F32.to_u32((U32.to_f32(period(id)) * F32.max(0.12,(1.0 - U32.to_f32(at(passives,1)) * 0.07 - U32.to_f32(meta_rank(meta,4)) * 0.03 - 0.20 * stat_bonus(arcana,1) - 0.10 * U32.to_f32(Bool.to_u32(U32.is_eq(character,5))) + 0.15 * stat_bonus(arcana,3) : F32)) : F32)))
def area_bonus(+passives: List<&2,U32>,+arcana: U32,+level: U32) -> F32: Model.area_bonus(passives,arcana,level)
def duration_bonus(+passives: List<&2,U32>,+arcana: U32) -> F32: Model.duration_bonus(passives,arcana)
def projectile_speed(+passives: List<&2,U32>,+arcana: U32) -> F32: Model.projectile_speed(passives,arcana)
def weapon_damage(+id: U32,+level: U32,+passives: List<&2,U32>,+meta: U32,+arcana: U32,+character: U32) -> U32:
  F32.to_u32((U32.to_f32((5 + level * 3 + id % 4 * 2 : U32)) * (1.0 + U32.to_f32(at(passives,0)) * 0.10 + U32.to_f32(meta_rank(meta,0)) * 0.05 + 0.35 * stat_bonus(arcana,0) + 0.15 * stat_bonus(arcana,8) + 0.10 * U32.to_f32(Bool.to_u32(U32.is_eq(character,0))) + 0.20 * U32.to_f32(Bool.to_u32(U32.is_eq(character,6)))) * (1.0 - 0.15 * stat_bonus(arcana,4)) * (1.0 + (0.20 + U32.to_f32(at(passives,14)) * 0.05) * U32.to_f32(Bool.to_u32(Bool.and(U32.is_eq(arcana,5),Bool.or(U32.is_eq(id,9),U32.is_eq(id,11)))))) * (1.0 + 1.2 * U32.to_f32(Bool.to_u32(U32.is_le(9,level)))) : F32))
def direction_x(+dx: F32,+dy: F32) -> F32: ((dx + U32.to_f32(Bool.to_u32(F32.is_lt((dx * dx + dy * dy : F32),0.01)))) / F32.max(1.0,F32.sqrt((dx * dx + dy * dy : F32))) : F32)
def direction_y(+dx: F32,+dy: F32) -> F32: (dy / F32.max(1.0,F32.sqrt((dx * dx + dy * dy : F32))) : F32)
def union_base(+id: U32) -> U32: at([0,1,2,3,4,6],id)
def union_partner(+id: U32) -> U32: at([5,13,15,23,19,17],id)
def secondary_weapon(+id: U32) -> U32: at([5,13,15,23,19,0,17,20,9,23,5,17,4,8,17,2,6,14,9,4,3,5,20,5],id)
def choose_id(select: Bool,yes: U32,no: U32) -> U32:
  match select:
    case True{}: yes
    case False{}: no
def effective_weapon(+base: U32,+level: U32,+slot: U32) -> U32:
  choose_id(Bool.and(U32.is_le(10,level),U32.is_eq((slot % 3 : U32),2)),at([16,23,3,18,20,14],Combat.lose(level,10)),choose_id(Bool.and(U32.is_le(10,level),U32.is_eq((slot % 2 : U32),1)),union_partner(Combat.lose(level,10)),choose_id(Bool.and(U32.is_le(9,level),U32.is_eq((slot % 2 : U32),1)),secondary_weapon(base),choose_id(Bool.and(U32.is_eq(base,21),U32.is_eq((slot % 2 : U32),1)),0,base))))
def familiar_x(+id: U32,+owner: U32,+slot: U32,+px: F32,+tick: U32) -> F32:
  (px + E.choose_float(Bool.and(U32.is_eq(owner,21),Bool.not(U32.is_eq(id,21))),(F32.cos((U32.to_f32(tick) * 0.035 + U32.to_f32(slot) * 0.3926991 : F32)) * 80.0 : F32),0.0) : F32)
def familiar_y(+id: U32,+owner: U32,+slot: U32,+py: F32,+tick: U32) -> F32:
  (py + E.choose_float(Bool.and(U32.is_eq(owner,21),Bool.not(U32.is_eq(id,21))),(F32.sin((U32.to_f32(tick) * 0.035 + U32.to_f32(slot) * 0.3926991 : F32)) * 80.0 : F32),0.0) : F32)
def aim_direction_x(+dx: F32,+dy: F32,+px: F32,+py: F32,+tx: F32,+ty: F32) -> F32:
  E.choose_float(F32.is_lt((dx * dx + dy * dy : F32),0.01),P.aim_x(px,py,tx,ty),direction_x(dx,dy))
def aim_direction_y(+dx: F32,+dy: F32,+px: F32,+py: F32,+tx: F32,+ty: F32) -> F32:
  E.choose_float(F32.is_lt((dx * dx + dy * dy : F32),0.01),P.aim_y(px,py,tx,ty),direction_y(dx,dy))
def shot_spawn_aim(+owner: U32,sourcePlayer: U32,fire: Bool,+seed: U32,+id: U32,+slot: U32,+level: U32,input: Shot.SpawnInput) -> EntityRow:
  match fire:
    case False{}: ProjectileRow{Shot.Outcome{Shot.dormant(0.0,0.0,seed,Shot.PlayerShot{}),0}}
    case True{}: ProjectileRow{Shot.Outcome{Shot.spawn(seed,id,level,owner,slot,sourcePlayer,slot,input),0}}
def shot_spawn_at(tick: U32,px: F32,py: F32,dx: F32,dy: F32,damage: U32,speed: F32,area: F32,duration: F32,aim: Aim) -> Shot.SpawnInput:
  match aim:
    case Aim{tx,ty,_,_}: Shot.SpawnInput{tick,px,py,dx,dy,tx,ty,damage,speed,area,duration}
def shot_spawn_input(+id: U32,+level: U32,run: Model.Run,dx: F32,dy: F32,targets: Targets.Targets) -> Shot.SpawnInput:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{+px,+py,_,_,character,_,+passives,_,+arcana,+meta,_,_,_,_,_,_}}: shot_spawn_at(tick,px,py,dx,dy,weapon_damage(id,level,passives,meta,arcana,character),projectile_speed(passives,arcana),area_bonus(passives,arcana,level),duration_bonus(passives,arcana),nearest(targets,px,py,Aim{(px + 180.0 : F32),py,0,10000000.0}))
# Ballistic volleys rotate through the whole pool; long-lived fields keep their slots.
def rotates_pool(id: U32) -> Bool:
  match id:
    case 3: False{}
    case 4: False{}
    case 7: False{}
    case 9: False{}
    case 19: False{}
    case 20: False{}
    case 21: False{}
    case 22: False{}
    case _: True{}
def projectile_amount(+base: U32,+level: U32,+passives: List<&2,U32>,+arcana: U32) -> U32:
  U32.min(8,(1 + at(passives,4) + level / 3 + Bool.to_u32(U32.is_eq(arcana,3)) + Bool.to_u32(U32.is_eq(base,21)) : U32))
def volley_slot(+base: U32,+slot: U32,+amount: U32,+tick: U32,+cooldown: U32) -> Bool:
  U32.is_lt(choose_id(rotates_pool(base),((slot + 8 - (tick / cooldown * amount) % 8) % 8 : U32),slot),amount)
def scheduled_shot_owned(owned: Bool,+base: U32,+slot: U32,+level: U32,+passives: List<&2,U32>,+tick: U32,+meta: U32,+arcana: U32,+character: U32) -> Bool:
  match owned:
    case False{}: False{}
    case True{}: Bool.and(volley_slot(base,slot,projectile_amount(base,level,passives,arcana),tick,cooldown_for(base,passives,meta,arcana,character)),U32.is_eq((tick % cooldown_for(base,passives,meta,arcana,character) : U32),1))
def scheduled_shot(+base: U32,+slot: U32,+level: U32,+passives: List<&2,U32>,+tick: U32,+meta: U32,+arcana: U32,+character: U32) -> Bool:
  scheduled_shot_owned(U32.is_lt(0,level),base,slot,level,passives,tick,meta,arcana,character)
# Physical slots are independent of weapon ownership and logical spread slots.
type ShotInventory is Data: ShotInventory{occupied: BI.Index<Bool>,counts: List<&2,U32>,locks: List<&2,U32>}
def empty_owner_counts() -> List<&2,U32>: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
def inventory_add(alive: Bool,+seed: U32,+owner: U32,+slot: U32,inventory: ShotInventory) -> ShotInventory:
  match alive inventory:
    case False{} inventory: inventory
    case True{} ShotInventory{occupied,+counts,+locks}: ShotInventory{BI.insert(~Bool,occupied,seed,True{}),bump(counts,owner),set_at(locks,owner,U32.or(at(locks,owner),U32.shln(1,U32.to_nat(U32.min(7,slot)))))}
def shot_inventory(rows: List<&2,Model.Snapshot>,inventory: ShotInventory) -> ShotInventory:
  match rows:
    case []: inventory
    case Model.ProjectileSnapshot{Shot.State{_,+seed,Shot.PlayerShot{},Components.ShotPayload{_,_,active},Components.Trajectory{_,_,life,pierce,_,owner,slot,+sourcePlayer}}} <> rest: shot_inventory(rest,inventory_add(Bool.and(active,Bool.and(PL.is_player_shot(seed),Bool.and(U32.is_lt(0,life),U32.is_lt(0,pierce)))),seed,owner,slot,inventory))
    case _ <> rest: shot_inventory(rest,inventory)
def free_slot(available: Bool,seed: U32,rest: List<&2,U32>) -> List<&2,U32>:
  match available:
    case True{}: seed <> rest
    case False{}: rest
def free_shot_slots(fuel: Nat,+seed: U32,+occupied: BI.Index<Bool>) -> List<&2,U32>:
  match fuel:
    case 0n: []
    case 1n+rest: free_slot(Bool.not(BI.get(~Bool,occupied,seed,False{})),seed,free_shot_slots(rest,(seed + 1 : U32),occupied))
def request_if(fire: Bool,sourcePlayer: U32,owner: U32,slot: U32,level: U32,tail: List<&2,SP.Request>) -> List<&2,SP.Request>:
  match fire:
    case False{}: tail
    case True{}: SP.Request{owner,SP.Emission{sourcePlayer,slot},level} <> tail
def requested_slot(sourcePlayer: U32,+owner: U32,+slot: U32,+level: U32,+passives: List<&2,U32>,+tick: U32,+meta: U32,+arcana: U32,+character: U32,+invuln: U32,+locks: U32,tail: List<&2,SP.Request>) -> List<&2,SP.Request>:
  request_if(Bool.and(Bool.or(rotates_pool(owner),U32.is_eq(U32.and(locks,U32.shln(1,U32.to_nat(slot))),0)),Bool.or(scheduled_shot(owner,slot,level,passives,tick,meta,arcana,character),Bool.and(U32.is_eq(arcana,4),Bool.and(U32.is_eq(owner,19),Bool.and(U32.is_eq(slot,0),Bool.and(U32.is_lt(30,invuln),U32.is_eq((tick % 12 : U32),0))))))),sourcePlayer,owner,slot,level,tail)
def shot_schedule_for(sourcePlayer: U32,run: Model.Run) -> Shot.Schedule:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,character,weapons,passives,invuln,arcana,meta,_,_,_,_,_,_}}: Shot.Schedule{tick,character,weapons,passives,invuln,arcana,meta,sourcePlayer}
def shot_schedule(run: Model.Run) -> Shot.Schedule: shot_schedule_for(0,run)
def request_slots(fuel: Nat,+owner: U32,+slot: U32,+schedule: Shot.Schedule,+locks: U32,tail: List<&2,SP.Request>) -> List<&2,SP.Request>:
  match fuel schedule:
    case 0n _: tail
    case 1n+rest Shot.Schedule{+tick,+character,+weapons,+passives,+invuln,+arcana,+meta,+sourcePlayer}: requested_slot(sourcePlayer,owner,slot,at(weapons,owner),passives,tick,meta,arcana,character,invuln,locks,request_slots(rest,owner,(slot + 1 : U32),Shot.Schedule{tick,character,weapons,passives,invuln,arcana,meta,sourcePlayer},locks,tail))
def owner_requests_needed(needed: Bool,+owner: U32,schedule: Shot.Schedule,locks: List<&2,U32>,tail: List<&2,SP.Request>) -> List<&2,SP.Request>:
  match needed:
    case False{}: tail
    case True{}: request_slots(8n,owner,0,schedule,at(locks,owner),tail)
def owner_requests(+owner: U32,+schedule: Shot.Schedule,locks: List<&2,U32>,tail: List<&2,SP.Request>) -> List<&2,SP.Request>:
  match schedule:
    case Shot.Schedule{_,_,weapons,_,_,arcana,_,_}: owner_requests_needed(Bool.or(U32.is_lt(0,at(weapons,owner)),Bool.and(U32.is_eq(arcana,4),U32.is_eq(owner,19))),owner,schedule,locks,tail)
def shot_requests(fuel: Nat,+owner: U32,+schedule: Shot.Schedule,+locks: List<&2,U32>) -> List<&2,SP.Request>:
  match fuel:
    case 0n: []
    case 1n+rest: owner_requests(owner,schedule,locks,shot_requests(rest,((owner + 1) % PL.owner_count() : U32),schedule,locks))
def shot_plan_inventory(+run: Model.Run,inventory: ShotInventory) -> SP.Plan:
  match inventory:
    case ShotInventory{occupied,counts,locks}: SP.allocate(free_shot_slots(U32.to_nat(PL.player_count()),PL.player_start(),occupied),counts,PL.caps(),shot_requests(24n,(Shot.schedule_tick(shot_schedule(run)) % PL.owner_count() : U32),shot_schedule(run),locks))
def prepare_shot_plan(args: Args) -> SP.Plan:
  match args:
    case Args{run,_,_,_,snapshots,_}: shot_plan_inventory(run,shot_inventory(snapshots,ShotInventory{BI.Empty{},empty_owner_counts(),empty_owner_counts()}))
# Resolve the complete firing predicate before preparing a projectile. Most
# unowned/unscheduled slots stay dormant and need neither aim nor materialization.
def shot_spawn_ready(fire: Bool,sourcePlayer: U32,+seed: U32,+base: U32,+slot: U32,+level: U32,args: Args) -> EntityRow:
  match fire args:
    case False{} _: ProjectileRow{Shot.Outcome{Shot.dormant(0.0,0.0,seed,Shot.PlayerShot{}),0}}
    case True{} Args{+run,targets,dx,dy,_,_}: shot_spawn_aim(base,sourcePlayer,True{},seed,effective_weapon(base,level,slot),slot,level,shot_spawn_input(effective_weapon(base,level,slot),level,run,dx,dy,targets))
def shot_step_input(run: Model.Run,aim: Aim) -> Shot.StepInput:
  match run aim:
    case Model.Run{_,RS.PlayerState{px,py,_,_,_,_,_,_,arcana,_,_,_,_,_,_,_}} Aim{tx,ty,_,_}: Shot.StepInput{px,py,tx,ty,U32.is_eq(arcana,8)}
def shot_step_aim(+projectile: Shot.State,args: Args,aim: Aim) -> EntityRow:
  match args:
    case Args{run,_,_,_,_,hits}: ProjectileRow{Shot.step(projectile,shot_step_input(run,aim),hit_targets(hits,Shot.identity(projectile)))}
def nearest_from_args(args: Args,+x: F32,+y: F32) -> Aim:
  match args:
    case Args{_,targets,_,_,+snapshots,+hits}: nearest(targets,x,y,Aim{(x + 180.0 : F32),y,0,10000000.0})
type Collision is Data: Collision{damage: U32,slow: Effect.Slow,burn: U32,pull: U32,knock: U32,pullX: F32,pullY: F32}
def collision_add(hit: Bool,+id: U32,+damage: U32,+cx: F32,+cy: F32,tail: Collision) -> Collision:
  match hit tail:
    case False{} tail: tail
    case True{} Collision{+d,+s,+b,+p,+k,+sumX,+sumY}: Collision{(d + damage : U32),Effect.stronger_slow(s,Effect.slow_from_status(P.status(id))),U32.max(b,(120 * Bool.to_u32(U32.is_eq(P.status(id),3)) : U32)),(p + Bool.to_u32(U32.is_eq(P.status(id),4)) : U32),(k + Bool.to_u32(U32.is_eq(P.status(id),5)) : U32),(sumX + cx * U32.to_f32(Bool.to_u32(U32.is_eq(P.status(id),4))) : F32),(sumY + cy * U32.to_f32(Bool.to_u32(U32.is_eq(P.status(id),4))) : F32)}
def hit_recipient(area: Bool,+targets: List<&2,U32>,+target: U32,+x: F32,+y: F32,+radius: F32,+tx: F32,+ty: F32,+r: F32) -> Bool:
  match area:
    case True{}: close(x,y,tx,ty,(radius + r : F32))
    case False{}: contains(targets,target)
def collisions(rows: List<&2,HitPlan>,+x: F32,+y: F32,+radius: F32,+target: U32) -> Collision:
  match rows:
    case []: Collision{0,Effect.empty_slow(),0,0,0,0.0,0.0}
    case HitPlan{_,+id,+damage,+tx,+ty,+r,+area,+targets} <> rest: collision_add(hit_recipient(area,targets,target,x,y,radius,tx,ty,r),id,damage,tx,ty,collisions(rest,x,y,radius,target))
def pull_x(+x: F32,+y: F32,+sumX: F32,+sumY: F32,+count: U32) -> F32:
  ((sumX / U32.to_f32(U32.max(1,count)) - x) / F32.max(1.0,F32.sqrt(distance2(x,y,(sumX / U32.to_f32(U32.max(1,count)) : F32),(sumY / U32.to_f32(U32.max(1,count)) : F32)))) : F32)
def pull_y(+x: F32,+y: F32,+sumX: F32,+sumY: F32,+count: U32) -> F32:
  ((sumY / U32.to_f32(U32.max(1,count)) - y) / F32.max(1.0,F32.sqrt(distance2(x,y,(sumX / U32.to_f32(U32.max(1,count)) : F32),(sumY / U32.to_f32(U32.max(1,count)) : F32)))) : F32)
# Dawn's pursuer takes damage but cannot be frozen, slowed or displaced.
def immune_collision(immune: Bool,collision: Collision) -> Collision:
  match immune collision:
    case True{} Collision{damage,_,burn,_,_,_,_}: Collision{damage,Effect.empty_slow(),burn,0,0,0.0,0.0}
    case False{} collision: collision
def intent_fire(intent: E.Intent) -> Bool:
  match intent:
    case E.Intent{_,_,fire}: fire
def nearest_shooter_targets(rows: List<&2,Targets.Shooter>,+x: F32,+y: F32,+best: Aim) -> Aim:
  match rows:
    case []: best
    case Targets.Shooter{Targets.Target{+tx,+ty,seed},variant,age} <> rest: nearest_shooter_targets(rest,x,y,prefer_aim(Bool.and(intent_fire(E.intent(variant,age,tx,ty,x,y)),F32.is_lt(distance2(x,y,tx,ty),aim_distance(best))),tx,ty,seed,distance2(x,y,tx,ty),best))
def nearest_shooter(targets: Targets.Targets,x: F32,y: F32,best: Aim) -> Aim:
  match targets:
    case Targets.Targets{_,shooters}: nearest_shooter_targets(shooters,x,y,best)
def hostile_created(fire: Bool,+seed: U32,+px: F32,+py: F32,aim: Aim) -> EntityRow:
  match fire aim:
    case True{} Aim{x,y,_,_}: ProjectileRow{Shot.Outcome{Shot.hostile_spawn(seed,x,y,px,py),0}}
    case False{} _: ProjectileRow{Shot.Outcome{Shot.dormant(0.0,0.0,seed,Shot.HostileShot{}),0}}
def hostile_spawn(+seed: U32,args: Args) -> EntityRow:
  match args:
    case Args{Model.Run{RS.Session{_,+tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{+px,+py,_,_,_,_,_,_,_,_,_,_,_,_,_,_}},+targets,_,_,_,_}: hostile_created(Bool.and(U32.is_lt((seed - PL.hostile_start() : U32),U32.min(PL.hostile_count(),(2 + tick / 1800 : U32))),Bool.and(U32.is_eq((tick % 12 : U32),((seed - PL.hostile_start()) % 12 : U32)),F32.is_lt(aim_distance(nearest_shooter(targets,px,py,Aim{0.0,0.0,0,10000000.0})),10000000.0))),seed,px,py,nearest_shooter(targets,px,py,Aim{0.0,0.0,0,10000000.0}))
def hostile_advance(alive: Bool,+projectile: Shot.State,args: Args) -> EntityRow:
  match alive args:
    case False{} args: hostile_spawn(Shot.identity(projectile),args)
    case True{} Args{Model.Run{_,RS.PlayerState{px,py,_,_,_,_,_,_,_,_,_,_,_,_,_,_}},_,_,_,_,_}: ProjectileRow{Shot.hostile_step(projectile,px,py)}
def hostile_step(+projectile: Shot.State,args: Args) -> EntityRow: hostile_advance(Shot.hostile_active(projectile),projectile,args)
# Each pass has an independently checked access contract. Read capabilities cannot write.
def missing_row() -> EntityRow: NoEntityRow{}
def Frame() -> Type: Q.Frame<Storage.Schema,Storage.Store,Unit,Unit>
def candidate_frame_identity(frame: Frame()) -> Frame(): frame
def selected_role(mode: U32,role: Role.Role) -> Bool:
  match mode:
    case 0: Role.projectile(role)
    case 1: Role.enemy(role)
    case 2: Role.pool(role)
    case _: False{}
def selected_role_observed(mode: U32,result: Frame() & C.Access<Role.Role>) -> Frame() & Bool:
  match result:
    case (frame,C.Found{role}): (frame,selected_role(mode,role))
    case (frame,_): (frame,False{})
def selected_enemy_phase(result: Frame() & C.Access<Enemy.Phase>) -> Frame() & Bool:
  match result:
    case (frame,C.Found{phase}): (frame,Enemy.active(phase))
    case (frame,_): (frame,False{})
def selected_enemy_admitted(result: Frame() & Bool) -> Frame() & Bool:
  match result:
    case (frame,True{}): selected_enemy_phase(Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~Storage.phase_family(),frame))
    case (frame,False{}): (frame,False{})
def selected_projectile(frame: Frame()) -> Frame() & Bool: selected_role_observed(0,Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,~Storage.role_family(),frame))
def selected_enemy(frame: Frame()) -> Frame() & Bool: selected_enemy_admitted(selected_role_observed(1,Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,~Storage.role_family(),frame)))
def selected_pool(frame: Frame()) -> Frame() & Bool: selected_role_observed(2,Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,~Storage.role_family(),frame))

# Projectile updates own geometry and trajectory, with no health/status grant.
def projectile_write(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~payloadRead: H -> H & C.Access<Components.ShotPayload>,~payloadReplace: H -> Components.ShotPayload -> H,~trajectoryRead: H -> H & C.Access<Components.Trajectory>,~trajectoryReplace: H -> Components.Trajectory -> H,~identityRead: H -> H & C.Access<Components.Identity>,~roleRead: H -> H & C.Access<Role.Role>,ctx: H,row: EntityRow) -> H & (T.Outcome<Error> & EntityRow):
  match row:
    case ProjectileRow{Shot.Outcome{Shot.State{+space,+identity,+side,+payload,+trajectory},+contact}}: (trajectoryReplace(payloadReplace(spatialReplace(ctx,space),payload),trajectory),(T.Success{},ProjectileRow{Shot.Outcome{Shot.State{space,identity,side,payload,trajectory},contact}}))
    case _: (ctx,(T.Failure{MissingComponent{}},missing_row()))

# Movement writes only spatial state, including the once-per-step age increment.
# Enemy kind/variant metadata and slow status are read-only.

def movement_roster_read_fields(store: Storage.StoreFields) -> Storage.Store & Storage.MovementRoster:
  match store:
    case Storage.StoreFields{vitals,motions,statuses,pickups,roles,+movement,candidates,players,spaces,enemyPhases,identities,shots}: (Storage.Owned{Storage.StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}},movement)
def movement_roster_read(store: Storage.Store) -> Storage.Store & Storage.MovementRoster: movement_roster_read_fields(Storage.unseal(store))
type PickupCall is Data: PickupCall{team: Team,advance: Bool,relic: Bool} XpPoolCall{team: Team}
# Lifecycle dispatch keeps enemy geometry and XP payload grants separate while
# executing both callbacks in the original enclosing transaction and row order.
def loot_active_handle(~H: Type,result: H & W.Handle<Storage.Schema>) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match result:
    case (ctx,handle): (ctx,(T.Success{},Some{handle}))
def loot_written(~H: Type,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~handleRead: H -> H & W.Handle<Storage.Schema>,~identityRead: H -> H & C.Access<Components.Identity>,active: Bool,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match active:
    case False{}: (ctx,(T.Success{},None{}))
    case True{}: loot_active_handle(~H,handleRead(ctx))
def loot_occupancy(active: Bool,archetype: U32) -> Enemy.Phase:
  match active:
    case True{}: Enemy.OccupiedByLoot{archetype}
    case False{}: Enemy.Dormant{archetype}
def pickup_payload_active(payload: Pickup.Payload) -> Bool:
  match payload:
    case Pickup.Payload{_,_,active}: active
def enemy_lifecycle_planned(~H: Type,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~handleRead: H -> H & W.Handle<Storage.Schema>,~identityRead: H -> H & C.Access<Components.Identity>,phase: Enemy.Phase,planned: Maybe<&2,Pickup.State>,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match planned:
    case None{}: loot_written(~H,~phaseRead,~phaseReplace,~spatialRead,~spatialReplace,~pickupRead,~pickupReplace,~handleRead,~identityRead,Enemy.active(phase),ctx)
    case Some{Pickup.State{spatial,+payload,_}}: (phaseReplace(pickupReplace(spatialReplace(ctx,spatial),payload),loot_occupancy(pickup_payload_active(payload),Enemy.archetype(phase))),(T.Success{},None{}))
def enemy_lifecycle_phase(~H: Type,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~handleRead: H -> H & W.Handle<Storage.Schema>,~identityRead: H -> H & C.Access<Components.Identity>,planned: Maybe<&2,Pickup.State>,result: H & C.Access<Enemy.Phase>) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match result:
    case (ctx,C.Found{phase}): enemy_lifecycle_planned(~H,~phaseRead,~phaseReplace,~spatialRead,~spatialReplace,~pickupRead,~pickupReplace,~handleRead,~identityRead,phase,planned,ctx)
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},None{}))
def enemy_lifecycle_identified(~H: Type,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~handleRead: H -> H & W.Handle<Storage.Schema>,~identityRead: H -> H & C.Access<Components.Identity>,index: BI.Index<Pickup.State>,result: H & C.Access<Components.Identity>) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match result:
    case (ctx,C.Found{Components.Identity{identity}}): enemy_lifecycle_phase(~H,~phaseRead,~phaseReplace,~spatialRead,~spatialReplace,~pickupRead,~pickupReplace,~handleRead,~identityRead,BI.find(~Pickup.State,index,identity),phaseRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},None{}))
def enemy_lifecycle(~H: Type,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~handleRead: H -> H & W.Handle<Storage.Schema>,~identityRead: H -> H & C.Access<Components.Identity>,index: BI.Index<Pickup.State>,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>): enemy_lifecycle_identified(~H,~phaseRead,~phaseReplace,~spatialRead,~spatialReplace,~pickupRead,~pickupReplace,~handleRead,~identityRead,index,identityRead(ctx))
def pickup_lifecycle_write(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~identityRead: H -> H & C.Access<Components.Identity>,planned: Maybe<&2,Pickup.State>,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match planned:
    case None{}: (ctx,(T.Success{},None{}))
    case Some{Pickup.State{space,payload,_}}: (pickupReplace(spatialReplace(ctx,space),payload),(T.Success{},None{}))
def pickup_lifecycle_identified(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~identityRead: H -> H & C.Access<Components.Identity>,index: BI.Index<Pickup.State>,result: H & C.Access<Components.Identity>) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match result:
    case (ctx,C.Found{Components.Identity{identity}}): pickup_lifecycle_write(~H,~spatialRead,~spatialReplace,~pickupRead,~pickupReplace,~identityRead,BI.find(~Pickup.State,index,identity),ctx)
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},None{}))
def pickup_lifecycle(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~pickupRead: H -> H & C.Access<Pickup.Payload>,~pickupReplace: H -> Pickup.Payload -> H,~identityRead: H -> H & C.Access<Components.Identity>,index: BI.Index<Pickup.State>,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>): pickup_lifecycle_identified(~H,~spatialRead,~spatialReplace,~pickupRead,~pickupReplace,~identityRead,index,identityRead(ctx))
def loot_dispatch(~H: Type,~roleRead: H -> H & C.Access<Role.Role>,~enemyPhaseRead: H -> H & C.Access<Enemy.Phase>,~enemyPhaseReplace: H -> Enemy.Phase -> H,~enemySpatialRead: H -> H & C.Access<Space.Spatial>,~enemySpatialReplace: H -> Space.Spatial -> H,~enemyPickupRead: H -> H & C.Access<Pickup.Payload>,~enemyPickupReplace: H -> Pickup.Payload -> H,~enemyHandleRead: H -> H & W.Handle<Storage.Schema>,~enemyIdentityRead: H -> H & C.Access<Components.Identity>,~pickupSpatialRead: H -> H & C.Access<Space.Spatial>,~pickupSpatialReplace: H -> Space.Spatial -> H,~pickupPickupRead: H -> H & C.Access<Pickup.Payload>,~pickupPickupReplace: H -> Pickup.Payload -> H,~pickupIdentityRead: H -> H & C.Access<Components.Identity>,role: Role.Role,index: BI.Index<Pickup.State>,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match role:
    case Role.XpSlot{}: pickup_lifecycle(~H,~pickupSpatialRead,~pickupSpatialReplace,~pickupPickupRead,~pickupPickupReplace,~pickupIdentityRead,index,ctx)
    case _: enemy_lifecycle(~H,~enemyPhaseRead,~enemyPhaseReplace,~enemySpatialRead,~enemySpatialReplace,~enemyPickupRead,~enemyPickupReplace,~enemyHandleRead,~enemyIdentityRead,index,ctx)
def loot_role_observed(~H: Type,~roleRead: H -> H & C.Access<Role.Role>,~enemyPhaseRead: H -> H & C.Access<Enemy.Phase>,~enemyPhaseReplace: H -> Enemy.Phase -> H,~enemySpatialRead: H -> H & C.Access<Space.Spatial>,~enemySpatialReplace: H -> Space.Spatial -> H,~enemyPickupRead: H -> H & C.Access<Pickup.Payload>,~enemyPickupReplace: H -> Pickup.Payload -> H,~enemyHandleRead: H -> H & W.Handle<Storage.Schema>,~enemyIdentityRead: H -> H & C.Access<Components.Identity>,~pickupSpatialRead: H -> H & C.Access<Space.Spatial>,~pickupSpatialReplace: H -> Space.Spatial -> H,~pickupPickupRead: H -> H & C.Access<Pickup.Payload>,~pickupPickupReplace: H -> Pickup.Payload -> H,~pickupIdentityRead: H -> H & C.Access<Components.Identity>,index: BI.Index<Pickup.State>,result: H & C.Access<Role.Role>) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  match result:
    case (ctx,C.Found{role}): loot_dispatch(~H,~roleRead,~enemyPhaseRead,~enemyPhaseReplace,~enemySpatialRead,~enemySpatialReplace,~enemyPickupRead,~enemyPickupReplace,~enemyHandleRead,~enemyIdentityRead,~pickupSpatialRead,~pickupSpatialReplace,~pickupPickupRead,~pickupPickupReplace,~pickupIdentityRead,role,index,ctx)
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},None{}))
def loot_system(~H: Type,~roleRead: H -> H & C.Access<Role.Role>,~enemyPhaseRead: H -> H & C.Access<Enemy.Phase>,~enemyPhaseReplace: H -> Enemy.Phase -> H,~enemySpatialRead: H -> H & C.Access<Space.Spatial>,~enemySpatialReplace: H -> Space.Spatial -> H,~enemyPickupRead: H -> H & C.Access<Pickup.Payload>,~enemyPickupReplace: H -> Pickup.Payload -> H,~enemyHandleRead: H -> H & W.Handle<Storage.Schema>,~enemyIdentityRead: H -> H & C.Access<Components.Identity>,~pickupSpatialRead: H -> H & C.Access<Space.Spatial>,~pickupSpatialReplace: H -> Space.Spatial -> H,~pickupPickupRead: H -> H & C.Access<Pickup.Payload>,~pickupPickupReplace: H -> Pickup.Payload -> H,~pickupIdentityRead: H -> H & C.Access<Components.Identity>,index: BI.Index<Pickup.State>,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>): loot_role_observed(~H,~roleRead,~enemyPhaseRead,~enemyPhaseReplace,~enemySpatialRead,~enemySpatialReplace,~enemyPickupRead,~enemyPickupReplace,~enemyHandleRead,~enemyIdentityRead,~pickupSpatialRead,~pickupSpatialReplace,~pickupPickupRead,~pickupPickupReplace,~pickupIdentityRead,index,roleRead(ctx))

def LootProgramOps(H: Type) -> Type: BI.Index<Pickup.State> -> H -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>)
def loot_program_dispatch(~H: Type,~run: LootProgramOps(H),args: BI.Index<Pickup.State>,ctx: H) -> H & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>): run(args,ctx)
def loot_caps(index: BI.Index<Pickup.State>,ctx: Frame()) -> Frame() & (T.Outcome<Error> & Maybe<&2,W.Handle<Storage.Schema>>):
  loot_system(~Frame(),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,~Storage.role_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~Storage.phase_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~Storage.phase_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PickupRest,~Pickup.Payload,~Pickup.Payload,~Storage.PickupToken,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,~Storage.pickup_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PickupRest,~Pickup.Payload,~Pickup.Payload,~Storage.PickupToken,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,~Storage.pickup_family()),~Q.handle_get(~Storage.Schema,~Storage.Store,~Unit,~Unit),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.IdentityRest,~Components.Identity,~Components.Identity,~Storage.IdentityToken,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,~Storage.identity_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PickupRest,~Pickup.Payload,~Pickup.Payload,~Storage.PickupToken,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,~Storage.pickup_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PickupRest,~Pickup.Payload,~Pickup.Payload,~Storage.PickupToken,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,~Storage.pickup_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.IdentityRest,~Components.Identity,~Components.Identity,~Storage.IdentityToken,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,~Storage.identity_family()),index,ctx)
def loot_plan() -> Q.Plan<Storage.Schema,Storage.Store,Unit,Unit,LootProgramOps>:
  Q.Plan{loot_caps,selected_pool}
def movement_roster_outputs(rows: List<&2,Maybe<&2,W.Handle<Storage.Schema>>>) -> List<&2,W.Handle<Storage.Schema>>:
  MM.outputs(~W.Handle<Storage.Schema>,rows)
# Publish membership only after the typed spatial transaction succeeds. Failed traversal
# retains the old components and roster; no partial output becomes a roster.
def lifecycle_done(+rows: List<&2,EntityRow>,result: Q.Executed<Storage.World(),Q.Error<Error>,Maybe<&2,W.Handle<Storage.Schema>>>) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>:
  match result:
    case Q.Executed{world,T.Success{},handles}: Q.Executed{movement_roster_save(world,movement_roster_outputs(handles)),T.Success{},rows}
    case Q.Executed{world,T.Failure{error},_}: Q.Executed{world,T.Failure{error},[]}
# Batch XP routing: preserve exact drops while free, then one stable accumulator.
# Existing accumulator identity/coordinates/generation survive every merge.
def xp_pool_states(rows: List<&2,EntityRow>) -> List<&2,Pickup.State>:
  match rows:
    case []: []
    case PickupRow{Pickup.Outcome{+state,_}} <> rest: List.filter.put(Pickup.State,state,xp_pool_states(rest),PL.is_xp(Pickup.slot(state)))
    case _ <> rest: xp_pool_states(rest)
def xp_death_drop(outcome: Enemy.Outcome,rest: List<&2,PickupPool.Drop>) -> List<&2,PickupPool.Drop>:
  match outcome:
    case Enemy.Killed{_,Enemy.DeathReward{Enemy.XpDrop{},amount,x,y,_,_,_}}: PickupPool.Drop{amount,x,y} <> rest
    case _: rest
def xp_death_drops(rows: List<&2,EntityRow>) -> List<&2,PickupPool.Drop>:
  match rows:
    case []: []
    case EnemyRow{outcome,_} <> rest: xp_death_drop(outcome,xp_death_drops(rest))
    case _ <> rest: xp_death_drops(rest)
def xp_nonpool_row(+row: EntityRow,rest: List<&2,EntityRow>) -> List<&2,EntityRow>:
  match row:
    case PickupRow{Pickup.Outcome{state,_}}: List.filter.put(EntityRow,row,rest,Bool.not(PL.is_xp(Pickup.slot(state))))
    case row: row <> rest
def xp_nonpool_rows(rows: List<&2,EntityRow>) -> List<&2,EntityRow>:
  match rows:
    case []: []
    case +row <> rest: xp_nonpool_row(row,xp_nonpool_rows(rest))
def xp_routed_pickup(next: List<&2,Pickup.State> -> List<&2,EntityRow>,pool: Bool,reward: Pickup.Reward,states: List<&2,Pickup.State>) -> List<&2,EntityRow>:
  match pool states:
    case True{} state <> rest: PickupRow{Pickup.Outcome{state,reward}} <> next(rest)
    case _ states: next(states)
def xp_routed_rows(rows: List<&2,EntityRow>,states: List<&2,Pickup.State>) -> List<&2,EntityRow>:
  match rows states:
    case [] _: []
    case PickupRow{Pickup.Outcome{+old,reward}} <> rest states: xp_routed_pickup(xp_routed_rows(rest),PL.is_xp(Pickup.slot(old)),reward,states)
    case _ <> rest states: xp_routed_rows(rest,states)
def pickup_created(planned: Maybe<&2,Pickup.State>,tail: List<&2,EntityRow>) -> List<&2,EntityRow>:
  match planned:
    case None{}: tail
    case Some{state}: PickupRow{Pickup.Outcome{state,Pickup.no_reward()}} <> tail
def pickup_death_outcome(outcome: Enemy.Outcome,generation: U32,tail: List<&2,EntityRow>) -> List<&2,EntityRow>:
  match outcome:
    case Enemy.Killed{_,reward}: pickup_created(PickupDeath.create(reward,generation),tail)
    case _: tail
def pickup_death_rows(rows: List<&2,EntityRow>,+generation: U32) -> List<&2,EntityRow>:
  match rows:
    case []: []
    case EnemyRow{+outcome,credit} <> rest: EnemyRow{outcome,credit} <> pickup_death_outcome(outcome,generation,pickup_death_rows(rest,generation))
    case row <> rest: row <> pickup_death_rows(rest,generation)
def xp_route_rows_at(+rows: List<&2,EntityRow>,+tick: U32,px: F32,py: F32) -> List<&2,EntityRow>:
  List.append(&2,EntityRow,pickup_death_rows(xp_nonpool_rows(rows),tick),xp_routed_rows(rows,PickupPool.route(xp_death_drops(rows),xp_pool_states(rows),tick,px,py)))
def xp_route_args(rows: List<&2,EntityRow>,args: Args) -> List<&2,EntityRow>:
  match args:
    case Args{Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{px,py,_,_,_,_,_,_,_,_,_,_,_,_,_,_}},_,_,_,_,_}: xp_route_rows_at(rows,tick,px,py)

# The trusted schema adapter narrows only enumeration; capabilities, selector,
# transaction finish, rollback and mixed allocator order remain the public query's.
def candidate_roster_read_fields(store: Storage.StoreFields) -> Storage.Store & Storage.CandidateRoster:
  match store:
    case Storage.StoreFields{vitals,motions,statuses,pickups,roles,movement,+candidates,players,spaces,enemyPhases,identities,shots}: (Storage.Owned{Storage.StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}},candidates)
def candidate_roster_read(store: Storage.Store) -> Storage.Store & Storage.CandidateRoster: candidate_roster_read_fields(Storage.unseal(store))
def candidate_roster_handles(projectile: Bool,roster: Storage.CandidateRoster) -> List<&2,W.Handle<Storage.Schema>>:
  match projectile roster:
    case True{} Storage.CandidatesPrepared{projectiles,_}: projectiles
    case False{} Storage.CandidatesPrepared{_,pool}: pool
def candidate_query_ready(~Ops: Type -> Type,~A: Data,~Out: Data,~caps: Ops(Frame()),~select: Frame() -> Frame() & Bool,~body: @-H: Type -> @-caps: Ops(H) -> A -> H -> H & (T.Outcome<Error> & Out),args: A,world: Storage.World(),handles: List<&2,W.Handle<Storage.Schema>>) -> Q.Executed<Storage.World(),Q.Error<Error>,Out>:
  OwnedQ.reserved_fields(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Ops,~Frame(),~A,~Error,~Out,~caps,~select,~candidate_frame_identity,~candidate_frame_identity,~body,args,None{},(world,handles))
def candidate_query_opened(~Ops: Type -> Type,~A: Data,~Out: Data,~caps: Ops(Frame()),~select: Frame() -> Frame() & Bool,~body: @-H: Type -> @-caps: Ops(H) -> A -> H -> H & (T.Outcome<Error> & Out),projectile: Bool,args: A,result: Storage.World() & Storage.CandidateRoster) -> Q.Executed<Storage.World(),Q.Error<Error>,Out>:
  match result:
    case (world,roster): candidate_query_ready(~Ops,~A,~Out,~caps,~select,~body,args,world,candidate_roster_handles(projectile,roster))
def candidate_query(~Ops: Type -> Type,~A: Data,~Out: Data,~caps: Ops(Frame()),~select: Frame() -> Frame() & Bool,~body: @-H: Type -> @-caps: Ops(H) -> A -> H -> H & (T.Outcome<Error> & Out),projectile: Bool,args: A,world: Storage.World()) -> Q.Executed<Storage.World(),Q.Error<Error>,Out>:
  candidate_query_opened(~Ops,~A,~Out,~caps,~select,~body,projectile,args,W.with_store(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.CandidateRoster,candidate_roster_read,world))

def pickup_index(rows: List<&2,EntityRow>,index: BI.Index<Pickup.State>) -> BI.Index<Pickup.State>:
  match rows:
    case []: index
    case PickupRow{Pickup.Outcome{+state,_}} <> rest: pickup_index(rest,BI.insert(~Pickup.State,index,Pickup.slot(state),state))
    case _ <> rest: pickup_index(rest,index)
def xp_lifecycle(+projectiles: List<&2,EntityRow>,+rows: List<&2,EntityRow>,world: Storage.World()) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>:
  lifecycle_done(List.append(&2,EntityRow,projectiles,rows),candidate_query(~LootProgramOps,~BI.Index<Pickup.State>,~Maybe<&2,W.Handle<Storage.Schema>>,~loot_caps,~selected_pool,~loot_program_dispatch,False{},pickup_index(rows,BI.Empty{}),world))
def owned(rows: List<&2,U32>) -> U32:
  match rows:
    case []: 0
    case n <> rest: (Bool.to_u32(U32.is_lt(0,n)) + owned(rest) : U32)
def offer_candidate(allowed: Bool,+kind: U32,+id: U32,+level: U32) -> Model.Offer:
  match allowed:
    case True{}: Model.Offer{kind,id,(level + 1 : U32)}
    case False{}: Model.Offer{2,0,1}
def offer_for(+roll: U32,+weapons: List<&2,U32>,+passives: List<&2,U32>) -> Model.Offer:
  match roll:
    case +roll: offer_candidate(Bool.and(U32.is_lt(at(weapons,(roll % 24 : U32)),8),Bool.or(U32.is_lt(0,at(weapons,(roll % 24 : U32))),U32.is_lt(owned(weapons),6))),0,(roll % 24 : U32),at(weapons,(roll % 24 : U32)))
def passive_offer(+id: U32,+passives: List<&2,U32>) -> Model.Offer:
  offer_candidate(Bool.and(U32.is_lt(at(passives,id),5),Bool.or(U32.is_lt(0,at(passives,id)),U32.is_lt(owned(passives),6))),1,id,at(passives,id))
def prefer_offer(valid: Bool,candidate: Model.Offer,fallback: Model.Offer) -> Model.Offer:
  match valid:
    case True{}: candidate
    case False{}: fallback
def equipped_offer(weapons: List<&2,U32>,+index: U32) -> Model.Offer:
  match weapons:
    case []: Model.Offer{2,0,1}
    case +level <> rest: prefer_offer(Bool.and(U32.is_lt(0,level),U32.is_lt(level,8)),Model.Offer{0,index,(level + 1 : U32)},equipped_offer(rest,(index + 1 : U32)))
def evolution_passive(+id: U32) -> U32: at([1,12,2,4,11,4,0,3,10,3,1,9,7,12,2,0,4,2,3,6,8,10,3,12],id)
def evolution_offer(weapons: List<&2,U32>,+index: U32,+passives: List<&2,U32>) -> Model.Offer:
  match weapons:
    case []: Model.Offer{4,0,50}
    case +level <> rest: prefer_offer(Bool.and(U32.is_eq(level,8),U32.is_lt(0,at(passives,evolution_passive(index)))),Model.Offer{3,index,9},evolution_offer(rest,(index + 1 : U32),passives))
def make_offers(+seed: U32,+weapons: List<&2,U32>,+passives: List<&2,U32>) -> List<&2,Model.Offer>:
  [equipped_offer(weapons,0),passive_offer(((seed * 7 + 3) % 18 : U32),passives),offer_for((seed % 24 : U32),weapons,passives)]
def union_offer(remaining: Nat,+id: U32,+weapons: List<&2,U32>,+fallback: Model.Offer) -> Model.Offer:
  match remaining:
    case 0n: fallback
    case 1n+rest: prefer_offer(Bool.and(Bool.and(U32.is_le(8,at(weapons,union_base(id))),U32.is_le(at(weapons,union_base(id)),9)),Bool.and(U32.is_le(8,at(weapons,union_partner(id))),U32.is_le(at(weapons,union_partner(id)),9))),Model.Offer{5,id,(10 + id : U32)},union_offer(rest,(id + 1 : U32),weapons,fallback))
def chest_offers(+seed: U32,+weapons: List<&2,U32>,+passives: List<&2,U32>) -> List<&2,Model.Offer>:
  [union_offer(6n,0,weapons,evolution_offer(weapons,0,passives)),evolution_offer(weapons,0,passives),Model.Offer{4,0,50}]
def phase_offers(chest: Bool,+seed: U32,+weapons: List<&2,U32>,+passives: List<&2,U32>) -> List<&2,Model.Offer>:
  match chest:
    case True{}: chest_offers(seed,weapons,passives)
    case False{}: make_offers(seed,weapons,passives)
def banned(+mask: U32,+id: U32) -> Bool: U32.is_lt(0,U32.and(mask,U32.shln(1,U32.to_nat(id))))
def filter_offer(offer: Model.Offer,+bannedWeapons: U32,+bannedPassives: U32) -> Model.Offer:
  match offer:
    case Model.Offer{0,+id,+level}: prefer_offer(Bool.not(banned(bannedWeapons,id)),Model.Offer{0,id,level},Model.Offer{2,0,1})
    case Model.Offer{1,+id,+level}: prefer_offer(Bool.not(banned(bannedPassives,id)),Model.Offer{1,id,level},Model.Offer{2,0,1})
    case offer: offer
def filter_offers(offers: List<&2,Model.Offer>,+bannedWeapons: U32,+bannedPassives: U32) -> List<&2,Model.Offer>:
  match offers:
    case []: []
    case offer <> rest: filter_offer(offer,bannedWeapons,bannedPassives) <> filter_offers(rest,bannedWeapons,bannedPassives)
def evolve_weapon(weapons: List<&2,U32>,+id: U32) -> List<&2,U32>:
  match weapons id:
    case Nil{} _: []
    case Con{+level,rest} 0: U32.min(9,(level + Bool.to_u32(U32.is_eq(level,8)) : U32)) <> rest
    case Con{level,rest} +id: level <> evolve_weapon(rest,(id - 1 : U32))
def upgrade(offer: Model.Offer,run: Model.Run) -> Model.Run:
  match offer run:
    case Model.Offer{0,+id,_} Model.Run{RS.Session{+phase,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,bump(weapons,id),passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
    case Model.Offer{5,+id,_} Model.Run{RS.Session{_,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{0,tick,xp,need,level,kills,(gold + 50 : U32),seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,U32.min(maxHp,(hp + 30 : U32)),maxHp,character,set_at(set_at(weapons,union_partner(id),0),union_base(id),(10 + id : U32)),passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
    case Model.Offer{3,+id,_} Model.Run{RS.Session{_,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{0,tick,xp,need,level,kills,(gold + 25 : U32),seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,U32.min(maxHp,(hp + 20 : U32)),maxHp,character,evolve_weapon(weapons,id),passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
    case Model.Offer{4,_,+amount} Model.Run{RS.Session{_,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{0,tick,xp,need,level,kills,(gold + amount : U32),seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
    case Model.Offer{1,+id,_} Model.Run{RS.Session{_,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,U32.min((maxHp + maxHp * 20 / (100 + at(passives,7) * 20) * Bool.to_u32(U32.is_eq(id,7)) : U32),(hp + maxHp * 20 / (100 + at(passives,7) * 20) * Bool.to_u32(U32.is_eq(id,7)) : U32)),(maxHp + maxHp * 20 / (100 + at(passives,7) * 20) * Bool.to_u32(U32.is_eq(id,7)) : U32),character,weapons,bump(passives,id),invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
    case Model.Offer{_,_,_} Model.Run{RS.Session{_,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,U32.min(maxHp,(hp + 30 : U32)),maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def offer_at(offers: List<&2,Model.Offer>,index: U32) -> Model.Offer:
  match offers index:
    case Nil{} _: Model.Offer{2,0,1}
    case Con{offer,_} 0: offer
    case Con{_,rest} index: offer_at(rest,(index - 1 : U32))
def choose_unchecked(state: State,+choice: U32) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{0,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},offers,snapshots,pending})
    case State{world,run,+offers,+snapshots,pending}: packet(State{world,upgrade(offer_at(offers,U32.min(choice,2)),run),[],snapshots,pending})
def choose_raw(state: State,+choice: U32) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{3,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{3,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},offers,snapshots,pending})
    case State{world,Model.Run{RS.Session{4,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{4,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},offers,snapshots,pending})
    case state: choose_unchecked(state,choice)
type Totals is Data: Totals{hit: U32,xp: U32,gold: U32,heal: U32,chest: U32,kills: U32,snapshots: List<&2,Model.Snapshot>,relic: U32}
def enemy_snapshot(outcome: Enemy.Outcome,tail: List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match outcome:
    case Enemy.Alive{enemy,_}: Model.EnemySnapshot{enemy} <> tail
    case Enemy.Born{newborn}: Model.EnemySnapshot{Enemy.newborn_state(newborn)} <> tail
    case _: tail
def accumulate(rows: List<&2,EntityRow>,+hit: U32,+xp: U32,+gold: U32,+heal: U32,+chest: U32,+kills: U32,+snapshots: List<&2,Model.Snapshot>,+relicTotal: U32) -> Totals:
  match rows:
    case NoEntityRow{} <> rest: accumulate(rest,hit,xp,gold,heal,chest,kills,snapshots,relicTotal)
    case []: Totals{hit,xp,gold,heal,chest,kills,snapshots,relicTotal}
    case PickupRow{Pickup.Outcome{state,Pickup.Reward{x,g,he,c,r}}} <> rest: accumulate(rest,hit,(xp + x : U32),(gold + g : U32),(heal + he : U32),(chest + c : U32),kills,Model.PickupSnapshot{state} <> snapshots,(relicTotal + r : U32))
    case ProjectileRow{Shot.Outcome{+projectile,h}} <> rest: accumulate(rest,(hit + h : U32),xp,gold,heal,chest,kills,Model.ProjectileSnapshot{projectile} <> snapshots,relicTotal)
    case EnemyRow{outcome,Enemy.Credit{h,k}} <> rest: accumulate(rest,(hit + h : U32),xp,gold,heal,chest,(kills + k : U32),enemy_snapshot(outcome,snapshots),relicTotal)
def phase_for(dead: Bool,won: Bool,chest: Bool,levelup: Bool) -> U32:
  match dead won chest levelup:
    case True{} _ _ _: 3
    case _ True{} _ _: 4
    case _ _ True{} _: 2
    case _ _ _ True{}: 1
    case _ _ _ _: 0
def enemy_archetype(enemy: Enemy.State) -> U32:
  match enemy:
    case Enemy.State{_,archetype,_,_,_}: archetype
def boss_kills(rows: List<&2,EntityRow>) -> U32:
  match rows:
    case []: 0
    case PickupRow{_} <> rest: boss_kills(rest)
    case EnemyRow{outcome,Enemy.Credit{_,k}} <> rest: (k * Bool.to_u32(U32.is_le(20,enemy_archetype(Enemy.state(outcome)))) + boss_kills(rest) : U32)
    case _ <> rest: boss_kills(rest)
def earned_xp(+earned: U32,+passives: List<&2,U32>,+meta: U32,+arcana: U32) -> U32: (earned * (100 + at(passives,9) * 10 + at(passives,14) * 10 + meta_rank(meta,7) * 5 + 30 * Bool.to_u32(U32.is_eq(arcana,5))) / 100 : U32)
def player_damage(+hit: U32,+invuln: U32,+passives: List<&2,U32>,+meta: U32,+arcana: U32,+character: U32) -> U32:
  Combat.contact_damage(hit,invuln,U32.max(1,Combat.lose(6,(at(passives,6) + meta_rank(meta,3) + 3 * Bool.to_u32(U32.is_eq(arcana,4)) + Bool.to_u32(U32.is_eq(character,3)) : U32))))
# Armor remains valuable, but crowd pressure cannot be reduced to one damage.
# The last minute is a deliberate lethal gauntlet rather than an Storage.empty victory lap.
def pressure_damage(+hit: U32,+tick: U32,+mode: U32,+invuln: U32,passives: List<&2,U32>,meta: U32,arcana: U32,character: U32) -> U32:
  Combat.contact_damage(hit,invuln,(player_damage(hit,invuln,passives,meta,arcana,character) + (tick / 3600 + U32.min(6,(hit / 3 : U32)) + U32.min(24,(Combat.lose(tick,Combat.lose(run_length(mode),3600)) / 150 : U32)) + 2000 * Bool.to_u32(U32.is_le(1000,hit))) : U32))
def revival_available(+hp: U32,+passives: List<&2,U32>,+meta: U32,+used: U32) -> Bool: Bool.and(U32.is_eq(hp,0),U32.is_lt(used,(meta_rank(meta,9) + at(passives,13) : U32)))
def revive_hp(revive: Bool,hp: U32,maxHp: U32) -> U32:
  match revive:
    case True{}: maxHp
    case False{}: hp
def remainder_xp(+xp: U32,+need: U32) -> U32: Combat.lose(xp,(need * Bool.to_u32(U32.is_le(need,xp)) : U32))
def reward_repeat(count: Nat,+kind: U32) -> List<&2,U32>:
  match count:
    case 0n: []
    case 1n+rest: kind <> reward_repeat(rest,kind)
def reward_extra(levelup: Bool,queue: List<&2,U32>) -> List<&2,U32>:
  match levelup:
    case True{}: 1 <> queue
    case False{}: queue
def reward_backlog(+chests: U32,levelup: Bool) -> List<&2,U32>:
  reward_extra(Bool.and(U32.is_lt(0,chests),levelup),reward_repeat(U32.to_nat(dec(chests)),2))
def finish_run(world: Storage.World(),run: Model.Run,+offers: List<&2,Model.Offer>,snapshots: List<&2,Model.Snapshot>,pending: List<&2,U32>) -> Packet: packet(State{world,run,offers,snapshots,pending})
def finish_values(world: Storage.World(),run: Model.Run,+totalXp: U32,+health: U32,+wasHit: U32,+chest: U32,+killed: U32,+coins: U32,+bossKills: U32,+snapshots: List<&2,Model.Snapshot>,+relicEvent: U32) -> Packet:
  match run:
    case Model.Run{RS.Session{_,+tick,_,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,_,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}:
      finish_run(world,Model.Run{RS.Session{phase_for(Bool.and(Bool.and(U32.is_eq(health,0),Bool.not(revival_available(health,passives,meta,revivals))),Bool.or(U32.is_eq(mode,2),U32.is_lt(tick,run_length(mode)))),Bool.and(Bool.and(Bool.not(U32.is_eq(mode,2)),U32.is_le(run_length(mode),tick)),Bool.and(U32.is_eq(health,0),Bool.not(revival_available(health,passives,meta,revivals)))),U32.is_lt(0,chest),U32.is_le(need,totalXp)),tick,remainder_xp(totalXp,need),(need + Combat.lose(next_xp_need(level),need) * Bool.to_u32(U32.is_le(need,totalXp)) : U32),(level + Bool.to_u32(U32.is_le(need,totalXp)) : U32),(kills + killed : U32),(gold + 300 * Bool.to_u32(Bool.and(U32.is_eq(mode,3),U32.is_eq(18000,tick))) + (50 + level * 5 + kills / 20) * Bool.to_u32(Bool.and(U32.is_eq(health,0),Bool.not(revival_available(health,passives,meta,revivals)))) + coins * (100 + at(passives,15) * 15 + at(passives,14) * 10 + 50 * Bool.to_u32(U32.is_eq(mode,1)) + meta_rank(meta,8) * 10 + 25 * Bool.to_u32(U32.is_eq(arcana,6))) / 100 : U32),(seed + 1 : U32),stage,(bosses + bossKills : U32),mode,enemyKinds,U32.max(relicCollected,relicEvent)},RS.PlayerState{px,py,revive_hp(revival_available(health,passives,meta,revivals),health,maxHp),maxHp,character,weapons,passives,U32.max(dec(invuln),(45 * wasHit + 180 * Bool.to_u32(revival_available(health,passives,meta,revivals)) : U32)),arcana,meta,(revivals + Bool.to_u32(revival_available(health,passives,meta,revivals)) : U32),rerolls,banishes,skips,bannedWeapons,bannedPassives}},filter_offers(phase_offers(U32.is_lt(0,chest),(seed + level * 13 : U32),weapons,passives),bannedWeapons,bannedPassives),snapshots,reward_backlog(chest,U32.is_le(need,totalXp)))
def heal_after_damage(hp: U32,damage: U32,healing: U32,healingPercent: U32,maxHp: U32) -> U32:
  U32.min(maxHp,(Combat.lose(hp,damage) + healing * healingPercent / 100 : U32))
def add_killed_kind(known: Bool,+kind: U32,kinds: List<&2,U32>) -> List<&2,U32>:
  match known:
    case True{}: kinds
    case False{}: kind <> kinds
def killed_kinds(rows: List<&2,EntityRow>,+kinds: List<&2,U32>) -> List<&2,U32>:
  match rows:
    case []: kinds
    case PickupRow{_} <> rest: killed_kinds(rest,kinds)
    case EnemyRow{+outcome,Enemy.Credit{_,1}} <> rest: killed_kinds(rest,add_killed_kind(contains(kinds,enemy_archetype(Enemy.state(outcome))),enemy_archetype(Enemy.state(outcome)),kinds))
    case _ <> rest: killed_kinds(rest,kinds)
    case _ <> rest: killed_kinds(rest,kinds)
def run_kinds(run: Model.Run) -> List<&2,U32>:
  match run:
    case Model.Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,kinds,+relicCollected},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: kinds
# Applies personal contact/hazard damage and recovery without progression or revival.
# Co-op owns match progression and has no personal auto-revival transition.
def personal_health_after_tick(run: Model.Run,+hit: U32,+heal: U32,+killed: U32) -> U32:
  match run:
    case Model.Run{RS.Session{_,+tick,_,_,_,_,_,_,+stage,_,+mode,_,_},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,_,_,_,_,_,_}}:
      heal_after_damage(hp,(pressure_damage(hit,tick,mode,invuln,passives,meta,arcana,character) + E.hazard(stage,tick,px,py) * Bool.to_u32(U32.is_eq(invuln,0)) : U32),(heal + killed * Bool.to_u32(Bool.and(U32.is_eq((tick % 12 : U32),0),Bool.and(U32.is_eq(arcana,9),Bool.or(U32.is_lt(0,at(weapons,4)),U32.is_lt(0,at(weapons,19)))))) + (meta_rank(meta,2) + at(passives,11) + 2 * Bool.to_u32(U32.is_eq(arcana,9)) + Bool.to_u32(U32.is_eq(character,2))) * Bool.to_u32(U32.is_eq((tick % 60 : U32),0)) : U32),(100 + at(passives,17) * 20 + 30 * Bool.to_u32(U32.is_eq(arcana,10)) : U32),maxHp)
def personal_invulnerability_after_tick(+invuln: U32,hit: U32) -> U32:
  U32.max(dec(invuln),(45 * Bool.to_u32(Bool.and(U32.is_lt(0,hit),U32.is_eq(invuln,0))) : U32))
def finish_personal_tick(+run: Model.Run,totals: Totals) -> RS.PlayerState:
  match totals:
    case Totals{+hit,_,_,heal,_,killed,_,_}: RS.player_with_invuln(RS.player_with_hp(run_player(run),personal_health_after_tick(run,hit,heal,killed)),personal_invulnerability_after_tick(RS.player_invuln(run_player(run)),hit))
def finish_stats(world: Storage.World(),+run: Model.Run,totals: Totals,+bossKills: U32,+kinds: List<&2,U32>) -> Packet:
  match run totals:
    case Model.Run{RS.Session{_,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}} Totals{+hit,+earned,+coins,+heal,+chest,+killed,+snapshots,+relic}:
      finish_values(world,Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,kinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},(xp + earned_xp(earned,passives,meta,arcana) : U32),personal_health_after_tick(run,hit,heal,killed),Bool.to_u32(Bool.and(U32.is_lt(0,hit),U32.is_eq(invuln,0))),chest,killed,coins,bossKills,snapshots,relic)
def executed(+run: Model.Run,result: Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>) -> Packet:
  match result:
    case Q.Executed{world,T.Success{},+rows}: finish_stats(world,run,accumulate(rows,0,0,0,0,0,0,[],0),boss_kills(rows),killed_kinds(rows,run_kinds(run)))
    case Q.Executed{_,T.Failure{_},_}: Failed{"ECS query failed"}
type effect_Player is Data: effect_Player{id: U32,run: Model.Run,eligible: Bool}
type effect_EffectStats is Data: effect_EffectStats{tick: U32,x: F32,y: F32,passives: List<&2,U32>,arcana: U32,hp: U32,eligible: Bool}
def effect_stats(eligible: Bool,run: Model.Run) -> effect_EffectStats:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{x,y,hp,_,_,_,passives,_,arcana,_,_,_,_,_,_,_}}: effect_EffectStats{tick,x,y,passives,arcana,hp,eligible}
def effect_fallback_stats() -> effect_EffectStats: effect_EffectStats{0,0.0,0.0,[],0,0,False{}}
def effect_find_stats(players: List<&2,effect_Player>,+id: U32) -> effect_EffectStats:
  match players:
    case []: effect_fallback_stats()
    case effect_Player{+pid,run,eligible} <> rest: Bool.pick(effect_EffectStats,U32.is_eq(pid,id),effect_stats(eligible,run),effect_find_stats(rest,id))
# Projectile identity selects its immutable originating player, not its current
# nearest target. Low logical-slot bits retain the original spread identity.
def effect_source(snapshots: List<&2,Model.Snapshot>,+shot: U32) -> U32:
  match snapshots:
    case []: 0
    case Model.ProjectileSnapshot{Shot.State{_,+seed,_,_,Components.Trajectory{_,_,_,_,_,_,_,Some{sourcePlayer}}}} <> rest: Bool.pick(U32,U32.is_eq(seed,shot),sourcePlayer,effect_source(rest,shot))
# Build once per world tick; shared-world callers use effect_apply_indexed to avoid
# scanning every snapshot for every enemy/projectile pair.
    case _ <> rest: effect_source(rest,shot)
def effect_origin_index(snapshots: List<&2,Model.Snapshot>) -> BI.Index<U32>:
  match snapshots:
    case []: BI.Empty{}
    case Model.ProjectileSnapshot{Shot.State{_,seed,_,_,Components.Trajectory{_,_,_,_,_,_,_,Some{sourcePlayer}}}} <> rest: BI.insert(~U32,effect_origin_index(rest),seed,sourcePlayer)
    case _ <> rest: effect_origin_index(rest)
def effect_indexed_source(origins: BI.Index<U32>,shot: U32) -> U32: BI.get(~U32,origins,shot,0)
def effect_source_hit(keep: Bool,row: HitPlan,tail: List<&2,HitPlan>) -> List<&2,HitPlan>:
  match keep:
    case True{}: row <> tail
    case False{}: tail
def effect_indexed_hits(rows: List<&2,HitPlan>,+origins: BI.Index<U32>,+id: U32) -> List<&2,HitPlan>:
  match rows:
    case []: []
    case HitPlan{+shot,+weapon,+damage,+x,+y,+radius,+area,+targets} <> rest: effect_source_hit(U32.is_eq(effect_indexed_source(origins,shot),id),HitPlan{shot,weapon,damage,x,y,radius,area,targets},effect_indexed_hits(rest,origins,id))

type effect_Effects is Data: effect_Effects{damage: U32,slow: Effect.Slow,burn: Effect.Burn,dx: F32,dy: F32}
def effect_one_effects(+oldX: F32,+oldY: F32,id: U32,collision: Collision,stat: effect_EffectStats) -> effect_Effects:
  match collision stat:
    case Collision{damage,slow,+burn,+pull,+knock,+sumX,+sumY} effect_EffectStats{_,+px,+py,+passives,+arcana,_,_}:
      effect_Effects{damage,slow,Effect.burn((burn * (1 + Bool.to_u32(U32.is_eq(arcana,7))) : U32),id),((oldX - px) / F32.max(1.0,F32.sqrt(distance2(oldX,oldY,px,py))) * U32.to_f32(knock) * (6.0 * (1.0 + U32.to_f32(at(passives,16)) * 0.15 + 0.75 * stat_bonus(arcana,11))) + pull_x(oldX,oldY,sumX,sumY,pull) * U32.to_f32(pull) * (3.0 + 4.0 * stat_bonus(arcana,11)) : F32),((oldY - py) / F32.max(1.0,F32.sqrt(distance2(oldX,oldY,px,py))) * U32.to_f32(knock) * (6.0 * (1.0 + U32.to_f32(at(passives,16)) * 0.15 + 0.75 * stat_bonus(arcana,11))) + pull_y(oldX,oldY,sumX,sumY,pull) * U32.to_f32(pull) * (3.0 + 4.0 * stat_bonus(arcana,11)) : F32)}
def effect_add_effects(left: effect_Effects,right: effect_Effects) -> effect_Effects:
  match left right:
    case effect_Effects{d,s,b,x,y} effect_Effects{d2,s2,b2,x2,y2}: effect_Effects{(d + d2 : U32),Effect.stronger_slow(s,s2),Effect.stronger_burn(b,b2),(x + x2 : F32),(y + y2 : F32)}
def effect_gather(players: List<&2,effect_Player>,+hits: List<&2,HitPlan>,+origins: BI.Index<U32>,+oldX: F32,+oldY: F32,+radius: F32,+target: U32,+immune: Bool) -> effect_Effects:
  match players:
    case []: effect_Effects{0,Effect.empty_slow(),Effect.empty_burn(),0.0,0.0}
    case effect_Player{+id,run,eligible} <> rest: effect_add_effects(effect_one_effects(oldX,oldY,id,immune_collision(immune,collisions(effect_indexed_hits(hits,origins,id),oldX,oldY,radius,target)),effect_stats(eligible,run)),effect_gather(rest,hits,origins,oldX,oldY,radius,target,immune))
def effect_indexed_killer(rows: List<&2,HitPlan>,+origins: BI.Index<U32>,+x: F32,+y: F32,+radius: F32,+target: U32,+hp: U32,+fallback: Maybe<&2,U32>) -> Maybe<&2,U32>:
  match rows:
    case []: fallback
    case HitPlan{+shot,_,+damage,+tx,+ty,+r,+area,+targets} <> rest: Bool.pick(Maybe<&2,U32>,Bool.and(hit_recipient(area,targets,target,x,y,radius,tx,ty,r),U32.is_le(hp,damage)),Some{effect_indexed_source(origins,shot)},effect_indexed_killer(rest,origins,x,y,radius,target,Combat.lose(hp,(damage * Bool.to_u32(hit_recipient(area,targets,target,x,y,radius,tx,ty,r)) : U32)),fallback))
# Missing credit uses the established player-zero statistics policy, without
# inventing a burn owner. Actual death reward ownership remains optional.
def effect_stats_for_credit(players: List<&2,effect_Player>,source: Maybe<&2,U32>) -> effect_EffectStats:
  match source:
    case None{}: effect_find_stats(players,0)
    case Some{id}: effect_find_stats(players,id)
def effect_stats_distance(+x: F32,+y: F32,stat: effect_EffectStats) -> F32:
  match stat:
    case effect_EffectStats{_,px,py,_,_,_,_}: distance2(x,y,px,py)
def effect_stats_living(stat: effect_EffectStats) -> Bool:
  match stat:
    case effect_EffectStats{_,_,_,_,_,hp,eligible}: Bool.and(eligible,U32.is_lt(0,hp))
def effect_nearest_target(players: List<&2,effect_Player>,+x: F32,+y: F32,+best: effect_EffectStats) -> effect_EffectStats:
  match players:
    case []: best
    case effect_Player{_,+run,+eligible} <> rest: effect_nearest_target(rest,x,y,Bool.pick(effect_EffectStats,Bool.and(effect_stats_living(effect_stats(eligible,run)),Bool.or(Bool.not(effect_stats_living(best)),F32.is_lt(effect_stats_distance(x,y,effect_stats(eligible,run)),effect_stats_distance(x,y,best)))),effect_stats(eligible,run),best))
def effect_burn_damage(+burn: Effect.Burn,stat: effect_EffectStats) -> U32:
  match stat:
    case effect_EffectStats{+tick,_,_,_,arcana,_,_}: ((2 + 2 * Bool.to_u32(U32.is_eq(arcana,7))) * Bool.to_u32(Bool.and(Effect.burn_active(burn),U32.is_eq((tick % 30 : U32),0))) : U32)
def effect_effect_luck(stat: effect_EffectStats) -> U32:
  match stat:
    case effect_EffectStats{_,_,_,passives,_,_,_}: at(passives,10)
def effect_target_x(stat: effect_EffectStats) -> F32:
  match stat:
    case effect_EffectStats{_,x,_,_,_,_,_}: x
def effect_target_y(stat: effect_EffectStats) -> F32:
  match stat:
    case effect_EffectStats{_,_,y,_,_,_,_}: y

def enemy_single_hit(collision: Collision) -> Enemy.SingleHit:
  match collision:
    case Collision{damage,slow,burn,pull,knock,x,y}: Enemy.SingleHit{damage,slow,burn,pull,knock,x,y}
def enemy_single_offense(run: Model.Run) -> Enemy.SingleOffense:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{px,py,_,_,_,_,+passives,_,+arcana,_,_,_,_,_,_,_}}: Enemy.SingleOffense{tick,px,py,(6.0 * (1.0 + U32.to_f32(at(passives,16)) * 0.15 + 0.75 * stat_bonus(arcana,11)) : F32),(3.0 + 4.0 * stat_bonus(arcana,11) : F32),(1 + Bool.to_u32(U32.is_eq(arcana,7)) : U32),(2 + 2 * Bool.to_u32(U32.is_eq(arcana,7)) : U32),at(passives,10)}
def enemy_effects_single(oldX: F32,oldY: F32,+enemy: Enemy.State,collision: Collision,run: Model.Run) -> Enemy.Outcome:
  match enemy:
    case Enemy.State{_,archetype,_,_,_}: Enemy.resolve_single(oldX,oldY,Enemy.immune(enemy),enemy_single_hit(immune_collision(U32.is_eq(archetype,30),collision)),enemy_single_offense(run))
def enemy_effects_resolved(oldX: F32,oldY: F32,+enemy: Enemy.State,effects: effect_Effects,oldBurnDamage: U32,luck: U32,+target: effect_EffectStats,killer: Maybe<&2,U32>) -> Enemy.Outcome:
  match enemy effects:
    case Enemy.State{_,_,_,_,Components.Status{+slow,+burn}} effect_Effects{damage,+freshSlow,freshBurn,dx,dy}: Enemy.resolve(enemy,oldX,oldY,Enemy.Effects{damage,freshSlow,dx,dy},Components.Status{Effect.stronger_slow(Effect.cool_slow(slow),freshSlow),Effect.stronger_burn(Effect.cool_burn(burn),freshBurn)},oldBurnDamage,luck,effect_target_x(target),effect_target_y(target),killer)
def enemy_effects_multiple(+players: List<&2,effect_Player>,+oldX: F32,+oldY: F32,+enemy: Enemy.State,+hits: List<&2,HitPlan>,+origins: BI.Index<U32>) -> Enemy.Outcome:
  match enemy:
    case Enemy.State{Space.Spatial{_,_,_,+radius},+archetype,+identity,Components.Vitals{+health,_},Components.Status{_,+burn}}:
      enemy_effects_resolved(oldX,oldY,Enemy.immune(enemy),effect_gather(players,hits,origins,oldX,oldY,radius,identity,U32.is_eq(archetype,30)),effect_burn_damage(burn,effect_stats_for_credit(players,Effect.source(burn))),effect_effect_luck(effect_stats_for_credit(players,effect_indexed_killer(hits,origins,oldX,oldY,radius,identity,health,Effect.source(burn)))),effect_nearest_target(players,oldX,oldY,effect_fallback_stats()),effect_indexed_killer(hits,origins,oldX,oldY,radius,identity,health,Effect.source(burn)))
# This sole-player-zero optimization is reachable only before any guest joins.
# Co-op views retain every joined record after disconnect, so foreign-owned
# burns continue through the multiple-player resolver and its real owner stats.
def enemy_effects_indexed(+players: List<&2,effect_Player>,+oldX: F32,+oldY: F32,+enemy: Enemy.State,+hits: List<&2,HitPlan>,+origins: BI.Index<U32>) -> Enemy.Outcome:
  match players enemy:
    case effect_Player{0,run,_} <> [] Enemy.State{Space.Spatial{_,_,_,radius},_,identity,_,_}: enemy_effects_single(oldX,oldY,enemy,collisions(hits,oldX,oldY,radius,identity),run)
    case players _: enemy_effects_multiple(players,oldX,oldY,enemy,hits,origins)

type PlayerView is Data: PlayerView{id: U32,run: Model.Run,dx: F32,dy: F32,eligible: Bool}
type Team is Data: Team{players: List<&2,PlayerView>,base: Args,plan: SP.Plan,origins: BI.Index<U32>}
def add_view(eligible: Bool,view: PlayerView,tail: List<&2,PlayerView>) -> List<&2,PlayerView>:
  match eligible:
    case True{}: view <> tail
    case False{}: tail
def run_phase(run: Model.Run) -> U32: Model.run_phase(run)
def run_tick(run: Model.Run) -> U32: Model.run_tick(run)
def run_px(run: Model.Run) -> F32: Model.run_px(run)
def run_py(run: Model.Run) -> F32: Model.run_py(run)
def run_hp(run: Model.Run) -> U32: Model.run_hp(run)
def run_maxHp(run: Model.Run) -> U32: Model.run_maxHp(run)
def run_xp(run: Model.Run) -> U32: Model.run_xp(run)
def run_xpNeed(run: Model.Run) -> U32: Model.run_xpNeed(run)
def run_level(run: Model.Run) -> U32: Model.run_level(run)
def run_kills(run: Model.Run) -> U32: Model.run_kills(run)
def run_gold(run: Model.Run) -> U32: Model.run_gold(run)
def run_character(run: Model.Run) -> U32: Model.run_character(run)
def run_weapons(run: Model.Run) -> List<&2,U32>: Model.run_weapons(run)
def run_passives(run: Model.Run) -> List<&2,U32>: Model.run_passives(run)
def run_invuln(run: Model.Run) -> U32: Model.run_invuln(run)
def run_seed(run: Model.Run) -> U32: Model.run_seed(run)
def run_stage(run: Model.Run) -> U32: Model.run_stage(run)
def run_arcana(run: Model.Run) -> U32: Model.run_arcana(run)
def run_meta(run: Model.Run) -> U32: Model.run_meta(run)
def run_revivals(run: Model.Run) -> U32: Model.run_revivals(run)
def run_bosses(run: Model.Run) -> U32: Model.run_bosses(run)
def run_mode(run: Model.Run) -> U32: Model.run_mode(run)
def run_rerolls(run: Model.Run) -> U32: Model.run_rerolls(run)
def run_banishes(run: Model.Run) -> U32: Model.run_banishes(run)
def run_skips(run: Model.Run) -> U32: Model.run_skips(run)
def run_bannedWeapons(run: Model.Run) -> U32: Model.run_bannedWeapons(run)
def run_bannedPassives(run: Model.Run) -> U32: Model.run_bannedPassives(run)
def run_enemyKinds(run: Model.Run) -> List<&2,U32>: Model.run_enemyKinds(run)
def run_relicCollected(run: Model.Run) -> U32: Model.run_relicCollected(run)
def with_phase(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{_,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{value,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_tick(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,_,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,value,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_xp(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,_,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,value,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_xpNeed(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,_,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,value,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_level(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,_,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,value,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_gold(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,_,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,value,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_seed(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,_,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,value,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_hp(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,_,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,value,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_invuln(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,_,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,value,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_revivals(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,_,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,value,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_px(run: Model.Run,value: F32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{_,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{value,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_py(run: Model.Run,value: F32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,_,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,value,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def with_relicCollected(run: Model.Run,value: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+xpNeed,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,_},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,xpNeed,level,kills,gold,seed,stage,bosses,mode,enemyKinds,value},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def view_run(view: PlayerView) -> Model.Run:
  match view:
    case PlayerView{_,run,_,_,_}: run
# Eligibility is a separate fact; disconnected owners retain their real loadout/HP.
def view_eligible(view: PlayerView) -> Bool:
  match view:
    case PlayerView{_,_,_,_,eligible}: eligible
def view_alive(+view: PlayerView) -> Bool: Bool.and(view_eligible(view),U32.is_lt(0,run_hp(view_run(view))))
def first_view(views: List<&2,PlayerView>,fallback: Model.Run) -> PlayerView:
  match views:
    case []: PlayerView{0,fallback,0.0,0.0,True{}}
    case +first <> rest: Bool.pick(PlayerView,view_alive(first),first,first_view(rest,fallback))
def view_id(view: PlayerView) -> U32:
  match view:
    case PlayerView{id,_,_,_,_}: id
def view_args(view: PlayerView,base: Args) -> Args:
  match view base:
    case PlayerView{_,run,dx,dy,_} Args{_,targets,_,_,snapshots,hits}: Args{run,targets,dx,dy,snapshots,hits}
def nearest_view(views: List<&2,PlayerView>,+x: F32,+y: F32,+best: PlayerView) -> PlayerView:
  match views:
    case []: best
    case +candidate <> rest: nearest_view(rest,x,y,Bool.pick(PlayerView,PickupPolicy.prefer(Bool.to_u32(view_alive(candidate)),Bool.to_u32(view_alive(best)),distance2(x,y,run_px(view_run(candidate)),run_py(view_run(candidate))),distance2(x,y,run_px(view_run(best)),run_py(view_run(best))),view_id(candidate),view_id(best)),candidate,best))
def team_nearest(+team: Team,+x: F32,+y: F32) -> PlayerView:
  match team:
    case Team{+players,Args{run,_,_,_,_,_},_,origins}: nearest_view(players,x,y,first_view(players,run))
def team_view_id(views: List<&2,PlayerView>,+id: U32,fallback: PlayerView) -> PlayerView:
  match views:
    case []: fallback
    case +view <> rest: Bool.pick(PlayerView,U32.is_eq(view_id(view),id),view,team_view_id(rest,id,fallback))
def team_for_id(+team: Team,id: U32) -> PlayerView:
  match team:
    case Team{+players,Args{run,_,_,_,_,_},_,origins}: team_view_id(players,id,first_view(players,run))
def team_base(team: Team) -> Args:
  match team:
    case Team{_,base,_,origins}: base
def team_args(+team: Team,view: PlayerView) -> Args: view_args(view,team_base(team))
def pickup_eligible(+x: F32,+y: F32,view: PlayerView) -> Bool:
  match view:
    case PlayerView{_,+run,_,_,eligible}: Bool.and(eligible,PickupPolicy.living_contact(run_hp(run),close(x,y,run_px(run),run_py(run),pickup_radius(run_passives(run),run_meta(run),run_arcana(run),run_character(run)))))
def pickup_candidates(views: List<&2,PlayerView>,+x: F32,+y: F32) -> List<&2,PlayerView>:
  match views:
    case []: []
    case +view <> rest: add_view(pickup_eligible(x,y,view),view,pickup_candidates(rest,x,y))
def collector_ready(+team: Team,+x: F32,+y: F32,+candidates: List<&2,PlayerView>) -> PlayerView:
  nearest_view(candidates,x,y,first_view(candidates,view_run(team_nearest(team,x,y))))
def collector(+team: Team,+x: F32,+y: F32) -> PlayerView:
  match team:
    case Team{players,_,_,_}: collector_ready(team,x,y,pickup_candidates(players,x,y))
def own_snapshot(row: Model.Snapshot,+id: U32,+tail: List<&2,Model.Snapshot>) -> List<&2,Model.Snapshot>:
  match row:
    case Model.ProjectileSnapshot{Shot.State{+space,+identity,+side,+payload,Components.Trajectory{+vx,+vy,+life,+pierce,+visited,+owner,+slot,Some{+sourcePlayer}}}}: Bool.pick(List<&2,Model.Snapshot>,U32.is_eq(sourcePlayer,id),Model.ProjectileSnapshot{Shot.State{space,identity,side,payload,Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,Some{sourcePlayer}}}} <> tail,tail)
    case _: tail
def own_snapshots(rows: List<&2,Model.Snapshot>,+id: U32) -> List<&2,Model.Snapshot>:
  match rows:
    case []: []
    case +row <> rest: own_snapshot(row,id,own_snapshots(rest,id))
def parity_slots(rows: List<&2,U32>,+id: U32) -> List<&2,U32>:
  match rows:
    case []: []
    case +seed <> rest: free_slot(U32.is_eq((seed % 2 : U32),id),seed,parity_slots(rest,id))
def assigned_plan(+id: U32,+run: Model.Run,inventory: ShotInventory) -> SP.Plan:
  match inventory:
    case ShotInventory{occupied,counts,locks}: SP.allocate(parity_slots(free_shot_slots(U32.to_nat(PL.player_count()),PL.player_start(),occupied),id),counts,PL.caps(),shot_requests(24n,(Shot.schedule_tick(shot_schedule_for(id,run)) % PL.owner_count() : U32),shot_schedule_for(id,run),locks))
def merge_assignments(index: BI.Index<SP.Request>,+id: U32,into: BI.Index<SP.Request>) -> BI.Index<SP.Request>:
  match index:
    case BI.Empty{}: into
    case BI.Item{seed,SP.Request{owner,emission,level}}: BI.insert(~SP.Request,into,seed,SP.Request{owner,emission,level})
    case BI.Fork{_,_,zero,one}: merge_assignments(one,id,merge_assignments(zero,id,into))
def merge_player_plan(+id: U32,plan: SP.Plan,tail: SP.Plan) -> SP.Plan:
  match plan tail:
    case SP.Plan{index,count} SP.Plan{into,other}: SP.Plan{merge_assignments(index,id,into),(count + other : U32)}
def player_plan(view: PlayerView,snapshots: List<&2,Model.Snapshot>) -> SP.Plan:
  match view:
    case PlayerView{+id,run,_,_,_}: assigned_plan(id,run,shot_inventory(own_snapshots(snapshots,id),ShotInventory{BI.Empty{},empty_owner_counts(),empty_owner_counts()}))
def team_plan_all(views: List<&2,PlayerView>,+snapshots: List<&2,Model.Snapshot>) -> SP.Plan:
  match views:
    case []: empty_shot_plan()
    case +view <> rest: merge_player_plan(view_id(view),player_plan(view,snapshots),team_plan_all(rest,snapshots))

# Player identity, weapon ownership and local spread slots are independent.
def team_shot_spawn(+team: Team,+seed: U32,request: Maybe<&2,SP.Request>) -> EntityRow:
  match request:
    case None{}: ProjectileRow{Shot.Outcome{Shot.dormant(0.0,0.0,seed,Shot.PlayerShot{}),0}}
    case Some{SP.Request{+owner,SP.Emission{+sourcePlayer,+slot},level}}: shot_spawn_ready(True{},sourcePlayer,seed,owner,slot,level,team_args(team,team_for_id(team,sourcePlayer)))
def team_shot_alive(alive: Bool,+team: Team,+projectile: Shot.State,plan: SP.Plan) -> EntityRow:
  match alive projectile:
    case False{} +projectile: team_shot_spawn(team,Shot.identity(projectile),SP.lookup(plan,Shot.identity(projectile)))
    case True{} Shot.State{Space.Spatial{+x,+y,+age,+radius},+identity,+side,+payload,Components.Trajectory{+vx,+vy,+life,+pierce,+visited,+owner,+slot,Some{+sourcePlayer}}}: shot_step_aim(Shot.State{Space.Spatial{x,y,age,radius},identity,side,payload,Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,Some{sourcePlayer}}},team_args(team,team_for_id(team,sourcePlayer)),nearest_from_args(team_base(team),x,y))
    case True{} _: missing_row()
def team_shot(team: Team,+projectile: Shot.State) -> EntityRow:
  match team:
    case Team{players,base,+plan,origins}: team_shot_alive(Shot.active(projectile),Team{players,base,plan,origins},projectile,plan)
def projectile_side(role: Role.Role) -> Shot.Side:
  match role:
    case Role.HostileProjectileSlot{}: Shot.HostileShot{}
    case _: Shot.PlayerShot{}
def team_projectile_role(role: Role.Role,+team: Team,+projectile: Shot.State) -> EntityRow:
  match role projectile:
    case Role.PlayerProjectileSlot{} projectile: team_shot(team,projectile)
    case Role.HostileProjectileSlot{} Shot.State{Space.Spatial{+x,+y,+age,+radius},+identity,+side,+payload,+trajectory}: hostile_step(Shot.State{Space.Spatial{x,y,age,radius},identity,side,payload,trajectory},team_args(team,team_nearest(team,x,y)))
    case _ _: missing_row()
def team_projectile_trajectory(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~payloadRead: H -> H & C.Access<Components.ShotPayload>,~payloadReplace: H -> Components.ShotPayload -> H,~trajectoryRead: H -> H & C.Access<Components.Trajectory>,~trajectoryReplace: H -> Components.Trajectory -> H,~identityRead: H -> H & C.Access<Components.Identity>,~roleRead: H -> H & C.Access<Role.Role>,+role: Role.Role,team: Team,identity: U32,space: Space.Spatial,payload: Components.ShotPayload,result: H & C.Access<Components.Trajectory>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{trajectory}): projectile_write(~H,~spatialRead,~spatialReplace,~payloadRead,~payloadReplace,~trajectoryRead,~trajectoryReplace,~identityRead,~roleRead,ctx,team_projectile_role(role,team,Shot.State{space,identity,projectile_side(role),payload,trajectory}))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_projectile_payload(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~payloadRead: H -> H & C.Access<Components.ShotPayload>,~payloadReplace: H -> Components.ShotPayload -> H,~trajectoryRead: H -> H & C.Access<Components.Trajectory>,~trajectoryReplace: H -> Components.Trajectory -> H,~identityRead: H -> H & C.Access<Components.Identity>,~roleRead: H -> H & C.Access<Role.Role>,role: Role.Role,team: Team,identity: U32,space: Space.Spatial,result: H & C.Access<Components.ShotPayload>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{payload}): team_projectile_trajectory(~H,~spatialRead,~spatialReplace,~payloadRead,~payloadReplace,~trajectoryRead,~trajectoryReplace,~identityRead,~roleRead,role,team,identity,space,payload,trajectoryRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_projectile_spatial(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~payloadRead: H -> H & C.Access<Components.ShotPayload>,~payloadReplace: H -> Components.ShotPayload -> H,~trajectoryRead: H -> H & C.Access<Components.Trajectory>,~trajectoryReplace: H -> Components.Trajectory -> H,~identityRead: H -> H & C.Access<Components.Identity>,~roleRead: H -> H & C.Access<Role.Role>,role: Role.Role,team: Team,identity: U32,result: H & C.Access<Space.Spatial>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{space}): team_projectile_payload(~H,~spatialRead,~spatialReplace,~payloadRead,~payloadReplace,~trajectoryRead,~trajectoryReplace,~identityRead,~roleRead,role,team,identity,space,payloadRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_projectile_identity(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~payloadRead: H -> H & C.Access<Components.ShotPayload>,~payloadReplace: H -> Components.ShotPayload -> H,~trajectoryRead: H -> H & C.Access<Components.Trajectory>,~trajectoryReplace: H -> Components.Trajectory -> H,~identityRead: H -> H & C.Access<Components.Identity>,~roleRead: H -> H & C.Access<Role.Role>,role: Role.Role,team: Team,result: H & C.Access<Components.Identity>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{Components.Identity{identity}}): team_projectile_spatial(~H,~spatialRead,~spatialReplace,~payloadRead,~payloadReplace,~trajectoryRead,~trajectoryReplace,~identityRead,~roleRead,role,team,identity,spatialRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_projectile_observed(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~payloadRead: H -> H & C.Access<Components.ShotPayload>,~payloadReplace: H -> Components.ShotPayload -> H,~trajectoryRead: H -> H & C.Access<Components.Trajectory>,~trajectoryReplace: H -> Components.Trajectory -> H,~identityRead: H -> H & C.Access<Components.Identity>,~roleRead: H -> H & C.Access<Role.Role>,team: Team,result: H & C.Access<Role.Role>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{role}): team_projectile_identity(~H,~spatialRead,~spatialReplace,~payloadRead,~payloadReplace,~trajectoryRead,~trajectoryReplace,~identityRead,~roleRead,role,team,identityRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_projectile_system(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~payloadRead: H -> H & C.Access<Components.ShotPayload>,~payloadReplace: H -> Components.ShotPayload -> H,~trajectoryRead: H -> H & C.Access<Components.Trajectory>,~trajectoryReplace: H -> Components.Trajectory -> H,~identityRead: H -> H & C.Access<Components.Identity>,~roleRead: H -> H & C.Access<Role.Role>,team: Team,ctx: H) -> H & (T.Outcome<Error> & EntityRow): team_projectile_observed(~H,~spatialRead,~spatialReplace,~payloadRead,~payloadReplace,~trajectoryRead,~trajectoryReplace,~identityRead,~roleRead,team,roleRead(ctx))
def EntityProgramOps(H: Type) -> Type: Team -> H -> H & (T.Outcome<Error> & EntityRow)
def entity_program_dispatch(~H: Type,~run: EntityProgramOps(H),args: Team,ctx: H) -> H & (T.Outcome<Error> & EntityRow): run(args,ctx)
def projectile_caps(team: Team,ctx: Frame()) -> Frame() & (T.Outcome<Error> & EntityRow):
  team_projectile_system(~Frame(),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.ShotRest,~Components.ShotPayload,~Components.ShotPayload,~Storage.ShotToken,~Storage.take_shot,~Storage.put_shot,~Storage.project_shot,~Storage.shot_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.ShotRest,~Components.ShotPayload,~Components.ShotPayload,~Storage.ShotToken,~Storage.take_shot,~Storage.put_shot,~Storage.project_shot,~Storage.shot_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.TrajectoryRest,~Components.Trajectory,~Components.Trajectory,~Storage.TrajectoryToken,~Storage.take_trajectory,~Storage.put_trajectory,~Storage.project_trajectory,~Storage.trajectory_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.TrajectoryRest,~Components.Trajectory,~Components.Trajectory,~Storage.TrajectoryToken,~Storage.take_trajectory,~Storage.put_trajectory,~Storage.project_trajectory,~Storage.trajectory_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.IdentityRest,~Components.Identity,~Components.Identity,~Storage.IdentityToken,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,~Storage.identity_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,~Storage.role_family()),team,ctx)
def projectile_plan() -> Q.Plan<Storage.Schema,Storage.Store,Unit,Unit,EntityProgramOps>:
  Q.Plan{projectile_caps,selected_projectile}
def move_space_toward(space: Space.Spatial,variant: U32,slow: Effect.Slow,+run: Model.Run) -> Space.Spatial:
  Space.step(space,variant,slow,run_tick(run),run_px(run),run_py(run))
def team_move_space(team: Team,+space: Space.Spatial,variant: U32,slow: Effect.Slow) -> Space.Spatial:
  match space:
    case Space.Spatial{x,y,_,_}: move_space_toward(space,variant,slow,view_run(team_nearest(team,x,y)))
def team_move_status(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~statusRead: H -> H & C.Access<Components.Status>,team: Team,space: Space.Spatial,variant: U32,result: H & C.Access<Components.Status>) -> H & (T.Outcome<Error> & Unit):
  match result:
    case (ctx,C.Found{Components.Status{slow,_}}): (spatialReplace(ctx,team_move_space(team,space,variant,slow)),(T.Success{},Unit{}))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},Unit{}))
def team_move_metadata(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~statusRead: H -> H & C.Access<Components.Status>,team: Team,space: Space.Spatial,result: H & C.Access<Enemy.Phase>) -> H & (T.Outcome<Error> & Unit):
  match result:
    case (ctx,C.Found{Enemy.ActiveEnemy{archetype}}): team_move_status(~H,~spatialRead,~spatialReplace,~phaseRead,~statusRead,team,space,archetype,statusRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},Unit{}))
def team_move_spatial(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~statusRead: H -> H & C.Access<Components.Status>,team: Team,result: H & C.Access<Space.Spatial>) -> H & (T.Outcome<Error> & Unit):
  match result:
    case (ctx,C.Found{space}): team_move_metadata(~H,~spatialRead,~spatialReplace,~phaseRead,~statusRead,team,space,phaseRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},Unit{}))
def team_move_system(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~statusRead: H -> H & C.Access<Components.Status>,team: Team,ctx: H) -> H & (T.Outcome<Error> & Unit): team_move_spatial(~H,~spatialRead,~spatialReplace,~phaseRead,~statusRead,team,spatialRead(ctx))

def MovementProgramOps(H: Type) -> Type: Team -> H -> H & (T.Outcome<Error> & Unit)
def movement_program_dispatch(~H: Type,~run: MovementProgramOps(H),args: Team,ctx: H) -> H & (T.Outcome<Error> & Unit): run(args,ctx)
def move_caps(team: Team,ctx: Frame()) -> Frame() & (T.Outcome<Error> & Unit):
  team_move_system(~Frame(),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~Storage.phase_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.StatusRest,~Components.Status,~Components.Status,~Storage.StatusToken,~Storage.take_status,~Storage.put_status,~Storage.project_status,~Storage.status_family()),team,ctx)
def move_plan() -> Q.Plan<Storage.Schema,Storage.Store,Unit,Unit,MovementProgramOps>:
  Q.Plan{move_caps,selected_enemy}
def team_spawn_view(+team: Team,+id: U32) -> PlayerView:
  +candidate = team_for_id(team,id)
  Bool.pick(PlayerView,view_alive(candidate),candidate,team_nearest(team,run_px(view_run(candidate)),run_py(view_run(candidate))))
def movement_x(point: PlayerMovement.Point) -> F32:
  match point:
    case PlayerMovement.Point{x,_}: x
def movement_y(point: PlayerMovement.Point) -> F32:
  match point:
    case PlayerMovement.Point{_,y}: y
def run_step_distance(+run: Model.Run) -> F32: (2.5 * speed_bonus(run_passives(run),run_meta(run),run_arcana(run),run_character(run)) : F32)
def move_point(x: F32,y: F32,distance: F32,dx: F32,dy: F32) -> PlayerMovement.Point: PlayerMovement.move_point(x,y,distance,dx,dy)
def moved_run_point(run: Model.Run,point: PlayerMovement.Point) -> Model.Run:
  match point:
    case PlayerMovement.Point{x,y}: with_py(with_px(run,x),y)
def moved_run(view: PlayerView) -> Model.Run:
  match view:
    case PlayerView{_,+run,dx,dy,_}: moved_run_point(run,move_point(run_px(run),run_py(run),run_step_distance(run),dx,dy))
def outside_players(views: List<&2,PlayerView>,+x: F32,+y: F32,+radius: F32) -> Bool:
  match views:
    case []: True{}
    case +view <> rest: Bool.and(Bool.or(Bool.not(view_alive(view)),S.admissible(x,y,run_px(moved_run(view)),run_py(moved_run(view)),radius)),outside_players(rest,x,y,radius))
def multiple_views(views: List<&2,PlayerView>) -> Bool:
  match views:
    case []: False{}
    case _ <> []: False{}
    case _: True{}
def spawn_camera(view: PlayerView) -> PredictionSpawn.Camera:
  match view:
    case PlayerView{_,+run,+dx,+dy,_}:
      +distance = run_step_distance(run)
      +moved = move_point(run_px(run),run_py(run),distance,dx,dy)
      PredictionSpawn.Camera{movement_x(moved),movement_y(moved),distance}
def outside_predicted_players(views: List<&2,PlayerView>,+x: F32,+y: F32,+radius: F32) -> Bool:
  match views:
    case []: True{}
    case +view <> rest: Bool.and(Bool.or(Bool.not(view_alive(view)),PredictionSpawn.admissible(x,y,spawn_camera(view),radius)),outside_predicted_players(rest,x,y,radius))
def maximum_prediction_distance(views: List<&2,PlayerView>,+distance: F32) -> F32:
  match views:
    case []: distance
    case PlayerView{_,+run,_,_,eligible} <> rest: maximum_prediction_distance(rest,F32.max(distance,Bool.pick(F32,Bool.and(eligible,U32.is_lt(0,run_hp(run))),run_step_distance(run),0.0)))
def effect_players(views: List<&2,PlayerView>) -> List<&2,effect_Player>:
  match views:
    case []: []
    case PlayerView{id,run,_,_,eligible} <> rest: effect_Player{id,run,eligible} <> effect_players(rest)
def living_views(views: List<&2,PlayerView>) -> List<&2,PlayerView>:
  match views:
    case []: []
    case +view <> rest: add_view(view_alive(view),view,living_views(rest))
def party_spawn_players(team: Team) -> U32:
  match team:
    case Team{views,_,_,_}: U32.from_nat(List.length(&2,PlayerView,living_views(views)))
def team_views(team: Team) -> List<&2,PlayerView>:
  match team:
    case Team{views,_,_,_}: views
def team_hits(team: Team) -> List<&2,HitPlan>:
  match team:
    case Team{_,Args{_,_,_,_,_,hits},_,_}: hits
def team_origins(team: Team) -> BI.Index<U32>:
  match team:
    case Team{_,_,_,origins}: origins
# Enemy-specific pure rules consume named facts, never Body or Motion.
def team_enemy_view(phase: Enemy.Phase,+team: Team,space: Space.Spatial,identity: U32) -> PlayerView:
  match phase space:
    case Enemy.Dormant{_} _: team_spawn_view(team,(identity % 2 : U32))
    case Enemy.ActiveEnemy{_} Space.Spatial{x,y,_,_}: team_nearest(team,x,y)
    case Enemy.OccupiedByLoot{_} Space.Spatial{x,y,_,_}: collector(team,x,y)
def enemy_spawn_context(team: Team,run: Model.Run) -> EnemySpawn.Context:
  match run:
    case Model.Run{RS.Session{_,+tick,_,_,_,_,_,rng,stage,_,+mode,_,_},RS.PlayerState{px,py,_,_,character,_,+passives,_,+arcana,_,_,_,_,_,_,_}}:
      EnemySpawn.Context{tick,mode,stage,(rng - tick + 1 : U32),px,py,(at(passives,14) * 10 + 35 * Bool.to_u32(U32.is_eq(mode,1)) + 20 * Bool.to_u32(U32.is_eq(arcana,5)) : U32),(at(passives,14) * 10 + 35 * Bool.to_u32(U32.is_eq(mode,1)) + 20 * Bool.to_u32(U32.is_eq(arcana,5)) + 15 * Bool.to_u32(U32.is_eq(character,6)) : U32),party_spawn_players(team)}
def candidate_state(candidate: EnemyLife.Candidate,status: Components.Status) -> Enemy.State:
  match candidate:
    case EnemyLife.Candidate{x,y,archetype,identity,vitals,radius}: Enemy.State{Space.Spatial{x,y,0,radius},archetype,identity,vitals,status}
def sleeping_enemy(enemy: Enemy.State) -> Enemy.Outcome:
  match enemy:
    case Enemy.State{Space.Spatial{x,y,age,radius},archetype,identity,vitals,status}: Enemy.Sleeping{Enemy.State{Space.Spatial{x,y,(age + 1 : U32),radius},archetype,identity,vitals,status}}
def enemy_identity(enemy: Enemy.State) -> U32:
  match enemy:
    case Enemy.State{_,_,identity,_,_}: identity
def enemy_status_slow(status: Components.Status) -> Effect.Slow:
  match status:
    case Components.Status{slow,_}: slow
def enemy_old_x(enemy: Enemy.State) -> F32:
  match enemy:
    case Enemy.State{Space.Spatial{x,_,_,_},_,_,_,_}: x
def enemy_old_y(enemy: Enemy.State) -> F32:
  match enemy:
    case Enemy.State{Space.Spatial{_,y,_,_},_,_,_,_}: y
def enemy_status(enemy: Enemy.State) -> Components.Status:
  match enemy:
    case Enemy.State{_,_,_,_,status}: status
def team_enemy_continued(phase: Enemy.Phase,+team: Team,+enemy: Enemy.State) -> Enemy.Decision:
  match phase:
    case Enemy.ActiveEnemy{_}: Enemy.Resolved{enemy_effects_indexed(effect_players(team_views(team)),enemy_old_x(enemy),enemy_old_y(enemy),enemy,team_hits(team),team_origins(team))}
    case Enemy.Dormant{_}: Enemy.Resolved{sleeping_enemy(enemy)}
    case Enemy.OccupiedByLoot{_}: Enemy.LootTurn{True{},False{}}
def enemy_clear_status(enemy: Enemy.State) -> Enemy.State:
  match enemy:
    case Enemy.State{space,archetype,identity,vitals,_}: Enemy.State{space,archetype,identity,vitals,Components.Status{Effect.empty_slow(),Effect.empty_burn()}}
def team_enemy_rejected(phase: Enemy.Phase,previous: Enemy.State) -> Enemy.Decision:
  match phase:
    case Enemy.ActiveEnemy{_}: Enemy.Resolved{Enemy.Alive{enemy_clear_status(previous),0}}
    case Enemy.Dormant{_}: Enemy.Resolved{Enemy.Sleeping{enemy_clear_status(previous)}}
    case Enemy.OccupiedByLoot{_}: Enemy.LootTurn{False{},True{}}
def enemy_candidate_point(candidate: EnemyLife.Candidate,point: S.Point) -> EnemyLife.Candidate:
  match candidate point:
    case EnemyLife.Candidate{_,_,archetype,identity,vitals,radius} S.Point{x,y}: EnemyLife.Candidate{x,y,archetype,identity,vitals,radius}
def enemy_predicted_at(view: PlayerView,distance: F32,+candidate: EnemyLife.Candidate) -> EnemyLife.Candidate:
  match view candidate:
    case PlayerView{_,+run,_,_,_} EnemyLife.Candidate{_,_,_,+identity,_,radius}: enemy_candidate_point(candidate,PredictionSpawn.choose((identity + ((run_seed(run) - run_tick(run) + 1 : U32) - 12345) * 31 : U32),wave_tick(run_mode(run),run_tick(run)),PredictionSpawn.Camera{run_px(run),run_py(run),distance},radius))
def enemy_candidate_padded(padded: Bool,+phase: Enemy.Phase,+team: Team,+previous: Enemy.State,candidate: EnemyLife.Candidate) -> EnemyLife.Candidate:
  match padded team previous:
    case False{} _ _: candidate
    case True{} Team{+views,base,plan,origins} Enemy.State{space,_,identity,_,_}: enemy_predicted_at(team_enemy_view(phase,Team{views,base,plan,origins},space,identity),maximum_prediction_distance(views,0.0),candidate)
def enemy_candidate_allowed(padded: Bool,views: List<&2,PlayerView>,candidate: EnemyLife.Candidate) -> Bool:
  match padded candidate:
    case False{} EnemyLife.Candidate{x,y,_,_,_,radius}: outside_players(views,x,y,radius)
    case True{} EnemyLife.Candidate{x,y,_,_,_,radius}: outside_predicted_players(views,x,y,radius)
def team_enemy_birth_allowed(allowed: Bool,phase: Enemy.Phase,previous: Enemy.State,candidate: EnemyLife.Candidate) -> Enemy.Decision:
  match allowed:
    case False{}: team_enemy_rejected(phase,previous)
    case True{}: Enemy.Resolved{Enemy.Born{EnemyLife.birth(candidate)}}
def team_enemy_birth_checked(+padded: Bool,phase: Enemy.Phase,+team: Team,previous: Enemy.State,+candidate: EnemyLife.Candidate) -> Enemy.Decision:
  team_enemy_birth_allowed(enemy_candidate_allowed(padded,team_views(team),candidate),phase,previous,candidate)
def team_enemy_birth(+phase: Enemy.Phase,+team: Team,+previous: Enemy.State,candidate: EnemyLife.Candidate) -> Enemy.Decision:
  team_enemy_birth_checked(multiple_views(team_views(team)),phase,team,previous,enemy_candidate_padded(multiple_views(team_views(team)),phase,team,previous,candidate))
def team_enemy_candidate(fresh: Bool,+team: Team,+phase: Enemy.Phase,+previous: Enemy.State,candidate: EnemyLife.Candidate) -> Enemy.Decision:
  match fresh:
    case True{}: team_enemy_birth(phase,team,previous,candidate)
    case False{}: Enemy.Resolved{enemy_effects_indexed(effect_players(team_views(team)),enemy_old_x(previous),enemy_old_y(previous),candidate_state(candidate,enemy_status(previous)),team_hits(team),team_origins(team))}
def team_enemy_updated(+team: Team,+previousPhase: Enemy.Phase,+previous: Enemy.State,candidate: Maybe<&2,EnemyLife.Candidate>) -> Enemy.Decision:
  match candidate:
    case None{}: team_enemy_continued(previousPhase,team,previous)
    case Some{candidate}: team_enemy_candidate(Bool.not(Bool.and(Enemy.active(previousPhase),U32.is_eq(Space.age(Enemy.spatial(previous)),0))),team,previousPhase,previous,candidate)
def enemy_row(+outcome: Enemy.Outcome) -> EntityRow: EnemyRow{outcome,Enemy.credit(outcome)}
def enemy_outcome_phase(outcome: Enemy.Outcome) -> Enemy.Phase:
  match outcome:
    case Enemy.Alive{Enemy.State{_,archetype,_,_,_},_}: Enemy.ActiveEnemy{archetype}
    case Enemy.Born{EnemyLife.Newborn{EnemyLife.Candidate{_,_,archetype,_,_,_},_,_,_,_}}: Enemy.ActiveEnemy{archetype}
    case Enemy.Sleeping{Enemy.State{_,archetype,_,_,_}}: Enemy.Dormant{archetype}
    case Enemy.Killed{_,Enemy.DeathReward{Enemy.XpDrop{},_,_,_,archetype,_,_}}: Enemy.Dormant{archetype}
    case Enemy.Killed{Enemy.State{_,archetype,_,_,_},_}: Enemy.OccupiedByLoot{archetype}
def enemy_outcome_space(outcome: Enemy.Outcome) -> Space.Spatial:
  match outcome:
    case Enemy.Killed{_,Enemy.DeathReward{Enemy.XpDrop{},_,x,y,_,_,_}}: Space.Spatial{x,y,0,0.0}
    case Enemy.Killed{_,Enemy.DeathReward{_,_,x,y,_,_,_}}: Space.Spatial{x,y,0,6.0}
    case outcome: Enemy.spatial(Enemy.state(outcome))
def write_enemy_values(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,ctx: H,phase: Enemy.Phase,space: Space.Spatial,vitals: Components.Vitals,status: Components.Status) -> H:
  phaseReplace(spatialReplace(statusReplace(vitalsReplace(ctx,vitals),status),space),phase)
def write_enemy_state(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,ctx: H,+outcome: Enemy.Outcome,state: Enemy.State) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match state:
    case Enemy.State{_,_,_,vitals,status}: (write_enemy_values(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,ctx,enemy_outcome_phase(outcome),enemy_outcome_space(outcome),vitals,status),(T.Success{},EnemyReady{enemy_row(outcome)}))
def write_enemy_outcome(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,ctx: H,+outcome: Enemy.Outcome) -> H & (T.Outcome<Error> & EnemyQueryResult):
  write_enemy_state(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,ctx,outcome,Enemy.state(outcome))
def enemy_loot_requested(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,reset: Bool,advance: Bool,ctx: H) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match reset:
    case False{}: (ctx,(T.Success{},LootRequest{advance}))
    case True{}: (statusReplace(ctx,Components.Status{Effect.empty_slow(),Effect.empty_burn()}),(T.Success{},LootRequest{advance}))
def write_enemy_decision(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,ctx: H,decision: Enemy.Decision) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match decision:
    case Enemy.Resolved{outcome}: write_enemy_outcome(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,ctx,outcome)
    case Enemy.LootTurn{advance,reset}: enemy_loot_requested(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,reset,advance,ctx)
def team_enemy_status(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,+team: Team,+phase: Enemy.Phase,+space: Space.Spatial,+identity: U32,vitals: Components.Vitals,result: H & C.Access<Components.Status>) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match result:
    case (ctx,C.Found{status}): write_enemy_decision(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,ctx,team_enemy_updated(team,phase,Enemy.State{space,Enemy.archetype(phase),identity,vitals,status},EnemySpawn.propose(identity,Enemy.dormant(phase),enemy_spawn_context(team,view_run(team_enemy_view(phase,team,space,identity))))))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},EnemyReady{missing_row()}))
def team_enemy_vitals(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,team: Team,phase: Enemy.Phase,space: Space.Spatial,identity: U32,result: H & C.Access<Components.Vitals>) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match result:
    case (ctx,C.Found{vitals}): team_enemy_status(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,team,phase,space,identity,vitals,statusRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},EnemyReady{missing_row()}))
def team_enemy_spatial(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,team: Team,phase: Enemy.Phase,identity: U32,result: H & C.Access<Space.Spatial>) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match result:
    case (ctx,C.Found{space}): team_enemy_vitals(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,team,phase,space,identity,vitalsRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},EnemyReady{missing_row()}))
def team_enemy_phase(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,team: Team,identity: U32,result: H & C.Access<Enemy.Phase>) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match result:
    case (ctx,C.Found{phase}): team_enemy_spatial(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,team,phase,identity,spatialRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},EnemyReady{missing_row()}))
def team_enemy_identity(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,team: Team,result: H & C.Access<Components.Identity>) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match result:
    case (ctx,C.Found{Components.Identity{identity}}): team_enemy_phase(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,team,identity,phaseRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},EnemyReady{missing_row()}))
type TeamEnemy is Data: TeamEnemy{role: Role.Role,team: Team}
def team_enemy_system(~H: Type,~vitalsRead: H -> H & C.Access<Components.Vitals>,~vitalsReplace: H -> Components.Vitals -> H,~statusRead: H -> H & C.Access<Components.Status>,~statusReplace: H -> Components.Status -> H,~spatialRead: H -> H & C.Access<Space.Spatial>,~spatialReplace: H -> Space.Spatial -> H,~phaseRead: H -> H & C.Access<Enemy.Phase>,~phaseReplace: H -> Enemy.Phase -> H,~identityRead: H -> H & C.Access<Components.Identity>,call: TeamEnemy,ctx: H) -> H & (T.Outcome<Error> & EnemyQueryResult):
  match call:
    case TeamEnemy{_,team}: team_enemy_identity(~H,~vitalsRead,~vitalsReplace,~statusRead,~statusReplace,~spatialRead,~spatialReplace,~phaseRead,~phaseReplace,~identityRead,team,identityRead(ctx))
def pickup_collector_state(+team: Team,+state: Pickup.State) -> Pickup.Outcome:
  match state:
    case Pickup.State{Space.Spatial{x,y,_,_},_,_}: Pickup.step(pickup_eligible(x,y,collector(team,x,y)),state)
def relic_player(+team: Team,state: Pickup.State,+x: F32,+y: F32) -> PlayerView:
  match state:
    case Pickup.State{_,Pickup.Payload{Pickup.Relic{_},_,True{}},_}: collector(team,x,y)
    case _: team_spawn_view(team,(PL.relic_seed() % 2 : U32))
def relic_turn_run(run: Model.Run,identity: U32) -> Pickup.Outcome:
  match run:
    case Model.Run{RS.Session{_,tick,_,_,_,_,_,_,+stage,_,_,_,collected},RS.PlayerState{px,py,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: PickupRelic.step(U32.is_lt(0,collected),stage,identity,tick,relic_x(stage),relic_y(stage),px,py)
def team_run(team: Team) -> Model.Run:
  match team:
    case Team{_,Args{run,_,_,_,_,_},_,_}: run
def relic_turn(+team: Team,+state: Pickup.State) -> Pickup.Outcome:
  relic_turn_run(view_run(relic_player(team,state,relic_x(run_stage(team_run(team))),relic_y(run_stage(team_run(team))))),Pickup.slot(state))
def xp_pool_active(active: Bool,team: Team,state: Pickup.State) -> Pickup.Outcome:
  match active:
    case False{}: Pickup.Outcome{Pickup.idle_xp(state),Pickup.no_reward()}
    case True{}: pickup_collector_state(team,state)
def xp_pool_turn(team: Team,+state: Pickup.State) -> Pickup.Outcome:
  xp_pool_active(Pickup.active(state),team,state)
def pickup_turn(call: PickupCall,state: Pickup.State) -> Pickup.Outcome:
  match call:
    case XpPoolCall{team}: xp_pool_turn(team,state)
    case PickupCall{_,False{},_}: Pickup.Outcome{state,Pickup.no_reward()}
    case PickupCall{team,True{},True{}}: relic_turn(team,state)
    case PickupCall{team,True{},False{}}: pickup_collector_state(team,state)
def team_pickup_identified(~H: Type,call: PickupCall,spatial: Space.Spatial,payload: Pickup.Payload,result: H & C.Access<Components.Identity>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{Components.Identity{identity}}): (ctx,(T.Success{},PickupRow{pickup_turn(call,Pickup.State{spatial,payload,identity})}))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_pickup_payload(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~pickupRead: H -> H & C.Access<Pickup.Payload>,~identityRead: H -> H & C.Access<Components.Identity>,call: PickupCall,spatial: Space.Spatial,result: H & C.Access<Pickup.Payload>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{payload}): team_pickup_identified(~H,call,spatial,payload,identityRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_pickup_spatial(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~pickupRead: H -> H & C.Access<Pickup.Payload>,~identityRead: H -> H & C.Access<Components.Identity>,call: PickupCall,result: H & C.Access<Space.Spatial>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{spatial}): team_pickup_payload(~H,~spatialRead,~pickupRead,~identityRead,call,spatial,pickupRead(ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_pickup_system(~H: Type,~spatialRead: H -> H & C.Access<Space.Spatial>,~pickupRead: H -> H & C.Access<Pickup.Payload>,~identityRead: H -> H & C.Access<Components.Identity>,call: PickupCall,ctx: H) -> H & (T.Outcome<Error> & EntityRow): team_pickup_spatial(~H,~spatialRead,~pickupRead,~identityRead,call,spatialRead(ctx))
def pool_enemy_done(~H: Type,~roleRead: H -> H & C.Access<Role.Role>,~enemyVitalsRead: H -> H & C.Access<Components.Vitals>,~enemyVitalsReplace: H -> Components.Vitals -> H,~enemyStatusRead: H -> H & C.Access<Components.Status>,~enemyStatusReplace: H -> Components.Status -> H,~enemySpatialRead: H -> H & C.Access<Space.Spatial>,~enemySpatialReplace: H -> Space.Spatial -> H,~enemyPhaseRead: H -> H & C.Access<Enemy.Phase>,~enemyPhaseReplace: H -> Enemy.Phase -> H,~enemyIdentityRead: H -> H & C.Access<Components.Identity>,~pickupSpatialRead: H -> H & C.Access<Space.Spatial>,~pickupPickupRead: H -> H & C.Access<Pickup.Payload>,~pickupIdentityRead: H -> H & C.Access<Components.Identity>,team: Team,result: H & (T.Outcome<Error> & EnemyQueryResult)) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,(T.Success{},EnemyReady{row})): (ctx,(T.Success{},row))
    case (ctx,(T.Success{},LootRequest{advance})): team_pickup_system(~H,~pickupSpatialRead,~pickupPickupRead,~pickupIdentityRead,PickupCall{team,advance,False{}},ctx)
    case (ctx,(T.Failure{error},_)): (ctx,(T.Failure{error},missing_row()))
def team_pool_role(~H: Type,~roleRead: H -> H & C.Access<Role.Role>,~enemyVitalsRead: H -> H & C.Access<Components.Vitals>,~enemyVitalsReplace: H -> Components.Vitals -> H,~enemyStatusRead: H -> H & C.Access<Components.Status>,~enemyStatusReplace: H -> Components.Status -> H,~enemySpatialRead: H -> H & C.Access<Space.Spatial>,~enemySpatialReplace: H -> Space.Spatial -> H,~enemyPhaseRead: H -> H & C.Access<Enemy.Phase>,~enemyPhaseReplace: H -> Enemy.Phase -> H,~enemyIdentityRead: H -> H & C.Access<Components.Identity>,~pickupSpatialRead: H -> H & C.Access<Space.Spatial>,~pickupPickupRead: H -> H & C.Access<Pickup.Payload>,~pickupIdentityRead: H -> H & C.Access<Components.Identity>,+team: Team,result: H & C.Access<Role.Role>) -> H & (T.Outcome<Error> & EntityRow):
  match result:
    case (ctx,C.Found{Role.XpSlot{}}): team_pickup_system(~H,~pickupSpatialRead,~pickupPickupRead,~pickupIdentityRead,XpPoolCall{team},ctx)
    case (ctx,C.Found{Role.RelicSlot{}}): team_pickup_system(~H,~pickupSpatialRead,~pickupPickupRead,~pickupIdentityRead,PickupCall{team,True{},True{}},ctx)
    case (ctx,C.Found{role}): pool_enemy_done(~H,~roleRead,~enemyVitalsRead,~enemyVitalsReplace,~enemyStatusRead,~enemyStatusReplace,~enemySpatialRead,~enemySpatialReplace,~enemyPhaseRead,~enemyPhaseReplace,~enemyIdentityRead,~pickupSpatialRead,~pickupPickupRead,~pickupIdentityRead,team,team_enemy_system(~H,~enemyVitalsRead,~enemyVitalsReplace,~enemyStatusRead,~enemyStatusReplace,~enemySpatialRead,~enemySpatialReplace,~enemyPhaseRead,~enemyPhaseReplace,~enemyIdentityRead,TeamEnemy{role,team},ctx))
    case (ctx,_): (ctx,(T.Failure{MissingComponent{}},missing_row()))
def team_pool_system(~H: Type,~roleRead: H -> H & C.Access<Role.Role>,~enemyVitalsRead: H -> H & C.Access<Components.Vitals>,~enemyVitalsReplace: H -> Components.Vitals -> H,~enemyStatusRead: H -> H & C.Access<Components.Status>,~enemyStatusReplace: H -> Components.Status -> H,~enemySpatialRead: H -> H & C.Access<Space.Spatial>,~enemySpatialReplace: H -> Space.Spatial -> H,~enemyPhaseRead: H -> H & C.Access<Enemy.Phase>,~enemyPhaseReplace: H -> Enemy.Phase -> H,~enemyIdentityRead: H -> H & C.Access<Components.Identity>,~pickupSpatialRead: H -> H & C.Access<Space.Spatial>,~pickupPickupRead: H -> H & C.Access<Pickup.Payload>,~pickupIdentityRead: H -> H & C.Access<Components.Identity>,team: Team,ctx: H) -> H & (T.Outcome<Error> & EntityRow): team_pool_role(~H,~roleRead,~enemyVitalsRead,~enemyVitalsReplace,~enemyStatusRead,~enemyStatusReplace,~enemySpatialRead,~enemySpatialReplace,~enemyPhaseRead,~enemyPhaseReplace,~enemyIdentityRead,~pickupSpatialRead,~pickupPickupRead,~pickupIdentityRead,team,roleRead(ctx))
def pool_caps(team: Team,ctx: Frame()) -> Frame() & (T.Outcome<Error> & EntityRow):
  team_pool_system(~Frame(),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.RoleRest,~Role.Role,~Role.Role,~Storage.RoleToken,~Storage.take_role,~Storage.put_role,~Storage.project_role,~Storage.role_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.VitalRest,~Components.Vitals,~Components.Vitals,~Storage.VitalToken,~Storage.take_vitals,~Storage.put_vitals,~Storage.project_vitals,~Storage.vital_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.VitalRest,~Components.Vitals,~Components.Vitals,~Storage.VitalToken,~Storage.take_vitals,~Storage.put_vitals,~Storage.project_vitals,~Storage.vital_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.StatusRest,~Components.Status,~Components.Status,~Storage.StatusToken,~Storage.take_status,~Storage.put_status,~Storage.project_status,~Storage.status_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.StatusRest,~Components.Status,~Components.Status,~Storage.StatusToken,~Storage.take_status,~Storage.put_status,~Storage.project_status,~Storage.status_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~Storage.phase_family()),~Q.set(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.EnemyPhaseRest,~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseToken,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~Storage.phase_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.IdentityRest,~Components.Identity,~Components.Identity,~Storage.IdentityToken,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,~Storage.identity_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.SpatialRest,~Space.Spatial,~Space.Spatial,~Storage.SpatialToken,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~Storage.spatial_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.PickupRest,~Pickup.Payload,~Pickup.Payload,~Storage.PickupToken,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,~Storage.pickup_family()),~Q.get(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.IdentityRest,~Components.Identity,~Components.Identity,~Storage.IdentityToken,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,~Storage.identity_family()),team,ctx)
def plan() -> Q.Plan<Storage.Schema,Storage.Store,Unit,Unit,EntityProgramOps>:
  Q.Plan{pool_caps,selected_pool}
def team_combat_done(+team: Team,projectiles: List<&2,EntityRow>,result: Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>:
  match result:
    case Q.Executed{world,T.Success{},rows}: xp_lifecycle(projectiles,xp_route_args(rows,team_base(team)),world)
    case Q.Executed{world,T.Failure{error},_}: Q.Executed{world,T.Failure{error},[]}
def team_moved(+team: Team,projectiles: List<&2,EntityRow>,result: Q.Executed<Storage.World(),Q.Error<Error>,Unit>) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>:
  match result:
    case Q.Executed{world,T.Success{},_}: team_combat_done(team,projectiles,candidate_query(~EntityProgramOps,~Team,~EntityRow,~pool_caps,~selected_pool,~entity_program_dispatch,False{},team,world))
    case Q.Executed{world,T.Failure{error},_}: Q.Executed{world,T.Failure{error},[]}
def team_movement_scoped(+team: Team,world: Storage.World(),roster: Storage.MovementRoster) -> Q.Executed<Storage.World(),Q.Error<Error>,Unit>:
  match roster:
    case Storage.MovementPrepared{handles}: OwnedQ.reserved_fields(~Storage.Schema,~Storage.Store,~Unit,~Unit,~MovementProgramOps,~Frame(),~Team,~Error,~Unit,~move_caps,~selected_enemy,~candidate_frame_identity,~candidate_frame_identity,~movement_program_dispatch,team,None{},(world,handles))
def team_movement_opened(team: Team,result: Storage.World() & Storage.MovementRoster) -> Q.Executed<Storage.World(),Q.Error<Error>,Unit>:
  match result:
    case (world,roster): team_movement_scoped(team,world,roster)
def team_projectiles_done(+team: Team,result: Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>:
  match result:
    case Q.Executed{world,T.Success{},rows}: team_moved(team,rows,team_movement_opened(team,W.with_store(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.MovementRoster,movement_roster_read,world)))
    case Q.Executed{world,T.Failure{error},_}: Q.Executed{world,T.Failure{error},[]}
# Freeze relative paths from the same movement functions the ECS will execute.
# Effects from this contact pass are applied after movement, and do not feed back
# into this tick's collision path.
def contact_spatial(+seed: U32,previous: Space.Spatial,moved: Space.Spatial) -> Contact.Target:
  match previous moved:
    case Space.Spatial{x0,y0,_,radius} Space.Spatial{x1,y1,_,_}: Contact.Target{seed,x0,y0,x1,y1,radius}
def contact_targets(rows: List<&2,Model.Snapshot>,+team: Team) -> List<&2,Contact.Target>:
  match rows:
    case []: []
    case Model.EnemySnapshot{Enemy.State{+space,archetype,identity,_,Components.Status{slow,_}}} <> rest: contact_spatial(identity,space,team_move_space(team,space,archetype,slow)) <> contact_targets(rest,team)

    case _ <> rest: contact_targets(rest,team)
def contact_shot_targets(unlimited: Bool,+targets: List<&2,Contact.Target>,+x: F32,+y: F32,+radius: F32,+pierce: U32,+visited: List<&2,U32>,next: P.Shot) -> List<&2,U32>:
  match unlimited next:
    case True{} _: []
    case False{} P.Shot{x1,y1,_,_,_,_,_}: Contact.first_ids(pierce,Contact.contacts(targets,x,y,x1,y1,radius,visited))
def contact_shot_input(args: Args,aim: Aim) -> Shot.StepInput:
  match args:
    case Args{run,_,_,_,_,_}: shot_step_input(run,aim)
def contact_shot_plan(active: Bool,+projectile: Shot.State,+team: Team,targets: List<&2,Contact.Target>,tail: List<&2,HitPlan>) -> List<&2,HitPlan>:
  match active projectile:
    case False{} _: tail
    case True{} Shot.State{Space.Spatial{+x,+y,+age,+radius},+seed,+side,Components.ShotPayload{+weapon,+damage,+enabled},Components.Trajectory{+vx,+vy,+life,+pierce,+visited,+owner,+slot,Some{+sourcePlayer}}}:
      HitPlan{seed,weapon,damage,x,y,radius,U32.is_le(9999,pierce),contact_shot_targets(U32.is_le(9999,pierce),targets,x,y,radius,pierce,visited,Shot.next(Shot.State{Space.Spatial{x,y,age,radius},seed,side,Components.ShotPayload{weapon,damage,enabled},Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,Some{sourcePlayer}}},contact_shot_input(team_args(team,team_for_id(team,sourcePlayer)),nearest_from_args(team_base(team),x,y))))} <> tail
    case True{} _: tail

def contact_plans(rows: List<&2,Model.Snapshot>,+team: Team,+targets: List<&2,Contact.Target>) -> List<&2,HitPlan>:
  match rows:
    case []: []
    case Model.ProjectileSnapshot{Shot.State{+space,+identity,Shot.PlayerShot{},Components.ShotPayload{+weapon,+damage,+enabled},+trajectory}} <> rest:
      contact_shot_plan(Bool.and(P.active_hit(weapon,Space.age(space)),Shot.active(Shot.State{space,identity,Shot.PlayerShot{},Components.ShotPayload{weapon,damage,enabled},trajectory})),Shot.State{space,identity,Shot.PlayerShot{},Components.ShotPayload{weapon,damage,enabled},trajectory},team,targets,contact_plans(rest,team,targets))
    case _ <> rest: contact_plans(rest,team,targets)
def contact_team_ready(team: Team,hits: List<&2,HitPlan>) -> Team:
  match team:
    case Team{players,Args{run,targets,dx,dy,snapshots,_},plan,origins}: Team{players,Args{run,targets,dx,dy,snapshots,hits},plan,origins}
def contact_team(+team: Team) -> Team:
  match team:
    case Team{+players,Args{+run,+targets,+dx,+dy,+snapshots,_},+plan,+origins}:
      contact_team_ready(Team{players,Args{run,targets,dx,dy,snapshots,[]},plan,origins},contact_plans(snapshots,Team{players,Args{run,targets,dx,dy,snapshots,[]},plan,origins},contact_targets(snapshots,Team{players,Args{run,targets,dx,dy,snapshots,[]},plan,origins})))
def team_execute_contacts(world: Storage.World(),+team: Team) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>:
  team_projectiles_done(team,candidate_query(~EntityProgramOps,~Team,~EntityRow,~projectile_caps,~selected_projectile,~entity_program_dispatch,True{},team,world))
def team_execute(world: Storage.World(),team: Team) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>:
  team_execute_contacts(world,contact_team(team))

def full_player_inventory(+id: U32,+run: Model.Run,all: ShotInventory,own: ShotInventory) -> SP.Plan:
  match all own:
    case ShotInventory{occupied,_,_} ShotInventory{_,counts,locks}: merge_player_plan(id,SP.allocate(free_shot_slots(U32.to_nat(PL.player_count()),PL.player_start(),occupied),counts,PL.caps(),shot_requests(24n,(Shot.schedule_tick(shot_schedule_for(id,run)) % PL.owner_count() : U32),shot_schedule_for(id,run),locks)),empty_shot_plan())
def full_player_plan(view: PlayerView,+snapshots: List<&2,Model.Snapshot>) -> SP.Plan:
  match view:
    case PlayerView{+id,run,_,_,_}: full_player_inventory(id,run,shot_inventory(snapshots,ShotInventory{BI.Empty{},empty_owner_counts(),empty_owner_counts()}),shot_inventory(own_snapshots(snapshots,id),ShotInventory{BI.Empty{},empty_owner_counts(),empty_owner_counts()}))
def plan_living(views: List<&2,PlayerView>,+snapshots: List<&2,Model.Snapshot>) -> SP.Plan:
  match views:
    case []: empty_shot_plan()
    case view <> []: full_player_plan(view,snapshots)
    case views: team_plan_all(views,snapshots)
def team_plan(views: List<&2,PlayerView>,snapshots: List<&2,Model.Snapshot>) -> SP.Plan: plan_living(living_views(views),snapshots)

def solo_team(+args: Args) -> Team:
  match args:
    case Args{+run,_,+dx,+dy,+snapshots,_}: Team{[PlayerView{0,run,dx,dy,True{}}],args,prepare_shot_plan(args),effect_origin_index(snapshots)}
def execute(world: Storage.World(),+args: Args) -> Q.Executed<Storage.World(),Q.Error<Error>,EntityRow>: team_execute(world,solo_team(args))
def advance_raw(state: State,+dx: F32,+dy: F32) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{0,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},_,+snapshots,pending}:
      executed(Model.Run{RS.Session{0,(tick + 1 : U32),xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{movement_x(move_point(px,py,(2.5 * speed_bonus(passives,meta,arcana,character) : F32),dx,dy)),movement_y(move_point(px,py,(2.5 * speed_bonus(passives,meta,arcana,character) : F32),dx,dy)),hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},execute(world,combat_args(Model.Run{RS.Session{0,(tick + 1 : U32),xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},dx,dy,snapshots)))
    case state: packet(state)
def started(+character: U32,+meta: U32,created: W.Creation<Storage.Schema,Storage.Store,Unit,Unit>) -> Packet:
  match created:
    case W.Created{_,world}: packet(State{prepare_movement_roster(W.barrier(~Storage.Schema,~Storage.Store,~Unit,~Unit,boot_pool(PL.total_nat(),0,world))),Model.Run{RS.Session{0,0,0,20,1,0,0,12345,0,0,0,[],0},RS.PlayerState{A.center(),A.center(),(initial_health(character,meta) * 70 / 100 : U32),(initial_health(character,meta) * 70 / 100 : U32),character,bump([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],starter(character)),[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],0,0,meta,0,3,3,3,0,0}},[],[],[]})
    case W.CreateRejected{_,_}: Failed{"Storage.World creation refused"}
def start(character: U32,meta: U32) -> Packet: started(U32.min(character,7),meta,W.create(~Storage.Schema,~Storage.Store,~Unit,~Unit,~Storage.empty,W.factory(),Unit{}))

def seeded_run(run: Model.Run,+selectedSeed: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,+tick,+xp,+need,+level,+kills,+gold,_,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: Model.Run{RS.Session{phase,tick,xp,need,level,kills,gold,selectedSeed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}
def seeded_packet(packetValue: Packet,+selectedSeed: U32) -> Packet:
  match packetValue:
    case Packet{State{world,run,offers,snapshots,pending}}: packet(State{world,seeded_run(run,selectedSeed),offers,snapshots,pending})
    case Failed{error}: Failed{error}
def start_seed(character: U32,meta: U32,seed: U32) -> Packet: seeded_packet(start(character,meta),seed)

def mode_configured(run: Model.Run,+selected: U32) -> Model.Run:
  match run:
    case Model.Run{RS.Session{+phase,0,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}}: configured(Model.Run{RS.Session{phase,0,xp,need,level,kills,gold,seed,stage,bosses,U32.min(selected,3),enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,choose_id(U32.is_eq(selected,3),0,meta),revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},stage,arcana)
    case run: run
def set_mode(state: State,+selected: U32) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{+phase,0,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,mode_configured(Model.Run{RS.Session{phase,0,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},selected),offers,snapshots,pending})
    case state: packet(state)
def configure_unlocks(state: State,+unlockedMask: U32) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{+phase,0,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{phase,0,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,U32.or(bannedWeapons,U32.and(16777215,U32.xor(unlockedMask,16777215))),bannedPassives}},offers,snapshots,pending})
    case state: packet(state)

def reroll_seed(seed: U32) -> U32: (seed + 41 : U32)
def reroll(state: State) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{1,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,0,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{1,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,0,banishes,skips,bannedWeapons,bannedPassives}},offers,snapshots,pending})
    case State{world,Model.Run{RS.Session{1,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},_,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{1,tick,xp,need,level,kills,gold,reroll_seed(seed),stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,dec(rerolls),banishes,skips,bannedWeapons,bannedPassives}},filter_offers(make_offers(reroll_seed(seed),weapons,passives),bannedWeapons,bannedPassives),snapshots,pending})
    case state: packet(state)

def skip_raw(state: State) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{1,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,0,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{1,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,0,bannedWeapons,bannedPassives}},offers,snapshots,pending})
    case State{world,Model.Run{RS.Session{1,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},_,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{0,tick,xp,need,level,kills,(gold + 10 : U32),seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,dec(skips),bannedWeapons,bannedPassives}},[],snapshots,pending})
    case state: packet(state)

def banish_offer(run: Model.Run,offer: Model.Offer) -> Model.Run:
  match run offer:
    case Model.Run{RS.Session{+phase,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}} Model.Offer{0,+id,_}: Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,dec(banishes),skips,U32.or(bannedWeapons,U32.shln(1,U32.to_nat(id))),bannedPassives}}
    case Model.Run{RS.Session{+phase,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}} Model.Offer{1,+id,_}: Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,dec(banishes),skips,bannedWeapons,U32.or(bannedPassives,U32.shln(1,U32.to_nat(id)))}}
    case Model.Run{RS.Session{+phase,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}} _: Model.Run{RS.Session{0,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}

def banish_raw(state: State,+choice: U32) -> Packet:
  match state:
    case State{world,Model.Run{RS.Session{1,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,0,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,Model.Run{RS.Session{1,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,0,skips,bannedWeapons,bannedPassives}},offers,snapshots,pending})
    case State{world,Model.Run{RS.Session{1,+tick,+xp,+need,+level,+kills,+gold,+seed,+stage,+bosses,+mode,+enemyKinds,+relicCollected},RS.PlayerState{+px,+py,+hp,+maxHp,+character,+weapons,+passives,+invuln,+arcana,+meta,+revivals,+rerolls,+banishes,+skips,+bannedWeapons,+bannedPassives}},+offers,+snapshots,pending}: packet(State{world,banish_offer(Model.Run{RS.Session{1,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maxHp,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}},offer_at(offers,U32.min(choice,2))),[],snapshots,pending})
    case state: packet(state)

# Deferred rewards are owned by the game state. The advance entry pauses;
# advance_live lets a host keep the arena running until the player opens a choice.
def pending_append(rows: List<&2,U32>,+kind: U32) -> List<&2,U32>:
  match rows:
    case []: [kind]
    case head <> rest: head <> pending_append(rest,kind)
def pending_add(active: Bool,rows: List<&2,U32>,kind: U32) -> List<&2,U32>:
  match active:
    case True{}: pending_append(rows,kind)
    case False{}: rows
def pending_join(left: List<&2,U32>,+right: List<&2,U32>) -> List<&2,U32>:
  match left:
    case []: right
    case head <> rest: head <> pending_join(rest,right)
def terminal_queue(terminal: Bool,pending: List<&2,U32>) -> List<&2,U32>:
  match terminal:
    case True{}: []
    case False{}: pending
# Simulation returns typed state; consumers choose whether to encode an observation.
def attach_pending(result: Packet,pending: List<&2,U32>) -> Packet:
  match result:
    case Packet{State{world,+run,offers,snapshots,newPending}}: packet(State{world,run,offers,snapshots,terminal_queue(U32.is_le(3,run_phase(run)),pending_join(pending,newPending))})
    case result: result
def advance(state: State,dx: F32,dy: F32) -> Packet:
  match state:
    case State{world,run,offers,snapshots,+pending}: attach_pending(advance_raw(State{world,run,offers,snapshots,[]},dx,dy),pending)
def reward_offers(run: Model.Run,chest: Bool) -> List<&2,Model.Offer>:
  match run:
    case Model.Run{RS.Session{_,_,_,_,+level,_,_,+seed,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,+weapons,+passives,_,_,_,_,_,_,_,+bannedWeapons,+bannedPassives}}: filter_offers(phase_offers(chest,(seed + level * 13 : U32),weapons,passives),bannedWeapons,bannedPassives)
def promote_ready(ready: Bool,world: Storage.World(),+run: Model.Run,offers: List<&2,Model.Offer>,snapshots: List<&2,Model.Snapshot>,pending: List<&2,U32>) -> Packet:
  match ready pending:
    case True{} +kind <> rest: packet(State{world,with_phase(run,kind),reward_offers(run,U32.is_eq(kind,2)),snapshots,rest})
    case _ pending: packet(State{world,run,offers,snapshots,pending})
def promote(result: Packet) -> Packet:
  match result:
    case Packet{State{world,+run,offers,snapshots,pending}}: promote_ready(U32.is_eq(run_phase(run),0),world,run,offers,snapshots,pending)
    case result: result
def choose(state: State,choice: U32) -> Packet: promote(choose_raw(state,choice))
def skip(state: State) -> Packet: promote(skip_raw(state))
def banish(state: State,choice: U32) -> Packet: promote(banish_raw(state,choice))
def live_selected(terminal: Bool,held: Bool,+oldPhase: U32,+oldLevel: U32,oldOffers: List<&2,Model.Offer>,pending: List<&2,U32>,world: Storage.World(),+run: Model.Run,offers: List<&2,Model.Offer>,snapshots: List<&2,Model.Snapshot>) -> Packet:
  match terminal held:
    case True{} _: packet(State{world,run,[],snapshots,[]})
    case False{} True{}: packet(State{world,with_phase(run,oldPhase),oldOffers,snapshots,pending_add(Bool.or(U32.is_eq(run_phase(run),1),U32.is_eq(run_phase(run),2)),pending,run_phase(run))})
    case False{} False{}: packet(State{world,run,offers,snapshots,pending})
def live_result(+oldPhase: U32,+oldLevel: U32,oldOffers: List<&2,Model.Offer>,pending: List<&2,U32>,result: Packet) -> Packet:
  match result:
    case Packet{State{world,+run,+offers,snapshots,newPending}}: live_selected(Bool.or(U32.is_eq(run_phase(run),3),U32.is_eq(run_phase(run),4)),Bool.or(U32.is_eq(oldPhase,1),U32.is_eq(oldPhase,2)),oldPhase,oldLevel,oldOffers,pending_join(pending,newPending),world,run,offers,snapshots)
    case result: result
def advance_live(state: State,dx: F32,dy: F32) -> Packet:
  match state:
    case State{world,+run,+offers,snapshots,pending}: live_result(run_phase(run),run_level(run),offers,pending,advance_raw(State{world,with_phase(run,choose_id(Bool.or(U32.is_eq(run_phase(run),1),U32.is_eq(run_phase(run),2)),0,run_phase(run))),offers,snapshots,[]},dx,dy))

def xp_visual_radius(amount: U32) -> F32: LV.radius(amount)

def xp_pile_color(amount: U32,variant: U32) -> U32: LV.pile_color(amount,U32.is_eq(variant,1))
