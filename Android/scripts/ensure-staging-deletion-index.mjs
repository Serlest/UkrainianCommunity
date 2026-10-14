import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

const project = "uac-android-test-20260903";
const indexManifest = JSON.parse(readFileSync(fileURLToPath(
  new URL("../../Firebase/firestore.indexes.json", import.meta.url)), "utf8"));
const declared = indexManifest.fieldOverrides?.find(row =>
  row.collectionGroup === "notificationInbox" && row.fieldPath === "actorUserId");
if (!declared?.indexes?.some(row => row.queryScope === "COLLECTION_GROUP" &&
  row.order === "ASCENDING")) throw new Error("Deletion index is absent from the source manifest");
const token = execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim();
const headers = {authorization: `Bearer ${token}`, "x-goog-user-project": project};
const base = "https://firestore.googleapis.com/v1/";
const name = `projects/${project}/databases/(default)/collectionGroups/notificationInbox/fields/actorUserId`;
async function field() {
  const response = await fetch(`${base}${name}`, {headers});
  if (!response.ok) throw new Error(`Staging field read HTTP ${response.status}`);
  return response.json();
}
const current = await field();
const indexes = current.indexConfig?.indexes ?? [];
const signature = row => `${row.queryScope}:${row.fields?.[0]?.fieldPath}:${row.fields?.[0]?.order ?? row.fields?.[0]?.arrayConfig}`;
const required = "COLLECTION_GROUP:actorUserId:ASCENDING";
if (!indexes.some(row => signature(row) === required)) {
  const expected = new Set(["COLLECTION:actorUserId:ASCENDING",
    "COLLECTION:actorUserId:DESCENDING", "COLLECTION:actorUserId:CONTAINS"]);
  if (indexes.length !== 3 || indexes.some(row => !expected.delete(signature(row))) || expected.size)
    throw new Error("Unexpected staging actorUserId indexes; refusing to replace them");
  const response = await fetch(`${base}${name}?updateMask=indexConfig`, {method: "PATCH",
    headers: {...headers, "content-type": "application/json"},
    body: JSON.stringify({indexConfig: {indexes: [...indexes.map(row => ({queryScope: row.queryScope,
      fields: row.fields.map(item => ({fieldPath: item.fieldPath,
        ...(item.order ? {order: item.order} : {arrayConfig: item.arrayConfig})}))})),
    {queryScope: "COLLECTION_GROUP", fields: [{fieldPath: "actorUserId", order: "ASCENDING"}]}]}})});
  if (!response.ok) throw new Error(`Staging index update HTTP ${response.status}: ${(await response.text()).slice(0, 450)}`);
  const operation = await response.json();
  if (!operation.name) throw new Error("Staging index update returned no operation");
  for (let attempt = 0; attempt < 90; attempt++) {
    const status = await fetch(`${base}${operation.name}`, {headers});
    if (!status.ok) throw new Error(`Index operation read HTTP ${status.status}`);
    const result = await status.json();
    if (result.error) throw new Error(`Index operation failed: ${result.error.code}`);
    if (result.done) break;
    if (attempt === 89) throw new Error("Staging index did not become ready in 15 minutes");
    await new Promise(resolve => setTimeout(resolve, 10_000));
  }
}
const after = await field();
const ready = after.indexConfig?.indexes?.find(row => signature(row) === required);
if (!ready || ready.state !== "READY" || after.indexConfig.indexes.length !== 4)
  throw new Error("Staging deletion index read-back is incomplete");
console.log("Staging notificationInbox.actorUserId collection-group index READY; 3 existing indexes preserved");
