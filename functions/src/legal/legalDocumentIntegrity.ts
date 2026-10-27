import {createHash} from "node:crypto";
import {type DocumentData} from "firebase-admin/firestore";

export function legalSHA256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/** Same immutable-content contract as the strict iOS reader, including historical seeded hashes. */
export function hasValidPublishedLegalContent(
  type: "terms" | "privacy", version: string, pointer: DocumentData, document: DocumentData
): boolean {
  const parts = /^([0-9]{4})\.([1-9][0-9]?)$/.exec(version);
  if (!parts || pointer.activeVersion !== version || (pointer.status !== undefined && pointer.status !== "published")
    || document.status !== "published" || document.documentType !== type || document.version !== version
    || document.versionNumber !== Number(parts[1]) * 100 + Number(parts[2])
    || (pointer.versionNumber !== undefined && pointer.versionNumber !== document.versionNumber)
    || typeof document.contentHash !== "string" || !/^[a-f0-9]{64}$/.test(document.contentHash)
    || !document.locales || typeof document.locales !== "object" || Array.isArray(document.locales)) return false;
  const locales = document.locales as Record<string, DocumentData>;
  const keys = Object.keys(locales).sort();
  if (!["de", "uk"].every(locale => keys.includes(locale))
    || typeof document.defaultLocale !== "string" || !keys.includes(document.defaultLocale.toLowerCase())
    || (document.canonicalLocale !== undefined && document.canonicalLocale !== null
      && (typeof document.canonicalLocale !== "string" || !keys.includes(document.canonicalLocale.toLowerCase())))) return false;
  const current: string[] = [], legacy: string[] = [];
  for (const key of keys) {
    const content = locales[key];
    if (!content || typeof content.title !== "string" || !content.title.trim()
      || typeof content.contentMarkdown !== "string" || !content.contentMarkdown.trim()) return false;
    const title = content.title.trim(), markdown = content.contentMarkdown.replace(/\r\n/g, "\n").trim();
    if (content.contentHash !== legalSHA256(markdown)) return false;
    current.push([key, title, markdown, content.contentHash].join("\n"));
    legacy.push([key, title, markdown, typeof content.contentText === "string" ? content.contentText : "", content.contentHash].join("\n"));
  }
  return [legalSHA256(current.join("\n---\n")), legalSHA256(legacy.join("\n---\n"))].includes(document.contentHash);
}
