import { strict as assert } from "node:assert";
import { after, before, test } from "node:test";

import { db } from "../firebase/admin";
import { deletePushRegistrationsForUser } from "./pushRegistrationMutations";

const shouldRun = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const userId = "push-registration-cleanup-integration";
const fid = "a123456789012345678901";
const userReference = db.collection("users").doc(userId);

before(async () => {
  if (shouldRun) {
    await db.recursiveDelete(userReference);
  }
});

after(async () => {
  if (shouldRun) {
    await db.recursiveDelete(userReference);
  }
});

test("FID cleanup paginates and preserves another installation", { skip: !shouldRun }, async () => {
  const registrations = userReference.collection("notificationPushTokens");
  const setup = db.batch();
  setup.set(registrations.doc("current-fid"), {
    token: fid,
    registrationType: "fid",
  });
  for (let index = 0; index < 251; index += 1) {
    setup.set(registrations.doc(`legacy-${String(index).padStart(3, "0")}`), {
      token: `${fid}:legacy-${index}`,
    });
  }
  setup.set(registrations.doc("other-device"), {
    token: "b123456789012345678901:other-device-token",
  });
  await setup.commit();

  const deletedCount = await deletePushRegistrationsForUser(userId, {
    userId,
    identifier: fid,
    registrationType: "fid",
  });
  const remaining = await registrations.get();

  assert.equal(deletedCount, 252);
  assert.deepEqual(remaining.docs.map((document) => document.id), ["other-device"]);
});
