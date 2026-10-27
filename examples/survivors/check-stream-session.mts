import { spawnSync } from "node:child_process"
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = dirname(fileURLToPath(import.meta.url))
const names = [
  "stream-session.bend",
  "stream-session-LAWS.bend",
  "stream-session-PROOF.bend",
  "stream-session-probe.bend"
]
const source = new Map(names.map((name) => [name, readFileSync(join(root, name), "utf8")]))
const limiter =
  ["timeout", "gtimeout"].find((command) => spawnSync(command, ["--version"]).status === 0) ??
  (() => {
    throw new Error("Install coreutils timeout or gtimeout before running Bend checks")
  })()
function check(path: string) {
  const result = spawnSync(
    "bash",
    [
      "-c",
      'ulimit -t 10; exec "$@"',
      "stream-session-check",
      limiter,
      "60",
      process.env.BEND || "bend",
      path,
      "--verdict"
    ],
    { encoding: "utf8", timeout: 65000 }
  )
  return { status: result.status, output: result.stdout + result.stderr }
}
const mutants = [
  ["frame-clock", "case Frame{now}: frame(clock(state,now))", "case Frame{_}: frame(state)", "step_frame_clock"],
  [
    "reply-clock",
    "case Reply{id,index,now}: reply(clock(state,now),id,index)",
    "case Reply{id,index,_}: reply(state,id,index)",
    "step_reply_clock"
  ],
  [
    "movement-clock",
    "case MovementReply{id,index,count,now}: movement_reply(clock(state,now),id,index,count)",
    "case MovementReply{id,index,count,_}: movement_reply(state,id,index,count)",
    "step_movement_clock"
  ],
  ["late-advice", "Nat.is_lt(elapsed,cutoff)", "True{}", "admission_exact"],
  [
    "ignore-generation",
    "Bool.and(Nat.is_eq(g,h),Bool.and(Nat.is_eq(d,e),U32.is_eq(p,k)))",
    "Bool.and(Nat.is_eq(d,e),U32.is_eq(p,k))",
    "identity_exact"
  ],
  [
    "duplicate-commit",
    "State{new_request(id),Committed{},paused,last,elapsed,a,d,b},Commit{index}",
    "State{new_request(id),Dwell{count,index},paused,last,elapsed,a,d,b},Commit{index}",
    "commit_leaves_dwell"
  ],
  ["paused-time", "case True{}: elapsed", "case True{}: Nat.add(elapsed,elapsed_at(now,lastAt))", "paused_elapsed"],
  ["early-commit", "Nat.is_ge(elapsed,d)", "True{}", "dwell_gate"],
  [
    "resume-spends-pause",
    "case Resume{now}: resume(state,now)",
    "case Resume{+now}: resume(clock(state,now),now)",
    "step_resume_clock"
  ],
  ["old-offers", "Nat.is_gt(decision,oldDecision)", "True{}", "offers_admission_exact"]
]
const work = mkdtempSync(join(tmpdir(), "stream-session-laws-"))
const results: { name: string; law: string; result: string }[] = []
try {
  for (const [name, text] of source) writeFileSync(join(work, name), text)
  for (const name of ["stream-session.bend", "stream-session-PROOF.bend", "stream-session-probe.bend"]) {
    const result = check(join(work, name))
    if (result.status !== 0 || !result.output.includes("ALL PROOFS CHECK")) throw new Error(`${name}: ${result.output}`)
  }
  const original = source.get("stream-session.bend")
  if (original === undefined) throw new Error("Missing stream-session source")
  for (const row of mutants) {
    const [name, before, after, law] = row
    if (!name || !before || !after || !law) throw new Error("Incomplete mutant row")
    if (original.split(before).length !== 2) throw new Error(`${name}: mutation target must occur exactly once`)
    writeFileSync(join(work, "stream-session.bend"), original.replace(before, after))
    const core = check(join(work, "stream-session.bend"))
    if (core.status !== 0) throw new Error(`${name}: mutant must typecheck: ${core.output}`)
    const result = check(join(work, "stream-session-PROOF.bend"))
    if (result.status !== 1 || !result.output.includes(`Location: L.${law}`))
      throw new Error(`${name}: expected rejection in ${law}: ${result.output}`)
    results.push({ name, law, result: "rejected" })
  }
  process.stdout.write(JSON.stringify({ laws: 34, literalScenarios: 21, mutants: results }, null, 2) + "\n")
} finally {
  rmSync(work, { recursive: true, force: true })
}
