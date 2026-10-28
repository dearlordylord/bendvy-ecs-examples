import game-observation.bend as Model
import run-state.bend as RS
import Base
import enemy-effects.bend as Effect
import enemy-status-encoder.bend as StatusEncoder
import pickup-state.bend as Pickup
import enemy-combat.bend as Enemy
import game-components.bend as Components
import projectile-state.bend as Shot
import game-storage.bend as Storage
import game.bend as G
import enemy-spatial.bend as Space
import pools.bend as PL
import entity-role.bend as GRole
import bendvy-ecs-core@0.1.0.2/world.bend as W
import bendvy-ecs-core@0.1.0.2/column.bend as Col
import bendvy-ecs-core@0.1.0.2/lifecycle.bend as L
import bendvy-ecs-core@0.1.0.2/change_tick.bend as Tick
import bendvy-ecs-core@0.1.0.2/clock_state.bend as Clock
import bendvy-ecs-core@0.1.0.2/entity_allocator.bend as A
import bendvy-ecs-core@0.1.0.2/entity_key.bend as K
import bendvy-ecs-core@0.1.0.2/deferred_command.bend as Deferred

# Development-only exact observer. It returns the same affine owners.
# Every float is its raw U32 bit pattern; lifecycle metadata is not normalized.
def fbits(value: F32) -> String: U32.show(F32.bits(value))
def join(rows: List<&2,String>) -> String:
  match rows:
    case []: ""
    case value <> []: value
    case value <> rest: value ++ "," ++ join(rest)
def array(rows: List<&2,String>) -> String: "[" ++ join(rows) ++ "]"
def nums(rows: List<&2,U32>) -> String:
  match rows:
    case []: ""
    case value <> []: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ nums(rest)
def u32s(rows: List<&2,U32>) -> String: "[" ++ nums(rows) ++ "]"
def codes(text: String) -> List<&2,U32>:
  match text:
    case SNil{}: []
    case SCon{Chr{code},rest}: code <> codes(rest)
def tick(value: Tick.Tick) -> String:
  match value:
    case Tick.Tick{epoch,low}: "[" ++ Nat.show(epoch) ++ "," ++ U32.show(low) ++ "]"
def ticks(rows: List<&2,Tick.Tick>) -> String:
  match rows:
    case []: ""
    case value <> []: tick(value)
    case value <> rest: tick(value) ++ "," ++ ticks(rest)
def maybe_tick(value: Maybe<&2,Tick.Tick>) -> String:
  match value:
    case None{}: "null"
    case Some{value}: tick(value)
def stamp(value: L.Stamp) -> String:
  match value:
    case L.Stamp{added,changed}: array([maybe_tick(added),maybe_tick(changed)])
def spatial(value: Space.Spatial) -> String:
  match value:
    case Space.Spatial{x,y,age,radius}: array([fbits(x),fbits(y),U32.show(age),fbits(radius)])
def vitals(value: Components.Vitals) -> String:
  match value:
    case Components.Vitals{health,maximum}: array([U32.show(health),U32.show(maximum)])
def enemy_phase(value: Enemy.Phase) -> String:
  match value:
    case Enemy.Dormant{archetype}: array(["0",U32.show(archetype)])
    case Enemy.ActiveEnemy{archetype}: array(["1",U32.show(archetype)])
    case Enemy.OccupiedByLoot{archetype}: array(["2",U32.show(archetype)])
def identity(value: Components.Identity) -> String:
  match value:
    case Components.Identity{slot}: U32.show(slot)
def enemy_status(value: Components.Status) -> String:
  match value:
    case Components.Status{slow,burn}: StatusEncoder.encode(Components.Status{slow,burn})
def enemy(value: Enemy.State) -> String:
  match value:
    case Enemy.State{space,archetype,slot,hp,status}: "{\"spatial\":" ++ spatial(space) ++ ",\"archetype\":" ++ U32.show(archetype) ++ ",\"identity\":" ++ U32.show(slot) ++ ",\"vitals\":" ++ vitals(hp) ++ ",\"status\":" ++ enemy_status(status) ++ "}"
def offer(value: Model.Offer) -> String:
  match value:
    case Model.Offer{kind,id,level}: array([U32.show(kind),U32.show(id),U32.show(level)])
def projectile_side(value: Shot.Side) -> String:
  match value:
    case Shot.PlayerShot{}: "\"player\""
    case Shot.HostileShot{}: "\"hostile\""
def source_player(value: Maybe<&2,U32>) -> String:
  match value:
    case None{}: "null"
    case Some{player}: U32.show(player)
def projectile_state(value: Shot.State) -> String:
  match value:
    case Shot.State{Space.Spatial{x,y,age,radius},identity,side,Components.ShotPayload{weapon,damage,active},Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,+sourcePlayer}}:
      "{\"spatial\":" ++ array([fbits(x),fbits(y),U32.show(age),fbits(radius)]) ++ ",\"identity\":" ++ U32.show(identity) ++ ",\"side\":" ++ projectile_side(side) ++ ",\"payload\":" ++ array([U32.show(weapon),U32.show(damage),U32.show(Bool.to_u32(active))]) ++ ",\"trajectory\":" ++ array([fbits(vx),fbits(vy),U32.show(life),U32.show(pierce),u32s(visited),U32.show(owner),U32.show(slot),source_player(sourcePlayer)]) ++ "}"
def pickup_item(value: Pickup.Item) -> String:
  match value:
    case Pickup.Xp{amount,accumulator}: array(["0",U32.show(amount),U32.show(Bool.to_u32(accumulator))])
    case Pickup.Gold{coins}: array(["1",U32.show(coins)])
    case Pickup.Healing{health}: array(["2",U32.show(health)])
    case Pickup.Chest{}: "[3]"
    case Pickup.Relic{stage}: array(["4",U32.show(stage)])
def pickup(value: Pickup.Payload) -> String:
  match value:
    case Pickup.Payload{item,generation,active}: array([pickup_item(item),U32.show(generation),U32.show(Bool.to_u32(active))])
def pickup_state(value: Pickup.State) -> String:
  match value:
    case Pickup.State{space,payload,identity}: "{\"spatial\":" ++ spatial(space) ++ ",\"identity\":" ++ U32.show(identity) ++ ",\"payload\":" ++ pickup(payload) ++ "}"
def snapshot_row(value: Model.Snapshot) -> String:
  match value:
    case Model.ProjectileSnapshot{projectile}: "{\"projectile\":" ++ projectile_state(projectile) ++ "}"
    case Model.EnemySnapshot{value}: "{\"enemy\":" ++ enemy(value) ++ "}"
    case Model.PickupSnapshot{value}: "{\"pickup\":" ++ pickup_state(value) ++ "}"
def offers_items(rows: List<&2,Model.Offer>) -> String:
  match rows:
    case []: ""
    case value <> []: offer(value)
    case value <> rest: offer(value) ++ "," ++ offers_items(rest)
def offers(rows: List<&2,Model.Offer>) -> String: "[" ++ offers_items(rows) ++ "]"
def snapshots_items(rows: List<&2,Model.Snapshot>) -> String:
  match rows:
    case []: ""
    case value <> []: snapshot_row(value)
    case value <> rest: snapshot_row(value) ++ "," ++ snapshots_items(rest)
def snapshots(rows: List<&2,Model.Snapshot>) -> String: "[" ++ snapshots_items(rows) ++ "]"
def run(value: Model.Run) -> String:
  match value:
    case Model.Run{RS.Session{phase,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maximum,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}: array([U32.show(phase),U32.show(tick),fbits(px),fbits(py),U32.show(hp),U32.show(maximum),U32.show(xp),U32.show(need),U32.show(level),U32.show(kills),U32.show(gold),U32.show(character),u32s(weapons),u32s(passives),U32.show(invuln),U32.show(seed),U32.show(stage),U32.show(arcana),U32.show(meta),U32.show(revivals),U32.show(bosses),U32.show(mode),U32.show(rerolls),U32.show(banishes),U32.show(skips),U32.show(bannedWeapons),U32.show(bannedPassives),u32s(enemyKinds),U32.show(relicCollected)])
def maybe_value(~T: Data,~show: T -> String,value: Maybe<&2,T>) -> String:
  match value:
    case None{}: "null"
    case Some{value}: show(value)
def column_finish(~C: Type,+id: U32,value: String,result: Col.Column<Storage.Schema,C> & L.Stamp) -> Col.Column<Storage.Schema,C> & String:
  match result:
    case (column,metadata): (column,array([U32.show(id),value,stamp(metadata)]))
def column_value(~C: Type,~V: Data,~show: V -> String,+id: U32,result: Col.Column<Storage.Schema,C> & Maybe<&2,V>) -> Col.Column<Storage.Schema,C> & String:
  match result:
    case (column,value): column_finish(~C,id,maybe_value(~V,~show,value),Col.lifecycle(~Storage.Schema,~C,column,id))
# Keep traversal tail-recursive: nested per-row continuations overflow the JS
# host stack on an ordinary initialized world before the first full comparison.
def column_row_accumulated(~C: Type,reversed: List<&2,String>,result: Col.Column<Storage.Schema,C> & String) -> Col.Column<Storage.Schema,C> & List<&2,String>:
  match result:
    case (column,text): (column,text <> reversed)
def column_rows_loop(~C: Type,~V: Data,~project: C -> C & V,~show: V -> String,fuel: Nat,+id: U32,state: Col.Column<Storage.Schema,C> & List<&2,String>) -> Col.Column<Storage.Schema,C> & String:
  match fuel state:
    case 0n Tuple{column,reversed}: (column,join(List.reverse(&2,String,reversed)))
    case 1n+rest Tuple{column,reversed}: column_rows_loop(~C,~V,~project,~show,rest,(id + 1 : U32),column_row_accumulated(~C,reversed,column_value(~C,~V,~show,id,Col.view(~Storage.Schema,~C,~V,~project,column,id))))
def column_rows(~C: Type,~V: Data,~project: C -> C & V,~show: V -> String,fuel: Nat,id: U32,column: Col.Column<Storage.Schema,C>) -> Col.Column<Storage.Schema,C> & String:
  column_rows_loop(~C,~V,~project,~show,fuel,id,(column,[]))
def roster_handle(value: W.Handle<Storage.Schema>) -> String:
  match value:
    case W.Handle{namespace,K.EntityKey{id,generation}}: array([U32.show(namespace),U32.show(id),U32.show(generation)])
def roster_handles(rows: List<&2,W.Handle<Storage.Schema>>) -> String:
  match rows:
    case []: ""
    case value <> []: roster_handle(value)
    case value <> rest: roster_handle(value) ++ "," ++ roster_handles(rest)
def movement_roster(value: Storage.MovementRoster) -> String:
  match value:
    case Storage.MovementPrepared{handles}: "[" ++ roster_handles(handles) ++ "]"
# Physical columns retain their actual membership and change stamps. Logical
def shot_payload(value: Components.ShotPayload) -> String:
  match value:
    case Components.ShotPayload{weapon,damage,active}: array([U32.show(weapon),U32.show(damage),U32.show(Bool.to_u32(active))])
def trajectory(value: Components.Trajectory) -> String:
  match value:
    case Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,+sourcePlayer}: array([fbits(vx),fbits(vy),U32.show(life),U32.show(pierce),u32s(visited),U32.show(owner),U32.show(slot),source_player(sourcePlayer)])
def status(value: Components.Status) -> String:
  match value:
    case Components.Status{slow,burn}: StatusEncoder.encode(Components.Status{slow,burn})
def role(value: GRole.Role) -> String:
  match value:
    case GRole.EnemySlot{}: "\"EnemySlot\""
    case GRole.RelicSlot{}: "\"RelicSlot\""
    case GRole.PlayerProjectileSlot{}: "\"PlayerProjectileSlot\""
    case GRole.HostileProjectileSlot{}: "\"HostileProjectileSlot\""
    case GRole.XpSlot{}: "\"XpSlot\""
    case GRole.OutsideSlot{}: "\"OutsideSlot\""
def candidate_roster(projectile: Bool,value: Storage.CandidateRoster) -> String:
  match projectile value:
    case True{} Storage.CandidatesPrepared{projectiles,_}: "[" ++ roster_handles(projectiles) ++ "]"
    case False{} Storage.CandidatesPrepared{_,pool}: "[" ++ roster_handles(pool) ++ "]"
def observed_column_done(~C: Type,~Rest: Type,~put: Rest -> Col.Column<Storage.Schema,C> -> Storage.Store,rest: Rest,result: Col.Column<Storage.Schema,C> & String) -> Storage.Store & String:
  match result:
    case (column,text): (put(rest,column),text)
def observed_column_split(~C: Type,~V: Data,~Rest: Type,~put: Rest -> Col.Column<Storage.Schema,C> -> Storage.Store,~project: C -> C & V,~show: V -> String,result: Rest & Col.Column<Storage.Schema,C>) -> Storage.Store & String:
  match result:
    case (rest,column): observed_column_done(~C,~Rest,~put,rest,column_rows(~C,~V,~project,~show,PL.total_nat(),1,column))
def observed_column(~C: Type,~V: Data,~Rest: Type,~take: Storage.Store -> Rest & Col.Column<Storage.Schema,C>,~put: Rest -> Col.Column<Storage.Schema,C> -> Storage.Store,~project: C -> C & V,~show: V -> String,store: Storage.Store) -> Storage.Store & String:
  observed_column_split(~C,~V,~Rest,~put,~project,~show,take(store))
def store_logical_fields(vs: String,ts: String,ss: String,ps: String,rs: String,es: String,qs: String,phases: String,ids: String,owner: Storage.StoreFields) -> Storage.Store & String:
  match owner:
    case Storage.StoreFields{v,t,s,p,r,+movement,+candidates,players,spaces,enemyPhases,identities,shots}: (Storage.Owned{Storage.StoreFields{v,t,s,p,r,movement,candidates,players,spaces,enemyPhases,identities,shots}},"{\"vitals\":[" ++ vs ++ "],\"trajectories\":[" ++ ts ++ "],\"statuses\":[" ++ ss ++ "],\"pickups\":[" ++ ps ++ "],\"roles\":[" ++ rs ++ "],\"spaces\":[" ++ es ++ "],\"shots\":[" ++ qs ++ "],\"enemyPhases\":[" ++ phases ++ "],\"identities\":[" ++ ids ++ "],\"movementCandidates\":" ++ movement_roster(movement) ++ ",\"projectileCandidates\":" ++ candidate_roster(True{},candidates) ++ ",\"poolCandidates\":" ++ candidate_roster(False{},candidates) ++ "}")
def store_logical(vs: String,ts: String,ss: String,ps: String,rs: String,es: String,qs: String,phases: String,ids: String,owner: Storage.Store) -> Storage.Store & String: store_logical_fields(vs,ts,ss,ps,rs,es,qs,phases,ids,Storage.unseal(owner))
def store_shots(vs: String,ts: String,ss: String,ps: String,rs: String,es: String,phases: String,ids: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,qs): store_logical(vs,ts,ss,ps,rs,es,qs,phases,ids,owner)
def store_identity(vs: String,ts: String,ss: String,ps: String,rs: String,es: String,phases: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,ids): store_shots(vs,ts,ss,ps,rs,es,phases,ids,observed_column(~Components.ShotPayload,~Components.ShotPayload,~Storage.ShotRest,~Storage.take_shot,~Storage.put_shot,~Storage.project_shot,~shot_payload,owner))
def store_phase(vs: String,ts: String,ss: String,ps: String,rs: String,es: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,phases): store_identity(vs,ts,ss,ps,rs,es,phases,observed_column(~Components.Identity,~Components.Identity,~Storage.IdentityRest,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,~identity,owner))
def store_spatial(vs: String,ts: String,ss: String,ps: String,rs: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,es): store_phase(vs,ts,ss,ps,rs,es,observed_column(~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseRest,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~enemy_phase,owner))
def store_role(vs: String,ts: String,ss: String,ps: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,rs): store_spatial(vs,ts,ss,ps,rs,observed_column(~Space.Spatial,~Space.Spatial,~Storage.SpatialRest,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~spatial,owner))
def store_pickup(vs: String,ts: String,ss: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,ps): store_role(vs,ts,ss,ps,observed_column(~GRole.Role,~GRole.Role,~Storage.RoleRest,~Storage.take_role,~Storage.put_role,~Storage.project_role,~role,owner))
def store_status(vs: String,ts: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,ss): store_pickup(vs,ts,ss,observed_column(~Pickup.Payload,~Pickup.Payload,~Storage.PickupRest,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,~pickup,owner))
def store_trajectory(vs: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,ts): store_status(vs,ts,observed_column(~Components.Status,~Components.Status,~Storage.StatusRest,~Storage.take_status,~Storage.put_status,~Storage.project_status,~status,owner))
def store_vitals(result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,vs): store_trajectory(vs,observed_column(~Components.Trajectory,~Components.Trajectory,~Storage.TrajectoryRest,~Storage.take_trajectory,~Storage.put_trajectory,~Storage.project_trajectory,~trajectory,owner))
def store(value: Storage.Store) -> Storage.Store & String:
  store_vitals(observed_column(~Components.Vitals,~Components.Vitals,~Storage.VitalRest,~Storage.take_vitals,~Storage.put_vitals,~Storage.project_vitals,~vitals,value))
def player_record(value: Components.PlayerRecord) -> String:
  match value:
    case Components.PlayerRecord{id,RS.PlayerState{px,py,hp,maximum,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives},connected,reviveTick}: array([U32.show(id),array([fbits(px),fbits(py),U32.show(hp),U32.show(maximum),U32.show(character),u32s(weapons),u32s(passives),U32.show(invuln),U32.show(arcana),U32.show(meta),U32.show(revivals),U32.show(rerolls),U32.show(banishes),U32.show(skips),U32.show(bannedWeapons),U32.show(bannedPassives)]),U32.show(Bool.to_u32(connected)),U32.show(reviveTick)])
def store_players_text(players: String,result: Storage.Store & String) -> Storage.Store & String:
  match result:
    case (owner,text): (owner,"\"actorColumns\":" ++ text ++ ",\"players\":[" ++ players ++ "]")
def store_players_done(rest: Storage.PlayerRest,result: Col.Column<Storage.Schema,Components.PlayerRecord> & String) -> Storage.Store & String:
  match result:
    case (column,text): store_players_text(text,store(Storage.put_players(rest,column)))
def store_players_split(high: U32,result: Storage.PlayerRest & Col.Column<Storage.Schema,Components.PlayerRecord>) -> Storage.Store & String:
  match result:
    case (rest,column): store_players_done(rest,column_rows(~Components.PlayerRecord,~Components.PlayerRecord,~Storage.project_player,~player_record,U32.to_nat(high),1,column))
def store_players(high: U32,owner: Storage.Store) -> Storage.Store & String: store_players_split(high,Storage.take_players(owner))
def key(value: K.Key) -> String:
  match value:
    case K.EntityKey{id,generation}: array([U32.show(id),U32.show(generation)])
def keys(rows: List<&2,K.Key>) -> String:
  match rows:
    case []: ""
    case value <> []: key(value)
    case value <> rest: key(value) ++ "," ++ keys(rest)
def allocator_phase(value: A.Phase) -> String:
  match value:
    case A.Consumed{}: "0"
    case A.Pending{}: "1"
    case A.Live{}: "2"
    case A.DeadRetained{}: "3"
    case A.Free{}: "4"
def slot(value: A.Slot) -> String:
  match value:
    case A.Slot{generation,phase}: array([U32.show(generation),allocator_phase(phase)])
def slot_accumulated(reversed: List<&2,String>,result: Array<A.Slot> & A.Slot) -> Array<A.Slot> & List<&2,String>:
  match result:
    case (rows,value): (rows,slot(value) <> reversed)
def slots_loop(fuel: Nat,+index: U32,state: Array<A.Slot> & List<&2,String>) -> Array<A.Slot> & String:
  match fuel state:
    case 0n Tuple{rows,reversed}: (rows,join(List.reverse(&2,String,reversed)))
    case 1n+rest Tuple{rows,reversed}: slots_loop(rest,(index + 1 : U32),slot_accumulated(reversed,Array.get(A.Slot,rows,index)))
def slots(fuel: Nat,index: U32,rows: Array<A.Slot>) -> Array<A.Slot> & String:
  slots_loop(fuel,index,(rows,[]))
def allocator_finish(+next: U32,+high: U32,+capacity: U32,+depth: Nat,+free: List<&2,U32>,+order: List<&2,K.Key>,result: Array<A.Slot> & String) -> A.Allocator & String:
  match result:
    case (rows,text): (A.Allocator{next,high,rows,capacity,depth,free,order},array([U32.show(next),U32.show(high),U32.show(capacity),Nat.show(depth),u32s(free),"[" ++ keys(order) ++ "]","[" ++ text ++ "]"]))
def allocator(value: A.Allocator) -> A.Allocator & String:
  match value:
    case A.Allocator{next,high,rows,+capacity,depth,free,order}: allocator_finish(next,high,capacity,depth,free,order,slots(U32.to_nat(capacity),0,rows))
def clock(value: Clock.State) -> String:
  match value:
    case Clock.State{now,scopes}: array([tick(now),"[" ++ ticks(scopes) ++ "]"])
def strings(rows: List<&2,String>) -> String:
  match rows:
    case []: ""
    case value <> []: u32s(codes(value))
    case value <> rest: u32s(codes(value)) ++ "," ++ strings(rest)
def registration(value: W.RegistrationMeta) -> String:
  match value:
    case W.RegistrationMeta{id,name,access}: array([U32.show(id),u32s(codes(name)),"[" ++ strings(access) ++ "]"])
def registrations(rows: List<&2,W.RegistrationMeta>) -> String:
  match rows:
    case []: ""
    case value <> []: registration(value)
    case value <> rest: registration(value) ++ "," ++ registrations(rest)
def world_allocator(+namespace: U32,store: Storage.Store,resource: Unit,+events: List<&2,Unit>,pending: List<Deferred.Command<Storage.World()>>,+regs: List<&2,W.RegistrationMeta>,+next: U32,+time: Clock.State,pendingCount: U32,result: A.Allocator & String) -> Storage.World() & String:
  match result:
    case (alloc,text): (W.World{namespace,alloc,store,resource,events,pending,regs,next,time},"{\"namespace\":" ++ U32.show(namespace) ++ ",\"allocator\":" ++ text ++ ",\"clock\":" ++ clock(time) ++ ",\"events\":" ++ Nat.show(List.length(&2,Unit,events)) ++ ",\"pendingCommands\":" ++ U32.show(pendingCount) ++ ",\"registrations\":[" ++ registrations(regs) ++ "],\"nextSystemId\":" ++ U32.show(next) ++ "}")
def world_counted(result: Storage.World() & U32) -> Storage.World() & String:
  match result:
    case (W.World{namespace,alloc,store,resource,events,pending,regs,next,time},count): world_allocator(namespace,store,resource,events,pending,regs,next,time,count,allocator(alloc))
def world(value: Storage.World()) -> Storage.World() & String:
  world_counted(W.pending_count(~Storage.Schema,~Storage.Store,~Unit,~Unit,value))
def metadata_join(componentText: String,result: Storage.World() & String) -> Storage.World() & String:
  match result:
    case (owner,text): (owner,"\"components\":" ++ componentText ++ ",\"metadata\":" ++ text)
def world_columns_done(namespace: U32,alloc: A.Allocator,resource: Unit,events: List<&2,Unit>,pending: List<Deferred.Command<Storage.World()>>,regs: List<&2,W.RegistrationMeta>,next: U32,time: Clock.State,result: Storage.Store & String) -> Storage.World() & String:
  match result:
    case (owner,text): (W.World{namespace,alloc,owner,resource,events,pending,regs,next,time},"{" ++ text ++ "}")
def world_columns(value: Storage.World()) -> Storage.World() & String:
  match value:
    case W.World{namespace,A.Allocator{nextId,+high,rows,capacity,depth,free,order},owner,resource,events,pending,regs,next,time}: world_columns_done(namespace,A.Allocator{nextId,high,rows,capacity,depth,free,order},resource,events,pending,regs,next,time,store_players(high,owner))
def world_components(result: Storage.World() & String) -> Storage.World() & String:
  match result:
    case (owner,text): metadata_join(text,world(owner))
def snapshot_finish(+runValue: Model.Run,+off: List<&2,Model.Offer>,+shots: List<&2,Model.Snapshot>,+pending: List<&2,U32>,result: Storage.World() & String) -> G.State & String:
  match result:
    case (owner,text): (G.State{owner,runValue,off,shots,pending},"{\"run\":" ++ run(runValue) ++ ",\"offers\":" ++ offers(off) ++ ",\"snapshots\":" ++ snapshots(shots) ++ ",\"pending\":" ++ u32s(pending) ++ "," ++ text ++ "}")
def snapshot(value: G.State) -> G.State & String:
  match value:
    case G.State{owner,runValue,off,shots,pending}: snapshot_finish(runValue,off,shots,pending,world_components(world_columns(owner)))

# Nonserializing completion barrier used ONCE per timed window, never per tick.
# Its rolling word value is observable but is not a correctness hash. Full exact
# observation remains outside the clock. Each native scalar must reach this
# result before the stop-clock continuation captures the U32 digest.
def mix(acc: U32,value: U32) -> U32: U32.xor((acc * 16777619 : U32),value)
def fold_words(rows: List<&2,U32>,acc: U32) -> U32:
  match rows:
    case []: acc
    case value <> rest: fold_words(rest,mix(acc,value))
def fold_tick(value: Tick.Tick,acc: U32) -> U32:
  match value:
    case Tick.Tick{epoch,low}: mix(mix(acc,U32.from_nat(epoch)),low)
def fold_maybe_tick(value: Maybe<&2,Tick.Tick>,acc: U32) -> U32:
  match value:
    case None{}: mix(acc,0)
    case Some{value}: fold_tick(value,mix(acc,1))
def fold_stamp(value: L.Stamp,acc: U32) -> U32:
  match value:
    case L.Stamp{added,changed}: fold_maybe_tick(changed,fold_maybe_tick(added,acc))
def fold_vitals(value: Components.Vitals,acc: U32) -> U32:
  match value:
    case Components.Vitals{health,maximum}: fold_words([health,maximum],acc)
def fold_offer(value: Model.Offer,acc: U32) -> U32:
  match value:
    case Model.Offer{kind,id,level}: fold_words([kind,id,level],acc)
def fold_projectile_side(value: Shot.Side) -> U32:
  match value:
    case Shot.PlayerShot{}: 0
    case Shot.HostileShot{}: 1
def fold_shot_payload(value: Components.ShotPayload,acc: U32) -> U32:
  match value:
    case Components.ShotPayload{weapon,damage,active}: fold_words([weapon,damage,Bool.to_u32(active)],acc)
def fold_spatial(value: Space.Spatial,acc: U32) -> U32:
  match value:
    case Space.Spatial{x,y,age,radius}: fold_words([F32.bits(x),F32.bits(y),age,F32.bits(radius)],acc)
def fold_burn_source(value: Maybe<&2,U32>,acc: U32) -> U32:
  match value:
    case None{}: mix(acc,0)
    case Some{player}: mix(mix(acc,1),player)
def fold_status(value: Components.Status,acc: U32) -> U32:
  match value:
    case Components.Status{Effect.Slow{ticks,frozen},Effect.Burn{duration,source}}: fold_burn_source(source,fold_words([ticks,Bool.to_u32(frozen),duration],acc))
def fold_pickup(value: Pickup.Payload,acc: U32) -> U32:
  match value:
    case Pickup.Payload{item,generation,active}: fold_words([generation,Bool.to_u32(active)],fold_words(codes(pickup_item(item)),acc))
def fold_source(value: Maybe<&2,U32>) -> U32:
  match value:
    case None{}: 4294967295
    case Some{player}: player
def fold_snapshot(value: Model.Snapshot,acc: U32) -> U32:
  match value:
    case Model.ProjectileSnapshot{Shot.State{Space.Spatial{x,y,age,radius},identity,side,Components.ShotPayload{weapon,damage,active},Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,+sourcePlayer}}}: fold_words(visited,fold_words([F32.bits(x),F32.bits(y),age,F32.bits(radius),identity,fold_projectile_side(side),weapon,damage,Bool.to_u32(active),F32.bits(vx),F32.bits(vy),life,pierce,owner,slot,fold_source(sourcePlayer)],acc))
    case Model.EnemySnapshot{Enemy.State{space,archetype,slot,hp,status}}: fold_status(status,fold_vitals(hp,fold_words([archetype,slot],fold_spatial(space,acc))))
    case Model.PickupSnapshot{Pickup.State{space,payload,identity}}: fold_pickup(payload,mix(fold_spatial(space,acc),identity))
def fold_offers(rows: List<&2,Model.Offer>,acc: U32) -> U32:
  match rows:
    case []: mix(acc,0)
    case value <> rest: fold_offers(rest,fold_offer(value,mix(acc,1)))
def fold_snapshots(rows: List<&2,Model.Snapshot>,acc: U32) -> U32:
  match rows:
    case []: mix(acc,0)
    case value <> rest: fold_snapshots(rest,fold_snapshot(value,mix(acc,1)))
def fold_run(value: Model.Run,acc: U32) -> U32:
  match value:
    case Model.Run{RS.Session{phase,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected},RS.PlayerState{px,py,hp,maximum,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}}: fold_words(enemyKinds,fold_words(passives,fold_words(weapons,fold_words([phase,tick,F32.bits(px),F32.bits(py),hp,maximum,xp,need,level,kills,gold,character,invuln,seed,stage,arcana,meta,revivals,bosses,mode,rerolls,banishes,skips,bannedWeapons,bannedPassives,relicCollected],acc))))
def fold_present(~V: Data,~fold: V -> U32 -> U32,value: Maybe<&2,V>,acc: U32) -> U32:
  match value:
    case None{}: mix(acc,0)
    case Some{value}: fold(value,mix(acc,1))
def force_column_metadata(~C: Type,acc: U32,result: Col.Column<Storage.Schema,C> & L.Stamp) -> Col.Column<Storage.Schema,C> & U32:
  match result:
    case (column,metadata): (column,fold_stamp(metadata,acc))
def force_column_value(~C: Type,~V: Data,~fold: V -> U32 -> U32,+id: U32,acc: U32,result: Col.Column<Storage.Schema,C> & Maybe<&2,V>) -> Col.Column<Storage.Schema,C> & U32:
  match result:
    case (column,value): force_column_metadata(~C,fold_present(~V,~fold,value,acc),Col.lifecycle(~Storage.Schema,~C,column,id))
def force_column_next(~C: Type,result: Col.Column<Storage.Schema,C> & U32,use: Col.Column<Storage.Schema,C> -> U32 -> Col.Column<Storage.Schema,C> & U32) -> Col.Column<Storage.Schema,C> & U32:
  match result:
    case (column,acc): use(column)(acc)
def force_column(~C: Type,~V: Data,~project: C -> C & V,~fold: V -> U32 -> U32,fuel: Nat,+id: U32,column: Col.Column<Storage.Schema,C>,acc: U32) -> Col.Column<Storage.Schema,C> & U32:
  match fuel:
    case 0n: (column,acc)
    case 1n+rest: force_column_next(~C,force_column_value(~C,~V,~fold,id,mix(acc,id),Col.view(~Storage.Schema,~C,~V,~project,column,id)),(column => acc => force_column(~C,~V,~project,~fold,rest,(id + 1 : U32),column,acc)))
def fold_roster_handle(value: W.Handle<Storage.Schema>,acc: U32) -> U32:
  match value:
    case W.Handle{namespace,K.EntityKey{id,generation}}: mix(mix(mix(acc,namespace),id),generation)
def fold_roster_handles(rows: List<&2,W.Handle<Storage.Schema>>,acc: U32) -> U32:
  match rows:
    case []: acc
    case value <> rest: fold_roster_handles(rest,fold_roster_handle(value,acc))
def fold_movement_roster(value: Storage.MovementRoster,acc: U32) -> U32:
  match value:
    case Storage.MovementPrepared{handles}: fold_roster_handles(handles,mix(acc,1))
def fold_trajectory(value: Components.Trajectory,acc: U32) -> U32:
  match value:
    case Components.Trajectory{vx,vy,life,pierce,visited,owner,slot,+sourcePlayer}: fold_words(visited,fold_words([F32.bits(vx),F32.bits(vy),life,pierce,owner,slot,fold_source(sourcePlayer)],acc))
def fold_role(value: GRole.Role,acc: U32) -> U32: fold_words(codes(role(value)),acc)
def fold_candidate_roster(value: Storage.CandidateRoster,acc: U32) -> U32:
  match value:
    case Storage.CandidatesPrepared{projectiles,pool}: fold_roster_handles(pool,mix(fold_roster_handles(projectiles,mix(acc,1)),2))
def force_column_done(~C: Type,~Rest: Type,~put: Rest -> Col.Column<Storage.Schema,C> -> Storage.Store,rest: Rest,result: Col.Column<Storage.Schema,C> & U32) -> Storage.Store & U32:
  match result:
    case (column,acc): (put(rest,column),acc)
def force_column_split(~C: Type,~V: Data,~Rest: Type,~put: Rest -> Col.Column<Storage.Schema,C> -> Storage.Store,~project: C -> C & V,~fold: V -> U32 -> U32,acc: U32,result: Rest & Col.Column<Storage.Schema,C>) -> Storage.Store & U32:
  match result:
    case (rest,column): force_column_done(~C,~Rest,~put,rest,force_column(~C,~V,~project,~fold,PL.total_nat(),1,column,acc))
def force_store_column(~C: Type,~V: Data,~Rest: Type,~take: Storage.Store -> Rest & Col.Column<Storage.Schema,C>,~put: Rest -> Col.Column<Storage.Schema,C> -> Storage.Store,~project: C -> C & V,~fold: V -> U32 -> U32,acc: U32,store: Storage.Store) -> Storage.Store & U32:
  force_column_split(~C,~V,~Rest,~put,~project,~fold,acc,take(store))
def force_store_routing_fields(result: Storage.StoreFields & U32) -> Storage.Store & U32:
  match result:
    case (Storage.StoreFields{v,t,s,p,r,+movement,+candidates,players,spaces,enemyPhases,identities,shots},acc): (Storage.Owned{Storage.StoreFields{v,t,s,p,r,movement,candidates,players,spaces,enemyPhases,identities,shots}},fold_candidate_roster(candidates,fold_movement_roster(movement,acc)))
def force_store_routing(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_routing_fields((Storage.unseal(owner),acc))
def fold_phase(value: Enemy.Phase,acc: U32) -> U32: fold_words(codes(enemy_phase(value)),acc)
def fold_identity(value: Components.Identity,acc: U32) -> U32:
  match value:
    case Components.Identity{slot}: mix(acc,slot)
def force_store_shots(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_routing(force_store_column(~Components.ShotPayload,~Components.ShotPayload,~Storage.ShotRest,~Storage.take_shot,~Storage.put_shot,~Storage.project_shot,~fold_shot_payload,acc,owner))
def force_store_identity(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_shots(force_store_column(~Components.Identity,~Components.Identity,~Storage.IdentityRest,~Storage.take_identity,~Storage.put_identity,~Storage.project_identity,~fold_identity,acc,owner))
def force_store_phase(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_identity(force_store_column(~Enemy.Phase,~Enemy.Phase,~Storage.EnemyPhaseRest,~Storage.take_phase,~Storage.put_phase,~Storage.project_phase,~fold_phase,acc,owner))
def force_store_role(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_phase(force_store_column(~Space.Spatial,~Space.Spatial,~Storage.SpatialRest,~Storage.take_spatial,~Storage.put_spatial,~Storage.project_spatial,~fold_spatial,acc,owner))
def force_store_pickup(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_role(force_store_column(~GRole.Role,~GRole.Role,~Storage.RoleRest,~Storage.take_role,~Storage.put_role,~Storage.project_role,~fold_role,acc,owner))
def force_store_status(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_pickup(force_store_column(~Pickup.Payload,~Pickup.Payload,~Storage.PickupRest,~Storage.take_pickup,~Storage.put_pickup,~Storage.project_pickup,~fold_pickup,acc,owner))
def force_store_trajectory(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_status(force_store_column(~Components.Status,~Components.Status,~Storage.StatusRest,~Storage.take_status,~Storage.put_status,~Storage.project_status,~fold_status,acc,owner))
def force_store_vitals(result: Storage.Store & U32) -> Storage.Store & U32:
  match result:
    case (owner,acc): force_store_trajectory(force_store_column(~Components.Trajectory,~Components.Trajectory,~Storage.TrajectoryRest,~Storage.take_trajectory,~Storage.put_trajectory,~Storage.project_trajectory,~fold_trajectory,acc,owner))
def force_store(value: Storage.Store) -> Storage.Store & U32:
  force_store_vitals(force_store_column(~Components.Vitals,~Components.Vitals,~Storage.VitalRest,~Storage.take_vitals,~Storage.put_vitals,~Storage.project_vitals,~fold_vitals,2166136261,value))
def force_world_clock(acc: U32,result: Storage.World() & Tick.Tick) -> Storage.World() & U32:
  match result:
    case (owner,time): (owner,fold_tick(time,acc))
def force_world(result: Storage.World() & U32) -> Storage.World() & U32:
  match result:
    case (owner,acc): force_world_clock(acc,W.clock(~Storage.Schema,~Storage.Store,~Unit,~Unit,owner))
def force_finish(+runValue: Model.Run,+off: List<&2,Model.Offer>,+shots: List<&2,Model.Snapshot>,+pending: List<&2,U32>,result: Storage.World() & U32) -> G.State & U32:
  match result:
    case (owner,acc): (G.State{owner,runValue,off,shots,pending},fold_words(pending,fold_snapshots(shots,fold_offers(off,fold_run(runValue,acc)))))
def force(value: G.State) -> G.State & U32:
  match value:
    case G.State{owner,runValue,off,shots,pending}: force_finish(runValue,off,shots,pending,force_world(W.with_store(~Storage.Schema,~Storage.Store,~Unit,~Unit,~U32,force_store,owner)))
