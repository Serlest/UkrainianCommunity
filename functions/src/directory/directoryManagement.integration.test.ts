import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";

import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {db} from "../firebase/admin";
import {deleteDirectoryCategory, saveDirectoryCategory} from "./directoryManagement";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const prefix = `directory-management-${Date.now()}`;
const uid = (role: string) => `${prefix}-${role}`;
const categoryId = `${prefix}-category`;
const payload = (title: string, id = categoryId) => JSON.stringify({
  id,
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

function request(actor: string, content: string, expectedRevision: number, verified = true,
  id = categoryId) {
  return {
    auth: {uid: uid(actor), token: {email_verified: verified}},
    data: {categoryId: id, payload: content, expectedRevision},
  } as never;
}

function deleteRequest(actor: string, id: string, expectedRevision: number) {
  return {
    auth: {uid: uid(actor), token: {email_verified: true}},
    data: {categoryId: id, expectedRevision},
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
    await seedCurrentLegalForIntegration(...actors.map(uid));
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
    await db.collection("users").doc(uid("editor")).update({acceptedTermsVersion: "outdated"});
    await assert.rejects(saveDirectoryCategory.run(request("editor", payload("Outdated consent"), 1)),
      {code: "failed-precondition"});
    await seedCurrentLegalForIntegration(uid("editor"));
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

test("directory deletion removes only custom categories with permission and revision checks",
  {skip: !enabled}, async () => {
    const id = `custom-${randomUUID()}`;
    const category = db.collection("directoryCategories").doc(id);
    try {
      await db.collection("users").doc(uid("owner")).set({
        globalRole: "owner", accountStatus: "active", blockState: "active",
      });
      await db.collection("users").doc(uid("reader")).set({
        globalRole: "user", accountStatus: "active", blockState: "active",
      });
      await seedCurrentLegalForIntegration(uid("owner"), uid("reader"));
      await saveDirectoryCategory.run(request("owner", payload("Custom", id), 0, true, id));
      await assert.rejects(deleteDirectoryCategory.run(deleteRequest("reader", id, 1)),
        {code: "permission-denied"});
      await assert.rejects(deleteDirectoryCategory.run(deleteRequest("owner", id, 0)),
        {code: "invalid-argument"});
      await assert.rejects(deleteDirectoryCategory.run(deleteRequest("owner", id, 2)),
        {code: "aborted"});
      await assert.rejects(deleteDirectoryCategory.run(deleteRequest("owner", categoryId, 3)),
        {code: "invalid-argument"});
      const deleted = await deleteDirectoryCategory.run(deleteRequest("owner", id, 1));
      assert.equal(deleted.revision, 2);
      assert.equal((await category.get()).data()?.isDeleted, true);
      assert.equal((await category.get()).data()?.payload, undefined);
      assert.equal((await category.collection("versions").doc("2").get()).data()?.action, "deleted");
      await assert.rejects(saveDirectoryCategory.run(request("owner", payload("Revived", id), 2,
        true, id)), {code: "failed-precondition"});
    } finally {
      await db.recursiveDelete(category);
      for (const actor of ["owner", "reader"]) {
        await db.recursiveDelete(db.collection("users").doc(uid(actor)));
      }
    }
  });

test("delegated editor deletes ordinary and regional sections and persisted reread stays deleted",
  {skip: !enabled}, async () => {
    const id = `${prefix}-sections`;
    const category = db.collection("directoryCategories").doc(id);
    const editorID = uid("section-editor");
    const readerID = uid("section-reader");
    try {
      for (const actor of [editorID, readerID]) {
        await db.collection("users").doc(actor).set({
          globalRole: "user", accountStatus: "active", blockState: "active",
        });
      }
      await seedCurrentLegalForIntegration(editorID, readerID);
      const grant = db.collection("directoryEditors").doc(editorID);
      await grant.set({enabled: true});
      const original = JSON.parse(payload("Before section deletion", id));
      const topic = original.topics[0];
      topic.sections.push({...topic.sections[0], id: "remaining-section"});
      topic.regionalSections.wien = [
        {...topic.sections[0], id: "regional-delete", source: topic.sources[0]},
        {...topic.sections[0], id: "regional-keep", source: topic.sources[0]},
      ];
      await saveDirectoryCategory.run(request("section-editor", JSON.stringify(original), 0, true, id));
      const changed = JSON.parse(JSON.stringify(original));
      changed.topics[0].sections = changed.topics[0].sections.filter(
        (section: {id: string}) => section.id !== "test-section");
      changed.topics[0].regionalSections.wien = changed.topics[0].regionalSections.wien.filter(
        (section: {id: string}) => section.id !== "regional-delete");
      await saveDirectoryCategory.run(request("section-editor", JSON.stringify(changed), 1, true, id));
      const persisted = (await category.get()).data();
      assert.equal(persisted?.revision, 2);
      assert.equal(persisted?.updatedBy, editorID);
      const reread = JSON.parse(persisted?.payload);
      assert.deepEqual(reread.topics[0].sections.map((section: {id: string}) => section.id),
        ["remaining-section"]);
      assert.deepEqual(reread.topics[0].regionalSections.wien.map((section: {id: string}) => section.id),
        ["regional-keep"]);
      assert.equal(JSON.parse((await category.collection("versions").doc("1").get()).data()?.payload)
        .topics[0].sections.length, 2);
      assert.equal(JSON.parse((await category.collection("versions").doc("2").get()).data()?.payload)
        .topics[0].sections.length, 1);
      await assert.rejects(saveDirectoryCategory.run(
        request("section-editor", JSON.stringify(original), 1, true, id)), {code: "aborted"});
      await assert.rejects(saveDirectoryCategory.run(
        request("section-reader", JSON.stringify(original), 2, true, id)), {code: "permission-denied"});
      await grant.delete();
      await assert.rejects(saveDirectoryCategory.run(
        request("section-editor", JSON.stringify(original), 2, true, id)), {code: "permission-denied"});
      assert.deepEqual((await category.get()).data(), persisted);
    } finally {
      await db.recursiveDelete(category);
      await db.collection("directoryEditors").doc(editorID).delete();
      for (const actor of [editorID, readerID]) await db.recursiveDelete(db.collection("users").doc(actor));
    }
  });
