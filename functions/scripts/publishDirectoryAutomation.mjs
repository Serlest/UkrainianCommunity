#!/usr/bin/env node
import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {contentAutomationAccessToken, decodeSuccessfulJSON} from "./contentAutomationCredential.mjs";

const projectId = "ukrainiancommunity-dbd5f";
const identity = "uac-directory-automation@ukrainiancommunity-dbd5f.iam.gserviceaccount.com";
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function options(args) {
  const result = {apply: false, file: "", url: ""};
  for (let index = 0; index < args.length; index++) {
    if (args[index] === "--apply") result.apply = true;
    else if (args[index] === "--candidate") result.file = args[++index] ?? "";
    else if (args[index] === "--url") result.url = args[++index] ?? "";
    else throw new Error(`Unknown argument ${args[index]}`);
  }
  if (!result.file || !result.url || !result.url.startsWith("https://")) {
    throw new Error("Usage: --candidate FILE --url PRIVATE_FUNCTION_URL [--apply]");
  }
  return result;
}

async function googleIdentityToken(audience) {
  let accessToken;
  try {
    accessToken = execFileSync("gcloud", ["auth", "print-access-token"],
    {encoding: "utf8", stdio: ["ignore", "pipe", "ignore"]}).trim();
  } catch {
    throw new Error("Local Google identity is unavailable.");
  }
  const endpoint = `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${identity}:generateIdToken`;
  const response = await fetch(endpoint, {method: "POST", headers: {
    Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json",
  }, body: JSON.stringify({audience, includeEmail: true})});
  const data = await decodeSuccessfulJSON(response, "Generate directory automation identity token");
  if (typeof data.token !== "string") throw new Error("Keyless identity token is unavailable.");
  return data.token;
}

async function call(url, identityToken, body) {
  const response = await fetch(url, {method: "POST", headers: {
    Authorization: `Bearer ${identityToken}`, "Content-Type": "application/json",
  }, body: JSON.stringify(body)});
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`Directory bridge rejected request (${response.status}): ${data.error ?? "unknown"}`);
  return data;
}

async function firestoreDocument(path, token) {
  const response = await fetch(`${base}/${path}`, {headers: {Authorization: `Bearer ${token}`}});
  return decodeSuccessfulJSON(response, `Directory read-back ${path}`);
}

export async function publishDirectoryAutomation(args = process.argv.slice(2)) {
  const {apply, file, url} = options(args);
  const manifest = JSON.parse(readFileSync(file, "utf8"));
  if (!manifest || typeof manifest.idempotencyKey !== "string" || !manifest.candidate) {
    throw new Error("Candidate manifest is incomplete.");
  }
  const identityToken = await googleIdentityToken(url);
  const preview = await call(url, identityToken, {...manifest, dryRun: true});
  if (preview.categoryId !== manifest.candidate.categoryId ||
      preview.expectedRevision !== manifest.candidate.expectedRevision ||
      typeof preview.candidateSHA256 !== "string") {
    throw new Error("Directory dry-run receipt differs from the candidate.");
  }
  if (!apply) return {status: "dry_run", ...preview};
  const published = await call(url, identityToken, {...manifest, dryRun: false});
  const readToken = await contentAutomationAccessToken();
  const category = await firestoreDocument(`directoryCategories/${manifest.candidate.categoryId}`, readToken);
  const receipt = await firestoreDocument(`directoryAutomationReceipts/${manifest.idempotencyKey}`, readToken);
  if (category.fields?.payload?.stringValue !== manifest.candidate.nextPayload ||
      Number(category.fields?.revision?.integerValue) !== published.revision ||
      receipt.fields?.candidateSHA256?.stringValue !== preview.candidateSHA256 ||
      Number(receipt.fields?.revision?.integerValue) !== published.revision) {
    throw new Error("Publication returned but production read-back does not match the candidate.");
  }
  return {status: "published_and_verified", categoryId: published.categoryId,
    revision: published.revision, alreadyPublished: published.alreadyPublished === true,
    candidateSHA256: preview.candidateSHA256};
}

if (import.meta.url === `file://${process.argv[1]}`) {
  publishDirectoryAutomation().then((result) => console.log(JSON.stringify(result)))
    .catch((error) => { console.error(error.message); process.exitCode = 1; });
}
