import {Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";

const options = {region: "europe-west3", maxInstances: 20, enforceAppCheck: false};
const maximumBlocks = 500;

export function parseOrganizationBlockRequest(value: unknown): {organizationId: string; isBlocked: boolean} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "A block request is required.");
  }
  const data = value as Record<string, unknown>;
  const id = typeof data.organizationId === "string" ? data.organizationId.trim() : "";
  if (!id || id.length > 160 || id.includes("/") || id === "." || id === ".." ||
      typeof data.isBlocked !== "boolean" ||
      Object.keys(data).some((key) => !["organizationId", "isBlocked"].includes(key))) {
    throw new HttpsError("invalid-argument", "Invalid organization block request.");
  }
  return {organizationId: id, isBlocked: data.isBlocked};
}

export function organizationBlockPath(actorId: string, organizationId: string): string {
  return `users/${actorId}/blockedOrganizations/${organizationId}`;
}

function receipt(organizationId: string, data: FirebaseFirestore.DocumentData) {
  if (!(data.blockedAt instanceof Timestamp) || typeof data.name !== "string") {
    throw new HttpsError("data-loss", "Invalid organization block record.");
  }
  return {organizationId, name: data.name, blockedAt: data.blockedAt.toDate().toISOString()};
}

export async function readOrganizationBlocks(actorId: string) {
  const snapshot = await db.collection(`users/${actorId}/blockedOrganizations`).limit(maximumBlocks + 1).get();
  if (snapshot.size > maximumBlocks) throw new HttpsError("resource-exhausted", "Too many blocked organizations.");
  return {blocks: snapshot.docs.map((document) => receipt(document.id, document.data()))};
}

export async function changeOrganizationBlock(actorId: string, input: ReturnType<typeof parseOrganizationBlockRequest>) {
  const reference = db.doc(organizationBlockPath(actorId, input.organizationId));
  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (!input.isBlocked) {
      // Unblocking must work even after the organization has been deleted.
      if (existing.exists) transaction.delete(reference);
      return {organizationId: input.organizationId, isBlocked: false, block: null};
    }
    const organization = await transaction.get(db.collection("organizations").doc(input.organizationId));
    if (!organization.exists || organization.get("moderationStatus") !== "approved") {
      throw new HttpsError("not-found", "The public organization is unavailable.");
    }
    if (!existing.exists) {
      const blocks = await transaction.get(reference.parent.limit(maximumBlocks));
      if (blocks.size >= maximumBlocks) throw new HttpsError("resource-exhausted", "Too many blocked organizations.");
    }
    const data = {
      organizationId: input.organizationId,
      name: String(organization.get("name") ?? "Organization").slice(0, 200),
      blockedAt: existing.get("blockedAt") ?? Timestamp.now(),
    };
    transaction.set(reference, data);
    return {organizationId: input.organizationId, isBlocked: true, block: receipt(input.organizationId, data)};
  });
}

// Access is exclusively through authenticated callables. No client Rules changes,
// organization/account mutations, role changes or changes to other users' blocks.
export const getBlockedOrganizations = onCall(options, async (request) => {
  const actor = await requireVerifiedActiveUser(request);
  if (request.data != null && (typeof request.data !== "object" ||
      Array.isArray(request.data) || Object.keys(request.data).length !== 0)) {
    throw new HttpsError("invalid-argument", "This request accepts no user identifiers.");
  }
  return readOrganizationBlocks(actor.uid);
});

export const setOrganizationBlocked = onCall(options, async (request) => {
  const actor = await requireVerifiedActiveUser(request);
  return changeOrganizationBlock(actor.uid, parseOrganizationBlockRequest(request.data));
});
