import {execFileSync} from "node:child_process";
import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

const project = "uac-android-test-20260903";
const originalBucket = "ukrainiancommunity-dbd5f[.]firebasestorage[.]app";
const stagingBucket = "uac-android-test-20260903[.]firebasestorage[.]app";
const sourcePath = fileURLToPath(new URL("../../Firebase/firestore.rules", import.meta.url));
const original = readFileSync(sourcePath, "utf8");
if (original.split(originalBucket).length !== 2 || original.includes(stagingBucket))
  throw new Error("Expected exactly one canonical avatar bucket rule");
const staging = original.replace(originalBucket, stagingBucket);
const digest = value => createHash("sha256").update(value).digest("hex");
const token = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const rulesApi = "https://firebaserules.googleapis.com/v1/";
const headers = {authorization: `Bearer ${token}`, "x-goog-user-project": project};
const releaseName = `projects/${project}/releases/cloud.firestore`;
async function rulesetSource(name) {
  const ruleset = await fetch(`${rulesApi}${name}`, {headers});
  if (!ruleset.ok) throw new Error(`Staging ruleset read HTTP ${ruleset.status}`);
  const {source} = await ruleset.json();
  if (source.files?.length !== 1 ||
    !["firestore.rules", "/firestore.rules"].some(end => source.files[0].name.endsWith(end)))
    throw new Error("Unexpected staging ruleset source layout");
  return source.files[0].content;
}
async function activeSource() {
  const release = await fetch(`${rulesApi}projects/${project}/releases/cloud.firestore`, {headers});
  if (!release.ok) throw new Error(`Staging release read HTTP ${release.status}`);
  const {rulesetName} = await release.json();
  return {name: rulesetName, content: await rulesetSource(rulesetName)};
}

const before = await activeSource();
if (before.content !== original && before.content !== staging)
  throw new Error(`Staging rules changed independently: ${digest(before.content)}`);
if (before.content !== staging) {
  // The Firebase CLI may upload a valid ruleset and then fail to create an already existing
  // release. Reuse that upload when present; otherwise create exactly one ruleset.
  const recent = await fetch(`${rulesApi}projects/${project}/rulesets?pageSize=10`, {headers});
  if (!recent.ok) throw new Error(`Staging ruleset list HTTP ${recent.status}`);
  const names = (await recent.json()).rulesets?.map(row => row.name) ?? [];
  let rulesetName;
  for (const name of names) {
    if (await rulesetSource(name) === staging) { rulesetName = name; break; }
  }
  if (!rulesetName) {
    const created = await fetch(`${rulesApi}projects/${project}/rulesets`, {method: "POST",
      headers: {...headers, "content-type": "application/json"},
      body: JSON.stringify({source: {files: [{name: "firestore.rules", content: staging}]}})});
    if (!created.ok) throw new Error(`Staging ruleset create HTTP ${created.status}: ${(await created.text()).slice(0, 400)}`);
    rulesetName = (await created.json()).name;
  }
  if ((await activeSource()).name !== before.name) throw new Error("Staging release changed during preparation");
  const patched = await fetch(`${rulesApi}${releaseName}`, {method: "PATCH",
    headers: {...headers, "content-type": "application/json"},
    body: JSON.stringify({release: {name: releaseName, rulesetName}, updateMask: "rulesetName"})});
  if (!patched.ok) throw new Error(`Staging release patch HTTP ${patched.status}: ${(await patched.text()).slice(0, 400)}`);
}
const after = await activeSource();
if (after.content !== staging) throw new Error("Staging avatar rules read-back mismatch");
console.log(`Staging-only avatar rule active, SHA-256 ${digest(after.content)}; production source SHA-256 ${digest(original)}`);
