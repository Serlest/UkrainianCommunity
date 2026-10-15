import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

const project = "uac-android-test-20260903";
const targets = [["organizationBookmarks", "organizationId"], ["recentViews", "itemId"],
  ["notificationInbox", "actionTargetId"]];
const manifest = JSON.parse(readFileSync(fileURLToPath(
  new URL("../../Firebase/firestore.indexes.json", import.meta.url)), "utf8"));
const token = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const headers = {authorization: `Bearer ${token}`, "x-goog-user-project": project};
const base = "https://firestore.googleapis.com/v1/";
const name = (collection, fieldPath) =>
  `projects/${project}/databases/(default)/collectionGroups/${collection}/fields/${fieldPath}`;
const signature = row => `${row.queryScope}:${row.fields?.[0]?.fieldPath}:${row.fields?.[0]?.order ?? row.fields?.[0]?.arrayConfig}`;
async function field(collection, fieldPath) {
  const response = await fetch(`${base}${name(collection, fieldPath)}`, {headers});
  if (!response.ok) throw new Error(`Staging field read HTTP ${response.status}: ${collection}.${fieldPath}`);
  return response.json();
}
for (const [collection, fieldPath] of targets) {
  const declared = manifest.fieldOverrides?.find(row =>
    row.collectionGroup === collection && row.fieldPath === fieldPath);
  if (!declared?.indexes?.some(row => row.queryScope === "COLLECTION_GROUP" && row.order === "ASCENDING"))
    throw new Error(`${collection}.${fieldPath} index absent from source`);
  const indexes = (await field(collection, fieldPath)).indexConfig?.indexes ?? [];
  if (indexes.some(row => signature(row) === `COLLECTION_GROUP:${fieldPath}:ASCENDING`)) continue;
  const expected = new Set([`COLLECTION:${fieldPath}:ASCENDING`,
    `COLLECTION:${fieldPath}:DESCENDING`, `COLLECTION:${fieldPath}:CONTAINS`]);
  if (indexes.length !== 3 || indexes.some(row => !expected.delete(signature(row))) || expected.size)
    throw new Error(`Unexpected ${collection}.${fieldPath} indexes; refusing update`);
  const response = await fetch(`${base}${name(collection, fieldPath)}?updateMask=indexConfig`, {method: "PATCH",
    headers: {...headers, "content-type": "application/json"},
    body: JSON.stringify({indexConfig: {indexes: [...indexes.map(row => ({queryScope: row.queryScope,
      fields: row.fields.map(item => ({fieldPath: item.fieldPath,
        ...(item.order ? {order: item.order} : {arrayConfig: item.arrayConfig})}))})),
    {queryScope: "COLLECTION_GROUP", fields: [{fieldPath, order: "ASCENDING"}]}]}})});
  if (!response.ok) throw new Error(`Staging index update HTTP ${response.status}: ${collection}.${fieldPath}`);
  if (!(await response.json()).name) throw new Error(`Staging index update returned no operation: ${collection}.${fieldPath}`);
}
for (let attempt = 0; attempt < 90; attempt++) {
  const ready = await Promise.all(targets.map(async ([collection, fieldPath]) => {
    const indexes = (await field(collection, fieldPath)).indexConfig?.indexes ?? [];
    return indexes.length === 4 && indexes.every(row => row.state === "READY") &&
      indexes.some(row => signature(row) === `COLLECTION_GROUP:${fieldPath}:ASCENDING`);
  }));
  if (ready.every(Boolean)) {
    console.log("Staging organization deletion indexes READY for bookmarks, recent views and notification target");
    process.exit(0);
  }
  if (attempt === 89) throw new Error("Staging deletion reference indexes not READY in 15 minutes");
  await new Promise(resolve => setTimeout(resolve, 10_000));
}
