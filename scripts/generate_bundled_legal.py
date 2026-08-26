#!/usr/bin/env python3
"""Bundle the published bilingual legal sources; --check is safe for CI."""

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "UkrainianCommunity/Resources/LegalDocuments.json"


def canonical_documents():
    manifest = json.loads((ROOT / "Legal/legal-manifest.json").read_text())
    if manifest["status"] != "published":
        raise ValueError("Only approved published documents may enter the app bundle")
    documents = {}
    for kind, definition in manifest["documents"].items():
        version = definition.get("version", manifest["version"])
        locales = {}
        for locale, filename in definition["files"].items():
            lines = (ROOT / filename).read_text().splitlines()
            heading = next(line for line in lines if line.startswith("# "))
            first_section = next(i for i, line in enumerate(lines) if line.startswith("## "))
            markdown = "\n".join([heading, "", *lines[first_section:]]).strip()
            locales[locale] = {
                "title": heading[2:].strip(),
                "contentMarkdown": markdown,
                "contentHash": hashlib.sha256(markdown.encode()).hexdigest(),
            }
        documents[kind] = {
            "id": kind, "type": kind, "version": version,
            "versionNumber": int(version.replace(".", "")),
            "locales": locales, "defaultLocale": manifest["canonicalLocale"],
            "canonicalLocale": manifest["canonicalLocale"],
            "requiresAcceptance": definition["requiresAcceptance"], "status": "published",
        }
    return documents


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = json.dumps(canonical_documents(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text() != expected:
            print("Bundled legal documents are stale. Run scripts/generate_bundled_legal.py")
            return 1
        print("Bundled legal documents match every published German/Ukrainian source.")
    else:
        OUTPUT.write_text(expected)
        print("Generated full bilingual offline legal documents.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
