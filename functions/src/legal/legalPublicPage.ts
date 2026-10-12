import {createHash} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";

import {db} from "../firebase/admin";
import {PublicLegalContent, PublicLegalPage, PublicLegalType, renderPublicLegalPage} from "./legalPageHtml";

const paths: Record<string, PublicLegalType> = {
  "/terms": "terms",
  "/privacy": "privacy",
  "/organization-rules": "organizationRules",
};

function pageType(path: string): PublicLegalType | undefined {
  const normalized = path.replace(/\/(index\.html)?\/?$/, "");
  return paths[normalized];
}

function localeContent(value: unknown): PublicLegalContent | undefined {
  if (!value || typeof value !== "object") return undefined;
  const data = value as Record<string, unknown>;
  const title = data.title;
  const markdown = data.contentMarkdown;
  const hash = data.contentHash;
  if (typeof title !== "string" || !title.trim() ||
      typeof markdown !== "string" || !markdown.trim() ||
      typeof hash !== "string") return undefined;
  const actualHash = createHash("sha256").update(markdown).digest("hex");
  if (actualHash !== hash) return undefined;
  return {title, contentMarkdown: markdown};
}

async function activePage(type: PublicLegalType): Promise<PublicLegalPage> {
  const pointer = db.doc(`legalDocuments/${type}`);
  return db.runTransaction(async transaction => {
    const active = await transaction.get(pointer);
    const activeVersion = active.get("activeVersion");
    if (!active.exists || active.get("status") !== "published" ||
        active.get("requiresAcceptance") !== true ||
        typeof activeVersion !== "string" || !/^[0-9]{4}\.[1-9][0-9]?$/.test(activeVersion)) {
      throw new Error("Active legal pointer unavailable");
    }
    const version = await transaction.get(pointer.collection("versions").doc(activeVersion));
    const data = version.data();
    const publishedAt = data?.publishedAt;
    const locales = data?.locales;
    const de = localeContent(locales?.de);
    const uk = localeContent(locales?.uk);
    if (data?.documentType !== type || data.version !== activeVersion ||
        data.status !== "published" || data.requiresAcceptance !== true ||
        data.versionNumber !== active.get("versionNumber") ||
        !(publishedAt instanceof Timestamp) || !de || !uk) {
      throw new Error("Published legal text unavailable");
    }
    return {
      type, version: activeVersion, publishedAt: publishedAt.toDate(),
      supersedesVersion: typeof data.supersedesVersion === "string" ? data.supersedesVersion : undefined,
      locales: {de, uk},
    };
  }, {readOnly: true});
}

export const serveLegalDocument = onRequest(
  {region: "europe-west3", maxInstances: 10, invoker: "public"},
  async (request, response) => {
    response.set("Cache-Control", "no-store");
    response.set("X-Content-Type-Options", "nosniff");
    response.set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'");
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.status(405).send("Method not allowed");
      return;
    }
    const type = pageType(request.path);
    if (!type) {
      response.status(404).send("Not found");
      return;
    }
    try {
      const page = await activePage(type);
      response.type("html").status(200).send(renderPublicLegalPage(page));
    } catch (error) {
      console.error("Public legal page unavailable", {type, error});
      response.type("html").status(503).send(
        "<!doctype html><html lang=\"de\"><meta charset=\"utf-8\"><title>Dokument vorübergehend nicht verfügbar</title>" +
        "<main><h1>Dokument vorübergehend nicht verfügbar / Документ тимчасово недоступний</h1>" +
        "<p>Bitte versuchen Sie es erneut. / Спробуйте ще раз пізніше.</p></main></html>"
      );
    }
  }
);
