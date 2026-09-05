#!/usr/bin/env python3
"""Fixed-target privacy publication. Default: read-only dry-run; never retries writes."""
from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "ukrainiancommunity-dbd5f"
DATABASE = f"projects/{PROJECT}/databases/(default)"
BASE = f"https://firestore.googleapis.com/v1/{DATABASE}/documents"
POINTER = "legalDocuments/privacy"
TARGET = f"{POINTER}/versions/2026.13"
KINDS = ("privacy", "terms", "organizationRules")
CONTROL = Path("/Users/serlest/Documents/Codex/2026-09-04/new-chat/production-release/control.py")
ACTOR = "privacy-2026.13-publisher"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(value):
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(value.encode()).hexdigest()


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def wire(value):
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, str):
        return {"stringValue": value}
    if isinstance(value, dict):
        return {"mapValue": {"fields": {k: wire(v) for k, v in value.items()}}}
    raise ValueError("Unsupported publication value")


def plain(markdown):
    text = re.sub(r"^#{1,6}\s+", "", markdown, flags=re.M)
    text = re.sub(r"^[-*]\s+", "• ", text, flags=re.M)
    text = re.sub(r"\*\*(.*?)\*\*", r"\1", text)
    return re.sub(r"`([^`]+)`", r"\1", text).strip()


def local_payload():
    manifest = json.loads((ROOT / "Legal/legal-manifest.json").read_text())
    definition = manifest["documents"]["privacy"]
    require(definition["version"] == "2026.13" and definition["supersedesVersion"] == "2026.12", "Unexpected privacy version chain")
    require(definition["requiresAcceptance"] is False, "Privacy must not require acceptance")
    require(manifest["canonicalLocale"] == "de" and manifest["supportedLocales"] == ["de", "uk"], "Unexpected locales")
    bundle_module = load_module(ROOT / "scripts/generate_bundled_legal.py", "privacy_bundle")
    expected = bundle_module.canonical_documents()["privacy"]
    bundled = json.loads((ROOT / "UkrainianCommunity/Resources/LegalDocuments.json").read_text())["privacy"]
    require(bundled == expected, "Privacy bundle differs from canonical sources")
    website_module = load_module(ROOT / "scripts/generate_legal_website.py", "privacy_website")
    sources = [(ROOT / definition["files"][locale]).read_text() for locale in ("de", "uk")]
    require(all(re.search(r"(?:Version|Версія) 2026\.13\b", source) for source in sources), "Wrong source header version")
    effective = date.fromisoformat(definition["effectiveDate"])
    de_months = "Januar Februar März April Mai Juni Juli August September Oktober November Dezember".split()
    uk_months = "січня лютого березня квітня травня червня липня серпня вересня жовтня листопада грудня".split()
    headers = [
        f"Version 2026.13 · Gültig ab {effective.day}. {de_months[effective.month - 1]} {effective.year} · ersetzt Version 2026.12.",
        f"Версія 2026.13 · Чинна з {effective.day} {uk_months[effective.month - 1]} {effective.year} року · замінює версію 2026.12.",
    ]
    require(all(header in source.splitlines() for header, source in zip(headers, sources)), "Source effective dates differ from manifest")
    website = (ROOT / "website/privacy/index.html").read_text()
    require(website == website_module.page_template("privacy", *sources), "Privacy website differs from canonical sources")
    require('currentPrivacyVersion = "2026.13"' in (ROOT / "UkrainianCommunity/Services/Auth/AuthService.swift").read_text(), "Wrong client privacy version")
    locales = {locale: {**content, "contentText": plain(content["contentMarkdown"])} for locale, content in expected["locales"].items()}
    combined = "\n---\n".join("\n".join([locale, content["title"], content["contentMarkdown"], content["contentText"], content["contentHash"]]) for locale, content in sorted(locales.items()))
    version = {
        "documentType": "privacy", "version": "2026.13", "versionNumber": 202613,
        "status": "published", "requiresAcceptance": False, "defaultLocale": "de",
        "canonicalLocale": "de", "locales": locales, "contentHash": digest(combined),
        "supersedesVersion": "2026.12", "changeSummary": definition["changeSummary"],
        "createdBy": ACTOR, "updatedBy": ACTOR, "publishedBy": ACTOR,
    }
    pointer = {key: version[key] for key in ("documentType", "versionNumber", "status", "requiresAcceptance", "defaultLocale", "changeSummary", "updatedBy", "publishedBy")}
    pointer["activeVersion"] = "2026.13"
    inputs = {"definition": digest(definition), "sources": [digest(s) for s in sources], "bundle": digest(bundled), "website": digest(website)}
    return {"version": version, "pointer": pointer, "inputHashes": inputs, "effectiveDate": definition["effectiveDate"]}


class Transport:
    def __init__(self, control_path):
        self.control = load_module(control_path, "privacy_control")
        require(self.control.PROJECT == PROJECT, "Control helper uses another project")

    def request(self, url, body=None):
        # No auth headers, error response bodies, account IDs or document text are logged.
        return self.control.request(url, body=body, method="POST" if body is not None else "GET")


def snapshot(transport):
    documents = {}
    for kind in KINDS:
        path = f"legalDocuments/{kind}"
        status, document = transport.request(f"{BASE}/{path}")
        require(status == 200, f"Could not read {path}: HTTP {status}")
        documents[path] = document
        token = ""
        seen = set()
        while True:
            from urllib.parse import urlencode
            query = urlencode({"pageSize": 100, **({"pageToken": token} if token else {})})
            status, page = transport.request(f"{BASE}/{path}/versions?{query}")
            require(status == 200, f"Could not list {path} versions: HTTP {status}")
            for item in page.get("documents", []):
                prefix = f"{DATABASE}/documents/"
                require(item["name"].startswith(prefix + path + "/versions/"), "Unexpected returned document path")
                documents[item["name"][len(prefix):]] = item
            token = page.get("nextPageToken", "")
            if not token:
                break
            require(token not in seen and len(seen) < 100, "Unexpected version pagination")
            seen.add(token)
    return documents


def plan_for(payload, documents):
    pointer = documents[POINTER]
    require(pointer["fields"].get("activeVersion") == wire("2026.12"), "Active privacy must still be 2026.12; use --verify for a completed/uncertain attempt")
    require(TARGET not in documents, "2026.13 already exists; refusing to replace immutable evidence")
    require(f"{POINTER}/versions/2026.12" in documents, "Missing historical 2026.12")
    for kind in KINDS:
        path = f"legalDocuments/{kind}"
        active = documents[path]["fields"]["activeVersion"]["stringValue"]
        require(f"{path}/versions/{active}" in documents, "Missing active legal version")
    return {
        "format": "uac-privacy-2026.13-plan-v1", "project": PROJECT,
        "effectiveDate": payload["effectiveDate"], "inputHashes": payload["inputHashes"],
        "pointerUpdateTime": pointer["updateTime"],
        "beforeHashes": {path: digest(doc) for path, doc in sorted(documents.items())},
        "localeHashes": {locale: content["contentHash"] for locale, content in payload["version"]["locales"].items()},
        "contentHash": payload["version"]["contentHash"],
        "writes": [TARGET, POINTER],
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
    return {"project": PROJECT, "activeVersion": "2026.13", "localeHashes": hashes,
            "contentHash": payload["version"]["contentHash"], "preservedDocumentCount": len(plan["beforeHashes"]) - 1,
            "publishedAt": after[TARGET]["fields"]["publishedAt"]["timestampValue"]}


def apply(transport, payload, plan):
    require(datetime.now(ZoneInfo("Europe/Vienna")).date().isoformat() == payload["effectiveDate"], "Effective date must match publication day; reconcile sources and regenerate the plan")
    require(plan_for(payload, snapshot(transport)) == plan, "Reviewed plan is stale; no write attempted")
    uncertain = False
    try:
        status, _ = transport.request(BASE + ":commit", writes_for(payload, plan))
        uncertain = status != 200
    except Exception:
        uncertain = True
    # Exactly one read-back attempt even after an uncertain commit; never retry a write.
    try:
        result = verify(payload, plan, snapshot(transport))
    except Exception:
        raise ValueError("Publication not confirmed. Do not retry --apply; use --verify with the same plan and investigate.") from None
    result["result"] = "verified-after-uncertain-response" if uncertain else "published-and-verified"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Explicitly execute the reviewed two-write atomic commit")
    mode.add_argument("--verify", action="store_true", help="Read back only, including after an uncertain commit")
    parser.add_argument("--plan", type=Path, required=True, help="Dry-run creates a new review plan; apply/verify reads it")
    parser.add_argument("--control", type=Path, default=CONTROL, help="Existing authentication helper; tokens are never output")
    args = parser.parse_args()
    payload = local_payload()
    transport = Transport(args.control)
    if args.apply or args.verify:
        plan = json.loads(args.plan.read_text())
        result = apply(transport, payload, plan) if args.apply else {"result": "verified-read-only", **verify(payload, plan, snapshot(transport))}
        print(json.dumps(result, indent=2))
    else:
        plan = plan_for(payload, snapshot(transport))
        # Never overwrite the evidence used by an earlier publication attempt.
        args.plan.parent.mkdir(parents=True, exist_ok=True)
        with args.plan.open("x") as file:
            json.dump(plan, file, indent=2)
            file.write("\n")
        print(json.dumps({"result": "dry-run-no-writes", "plan": str(args.plan), **plan}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("Publisher failed; no automatic retry. Details suppressed to protect credentials. Use --verify after any attempted commit.", file=sys.stderr)
        sys.exit(1)
