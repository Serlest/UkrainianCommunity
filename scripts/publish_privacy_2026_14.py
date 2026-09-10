#!/usr/bin/env python3
"""Publish immutable cross-platform privacy 2026.14. Dry-run by default."""
from __future__ import annotations

from datetime import date
import json
from pathlib import Path
import re

import publish_privacy_2026_13 as base

ROOT = base.ROOT
PROJECT = base.PROJECT
DATABASE = base.DATABASE
BASE = base.BASE
POINTER = base.POINTER
TARGET = f"{POINTER}/versions/2026.14"
KINDS = base.KINDS
CONTROL = base.CONTROL
ACTOR = "privacy-2026.14-publisher"
require = base.require
digest = base.digest
wire = base.wire
plain = base.plain
Transport = base.Transport


def local_payload():
    manifest = json.loads((ROOT / "Legal/legal-manifest.json").read_text())
    definition = manifest["documents"]["privacy"]
    require(definition["version"] == "2026.14" and definition["supersedesVersion"] == "2026.13", "Unexpected privacy version chain")
    require(definition["requiresAcceptance"] is False, "Privacy must not require acceptance")
    require(manifest["canonicalLocale"] == "de" and manifest["supportedLocales"] == ["de", "uk"], "Unexpected locales")
    bundle_module = base.load_module(ROOT / "scripts/generate_bundled_legal.py", "privacy_bundle_2026_14")
    expected = bundle_module.canonical_documents()["privacy"]
    bundled = json.loads((ROOT / "UkrainianCommunity/Resources/LegalDocuments.json").read_text())["privacy"]
    require(bundled == expected, "Privacy bundle differs from canonical sources")
    website_module = base.load_module(ROOT / "scripts/generate_legal_website.py", "privacy_website_2026_14")
    sources = [(ROOT / definition["files"][locale]).read_text() for locale in ("de", "uk")]
    require(all(re.search(r"(?:Version|Версія) 2026\.14\b", source) for source in sources), "Wrong source header version")
    effective = date.fromisoformat(definition["effectiveDate"])
    de_months = "Januar Februar März April Mai Juni Juli August September Oktober November Dezember".split()
    uk_months = "січня лютого березня квітня травня червня липня серпня вересня жовтня листопада грудня".split()
    headers = [
        f"Version 2026.14 · Gültig ab {effective.day}. {de_months[effective.month - 1]} {effective.year} · ersetzt Version 2026.13.",
        f"Версія 2026.14 · Чинна з {effective.day} {uk_months[effective.month - 1]} {effective.year} року · замінює версію 2026.13.",
    ]
    require(all(header in source.splitlines() for header, source in zip(headers, sources)), "Source effective dates differ from manifest")
    website = (ROOT / "website/privacy/index.html").read_text()
    require(website == website_module.page_template("privacy", *sources), "Privacy website differs from canonical sources")
    require('currentPrivacyVersion = "2026.14"' in (ROOT / "UkrainianCommunity/Services/Auth/AuthService.swift").read_text(), "Wrong client privacy version")
    locales = {locale: {**content, "contentText": plain(content["contentMarkdown"])} for locale, content in expected["locales"].items()}
    combined = "\n---\n".join("\n".join([locale, content["title"], content["contentMarkdown"], content["contentText"], content["contentHash"]]) for locale, content in sorted(locales.items()))
    version = {
        "documentType": "privacy", "version": "2026.14", "versionNumber": 202614,
        "status": "published", "requiresAcceptance": False, "defaultLocale": "de",
        "canonicalLocale": "de", "locales": locales, "contentHash": digest(combined),
        "supersedesVersion": "2026.13", "changeSummary": definition["changeSummary"],
        "createdBy": ACTOR, "updatedBy": ACTOR, "publishedBy": ACTOR,
    }
    pointer = {key: version[key] for key in ("documentType", "versionNumber", "status", "requiresAcceptance", "defaultLocale", "changeSummary", "updatedBy", "publishedBy")}
    pointer["activeVersion"] = "2026.14"
    inputs = {"definition": digest(definition), "sources": [digest(s) for s in sources], "bundle": digest(bundled), "website": digest(website)}
    return {"version": version, "pointer": pointer, "inputHashes": inputs, "effectiveDate": definition["effectiveDate"]}


def snapshot(transport):
    return base.snapshot(transport)


def plan_for(payload, documents):
    pointer = documents[POINTER]
    require(pointer["fields"].get("activeVersion") == wire("2026.13"), "Active privacy must still be 2026.13; use --verify for a completed/uncertain attempt")
    require(TARGET not in documents, "2026.14 already exists; refusing to replace immutable evidence")
    require(f"{POINTER}/versions/2026.13" in documents, "Missing historical 2026.13")
    for kind in KINDS:
        path = f"legalDocuments/{kind}"
        active = documents[path]["fields"]["activeVersion"]["stringValue"]
        require(f"{path}/versions/{active}" in documents, "Missing active legal version")
    return {
        "format": "uac-privacy-2026.14-plan-v1", "project": PROJECT,
        "effectiveDate": payload["effectiveDate"], "inputHashes": payload["inputHashes"],
        "pointerUpdateTime": pointer["updateTime"],
        "beforeHashes": {path: digest(doc) for path, doc in sorted(documents.items())},
        "localeHashes": {locale: content["contentHash"] for locale, content in payload["version"]["locales"].items()},
        "contentHash": payload["version"]["contentHash"], "writes": [TARGET, POINTER],
    }


def writes_for(payload, plan):
    writes = []
    for path, fields, timestamps in (
        (TARGET, payload["version"], ("createdAt", "updatedAt", "publishedAt")),
        (POINTER, payload["pointer"], ("updatedAt", "publishedAt")),
    ):
        write = {"update": {"name": f"{DATABASE}/documents/{path}", "fields": {k: wire(v) for k, v in fields.items()}},
                 "currentDocument": {"exists": False} if path == TARGET else {"updateTime": plan["pointerUpdateTime"]},
                 "updateTransforms": [{"fieldPath": key, "setToServerValue": "REQUEST_TIME"} for key in timestamps]}
        if path == POINTER:
            write["updateMask"] = {"fieldPaths": list(fields)}
        writes.append(write)
    return {"writes": writes}


def verify(payload, plan, after):
    require(plan["project"] == PROJECT and plan["inputHashes"] == payload["inputHashes"], "Plan/project/local inputs changed")
    require(set(after) == set(plan["beforeHashes"]) | {TARGET}, "Legal document set changed unexpectedly")
    for path, expected in plan["beforeHashes"].items():
        if path != POINTER:
            require(digest(after[path]) == expected, f"Preserved legal document changed: {path}")
    for path, expected in ((TARGET, payload["version"]), (POINTER, payload["pointer"])):
        fields = after[path]["fields"]
        require(all(fields.get(key) == wire(value) for key, value in expected.items()), f"Read-back differs: {path}")
        require(all("timestampValue" in fields.get(key, {}) for key in ("updatedAt", "publishedAt")), "Missing publication timestamp")
    require("timestampValue" in after[TARGET]["fields"].get("createdAt", {}), "Missing creation timestamp")
    locales = after[TARGET]["fields"]["locales"]["mapValue"]["fields"]
    hashes = {}
    for locale in ("de", "uk"):
        fields = locales[locale]["mapValue"]["fields"]
        hashes[locale] = digest(fields["contentMarkdown"]["stringValue"])
        require(hashes[locale] == plan["localeHashes"][locale] == fields["contentHash"]["stringValue"], "Locale read-back hash differs")
    return {"project": PROJECT, "activeVersion": "2026.14", "localeHashes": hashes,
            "contentHash": payload["version"]["contentHash"], "preservedDocumentCount": len(plan["beforeHashes"]) - 1,
            "publishedAt": after[TARGET]["fields"]["publishedAt"]["timestampValue"]}


def apply(transport, payload, plan):
    from datetime import datetime
    from zoneinfo import ZoneInfo
    require(datetime.now(ZoneInfo("Europe/Vienna")).date().isoformat() == payload["effectiveDate"], "Effective date must match publication day")
    require(plan_for(payload, snapshot(transport)) == plan, "Reviewed plan is stale; no write attempted")
    uncertain = False
    try:
        status, _ = transport.request(BASE + ":commit", writes_for(payload, plan))
        uncertain = status != 200
    except Exception:
        uncertain = True
    try:
        result = verify(payload, plan, snapshot(transport))
    except Exception:
        raise ValueError("Publication not confirmed. Do not retry --apply; use --verify with the same plan.") from None
    result["result"] = "verified-after-uncertain-response" if uncertain else "published-and-verified"
    return result


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--control", type=Path, default=CONTROL)
    args = parser.parse_args()
    payload = local_payload()
    transport = Transport(args.control)
    if args.apply or args.verify:
        plan = json.loads(args.plan.read_text())
        require(plan["format"] == "uac-privacy-2026.14-plan-v1", "Wrong plan")
        result = apply(transport, payload, plan) if args.apply else {"result": "verified-read-only", **verify(payload, plan, snapshot(transport))}
        print(json.dumps(result, indent=2))
    else:
        plan = plan_for(payload, snapshot(transport))
        args.plan.parent.mkdir(parents=True, exist_ok=True)
        with args.plan.open("x") as file:
            json.dump(plan, file, indent=2)
            file.write("\n")
        print(json.dumps({"result": "dry-run-no-writes", "plan": str(args.plan), **plan}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=__import__("sys").stderr)
        raise SystemExit(1)
    except Exception:
        print("Publisher failed; no automatic retry. Use --verify after any attempted commit.", file=__import__("sys").stderr)
        raise SystemExit(1)
