import {strict as assert} from "node:assert";
import {test} from "node:test";
import type {CallableRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {translationInput, translateContentHandler} from "./service";

test("translation contract rejects unsupported fields and excessive provider input", () => {
  assert.deepEqual(translationInput({kind: "news", texts: ["Новина", "Текст"]}), {kind: "news", texts: ["Новина", "Текст"], source: "uk"});
  assert.equal(translationInput({kind:"announcement",texts:["Text"],source:"de"}).source,"de");
  for (const input of [{kind:"news",texts:["Text"],source:"de"},{kind:"announcement",texts:["Text"],source:"fr"},null, {kind:"news",texts:[]}, {kind:"profile",texts:["a"]}, {kind:"event",texts:[1]}, {kind:"legal",texts:["a".repeat(20001)]}, {kind:"legal",texts:["a".repeat(15000),"b".repeat(15000)]}]) {
    assert.throws(() => translationInput(input));
  }
});
test("translation is authenticated, scoped, bounded and never stores source text", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const uid = "translation-editor-fixture", owner = "translation-owner-fixture";
  const request = (id: string | undefined, kind = "news", verified = true) => ({data:{kind,texts:["Private draft text"]}, auth:id ? {uid:id,token:{email_verified:verified}} : undefined}) as CallableRequest;
  let calls = 0;
  const translate = async (texts: string[]) => { calls++; return texts.map(() => "Übersetzung"); };
  try {
    await db.doc("contentTranslationLimits/_daily").delete();
    for (const id of [uid,owner]) await db.doc(`users/${id}`).set({globalRole:id===owner ? "owner":"user",accountStatus:"active"});
    await assert.rejects(translateContentHandler(request(undefined),translate));
    await assert.rejects(translateContentHandler(request(uid,"news",false),translate));
    await assert.rejects(translateContentHandler(request(uid,"legal"),translate));
    assert.equal(calls,0);
    assert.deepEqual(await translateContentHandler(request(uid),translate),{texts:["Übersetzung"]});
    assert.equal(calls,1);
    await assert.rejects(translateContentHandler(request(uid),translate));
    assert.equal(calls,1);
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
    for (const id of [uid,owner]) { await db.doc(`users/${id}`).delete();await db.doc(`users/${id}/privateTranslationLimits/daily`).delete(); }
  }
});
