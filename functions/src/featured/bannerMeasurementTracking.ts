import {createHash} from "node:crypto";

import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {assertActiveUser, requireVerifiedActiveUser} from "../auth/context";
import {analyticsRateLimitID, analyticsReceiptRetentionHours,
  expirationDate, nextAnalyticsRateLimitState} from "../analytics/analyticsEventGuard";
import {db} from "../firebase/admin";
import {userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {bannerConsentReceiptCollection, bannerConsentReceiptID,
  bannerConsentStateCollection, enforceBannerMeasurementAppCheck,
  hasAcknowledgedBannerPrivacy,
  isCurrentBannerConsent} from "./bannerMeasurementConsent";

export const bannerMeasurementReceiptCollection = "bannerMeasurementEventReceipts";
export const bannerMeasurementRateLimitCollection = "bannerMeasurementRateLimits";
export const bannerMeasurementShardCollection = "bannerMeasurementDailyShards";

type Section = "home" | "events" | "organizations" | "directory";
type Kind = "impression" | "click";
interface MeasurementInput {
  id: string;
  bannerID: string;
  section: Section;
  kind: Kind;
  occurredAtMilliseconds: number;
  consentID: string;
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const bannerIDPattern = /^[A-Za-z0-9_-]{1,128}$/;
const sections = new Set<Section>(["home", "events", "organizations", "directory"]);
const kinds = new Set<Kind>(["impression", "click"]);
const maximumEventAgeMilliseconds = 48 * 60 * 60 * 1_000;
const maximumFutureSkewMilliseconds = 60 * 1_000;

function digest(parts: string[]): string {
  return createHash("sha256").update(parts.join("\0")).digest("hex");
}

export function bannerMeasurementEventReceiptID(uid: string, eventID: string): string {
  return digest(["banner-event", uid, eventID]);
}

export function parseBannerMeasurement(value: unknown, now: Date): MeasurementInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw invalidInput();
  const data = value as Record<string, unknown>;
  const allowed = new Set(["id", "bannerID", "section", "kind", "occurredAtMilliseconds", "consentID"]);
  if (Object.keys(data).some(key => !allowed.has(key))
      || typeof data.id !== "string" || !uuid.test(data.id)
      || typeof data.consentID !== "string" || !uuid.test(data.consentID)
      || typeof data.bannerID !== "string" || !bannerIDPattern.test(data.bannerID)
      || !sections.has(data.section as Section) || !kinds.has(data.kind as Kind)
      || typeof data.occurredAtMilliseconds !== "number"
      || !Number.isSafeInteger(data.occurredAtMilliseconds)
      || now.getTime() - data.occurredAtMilliseconds > maximumEventAgeMilliseconds
      || data.occurredAtMilliseconds - now.getTime() > maximumFutureSkewMilliseconds) throw invalidInput();
  return data as unknown as MeasurementInput;
}

function invalidInput(): HttpsError {
  return new HttpsError("invalid-argument", "Invalid banner measurement.");
}

function validBannerForMeasurement(
  banner: DocumentData | undefined,
  input: MeasurementInput
): boolean {
  if (!banner || banner.isActive !== true
      || !Array.isArray(banner.visibleSections)
      || !banner.visibleSections.includes(input.section)
      || (input.kind === "click" && !["news", "event", "organization", "externalURL", "partner"]
        .includes(banner.actionType))) return false;
  const start = banner.startsAt instanceof Timestamp ? banner.startsAt.toMillis() : null;
  const end = banner.endsAt instanceof Timestamp ? banner.endsAt.toMillis() : null;
  return (start == null || input.occurredAtMilliseconds >= start)
    && (end == null || input.occurredAtMilliseconds < end);
}

export const recordBannerMeasurement = onCall(
  {region: "europe-west3", maxInstances: 20, enforceAppCheck: enforceBannerMeasurementAppCheck},
  async (request): Promise<{counted: boolean; duplicate: boolean}> => {
    const auth = await requireVerifiedActiveUser(request);
    return persistBannerMeasurement(auth.uid, parseBannerMeasurement(request.data, new Date()));
  }
);

export async function persistBannerMeasurement(
  uid: string, input: MeasurementInput, now: Date = new Date()
): Promise<{counted: boolean; duplicate: boolean}> {
    const receiptRef = db.collection(bannerMeasurementReceiptCollection)
      .doc(bannerMeasurementEventReceiptID(uid, input.id));
    const consentRef = db.collection(bannerConsentStateCollection).doc(uid);
    const consentReceiptRef = db.collection(bannerConsentReceiptCollection)
      .doc(bannerConsentReceiptID(uid, input.consentID));
    const profileRef = db.doc(`users/${uid}`);
    const policyRef = db.doc("legalDocuments/privacy");
    const bannerRef = db.collection("featuredBanners").doc(input.bannerID);
    const rateRef = db.collection(bannerMeasurementRateLimitCollection).doc(analyticsRateLimitID(uid, now));
    const day = new Date(input.occurredAtMilliseconds).toISOString().slice(0, 10);
    const aggregateExpiresAt = Timestamp.fromDate(
      new Date(Date.parse(`${day}T00:00:00.000Z`) + 395 * 24 * 60 * 60 * 1_000)
    );
    const shard = parseInt(digest([input.id]).slice(0, 2), 16) % 16;
    const shardRef = db.collection(bannerMeasurementShardCollection)
      .doc(`${day}_${digest([input.bannerID])}_${input.section}_${shard}`);
    const payloadHash = digest([input.consentID, input.bannerID, input.section,
      input.kind, String(input.occurredAtMilliseconds)]);

    return db.runTransaction(async transaction => {
      const [receipt, consent, consentReceipt, profile, policy, banner, rate] = await transaction.getAll(
        receiptRef, consentRef, consentReceiptRef, profileRef, policyRef, bannerRef, rateRef
      );
      if (!profile.exists) throw new HttpsError("permission-denied", "Account no longer exists.");
      assertActiveUser(userPermissionSnapshotFromData(uid, profile.data()));
      if (!hasAcknowledgedBannerPrivacy(
        profile.get("acceptedPrivacyVersion"), policy.get("activeVersion")
      )
          || !isCurrentBannerConsent(consent.data(), input.consentID)
          || consentReceipt.get("enabled") !== true || consentReceipt.get("withdrawnAt") != null) {
        throw new HttpsError("failed-precondition", "Current banner-measurement consent is required.");
      }
      if (receipt.exists) {
        if (receipt.get("payloadHash") !== payloadHash) throw invalidInput();
        return {counted: true, duplicate: true};
      }
      if (!validBannerForMeasurement(banner.data(), input)) {
        throw new HttpsError("not-found", "Banner is not eligible for this measurement.");
      }
      const rateState = nextAnalyticsRateLimitState(rate.get("count"), now);
      transaction.set(rateRef, rateState, {merge: true});
      transaction.create(receiptRef, {
        payloadHash, expiresAt: Timestamp.fromDate(expirationDate(now, analyticsReceiptRetentionHours)),
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.set(shardRef, {
        day, bannerID: input.bannerID, section: input.section, shard,
        impressions: FieldValue.increment(input.kind === "impression" ? 1 : 0),
        clicks: FieldValue.increment(input.kind === "click" ? 1 : 0),
        expiresAt: aggregateExpiresAt,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {counted: true, duplicate: false};
    });
}
