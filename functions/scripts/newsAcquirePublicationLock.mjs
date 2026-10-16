#!/usr/bin/env node
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";

const execute = promisify(execFile);
export async function acquirePublicationLock(runtime, runId, threadId, {
  invoke = async () => JSON.parse((await execute("python3", [runtime, "news-acquire", "--run-id", runId, "--thread-id", threadId], {timeout: 10_000})).stdout),
  wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
} = {}) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    const result = await invoke();
    if (result.acquired === true) return {...result, attempts: attempt};
    if (!["busy", "news_state_busy"].includes(result.reason) || attempt === 3) {
      return {...result, attempts: attempt};
    }
    await wait(15_000);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [runtime, runId, threadId] = process.argv.slice(2);
  try {
    if (!runtime || !runId || !threadId) throw new Error("Usage: node newsAcquirePublicationLock.mjs <runtime.py> <unique-run-id> <thread-id>");
    console.log(JSON.stringify(await acquirePublicationLock(runtime, runId, threadId)));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
