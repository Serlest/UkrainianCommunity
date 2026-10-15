import {createHash} from "node:crypto";

import {FieldValue, type DocumentData} from "firebase-admin/firestore";
import {defineBoolean} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {assertActiveUser, requireVerifiedActiveUser, requireVerifiedAuth} from "../auth/context";
import {db} from "../firebase/admin";
import {userPermissionSnapshotFromData} from "../permissions/userPermissions";

export const bannerConsentStateCollection = "bannerMeasurementConsentStates";
export const bannerConsentReceiptCollection = "bannerMeasurementConsentReceipts";
export const bannerConsentPrivacyVersion = "2026.21";
export const bannerConsentDisclosureVersion = "2026-10-12.1";
export const bannerConsentPurpose = "first-party-banner-measurement-v1";
// 2026.22 only clarifies Apple login on Android; the separate banner disclosure
// and purpose are unchanged. Preserve existing explicit banner choices after
// the account acknowledges the newly active privacy notice.
const eligiblePrivacyVersions = new Set([bannerConsentPrivacyVersion, "2026.22"]);

export function hasAcknowledgedBannerPrivacy(
  acceptedVersion: unknown, activeVersion: unknown
): boolean {
  return typeof activeVersion === "string" && eligiblePrivacyVersions.has(activeVersion)
    && acceptedVersion === activeVersion;
}
export const enforceBannerMeasurementAppCheck = defineBoolean(
  "ENFORCE_BANNER_MEASUREMENT_APP_CHECK", {default: false}
);

type Locale = "de" | "uk";
interface ConsentInput {
  enabled: boolean;
  consentID: string;
  locale: Locale;
  privacyVersion: string;
  disclosureVersion: string;
}

// The separate choice is unavailable until the matching privacy revision is
// published and accepted. Existing content-analytics grants cannot enable it.
const disclosure: Record<Locale, string> = {
  de: "Optional: UAC misst sichtbare Einblendungen und Aufrufe seiner Banner je Banner und App-Bereich für zusammengefasste Berichte an den Plattforminhaber. Eine Einblendung zählt nach mindestens einer Sekunde bei mindestens 50 % Sichtbarkeit; ein Tippen zählt als Aufruf. Die Wahl gilt für dieses Konto auf allen angemeldeten Geräten. Für Berechtigung und Deduplizierung werden Konto-, Zustimmungs- und Ereigniskennungen verarbeitet. Ereignisbelege werden nach 72 Stunden zur Löschung fällig; Zustimmungsnachweise bleiben gemäß Datenschutzerklärung erhalten. Keine Werbe-ID, kein Tracking zwischen Apps und keine Teilnehmerlisten für Werbepartner. Jederzeit in den Einstellungen widerrufbar.",
  uk: "Необов’язково: UAC вимірює видимі покази та натискання своїх банерів за банером і розділом застосунку для зведених звітів власнику платформи. Показ зараховується після щонайменше однієї секунди за видимості не менш ніж 50 %; натискання зараховується окремо. Вибір діє для цього акаунта на всіх пристроях, де виконано вхід. Для перевірки прав і захисту від дублювання обробляються ID акаунта, згоди та події. Квитанції подій підлягають видаленню через 72 години; докази згоди зберігаються відповідно до політики приватності. Без рекламного ID, відстеження між застосунками й списків користувачів для рекламодавців. Згоду можна відкликати в налаштуваннях будь-коли.",
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function bannerConsentReceiptID(uid: string, consentID: string): string {
  return createHash("sha256").update(["banner-consent", uid, consentID].join("\0")).digest("hex");
}

export function isCurrentBannerConsent(data: DocumentData | undefined, consentID: string): boolean {
  return data?.enabled === true && data?.consentID === consentID
    && data?.purpose === bannerConsentPurpose
    && data?.privacyVersion === bannerConsentPrivacyVersion
    && data?.disclosureVersion === bannerConsentDisclosureVersion
    && data?.withdrawnAt == null;
}

export function parseBannerConsentInput(value: unknown): ConsentInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw invalidInput();
  const data = value as Record<string, unknown>;
  const allowed = new Set(["enabled", "consentID", "locale", "privacyVersion", "disclosureVersion"]);
  if (Object.keys(data).some(key => !allowed.has(key))
      || typeof data.enabled !== "boolean"
      || typeof data.consentID !== "string" || !uuid.test(data.consentID)
      || (data.locale !== "de" && data.locale !== "uk")
      || (data.enabled && (data.privacyVersion !== bannerConsentPrivacyVersion
        || data.disclosureVersion !== bannerConsentDisclosureVersion))
      || (!data.enabled && (typeof data.privacyVersion !== "string"
        || typeof data.disclosureVersion !== "string"))) throw invalidInput();
  return data as unknown as ConsentInput;
}

function invalidInput(): HttpsError {
  return new HttpsError("invalid-argument", "Invalid banner-measurement consent.");
}

export const updateBannerMeasurementConsent = onCall(
  {region: "europe-west3", maxInstances: 10, enforceAppCheck: enforceBannerMeasurementAppCheck},
  async (request): Promise<{enabled: boolean; consentID: string}> => {
    const input = parseBannerConsentInput(request.data);
    const auth = input.enabled ? await requireVerifiedActiveUser(request) : requireVerifiedAuth(request);
    const enabled = await persistBannerMeasurementConsent(auth.uid, input);
    if (input.enabled && !enabled) {
      throw new HttpsError("failed-precondition", "This consent has been withdrawn or superseded.");
    }
    return {enabled, consentID: input.consentID};
  }
);

export const getBannerMeasurementConsent = onCall(
  {region: "europe-west3", maxInstances: 10, enforceAppCheck: enforceBannerMeasurementAppCheck},
  async (request): Promise<{available: boolean; enabled: boolean; consentID: string | null}> => {
    const auth = await requireVerifiedActiveUser(request);
    const [state, profile, policy] = await db.getAll(
      db.collection(bannerConsentStateCollection).doc(auth.uid),
      db.doc(`users/${auth.uid}`),
      db.doc("legalDocuments/privacy")
    );
    const available = hasAcknowledgedBannerPrivacy(
      profile.get("acceptedPrivacyVersion"), policy.get("activeVersion")
    );
    const consentID = state.get("consentID");
    const receipt = available && typeof consentID === "string"
      ? await db.collection(bannerConsentReceiptCollection)
        .doc(bannerConsentReceiptID(auth.uid, consentID)).get()
      : null;
    const enabled = available && typeof consentID === "string"
      && isCurrentBannerConsent(state.data(), consentID)
      && receipt?.get("enabled") === true && receipt.get("withdrawnAt") == null;
    return {available, enabled, consentID: enabled ? consentID : null};
  }
);

export async function persistBannerMeasurementConsent(uid: string, input: ConsentInput): Promise<boolean> {
  const stateRef = db.collection(bannerConsentStateCollection).doc(uid);
  const receiptRef = db.collection(bannerConsentReceiptCollection).doc(bannerConsentReceiptID(uid, input.consentID));
  const profileRef = db.doc(`users/${uid}`);
  const policyRef = db.doc("legalDocuments/privacy");
  return db.runTransaction(async transaction => {
    const [state, receipt, profile, policy] = await transaction.getAll(stateRef, receiptRef, profileRef, policyRef);
    if (!profile.exists) {
      if (input.enabled) throw new HttpsError("permission-denied", "Account no longer exists.");
      return false;
    }
    if (!input.enabled) {
      if (!receipt.exists) {
        transaction.create(receiptRef, {
          userId: uid, consentID: input.consentID, purpose: bannerConsentPurpose,
          enabled: false, grantedAt: null, withdrawnAt: FieldValue.serverTimestamp(),
        });
      } else if (receipt.get("enabled") !== false || receipt.get("withdrawnAt") == null) {
        transaction.update(receiptRef, {enabled: false, withdrawnAt: FieldValue.serverTimestamp()});
      }
      if (state.get("consentID") === input.consentID && state.get("enabled") === true) {
        transaction.update(stateRef, {enabled: false, withdrawnAt: FieldValue.serverTimestamp()});
      }
      return false;
    }
    assertActiveUser(userPermissionSnapshotFromData(uid, profile.data()));
    if (!hasAcknowledgedBannerPrivacy(
      profile.get("acceptedPrivacyVersion"), policy.get("activeVersion")
    )) {
      throw new HttpsError("failed-precondition", "The banner-measurement privacy revision must be published and accepted.");
    }
    if (receipt.exists) {
      return receipt.get("enabled") === true && receipt.get("withdrawnAt") == null
        && isCurrentBannerConsent(state.data(), input.consentID);
    }
    if (state.get("enabled") === true && state.get("consentID") !== input.consentID) {
      throw new HttpsError("failed-precondition", "Withdraw the previous banner choice before granting a new one.");
    }
    const record = {
      userId: uid, consentID: input.consentID, purpose: bannerConsentPurpose,
      privacyVersion: bannerConsentPrivacyVersion,
      disclosureVersion: bannerConsentDisclosureVersion,
      disclosureLocale: input.locale, disclosureText: disclosure[input.locale],
      enabled: true, grantedAt: FieldValue.serverTimestamp(), withdrawnAt: null,
    };
    transaction.create(receiptRef, record);
    transaction.set(stateRef, record);
    return true;
  });
}
