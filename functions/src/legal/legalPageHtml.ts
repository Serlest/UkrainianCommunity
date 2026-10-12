import MarkdownIt = require("markdown-it");

export type PublicLegalType = "terms" | "privacy" | "organizationRules";

export interface PublicLegalContent {
  title: string;
  contentMarkdown: string;
}

export interface PublicLegalPage {
  type: PublicLegalType;
  version: string;
  publishedAt: Date;
  supersedesVersion?: string;
  locales: {de: PublicLegalContent; uk: PublicLegalContent};
}

const markdown = new MarkdownIt({html: false, linkify: true, breaks: true});
markdown.disable("image");
markdown.validateLink = (url: string) => /^(https:\/\/|mailto:)/i.test(url);

const presentation: Record<PublicLegalType, {
  de: string; uk: string; descriptionDe: string; descriptionUk: string;
}> = {
  terms: {
    de: "Nutzungsbedingungen", uk: "Умови використання",
    descriptionDe: "Regeln, Verantwortlichkeiten und Moderation auf UkrainianCommunity.",
    descriptionUk: "Правила, відповідальність і модерація в UkrainianCommunity.",
  },
  privacy: {
    de: "Datenschutz", uk: "Конфіденційність",
    descriptionDe: "Wie UkrainianCommunity personenbezogene Daten verarbeitet.",
    descriptionUk: "Як UkrainianCommunity обробляє персональні дані.",
  },
  organizationRules: {
    de: "Regeln für Organisationen", uk: "Правила для організацій",
    descriptionDe: "Pflichten und Verantwortung beim Erstellen einer Organisation.",
    descriptionUk: "Обов’язки та відповідальність під час створення організації.",
  },
};

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;",
  })[character] ?? character);
}

function legalBody(content: PublicLegalContent): string {
  const withoutTitle = content.contentMarkdown.replace(/^# [^\n]+\n+/, "");
  return markdown.render(withoutTitle)
    .replace(/<table>/g, '<div class="table-scroll"><table>')
    .replace(/<\/table>/g, "</table></div>");
}

function versionLine(page: PublicLegalPage, locale: "de" | "uk"): string {
  const date = new Intl.DateTimeFormat(locale === "de" ? "de-AT" : "uk-UA", {
    day: "numeric", month: "long", year: "numeric", timeZone: "Europe/Vienna",
  }).format(page.publishedAt);
  const previous = page.supersedesVersion;
  if (locale === "de") {
    return `Version ${page.version} · Veröffentlicht am ${date}` +
      (previous ? ` · ersetzt Version ${previous}` : "");
  }
  return `Версія ${page.version} · Опубліковано ${date}` +
    (previous ? ` · замінює версію ${previous}` : "");
}

export function renderPublicLegalPage(page: PublicLegalPage): string {
  const label = presentation[page.type];
  const de = page.locales.de;
  const uk = page.locales.uk;
  return `<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${escapeHtml(label.descriptionDe)}">
  <meta name="theme-color" content="#0a66c2">
  <title>${escapeHtml(label.de)} – UkrainianCommunity</title>
  <link rel="stylesheet" href="/assets/styles.css">
  <script src="/assets/site.js" defer></script>
</head>
<body data-title-de="${escapeHtml(label.de)} – UkrainianCommunity" data-title-uk="${escapeHtml(label.uk)} – UkrainianCommunity">
  <a class="skip-link" href="#main"><span data-lang="de">Zum Inhalt</span><span data-lang="uk">До вмісту</span></a>
  <header class="site-header"><nav class="nav" aria-label="Hauptnavigation">
    <a class="brand" href="/">UkrainianCommunity</a>
    <div class="nav-links">
      <a href="/support">Support</a>
      <a href="/privacy"><span data-lang="de">Datenschutz</span><span data-lang="uk">Конфіденційність</span></a>
      <a href="/terms"><span data-lang="de">Bedingungen</span><span data-lang="uk">Умови</span></a>
      <a href="/organization-rules"><span data-lang="de">Organisationen</span><span data-lang="uk">Організації</span></a>
      <a href="/imprint"><span data-lang="de">Impressum</span><span data-lang="uk">Вихідні дані</span></a>
    </div>
    <div class="language-switch" role="group" aria-label="Sprache / Мова">
      <button type="button" data-language-button="de" aria-pressed="true" lang="de">DE</button>
      <button type="button" data-language-button="uk" aria-pressed="false" lang="uk">UA</button>
    </div>
  </nav></header>
  <main id="main">
    <header class="page-header"><div class="page-header-inner">
      <p class="eyebrow">UkrainianCommunity</p>
      <h1><span data-lang="de">${escapeHtml(de.title)}</span><span data-lang="uk">${escapeHtml(uk.title)}</span></h1>
      <p><span data-lang="de">${escapeHtml(label.descriptionDe)}</span><span data-lang="uk">${escapeHtml(label.descriptionUk)}</span></p>
    </div></header>
    <article class="document">
      <div class="meta"><span data-lang="de">${escapeHtml(versionLine(page, "de"))}</span><span data-lang="uk">${escapeHtml(versionLine(page, "uk"))}</span></div>
      <div data-lang="de">${legalBody(de)}</div>
      <div data-lang="uk">${legalBody(uk)}</div>
    </article>
  </main>
  <footer class="site-footer"><div class="footer-inner">
    <span>© <span data-current-year></span> Timofeev Philipp · UkrainianCommunity</span>
    <div class="footer-links">
      <a href="/support">Support</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/organization-rules">Organization rules</a>
      <a href="/imprint">Impressum</a><a href="/report-illegal-content"><span data-lang="de">Inhalt melden</span><span data-lang="uk">Повідомити</span></a>
    </div>
  </div></footer>
</body>
</html>
`;
}
