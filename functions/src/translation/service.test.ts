import {strict as assert} from "node:assert";
import {test} from "node:test";
import type {CallableRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {translationInput, translateContentHandler} from "./service";

test("translation contract rejects unsupported fields and excessive provider input", () => {
  assert.deepEqual(translationInput({kind: "news", texts: ["Новина", "Текст"]}), {kind: "news", texts: ["Новина", "Текст"], source: "uk"});
  assert.deepEqual(translationInput({kind: "news", texts: ["Текст"], organizationId: "org-123"}),
    {kind: "news", texts: ["Текст"], source: "uk", organizationId: "org-123"});
  assert.equal(translationInput({kind:"announcement",texts:["Text"],source:"de"}).source,"de");
  assert.equal(translationInput({kind: "directory", texts: ["Text"], source: "de"}).source, "de");
  for (const input of [{kind:"news",texts:["Text"],source:"de"},{kind:"announcement",texts:["Text"],source:"fr"},null, {kind:"news",texts:[]}, {kind:"profile",texts:["a"]}, {kind:"event",texts:[1]}, {kind:"legal",texts:["a".repeat(100001)]}, {kind:"legal",texts:["a".repeat(60000),"b".repeat(60000)]}, {kind:"news",texts:["a"],organizationId:"bad/id"}, {kind:"legal",texts:["a"],organizationId:"org-123"}]) {
    assert.throws(() => translationInput(input));
  }
});
test("translation is authenticated, scoped, bounded and never stores source text", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const uid = "translation-editor-fixture", owner = "translation-owner-fixture";
  const outsider = "translation-outsider-fixture", moderator = "translation-moderator-fixture";
  const orgID = "translation-fixture-org", pendingOrgID = "translation-pending-fixture-org";
  const request = (id: string | undefined, kind = "news", verified = true, organizationId?: string) => ({
    data: {kind, texts: ["Private draft text"],
      ...(["news", "event", "organization"].includes(kind) && id !== owner
        ? {organizationId: organizationId ?? orgID} : {})},
    auth: id ? {uid: id, token: {email_verified: verified}} : undefined,
  }) as CallableRequest;
  let calls = 0;
  const translate = async (texts: string[]) => { calls++; return texts.map(() => "Übersetzung"); };
  try {
    await db.doc("contentTranslationLimits/_daily").delete();
    for (const id of [uid, owner, outsider, moderator]) {
      await db.doc(`users/${id}`).set({globalRole:id===owner ? "owner":"user",accountStatus:"active"});
    }
    await seedCurrentLegalForIntegration(uid, owner, outsider, moderator);
    await db.doc(`organizations/${orgID}`).set({ownerId: uid, adminIds: [], moderatorIds: [moderator], moderationStatus: "approved"});
    await db.doc(`organizations/${pendingOrgID}`).set({submittedByUserId: outsider, moderationStatus: "needsRevision"});
    await assert.rejects(translateContentHandler(request(undefined),translate));
    await assert.rejects(translateContentHandler(request(uid,"news",false),translate));
    await assert.rejects(translateContentHandler(request(uid,"legal"),translate));
    await assert.rejects(translateContentHandler(request(outsider), translate), {code: "permission-denied"});
    const outsiderLegacy = request(outsider);
    delete outsiderLegacy.data.organizationId;
    await assert.rejects(translateContentHandler(outsiderLegacy, translate), {code: "permission-denied"});
    await assert.rejects(translateContentHandler(request(uid, "news", true, "unknown-org"), translate), {code: "permission-denied"});
    await assert.rejects(translateContentHandler(request(uid, "directory"), translate), {code: "permission-denied"});
    await db.doc(`directoryEditors/${uid}`).set({enabled: true});
    const directory = request(uid, "directory"); directory.data.source = "de";
    assert.deepEqual(await translateContentHandler(directory, async (_texts, source, target) => {
      assert.equal(source, "de"); assert.equal(target, "uk"); return ["Переклад"];
    }), {texts: ["Переклад"]});
    await db.doc(`directoryEditors/${uid}`).update({enabled: false});
    await assert.rejects(translateContentHandler(directory, translate), {code: "permission-denied"});
    await db.doc(`users/${uid}/privateTranslationLimits/daily`).delete();
    assert.equal(calls,0);
    const editorLegacy = request(uid);
    delete editorLegacy.data.organizationId;
    assert.deepEqual(await translateContentHandler(editorLegacy,translate),{texts:["Übersetzung"]});
    assert.equal(calls,1);
    assert.deepEqual(await translateContentHandler(request(moderator,"event"), translate),{texts:["Übersetzung"]});
    assert.deepEqual(await translateContentHandler(request(outsider,"organization",true,pendingOrgID), translate),
      {texts:["Übersetzung"]});
    await assert.rejects(translateContentHandler(request(outsider,"news",true,pendingOrgID), translate),
      {code: "permission-denied"});
    await db.doc(`organizations/${orgID}`).update({ownerId: outsider});
    await assert.rejects(translateContentHandler(request(uid), translate), {code: "permission-denied"});
    await db.doc(`organizations/${orgID}`).update({ownerId: uid});
    await assert.rejects(translateContentHandler(request(uid),translate));
    assert.equal(calls,3);
    assert.equal(JSON.stringify((await db.doc(`users/${uid}/privateTranslationLimits/daily`).get()).data()).includes("Private draft"),false);
    await db.doc(`users/${uid}/privateTranslationLimits/daily`).set({day:Math.floor(Date.now()/86400000),count:40,chars:100,lastAt:0});
    await assert.rejects(translateContentHandler(request(uid),translate));
    assert.deepEqual(await translateContentHandler(request(owner,"legal"),translate),{texts:["Übersetzung"]});
    await db.doc(`users/${owner}/privateTranslationLimits/daily`).delete();
    const reverse = request(owner,"announcement"); reverse.data.source = "de";
    assert.deepEqual(await translateContentHandler(reverse, async (texts, source, target) => {
      assert.equal(source,"de"); assert.equal(target,"uk"); assert.deepEqual(texts,["Private draft text"]);
      return ["Переклад"];
    }),{texts:["Переклад"]});
    await db.doc(`users/${uid}/privateTranslationLimits/daily`).set({day:Math.floor(Date.now()/86400000),count:1,chars:150000,lastAt:0});
    await assert.rejects(translateContentHandler(request(uid),translate));
    await db.doc(`users/${uid}/privateTranslationLimits/daily`).delete();
    await db.doc("contentTranslationLimits/_daily").set({day:Math.floor(Date.now()/86400000),chars:1000000});
    await assert.rejects(translateContentHandler(request(uid),translate));
    await db.doc("contentTranslationLimits/_daily").delete();
    await assert.rejects(translateContentHandler(request(uid),async () => { throw new Error("provider unavailable"); }));
    await db.doc(`users/${uid}`).update({accountStatus:"blocked"});
    await assert.rejects(translateContentHandler(request(uid),translate));
    await db.doc(`users/${owner}`).update({requiresMultiFactorAuth:true});
    await assert.rejects(translateContentHandler(request(owner,"legal"),translate));
  } finally {
    await db.doc("contentTranslationLimits/_daily").delete();
    await db.doc(`directoryEditors/${uid}`).delete();
    await db.doc(`organizations/${orgID}`).delete();
    await db.doc(`organizations/${pendingOrgID}`).delete();
    for (const id of [uid, owner, outsider, moderator]) {
      await db.doc(`users/${id}`).delete();
      await db.doc(`users/${id}/privateTranslationLimits/daily`).delete();
    }
  }
});

test("owner translates a complete long German legal document to Ukrainian within existing quota", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const uid = "legal-translation-long-owner";
  await db.doc(`users/${uid}`).set({globalRole: "owner", accountStatus: "active"});
  await seedCurrentLegalForIntegration(uid);
  await db.doc("contentTranslationLimits/_daily").delete();
  const text = "# Hallo\n\n" + "Hallo paragraph with complete legal content.\n".repeat(900);
  let batches = 0;
  try {
    const result = await translateContentHandler({data: {kind: "legal", source: "de", texts: [text]},
      auth: {uid, token: {email_verified: true}}} as CallableRequest, async (texts, source, target) => {
      assert.equal(source, "de"); assert.equal(target, "uk"); batches++;
      return texts.map(t => t.replaceAll("Hallo", "Вітаю"));
    });
    assert.deepEqual(result.texts, [text.replaceAll("Hallo", "Вітаю")]);
    assert.ok(batches > 1);
    const quota = (await db.doc(`users/${uid}/privateTranslationLimits/daily`).get()).data();
    assert.equal(quota?.count, 1);
    assert.equal(JSON.stringify(quota).includes("paragraph"), false);
  } finally {
    await db.doc(`users/${uid}/privateTranslationLimits/daily`).delete();
    await db.doc(`users/${uid}`).delete();
    await db.doc("contentTranslationLimits/_daily").delete();
  }
});
