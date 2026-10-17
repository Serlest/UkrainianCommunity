import {createHash} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {verifyOfficialDirectoryEvidence} from "./directoryAutomationEvidence";
import {
  validateAutomaticDirectoryChange, type DirectoryAutomationCandidate,
} from "./directoryAutomationPolicy";
import {publishDirectoryCategoryInTransaction} from "./directoryPublishTransaction";

const automationActor = "directory-automation-v1";
const receiptCollection = "directoryAutomationReceipts";

interface PublicationRequest {
  idempotencyKey: string;
  dryRun: boolean;
  candidate: DirectoryAutomationCandidate;
}

function parseRequest(body: unknown): PublicationRequest {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error("Expected a JSON publication request.");
  }
  const input = body as Record<string, unknown>;
  if (Object.keys(input).sort().join(",") !== "candidate,dryRun,idempotencyKey" ||
      typeof input.idempotencyKey !== "string" ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(
        input.idempotencyKey) ||
      typeof input.dryRun !== "boolean" || !input.candidate ||
      typeof input.candidate !== "object" || Array.isArray(input.candidate)) {
    throw new Error("Invalid publication request fields.");
  }
  const candidate = input.candidate as DirectoryAutomationCandidate;
  if (typeof candidate.categoryId !== "string" ||
      !/^[a-z0-9][a-z0-9-]{0,63}$/.test(candidate.categoryId) ||
      typeof candidate.nextPayload !== "string" ||
      Buffer.byteLength(candidate.nextPayload, "utf8") > 800_000) {
    throw new Error("Candidate category or payload is invalid.");
  }
  return {idempotencyKey: input.idempotencyKey, dryRun: input.dryRun, candidate};
}

function digest(candidate: DirectoryAutomationCandidate): string {
  return createHash("sha256").update(JSON.stringify(candidate), "utf8").digest("hex");
}

export async function processDirectoryAutomationRequest(
  input: PublicationRequest,
  options: {allowLive: boolean; verifyEvidence?: typeof verifyOfficialDirectoryEvidence}
): Promise<Record<string, unknown>> {
  const {candidate, dryRun, idempotencyKey} = input;
  if (!dryRun && !options.allowLive) {
    throw new Error("Directory automation live publishing is disabled.");
  }
  const candidateSHA256 = digest(candidate);
  if (!dryRun) {
    const existing = await db.collection(receiptCollection).doc(idempotencyKey).get();
    if (existing.exists) {
      if (existing.data()?.candidateSHA256 !== candidateSHA256) {
        throw new Error("Idempotency key was already used for another candidate.");
      }
      return {dryRun: false, alreadyPublished: true,
        categoryId: existing.data()?.categoryId, revision: existing.data()?.revision,
        candidateSHA256};
    }
  }
  const reference = db.collection("directoryCategories").doc(candidate.categoryId);
  const current = await reference.get();
  if (!current.exists || current.data()?.isDeleted === true ||
      typeof current.data()?.payload !== "string") {
    throw new Error("Published category is unavailable.");
  }
  validateAutomaticDirectoryChange(candidate, current.data()!.payload,
    current.data()!.revision, new Date());
  const evidence = await (options.verifyEvidence ?? verifyOfficialDirectoryEvidence)(candidate);
  if (dryRun) {
    return {dryRun: true, categoryId: candidate.categoryId,
      expectedRevision: candidate.expectedRevision, candidateSHA256, evidence};
  }

  return db.runTransaction(async (transaction) => {
    const receiptRef = db.collection(receiptCollection).doc(idempotencyKey);
    const [receipt, migration, permission] = await Promise.all([
      transaction.get(receiptRef),
      transaction.get(db.collection("appConfig").doc("directoryCatalog")),
      transaction.get(db.collection("appConfig").doc("directoryAutomation")),
    ]);
    if (receipt.exists) {
      if (receipt.data()?.candidateSHA256 !== candidateSHA256) {
        throw new Error("Idempotency key was already used for another candidate.");
      }
      return {dryRun: false, alreadyPublished: true,
        categoryId: receipt.data()?.categoryId, revision: receipt.data()?.revision,
        candidateSHA256};
    }
    if (migration.data()?.migrationComplete !== true ||
        migration.data()?.source !== "firestore") {
      throw new Error("Firebase directory catalog migration is not complete.");
    }
    if (permission.data()?.allowLowRiskAutoPublish !== true ||
        permission.data()?.policyVersion !== "directory-v1") {
      throw new Error("Low-risk directory publication is not enabled.");
    }
    const published = await publishDirectoryCategoryInTransaction(transaction, {
      categoryId: candidate.categoryId, payload: candidate.nextPayload,
      expectedRevision: candidate.expectedRevision, updatedBy: automationActor,
      validatePrevious: (payload, revision) => {
        validateAutomaticDirectoryChange(candidate, payload, revision, new Date());
      },
    });
    transaction.create(receiptRef, {
      schemaVersion: 1, categoryId: candidate.categoryId, topicId: candidate.topicId,
      sectionId: candidate.sectionId, federalState: candidate.federalState ?? null,
      changeClass: candidate.changeClass, field: candidate.field,
      expectedRevision: candidate.expectedRevision, revision: published.revision,
      candidateSHA256, sourceURL: evidence.url,
      authority: candidate.evidence.authority,
      evidenceExcerpt: candidate.evidence.excerpt,
      observedAt: candidate.evidence.observedAt, checkedAt: evidence.checkedAt,
      publishedAt: FieldValue.serverTimestamp(),
    });
    return {dryRun: false, alreadyPublished: false, categoryId: candidate.categoryId,
      revision: published.revision, candidateSHA256};
  });
}

/** Cloud IAM must grant invoker only to the dedicated automation identity. */
export const publishDirectoryAutomation = onRequest({
  region: "europe-west3", invoker: "private", maxInstances: 2,
  cors: false, timeoutSeconds: 45,
}, async (request, response) => {
  response.set("Cache-Control", "no-store");
  if (request.method !== "POST" || !request.is("application/json")) {
    response.status(405).json({error: "POST application/json required"});
    return;
  }
  try {
    const input = parseRequest(request.body);
    const result = await processDirectoryAutomationRequest(input, {
      allowLive: process.env.DIRECTORY_AUTOMATION_PUBLISH_ENABLED === "true",
    });
    response.status(200).json(result);
  } catch (error) {
    // Do not expose document bodies or source contents through this endpoint.
    const message = error instanceof Error ? error.message : "Publication failed.";
    const status = /disabled|not enabled|migration is not complete/.test(message) ? 412 :
      /revision|payload changed|already used/.test(message) ? 409 : 400;
    response.status(status).json({error: message});
  }
});
