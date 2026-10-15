#!/usr/bin/env python3
"""Publish owner-approved Android 107 legal successors; dry-run by default."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

import publish_privacy_2026_13 as common

ROOT = Path(__file__).resolve().parent.parent
ACTOR = "legal-2026-10-15-android107-publisher"
TARGETS = {"terms": ("2026.14", "2026.15"), "privacy": ("2026.21", "2026.22")}
PUBLICATION_DATE = "2026-10-15"
PLAN_FORMAT = "uac-legal-2026-10-15-android107-v1"
require = common.require
wire = common.wire
digest = common.digest


def payload():
    manifest = json.loads((ROOT / "Legal/legal-manifest.json").read_text())
    bundle = common.load_module(ROOT / "scripts/generate_bundled_legal.py", "legal_bundle").canonical_documents()
    stored_bundle = json.loads((ROOT / "UkrainianCommunity/Resources/LegalDocuments.json").read_text())
    require(bundle == stored_bundle, "Bundled legal documents differ from sources")
    website = common.load_module(ROOT / "scripts/generate_legal_website.py", "legal_website")
    swift = (ROOT / "UkrainianCommunity/Services/Auth/AuthService.swift").read_text()
    result = {}
    for kind, (previous, version) in TARGETS.items():
        website_kind = "organization-rules" if kind == "organizationRules" else kind
        definition = manifest["documents"][kind]
        require(definition.get("version", manifest["version"]) == version, f"Wrong {kind} version")
        require(definition["supersedesVersion"] == previous
                and definition.get("effectiveDate", manifest["effectiveDate"]) == PUBLICATION_DATE,
                f"Wrong {kind} version chain")
        swift_kind = "OrganizationRules" if kind == "organizationRules" else kind.title()
        require(f'current{swift_kind}Version = "{version}"' in swift, f"Wrong iOS {kind} version")
        sources = [(ROOT / definition["files"][locale]).read_text() for locale in ("de", "uk")]
        require((ROOT / f"website/{website_kind}/index.html").read_text() == website.page_template(website_kind, *sources),
                f"{kind} website differs from sources")
        locales = {}
        for locale, source in zip(("de", "uk"), sources):
            lines = source.strip().splitlines()
            require(version in lines[2] and previous in lines[2], f"Wrong {kind} {locale} header")
            markdown = "\n".join(lines[:2] + lines[4:]).strip()
            require(markdown.startswith(lines[0] + "\n\n## 1."), f"Unexpected {kind} markdown header")
            locales[locale] = {
                "title": bundle[kind]["locales"][locale]["title"],
                "contentMarkdown": markdown,
                "contentText": common.plain(markdown),
                "contentHash": digest(markdown),
            }
        combined = "\n---\n".join(
            "\n".join([locale, value["title"], value["contentMarkdown"], value["contentText"], value["contentHash"]])
            for locale, value in sorted(locales.items())
        )
        document = {
            "documentType": kind, "version": version, "versionNumber": int(version.replace(".", "")),
            "status": "published", "requiresAcceptance": definition["requiresAcceptance"],
            "defaultLocale": "de", "canonicalLocale": "de", "locales": locales,
            "contentHash": digest(combined), "supersedesVersion": previous,
            "changeSummary": definition["changeSummary"],
            "createdBy": ACTOR, "updatedBy": ACTOR, "publishedBy": ACTOR,
        }
        pointer = {key: document[key] for key in (
            "documentType", "versionNumber", "status", "requiresAcceptance", "defaultLocale",
            "changeSummary", "updatedBy", "publishedBy"
        )}
        pointer["activeVersion"] = version
        result[kind] = {"version": document, "pointer": pointer, "inputHashes": {
            "definition": digest(definition), "sources": [digest(source) for source in sources],
            "website": digest((ROOT / f"website/{website_kind}/index.html").read_text()),
        }}
    return result


def plan_for(data, documents):
    require(set(data) == set(TARGETS), "Unexpected document types")
    for kind, (previous, version) in TARGETS.items():
        path = f"legalDocuments/{kind}"
        require(documents[path]["fields"].get("activeVersion") == wire(previous), f"Unexpected active {kind}")
        require(f"{path}/versions/{previous}" in documents, f"Missing {kind} predecessor")
        require(f"{path}/versions/{version}" not in documents, f"{kind} successor already exists")
    return {
        "format": PLAN_FORMAT, "project": common.PROJECT,
        "beforeHashes": {path: digest(document) for path, document in sorted(documents.items())},
        "pointerUpdateTimes": {kind: documents[f"legalDocuments/{kind}"]["updateTime"] for kind in TARGETS},
        "inputHashes": {kind: data[kind]["inputHashes"] for kind in TARGETS},
        "localeHashes": {kind: {locale: value["contentHash"] for locale, value in data[kind]["version"]["locales"].items()} for kind in TARGETS},
        "writes": [f"legalDocuments/{kind}/versions/{TARGETS[kind][1]}" for kind in TARGETS]
                  + [f"legalDocuments/{kind}" for kind in TARGETS],
    }


def writes_for(data, plan):
    writes = []
    for kind, (_, version) in TARGETS.items():
        base = f"legalDocuments/{kind}"
        for path, fields, timestamps in (
            (f"{base}/versions/{version}", data[kind]["version"], ("createdAt", "updatedAt", "publishedAt")),
            (base, data[kind]["pointer"], ("updatedAt", "publishedAt")),
        ):
            write = {
                "update": {"name": f"{common.DATABASE}/documents/{path}", "fields": {key: wire(value) for key, value in fields.items()}},
                "currentDocument": {"exists": False} if path != base else {"updateTime": plan["pointerUpdateTimes"][kind]},
                "updateTransforms": [{"fieldPath": key, "setToServerValue": "REQUEST_TIME"} for key in timestamps],
            }
            if path == base:
                write["updateMask"] = {"fieldPaths": list(fields)}
            writes.append(write)
    return {"writes": writes}


def verify(data, plan, after):
    require(plan["format"] == PLAN_FORMAT and plan["project"] == common.PROJECT, "Wrong plan")
    require(plan["inputHashes"] == {kind: data[kind]["inputHashes"] for kind in TARGETS}, "Local inputs changed")
    targets = {f"legalDocuments/{kind}/versions/{version}" for kind, (_, version) in TARGETS.items()}
    require(set(after) == set(plan["beforeHashes"]) | targets, "Legal document inventory changed")
    for path, expected in plan["beforeHashes"].items():
        if path not in {f"legalDocuments/{kind}" for kind in TARGETS}:
            require(digest(after[path]) == expected, f"Preserved legal document changed: {path}")
    for kind, (_, version) in TARGETS.items():
        base = f"legalDocuments/{kind}"
        for path, expected in ((base, data[kind]["pointer"]), (f"{base}/versions/{version}", data[kind]["version"])):
            fields = after[path]["fields"]
            require(all(fields.get(key) == wire(value) for key, value in expected.items()), f"Read-back differs: {path}")
            require(all("timestampValue" in fields.get(key, {}) for key in ("updatedAt", "publishedAt")), f"Missing timestamps: {path}")
        locales = after[f"{base}/versions/{version}"]["fields"]["locales"]["mapValue"]["fields"]
        for locale, expected in plan["localeHashes"][kind].items():
            fields = locales[locale]["mapValue"]["fields"]
            require(fields["contentHash"] == wire(expected), f"{kind} {locale} locale hash changed")
            require(digest(fields["contentMarkdown"]["stringValue"]) == expected, f"{kind} {locale} content hash differs")
    return {"activeVersions": {kind: version for kind, (_, version) in TARGETS.items()},
            "preservedDocumentCount": len(plan["beforeHashes"]) - len(TARGETS),
            "localeHashes": plan["localeHashes"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--control", type=Path, default=common.CONTROL)
    args = parser.parse_args()
    data = payload()
    transport = common.Transport(args.control)
    if not args.apply and not args.verify:
        plan = plan_for(data, common.snapshot(transport))
        args.plan.parent.mkdir(parents=True, exist_ok=True)
        with args.plan.open("x") as output:
            json.dump(plan, output, indent=2)
            output.write("\n")
        print(json.dumps({"result": "dry-run-no-writes", "plan": str(args.plan), "writes": plan["writes"],
                          "preservedDocumentCount": len(plan["beforeHashes"]) - len(TARGETS)}, indent=2))
        return
    plan = json.loads(args.plan.read_text())
    if args.apply:
        require(datetime.now(ZoneInfo("Europe/Vienna")).date().isoformat() == PUBLICATION_DATE, "Publication date changed")
        require(plan_for(data, common.snapshot(transport)) == plan, "Plan is stale; no write attempted")
        try:
            status, _ = transport.request(common.BASE + ":commit", writes_for(data, plan))
        except Exception:
            status = None
        try:
            result = verify(data, plan, common.snapshot(transport))
        except Exception:
            raise ValueError("Publication unconfirmed. Do not retry --apply; inspect with --verify.") from None
        result["result"] = "published-and-verified" if status == 200 else "verified-after-uncertain-response"
    else:
        result = {"result": "verified-read-only", **verify(data, plan, common.snapshot(transport))}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("Legal publication unconfirmed; inspect read-only without repeating writes.", file=sys.stderr)
        sys.exit(1)
