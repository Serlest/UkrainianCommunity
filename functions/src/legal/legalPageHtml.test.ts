import * as assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import * as path from "node:path";
import {test} from "node:test";

import {PublicLegalPage, PublicLegalType, renderPublicLegalPage} from "./legalPageHtml";

const bundled = JSON.parse(readFileSync(path.resolve(__dirname,
  "../../../UkrainianCommunity/Resources/LegalDocuments.json"), "utf8"));

for (const type of ["terms", "privacy", "organizationRules"] as PublicLegalType[]) {
  test(`public ${type} page presents both complete current texts`, () => {
    const document = bundled[type];
    const page: PublicLegalPage = {
      type, version: document.version, publishedAt: new Date("2026-10-12T12:00:00Z"),
      locales: {
        de: document.locales.de,
        uk: document.locales.uk,
      },
    };
    const html = renderPublicLegalPage(page);
    assert.match(html, /<html lang="de">/);
    assert.match(html, new RegExp(`Version ${document.version.replace(".", "\\.")}`));
    assert.match(html, new RegExp(`Версія ${document.version.replace(".", "\\.")}`));
    for (const language of ["de", "uk"]) {
      const source = document.locales[language].contentMarkdown as string;
      const sections = [...source.matchAll(/^## (.+)$/gm)];
      for (const section of sections) {
        assert.ok(html.includes(section[1].replaceAll("&", "&amp;")), `${type}/${language}: ${section[1]}`);
      }
    }
    if (type === "privacy") assert.match(html, /<div class="table-scroll"><table>/);
  });
}

test("published Markdown cannot inject HTML or unsafe links", () => {
  const html = renderPublicLegalPage({
    type: "terms", version: "2026.99", publishedAt: new Date("2026-10-12T12:00:00Z"),
    locales: {
      de: {title: "<img src=x onerror=alert(1)>", contentMarkdown: "# Titel\n\n## Abschnitt\n\n<script>alert(1)</script> [Link](javascript:alert(1))"},
      uk: {title: "Текст", contentMarkdown: "# Текст\n\n## Розділ\n\nБезпечно"},
    },
  });
  assert.ok(!html.includes("<script>alert(1)</script>"));
  assert.ok(!html.includes("href=\"javascript:"));
  assert.ok(!html.includes("<img src=x"));
});
