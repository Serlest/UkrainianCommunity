#!/usr/bin/env node
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {acquireContentPublicationLock} from "./contentPublicationLock.mjs";

const execute = promisify(execFile);
export async function acquirePublicationLock(runtime, runId, threadId, options = {}) {
  const invoke = options.invoke ?? (async () => JSON.parse((await execute("python3", [runtime, "news-acquire", "--run-id", runId, "--thread-id", threadId], {timeout: 10_000})).stdout));
  return acquireContentPublicationLock({...options, invoke});
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [runtime, runId, threadId] = process.argv.slice(2);
  try {
    if (!runtime || !runId || !threadId) throw new Error("Usage: node newsAcquirePublicationLock.mjs <runtime.py> <unique-run-id> <thread-id>");
    const result = await acquirePublicationLock(runtime, runId, threadId);
    console.log(JSON.stringify(result));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
