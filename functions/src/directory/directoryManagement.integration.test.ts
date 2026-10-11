import {strict as assert} from "node:assert";
import {test} from "node:test";

import {db} from "../firebase/admin";
import {saveDirectoryCategory} from "./directoryManagement";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const prefix = `directory-management-${Date.now()}`;
const uid = (role: string) => `${prefix}-${role}`;
const categoryId = `${prefix}-category`;
const payload = (title: string) => JSON.stringify({
  id: categoryId,
  placement: "start",
  order: 1,
  isHidden: false,
  title: {ukrainian: title, german: title},
  summary: {ukrainian: "Короткий опис", german: "Kurzbeschreibung"},
  symbol: "book",
  groups: [{id: "general", title: {ukrainian: "Основне", german: "Allgemein"}, order: 0, isHidden: false}],
  topics: [{
    id: "test-topic", groupID: "general", order: 0, isHidden: false,
    title: {ukrainian: "Тема", german: "Thema"},
    summary: {ukrainian: "Вступ", german: "Einleitung"},
    sections: [{
      id: "test-section", order: 0, isHidden: false,
      title: {ukrainian: "Крок", german: "Schritt"},
      body: {ukrainian: "Пояснення", german: "Erklärung"},
      symbol: "text.book.closed.fill", phoneNumber: null, source: null, contacts: [],
    }],
    sources: [{name: "Official source", url: "https://www.oesterreich.gv.at/"}],
    regionalSections: {},
  }],
});

function request(actor: string, content: string, expectedRevision: number, verified = true) {
  return {
    auth: {uid: uid(actor), token: {email_verified: verified}},
    data: {categoryId, payload: content, expectedRevision},
  } as never;
}

test("directory publishing enforces grants, revisions, validation and history", {skip: !enabled}, async () => {
  const actors = ["owner", "editor", "reader", "inactive"];
  const category = db.collection("directoryCategories").doc(categoryId);
  try {
    for (const actor of actors) {
      await db.collection("users").doc(uid(actor)).set({
        globalRole: actor === "owner" ? "owner" : "user",
        accountStatus: actor === "inactive" ? "deactivated" : "active",
        blockState: "active",
      });
    }
    await assert.rejects(saveDirectoryCategory.run(request("reader", payload("Original"), 0)),
      {code: "permission-denied"});
    await assert.rejects(saveDirectoryCategory.run(request("inactive", payload("Original"), 0)),
      {code: "permission-denied"});
    await assert.rejects(saveDirectoryCategory.run(request("owner", payload("Original"), 0, false)),
      {code: "permission-denied"});

    const first = await saveDirectoryCategory.run(request("owner", payload("Original"), 0));
    assert.equal(first.revision, 1);
    assert.equal((await category.get()).data()?.updatedBy, uid("owner"));
    assert.equal((await category.collection("versions").doc("1").get()).data()?.revision, 1);

    await db.collection("directoryEditors").doc(uid("editor")).set({enabled: true});
    const second = await saveDirectoryCategory.run(request("editor", payload("Updated"), 1));
    assert.equal(second.revision, 2);
    assert.equal((await category.collection("versions").doc("2").get()).data()?.updatedBy, uid("editor"));

    await db.collection("users").doc(uid("editor")).update({accountStatus: "deactivated"});
    await assert.rejects(saveDirectoryCategory.run(request("editor", payload("Suspended"), 2)),
      {code: "permission-denied"});
    await db.collection("users").doc(uid("editor")).update({accountStatus: "active"});

    await assert.rejects(saveDirectoryCategory.run(request("editor", payload("Stale"), 1)),
      {code: "aborted"});
    const withoutSource = JSON.parse(payload("Invalid"));
    withoutSource.topics[0].sources = [];
    await assert.rejects(saveDirectoryCategory.run(request("editor", JSON.stringify(withoutSource), 2)),
      {code: "invalid-argument"});
    await db.collection("directoryEditors").doc(uid("editor")).delete();
    await assert.rejects(saveDirectoryCategory.run(request("editor", payload("Revoked"), 2)),
      {code: "permission-denied"});
    const hiddenGroup = JSON.parse(payload("Hidden group"));
    hiddenGroup.groups[0].isHidden = true;
    const third = await saveDirectoryCategory.run(request("owner", JSON.stringify(hiddenGroup), 2));
    assert.equal(third.revision, 3);
    assert.equal((await category.get()).data()?.revision, 3);
  } finally {
    await db.recursiveDelete(category);
    for (const actor of actors) {
      await db.collection("directoryEditors").doc(uid(actor)).delete();
      await db.recursiveDelete(db.collection("users").doc(uid(actor)));
    }
  }
});
