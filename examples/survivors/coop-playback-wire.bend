import ./game-observation.bend as Model
import enemy-combat.bend as Enemy
import pickup-state.bend as Pickup
# Typed projection only. This module exposes no world-forecast operation.
import Base
import game-components.bend as Components
import projectile-state.bend as Shot
import enemy-spatial.bend as Space
import ./game.bend as G
import ./coop-combat-prediction.bend as Wire
import ./coop-playback.bend as P
import ./coop-playback-wire-policy.bend as Projection
import ./body-index.bend as BI
import ./list-map.bend as LM

type ActorContext is Data: ActorContext{tick:U32,births:BI.Index<U32>}
def player_actor(player:G.PlayerSnapshot) -> P.Actor:
  match player:
    case G.PlayerSnapshot{id,+run,connected}: Projection.player_actor(id,G.run_character(run),G.run_px(run),G.run_py(run),G.run_hp(run),connected)
def mapped_player(context:Unit,player:G.PlayerSnapshot) -> P.Actor: player_actor(player)
def projectile_hostile(side:Shot.Side) -> Bool:
  match side:
    case Shot.PlayerShot{}: False{}
    case Shot.HostileShot{}: True{}
def pickup_actor(pickup:Pickup.State) -> P.Actor: Projection.pickup_actor(pickup)
def snapshot_actor(context:ActorContext,snapshot:Model.Snapshot) -> P.Actor:
  match context snapshot:
    case ActorContext{tick,births} Model.ProjectileSnapshot{Shot.State{Space.Spatial{x,y,+age,_},+seed,side,_,Components.Trajectory{_,_,life,pierce,_,owner,slot,+sourcePlayer}}}: Projection.projectile_actor(projectile_hostile(side),seed,Projection.birth(births,tick,age,seed),owner,slot,sourcePlayer,x,y,age,life,pierce)
    case _ Model.PickupSnapshot{pickup}: pickup_actor(pickup)
    case ActorContext{tick,births} Model.EnemySnapshot{Enemy.State{Space.Spatial{x,y,+age,_},_,+identity,Components.Vitals{health,_},_}}: Projection.enemy_actor(identity,Projection.birth(births,tick,age,identity),x,y,age,health)
def join(first:List<&2,P.Actor>,second:List<&2,P.Actor>) -> List<&2,P.Actor>: Projection.join(first,second)
def project(scene:Wire.Scene,observation:U32,receivedAt:Nat,extras:List<&2,P.Actor>) -> P.Frame:
  match scene:
    case Wire.Scene{_,players,snapshots,births,_,_,+tick,_}: Projection.frame(observation,tick,receivedAt,LM.map(~G.PlayerSnapshot,~P.Actor,~Unit,~mapped_player,Unit{},players),LM.map(~Model.Snapshot,~P.Actor,~ActorContext,~snapshot_actor,ActorContext{tick,births},snapshots),extras)
def own_run(scene:Wire.Scene) -> Maybe<&2,Model.Run>:
  match scene:
    case Wire.Scene{own,players,_,_,_,_,_,_}: Wire.find_run(players,own)
