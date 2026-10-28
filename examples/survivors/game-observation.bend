import Base
import run-state.bend as RS
import enemy-combat.bend as Enemy
import projectile-state.bend as Shot
import pickup-state.bend as Pickup
import enemy-spatial.bend as Space
import arena.bend as A
import list-index.bend as ListIndex

type Run is Data: Run{session: RS.Session,player: RS.PlayerState}
# Player records are authoritative ECS payloads, separate from pooled actors.
# Run owns solo session and player state; co-op stores those authorities separately.
def run_session(value: Run) -> RS.Session:
  match value:
    case Run{session,_}: session
def run_player(value: Run) -> RS.PlayerState:
  match value:
    case Run{_,player}: player
type Offer is Data: Offer{kind: U32,id: U32,level: U32}
type Snapshot is Data:
  EnemySnapshot{enemy: Enemy.State}
  ProjectileSnapshot{projectile: Shot.State}
  PickupSnapshot{pickup: Pickup.State}
# Common geometry contains no overloaded health, damage or reward payload.
type SnapshotGeometry is Data: SnapshotGeometry{identity: U32,x: F32,y: F32,age: U32,radius: F32}
def snapshot_geometry(snapshot: Snapshot) -> SnapshotGeometry:
  match snapshot:
    case ProjectileSnapshot{Shot.State{Space.Spatial{x,y,age,radius},identity,_,_,_}}: SnapshotGeometry{identity,x,y,age,radius}
    case EnemySnapshot{Enemy.State{Space.Spatial{x,y,age,radius},_,identity,_,_}}: SnapshotGeometry{identity,x,y,age,radius}
    case PickupSnapshot{Pickup.State{Space.Spatial{x,y,age,radius},_,identity}}: SnapshotGeometry{identity,x,y,age,radius}
def geometry_identity(geometry: SnapshotGeometry) -> U32:
  match geometry:
    case SnapshotGeometry{identity,_,_,_,_}: identity
def snapshot_identity(snapshot: Snapshot) -> U32: geometry_identity(snapshot_geometry(snapshot))
def geometry_age(geometry: SnapshotGeometry) -> U32:
  match geometry:
    case SnapshotGeometry{_,_,_,age,_}: age
def snapshot_age(snapshot: Snapshot) -> U32: geometry_age(snapshot_geometry(snapshot))
def enemy_observations(snapshots: List<&2,Snapshot>) -> List<&2,Enemy.State>:
  match snapshots:
    case []: []
    case EnemySnapshot{enemy} <> rest: enemy <> enemy_observations(rest)
    case _ <> rest: enemy_observations(rest)
def pickup_observations(snapshots: List<&2,Snapshot>) -> List<&2,Pickup.State>:
  match snapshots:
    case []: []
    case PickupSnapshot{+pickup} <> rest: List.filter.put(Pickup.State,pickup,pickup_observations(rest),Pickup.active(pickup))
    case _ <> rest: pickup_observations(rest)
def at(values: List<&2,U32>,index: U32) -> U32:
  ListIndex.at(values,index)
def world_size() -> F32: A.size()
def world_center() -> F32: A.center()
def world_margin() -> F32: A.player_min()
def meta_max(id: U32) -> U32:
  match id:
    case 3: 3
    case 9: 2
    case _: 5
def meta_rank(+meta: U32,+id: U32) -> U32: U32.min(meta_max(id),(U32.shrn(meta,U32.to_nat((id * 3 : U32))) % 8 : U32))
def stat_bonus(+arcana: U32,+wanted: U32) -> F32: U32.to_f32(Bool.to_u32(U32.is_eq(arcana,wanted)))
def speed_bonus(+passives: List<&2,U32>,+meta: U32,+arcana: U32,+character: U32) -> F32:
  ((1.0 + U32.to_f32(at(passives,5)) * 0.10 + U32.to_f32(meta_rank(meta,5)) * 0.05 + 0.15 * U32.to_f32(Bool.to_u32(U32.is_eq(character,1))) + 0.30 * stat_bonus(arcana,10)) * (1.0 - 0.15 * stat_bonus(arcana,2)) : F32)
def area_bonus(+passives: List<&2,U32>,+arcana: U32,+level: U32) -> F32:
  ((1.0 + U32.to_f32(at(passives,2)) * 0.10 + 0.35 * stat_bonus(arcana,2) + 0.15 * stat_bonus(arcana,11) + U32.to_f32(level) * 0.025) * (1.0 - 0.15 * stat_bonus(arcana,1)) * (1.0 + 0.35 * U32.to_f32(Bool.to_u32(U32.is_le(9,level)))) : F32)
def duration_bonus(+passives: List<&2,U32>,+arcana: U32) -> F32: (1.0 + U32.to_f32(at(passives,3)) * 0.15 + 0.50 * stat_bonus(arcana,7) : F32)
def projectile_speed(+passives: List<&2,U32>,+arcana: U32) -> F32: ((1.0 + U32.to_f32(at(passives,12)) * 0.15 + 0.50 * stat_bonus(arcana,8)) * (1.0 - 0.20 * stat_bonus(arcana,7)) : F32)
def run_phase(run: Run) -> U32:
  match run:
    case Run{RS.Session{phase,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: phase
def run_tick(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,tick,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: tick
def run_px(run: Run) -> F32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{px,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: px
def run_py(run: Run) -> F32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,py,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: py
def run_hp(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,hp,_,_,_,_,_,_,_,_,_,_,_,_,_}}: hp
def run_maxHp(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,maxHp,_,_,_,_,_,_,_,_,_,_,_,_}}: maxHp
def run_xp(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,xp,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: xp
def run_xpNeed(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,xpNeed,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: xpNeed
def run_level(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,level,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: level
def run_kills(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,kills,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: kills
def run_gold(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,gold,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: gold
def run_character(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,character,_,_,_,_,_,_,_,_,_,_,_}}: character
def run_weapons(run: Run) -> List<&2,U32>:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,weapons,_,_,_,_,_,_,_,_,_,_}}: weapons
def run_passives(run: Run) -> List<&2,U32>:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,passives,_,_,_,_,_,_,_,_,_}}: passives
def run_invuln(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,invuln,_,_,_,_,_,_,_,_}}: invuln
def run_seed(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,seed,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: seed
def run_stage(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,stage,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: stage
def run_arcana(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,arcana,_,_,_,_,_,_,_}}: arcana
def run_meta(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,meta,_,_,_,_,_,_}}: meta
def run_revivals(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,revivals,_,_,_,_,_}}: revivals
def run_bosses(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,bosses,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: bosses
def run_mode(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,mode,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: mode
def run_rerolls(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,rerolls,_,_,_,_}}: rerolls
def run_banishes(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,banishes,_,_,_}}: banishes
def run_skips(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,skips,_,_}}: skips
def run_bannedWeapons(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,bannedWeapons,_}}: bannedWeapons
def run_bannedPassives(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,bannedPassives}}: bannedPassives
def run_enemyKinds(run: Run) -> List<&2,U32>:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,enemyKinds,_},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: enemyKinds
def run_relicCollected(run: Run) -> U32:
  match run:
    case Run{RS.Session{_,_,_,_,_,_,_,_,_,_,_,_,relicCollected},RS.PlayerState{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: relicCollected
