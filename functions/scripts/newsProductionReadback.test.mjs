import assert from "node:assert/strict";
import test from "node:test";

import {verifyNewsProductionDocument} from "./newsProductionReadback.mjs";

test("production receipt requires both exact language bodies and a served JPEG", () => {
  const item = {
    regionScope: "federalState", federalState: "wien", canonicalURL: "https://wien.gv.at/news",
    publishedAt: new Date("2026-10-12T09:00:00Z"), title: "Українська", subtitle: "Опис",
    body: "Повний текст", deTitle: "Deutsch", deSubtitle: "Beschreibung", deBody: "Voller Text",
    imageCredit: "KI", imageAlternativeText: "Gebäude",
  };
  const document = {
    id: "id-1", organizationId: "uac-wien-info", moderationStatus: "approved",
    regionScope: "federalState", federalState: "wien", sourceURL: item.canonicalURL,
    publishedAt: "2026-10-12T09:00:00Z", mediaMetadata: {credit: "KI", alternativeText: "Gebäude"},
    localizations: {
      uk: {title: item.title, subtitle: item.subtitle, body: item.body},
      de: {title: item.deTitle, subtitle: item.deSubtitle, body: item.deBody},
    },
  };
  const cover = {contentType: "image/jpeg", bytes: 20_000, sha256: "a".repeat(64)};
  assert.equal(verifyNewsProductionDocument(document, item, document.organizationId, document.id, cover).allVerified, true);
  document.localizations.de.body = "Wrong";
  const failed = verifyNewsProductionDocument(document, item, document.organizationId, document.id, cover);
  assert.equal(failed.allVerified, false);
  assert.equal(failed.checks.deBody, false);
});
