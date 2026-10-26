import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { build } from "esbuild"
import { createHash } from "node:crypto"
import { mkdir, writeFile, rename } from "node:fs/promises"
import { dirname, resolve } from "node:path"
const entry = resolve(process.argv[2] ?? "examples/survivors/stream-strategy.mts")
const manifest = resolve(process.argv[3] ?? "examples/survivors/dist/stream-strategy.json")
const root = fileURLToPath(new URL("../../", import.meta.url))
const checked = spawnSync(
  process.execPath,
  [
    resolve(root, "node_modules/typescript/bin/tsc"),
    "--ignoreConfig",
    "--noEmit",
    "--strict",
    "--target",
    "ES2023",
    "--module",
    "NodeNext",
    "--moduleResolution",
    "NodeNext",
    "--skipLibCheck",
    "--allowImportingTsExtensions",
    "--allowJs",
    "--checkJs",
    entry,
    resolve(root, ".typescript/bend.d.ts")
  ],
  { stdio: "inherit" }
)
if (checked.status !== 0) throw Error("Strategy type checking failed; previous manifest is unchanged")
const result = await build({
  entryPoints: [entry],
  bundle: true,
  write: false,
  format: "esm",
  platform: "browser",
  target: "es2023"
})
const output = result.outputFiles?.[0]
if (!output) throw Error("No strategy bundle was produced")
const revision = createHash("sha256").update(output.contents).digest("hex")
const module = `stream-strategy-${revision}.mjs`
await mkdir(dirname(manifest), { recursive: true })
await writeFile(resolve(dirname(manifest), module), output.contents)
await writeFile(`${manifest}.tmp`, JSON.stringify({ version: 1, revision, module }) + "\n")
await rename(`${manifest}.tmp`, manifest)
process.stdout.write(`${manifest}\n${revision}\n`)
