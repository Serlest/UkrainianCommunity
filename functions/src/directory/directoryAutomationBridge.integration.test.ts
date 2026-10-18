import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";
import {db} from "../firebase/admin";
import {processDirectoryAutomationRequest} from "./directoryAutomationBridge";
import {payloadSHA256, validateAutomaticDirectoryChange, type DirectoryAutomationCandidate} from "./directoryAutomationPolicy";
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

test("reviewed content creates one feed event, corrections do not bump it, and new topics do not duplicate sections",
  {skip: !enabled}, async () => {
    const categoryId = `${id}-content`;
    const category = structuredClone(original);
    category.id = categoryId;
    const reference = db.collection("directoryCategories").doc(categoryId);
    const keys: string[] = [];
    const evidence = {url: "https://www.bfa.gv.at/kontakt/", authority: "BFA",
      observedAt: new Date().toISOString(), excerpt: "Bundesamt für Fremdenwesen und Asyl Kontakt"};
    const request = (before: string, after: string, revision: number,
      operation: DirectoryAutomationCandidate["operation"], topicId = "contact", sectionId = "new-section") => {
      const candidate: DirectoryAutomationCandidate = {
        categoryId, topicId, sectionId, expectedRevision: revision,
        previousPayloadSHA256: payloadSHA256(before), nextPayload: after,
        changeClass: "verified-content", field: operation === "add-topic" ? "topic" : "section",
        newValue: operation === "add-topic" ? topicId : sectionId, operation, evidence,
        review: {payloadSHA256: payloadSHA256(after), reviewedAt: new Date().toISOString(),
          bilingualChecked: true, applicabilityChecked: true, noSourceConflict: true,
          scope: "Austria, official contact instructions", statements: [
            {ukrainian: "Офіційний контакт", german: "Offizieller Kontakt", excerpt: evidence.excerpt},
          ]},
      };
      const idempotencyKey = randomUUID(); keys.push(idempotencyKey);
      return {idempotencyKey, dryRun: false, candidate};
    };
    const verifyEvidence = async () => ({url: evidence.url, checkedAt: new Date().toISOString()});
    try {
      const before = JSON.stringify(category);
      await reference.set({id: categoryId, payload: before, revision: 1});
      await reference.collection("recentState").doc("v1").set({schemaVersion: 1,
        knownIDs: directoryMaterials(before).map((material) => material.id)});
      await db.collection("appConfig").doc("directoryCatalog").set({source: "firestore", migrationComplete: true});
      await db.collection("appConfig").doc("directoryAutomation").set({policyVersion: "directory-v1"});
      const next = structuredClone(category);
      next.topics[0].sections.push({...structuredClone(category.topics[0].sections[0]), id: "new-section", order: 1});
      const addition = request(before, JSON.stringify(next), 1, "add-section");
      await assert.rejects(processDirectoryAutomationRequest(addition, {allowLive: true, verifyEvidence}), /not enabled/);
      await db.collection("appConfig").doc("directoryAutomation").update({allowVerifiedContentPublish: true});
      const tampered = structuredClone(next); tampered.summary.german = "Unrelated overwrite";
      const invalid = request(before, JSON.stringify(tampered), 1, "add-section");
      assert.throws(() => validateAutomaticDirectoryChange(invalid.candidate, before, 1), /unrelated/);
      const missingReview = structuredClone(addition.candidate); delete missingReview.review;
      assert.throws(() => validateAutomaticDirectoryChange(missingReview, before, 1), /requires review/);
      await processDirectoryAutomationRequest(addition, {allowLive: true, verifyEvidence});
      const events = () => db.collection("directoryRecentAdditions").where("categoryID", "==", categoryId).get();
      assert.equal((await events()).size, 1);
      assert.equal((await events()).docs[0].data().sectionID, "new-section");
      const replay = await processDirectoryAutomationRequest({...addition, dryRun: true}, {allowLive: true, verifyEvidence});
      assert.equal(replay.alreadyPublished, true);
      const corrected = structuredClone(next);
      corrected.topics[0].sections[1].body = {ukrainian: "Уточнений контакт", german: "Präzisierter Kontakt"};
      const correction = request(JSON.stringify(next), JSON.stringify(corrected), 2, "replace-section");
      await processDirectoryAutomationRequest(correction, {allowLive: true, verifyEvidence});
      assert.equal((await events()).size, 1);
      const withTopic = structuredClone(corrected);
      withTopic.topics.push({...structuredClone(corrected.topics[0]), id: "new-topic", order: 1});
      const newTopic = request(JSON.stringify(corrected), JSON.stringify(withTopic), 3, "add-topic", "new-topic");
      await processDirectoryAutomationRequest(newTopic, {allowLive: true, verifyEvidence});
      assert.equal((await events()).size, 2);
      assert.equal((await events()).docs.filter((doc) => doc.data().topicID === "new-topic").length, 1);
      const repeat = await processDirectoryAutomationRequest(newTopic, {allowLive: true, verifyEvidence});
      assert.equal(repeat.alreadyPublished, true);
      assert.equal((await reference.get()).data()?.revision, 4);
      await assert.rejects(processDirectoryAutomationRequest({...addition, idempotencyKey: randomUUID()},
        {allowLive: true, verifyEvidence}), /stale revision|payload changed/);
    } finally {
      for (const doc of (await db.collection("directoryRecentAdditions").where("categoryID", "==", categoryId).get()).docs) {
        await doc.ref.delete();
      }
      await db.recursiveDelete(reference);
      for (const key of keys) await db.collection("directoryAutomationReceipts").doc(key).delete();
      await db.collection("appConfig").doc("directoryCatalog").delete();
      await db.collection("appConfig").doc("directoryAutomation").delete();
    }
  });
