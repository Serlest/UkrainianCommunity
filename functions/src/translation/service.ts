import {getApp} from "firebase-admin/app";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {requireVerifiedActiveUser} from "../auth/context";
import {assertOwner} from "../permissions/userPermissions";

export function translationInput(value: unknown): {kind: string; texts: string[]; source: "uk" | "de"} {
  const v = value as {kind?: unknown; texts?: unknown; source?: unknown} | null;
  if (!v || !["news", "event", "organization", "banner", "donation", "legal", "announcement"].includes(String(v.kind)) ||
      (v.source !== undefined && v.source !== "uk" && !(v.source === "de" && v.kind === "announcement")) ||
      !Array.isArray(v.texts) || v.texts.length < 1 || v.texts.length > 12 ||
      v.texts.some((t) => typeof t !== "string" || !t.trim() || t.length > 20000) ||
      v.texts.reduce((n, t) => n + t.length, 0) > 25000) {
    throw new HttpsError("invalid-argument", "Invalid translation input.");
  }
  return {kind: String(v.kind), texts: v.texts as string[], source: v.source === "de" ? "de" : "uk"};
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
  if (["banner", "donation", "legal", "announcement"].includes(input.kind)) assertOwner(auth.permissions);
  const now = Date.now(), day = Math.floor(now / 86400000), size = input.texts.reduce((n, t) => n + t.length, 0);
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
  return {texts: await translate(input.texts, input.source, input.source === "uk" ? "de" : "uk")};
}
export const translateContent = onCall({region: "europe-west3", maxInstances: 5, enforceAppCheck: true}, (r) => translateContentHandler(r));
