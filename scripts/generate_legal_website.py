#!/usr/bin/env python3
"""Generate bilingual public legal pages from the canonical Markdown sources."""

from __future__ import annotations

import html
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = json.loads((ROOT / "Legal/legal-manifest.json").read_text(encoding="utf-8"))
WEBSITE = ROOT / "website"

PAGES = {
    "privacy": {
        "sources": ("Legal/privacy.de.md", "Legal/privacy.uk.md"),
        "title": ("Datenschutz", "Конфіденційність"),
        "description": (
            "Wie UkrainianCommunity personenbezogene Daten verarbeitet.",
            "Як UkrainianCommunity обробляє персональні дані.",
        ),
    },
    "terms": {
        "sources": ("Legal/terms.de.md", "Legal/terms.uk.md"),
        "title": ("Nutzungsbedingungen", "Умови використання"),
        "description": (
            "Regeln, Verantwortlichkeiten und Moderation auf UkrainianCommunity.",
            "Правила, відповідальність і модерація в UkrainianCommunity.",
        ),
    },
    "organization-rules": {
        "sources": ("Legal/organization-rules.de.md", "Legal/organization-rules.uk.md"),
        "title": ("Regeln für Organisationen", "Правила для організацій"),
        "description": (
            "Pflichten und Verantwortung beim Erstellen einer Organisation.",
            "Обов’язки та відповідальність під час створення організації.",
        ),
    },
    "imprint": {
        "sources": ("Legal/imprint.de.md", "Legal/imprint.uk.md"),
        "title": ("Impressum", "Вихідні дані"),
        "description": (
            "Anbieterinformation und gesetzliche Kontaktpunkte.",
            "Інформація про оператора та офіційні контакти.",
        ),
    },
    "report-illegal-content": {
        "sources": ("Legal/notice-and-action.de.md", "Legal/notice-and-action.uk.md"),
        "title": ("Rechtswidrige Inhalte melden", "Повідомити про незаконний вміст"),
        "description": (
            "Hinweise zum Melden rechtswidriger Inhalte und zur Überprüfung.",
            "Як повідомити про незаконний вміст і подати запит на перегляд.",
        ),
    },
}


def inline(value: str) -> str:
    escaped = html.escape(value, quote=True)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    def link_url(match: re.Match[str]) -> str:
        raw = match.group(0)
        url = raw.rstrip(".,;:!?)")
        return f'<a href="{url}" rel="noopener">{url}</a>{raw[len(url):]}'

    escaped = re.sub(r"https://[^\s<]+", link_url, escaped)
    escaped = escaped.replace(
        "ukrainian.community@outlook.com",
        '<a href="mailto:ukrainian.community@outlook.com">'
        "ukrainian.community@outlook.com</a>",
    )
    return escaped


def markdown_blocks(source: str) -> tuple[str, str, str]:
    lines = source.replace("\r\n", "\n").splitlines()
    title = next(line[2:].strip() for line in lines if line.startswith("# "))
    version = next(
        (line.strip() for line in lines[1:] if line.strip() and not line.startswith("## ")),
        "",
    )
    start = next(index for index, line in enumerate(lines) if line.startswith("## "))
    lines = lines[start:]
    output: list[str] = []
    paragraph: list[str] = []
    list_items: list[str] = []
    list_tag: str | None = None
    section_open = False

    def flush_paragraph() -> None:
        if paragraph:
            output.append(
                "<p>" + "<br>\n".join(inline(line) for line in paragraph) + "</p>"
            )
            paragraph.clear()

    def flush_list() -> None:
        nonlocal list_tag
        if list_items:
            tag = list_tag or "ul"
            output.append(
                f"<{tag}>"
                + "".join(f"<li>{inline(item)}</li>" for item in list_items)
                + f"</{tag}>"
            )
            list_items.clear()
        list_tag = None

    def append_list_item(tag: str, item: str) -> None:
        nonlocal list_tag
        flush_paragraph()
        if list_tag is not None and list_tag != tag:
            flush_list()
        list_tag = tag
        list_items.append(item)

    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if line.startswith("|") and index + 1 < len(lines) and set(lines[index + 1].replace("|", "").replace("-", "").replace(":", "").strip()) == set():
            flush_paragraph()
            flush_list()
            headers = [cell.strip() for cell in line.strip("|").split("|")]
            index += 2
            rows: list[list[str]] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                rows.append([cell.strip() for cell in lines[index].strip().strip("|").split("|")])
                index += 1
            output.append(
                "<div class=\"table-scroll\"><table><thead><tr>"
                + "".join(f"<th>{inline(cell)}</th>" for cell in headers)
                + "</tr></thead><tbody>"
                + "".join(
                    "<tr>" + "".join(f"<td>{inline(cell)}</td>" for cell in row) + "</tr>"
                    for row in rows
                )
                + "</tbody></table></div>"
            )
            continue
        if line.startswith("## "):
            flush_paragraph()
            flush_list()
            if section_open:
                output.append("</section>")
            output.append(f"<section><h2>{inline(line[3:])}</h2>")
            section_open = True
        elif line.startswith("### "):
            flush_paragraph()
            flush_list()
            output.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.startswith("- "):
            append_list_item("ul", line[2:].strip())
        elif ordered_item := re.match(r"^\d+[.)]\s+(.+)$", line):
            append_list_item("ol", ordered_item.group(1).strip())
        elif not line:
            flush_paragraph()
            flush_list()
        else:
            flush_list()
            paragraph.append(line)
        index += 1
    flush_paragraph()
    flush_list()
    if section_open:
        output.append("</section>")
    return title, version, "\n".join(output)


def page_template(slug: str, de_source: str, uk_source: str) -> str:
    page = PAGES[slug]
    de_title, de_version, de_body = markdown_blocks(de_source)
    uk_title, uk_version, uk_body = markdown_blocks(uk_source)
    report_action = ""
    if slug == "report-illegal-content":
        report_action = (ROOT / "website/assets/dsa-portal.html").read_text(encoding="utf-8")
    rendered = f"""<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="{html.escape(page['description'][0])}">
  <meta name="theme-color" content="#0a66c2">
  <title>{html.escape(page['title'][0])} – UkrainianCommunity</title>
  <link rel="stylesheet" href="/assets/styles.css">
  <script src="/assets/site.js" defer></script>
  {('<script src="/assets/dsa-portal.js" defer></script>' if slug == 'report-illegal-content' else '')}
</head>
<body data-title-de="{html.escape(page['title'][0])} – UkrainianCommunity" data-title-uk="{html.escape(page['title'][1])} – UkrainianCommunity">
  <a class="skip-link" href="#main"><span data-lang="de">Zum Inhalt</span><span data-lang="uk">До вмісту</span></a>
  <header class="site-header">
    <nav class="nav" aria-label="Hauptnavigation">
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
    </nav>
  </header>
  <main id="main">
    <header class="page-header"><div class="page-header-inner">
      <p class="eyebrow">UkrainianCommunity</p>
      <h1><span data-lang="de">{html.escape(de_title)}</span><span data-lang="uk">{html.escape(uk_title)}</span></h1>
      <p><span data-lang="de">{html.escape(page['description'][0])}</span><span data-lang="uk">{html.escape(page['description'][1])}</span></p>
    </div></header>
    <article class="document">
      <div class="meta"><span data-lang="de">{html.escape(de_version)}</span><span data-lang="uk">{html.escape(uk_version)}</span></div>
      {report_action}
      <div data-lang="de">{de_body}</div>
      <div data-lang="uk">{uk_body}</div>
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
"""
    return "\n".join(line.rstrip() for line in rendered.splitlines()) + "\n"


def main() -> None:
    for slug, definition in PAGES.items():
        de_source = (ROOT / definition["sources"][0]).read_text(encoding="utf-8")
        uk_source = (ROOT / definition["sources"][1]).read_text(encoding="utf-8")
        target = WEBSITE / slug / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(page_template(slug, de_source, uk_source), encoding="utf-8")
        print(f"generated {target.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
