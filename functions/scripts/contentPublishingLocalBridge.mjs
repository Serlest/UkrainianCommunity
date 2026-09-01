#!/usr/bin/env node

import {spawn} from "node:child_process";
import {resolve} from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

const publisherPath = fileURLToPath(new URL("./publishVerifiedContent.mjs", import.meta.url));

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  run(process.argv.slice(2));
}

export function parsePublishCommand(argumentsList) {
  const [command, ...publisherArguments] = argumentsList;
  if (command !== "publish" || publisherArguments.length === 0) {
    throw new Error(
      "Usage: node scripts/contentPublishingLocalBridge.mjs publish <manifest.json> "
      + "--organization-id <id> (--federal-state <state|austria> | --region-scope <scope>) [--dry-run]"
    );
  }
  return publisherArguments;
}

function run(argumentsList) {
  let publisherArguments;
  try {
    publisherArguments = parsePublishCommand(argumentsList);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
    return;
  }
  const child = spawn(process.execPath, [publisherPath, ...publisherArguments], {
    stdio: "inherit",
    shell: false,
  });
  child.once("error", (error) => {
    console.error(`Publisher could not start: ${error.message}`);
    process.exitCode = 1;
  });
  child.once("exit", (code, signal) => {
    if (signal) {
      console.error(`Publisher stopped by signal ${signal}.`);
      process.exitCode = 1;
      return;
    }
    process.exitCode = code ?? 1;
  });
}
