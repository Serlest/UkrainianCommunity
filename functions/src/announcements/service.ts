import {createHash, randomBytes} from "node:crypto";
import {FieldPath, type DocumentData} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {requireAuth, requireVerifiedActiveUser} from "../auth/context";
import {assertOwner, isActiveUser} from "../permissions/userPermissions";
import {sendPushToRegistrationDocuments, isStrictFirebaseInstallationID} from "../notifications/pushRegistrations";
import {getApp} from "firebase-admin/app";
import {Announcement, AudienceUser, parseDraft, identifier, record, text, fail, matchesAudience, supports, isActive, publicAnnouncement, assertPublishable} from "./contract";

const options = {region: "europe-west3", maxInstances: 10, enforceAppCheck: true};
const campaigns = db.collection("announcements");
const devices = db.collection("announcementDevices");
async function rolloutEnabled(push = false): Promise<boolean> {
  const config = (await db.doc("appConfig/announcements").get()).data();
  return config?.enabled === true && config.iosEnabled === true && (!push || config.pushEnabled === true);
}

const digest = (s: string) => createHash("sha256").update(s).digest("hex");
const denied = (): never => {throw new HttpsError("permission-denied", "Announcement access denied.");};

export async function audienceUser(uid: string): Promise<AudienceUser | undefined> {
  const profile = (await db.collection("users").doc(uid).get()).data();
  if (!profile || !isActiveUser({uid, ...profile})) return undefined;
  const [owned, administered, moderated] = await Promise.all([
    db.collection("organizations").where("ownerId", "==", uid).limit(1).get(),
    db.collection("organizations").where("adminIds", "array-contains", uid).limit(1).get(),
    db.collection("organizations").where("moderatorIds", "array-contains", uid).limit(1).get(),
  ]);
  return {uid, region: profile.selectedFederalState, globalRole: profile.globalRole,
    organizationRoles: [...(!owned.empty ? ["communityOwner"] : []), ...(!administered.empty ? ["communityAdmin"] : []), ...(!moderated.empty ? ["communityModerator"] : [])]};
}
async function readCampaign(id: string): Promise<Announcement> {
  const doc = await campaigns.doc(id).get();
  if (!doc.exists) throw new HttpsError("not-found", "Announcement unavailable.");
  return doc.data() as Announcement;
}
function client(data: Record<string, unknown>): void {
  if (data.platform !== "ios" || data.capability !== 1) throw new HttpsError("failed-precondition", "Client does not support announcements.");
}
function receiptRef(uid: string, id: string) { return db.collection("users").doc(uid).collection("announcementReceipts").doc(id); }

export async function manage(request: CallableRequest) {
  const auth = await requireVerifiedActiveUser(request); assertOwner(auth.permissions);
  const data = record(request.data); const now = Date.now();
  switch (data.operation) {
    case "list": {
      let query = campaigns.orderBy("updatedAt", "desc").orderBy(FieldPath.documentId(), "desc").limit(30);
      if (data.cursor) {const cursor = await campaigns.doc(identifier(data.cursor)).get(); if (cursor.exists) query = query.startAfter(cursor);}
      const page = await query.get();
      return {items: page.docs.map((d) => d.data()), cursor: page.size === 30 ? page.docs.at(-1)!.id : null};
    }
    case "save": {
      const draft = parseDraft(data.draft, auth.uid, now), ref = campaigns.doc(draft.id);
      await db.runTransaction(async (tx) => {
        const previous = (await tx.get(ref)).data();
        if (previous && previous.status !== "draft") throw new HttpsError("failed-precondition", "Published announcements are immutable.");
        if (previous && data.revision !== previous.revision) throw new HttpsError("aborted", "Draft changed. Reload before saving.");
        draft.createdAt = previous?.createdAt ?? now; draft.revision = (previous?.revision ?? 0) + 1;
        tx.set(ref, draft);
      });
      return {item: draft};
    }
    case "publish": {
      if (!await rolloutEnabled()) throw new HttpsError("failed-precondition", "Announcements are not enabled.");
      const ref = campaigns.doc(identifier(data.id));
      await db.runTransaction(async (tx) => {
        const a = (await tx.get(ref)).data() as Announcement | undefined;
        if (!a) throw new HttpsError("not-found", "Draft unavailable.");
        if (a.status === "published") return;
        if (a.status !== "draft" || a.revision !== data.revision) throw new HttpsError("failed-precondition", "Reload the draft.");
        assertPublishable(a, now);
        // Bound the active feed rather than silently dropping excess messages.
        const active = await tx.get(campaigns.where("status", "==", "published"));
        if (active.docs.filter((d) => d.data().expiresAt > now).length >= 100) throw new HttpsError("resource-exhausted", "There are already 100 active or scheduled announcements.");
        tx.update(ref, {status: "published", updatedAt: now, pushState: a.push ? "pending" : "disabled", publishedAt: now});
      });
      return {ok: true};
    }
    case "cancel": {
      await campaigns.doc(identifier(data.id)).update({status: "cancelled", updatedAt: now}); return {ok: true};
    }
    case "preview": {
      const a = parseDraft(data.draft, auth.uid, now);
      let query = db.collection("users").orderBy(FieldPath.documentId()).limit(100);
      if (data.cursor) query = query.startAfter(identifier(data.cursor));
      const page = await query.get(); let accounts = 0;
      for (const doc of page.docs) {const u = await audienceUser(doc.id); if (u && matchesAudience(a, u)) accounts++;}
      return {accounts, guests: a.groups.includes("guests"), cursor: page.size === 100 ? page.docs.at(-1)!.id : null};
    }
    case "users": {
      let query = db.collection("users").orderBy(FieldPath.documentId()).limit(50);
      if (data.cursor) query = query.startAfter(identifier(data.cursor));
      const page = await query.get();
      return {items: page.docs.map((d) => ({id: d.id, name: d.data().displayName || d.data().fullName || d.id, region: d.data().selectedFederalState ?? null})), cursor: page.size === 50 ? page.docs.at(-1)!.id : null};
    }
    case "stats": {
      const ref = campaigns.doc(identifier(data.id));
      const [p, a, f, delivery, guestP, guestA, pushOK, pushFailed] = await Promise.all([
        ref.collection("metrics").where("presented", "==", true).count().get(),
        ref.collection("metrics").where("acknowledged", "==", true).count().get(),
        ref.collection("metrics").where("action", "==", true).count().get(),
        ref.get(),
        ref.collection("guestMetrics").where("presented", "==", true).count().get(),
        ref.collection("guestMetrics").where("acknowledged", "==", true).count().get(),
        ref.collection("deliveries").where("success", "==", true).count().get(),
        ref.collection("deliveries").where("success", "==", false).count().get(),
      ]);
      return {presented: p.data().count, acknowledged: a.data().count, action: f.data().count, pushState: delivery.data()?.pushState ?? "disabled", pushSuccess: pushOK.data().count, pushFailure: pushFailed.data().count, guestPresented: guestP.data().count, guestAcknowledged: guestA.data().count};
    }
    case "test": {
      if (!await rolloutEnabled()) throw new HttpsError("failed-precondition", "Announcements are not enabled.");
      const draft = parseDraft(data.draft, auth.uid, now); assertPublishable(draft, now);
      const id = `test_${randomBytes(12).toString("hex")}`;
      await campaigns.doc(id).set({...draft, id, groups: [], userIds: [auth.uid], regions: [], status: "published", startsAt: now, expiresAt: now + 3600000, pushState: draft.push ? "pending" : "disabled", test: true});
      return {id};
    }
    case "translate": return translate(data, auth.uid);
    default: return fail("Unknown announcement operation.");
  }
}
export const manageAnnouncements = onCall(options, manage);

export async function feed(request: CallableRequest) {
  const data = record(request.data); client(data);
  if (!await rolloutEnabled()) return {items: [], serverNow: Date.now(), cursor: null};
  const uid = request.auth?.uid;
  const user = uid ? await audienceUser(uid) : undefined;
  if (uid && !user) return denied();
  const now = Date.now();
  // Cursor supports retained history; expiration is evaluated independently of publication status.
  let query = campaigns.where("status", "in", ["published", "cancelled"]).orderBy(FieldPath.documentId()).limit(100);
  if (data.cursor) query = query.startAfter(identifier(data.cursor));
  const page = await query.get(); const items = [];
  for (const doc of page.docs) {
    const a = doc.data() as Announcement;
    if (a.startsAt > now || !supports(a, data.platform, data.capability) || !matchesAudience(a, user)) continue;
    const receipt = uid ? (await receiptRef(uid, a.id).get()).data() ?? {} : {};
    if (a.status === "cancelled" && uid && !receipt.presentedAt) continue;
    // Expired history is retained, but never a popup candidate.
    items.push({...publicAnnouncement(a), presentedAt: receipt.presentedAt ?? null, acknowledgedAt: receipt.acknowledgedAt ?? null});
  }
  return {items, serverNow: now, cursor: page.size === 100 ? page.docs.at(-1)!.id : null};
}
export const getAnnouncements = onCall(options, feed);

export async function acknowledge(request: CallableRequest) {
  const data = record(request.data); client(data);
  const auth = request.auth ? requireAuth(request) : undefined, id = identifier(data.id);
  if (!["presented", "acknowledged", "action"].includes(String(data.event))) return fail("Invalid event.");
  const a = await readCampaign(id), user = auth ? await audienceUser(auth.uid) : undefined;
  if ((auth && !user) || !matchesAudience(a, user) || !supports(a, data.platform, data.capability) || a.status !== "published") return denied();
  const event = String(data.event);
  if (event === "acknowledged" && a.mode !== "acknowledge") return fail("Confirmation is not required.");
  const field = event === "action" ? "actionOpenedAt" : `${event}At`;
  const guestSecret = auth ? undefined : text(data.secret, 128);
  if (guestSecret !== undefined && guestSecret.length < 64) return fail("Invalid guest credential.");
  const metric = campaigns.doc(id).collection(auth ? "metrics" : "guestMetrics").doc(digest(auth?.uid ?? guestSecret!));
  const ref = auth ? receiptRef(auth.uid, id) : metric;
  await db.runTransaction(async (tx) => {
    const [receipt, current] = await Promise.all([tx.get(ref), tx.get(campaigns.doc(id))]);
    const old = receipt.data();
    if (current.data()?.status !== "published") return denied();
    if (old?.[field]) return;
    tx.set(ref, {[field]: Date.now(), revision: a.revision, retentionExpiresAt: a.expiresAt + 180 * 86400000}, {merge: true});
    tx.set(metric, {[event]: true}, {merge: true});
  }); return {ok: true};
}
export const acknowledgeAnnouncement = onCall(options, acknowledge);

// The secret identifies a local installation. A push challenge proves control of its FID
// before it may receive announcements. Merely knowing another installation's FID is insufficient.
export async function register(request: CallableRequest, send: typeof sendPushToRegistrationDocuments = sendPushToRegistrationDocuments) {
  const data = record(request.data); client(data);
  const secret = text(data.secret, 128); if (secret.length < 32) return fail("Invalid installation credential.");
  const ref = devices.doc(digest(secret));
  if (data.operation === "disable") {await ref.delete(); return {ok: true};}
  if (data.operation === "confirm") {
    const challenge = text(data.challenge, 128);
    await db.runTransaction(async (tx) => {
      const device = (await tx.get(ref)).data();
      if (!device || device.challengeHash !== digest(challenge) || device.challengeExpiresAt < Date.now() || device.uid !== (request.auth?.uid ?? null)) return denied();
      tx.update(ref, {verified: true, challengeHash: null, updatedAt: Date.now()});
    }); return {ok: true};
  }
  const fid = text(data.fid, 22); if (!isStrictFirebaseInstallationID(fid)) return fail("Invalid installation ID.");
  const uid = request.auth?.uid ?? null, language = data.language === "uk" ? "uk" : "de";
  const previous = (await ref.get()).data();
  if (previous?.token === fid && previous.uid === uid && previous.verified === true) {
    await ref.update({language, updatedAt: Date.now()}); return {ok: true};
  }
  if (previous && previous.updatedAt > Date.now() - 30000 && previous.uid === uid && previous.token === fid) throw new HttpsError("resource-exhausted", "Please retry registration later.");
  const challenge = randomBytes(32).toString("hex");
  await ref.set({token: fid, registrationType: "fid", platform: "ios", capability: 1, uid, language,
    verified: false, challengeHash: digest(challenge), challengeExpiresAt: Date.now() + 300000, updatedAt: Date.now()});
  const doc = await ref.get();
  await send([doc as typeof doc & {data(): DocumentData}], {
    data: {announcementChallenge: challenge}, apns: {headers: {"apns-push-type": "background", "apns-priority": "5"}, payload: {aps: {contentAvailable: true}}},
  });
  return {ok: true};
}
export const registerAnnouncementDevice = onCall(options, (request) => register(request));

async function translate(data: Record<string, unknown>, uid: string) {
  const source = data.source === "uk" ? "uk" : data.source === "de" ? "de" : fail("Invalid language.");
  const title = text(data.title, 160), body = text(data.body, 6000);
  const ref = db.collection("announcementTranslationLimits").doc(uid);
  await db.runTransaction(async (tx) => {
    const old = (await tx.get(ref)).data(), day = Math.floor(Date.now() / 86400000);
    const count = old?.day === day ? old.count : 0;
    if (count >= 20 || old?.lastAt > Date.now() - 3000) throw new HttpsError("resource-exhausted", "Translation limit reached. You can enter both languages manually.");
    tx.set(ref, {day, count: count + 1, lastAt: Date.now()});
  });
  const credential = getApp().options.credential;
  if (!credential) throw new HttpsError("unavailable", "Translation is unavailable.");
  const token = await credential.getAccessToken();
  const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  const response = await fetch(`https://translation.googleapis.com/v3/projects/${project}/locations/global:translateText`, {
    method: "POST", signal: AbortSignal.timeout(20000),
    headers: {Authorization: `Bearer ${token.access_token}`, "Content-Type": "application/json"},
    body: JSON.stringify({contents: [title, body], mimeType: "text/plain", sourceLanguageCode: source, targetLanguageCode: source === "uk" ? "de" : "uk"}),
  });
  if (!response.ok) throw new HttpsError("unavailable", "Translation is unavailable. Please enter the translation manually or retry later.");
  const result = await response.json() as {translations?: {translatedText?: string}[]};
  if (result.translations?.length !== 2) throw new HttpsError("unavailable", "Incomplete translation.");
  return {title: text(result.translations[0].translatedText, 160), body: text(result.translations[1].translatedText, 6000)};
}

export async function dispatchAnnouncements(send: typeof sendPushToRegistrationDocuments = sendPushToRegistrationDocuments) {
  if (!await rolloutEnabled(true)) return;
  const page = await campaigns.where("status", "==", "published").get();
  for (const doc of page.docs) {
    const a = doc.data() as Announcement;
    if (!a.push || !isActive(a, Date.now())) continue;
    const lease = randomBytes(12).toString("hex");
    const claimed = await db.runTransaction(async (tx) => {
      const state = (await tx.get(doc.ref)).data()!;
      if (["completed", "disabled"].includes(state.pushState) || state.leaseUntil > Date.now()) return false;
      tx.update(doc.ref, {pushState: "running", lease, leaseUntil: Date.now() + 540000}); return true;
    });
    if (!claimed) continue;
    try {
      let cursor = (await doc.ref.get()).data()?.pushCursor as string | undefined;
      let done = false;
      // A bounded number of pages per invocation; next minute resumes the cursor.
      for (let batch = 0; batch < 4 && !done; batch++) {
        const latest = await doc.ref.get();
        if (!await rolloutEnabled(true) || !isActive(latest.data() as Announcement, Date.now())) break;
        let query = devices.orderBy(FieldPath.documentId()).limit(100);
        if (cursor) query = query.startAfter(cursor);
        const registrations = await query.get();
        let successes = 0, failures = 0;
        for (const registration of registrations.docs) {
          const d = registration.data();
          if (!d.verified || !supports(a, d.platform, d.capability) || d.updatedAt < Date.now() - 90 * 86400000) continue;
          const user = d.uid ? await audienceUser(d.uid) : undefined;
          if ((d.uid && !user) || !matchesAudience(a, user)) continue;
          if (d.uid) {
            const preferences = (await db.collection("users").doc(d.uid).collection("notificationPreferences").doc("settings").get()).data();
            if (preferences?.notificationsEnabled !== true) continue;
          }
          const delivery = doc.ref.collection("deliveries").doc(registration.id);
          const prior = (await delivery.get()).data();
          if (prior?.success || prior?.attempts >= 3) continue;
          if (!isActive((await doc.ref.get()).data() as Announcement, Date.now())) break;
          // Never include personal content on the lock screen or in data payloads.
          const result = await send([registration], {
            notification: {title: "UAC", body: d.language === "uk" ? "Нове повідомлення в застосунку" : "Neue Mitteilung in der App"},
            data: {announcementId: a.id, announcementVersion: "1"},
            apns: {headers: {"apns-collapse-id": a.id, "apns-expiration": String(Math.floor(a.expiresAt / 1000))}, payload: {aps: {sound: "default"}}},
          });
          await delivery.set({success: result.successCount > 0, attempts: (prior?.attempts ?? 0) + 1, at: Date.now()});
          if (result.failureCount && (prior?.attempts ?? 0) < 2) throw new Error("Announcement delivery will retry.");
          successes += result.successCount; failures += result.failureCount;
        }
        cursor = registrations.docs.at(-1)?.id ?? cursor;
        done = registrations.size < 100;
        await db.runTransaction(async (tx) => {
          const state = (await tx.get(doc.ref)).data()!;
          if (state.lease !== lease) return;
          tx.update(doc.ref, {pushCursor: cursor ?? null, pushSuccess: (state.pushSuccess ?? 0) + successes,
            pushFailure: (state.pushFailure ?? 0) + failures});
        });
      }
      await doc.ref.update({pushState: done ? "completed" : "pending", leaseUntil: 0});
    } catch (error) {
      await doc.ref.update({pushState: "failed", leaseUntil: 0}); throw error;
    }
  }
}
export const deliverAnnouncements = onSchedule({region: "europe-west3", schedule: "every 1 minutes", timeoutSeconds: 540, maxInstances: 1}, () => dispatchAnnouncements());

export async function cleanupAnnouncementData(now = Date.now()) {
  const cutoff = now - 180 * 86400000;
  const oldCampaigns = await campaigns.where("expiresAt", "<=", cutoff).limit(25).get();
  for (const doc of oldCampaigns.docs) await db.recursiveDelete(doc.ref);
  const [oldDevices, oldReceipts] = await Promise.all([
    devices.where("updatedAt", "<=", now - 90 * 86400000).limit(250).get(),
    db.collectionGroup("announcementReceipts").where("retentionExpiresAt", "<=", now).limit(250).get(),
  ]);
  const batch = db.batch();
  for (const doc of [...oldDevices.docs, ...oldReceipts.docs]) batch.delete(doc.ref);
  if (oldDevices.size + oldReceipts.size) await batch.commit();
  return {campaigns: oldCampaigns.size, devices: oldDevices.size, receipts: oldReceipts.size};
}
export const cleanupAnnouncements = onSchedule({region: "europe-west3", schedule: "every day 04:20", timeZone: "Europe/Vienna", timeoutSeconds: 540}, () => cleanupAnnouncementData().then(() => undefined));
