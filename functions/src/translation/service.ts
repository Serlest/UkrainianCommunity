import {getApp} from "firebase-admin/app";
import {type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {requireVerifiedActiveUser} from "../auth/context";
import {organizationActions} from "../organizations/organizationAccess";
import {assertOwner, isAppOwner, type UserPermissionSnapshot} from "../permissions/userPermissions";

import {legalTranslationSize, translateLegalTexts} from "./legalTranslation";

const organizationKinds = ["news", "event", "organization"];

export function translationInput(value: unknown): {kind: string; texts: string[]; source: "uk" | "de"; organizationId?: string} {
  const v = value as {kind?: unknown; texts?: unknown; source?: unknown; organizationId?: unknown} | null;
  if (!v || !["news", "event", "organization", "banner", "donation", "legal", "announcement", "directory"].includes(String(v.kind)) ||
      (v.source !== undefined && v.source !== "uk" && !(v.source === "de" && ["announcement", "directory", "legal"].includes(String(v.kind)))) ||
      !Array.isArray(v.texts) || v.texts.length < 1 || v.texts.length > 12 ||
      v.texts.some((t) => typeof t !== "string" || !t.trim() || t.length > (v.kind === "legal" ? 100000 : 20000)) ||
      v.texts.reduce((n, t) => n + t.length, 0) > (v.kind === "legal" ? 110000 : 25000) ||
      (v.organizationId !== undefined &&
        (typeof v.organizationId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(v.organizationId))) ||
      (!organizationKinds.includes(String(v.kind)) && v.organizationId !== undefined)) {
    throw new HttpsError("invalid-argument", "Invalid translation input.");
  }
  return {kind: String(v.kind), texts: v.texts as string[], source: v.source === "de" ? "de" : "uk",
    ...(v.organizationId ? {organizationId: v.organizationId as string} : {})};
}

async function assertTranslationAccess(kind: string, organizationId: string | undefined,
  actor: UserPermissionSnapshot): Promise<void> {
  if (kind === "directory") {
    if (isAppOwner(actor)) return;
    const grant = await db.doc(`directoryEditors/${actor.uid}`).get();
    if (grant.data()?.enabled === true) return;
    throw new HttpsError("permission-denied", "Directory editor access is required.");
  }
  if (!organizationKinds.includes(kind)) {
    assertOwner(actor);
    return;
  }
  if (isAppOwner(actor)) return;
  const needed = kind === "organization" ? "editInfo" : kind === "news" ? "createNews" : "createEvent";
  if (organizationId) {
    const snapshot = await db.collection("organizations").doc(organizationId).get();
    if (snapshot.exists && hasAction(snapshot.id, snapshot.data(), needed, actor)) return;
  } else {
    // Older app builds do not send organizationId. Keep team editors working,
    // while still requiring a server-verified organization role.
    const organizations = db.collection("organizations");
    const lookups = [
      organizations.where("ownerId", "==", actor.uid).limit(25).get(),
      organizations.where("adminIds", "array-contains", actor.uid).limit(25).get(),
      organizations.where("moderatorIds", "array-contains", actor.uid).limit(25).get(),
      ...(kind === "organization"
        ? [organizations.where("submittedByUserId", "==", actor.uid).limit(25).get()] : []),
    ];
    const snapshots = await Promise.all(lookups);
    if (snapshots.some((query) => query.docs.some((doc) => hasAction(doc.id, doc.data(), needed, actor)))) return;
  }
  throw new HttpsError("permission-denied", "Organization access is required.");
}

function hasAction(id: string, data: DocumentData | undefined, needed: string,
  actor: UserPermissionSnapshot): boolean {
  const actions = organizationActions(actor, {...data, id});
  return actions.includes(needed) || (needed === "editInfo" && actions.includes("resubmitRequest"));
}
export async function translateTexts(texts: string[], source = "uk", target = "de"): Promise<string[]> {
  const credential = getApp().options.credential;
  if (!credential) throw new HttpsError("unavailable", "Translation unavailable.");
  const token = await credential.getAccessToken();
  const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  const response = await fetch(`https://translation.googleapis.com/v3/projects/${project}/locations/global:translateText`, {
    method: "POST", signal: AbortSignal.timeout(20000),
    headers: {Authorization: `Bearer ${token.access_token}`, "Content-Type": "application/json"},
    body: JSON.stringify({contents: texts, mimeType: "text/plain", sourceLanguageCode: source, targetLanguageCode: target}),
  });
  if (!response.ok) throw new HttpsError("unavailable", "Translation unavailable.");
  const result = await response.json() as {translations?: {translatedText?: string}[]};
  if (result.translations?.length !== texts.length || result.translations.some((t) => typeof t.translatedText !== "string" || !t.translatedText.trim())) {
    throw new HttpsError("unavailable", "Incomplete translation.");
  }
  return result.translations.map((t) => t.translatedText!);
}
export async function translateContentHandler(request: CallableRequest, translate = translateTexts) {
  const auth = await requireVerifiedActiveUser(request);
  const input = translationInput(request.data);
  await assertTranslationAccess(input.kind, input.organizationId, auth.permissions);
  const now = Date.now(), day = Math.floor(now / 86400000), size = input.kind === "legal" ? legalTranslationSize(input.texts) : input.texts.reduce((n, t) => n + t.length, 0);
  const user = db.doc(`users/${auth.uid}/privateTranslationLimits/daily`), total = db.doc("contentTranslationLimits/_daily");
  await db.runTransaction(async (tx) => {
    const [a, b] = await Promise.all([tx.get(user), tx.get(total)]);
    const old = a.data(), global = b.data();
    const count = old?.day === day ? old.count : 0, chars = old?.day === day ? old.chars : 0;
    const globalChars = global?.day === day ? global.chars : 0;
    if (count >= 40 || chars + size > 150000 || globalChars + size > 1000000 || old?.lastAt > now - 3000) {
      throw new HttpsError("resource-exhausted", "Translation limit reached; manual editing remains available.");
    }
    tx.set(user, {day, count: count + 1, chars: chars + size, lastAt: now});
    tx.set(total, {day, chars: globalChars + size});
  });
  return {texts: input.kind === "legal"
    ? await translateLegalTexts(input.texts, input.source, input.source === "uk" ? "de" : "uk", translate)
    : await translate(input.texts, input.source, input.source === "uk" ? "de" : "uk")};
}
export const translateContent = onCall({region: "europe-west3", maxInstances: 5, timeoutSeconds: 300, enforceAppCheck: true}, (r) => translateContentHandler(r));
