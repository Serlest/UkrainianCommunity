import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Firestore emulator is required");
initializeApp({projectId: "demo-uac-legal-pages"});
const db = getFirestore();
const functionBase = process.env.UAC_LEGAL_HTTP_BASE ??
  "http://127.0.0.1:5001/demo-uac-legal-pages/europe-west3/serveLegalDocument";
const bundle = JSON.parse(readFileSync(new URL("../../UkrainianCommunity/Resources/LegalDocuments.json", import.meta.url)));
const routes = {terms: "/terms", privacy: "/privacy", organizationRules: "/organization-rules"};

for (const [type, route] of Object.entries(routes)) {
  const source = bundle[type];
  const pointer = db.doc(`legalDocuments/${type}`);
  await pointer.collection("versions").doc(source.version).set({
    ...source, documentType: type, status: "published", requiresAcceptance: true,
    publishedAt: Timestamp.fromDate(new Date("2026-10-12T12:00:00Z")),
  });
  await pointer.set({
    documentType: type, activeVersion: source.version, versionNumber: source.versionNumber,
    status: "published", requiresAcceptance: true,
  });
  const response = await fetch(`${functionBase}${route}`);
  assert.equal(response.status, 200, `${route}: ${response.status}`);
  const html = await response.text();
  assert.ok(html.includes(`Version ${source.version}`), `${route}: German version missing`);
  assert.ok(html.includes(`Версія ${source.version}`), `${route}: Ukrainian version missing`);
  assert.ok(html.includes(source.locales.de.title), `${route}: German title missing`);
  assert.ok(html.includes(source.locales.uk.title), `${route}: Ukrainian title missing`);
}

const privacy = db.doc("legalDocuments/privacy");
const next = "2026.20";
await privacy.collection("versions").doc(next).set({
  ...bundle.privacy, version: next, versionNumber: 202620,
  documentType: "privacy", status: "published", requiresAcceptance: true,
  publishedAt: Timestamp.fromDate(new Date("2026-10-12T13:00:00Z")),
});
await privacy.update({activeVersion: next, versionNumber: 202620});
const updated = await fetch(`${functionBase}/privacy`);
assert.equal(updated.status, 200);
assert.ok((await updated.text()).includes(`Version ${next}`), "Public page must follow active pointer");
console.log("Legal HTTP function reads exact active Firestore versions in both languages.");
