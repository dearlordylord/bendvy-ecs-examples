import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { spawnSync } from "node:child_process"
import { mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, mkdirSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

type SourceRow = { path: string; sha256: string }
type Prerequisite = {
  method: "full-source-cli-check-only"
  sources: SourceRow[]
  nodeVersion: string
  nodeSha256: string
  proofSha256: string
  lawsSha256: string
  cliSha256: string
  kernelSha256: string
}
type CompilerDeclaration = {
  $: string
  T: unknown
  v?: unknown
  e?: unknown
  b?: boolean
  u?: boolean
  i?: unknown
  l?: boolean
}
type CompilerBook = {
  tlds: Record<string, CompilerDeclaration>
  ctrs: unknown
  tmps: unknown
  order: string[]
  hols: number
}
interface CompilerAPI {
  BASE_BEND: string
  book_nil(): CompilerBook
  book_load(book: CompilerBook, file: string, namespace: string, seen: Map<string, string | null>): Promise<number>
  book_valid(book: CompilerBook): void
  term_lower(term: unknown): unknown
}
interface KernelAPI {
  safe_emit(book: CompilerBook, output: string): string[]
  run_read(binary: string, args: string[], options: { env: NodeJS.ProcessEnv }): [{ status: number | null }, string]
}
function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}
// The pinned official source supplies function signatures; validate its export shape at import.
function compilerAPI(value: unknown): value is CompilerAPI {
  return (
    record(value) &&
    typeof value.BASE_BEND === "string" &&
    typeof value.book_nil === "function" &&
    typeof value.book_load === "function" &&
    typeof value.book_valid === "function" &&
    typeof value.term_lower === "function"
  )
}
function kernelAPI(value: unknown): value is KernelAPI {
  return record(value) && typeof value.safe_emit === "function" && typeof value.run_read === "function"
}
async function loadCompiler(source: string) {
  const module: unknown = await import(pathToFileURL(join(source, "bend2/bend.ts")).href)
  assert.ok(compilerAPI(module), "Official compiler exports do not match the pinned API")
  return module
}
async function loadKernel(source: string) {
  const module: unknown = await import(pathToFileURL(join(source, "bend2/safe.ts")).href)
  assert.ok(kernelAPI(module), "Official kernel adapter exports do not match the pinned API")
  return module
}
function text(value: unknown): string {
  assert.ok(typeof value === "string")
  return value
}
function sourceRows(value: unknown): SourceRow[] {
  assert.ok(Array.isArray(value))
  return value.map((row: unknown) => {
    assert.ok(record(row))
    return { path: text(row.path), sha256: text(row.sha256) }
  })
}
function prerequisite(value: unknown): Prerequisite {
  assert.ok(record(value))
  assert.equal(value.method, "full-source-cli-check-only")
  return {
    method: "full-source-cli-check-only",
    sources: sourceRows(value.sources),
    nodeVersion: text(value.nodeVersion),
    nodeSha256: text(value.nodeSha256),
    proofSha256: text(value.proofSha256),
    lawsSha256: text(value.lawsSha256),
    cliSha256: text(value.cliSha256),
    kernelSha256: text(value.kernelSha256)
  }
}

assert.equal(compilerAPI({ BASE_BEND: "missing-functions" }), false)
assert.equal(kernelAPI({ safe_emit: () => [] }), false)
assert.throws(() => sourceRows([{}]))
assert.throws(() => prerequisite({ method: "full-source-cli-check-only", sources: [] }))

const root = dirname(fileURLToPath(import.meta.url))
if (process.versions.bun) throw Error("Run this gate with Node24")
const workerFlags = ["--no-warnings", "--stack-size=8192", "--experimental-transform-types"]
const compilerCommit = "a3efe8a3801f423827424227172eed9802c5e6cb"
const compilerRoot = process.env.BEND_SOURCE_ROOT
if (process.env.BEND) throw Error("BEND override is forbidden; use the installed pinned CLI")
const lawPath = join(root, "offline-policy/preference-LAWS.bend")
const proofPath = join(root, "offline-policy/preference-PROOF.bend")
const hash = (text: string) => createHash("sha256").update(text).digest("hex")
const limiter =
  ["timeout", "gtimeout"].find((name) => spawnSync(name, ["--version"]).status === 0) ??
  (() => {
    throw Error("Install coreutils timeout or gtimeout")
  })()
function limited(command: string, args: string[]) {
  const started = Date.now()
  if (process.env.STREAM_GOAL_CPU) {
    args = ["-c", process.env.STREAM_GOAL_CPU, command, ...args]
    command = "taskset"
  }
  const result = spawnSync(
    "bash",
    ["-c", 'ulimit -t 10; exec "$@"', "stream-goal-check", limiter, "60", command, ...args],
    { encoding: "utf8", timeout: 65000 }
  )
  return {
    status: result.status,
    signal: result.signal,
    wallMs: Date.now() - started,
    output: result.stdout + result.stderr
  }
}
function checked(path: string) {
  return limited(process.env.BEND || "bend", [path, "--check-only"])
}
function pass(result: ReturnType<typeof limited>, label: string) {
  assert.equal(result.status, 0, `${label}: ${JSON.stringify(result)}`)
  assert.ok(result.output.includes("ALL PROOFS CHECK"), label)
}

function selectedOrder(original: readonly string[], selected: string[]) {
  if (selected.length === 0) throw Error("Empty selected roots")
  if (new Set(selected).size !== selected.length) throw Error("Duplicate selected roots")
  for (const name of selected) if (!original.includes(name)) throw Error("Missing selected root")
  const snapshot = Object.freeze([...original])
  const result = [...selected]
  Object.defineProperty(result, "lastIndexOf", { value: snapshot.lastIndexOf.bind(snapshot), enumerable: false })
  return result
}
const controlOrder = Object.freeze(["helper-before", "law", "helper-after", "law"])
const controlSelected = selectedOrder(controlOrder, ["law"])
assert.deepEqual([...controlSelected], ["law"])
assert.deepEqual(controlOrder, ["helper-before", "law", "helper-after", "law"])
assert.equal(Object.getOwnPropertyDescriptor(controlSelected, "lastIndexOf")?.enumerable, false)
for (const name of ["law", "helper-before", "helper-after", "unknown"]) {
  assert.equal(controlSelected.lastIndexOf(name), controlOrder.lastIndexOf(name))
  assert.equal(controlSelected.lastIndexOf(name, undefined), controlOrder.lastIndexOf(name, undefined))
  assert.equal(controlSelected.lastIndexOf(name, -2), controlOrder.lastIndexOf(name, -2))
  assert.equal(controlSelected.lastIndexOf(name, 1), controlOrder.lastIndexOf(name, 1))
}
assert.throws(() => selectedOrder(controlOrder, []))
assert.throws(() => selectedOrder(controlOrder, ["missing"]))
assert.throws(() => selectedOrder(controlOrder, ["law", "law"]))

if (process.argv[2] === "--source-manifest") {
  if (!compilerRoot) throw Error("Missing BEND_SOURCE_ROOT")
  const Bend = await loadCompiler(compilerRoot)
  const book = Bend.book_nil()
  const seen = new Map<string, string | null>()
  await Bend.book_load(book, proofPath, "", seen)
  Bend.book_valid(book)
  const installedBase = join(homedir(), ".bend/bend2/base.bend")
  assert.equal(
    readFileSync(Bend.BASE_BEND, "utf8"),
    readFileSync(installedBase, "utf8"),
    "Source API and installed CLI must share exact Base bytes"
  )
  seen.set(installedBase, "")
  assert.equal(book.hols, 0)
  process.stdout.write(
    JSON.stringify([...seen.keys()].sort().map((path) => ({ path, sha256: hash(readFileSync(path, "utf8")) }))) + "\n"
  )
  process.exit(0)
}

if (process.argv[2] === "--kernel-root") {
  const cpuLimit = Number(spawnSync("bash", ["-c", "ulimit -t"], { encoding: "utf8" }).stdout.trim())
  assert.ok(cpuLimit > 0 && cpuLimit <= 10, "Kernel worker must inherit the CPU limit")
  const receiptPath = process.env.STREAM_GOAL_ATTESTATION
  if (!receiptPath) throw Error("Private kernel worker requires full-source prerequisite attestation")
  const rawPrerequisite: unknown = JSON.parse(readFileSync(receiptPath, "utf8"))
  const attested = prerequisite(rawPrerequisite)
  assert.equal(process.version, attested.nodeVersion)
  assert.equal(createHash("sha256").update(readFileSync(process.execPath)).digest("hex"), attested.nodeSha256)
  assert.equal(attested.proofSha256, hash(readFileSync(proofPath, "utf8")))
  assert.equal(attested.lawsSha256, hash(readFileSync(lawPath, "utf8")))
  assert.equal(attested.method, "full-source-cli-check-only")
  if (process.env.BENDTT) throw Error("BENDTT override is forbidden")
  const cli = process.env.BEND || "bend"
  assert.equal(spawnSync(cli, ["version"], { encoding: "utf8" }).stdout.trim(), "bend 2.0.39")
  const cliPath = spawnSync("which", [cli], { encoding: "utf8" }).stdout.trim()
  assert.equal(createHash("sha256").update(readFileSync(cliPath)).digest("hex"), attested.cliSha256)
  if (!compilerRoot) throw Error("BEND_SOURCE_ROOT must identify official Bend v2.0.39 sources")
  const commit = spawnSync("git", ["-C", compilerRoot, "rev-parse", "HEAD"], { encoding: "utf8" })
  assert.equal(commit.status, 0)
  assert.equal(commit.stdout.trim(), compilerCommit)
  assert.equal(
    spawnSync("git", ["-C", compilerRoot, "diff", "--quiet", "HEAD", "--", "bend2"], { encoding: "utf8" }).status,
    0,
    "Compiler sources must be unchanged"
  )
  const Bend = await loadCompiler(compilerRoot)
  const Safe = await loadKernel(compilerRoot)
  const book = Bend.book_nil()
  const seen = new Map<string, string | null>()
  await Bend.book_load(book, proofPath, "", seen)
  Bend.book_valid(book)
  const installedBase = join(homedir(), ".bend/bend2/base.bend")
  assert.equal(
    readFileSync(Bend.BASE_BEND, "utf8"),
    readFileSync(installedBase, "utf8"),
    "Source API and installed CLI must share exact Base bytes"
  )
  seen.set(installedBase, "")
  assert.equal(book.hols, 0)
  for (const name of Object.keys(book.tlds)) {
    const declaration = book.tlds[name]
    assert.ok(declaration)
    assert.ok(
      declaration.b === true || (declaration.u !== true && declaration.i === undefined),
      `Unsafe/foreign declaration: ${name}`
    )
  }
  const law = process.argv[3]
  if (!law) throw Error("Missing law root")
  const originalOrder = Object.freeze([...book.order])
  const expectedRoot = `preference-LAWS:${law}`
  assert.equal(
    originalOrder.filter((name: string) => name === expectedRoot).length,
    2,
    "Exactly one law declaration and one proof fill are required"
  )
  const roots = selectedOrder(originalOrder, [expectedRoot])
  assert.equal(roots.length, 1, `Expected one fully resolved root for ${law}`)
  const declaration = book.tlds[expectedRoot]
  assert.ok(declaration)
  assert.notEqual(declaration.b, true, "Law root must not be Base")
  assert.equal(declaration.$, "Def")
  assert.equal(declaration.l, true, "Selected root must be an actual law")
  assert.notEqual(declaration.v, null)
  assert.ok(declaration.e, "Root must be a checked filled definition")
  const proofLines = readFileSync(proofPath, "utf8").split("\n")
  for (const [index, originalLine] of proofLines.entries()) {
    const line = originalLine.trim()
    if (!line || line.startsWith("#")) continue
    if (!/^import(\s|$)/.test(line)) break
    proofLines[index] = ""
  }
  const normalizedProofSha256 = hash(proofLines.join("\n"))
  const originHashes = new Set<string>()
  let proofOrigin = false
  JSON.stringify(declaration.e, (key, value: unknown) => {
    if (key === "s") {
      if (record(value) && record(value.file) && typeof value.file.str === "string") {
        const sourceHash = hash(value.file.str)
        originHashes.add(sourceHash)
        if (sourceHash === normalizedProofSha256 && value.file.ns === "" && value.file.dir === dirname(proofPath) + "/")
          proofOrigin = true
      }
      return undefined
    }
    return value
  })
  assert.ok(proofOrigin, "Filled proof must originate in the loader-normalized attested PROOF source")
  // Safe enumerates roots with iteration, and chooses recursive group order with lastIndexOf.
  // Preserve original group ordering while selecting only this kernel obligation.
  assert.deepEqual([...roots], [expectedRoot])
  assert.equal(roots.lastIndexOf(expectedRoot), originalOrder.lastIndexOf(expectedRoot))
  const omitted = originalOrder.find((name) => name !== expectedRoot)
  assert.ok(omitted)
  assert.ok(!roots.includes(omitted))
  assert.equal(roots.lastIndexOf(omitted), originalOrder.lastIndexOf(omitted))
  book.order = roots
  const sources = [...seen.keys()].sort().map((path) => ({ path, sha256: hash(readFileSync(path, "utf8")) }))
  assert.deepEqual(sources, attested.sources, "Kernel source set must match full-CLI subject")
  const dictionary = book.tlds
  const constructors = book.ctrs
  const templates = book.tmps
  const artifact = join(dirname(receiptPath), `${law}.bendtt`)
  const outside = Safe.safe_emit(book, artifact)
  assert.deepEqual(outside, [], "Selected root must be inside kernel scope")
  const kernelSource = readFileSync(join(homedir(), ".bend/bend2/bendtt.lean"), "utf8")
  assert.equal(kernelSource, readFileSync(join(compilerRoot, "bend2/bendtt.lean"), "utf8"))
  const kernelKey = hash("4.34.0" + "\0" + kernelSource).slice(0, 16)
  const kernel = join(homedir(), ".bend/bendtt", kernelKey, "bendtt")
  const kernelSha256 = createHash("sha256").update(readFileSync(kernel)).digest("hex")
  assert.equal(kernelSha256, attested.kernelSha256)
  const [verdict, output] = Safe.run_read(kernel, [artifact], {
    env: { ...process.env, LEAN_STACK_SIZE_KB: "4194304" }
  })
  assert.equal(verdict.status, 0, JSON.stringify(verdict))
  assert.equal(output.trim(), "ALL PROOFS CHECK")
  assert.deepEqual(
    [...seen.keys()].sort().map((path) => ({ path, sha256: hash(readFileSync(path, "utf8")) })),
    attested.sources,
    "Source snapshot changed during kernel check"
  )
  assert.equal(book.tlds, dictionary)
  assert.equal(book.ctrs, constructors)
  assert.equal(book.tmps, templates)
  process.stdout.write(
    JSON.stringify({
      method: "selected-root-kernel",
      nodeVersion: process.version,
      nodeSha256: attested.nodeSha256,
      workerFlags,
      compilerCommit,
      law,
      root: roots[0],
      lawMarker: declaration.l,
      normalizedProofSha256,
      originHashes: [...originHashes],
      sources,
      cliSha256: attested.cliSha256,
      kernelSha256,
      artifactSha256: hash(readFileSync(artifact, "utf8")),
      checkedTypeSha256: hash(
        JSON.stringify(Bend.term_lower(declaration.T), (key, value: unknown) => (key === "s" ? undefined : value))
      ),
      kernelResult: output.trim(),
      limits: { cpuSeconds: 10, wallSeconds: 60 },
      originalDeclarations: originalOrder.length,
      rootSha256: hash(JSON.stringify(declaration.e, (key, value: unknown) => (key === "s" ? undefined : value)))
    }) + "\n"
  )
  process.exit(0)
}

const mutations = [
  {
    name: "ignored-preference",
    file: "offline-policy/preference.bend",
    before: "case Navigation{_,Some{Preferred{choice,_}}}: Some{choice}",
    after: "case Navigation{policy,Some{Preferred{_,_}}}: current(policy)",
    law: "preferred_selected"
  },
  {
    name: "healthy-cardinal-suppression",
    file: "offline-policy/preference.bend",
    before: "case Navigation{_,Some{Preferred{choice,_}}}: Some{choice}",
    after: "case Navigation{_,Some{Preferred{choice,_}}}: P.suppress_cardinal(Some{choice},False{},False{})",
    law: "preferred_selected"
  },
  {
    name: "score-overrides-advice",
    file: "offline-policy/preference.bend",
    before: "case Navigation{_,Some{Preferred{choice,_}}}: Some{choice}",
    after: "case Navigation{policy,Some{Preferred{choice,_}}}: P.select_retained(current(policy),Some{choice},False{})",
    law: "preferred_selected"
  },
  {
    name: "rebased-cardinal",
    file: "offline-policy/preference.bend",
    before: "is_cardinal(goal),(_ => Some{goal}),(_ => P.find_goal(observed,goal))",
    after: "is_cardinal(goal),(_ => P.find_goal(observed,goal)),(_ => P.find_goal(observed,goal))",
    law: "cardinal_endpoint_pinned"
  },
  {
    name: "physical-proximity-completion",
    file: "offline-policy/preference.bend",
    before: "Bool.and(is_cardinal(goal),F32.is_lt(P.distance(here,P.goal_point(goal)),35.0))",
    after: "F32.is_lt(P.distance(here,P.goal_point(goal)),35.0)",
    law: "physical_not_proximity_complete"
  },
  {
    name: "wrong-steering-target",
    file: "stream-bot.bend",
    before: "P.target(Nav.selected(navigation))",
    after: "P.target(Nav.selected(Nav.step(navigation,Nav.Default{})))",
    law: "stream_steering_uses_selected"
  },
  {
    name: "drop-hostile-shot",
    file: "offline-policy/preference.bend",
    before: "threats(rest,T.Threat{x,y,radius,True{}} <> acc)",
    after: "threats(rest,acc)",
    law: "threats_hostile"
  },
  {
    name: "recycled-goal-identity",
    file: "stream-bot.bend",
    before: "Bool.and(U32.is_eq(g,h),Bool.and(U32.is_eq(k,l)",
    after: "Bool.and(True{},Bool.and(U32.is_eq(k,l)",
    law: "published_identity_exact"
  },
  {
    name: "entrypoint-bypasses-preference",
    file: "stream-bot.bend",
    before: "      planned(policy,run,offers,visible,knowledge,",
    after: "      planned(Nav.step(policy,Nav.Default{}),run,offers,visible,knowledge,",
    law: "public_plan_composition"
  }
]

const workspace = mkdtempSync(join(tmpdir(), "stream-goal-laws-"))
const results: { name: string; law: string; status: string }[] = []
try {
  let sources: { path: string; sha256: string }[] = []
  if (!process.argv.includes("--elaborator-only")) {
    const preflight = limited(process.execPath, [...workerFlags, fileURLToPath(import.meta.url), "--source-manifest"])
    assert.equal(preflight.status, 0, JSON.stringify(preflight))
    const rawSources: unknown = JSON.parse(preflight.output)
    sources = sourceRows(rawSources)
  }
  for (const path of [
    "stream-bot.bend",
    "offline-policy/preference.bend",
    "offline-policy/preference-probe.bend",
    "offline-policy/preference-PROOF.bend"
  ])
    pass(checked(join(root, path)), path)
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (entry.name === "offline-policy" || entry.name === "stream-bot.bend") continue
    symlinkSync(join(root, entry.name), join(workspace, entry.name))
  }
  mkdirSync(join(workspace, "offline-policy"))
  for (const entry of readdirSync(join(root, "offline-policy"))) {
    if (entry === "preference.bend") continue
    symlinkSync(join(root, "offline-policy", entry), join(workspace, "offline-policy", entry))
  }
  const originals = new Map(
    ["stream-bot.bend", "offline-policy/preference.bend"].map((name) => [name, readFileSync(join(root, name), "utf8")])
  )
  for (const name of ["preference-LAWS.bend", "preference-PROOF.bend"]) {
    rmSync(join(workspace, "offline-policy", name))
    writeFileSync(join(workspace, "offline-policy", name), readFileSync(join(root, "offline-policy", name)))
  }
  for (const mutant of mutations) {
    for (const [name, source] of originals) writeFileSync(join(workspace, name), source)
    const original = originals.get(mutant.file)
    assert.ok(original)
    assert.equal(original.split(mutant.before).length, 2, `${mutant.name}: target must occur once`)
    writeFileSync(join(workspace, mutant.file), original.replace(mutant.before, mutant.after))
    pass(checked(join(workspace, "stream-bot.bend")), `${mutant.name}: mutant typecheck`)
    const rejection = checked(join(workspace, "offline-policy/preference-PROOF.bend"))
    assert.equal(rejection.status, 1, `${mutant.name}: mutant survived: ${rejection.output}`)
    assert.ok(
      rejection.output.includes(`Location: L.${mutant.law}`),
      `${mutant.name}: wrong rejection: ${rejection.output}`
    )
    results.push({ name: mutant.name, law: mutant.law, status: "typechecked-and-rejected-by-named-law" })
  }
  process.stdout.write(
    JSON.stringify({ method: "full-source-elaborator", laws: 82, literalProbes: 14, mutants: results }, null, 2) + "\n"
  )
  if (!process.argv.includes("--elaborator-only")) {
    if (!compilerRoot)
      throw Error(
        "Set BEND_SOURCE_ROOT to the unchanged official v2.0.39 checkout; --elaborator-only does not qualify kernel proofs"
      )
    const laws = [...readFileSync(lawPath, "utf8").matchAll(/^law (\w+):/gm)].map((match) => {
      const name = match[1]
      assert.ok(name)
      return name
    })
    assert.equal(laws.length, 82)
    assert.equal(new Set(laws).size, 82)
    if (process.env.BENDTT) throw Error("BENDTT override is forbidden")
    const cli = process.env.BEND || "bend"
    assert.equal(spawnSync(cli, ["version"], { encoding: "utf8" }).stdout.trim(), "bend 2.0.39")
    const cliPath = spawnSync("which", [cli], { encoding: "utf8" }).stdout.trim()
    const kernelSource = readFileSync(join(homedir(), ".bend/bend2/bendtt.lean"), "utf8")
    const kernelKey = hash("4.34.0" + "\0" + kernelSource).slice(0, 16)
    const kernelPath = join(homedir(), ".bend/bendtt", kernelKey, "bendtt")
    for (const source of sources)
      assert.equal(hash(readFileSync(source.path, "utf8")), source.sha256, "Source changed after full-CLI prerequisite")
    const attestation = join(workspace, "attested.json")
    writeFileSync(
      attestation,
      JSON.stringify({
        method: "full-source-cli-check-only",
        sources,
        nodeVersion: process.version,
        nodeSha256: createHash("sha256").update(readFileSync(process.execPath)).digest("hex"),
        proofSha256: hash(readFileSync(proofPath, "utf8")),
        lawsSha256: hash(readFileSync(lawPath, "utf8")),
        cliSha256: createHash("sha256").update(readFileSync(cliPath)).digest("hex"),
        kernelSha256: createHash("sha256").update(readFileSync(kernelPath)).digest("hex")
      }),
      { mode: 0o600 }
    )
    process.env.STREAM_GOAL_ATTESTATION = attestation
    for (const law of laws) {
      const result = limited(process.execPath, [...workerFlags, fileURLToPath(import.meta.url), "--kernel-root", law])
      writeFileSync(join(workspace, `${law}.outcome.json`), JSON.stringify(result))
      assert.equal(result.status, 0, `${law}: ${JSON.stringify(result)}`)
      process.stdout.write(result.output)
    }
  }
} finally {
  if (process.env.STREAM_GOAL_KEEP_WORKSPACE === "1")
    process.stderr.write(JSON.stringify({ retainedWorkspace: workspace }) + "\n")
  else rmSync(workspace, { recursive: true, force: true })
}
