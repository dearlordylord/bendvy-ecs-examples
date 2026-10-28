import game-observation.bend as Model
import Base
import bot-turn.bend as Turn
import game.bend as G
import offline-policy.bend as Policy

type Progress is Type: Progress{memory: Policy.Memory,packet: G.Packet,choices: U32}

def moved(state: G.State,choices: U32,result: Policy.Memory & (F32 & F32)) -> Progress:
  (memory,direction) = result
  (dx,dy) = direction
  Progress{memory,G.advance(state,dx,dy),choices}
def selected(turn: Turn.Turn,state: G.State,+run: Model.Run,+offers: List<&2,Model.Offer>,memory: Policy.Memory,+choices: U32,snapshots: List<&2,Model.Snapshot>) -> Progress:
  match turn:
    case Turn.UpgradeDecision{}: Progress{memory,G.choose(state,Policy.upgrade(run,offers)),(choices + 1 : U32)}
    case Turn.MovementDecision{}: moved(state,choices,Policy.movement(memory,run,snapshots))
    case _: Progress{memory,G.packet(state),choices}
def next(currentPhase: U32,state: G.State,run: Model.Run,offers: List<&2,Model.Offer>,memory: Policy.Memory,choices: U32,snapshots: List<&2,Model.Snapshot>) -> Progress:
  selected(Turn.select(currentPhase),state,run,offers,memory,choices,snapshots)
def step(progress: Progress) -> Progress:
  match progress:
    case Progress{memory,G.Packet{G.State{world,+run,+offers,+snapshots,pending}},choices}: next(G.run_phase(run),G.State{world,run,offers,snapshots,pending},run,offers,memory,choices,snapshots)
    case progress: progress
