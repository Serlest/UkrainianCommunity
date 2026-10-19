#!/usr/bin/env node
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";

const execute = promisify(execFile);

export async function acquireContentPublicationLock({
  invoke,
  wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now = () => Date.now(),
  maxWaitSeconds = 900,
  pollIntervalSeconds = 15,
} = {}) {
  if (!Number.isFinite(maxWaitSeconds) || maxWaitSeconds < 0 || !Number.isFinite(pollIntervalSeconds) || pollIntervalSeconds <= 0) {
    throw new Error("Lock wait limits must be finite and non-negative.");
  }
  const started = now();
  let attempts = 0;
  while (true) {
    attempts += 1;
    const result = await invoke();
    if (result.acquired === true) return {...result, attempts, waitedSeconds: Math.floor((now() - started) / 1000), maxWaitSeconds};
    if (result.reason !== "busy") return {...result, attempts, waitedSeconds: Math.floor((now() - started) / 1000), maxWaitSeconds};
    const elapsedSeconds = (now() - started) / 1000;
    const remainingSeconds = maxWaitSeconds - elapsedSeconds;
    if (remainingSeconds <= 0) return {...result, attempts, waitedSeconds: Math.floor(elapsedSeconds), maxWaitSeconds, reason: "busy_timeout"};
    await wait(Math.min(pollIntervalSeconds, remainingSeconds) * 1000);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [runtime, runId, threadId, command = "publication-acquire"] = process.argv.slice(2);
  try {
    if (!runtime || !runId || !threadId || !["publication-acquire", "news-acquire"].includes(command)) {
      throw new Error("Usage: node contentPublicationLock.mjs <runtime.py> <unique-run-id> <thread-id> [publication-acquire|news-acquire]");
    }
    const result = await acquireContentPublicationLock({
      invoke: async () => JSON.parse((await execute("python3", [runtime, command, "--run-id", runId, "--thread-id", threadId], {timeout: 10_000})).stdout),
    });
    console.log(JSON.stringify(result));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
