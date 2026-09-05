import {createHash} from "node:crypto";

import {
  FieldValue,
  type DocumentData,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {assertActiveUser, requireVerifiedAuth} from "../auth/context";
import {requireLegacyCallableUser as requireVerifiedActiveUser} from "../auth/legacyCallableContext";
import {db} from "../firebase/admin";
import {userPermissionSnapshotFromData} from "../permissions/userPermissions";

export const analyticsConsentStateCollection = "analyticsConsentStates";
export const analyticsConsentReceiptCollection = "analyticsConsentReceipts";
export const analyticsConsentPurposeVersion = "owner-aggregate-analytics-v1";
export const analyticsConsentPrivacyVersion = "2026.13";
export const analyticsConsentDisclosureVersion = "2026-08-25.1";

// The presence-only notice correction leaves the analytics disclosure unchanged.
// Keep explicit grants/withdrawals from released 2026.12 clients valid too.
const mutationPrivacyVersions = new Set(["2026.12", analyticsConsentPrivacyVersion]);

export interface AnalyticsConsentMutationInput {
  enabled: boolean;
  consentID: string;
  locale: "de" | "uk";
  appVersion?: string;
  privacyVersion?: string;
  disclosureVersion?: string;
  existingReceiptOnly?: boolean;
  principalId?: string;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const appVersionPattern = /^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$/;
const disclosureByLocale: Record<AnalyticsConsentMutationInput["locale"], string> = {
  de: "Optional. Sendet tägliche Aufruf- und Aktionssignale an geschützte aggregierte Berichte für Inhaltsverantwortliche. Beim Ausschalten werden nur diese Analysesignale beendet. Kontobezogene Einträge für verwendete Funktionen – darunter dauerhafte Aufruf-Deduplizierung und öffentliche Zähler, Likes, Lesezeichen, Abos und Anmeldungen – werden weiterhin erstellt. Nie für Werbung oder appübergreifendes Tracking.",
  uk: "Необов’язково. Передає щоденні сигнали про перегляди й дії до захищених зведених звітів для власників контенту. Вимкнення зупиняє лише ці аналітичні сигнали. Пов’язані з обліковим записом записи, потрібні для функцій, якими ви користуєтеся,— зокрема постійне усунення повторних переглядів і публічні лічильники, вподобання, збереження, підписки та реєстрації — створюються й надалі. Ніколи не використовуються для реклами чи відстеження між застосунками.",
};

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
  enforceAppCheck: false,
};

export const updateAnalyticsConsent = onCall(
  callableOptions,
  async (request): Promise<{enabled: boolean; consentID: string}> => {
    const input = parseAnalyticsConsentMutation(request.data);
    const auth = input.enabled
      ? await requireVerifiedActiveUser(request)
      : requireVerifiedAuth(request);
    if (input.principalId !== undefined && input.principalId !== auth.uid) {
      throw new HttpsError("permission-denied", "The account changed before consent synchronization.");
    }
    const enabled = await persistAnalyticsConsentMutation(auth.uid, input);
    if (input.enabled && !enabled) {
      throw new HttpsError("failed-precondition", "This consent was withdrawn or superseded. A new consent ID is required.");
    }
    return {enabled: input.enabled, consentID: input.consentID};
  }
);

// Separate name lets new clients negotiate with an older deployed parser.
export const updateAnalyticsConsentV2 = onCall(callableOptions, request => {
  if (typeof request.data?.principalId !== "string") throw invalidConsentMutation();
  return updateAnalyticsConsent.run(request);
});

export function parseAnalyticsConsentMutation(data: unknown): AnalyticsConsentMutationInput {
  if (!isRecord(data)) {
    throw invalidConsentMutation();
  }
  const allowedFields = new Set(["enabled", "consentID", "locale", "appVersion", "privacyVersion", "disclosureVersion", "existingReceiptOnly", "principalId"]);
  if (Object.keys(data).some((field) => !allowedFields.has(field))
    || typeof data.enabled !== "boolean"
    || typeof data.consentID !== "string"
    || !uuidPattern.test(data.consentID)
    || (data.locale !== "de" && data.locale !== "uk")
    || (data.appVersion !== undefined
      && (typeof data.appVersion !== "string" || !appVersionPattern.test(data.appVersion)))) {
    throw invalidConsentMutation();
  }
  if (data.principalId !== undefined && (typeof data.principalId !== "string" || data.principalId.length > 128)) throw invalidConsentMutation();
  if (data.existingReceiptOnly !== undefined && typeof data.existingReceiptOnly !== "boolean") throw invalidConsentMutation();
  if ((data.privacyVersion !== undefined || data.disclosureVersion !== undefined)
    && (!mutationPrivacyVersions.has(data.privacyVersion as string)
      || data.disclosureVersion !== analyticsConsentDisclosureVersion)) {
    throw invalidConsentMutation();
  }
  return {
    enabled: data.enabled,
    consentID: data.consentID,
    locale: data.locale,
    appVersion: data.appVersion,
    ...(data.principalId === undefined ? {} : {principalId: data.principalId as string}),
    ...(data.existingReceiptOnly === undefined ? {} : {existingReceiptOnly: data.existingReceiptOnly as boolean}),
    ...(data.privacyVersion === undefined ? {} : {privacyVersion: data.privacyVersion as string, disclosureVersion: data.disclosureVersion as string}),
  };
}

export function analyticsConsentReceiptID(uid: string, consentID: string): string {
  return createHash("sha256")
    .update(["analytics-consent", uid, consentID].join("\u0000"))
    .digest("hex");
}

export function isCurrentAnalyticsConsent(
  data: DocumentData | undefined,
  consentID: string
): boolean {
  return data?.enabled === true
    && data.consentID === consentID
    && data.purposeVersion === analyticsConsentPurposeVersion
    && (data.withdrawnAt === undefined || data.withdrawnAt === null)
    && compatibleConsentVersions.has(`${data.privacyVersion}|${data.disclosureVersion}`);
}

export async function requireCurrentAnalyticsConsent(
  uid: string,
  consentID: string
): Promise<void> {
  const [snapshot, receipt] = await db.getAll(
    db.collection(analyticsConsentStateCollection).doc(uid),
    db.collection(analyticsConsentReceiptCollection).doc(analyticsConsentReceiptID(uid, consentID))
  );
  if (!isCurrentAnalyticsConsent(snapshot.data(), consentID) || receipt.get("enabled") !== true || receipt.get("withdrawnAt") != null) {
    throw new HttpsError(
      "failed-precondition",
      "A current server-recorded analytics consent is required."
    );
  }
}

// Explicit compatibility for released contracts with unchanged analytics terms.
const compatibleConsentVersions = new Set([
  "2026.1|2026-08-24.1", "2026.10|2026-08-25.1",
  "2026.11|2026-08-25.1", "2026.12|2026-08-25.1",
  "2026.13|2026-08-25.1",
]);

export function consentPrivacyVersion(input: AnalyticsConsentMutationInput): string {
  if (input.privacyVersion !== undefined) return input.privacyVersion;
  if (input.appVersion === "1.0") return "2026.11";
  if (input.appVersion === "1.0.1" || input.appVersion === "1.0.2") return "2026.12";
  throw new HttpsError("failed-precondition", "The displayed consent version is required.");
}

export async function persistAnalyticsConsentMutation(
  uid: string,
  input: AnalyticsConsentMutationInput
): Promise<boolean> {
  const stateReference = db.collection(analyticsConsentStateCollection).doc(uid);
  const receiptReference = db.collection(analyticsConsentReceiptCollection)
    .doc(analyticsConsentReceiptID(uid, input.consentID));
  return db.runTransaction(async (transaction) => {
    const [stateSnapshot, receiptSnapshot, profile] = await transaction.getAll(stateReference, receiptReference, db.doc(`users/${uid}`));
    // Recheck in the commit transaction: account deletion/blocking may finish
    // after the callable's initial authentication check.
    if (!profile.exists) {
      if (input.enabled) throw new HttpsError("permission-denied", "User profile no longer exists.");
      return false;
    }
    if (input.enabled) assertActiveUser(userPermissionSnapshotFromData(uid, profile.data()));
    const state = stateSnapshot.data();
    const receipt = receiptSnapshot.data();
    if (!input.enabled) {
      // A withdrawal arriving before its grant leaves a durable tombstone.
      if (!receiptSnapshot.exists) {
        transaction.create(receiptReference, {
          userId: uid, consentID: input.consentID, enabled: false,
          grantedAt: null, withdrawnAt: FieldValue.serverTimestamp(),
          disclosureLocale: input.locale, appVersion: input.appVersion ?? null,
        });
      } else if (receipt?.enabled !== false || receipt?.withdrawnAt == null) {
        transaction.update(receiptReference, {enabled: false, withdrawnAt: FieldValue.serverTimestamp()});
      }
      if (state?.consentID === input.consentID && state.enabled === true) {
        transaction.update(stateReference, {
          enabled: false, withdrawnAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return false;
    }
    if (receiptSnapshot.exists) {
      const active = receipt?.enabled === true && receipt?.withdrawnAt == null;
      // A delayed grant cannot supersede a newer ID or revive a withdrawal.
      if (!active && state?.consentID === input.consentID && state.enabled === true) {
        transaction.update(stateReference, {
          enabled: false, withdrawnAt: receipt?.withdrawnAt ?? FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return active && state?.enabled === true && state?.consentID === input.consentID;
    }
    if (input.existingReceiptOnly) {
      throw new HttpsError("failed-precondition", "A new explicit consent is required because its original version is unknown.");
    }
    const common = {
      userId: uid, consentID: input.consentID,
      purposeVersion: analyticsConsentPurposeVersion,
      privacyVersion: consentPrivacyVersion(input),
      disclosureVersion: analyticsConsentDisclosureVersion,
      disclosureLocale: input.locale, disclosureText: disclosureByLocale[input.locale],
      appVersion: input.appVersion ?? null, enabled: true,
      grantedAt: FieldValue.serverTimestamp(), withdrawnAt: null,
    };
    transaction.create(receiptReference, common);
    transaction.set(stateReference, {...common, updatedAt: FieldValue.serverTimestamp()});
    return true;
  });
}

function invalidConsentMutation(): HttpsError {
  return new HttpsError("invalid-argument", "The analytics consent mutation is invalid.");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
