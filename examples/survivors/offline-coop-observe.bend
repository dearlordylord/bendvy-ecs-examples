import game-observation.bend as Model
import run-state.bend as RS
import Base
import enemy-status-encoder.bend as StatusEncoder
import pickup-state.bend as Pickup
import enemy-combat.bend as Enemy
import game-components.bend as Components
import projectile-state.bend as Shot
import game-storage.bend as Storage
import enemy-spatial.bend as Space
import entity-role.bend as GRole
import bendvy-ecs-core@0.1.0.2/world.bend as W
import bendvy-ecs-core@0.1.0.2/column.bend as Col
import bendvy-ecs-core@0.1.0.2/lifecycle.bend as L
import bendvy-ecs-core@0.1.0.2/change_tick.bend as Tick
import bendvy-ecs-core@0.1.0.2/clock_state.bend as Clock
import bendvy-ecs-core@0.1.0.2/entity_allocator.bend as A
import bendvy-ecs-core@0.1.0.2/entity_key.bend as K

import coop-core.bend as Core
import offline-policy.bend as Policy
import bendvy-ecs-core@0.1.0.2/indexed_lifecycle.bend as M
import bendvy-ecs-core@0.1.0.2/owner_handoff.bend as H

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
def session(value: RS.Session) -> String:
  match value:
    case RS.Session{phase,tick,xp,need,level,kills,gold,seed,stage,bosses,mode,enemyKinds,relicCollected}: array([U32.show(phase),U32.show(tick),U32.show(xp),U32.show(need),U32.show(level),U32.show(kills),U32.show(gold),U32.show(seed),U32.show(stage),U32.show(bosses),U32.show(mode),u32s(enemyKinds),U32.show(relicCollected)])
def player_state(value: RS.PlayerState) -> String:
  match value:
    case RS.PlayerState{px,py,hp,maximum,character,weapons,passives,invuln,arcana,meta,revivals,rerolls,banishes,skips,bannedWeapons,bannedPassives}: array([fbits(px),fbits(py),U32.show(hp),U32.show(maximum),U32.show(character),u32s(weapons),u32s(passives),U32.show(invuln),U32.show(arcana),U32.show(meta),U32.show(revivals),U32.show(rerolls),U32.show(banishes),U32.show(skips),U32.show(bannedWeapons),U32.show(bannedPassives)])
def run(value: Model.Run) -> String:
  match value:
    case Model.Run{shared,personal}: array([session(shared),player_state(personal)])
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
def bind(~A:Type,~B:Type,~R:Type,pair:A & B,next:A -> B -> R) -> R:
  match pair:
    case (a,b): next(a)(b)
def items(~T:Data,~show:T -> String,values:List<&2,T>) -> String:
  match values:
    case []: ""
    case value <> []: show(value)
    case value <> rest: show(value) ++ "," ++ items(~T,~show,rest)
def listed(~T:Data,~show:T -> String,values:List<&2,T>) -> String: "[" ++ items(~T,~show,values) ++ "]"
def optional(~T:Data,~show:T -> String,value:Maybe<&2,T>) -> String:
  match value:
    case None{}: "null"
    case Some{value}: show(value)
def owned_optional(~T:Data,~show:T -> String,value:Maybe<&1,T>) -> Maybe<&1,T> & String:
  match value:
    case None{}: (None{},"null")
    case Some{+value}: (Some{value},show(value))
def copied(~T:Data,~show:T -> String,value:T) -> T & String:
  +copy = value
  (copy,show(copy))
def tree(~T:Type,~show:T -> T & String,value:Array<T>) -> Array<T> & String:
  match value:
    case ALeaf{value}: bind(~T,~String,~(Array<T> & String),show(value),(value => text => (ALeaf{value},array(["0",text]))))
    case ANode{left,right}:
      bind(~Array<T>,~String,~(Array<T> & String),tree(~T,~show,left),(left => a =>
        bind(~Array<T>,~String,~(Array<T> & String),tree(~T,~show,right),(right => b => (ANode{left,right},array(["1",a,b]))))
      ))
def entry(value:L.Entry) -> String:
  match value:
    case L.Entry{id,value}: array([U32.show(id),stamp(value)])
def metadata(value:M.Metadata) -> M.Metadata & String:
  match value:
    case M.Metadata{added,changed,+capacity,+depth,+exceptional}:
      bind(~Array<Maybe<&2,Tick.Tick>>,~String,~(M.Metadata & String),tree(~Maybe<&2,Tick.Tick>,~copied(~Maybe<&2,Tick.Tick>,~maybe_tick),added),(added => a =>
        bind(~Array<Maybe<&2,Tick.Tick>>,~String,~(M.Metadata & String),tree(~Maybe<&2,Tick.Tick>,~copied(~Maybe<&2,Tick.Tick>,~maybe_tick),changed),(changed => b =>
          (M.Metadata{added,changed,capacity,depth,exceptional},array([a,b,U32.show(capacity),Nat.show(depth),listed(~L.Entry,~entry,exceptional)]))
        ))
      ))
def handoff(~T:Data,~show:T -> String,value:H.PrototypeHandoffRows<Storage.Schema,T>) -> H.PrototypeHandoffRows<Storage.Schema,T> & List<&2,String>:
  match value:
    case H.HandoffNil{}: (H.HandoffNil{},[])
    case H.HandoffCon{+id,+owner,rest}:
      bind(~H.PrototypeHandoffRows<Storage.Schema,T>,~List<&2,String>,~(H.PrototypeHandoffRows<Storage.Schema,T> & List<&2,String>),handoff(~T,~show,rest),(rest => rows =>
        (H.HandoffCon{id,owner,rest},array([U32.show(id),show(owner)]) <> rows)
      ))
def history(~T:Data,~show:T -> String,value:Col.History<Storage.Schema,T>) -> Col.History<Storage.Schema,T> & List<&2,String>:
  match value:
    case Col.HistoryNil{}: (Col.HistoryNil{},[])
    case Col.HistoryCon{+id,owner,rest}:
      bind(~Maybe<&1,T>,~String,~(Col.History<Storage.Schema,T> & List<&2,String>),owned_optional(~T,~show,owner),(owner => text =>
        bind(~Col.History<Storage.Schema,T>,~List<&2,String>,~(Col.History<Storage.Schema,T> & List<&2,String>),history(~T,~show,rest),(rest => rows =>
          (Col.HistoryCon{id,owner,rest},array([U32.show(id),text]) <> rows)
        ))
      ))
def prepared_state(~T:Data,~show:T -> String,value:Col.State<Storage.Schema,T>) -> Col.State<Storage.Schema,T> & String:
  match value:
    case Col.State{values,+stamps,+capacity,+current,owner,remaining,past}:
      bind(~Array<Maybe<&1,T>>,~String,~(Col.State<Storage.Schema,T> & String),tree(~Maybe<&1,T>,~owned_optional(~T,~show),values),(values => a =>
        bind(~Maybe<&1,T>,~String,~(Col.State<Storage.Schema,T> & String),owned_optional(~T,~show,owner),(owner => c =>
          bind(~H.PrototypeHandoffRows<Storage.Schema,T>,~List<&2,String>,~(Col.State<Storage.Schema,T> & String),handoff(~T,~show,remaining),(remaining => d =>
            bind(~Col.History<Storage.Schema,T>,~List<&2,String>,~(Col.State<Storage.Schema,T> & String),history(~T,~show,past),(past => e =>
              (Col.State{values,stamps,capacity,current,owner,remaining,past},array([a,listed(~L.Entry,~entry,stamps),U32.show(capacity),U32.show(current),c,array(d),array(e)]))
            ))
          ))
        ))
      ))
def indexed_prepared_state(~T:Data,~show:T -> String,value:Col.IndexedPreparedState<Storage.Schema,T>) -> Col.IndexedPreparedState<Storage.Schema,T> & String:
  match value:
    case Col.IndexedPreparedState{values,meta,+capacity,+current,owner,remaining,past}:
      bind(~Array<Maybe<&1,T>>,~String,~(Col.IndexedPreparedState<Storage.Schema,T> & String),tree(~Maybe<&1,T>,~owned_optional(~T,~show),values),(values => a =>
        bind(~M.Metadata,~String,~(Col.IndexedPreparedState<Storage.Schema,T> & String),metadata(meta),(meta => b =>
          bind(~Maybe<&1,T>,~String,~(Col.IndexedPreparedState<Storage.Schema,T> & String),owned_optional(~T,~show,owner),(owner => c =>
            bind(~H.PrototypeHandoffRows<Storage.Schema,T>,~List<&2,String>,~(Col.IndexedPreparedState<Storage.Schema,T> & String),handoff(~T,~show,remaining),(remaining => d =>
              bind(~Col.History<Storage.Schema,T>,~List<&2,String>,~(Col.IndexedPreparedState<Storage.Schema,T> & String),history(~T,~show,past),(past => e =>
                (Col.IndexedPreparedState{values,meta,capacity,current,owner,remaining,past},array([a,b,U32.show(capacity),U32.show(current),c,array(d),array(e)]))
              ))
            ))
          ))
        ))
      ))
def indexed_state(~T:Data,~show:T -> String,value:Col.IndexedOrdinaryState<Storage.Schema,T>) -> Col.IndexedOrdinaryState<Storage.Schema,T> & String:
  match value:
    case Col.IndexedOrdinaryState{values,meta}:
      bind(~Array<Maybe<&1,T>>,~String,~(Col.IndexedOrdinaryState<Storage.Schema,T> & String),tree(~Maybe<&1,T>,~owned_optional(~T,~show),values),(values => a =>
        bind(~M.Metadata,~String,~(Col.IndexedOrdinaryState<Storage.Schema,T> & String),metadata(meta),(meta => b =>
          (Col.IndexedOrdinaryState{values,meta},array([a,b]))
        ))
      ))
def prepared_carrier(~T:Data,~show:T -> String,value:Col.Carrier<Storage.Schema,T>) -> Col.Carrier<Storage.Schema,T> & String:
  match value:
    case Col.Owned{state}: bind(~Col.State<Storage.Schema,T>,~String,~(Col.Carrier<Storage.Schema,T> & String),prepared_state(~T,~show,state),(state => text => (Col.Owned{state},array(["0",text]))))
    case Col.Wrapped{inner}: bind(~Col.Carrier<Storage.Schema,T>,~String,~(Col.Carrier<Storage.Schema,T> & String),prepared_carrier(~T,~show,inner),(inner => text => (Col.Wrapped{inner},array(["1",text]))))
def indexed_carrier(~T:Data,~show:T -> String,value:Col.IndexedOrdinaryCarrier<Storage.Schema,T>) -> Col.IndexedOrdinaryCarrier<Storage.Schema,T> & String:
  match value:
    case Col.IndexedOrdinaryOwned{state}: bind(~Col.IndexedOrdinaryState<Storage.Schema,T>,~String,~(Col.IndexedOrdinaryCarrier<Storage.Schema,T> & String),indexed_state(~T,~show,state),(state => text => (Col.IndexedOrdinaryOwned{state},array(["0",text]))))
    case Col.IndexedOrdinaryWrapped{inner}: bind(~Col.IndexedOrdinaryCarrier<Storage.Schema,T>,~String,~(Col.IndexedOrdinaryCarrier<Storage.Schema,T> & String),indexed_carrier(~T,~show,inner),(inner => text => (Col.IndexedOrdinaryWrapped{inner},array(["1",text]))))
def indexed_prepared_carrier(~T:Data,~show:T -> String,value:Col.IndexedPreparedCarrier<Storage.Schema,T>) -> Col.IndexedPreparedCarrier<Storage.Schema,T> & String:
  match value:
    case Col.IndexedPreparedOwned{state}: bind(~Col.IndexedPreparedState<Storage.Schema,T>,~String,~(Col.IndexedPreparedCarrier<Storage.Schema,T> & String),indexed_prepared_state(~T,~show,state),(state => text => (Col.IndexedPreparedOwned{state},array(["0",text]))))
    case Col.IndexedPreparedWrapped{inner}: bind(~Col.IndexedPreparedCarrier<Storage.Schema,T>,~String,~(Col.IndexedPreparedCarrier<Storage.Schema,T> & String),indexed_prepared_carrier(~T,~show,inner),(inner => text => (Col.IndexedPreparedWrapped{inner},array(["1",text]))))
def column(~T:Data,~show:T -> String,value:Col.Column<Storage.Schema,T>) -> Col.Column<Storage.Schema,T> & String:
  match value:
    case Col.Column{values,+stamps}:
      bind(~Array<Maybe<&1,T>>,~String,~(Col.Column<Storage.Schema,T> & String),tree(~Maybe<&1,T>,~owned_optional(~T,~show),values),(values => text =>
        (Col.Column{values,stamps},array(["\"Column\"",text,listed(~L.Entry,~entry,stamps)]))
      ))
    case Col.Prepared{state}: bind(~Col.Carrier<Storage.Schema,T>,~String,~(Col.Column<Storage.Schema,T> & String),prepared_carrier(~T,~show,state),(state => text => (Col.Prepared{state},array(["\"Prepared\"",text]))))
    case Col.Indexed{state}: bind(~Col.IndexedOrdinaryCarrier<Storage.Schema,T>,~String,~(Col.Column<Storage.Schema,T> & String),indexed_carrier(~T,~show,state),(state => text => (Col.Indexed{state},array(["\"Indexed\"",text]))))
    case Col.PreparedIndexed{state}: bind(~Col.IndexedPreparedCarrier<Storage.Schema,T>,~String,~(Col.Column<Storage.Schema,T> & String),indexed_prepared_carrier(~T,~show,state),(state => text => (Col.PreparedIndexed{state},array(["\"PreparedIndexed\"",text]))))
def handle(value: W.Handle<Storage.Schema>) -> String:
  match value:
    case W.Handle{namespace,K.EntityKey{id,generation}}: array([U32.show(namespace),U32.show(id),U32.show(generation)])
def player(value: Components.PlayerRecord) -> String:
  match value:
    case Components.PlayerRecord{id,personal,connected,reviveTick}: array([U32.show(id),player_state(personal),U32.show(Bool.to_u32(connected)),U32.show(reviveTick)])
def movement(value: Storage.MovementRoster) -> String:
  match value:
    case Storage.MovementPrepared{handles}: listed(~W.Handle<Storage.Schema>,~handle,handles)
def candidates(value: Storage.CandidateRoster) -> String:
  match value:
    case Storage.CandidatesPrepared{projectiles,pool}: array([listed(~W.Handle<Storage.Schema>,~handle,projectiles),listed(~W.Handle<Storage.Schema>,~handle,pool)])
def store_fields(value: Storage.StoreFields) -> Storage.StoreFields & String:
  match value:
    case Storage.StoreFields{v,t,s,p,r,+m,+c,players,spaces,phases,identities,shots}:
      bind(~Col.Column<Storage.Schema,Components.Vitals>,~String,~(Storage.StoreFields & String),column(~Components.Vitals,~vitals,v),(v => vText =>
        bind(~Col.Column<Storage.Schema,Components.Trajectory>,~String,~(Storage.StoreFields & String),column(~Components.Trajectory,~trajectory,t),(t => tText =>
          bind(~Col.Column<Storage.Schema,Components.Status>,~String,~(Storage.StoreFields & String),column(~Components.Status,~status,s),(s => sText =>
            bind(~Col.Column<Storage.Schema,Pickup.Payload>,~String,~(Storage.StoreFields & String),column(~Pickup.Payload,~pickup,p),(p => pText =>
              bind(~Col.Column<Storage.Schema,GRole.Role>,~String,~(Storage.StoreFields & String),column(~GRole.Role,~role,r),(r => rText =>
                bind(~Col.Column<Storage.Schema,Components.PlayerRecord>,~String,~(Storage.StoreFields & String),column(~Components.PlayerRecord,~player,players),(players => playersText =>
                  bind(~Col.Column<Storage.Schema,Space.Spatial>,~String,~(Storage.StoreFields & String),column(~Space.Spatial,~spatial,spaces),(spaces => spacesText =>
                    bind(~Col.Column<Storage.Schema,Enemy.Phase>,~String,~(Storage.StoreFields & String),column(~Enemy.Phase,~enemy_phase,phases),(phases => phasesText =>
                      bind(~Col.Column<Storage.Schema,Components.Identity>,~String,~(Storage.StoreFields & String),column(~Components.Identity,~identity,identities),(identities => identitiesText =>
                        bind(~Col.Column<Storage.Schema,Components.ShotPayload>,~String,~(Storage.StoreFields & String),column(~Components.ShotPayload,~shot_payload,shots),(shots => shotsText =>
                          (Storage.StoreFields{v,t,s,p,r,m,c,players,spaces,phases,identities,shots},"{" ++ "\"vitals\":" ++ vText ++ "," ++ "\"trajectories\":" ++ tText ++ "," ++ "\"statuses\":" ++ sText ++ "," ++ "\"pickups\":" ++ pText ++ "," ++ "\"roles\":" ++ rText ++ "," ++ "\"players\":" ++ playersText ++ "," ++ "\"spaces\":" ++ spacesText ++ "," ++ "\"enemyPhases\":" ++ phasesText ++ "," ++ "\"identities\":" ++ identitiesText ++ "," ++ "\"shots\":" ++ shotsText ++ "," ++ "\"movement\":" ++ movement(m) ++ "," ++ "\"candidates\":" ++ candidates(c) ++ "}")
                        ))
                      ))
                    ))
                  ))
                ))
              ))
            ))
          ))
        ))
      ))
def store(value: Storage.Store) -> Storage.Store & String:
  match value:
    case Storage.Owned{fields}: bind(~Storage.StoreFields,~String,~(Storage.Store & String),store_fields(fields),(fields => text => (Storage.Owned{fields},array(["0",text]))))
    case Storage.Wrapped{inner}: bind(~Storage.Store,~String,~(Storage.Store & String),store(inner),(inner => text => (Storage.Wrapped{inner},array(["1",text]))))
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
def allocator(value:A.Allocator) -> A.Allocator & String:
  match value:
    case A.Allocator{+next,+high,slots,+capacity,+depth,+free,+order}:
      bind(~Array<A.Slot>,~String,~(A.Allocator & String),tree(~A.Slot,~copied(~A.Slot,~slot),slots),(slots => text =>
        (A.Allocator{next,high,slots,capacity,depth,free,order},"{\"next\":" ++ U32.show(next) ++ ",\"high\":" ++ U32.show(high) ++ ",\"capacity\":" ++ U32.show(capacity) ++ ",\"depth\":" ++ Nat.show(depth) ++ ",\"free\":" ++ u32s(free) ++ ",\"order\":[" ++ keys(order) ++ "],\"slots\":" ++ text ++ "}")
      ))
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
def unit(value:Unit) -> String:
  match value:
    case Unit{}: "null"
def world(value:Storage.World()) -> Storage.World() & Maybe<&2,String>:
  match value:
    case W.World{+namespace,alloc,components,+resource,+events,[],+regs,+next,+time}:
      bind(~A.Allocator,~String,~(Storage.World() & Maybe<&2,String>),allocator(alloc),(alloc => a =>
        bind(~Storage.Store,~String,~(Storage.World() & Maybe<&2,String>),store(components),(components => b =>
          (W.World{namespace,alloc,components,resource,events,[],regs,next,time},Some{"{\"namespace\":" ++ U32.show(namespace) ++ ",\"allocator\":" ++ a ++ ",\"store\":" ++ b ++ ",\"resource\":" ++ unit(resource) ++ ",\"events\":" ++ listed(~Unit,~unit,events) ++ ",\"pendingCommands\":0,\"registrations\":[" ++ registrations(regs) ++ "],\"nextSystemId\":" ++ U32.show(next) ++ ",\"clock\":" ++ clock(time) ++ "}"})
        ))
      ))
    case W.World{namespace,alloc,components,resource,events,pending,regs,next,time}: (W.World{namespace,alloc,components,resource,events,pending,regs,next,time},None{})
def player_ref(value:Core.PlayerRef) -> String:
  match value:
    case Core.PlayerRef{id,value}: array([U32.show(id),handle(value)])
def player_offers(value:Core.PlayerOffers) -> String:
  match value:
    case Core.PlayerOffers{id,values}: array([U32.show(id),offers(values)])
def reward(value:Core.Reward) -> String:
  match value:
    case Core.Reward{kind,collector}: array([U32.show(kind),U32.show(collector)])
def point(value:Policy.Point) -> String:
  match value:
    case Policy.Point{x,y}: array([fbits(x),fbits(y)])
def goal(value:Policy.Goal) -> String:
  match value:
    case Policy.Goal{seed,generation,kind,x,y,reward,cluster}: array([U32.show(seed),U32.show(generation),U32.show(kind),fbits(x),fbits(y),fbits(reward),point(cluster)])
def choice(value:Policy.Choice) -> String:
  match value:
    case Policy.Choice{value,path,score}: array([goal(value),listed(~Policy.Point,~point,path),fbits(score)])
def memory(value:Policy.Memory) -> String:
  match value:
    case Policy.Memory{current,lastPlan,lastHp,anchor,stuckSince,initialized,objectKeys,candidates}: array([optional(~Policy.Choice,~choice,current),U32.show(lastPlan),U32.show(lastHp),point(anchor),U32.show(stuckSince),U32.show(Bool.to_u32(initialized)),listed(~Policy.Goal,~goal,objectKeys),listed(~Policy.Choice,~choice,candidates)])
type Capture is Type: Captured{state:Core.CoreState,text:String} Unobservable{state:Core.CoreState}
def snapshot_done(+shared:RS.Session,+refs:List<&2,Core.PlayerRef>,+shots:List<&2,Model.Snapshot>,+round:U32,+required:List<&2,U32>,+off:List<&2,Core.PlayerOffers>,+pending:List<&2,Core.Reward>,result:Storage.World() & Maybe<&2,String>) -> Capture:
  match result:
    case (world,None{}): Unobservable{Core.CoreState{world,shared,refs,shots,round,required,off,pending}}
    case (world,Some{text}): Captured{Core.CoreState{world,shared,refs,shots,round,required,off,pending},"{\"world\":" ++ text ++ ",\"shared\":" ++ session(shared) ++ ",\"refs\":" ++ listed(~Core.PlayerRef,~player_ref,refs) ++ ",\"snapshots\":" ++ snapshots(shots) ++ ",\"round\":" ++ U32.show(round) ++ ",\"required\":" ++ u32s(required) ++ ",\"offers\":" ++ listed(~Core.PlayerOffers,~player_offers,off) ++ ",\"pending\":" ++ listed(~Core.Reward,~reward,pending) ++ "}"}
def snapshot(value:Core.CoreState) -> Capture:
  match value:
    case Core.CoreState{owner,shared,refs,shots,round,required,off,pending}: snapshot_done(shared,refs,shots,round,required,off,pending,world(owner))

type Action is Data: AuditMove{beforeTick:U32,dx0:F32,dy0:F32,dx1:F32,dy1:F32} AuditChoose{beforeTick:U32,player:U32,round:U32,index:U32}
def action(value:Action) -> String:
  match value:
    case AuditMove{_,dx0,dy0,dx1,dy1}: "{\"kind\":\"move\",\"bits\":" ++ array([fbits(dx0),fbits(dy0),fbits(dx1),fbits(dy1)]) ++ "}"
    case AuditChoose{_,player,round,index}: "{\"kind\":\"choose\",\"player\":" ++ U32.show(player) ++ ",\"round\":" ++ U32.show(round) ++ ",\"index\":" ++ U32.show(index) ++ "}"
def before_tick(value:Action) -> U32:
  match value:
    case AuditMove{tick,_,_,_,_}: tick
    case AuditChoose{tick,_,_,_}: tick
def was_choice(value:Maybe<&2,Action>) -> Bool:
  match value:
    case Some{AuditChoose{_,_,_,_}}: True{}
    case _: False{}
