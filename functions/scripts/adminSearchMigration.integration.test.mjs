import {test} from "node:test";
import {strict as assert} from "node:assert";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {Firestore} from "firebase-admin/firestore";
const enabled = process.env.GCLOUD_PROJECT === "demo-uac-admin-search"
  && /^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
test("migration verifies, backfills, activates and rolls back without changing source profiles", {skip: !enabled}, async () => {
  const project = "demo-uac-search-migration";
  const db = new Firestore({projectId: project});
  const ref = db.doc("users/migration-fixture");
  const run = (...args) => promisify(execFile)(process.execPath, [new URL("./backfillAdminUserSearch.mjs", import.meta.url).pathname,
    `--project=${project}`, `--confirm-project=${project}`, ...args]);
  try {
    await ref.set({displayName: "Müller", city: "Wien", email: "test@example.com", globalRole: "user"});
    await assert.rejects(run(), error => error.code === 2 && JSON.parse(error.stdout).mismatched === 1);
    await assert.rejects(run("--activate"), /Index scan has mismatches/);
    const applied = JSON.parse((await run("--apply")).stdout);
    assert.equal(applied.written, 1);
    assert.equal(applied.ready, false);
    const verified = JSON.parse((await run("--activate")).stdout);
    assert.equal(verified.ready, true);
    assert.ok(verified.queryChecks >= 4);
    const profile = (await ref.get()).data();
    delete profile.adminSearchGramsV1;
    assert.deepEqual(profile, {displayName: "Müller", city: "Wien", email: "test@example.com", globalRole: "user"});
    assert.equal(JSON.parse((await run("--disable")).stdout).ready, false);
  } finally {
    await ref.delete();
    await db.doc("internalSearchState/usersV1").delete();
    await db.terminate();
  }
});
