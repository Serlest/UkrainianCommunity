import {createHash} from "node:crypto";
import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireVerifiedActiveUser, assertActiveUser, assertPrivilegedMFA} from "../auth/context";
import {requireLegacyCallableUser} from "../auth/legacyCallableContext";
import {db} from "../firebase/admin";
import {isActiveUser, isOwner, userPermissionSnapshotFromData, type UserPermissionSnapshot} from "../permissions/userPermissions";

import {commandEnabled, compareOrganizationDecisions, organizationRollout} from "./organizationAccessPolicy";
import {recordAccessComparison, withAccessDiagnostics} from "./organizationAccessDiagnostics";

const options = {region: "europe-west3", maxInstances: 20, enforceAppCheck: false};
export const accessPolicyVersion = "organization-actions-v1";
export const accessPolicyConfiguration = "serverConfiguration/organizationAccess";

export function organizationActions(user: UserPermissionSnapshot, organization: DocumentData): string[] {
  if (!isActiveUser(user)) return [];
  const owner = isOwner(user);
  const system = organization.id === "ukrainian-community" || organization.isSystemManaged === true || organization.sourceType === "system";
  const owns = organization.ownerId === user.uid;
  const admin = Array.isArray(organization.adminIds) && organization.adminIds.includes(user.uid);
  const moderator = Array.isArray(organization.moderatorIds) && organization.moderatorIds.includes(user.uid);
  const applicant = organization.submittedByUserId === user.uid
    && ["pendingReview", "needsRevision", "rejected"].includes(organization.moderationStatus);
  const editableApplicant = applicant && organization.moderationStatus !== "rejected";
  const editor = owner || (!system && (owns || admin || moderator));
  const info = owner || (!system && (owns || admin || editableApplicant));
  return [
    ...(info ? ["editInfo"] : []),
    ...(editor ? ["manageContent", "createNews", "editNews", "createEvent", "editEvent", "managePhotos"] : []),
    ...(!system && (owner || owns) ? ["manageTeam", "deleteContent"] : []),
    ...(owner || (!system && owns) ? ["cancelEvent"] : []),
    ...(!system && applicant && ["needsRevision", "rejected"].includes(organization.moderationStatus) ? ["resubmitRequest"] : []),
    ...(!system && (owner || applicant) ? ["deleteOrganization"] : []),
    "viewSubscribers",
  ];
}

export function organizationRevision(data: DocumentData): string | null {
  const time = data.updatedAt;
  return time instanceof Timestamp ? `${time.seconds}:${time.nanoseconds}` : null;
}

export const getOrganizationAccess = onCall(options, request => withAccessDiagnostics(request, "getOrganizationAccess", async correlationId => {
  // Reading UI capabilities must not introduce another MFA challenge. Commands
  // replacing direct writes retain the existing Rules MFA condition below.
  const auth = await requireLegacyCallableUser(request);
  const ids = request.data?.organizationIds;
  if (!Array.isArray(ids) || ids.length > 50 || ids.some(id => !validID(id))) {
    throw new HttpsError("invalid-argument", "Up to 50 organization IDs are required.");
  }
  const unique = [...new Set(ids as string[])];
  const config = await db.doc(accessPolicyConfiguration).get();
  const snapshots = unique.length ? await db.getAll(...unique.map(id => db.doc(`organizations/${id}`))) : [];
  return {
    principalId: auth.uid, schemaVersion: 1, policyVersion: accessPolicyVersion,
    ...organizationRollout(config.data(), auth.uid), correlationId,
    commandsEnabled: organizationRollout(config.data(), auth.uid).commands.updateOrganizationInfo,
    records: snapshots.map(snapshot => {
      const actions = snapshot.exists ? organizationActions(auth.permissions, {...snapshot.data(), id: snapshot.id}) : [];
      for (const mismatch of compareOrganizationDecisions(request.data?.legacyDecisions?.[snapshot.id], actions)) {
        recordAccessComparison(mismatch.action, mismatch.client, mismatch.server, correlationId);
      }
      return {organizationId: snapshot.id, actions};
    }),
  };
}));

const editable = new Set([
  "name", "localizations", "description", "shortDescription", "fullDescription", "city", "languages", "socialLinks",
  "regionScope", "federalState", "imageURL", "logoURL", "coverURL", "contactEmail", "email", "phone", "website",
  "address", "latitude", "longitude", "organizationType", "directoryProfile", "foundedYear", "foundedMonth",
  "telegramURL", "donationURL", "facebookURL", "instagramURL", "whatsappURL", "youtubeURL", "linkedinURL",
  "missionStatement", "contactPerson",
]);

export function parseOrganizationFields(value: unknown): DocumentData {
  if (!record(value) || JSON.stringify(value).length > 100_000 || Object.keys(value).some(key => !editable.has(key))) {
    throw new HttpsError("invalid-argument", "Invalid organization fields.");
  }
  const result: DocumentData = {};
  for (const [key, raw] of Object.entries(value)) {
    if (raw === null) { result[key] = FieldValue.delete(); continue; }
    if (["latitude", "longitude", "foundedYear", "foundedMonth"].includes(key)) {
      if (typeof raw !== "number" || !Number.isFinite(raw)) invalidFields();
    } else if (key === "languages") {
      if (!Array.isArray(raw) || raw.length > 12 || raw.some(x => typeof x !== "string" || x.length > 100)) invalidFields();
    } else if (["socialLinks", "localizations", "directoryProfile"].includes(key)) {
      if (!record(raw)) invalidFields();
      validateNested(key, raw as DocumentData);
    } else {
      const maximum = ({name: 180, description: 1000, city: 160, email: 320, contactEmail: 320, phone: 80, address: 500} as Record<string, number>)[key] ?? 20_000;
      if (typeof raw !== "string" || raw.length > maximum || (key === "name" && raw.trim().length === 0)) invalidFields();
      if ((key.endsWith("URL") || key === "website") && (raw as string).length > 2048) invalidFields();
    }
    result[key] = raw;
  }
  if (record(result.directoryProfile) && record(result.directoryProfile.currentOfferValidUntil)) {
    const time = result.directoryProfile.currentOfferValidUntil.__timestamp;
    if (!record(time) || !Number.isSafeInteger(time.seconds) || !Number.isInteger(time.nanoseconds)) invalidFields();
    try { result.directoryProfile.currentOfferValidUntil = new Timestamp(time.seconds, time.nanoseconds); }
    catch { invalidFields(); }
  }
  return result;
}

function validateNested(key: string, value: DocumentData): void {
  if (key === "socialLinks" && Object.values(value).some(x => typeof x !== "string" || x.length > 2048)) invalidFields();
  if (key === "localizations") {
    if (Object.keys(value).some(k => !["uk", "de"].includes(k))) invalidFields();
    for (const v of Object.values(value)) {
      if (!record(v) || Object.keys(v).some(k => !["name", "shortDescription", "fullDescription", "description", "missionStatement"].includes(k))
        || Object.values(v).some(x => typeof x !== "string" || x.length > 20_000)) invalidFields();
    }
  }
  if (key === "directoryProfile") {
    const keys = ["profileKind", "secondaryCategories", "serviceModes", "serviceArea", "regularHours", "specialHoursNote", "services", "orderURL", "bookingURL", "currentOfferTitle", "currentOfferDetails", "currentOfferURL", "currentOfferValidUntil"];
    if (Object.keys(value).some(k => !keys.includes(k)) || !["community", "business", "restaurant", "specialist", "institution", "mediaProject"].includes(value.profileKind)) invalidFields();
    for (const [field, maximum] of [["secondaryCategories", 2], ["serviceModes", 5], ["services", 8]] as const) {
      if (value[field] !== undefined && (!Array.isArray(value[field]) || value[field].length > maximum)) invalidFields();
    }
    if (value.regularHours !== undefined && (!record(value.regularHours) || Object.keys(value.regularHours).some(k => !["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].includes(k)))) invalidFields();
    // The callable wire format must become a Firestore timestamp, matching Rules.
    if (value.currentOfferValidUntil !== undefined && !record(value.currentOfferValidUntil)) invalidFields();
  }
}

export const updateOrganizationInfo = onCall(options, request => withAccessDiagnostics(request, "updateOrganizationInfo", async () => {
  const auth = await requireVerifiedActiveUser(request);
  const input = request.data;
  if (input?.principalId !== auth.uid) throw new HttpsError("permission-denied", "The account changed before saving.");
  if (!record(input) || !validID(input.organizationId) || !validID(input.operationId)
    || !(input.expectedRevision === null || typeof input.expectedRevision === "string")) invalidFields();
  const fields = parseOrganizationFields(input.fields);
  const org = db.doc(`organizations/${input.organizationId}`);
  const receiptID = createHash("sha256").update(`${auth.uid}\0${input.organizationId}\0${input.operationId}`).digest("hex");
  const receipt = db.doc(`organizationMutationReceipts/${receiptID}`);
  const fingerprint = createHash("sha256").update(stableJSON({fields: input.fields, expectedRevision: input.expectedRevision, targetStatus: input.targetStatus})).digest("hex");
  return db.runTransaction(async transaction => {
    const [profile, snapshot, completed, config] = await transaction.getAll(db.doc(`users/${auth.uid}`), org, receipt, db.doc(accessPolicyConfiguration));
    if (!profile.exists) throw new HttpsError("permission-denied", "User profile no longer exists.");
    const actor = userPermissionSnapshotFromData(auth.uid, profile.data());
    assertActiveUser(actor); assertPrivilegedMFA(auth.token, actor);
    if (completed.exists) {
      if (completed.get("fingerprint") !== fingerprint) throw new HttpsError("already-exists", "Operation ID was reused.");
      return {organizationId: org.id, didChange: false, revision: completed.get("revision")};
    }
    const commandAction = input.targetStatus === "pendingReview" && snapshot.get("moderationStatus") !== "pendingReview" ? "resubmitRequest" : "editInfo";
    if (!commandEnabled(config.data(), auth.uid, "updateOrganizationInfo", commandAction)) {
      throw new HttpsError("failed-precondition", "The organization command is not enabled.");
    }
    if (!snapshot.exists) throw new HttpsError("not-found", "Organization does not exist.");
    const before: DocumentData = {...snapshot.data(), id: org.id};
    const actions = organizationActions(actor, before);
    if (!actions.includes("editInfo") && !(actions.includes("resubmitRequest") && input.targetStatus === "pendingReview")) {
      throw new HttpsError("permission-denied", "Organization editing is not allowed.");
    }
    if (organizationRevision(before) !== input.expectedRevision) throw new HttpsError("aborted", "The organization changed. Reload before saving.");
    const requestState = ["pendingReview", "needsRevision", "rejected"].includes(before.moderationStatus);
    if (input.targetStatus !== before.moderationStatus) {
      if (!requestState || input.targetStatus !== "pendingReview") invalidFields();
      fields.moderationStatus = "pendingReview";
      fields.submittedAt = Timestamp.now();
      fields.reviewMessage = FieldValue.delete(); fields.rejectionReason = FieldValue.delete();
    }
    const merged = {...before, ...input.fields};
    if (typeof merged.name !== "string" || !merged.name.trim() || typeof merged.description !== "string" || typeof merged.city !== "string") invalidFields();
    if (merged.regionScope != null && !["austria", "federalState", "city"].includes(merged.regionScope)) invalidFields();
    const now = Timestamp.now();
    fields.updatedAt = now;
    const revision = `${now.seconds}:${now.nanoseconds}`;
    transaction.update(org, fields);
    transaction.create(receipt, {userId: auth.uid, organizationId: org.id, fingerprint, revision, completedAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + 30 * 24 * 60 * 60 * 1000)});
    return {organizationId: org.id, didChange: true, revision};
  });
}));

function record(value: unknown): value is Record<string, any> { return value !== null && typeof value === "object" && !Array.isArray(value); }
function validID(value: unknown): value is string { return typeof value === "string" && value.length > 0 && value.length <= 200 && !value.includes("/"); }
function invalidFields(): never { throw new HttpsError("invalid-argument", "Invalid organization update."); }

function stableJSON(value: unknown): string { return JSON.stringify(value, (_key, item) => record(item) ? Object.fromEntries(Object.entries(item).sort(([a], [b]) => a.localeCompare(b))) : item); }
