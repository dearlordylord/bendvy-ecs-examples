import game-observation.bend as Model
import pickup-encoder.bend as PickupEncoder
import Base
import enemy-status-encoder.bend as StatusEncoder
import enemy-combat.bend as Enemy
import enemy-spatial.bend as Space
import game-components.bend as Components
import projectile-state.bend as Shot
import projectile-encoder.bend as ShotEncoder
import game.bend as G
import coop-combat-prediction.bend as Prediction
import coop-combat-codec.bend as W
import coop-session.bend as Session
import coop-combat-prediction-policy.bend as Policy

# Wire snapshots preserve contact visitation and enemy statuses. Omitting either
# would let a new anchor repeat an already consumed contact or erase slow/burn.
def native_enemy(enemy: Enemy.State) -> String:
  match enemy:
    case Enemy.State{Space.Spatial{x,y,age,radius},archetype,identity,Components.Vitals{health,maximum},status}:
      "{\"$\":\"State\",\"spatial\":{\"$\":\"Spatial\",\"x\":" ++ F32.show(x) ++ ",\"y\":" ++ F32.show(y) ++ ",\"age\":" ++ U32.show(age) ++ ",\"radius\":" ++ F32.show(radius) ++ "},\"archetype\":" ++ U32.show(archetype) ++ ",\"identity\":" ++ U32.show(identity) ++ ",\"vitals\":{\"$\":\"Vitals\",\"health\":" ++ U32.show(health) ++ ",\"maximum\":" ++ U32.show(maximum) ++ "},\"status\":" ++ StatusEncoder.native(status) ++ "}"
def native_snapshot(value:Model.Snapshot) -> String:
  match value:
    case Model.ProjectileSnapshot{projectile}: "{\"$\":\"ProjectileSnapshot\",\"projectile\":" ++ ShotEncoder.native_state(projectile) ++ "}"
    case Model.EnemySnapshot{enemy}: "{\"$\":\"EnemySnapshot\",\"enemy\":" ++ native_enemy(enemy) ++ "}"
    case Model.PickupSnapshot{pickup}: "{\"$\":\"PickupSnapshot\",\"pickup\":" ++ PickupEncoder.native_state(pickup) ++ "}"
def native_snapshots(rows:List<&2,Model.Snapshot>) -> String:
  match rows:
    case []: "{\"$\":\"Nil\"}"
    case head <> tail: "{\"$\":\"Con\",\"head\":" ++ native_snapshot(head) ++ ",\"tail\":" ++ native_snapshots(tail) ++ "}"
def native_player(value:G.PlayerSnapshot) -> String:
  match value:
    case G.PlayerSnapshot{id,run,connected}: "{\"$\":\"PlayerSnapshot\",\"id\":" ++ U32.show(id) ++ ",\"run\":" ++ W.native_run(run) ++ ",\"connected\":" ++ Bool.pick(String,connected,"true","false") ++ "}"
def native_players(rows:List<&2,G.PlayerSnapshot>) -> String:
  match rows:
    case []: "{\"$\":\"Nil\"}"
    case head <> tail: "{\"$\":\"Con\",\"head\":" ++ native_player(head) ++ ",\"tail\":" ++ native_players(tail) ++ "}"
def native_directions(value:Session.Directions) -> String:
  match value:
    case Session.Directions{x0,y0,x1,y1}: "{\"$\":\"Directions\",\"x0\":" ++ F32.show(x0) ++ ",\"y0\":" ++ F32.show(y0) ++ ",\"x1\":" ++ F32.show(x1) ++ ",\"y1\":" ++ F32.show(y1) ++ "}"

def witness_fields(value:Policy.Witness) -> String:
  match value:
    case Policy.Witness{kind,tick,shot,target,shotBirth,targetBirth,x0,y0,x1,y1,ex0,ey0,ex1,ey1,radius,time}: "\"kind\":" ++ U32.show(kind) ++ ",\"tick\":" ++ U32.show(tick) ++ ",\"shot\":" ++ U32.show(shot) ++ ",\"target\":" ++ U32.show(target) ++ ",\"shotBirth\":" ++ U32.show(shotBirth) ++ ",\"targetBirth\":" ++ U32.show(targetBirth) ++ ",\"x0\":" ++ F32.show(x0) ++ ",\"y0\":" ++ F32.show(y0) ++ ",\"x1\":" ++ F32.show(x1) ++ ",\"y1\":" ++ F32.show(y1) ++ ",\"ex0\":" ++ F32.show(ex0) ++ ",\"ey0\":" ++ F32.show(ey0) ++ ",\"ex1\":" ++ F32.show(ex1) ++ ",\"ey1\":" ++ F32.show(ey1) ++ ",\"radius\":" ++ F32.show(radius) ++ ",\"time\":" ++ F32.show(time)
def native_witness(value:Policy.Witness) -> String: "{\"$\":\"Witness\"," ++ witness_fields(value) ++ "}"
def native_contacts(rows:List<&2,Policy.Witness>) -> String:
  match rows:
    case []: "{\"$\":\"Nil\"}"
    case head <> tail: "{\"$\":\"Con\",\"head\":" ++ native_witness(head) ++ ",\"tail\":" ++ native_contacts(tail) ++ "}"
def native_scene(scene:Prediction.Scene) -> String:
  match scene:
    case Prediction.Scene{own,players,snapshots,births,directions,contacts,tick,diagnostics}: "{\"$\":\"Scene\",\"own\":" ++ U32.show(own) ++ ",\"players\":" ++ native_players(players) ++ ",\"snapshots\":" ++ native_snapshots(snapshots) ++ ",\"births\":" ++ W.native_births(births) ++ ",\"directions\":" ++ native_directions(directions) ++ ",\"contacts\":" ++ native_contacts(contacts) ++ ",\"tick\":" ++ U32.show(tick) ++ ",\"diagnostics\":" ++ Bool.pick(String,diagnostics,"true","false") ++ "}"
