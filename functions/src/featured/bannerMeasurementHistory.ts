import {Timestamp, type DocumentData, type DocumentSnapshot, type Transaction} from "firebase-admin/firestore";
import {db} from "../firebase/admin";

const maximumAge = 48 * 60 * 60 * 1_000;
export const bannerMeasurementHistoryCollection = "bannerMeasurementHistory";

// Only non-personal delivery configuration, never artwork or owner data.
export async function archiveBannerMeasurementConfiguration(
  transaction: Transaction, snapshot: DocumentSnapshot, until: Timestamp
): Promise<void> {
  if (!snapshot.exists) return;
  const ref = db.collection(bannerMeasurementHistoryCollection).doc(snapshot.id);
  const previous = await transaction.get(ref);
  const data = snapshot.data() ?? {};
  const versions: DocumentData[] = Array.isArray(previous.get("versions")) ? previous.get("versions") : [];
  const validFrom = data.updatedAt instanceof Timestamp ? data.updatedAt
    : data.createdAt instanceof Timestamp ? data.createdAt : Timestamp.fromMillis(0);
  versions.push({
    isActive: data.isActive === true, visibleSections: data.visibleSections ?? [],
    actionType: data.actionType ?? "none", startsAt: data.startsAt ?? null, endsAt: data.endsAt ?? null,
    validFrom, validUntil: until,
  });
  transaction.set(ref, {
    versions: versions.filter(v => v.validUntil instanceof Timestamp
      && v.validUntil.toMillis() >= until.toMillis() - maximumAge).slice(-64),
    expiresAt: Timestamp.fromMillis(until.toMillis() + maximumAge),
  });
}

export function bannerConfigurationAt(
  current: DocumentData | undefined, history: DocumentData | undefined, occurredAt: number
): DocumentData | undefined {
  const from = current?.updatedAt instanceof Timestamp ? current.updatedAt.toMillis() : -Infinity;
  if (current && occurredAt >= from) return current;
  const versions: DocumentData[] = Array.isArray(history?.versions) ? history.versions : [];
  return versions.find(v => v.validFrom instanceof Timestamp && v.validUntil instanceof Timestamp
    && occurredAt >= v.validFrom.toMillis() && occurredAt < v.validUntil.toMillis());
}
