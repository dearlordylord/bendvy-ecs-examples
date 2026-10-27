import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { createServer } from "node:http"
import { cp, readdir, readFile, stat } from "node:fs/promises"
import path from "node:path"

export type StrategyFault =
  | "healthy"
  | "syntax"
  | "initialize"
  | "smoke-loop"
  | "active-crash"
  | "active-large-error"
  | "active-loop"
  | "malformed"
  | "delayed"

export function goalStrategySource(direction: "east" | "west"): string {
  return `
export const revision = 'goal-${direction}';
export const memoryVersion = 1;
export function decide(observation, memory) {
  let rows = observation.goals;
  while (rows && rows.$ === 'Con') {
    const goal = rows.head;
    if (goal.kind === ${direction === "east" ? 13 : 15})
      return {intention:{$:'GoalChoice',index:goal.index},memory:null,label:'goal-${direction}'};
    rows = rows.tail;
  }
  return {intention:{$:'Default'},memory:null,label:'no-${direction}-candidate'};
}
`
}

export function strategySource({
  label,
  memoryVersion = 1,
  fault = "healthy",
  offer = -1
}: {
  label: string
  memoryVersion?: number
  fault?: StrategyFault
  offer?: number
}): string {
  if (fault === "syntax") return "export const broken = ;"
  if (fault === "initialize") return "throw new Error('acceptance initialization failure')"
  return `
export const revision = ${JSON.stringify(label)};
export const memoryVersion = ${memoryVersion};
let calls = 0;
export ${fault === "delayed" ? "async " : ""}function decide(observation, memory) {
  calls++;
  ${fault === "delayed" ? "await new Promise(resolve => setTimeout(resolve, 200));" : ""}
  ${fault === "smoke-loop" ? "for (;;) {}" : ""}
  ${fault === "active-crash" ? "if (calls > 1) throw new Error('acceptance active failure');" : ""}
  ${fault === "active-large-error" ? "if (calls > 1) throw new Error('acceptance active large failure: ' + 'x'.repeat(1048576));" : ""}
  ${fault === "active-loop" ? "if (calls > 1) for (;;) {}" : ""}
  const count = memory && typeof memory === 'object' && 'count' in memory && typeof memory.count === 'number' ? memory.count + 1 : 1;
  const hasOffers = (observation.phase === 1 || observation.phase === 2) && observation.offers && observation.offers.$ === 'Con';

  let offers = observation.offers, offerCount = 0;
  while (offers && offers.$ === 'Con') { offerCount++; offers = offers.tail; }
  const preferred = ${offer >= 0 ? offer : "observation.fallback === 0 && offerCount > 1 ? 1 : 0"};
  const intention = hasOffers ? {$:'UpgradeChoice', index:preferred} : {$:'Default'};
  return {intention:${fault === "malformed" ? "{$:'UpgradeChoice',index:Infinity}" : "intention"}, memory:{count}, label:${JSON.stringify(label)} + ':memory=' + count};
}
`
}

const mime: Readonly<Record<string, string>> = {
  ".html": "text/html; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webp": "image/webp",
  ".wasm": "application/wasm"
}

export async function fixtureServer(root: string) {
  const files = new Map<string, string>()
  let manifest = ""
  function publish(source: string) {
    const revision = createHash("sha256").update(source).digest("hex")
    const module = `/__stream-check/strategy-${revision}.mjs`
    files.set(module, source)
    manifest = JSON.stringify({ version: 1, revision, module })
    return revision
  }
  publish(strategySource({ label: "acceptance-initial" }))
  const absoluteRoot = path.resolve(root)
  const server = createServer((request, response) => {
    void (async () => {
      try {
        const pathname = new URL(request.url ?? "/", "http://localhost").pathname
        if (pathname === "/__stream-check/strategy.json") {
          response.writeHead(200, { "Content-Type": mime[".json"], "Cache-Control": "no-store" })
          response.end(manifest)
          return
        }
        const fixture = files.get(pathname)
        if (fixture !== undefined) {
          response.writeHead(200, {
            "Content-Type": mime[".mjs"],
            "Cache-Control": "public, max-age=31536000, immutable"
          })
          response.end(fixture)
          return
        }
        const target = path.resolve(absoluteRoot, `.${decodeURIComponent(pathname)}`)
        if (target !== absoluteRoot && !target.startsWith(`${absoluteRoot}${path.sep}`)) {
          response.writeHead(403)
          response.end("Forbidden")
          return
        }
        const item = await stat(target)
        const filename = item.isDirectory() ? path.join(target, "index.html") : target
        const contents = await readFile(filename)
        response.writeHead(200, { "Content-Type": mime[path.extname(filename)] ?? "application/octet-stream" })
        response.end(contents)
      } catch {
        response.writeHead(404)
        response.end("Not found")
      }
    })()
  })
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject)
    server.listen(0, "127.0.0.1", resolve)
  })
  const address = server.address()
  if (!address || typeof address === "string") throw new Error("Fixture server did not bind a TCP address")
  return {
    url: `http://127.0.0.1:${address.port}`,
    manifest: "/__stream-check/strategy.json",
    publish,
    close: () => new Promise<void>((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())))
  }
}

export async function applicationManifest(root: string): Promise<Record<string, string>> {
  const files: Record<string, string> = {}
  async function visit(directory: string) {
    const entries = await readdir(path.join(root, directory), { withFileTypes: true })
    entries.sort((a, b) => a.name.localeCompare(b.name))
    for (const entry of entries) {
      const relative = path.join(directory, entry.name)
      if (entry.isDirectory()) await visit(relative)
      else {
        assert(entry.isFile(), "Application snapshot must contain regular files: " + relative)
        files[relative.split(path.sep).join("/")] = createHash("sha256")
          .update(await readFile(path.join(root, relative)))
          .digest("hex")
      }
    }
  }
  await visit("")
  return files
}
export async function snapshotApplication(root: string, destination: string) {
  const before = await applicationManifest(root)
  await cp(root, destination, { recursive: true, errorOnExist: true, force: false })
  const copied = await applicationManifest(destination)
  const after = await applicationManifest(root)
  assert.deepEqual(after, before, "Source build changed while creating diagnostic snapshot")
  assert.deepEqual(copied, before, "Diagnostic snapshot differs from source build")
  return { files: copied, hash: createHash("sha256").update(JSON.stringify(copied)).digest("hex") }
}
