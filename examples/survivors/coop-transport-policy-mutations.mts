import assert from "node:assert/strict"
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"
import { spawnSync } from "node:child_process"

const sourcePath = path.resolve("examples/survivors/coop-transport-policy.bend")
const checkPath = path.resolve("examples/survivors/coop-transport-policy-check.mts")
const source = (await readFile(sourcePath, "utf8")).replace(
  /^import (\.\/\S+) as /gm,
  (_match, relative: string) => `import ${path.resolve(path.dirname(sourcePath), relative)} as `
)
const mutants = [
  {
    name: "waiting offer budget doubles",
    before: "def max_waiting_offers() -> Nat: 16n",
    after: "def max_waiting_offers() -> Nat: 32n"
  },
  {
    name: "failed authentication drops waiting offers",
    before: "accept_waiting(State{Available{},next,epoch,rows,writer,handshake,drain,allowIncoming},waiting)",
    after: "Out{State{Available{},next,epoch,rows,writer,handshake,drain,allowIncoming},[]}"
  },
  {
    name: "authenticated peer retains competing offers",
    before: "List.append(&2,Effect,refused_offers(waiting),[NotifyConnected{peer,0}])",
    after: "[NotifyConnected{peer,0}]"
  },
  {
    name: "peer departure cancels the room drain timer",
    before: "cancelled_work(State{phase,next,epoch,rows,writer,handshake,None{},allowIncoming},Cancelled{})",
    after: "cancelled_work(state,Cancelled{})"
  },
  {
    name: "guest creation resets its attempt deadline",
    before: "case GuestEndpoint{}: Out{state,[]}",
    after: "case GuestEndpoint{}: ready(state)"
  },
  {
    name: "stale writer completion clears the current flight",
    before: "written_selected(writer_matches(state,operation,connection),state,success)",
    after: "written_selected(True{},state,success)"
  },
  {
    name: "terminal admission accepts an incoming offer",
    before: "Bool.and(allocation_available(state),incoming_allowed(state))",
    after: "allocation_available(state)"
  },
  {
    name: "close retains queued work",
    before: "case CloseRequest{}: close(state,Cancelled{})",
    after: "case CloseRequest{}: Out{state,[]}"
  },
  {
    name: "pending byte budget doubles",
    before: "def max_pending_bytes() -> U32: 4194304",
    after: "def max_pending_bytes() -> U32: 8388608"
  },
  {
    name: "pending message budget doubles",
    before: "def max_pending_messages() -> Nat: 16n",
    after: "def max_pending_messages() -> Nat: 32n"
  },
  {
    name: "a failed native write reports success",
    before: "written_selected(writer_matches(state,operation,connection),state,success)",
    after: "written_selected(writer_matches(state,operation,connection),state,True{})"
  },
  {
    name: "an old deadline expires the new connection",
    before: "deadline_selected(timer_matches(handshake,id),timer_matches(drain,id),state,now)",
    after: "deadline_selected(True{},True{},state,now)"
  }
]
const temporary = await mkdtemp(path.join(tmpdir(), "survivors-transport-mutants-"))
try {
  for (const [index, mutant] of mutants.entries()) {
    assert.equal(source.split(mutant.before).length, 2, `Mutation has exactly one semantic target: ${mutant.name}`)
    const mutantPath = path.join(temporary, `policy-${index}.bend`)
    const modulePath = path.join(temporary, "coop-transport-policy.mjs")
    await writeFile(mutantPath, source.replace(mutant.before, mutant.after))
    const compile = spawnSync(process.env.BEND ?? "bend", [mutantPath, "-o", modulePath], {
      encoding: "utf8",
      timeout: 30000
    })
    assert.equal(compile.status, 0, `Mutation must compile: ${mutant.name}\n${compile.stdout}\n${compile.stderr}`)
    const checked = spawnSync(process.execPath, [checkPath, temporary], { encoding: "utf8", timeout: 30000 })
    assert.notEqual(checked.status, 0, `Behavior checks must reject: ${mutant.name}`)
    assert.match(
      checked.stderr,
      /AssertionError|Missing (?:Settle|NotifyTimeout|Accept|Refuse) effect/,
      `Counterexample must be behavioral: ${mutant.name}\n${checked.stderr}`
    )
    console.log(JSON.stringify({ status: "REJECTED", mutation: mutant.name }))
  }
  console.log(
    JSON.stringify({
      status: "PASS",
      rejected: mutants.length,
      scope: "semantic transport-policy mutations executed through production policy checks"
    })
  )
} finally {
  await rm(temporary, { recursive: true, force: true })
}
