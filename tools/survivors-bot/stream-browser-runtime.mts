import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"
import { setTimeout } from "node:timers/promises"
import { chromium, type BrowserType } from "playwright"

export async function browserRuntime(kind: BrowserType, headed: boolean) {
  if (headed && kind.name() === "chromium") {
    const profile = await mkdtemp(path.join(tmpdir(), "stream-browser-"))
    const process = spawn(
      chromium.executablePath(),
      [
        "--no-sandbox",
        "--no-first-run",
        "--no-default-browser-check",
        "--window-size=1280,900",
        "--remote-debugging-port=0",
        `--user-data-dir=${profile}`,
        "about:blank"
      ],
      { stdio: ["ignore", "ignore", "pipe"] }
    )
    let launchError = ""
    process.on("error", (error) => {
      launchError = error.message
    })
    process.stderr?.on("data", (data: Buffer) => {
      launchError = (launchError + data.toString()).slice(-8192)
    })
    try {
      let port = ""
      for (let attempt = 0; attempt < 100 && !port; attempt++) {
        if (process.exitCode !== null) throw new Error(`Chromium exited before its debugger was ready: ${launchError}`)
        try {
          port = (await readFile(path.join(profile, "DevToolsActivePort"), "utf8")).split("\n")[0] ?? ""
        } catch {
          await setTimeout(100)
        }
      }
      assert(/^\d+$/.test(port), `Chromium debugger did not start: ${launchError}`)
      const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { noDefaults: true })
      const context = browser.contexts()[0]
      assert(context, "Native Chromium did not expose its default context")
      assert(process.pid, "Native Chromium process identity is missing")
      return {
        browser,
        context,
        pid: process.pid,
        launch: "Native Chromium attached with noDefaults; focus and visibility are not emulated",
        close: async () => {
          try {
            await browser.close()
          } finally {
            process.kill("SIGTERM")
            for (let attempt = 0; attempt < 30 && process.exitCode === null && process.signalCode === null; attempt++)
              await setTimeout(100)
            if (process.exitCode === null && process.signalCode === null) process.kill("SIGKILL")
            await rm(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
          }
        }
      }
    } catch (error) {
      process.kill("SIGKILL")
      await rm(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
      throw error
    }
  }
  const executablePath = kind.name() === "webkit" ? process.env.PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH : undefined
  const server = await kind.launchServer({ headless: !headed, ...(executablePath ? { executablePath } : {}) })
  try {
    const browser = await kind.connect(server.wsEndpoint())
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
    const pid = server.process().pid
    assert(pid, "Browser server process identity is missing")
    return {
      browser,
      context,
      pid,
      launch: "Playwright launchServer with standard browser defaults",
      close: async () => {
        try {
          await context.close()
        } finally {
          try {
            await browser.close()
          } finally {
            await server.close()
          }
        }
      }
    }
  } catch (error) {
    await server.close()
    throw error
  }
}
