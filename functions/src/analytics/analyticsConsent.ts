import {createHash} from "node:crypto";

import {
  FieldValue,
  type DocumentData,
  type DocumentReference,
  type Transaction,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser, requireVerifiedAuth} from "../auth/context";
import {db} from "../firebase/admin";

export const analyticsConsentStateCollection = "analyticsConsentStates";
export const analyticsConsentReceiptCollection = "analyticsConsentReceipts";
export const analyticsConsentPurposeVersion = "owner-aggregate-analytics-v1";
export const analyticsConsentPrivacyVersion = "2026.10";
export const analyticsConsentDisclosureVersion = "2026-08-25.1";

export interface AnalyticsConsentMutationInput {
  enabled: boolean;
  consentID: string;
  locale: "de" | "uk";
  appVersion?: string;
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
    await persistAnalyticsConsentMutation(auth.uid, input);
    return {enabled: input.enabled, consentID: input.consentID};
  }
);

export function parseAnalyticsConsentMutation(data: unknown): AnalyticsConsentMutationInput {
  if (!isRecord(data)) {
    throw invalidConsentMutation();
  }
  const allowedFields = new Set(["enabled", "consentID", "locale", "appVersion"]);
  if (Object.keys(data).some((field) => !allowedFields.has(field))
    || typeof data.enabled !== "boolean"
    || typeof data.consentID !== "string"
    || !uuidPattern.test(data.consentID)
    || (data.locale !== "de" && data.locale !== "uk")
    || (data.appVersion !== undefined
      && (typeof data.appVersion !== "string" || !appVersionPattern.test(data.appVersion)))) {
    throw invalidConsentMutation();
  }
  return {
    enabled: data.enabled,
    consentID: data.consentID,
    locale: data.locale,
    appVersion: data.appVersion,
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
    && data.privacyVersion === analyticsConsentPrivacyVersion
    && data.disclosureVersion === analyticsConsentDisclosureVersion;
}

export async function requireCurrentAnalyticsConsent(
  uid: string,
  consentID: string
): Promise<void> {
  const snapshot = await db.collection(analyticsConsentStateCollection).doc(uid).get();
  if (!isCurrentAnalyticsConsent(snapshot.data(), consentID)) {
    throw new HttpsError(
      "failed-precondition",
      "A current server-recorded analytics consent is required."
    );
  }
}

async function persistAnalyticsConsentMutation(
  uid: string,
  input: AnalyticsConsentMutationInput
): Promise<void> {
  const stateReference = db.collection(analyticsConsentStateCollection).doc(uid);
  const receiptReference = db.collection(analyticsConsentReceiptCollection)
    .doc(analyticsConsentReceiptID(uid, input.consentID));

  await db.runTransaction(async (transaction) => {
    const [stateSnapshot, receiptSnapshot] = await transaction.getAll(
      stateReference,
      receiptReference
    );
    if (input.enabled) {
      persistGrant(transaction, uid, input, stateReference, receiptReference, receiptSnapshot.exists);
      return;
    }
    persistWithdrawal(
      transaction,
      uid,
      input,
      stateReference,
      receiptReference,
      stateSnapshot.data(),
      receiptSnapshot.exists
    );
  });
}

function persistGrant(
  transaction: Transaction,
  uid: string,
  input: AnalyticsConsentMutationInput,
  stateReference: DocumentReference,
  receiptReference: DocumentReference,
  receiptExists: boolean
): void {
  const disclosureText = disclosureByLocale[input.locale];
  const commonData = {
    userId: uid,
    consentID: input.consentID,
    purposeVersion: analyticsConsentPurposeVersion,
    privacyVersion: analyticsConsentPrivacyVersion,
    disclosureVersion: analyticsConsentDisclosureVersion,
    disclosureLocale: input.locale,
    disclosureText,
    appVersion: input.appVersion ?? null,
  };
  if (!receiptExists) {
    transaction.create(receiptReference, {
      ...commonData,
      enabled: true,
      grantedAt: FieldValue.serverTimestamp(),
      withdrawnAt: null,
    });
  }
  transaction.set(stateReference, {
    ...commonData,
    enabled: true,
    grantedAt: FieldValue.serverTimestamp(),
    withdrawnAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function persistWithdrawal(
  transaction: Transaction,
  uid: string,
  input: AnalyticsConsentMutationInput,
  stateReference: DocumentReference,
  receiptReference: DocumentReference,
  stateData: DocumentData | undefined,
  receiptExists: boolean
): void {
  if (receiptExists) {
    transaction.update(receiptReference, {
      enabled: false,
      withdrawnAt: FieldValue.serverTimestamp(),
    });
  }
  if (stateData?.consentID !== input.consentID) {
    return;
  }
  transaction.set(stateReference, {
    userId: uid,
    consentID: input.consentID,
    purposeVersion: analyticsConsentPurposeVersion,
    privacyVersion: analyticsConsentPrivacyVersion,
    disclosureVersion: analyticsConsentDisclosureVersion,
    disclosureLocale: input.locale,
    disclosureText: disclosureByLocale[input.locale],
    appVersion: input.appVersion ?? null,
    enabled: false,
    grantedAt: stateData.grantedAt ?? null,
    withdrawnAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function invalidConsentMutation(): HttpsError {
  return new HttpsError("invalid-argument", "The analytics consent mutation is invalid.");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
