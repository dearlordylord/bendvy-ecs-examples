import assert from "node:assert/strict"
import { test } from "node:test"
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { spawnSync } from "node:child_process"
const builder = fileURLToPath(new URL("./build-stream-strategy.mts", import.meta.url))
const cases: [string, string, RegExp][] = [
  [
    "nonliteral dynamic import",
    "const path = String(memory); await import(path)",
    /unsupported-dynamic-import|not.*bundled/i
  ],
  [
    "external URL import",
    '// @ts-expect-error Remote imports cannot be type-resolved locally.\nawait import("https://example.invalid/policy.mjs")',
    /unbundled imports are unsupported/
  ]
]
for (const [name, body, expected] of cases) {
  void test(`rejects ${name} before replacing a working manifest`, (t) => {
    const dir = mkdtempSync(join(tmpdir(), "stream-strategy-graph-"))
    t.after(() => rmSync(dir, { recursive: true, force: true }))
    const entry = join(dir, "strategy.mts")
    const manifest = join(dir, "stream-strategy.json")
    const previous = '{"previous":"working"}\n'
    writeFileSync(manifest, previous)
    writeFileSync(
      entry,
      `export const revision="test"; export const memoryVersion=1;\nexport async function decide(_observation: unknown, memory: unknown) {\n${body}\nreturn {intention:{$:"Default"},memory:null,label:"test"}\n}`
    )
    const result = spawnSync(process.execPath, [builder, entry, manifest], { encoding: "utf8", timeout: 20000 })
    assert.notEqual(result.status, 0)
    assert.match(result.stdout + result.stderr, expected)
    assert.equal(readFileSync(manifest, "utf8"), previous)
  })
}
