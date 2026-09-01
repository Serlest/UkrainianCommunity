import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";

import {
  classifyPlanningHistoryDraft,
  publicationOutcomeForContent,
  summarizeHistoryClassifications,
} from "./contentPlanningHistoryBackfillCore.mjs";

const options = parseOptions(process.argv.slice(2));
const app = initializeApp(
  {credential: applicationDefault(), projectId: options.projectId},
  `content-planning-history-${Date.now()}`
);

try {
  const database = getFirestore(app);
  const [draftSnapshot, newsSnapshot, eventSnapshot] = await Promise.all([
    database.collectionGroup("contentPlanningDrafts").where("state", "==", "completed").get(),
    database.collection("news").get(),
    database.collection("events").get(),
  ]);
  const liveContent = [
    ...newsSnapshot.docs.map((document) => ({
      collection: "news",
      id: document.id,
      data: document.data(),
    })),
    ...eventSnapshot.docs.map((document) => ({
      collection: "events",
      id: document.id,
      data: document.data(),
    })),
  ];
  const classifications = draftSnapshot.docs.map((document) => ({
    reference: document.ref,
    draft: {id: document.id, path: document.ref.path, data: document.data()},
    result: classifyPlanningHistoryDraft(
      {id: document.id, path: document.ref.path, data: document.data()},
      liveContent
    ),
  }));
  const summary = summarizeHistoryClassifications(classifications);
  assertExpectedSummary(summary, options);

  if (options.apply) {
    await applyBackfill(database, classifications);
    await verifyReadBack(classifications);
  }

  console.log(JSON.stringify({
    projectId: options.projectId,
    mode: options.apply ? "apply" : "dry-run",
    summary,
    records: classifications.map(({draft, result}) => ({
      path: draft.path,
      status: result.status,
      reason: result.reason,
      contentPath: result.content
        ? `${result.content.collection}/${result.content.id}`
        : undefined,
      ambiguousPaths: result.matches?.map((item) => `${item.collection}/${item.id}`),
    })),
  }, null, 2));
} finally {
  await deleteApp(app);
}

async function applyBackfill(database, classifications) {
  for (const group of chunks(classifications, 400)) {
    const batch = database.batch();
    for (const item of group) {
      if (item.result.status === "matched") {
        const content = item.result.content;
        batch.update(item.reference, {
          schemaVersion: 3,
          publishedContentId: content.id,
          publishedContentKind: content.collection === "news" ? "news" : "event",
          publishedOrganizationId: content.data.organizationId ?? null,
          publishedOrganizationName: content.data.organizationName ?? null,
          publicationOutcome: publicationOutcomeForContent(content.data),
          historyBackfillStatus: "matched",
          historyBackfilledAt: FieldValue.serverTimestamp(),
        });
      } else if (item.result.status === "unresolved") {
        batch.update(item.reference, {
          schemaVersion: 3,
          publicationOutcome: "unresolved",
          historyBackfillStatus: "unresolved",
          historyBackfilledAt: FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }
}

async function verifyReadBack(classifications) {
  for (const item of classifications) {
    if (!["matched", "unresolved", "alreadyUnresolved"].includes(item.result.status)) continue;
    const snapshot = await item.reference.get();
    if (!snapshot.exists) throw new Error(`Read-back failed: ${item.reference.path} is missing.`);
    if (item.result.status === "matched") {
      if (snapshot.get("publishedContentId") !== item.result.content.id ||
          snapshot.get("schemaVersion") !== 3 ||
          snapshot.get("publishedContentKind") !==
            (item.result.content.collection === "news" ? "news" : "event") ||
          snapshot.get("publishedOrganizationId") !==
            (item.result.content.data.organizationId ?? null) ||
          snapshot.get("publishedOrganizationName") !==
            (item.result.content.data.organizationName ?? null) ||
          snapshot.get("publicationOutcome") !==
            publicationOutcomeForContent(item.result.content.data) ||
          snapshot.get("historyBackfillStatus") !== "matched" ||
          !(snapshot.get("historyBackfilledAt") instanceof Timestamp)) {
        throw new Error(`Read-back failed for matched draft ${item.reference.path}.`);
      }
    } else if (snapshot.get("publishedContentId") ||
        snapshot.get("schemaVersion") !== 3 ||
        snapshot.get("publicationOutcome") !== "unresolved" ||
        snapshot.get("historyBackfillStatus") !== "unresolved" ||
        !(snapshot.get("historyBackfilledAt") instanceof Timestamp)) {
      throw new Error(`Read-back failed for unresolved draft ${item.reference.path}.`);
    }
  }
}

function assertExpectedSummary(summary, options) {
  if (summary.safeResolved !== options.expectedMatched ||
      summary.totalUnresolved !== options.expectedUnresolved ||
      summary.ambiguous !== options.expectedAmbiguous ||
      summary.invalid !== 0) {
    throw new Error(
      `Preflight mismatch: expected resolved/unresolved/ambiguous ` +
      `${options.expectedMatched}/${options.expectedUnresolved}/${options.expectedAmbiguous}, ` +
      `received ${summary.safeResolved}/${summary.totalUnresolved}/${summary.ambiguous}; ` +
      `invalid=${summary.invalid}. No writes were made.`
    );
  }
}

function parseOptions(argumentsList) {
  const values = new Map();
  let apply = false;
  for (const argument of argumentsList) {
    if (argument === "--apply") apply = true;
    else if (argument.startsWith("--") && argument.includes("=")) {
      const separator = argument.indexOf("=");
      values.set(argument.slice(2, separator), argument.slice(separator + 1));
    } else {
      throw new Error(`Unsupported argument: ${argument}`);
    }
  }
  const projectId = required(values.get("project"), "--project");
  if (apply && values.get("confirm-project") !== projectId) {
    throw new Error("--apply requires --confirm-project to exactly match --project.");
  }
  return {
    projectId,
    apply,
    expectedMatched: positiveInteger(values.get("expect-matched") ?? "91", "--expect-matched"),
    expectedUnresolved: nonNegativeInteger(values.get("expect-unresolved") ?? "3", "--expect-unresolved"),
    expectedAmbiguous: nonNegativeInteger(values.get("expect-ambiguous") ?? "0", "--expect-ambiguous"),
  };
}

function required(value, flag) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${flag} is required.`);
  return value.trim();
}

function positiveInteger(value, flag) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${flag} must be a positive integer.`);
  return parsed;
}

function nonNegativeInteger(value, flag) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`${flag} must be a non-negative integer.`);
  return parsed;
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}
