#!/usr/bin/env node

import {spawn} from "node:child_process";
import {resolve} from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

import {reviewNewsForPublication, writeNewsEditorialReceipt} from "./newsEditorialGate.mjs";

const publisherPath = fileURLToPath(new URL("./contentPublishingLocalBridge.mjs", import.meta.url));

export function parseNewsPublishArguments(argumentsList) {
  const [command, manifestPath, ...remaining] = argumentsList;
  if (command !== "publish" || !manifestPath || manifestPath.startsWith("--")) {
    throw new Error("Usage: newsPublishingLocalBridge.mjs publish <manifest.json> --review <review.json> --receipt <receipt.json> <publisher options>");
  }
  const publisherArgs = [command, manifestPath];
  let reviewPath;
  let receiptPath;
  for (let i = 0; i < remaining.length; i++) {
    const option = remaining[i];
    if (option === "--review" || option === "--receipt") {
      const value = remaining[++i];
      if (!value || value.startsWith("--")) throw new Error(`${option} requires a path.`);
      if (option === "--review") reviewPath = value;
      else receiptPath = value;
    } else {
      publisherArgs.push(option);
    }
  }
  if (!reviewPath || !receiptPath) throw new Error("News publication requires review and receipt paths.");
  return {manifestPath: resolve(manifestPath), reviewPath: resolve(reviewPath),
    receiptPath: resolve(receiptPath), publisherArgs};
}

export async function publishReviewedNews(argumentsList) {
  const options = parseNewsPublishArguments(argumentsList);
  const receipt = await reviewNewsForPublication(options.manifestPath, options.reviewPath);
  await writeNewsEditorialReceipt(options.receiptPath, receipt);
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [publisherPath, ...options.publisherArgs], {
      stdio: "inherit", shell: false,
    });
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (signal) reject(new Error(`News publisher stopped by signal ${signal}.`));
      else if (code !== 0) reject(new Error(`News publisher failed with exit code ${code}.`));
      else resolvePromise(receipt);
    });
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    await publishReviewedNews(process.argv.slice(2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
