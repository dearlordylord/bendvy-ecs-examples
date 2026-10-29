import Base
import pickup-state.bend as Pickup
import enemy-combat.bend as Enemy
import game-components.bend as Components
import enemy-spatial.bend as Space
import entity-role.bend as Role
import bendvy-ecs-core@0.1.0.2/world.bend as W
import bendvy-ecs-core@0.1.0.2/column.bend as Col
import bendvy-ecs-core@0.1.0.2/component.bend as C

# Application-owned schema adapter: columns, family/rest wiring and ownership.
# Systems, query plans and access contracts remain beside behavior in game.
type Schema is Data: Schema{}
type VitalToken is Data: VitalToken{}
type PickupToken is Data: PickupToken{}
type TrajectoryToken is Data: TrajectoryToken{}
type StatusToken is Data: StatusToken{}
type RoleToken is Data: RoleToken{}
type MovementRoster is Data:
  MovementPrepared{handles: List<&2,W.Handle<Schema>>}
type CandidateRoster is Data:
  CandidatesPrepared{projectiles: List<&2,W.Handle<Schema>>,pool: List<&2,W.Handle<Schema>>}
# Recursive Rest carriers are boxed; three U32 pads match Store's 33-word native
# allocation class so direct take/put can reuse its cell when uniquely owned.
type VitalRest is Type:
  VitalRest{pad0: U32,pad1: U32,pad2: U32,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  VitalRestWrapped{inner: VitalRest}
type TrajectoryRest is Type:
  TrajectoryRest{vitals: Col.Column<Schema,Components.Vitals>,pad0: U32,pad1: U32,pad2: U32,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  TrajectoryRestWrapped{inner: TrajectoryRest}
type StatusRest is Type:
  StatusRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,pad0: U32,pad1: U32,pad2: U32,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  StatusRestWrapped{inner: StatusRest}
type RoleRest is Type:
  RoleRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,pad0: U32,pad1: U32,pad2: U32,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  RoleRestWrapped{inner: RoleRest}
type StoreFields is Type: StoreFields{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
# The recursive carrier keeps handle validation independent of the storage layout.
# Access adapters open the actual owner and always return the canonical Owned form.
type Store is Type:
  Owned{state: StoreFields}
  Wrapped{inner: Store}
def unseal(store: Store) -> StoreFields:
  match store:
    case Owned{state}: state
    case Wrapped{inner}: unseal(inner)
def take_vitals(store: Store) -> VitalRest & Col.Column<Schema,Components.Vitals>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (VitalRest{0,0,0,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots},vitals)
    case Wrapped{inner}: take_vitals(inner)
def put_vitals(rest: VitalRest,vitals: Col.Column<Schema,Components.Vitals>) -> Store:
  match rest:
    case VitalRest{_,_,_,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case VitalRestWrapped{inner}: put_vitals(inner,vitals)
def project_vitals(value: Components.Vitals) -> Components.Vitals & Components.Vitals:
  match value:
    case Components.Vitals{+health,+maximum}: (Components.Vitals{health,maximum},Components.Vitals{health,maximum})
def vital_family() -> C.Family<Schema,Store,VitalRest,Components.Vitals,Components.Vitals,VitalToken,take_vitals,put_vitals,project_vitals>: C.Family{"vitals"}
def take_trajectory(store: Store) -> TrajectoryRest & Col.Column<Schema,Components.Trajectory>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (TrajectoryRest{vitals,0,0,0,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots},motions)
    case Wrapped{inner}: take_trajectory(inner)
def put_trajectory(rest: TrajectoryRest,motions: Col.Column<Schema,Components.Trajectory>) -> Store:
  match rest:
    case TrajectoryRest{vitals,_,_,_,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case TrajectoryRestWrapped{inner}: put_trajectory(inner,motions)
def project_trajectory(value: Components.Trajectory) -> Components.Trajectory & Components.Trajectory:
  match value:
    case Components.Trajectory{+vx,+vy,+life,+pierce,+visited,+ownerBase,+logicalSlot,+sourcePlayer}: (Components.Trajectory{vx,vy,life,pierce,visited,ownerBase,logicalSlot,sourcePlayer},Components.Trajectory{vx,vy,life,pierce,visited,ownerBase,logicalSlot,sourcePlayer})
def trajectory_family() -> C.Family<Schema,Store,TrajectoryRest,Components.Trajectory,Components.Trajectory,TrajectoryToken,take_trajectory,put_trajectory,project_trajectory>: C.Family{"trajectory"}
def take_status(store: Store) -> StatusRest & Col.Column<Schema,Components.Status>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (StatusRest{vitals,motions,0,0,0,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots},statuses)
    case Wrapped{inner}: take_status(inner)
def put_status(rest: StatusRest,statuses: Col.Column<Schema,Components.Status>) -> Store:
  match rest:
    case StatusRest{vitals,motions,_,_,_,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case StatusRestWrapped{inner}: put_status(inner,statuses)
def project_status(value: Components.Status) -> Components.Status & Components.Status:
  match value:
    case Components.Status{+slow,+burn}: (Components.Status{slow,burn},Components.Status{slow,burn})
def status_family() -> C.Family<Schema,Store,StatusRest,Components.Status,Components.Status,StatusToken,take_status,put_status,project_status>: C.Family{"status"}
type PickupRest is Type:
  PickupRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pad0: U32,pad1: U32,pad2: U32,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  PickupRestWrapped{inner: PickupRest}
def take_pickup(store: Store) -> PickupRest & Col.Column<Schema,Pickup.Payload>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (PickupRest{vitals,motions,statuses,0,0,0,roles,movement,candidates,players,spaces,enemyPhases,identities,shots},pickups)
    case Wrapped{inner}: take_pickup(inner)
def put_pickup(rest: PickupRest,pickups: Col.Column<Schema,Pickup.Payload>) -> Store:
  match rest:
    case PickupRest{vitals,motions,statuses,_,_,_,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case PickupRestWrapped{inner}: put_pickup(inner,pickups)
def project_pickup(value: Pickup.Payload) -> Pickup.Payload & Pickup.Payload:
  match value:
    case Pickup.Payload{+item,+generation,+active}: (Pickup.Payload{item,generation,active},Pickup.Payload{item,generation,active})
def pickup_family() -> C.Family<Schema,Store,PickupRest,Pickup.Payload,Pickup.Payload,PickupToken,take_pickup,put_pickup,project_pickup>: C.Family{"pickup"}
def take_role(store: Store) -> RoleRest & Col.Column<Schema,Role.Role>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (RoleRest{vitals,motions,statuses,pickups,0,0,0,movement,candidates,players,spaces,enemyPhases,identities,shots},roles)
    case Wrapped{inner}: take_role(inner)
def put_role(rest: RoleRest,roles: Col.Column<Schema,Role.Role>) -> Store:
  match rest:
    case RoleRest{vitals,motions,statuses,pickups,_,_,_,movement,candidates,players,spaces,enemyPhases,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case RoleRestWrapped{inner}: put_role(inner,roles)
def project_role(value: Role.Role) -> Role.Role & Role.Role:
  match value:
    case Role.EnemySlot{}: (Role.EnemySlot{},Role.EnemySlot{})
    case Role.RelicSlot{}: (Role.RelicSlot{},Role.RelicSlot{})
    case Role.PlayerProjectileSlot{}: (Role.PlayerProjectileSlot{},Role.PlayerProjectileSlot{})
    case Role.HostileProjectileSlot{}: (Role.HostileProjectileSlot{},Role.HostileProjectileSlot{})
    case Role.XpSlot{}: (Role.XpSlot{},Role.XpSlot{})
    case Role.OutsideSlot{}: (Role.OutsideSlot{},Role.OutsideSlot{})
def role_family() -> C.Family<Schema,Store,RoleRest,Role.Role,Role.Role,RoleToken,take_role,put_role,project_role>: C.Family{"role"}
type SpatialToken is Data: SpatialToken{}
type SpatialRest is Type:
  SpatialRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,pad0: U32,pad1: U32,pad2: U32,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  SpatialRestWrapped{inner: SpatialRest}
def take_spatial(store: Store) -> SpatialRest & Col.Column<Schema,Space.Spatial>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (SpatialRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,0,0,0,enemyPhases,identities,shots},spaces)
    case Wrapped{inner}: take_spatial(inner)
def put_spatial(rest: SpatialRest,spaces: Col.Column<Schema,Space.Spatial>) -> Store:
  match rest:
    case SpatialRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,_,_,_,enemyPhases,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case SpatialRestWrapped{inner}: put_spatial(inner,spaces)
def project_spatial(value: Space.Spatial) -> Space.Spatial & Space.Spatial:
  match value:
    case Space.Spatial{+x,+y,+age,+radius}: (Space.Spatial{x,y,age,radius},Space.Spatial{x,y,age,radius})
def spatial_family() -> C.Family<Schema,Store,SpatialRest,Space.Spatial,Space.Spatial,SpatialToken,take_spatial,put_spatial,project_spatial>: C.Family{"enemy-spatial"}
def empty(unit: Unit) -> Store: Owned{StoreFields{Col.empty_indexed(~Schema,~Components.Vitals),Col.empty_indexed(~Schema,~Components.Trajectory),Col.empty_indexed(~Schema,~Components.Status),Col.empty_indexed(~Schema,~Pickup.Payload),Col.empty_indexed(~Schema,~Role.Role),MovementPrepared{[]},CandidatesPrepared{[],[]},Col.empty_indexed(~Schema,~Components.PlayerRecord),Col.empty_indexed(~Schema,~Space.Spatial),Col.empty_indexed(~Schema,~Enemy.Phase),Col.empty_indexed(~Schema,~Components.Identity),Col.empty_indexed(~Schema,~Components.ShotPayload)}}
def World() -> Type: W.World<Schema,Store,Unit,Unit>
type PlayerToken is Data: PlayerToken{}
type PlayerRest is Type:
  PlayerRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,pad0: U32,pad1: U32,pad2: U32,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  PlayerRestWrapped{inner: PlayerRest}
def take_players(store: Store) -> PlayerRest & Col.Column<Schema,Components.PlayerRecord>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (PlayerRest{vitals,motions,statuses,pickups,roles,movement,candidates,0,0,0,spaces,enemyPhases,identities,shots},players)
    case Wrapped{inner}: take_players(inner)
def put_players(rest: PlayerRest,players: Col.Column<Schema,Components.PlayerRecord>) -> Store:
  match rest:
    case PlayerRest{vitals,motions,statuses,pickups,roles,movement,candidates,_,_,_,spaces,enemyPhases,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case PlayerRestWrapped{inner}: put_players(inner,players)
def project_player(value: Components.PlayerRecord) -> Components.PlayerRecord & Components.PlayerRecord:
  match value:
    case Components.PlayerRecord{+id,+player,+connected,+reviveTick}: (Components.PlayerRecord{id,player,connected,reviveTick},Components.PlayerRecord{id,player,connected,reviveTick})
def player_family() -> C.Family<Schema,Store,PlayerRest,Components.PlayerRecord,Components.PlayerRecord,PlayerToken,take_players,put_players,project_player>: C.Family{"player"}

type EnemyPhaseToken is Data: EnemyPhaseToken{}
type EnemyPhaseRest is Type:
  EnemyPhaseRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,pad0: U32,pad1: U32,pad2: U32,identities: Col.Column<Schema,Components.Identity>,shots: Col.Column<Schema,Components.ShotPayload>}
  EnemyPhaseRestWrapped{inner: EnemyPhaseRest}
def take_phase(store: Store) -> EnemyPhaseRest & Col.Column<Schema,Enemy.Phase>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (EnemyPhaseRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,0,0,0,identities,shots},enemyPhases)
    case Wrapped{inner}: take_phase(inner)
def put_phase(rest: EnemyPhaseRest,enemyPhases: Col.Column<Schema,Enemy.Phase>) -> Store:
  match rest:
    case EnemyPhaseRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,_,_,_,identities,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case EnemyPhaseRestWrapped{inner}: put_phase(inner,enemyPhases)
def project_phase(value: Enemy.Phase) -> Enemy.Phase & Enemy.Phase:
  match value:
    case Enemy.Dormant{+archetype}: (Enemy.Dormant{archetype},Enemy.Dormant{archetype})
    case Enemy.ActiveEnemy{+archetype}: (Enemy.ActiveEnemy{archetype},Enemy.ActiveEnemy{archetype})
    case Enemy.OccupiedByLoot{+archetype}: (Enemy.OccupiedByLoot{archetype},Enemy.OccupiedByLoot{archetype})
def phase_family() -> C.Family<Schema,Store,EnemyPhaseRest,Enemy.Phase,Enemy.Phase,EnemyPhaseToken,take_phase,put_phase,project_phase>: C.Family{"enemy-phase"}

type IdentityToken is Data: IdentityToken{}
type IdentityRest is Type:
  IdentityRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,pad0: U32,pad1: U32,pad2: U32,shots: Col.Column<Schema,Components.ShotPayload>}
  IdentityRestWrapped{inner: IdentityRest}
def take_identity(store: Store) -> IdentityRest & Col.Column<Schema,Components.Identity>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (IdentityRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,0,0,0,shots},identities)
    case Wrapped{inner}: take_identity(inner)
def put_identity(rest: IdentityRest,identities: Col.Column<Schema,Components.Identity>) -> Store:
  match rest:
    case IdentityRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,_,_,_,shots}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case IdentityRestWrapped{inner}: put_identity(inner,identities)
def project_identity(value: Components.Identity) -> Components.Identity & Components.Identity:
  match value:
    case Components.Identity{+slot}: (Components.Identity{slot},Components.Identity{slot})
def identity_family() -> C.Family<Schema,Store,IdentityRest,Components.Identity,Components.Identity,IdentityToken,take_identity,put_identity,project_identity>: C.Family{"enemy-identity"}

type ShotToken is Data: ShotToken{}
type ShotRest is Type:
  ShotRest{vitals: Col.Column<Schema,Components.Vitals>,motions: Col.Column<Schema,Components.Trajectory>,statuses: Col.Column<Schema,Components.Status>,pickups: Col.Column<Schema,Pickup.Payload>,roles: Col.Column<Schema,Role.Role>,movement: MovementRoster,candidates: CandidateRoster,players: Col.Column<Schema,Components.PlayerRecord>,spaces: Col.Column<Schema,Space.Spatial>,enemyPhases: Col.Column<Schema,Enemy.Phase>,identities: Col.Column<Schema,Components.Identity>,pad0: U32,pad1: U32,pad2: U32}
  ShotRestWrapped{inner: ShotRest}
def take_shot(store: Store) -> ShotRest & Col.Column<Schema,Components.ShotPayload>:
  match store:
    case Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}: (ShotRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,0,0,0},shots)
    case Wrapped{inner}: take_shot(inner)
def put_shot(rest: ShotRest,shots: Col.Column<Schema,Components.ShotPayload>) -> Store:
  match rest:
    case ShotRest{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,_,_,_}: Owned{StoreFields{vitals,motions,statuses,pickups,roles,movement,candidates,players,spaces,enemyPhases,identities,shots}}
    case ShotRestWrapped{inner}: put_shot(inner,shots)
def project_shot(value: Components.ShotPayload) -> Components.ShotPayload & Components.ShotPayload:
  match value:
    case Components.ShotPayload{+weapon,+damage,+active}: (Components.ShotPayload{weapon,damage,active},Components.ShotPayload{weapon,damage,active})
def shot_family() -> C.Family<Schema,Store,ShotRest,Components.ShotPayload,Components.ShotPayload,ShotToken,take_shot,put_shot,project_shot>: C.Family{"projectile-payload"}
