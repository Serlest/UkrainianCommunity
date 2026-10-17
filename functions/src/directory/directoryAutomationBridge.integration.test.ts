import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";
import {db} from "../firebase/admin";
import {processDirectoryAutomationRequest} from "./directoryAutomationBridge";
import {payloadSHA256, type DirectoryAutomationCandidate} from "./directoryAutomationPolicy";
import {directoryMaterials} from "./directoryRecentModel";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const id = `automation-${Date.now()}`;
const original = {
  id, placement: "support", order: 1, isHidden: false,
  title: {ukrainian: "Підтримка", german: "Unterstützung"},
  summary: {ukrainian: "Опис", german: "Beschreibung"}, symbol: "book",
  groups: [{id: "general", title: {ukrainian: "Основне", german: "Allgemein"}, order: 0, isHidden: false}],
  topics: [{id: "contact", groupID: "general", order: 0, isHidden: false,
    title: {ukrainian: "Контакт", german: "Kontakt"},
    summary: {ukrainian: "Опис", german: "Beschreibung"},
    sections: [{id: "phone", order: 0, isHidden: false,
      title: {ukrainian: "Телефон", german: "Telefon"},
      body: {ukrainian: "Зверніться до органу", german: "Kontaktieren Sie die Behörde"},
      symbol: "phone", phoneNumber: "+43 1 12345",
      source: {name: "BFA", url: "https://www.bfa.gv.at/kontakt/"}, contacts: []}],
    sources: [{name: "BFA", url: "https://www.bfa.gv.at/kontakt/"}], regionalSections: {},
  }],
};

test("restricted bridge preserves the editor transaction, history and idempotency",
  {skip: !enabled}, async () => {
    const categoryRef = db.collection("directoryCategories").doc(id);
    const receiptKey = randomUUID();
    const before = JSON.stringify(original);
    const after = structuredClone(original);
    after.topics[0].sections[0].phoneNumber = "+43 1 99999";
    const candidate: DirectoryAutomationCandidate = {
      categoryId: id, topicId: "contact", sectionId: "phone", expectedRevision: 1,
      previousPayloadSHA256: payloadSHA256(before), nextPayload: JSON.stringify(after),
      changeClass: "official-contact", field: "phoneNumber", newValue: "+43 1 99999",
      evidence: {url: "https://www.bfa.gv.at/kontakt/", authority: "BFA",
        observedAt: new Date().toISOString(), excerpt: "Bundesamt für Fremdenwesen und Asyl: +43 1 99999"},
    };
    const input = {idempotencyKey: receiptKey, dryRun: false, candidate};
    const verifyEvidence = async () => ({url: candidate.evidence.url, checkedAt: new Date().toISOString()});
    try {
      await categoryRef.set({id, payload: before, revision: 1, updatedBy: "bootstrap"});
      await categoryRef.collection("recentState").doc("v1").set({schemaVersion: 1,
        knownIDs: directoryMaterials(before).map((material) => material.id)});
      await db.collection("appConfig").doc("directoryCatalog").set({
        source: "firestore", migrationComplete: true,
      });
      await db.collection("appConfig").doc("directoryAutomation").set({
        allowLowRiskAutoPublish: true, policyVersion: "directory-v1",
      });
      const preview = await processDirectoryAutomationRequest({...input, dryRun: true},
        {allowLive: false, verifyEvidence});
      assert.equal(preview.dryRun, true);
      assert.equal((await categoryRef.get()).data()?.revision, 1);
      await assert.rejects(processDirectoryAutomationRequest(input,
        {allowLive: false, verifyEvidence}), /disabled/);
      const result = await processDirectoryAutomationRequest(input, {allowLive: true, verifyEvidence});
      assert.equal(result.revision, 2);
      assert.equal((await categoryRef.get()).data()?.payload, candidate.nextPayload);
      assert.equal((await categoryRef.collection("versions").doc("2").get()).data()?.updatedBy,
        "directory-automation-v1");
      assert.equal((await db.collection("directoryAutomationReceipts").doc(receiptKey).get()).data()?.revision, 2);
      assert.equal((await db.collection("directoryRecentAdditions").count().get()).data().count, 0);
      const replay = await processDirectoryAutomationRequest(input, {allowLive: true, verifyEvidence});
      assert.equal(replay.alreadyPublished, true);
      assert.equal((await categoryRef.get()).data()?.revision, 2);
      await assert.rejects(processDirectoryAutomationRequest({
        ...input, idempotencyKey: randomUUID(),
      }, {allowLive: true, verifyEvidence}), /stale revision|payload changed/);
    } finally {
      await db.recursiveDelete(categoryRef);
      await db.collection("directoryAutomationReceipts").doc(receiptKey).delete();
      await db.collection("appConfig").doc("directoryCatalog").delete();
      await db.collection("appConfig").doc("directoryAutomation").delete();
    }
  });
