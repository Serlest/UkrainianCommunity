#!/usr/bin/env python3
"""Replace only privacy, support and account-deletion pages on live Hosting."""
from __future__ import annotations

import argparse
from datetime import datetime
import gzip
import json
from pathlib import Path
import sys
import urllib.error
import urllib.request
from urllib.parse import urlencode
from uuid import uuid4
from zoneinfo import ZoneInfo

import publish_privacy_2026_14 as privacy
import publish_privacy_hosting_2026_13 as hosting

SITE = hosting.SITE
LIVE = hosting.LIVE
ROUTES = {
    "/privacy/index.html": ("website/privacy/index.html", "https://ukrainiancommunity-dbd5f.web.app/privacy"),
    "/support/index.html": ("website/support/index.html", "https://ukrainiancommunity-dbd5f.web.app/support"),
    "/delete-account/index.html": ("website/delete-account/index.html", "https://ukrainiancommunity-dbd5f.web.app/delete-account"),
}
require = privacy.require
sha = hosting.sha
Transport = hosting.Transport
current = hosting.current
inventory = hosting.inventory
save_new = hosting.save_new
journal = hosting.journal


def public(url, allow_missing=False):
    request = urllib.request.Request(url + "?uac_legal_readback=" + uuid4().hex,
                                     headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            require(response.status == 200 and response.url.startswith(url), "Unexpected public response")
            body = response.read()
            if response.headers.get("Content-Encoding") == "gzip":
                body = gzip.decompress(body)
            return body
    except urllib.error.HTTPError as error:
        if allow_missing and error.code == 404:
            return None
        raise


def payload():
    legal = privacy.local_payload()
    require(legal["effectiveDate"] == "2026-09-10", "Unexpected legal effective date")
    pages = {}
    for path, (source, _) in ROUTES.items():
        raw = (privacy.ROOT / source).read_bytes()
        compressed = gzip.compress(raw, compresslevel=9, mtime=0)
        pages[path] = {"raw": raw, "compressed": compressed, "htmlHash": sha(raw), "gzipHash": sha(compressed)}
    require(b"Version 2026.14" in pages["/privacy/index.html"]["raw"] and "Версія 2026.14".encode() in pages["/privacy/index.html"]["raw"], "Privacy locale markers missing")
    require(b"/delete-account" in pages["/support/index.html"]["raw"], "Support page does not link account deletion")
    require(b"iOS" in pages["/delete-account/index.html"]["raw"] and b"Android" in pages["/delete-account/index.html"]["raw"], "Deletion page is not cross-platform")
    return {"effectiveDate": legal["effectiveDate"], "legalInputs": legal["inputHashes"],
            "pages": {path: {key: value for key, value in page.items() if key not in ("raw", "compressed")} for path, page in pages.items()}}, pages


def prepare(transport, local):
    before = current(transport)
    old = inventory(transport, before["version"])
    require("/privacy/index.html" in old["files"] and "/support/index.html" in old["files"], "Live filemap is missing baseline legal pages")
    before_public = {}
    for path, (_, url) in ROUTES.items():
        body = public(url, allow_missing=path == "/delete-account/index.html")
        before_public[path] = None if body is None else sha(body)
    require(b"Version 2026.13" in public(ROUTES["/privacy/index.html"][1]), "Live privacy is not 2026.13")
    require(current(transport) == before, "Live release changed while preparing")
    after = dict(old["files"])
    for path, page in local["pages"].items():
        after[path] = page["gzipHash"]
    changed = sorted(path for path in ROUTES if old["files"].get(path) != after[path])
    require(changed == sorted(ROUTES), "Expected exactly the three approved legal paths to change")
    return {"format": "uac-android-legal-hosting-2026.14-v1", "site": SITE,
            "beforeRelease": before, "config": old["config"], "beforeFiles": old["files"],
            "afterFiles": dict(sorted(after.items())), "beforePublicHashes": before_public,
            "local": local, "changedPaths": changed}


def verify(transport, plan, state, rollback=False):
    live = current(transport)
    expected_version = plan["beforeRelease"]["version"] if rollback else state["candidateVersion"]
    require(live["version"] == expected_version, "Expected version is not live")
    expected_files = plan["beforeFiles"] if rollback else plan["afterFiles"]
    require(inventory(transport, expected_version) == {"config": plan["config"], "files": expected_files}, "Live config/filemap differs")
    public_hashes = {}
    if rollback:
        for path, (_, url) in ROUTES.items():
            body = public(url, allow_missing=plan["beforePublicHashes"][path] is None)
            public_hashes[path] = None if body is None else sha(body)
        require(public_hashes == plan["beforePublicHashes"], "Rollback public hashes differ")
    else:
        for path, (_, url) in ROUTES.items():
            public_hashes[path] = sha(public(url))
            require(public_hashes[path] == plan["local"]["pages"][path]["htmlHash"], f"Public hash differs: {path}")
    require(current(transport) == live, "Release changed during read-back")
    return {"release": live, "publicHashes": public_hashes, "fileCount": len(expected_files),
            "unchangedOtherFiles": len(expected_files) - len(ROUTES), "rollbackPaths": sorted(ROUTES), "rollback": rollback}


def apply(transport, plan, local, pages, state_path):
    require(plan["site"] == SITE and plan["local"] == local, "Plan/local mismatch")
    require(datetime.now(ZoneInfo("Europe/Vienna")).date().isoformat() == local["effectiveDate"], "Effective date must match publication day")
    require(prepare(transport, local) == plan, "Reviewed plan is stale")
    state = {"planHash": privacy.digest(plan), "phase": "reserved"}
    save_new(state_path, state)
    journal(state_path, state, "create-intent")
    created = transport.api("POST", SITE + "/versions", {"config": plan["config"], "labels": {"deployment-tool": "android-legal-scoped-publisher"}})
    version = created["name"]
    hosting.validate_version(version)
    journal(state_path, state, "created", candidateVersion=version)
    pairs = sorted(plan["afterFiles"].items())
    required = set()
    for offset in range(0, len(pairs), 1000):
        response = transport.api("POST", version + ":populateFiles", {"files": dict(pairs[offset:offset + 1000])})
        required.update(response.get("uploadRequiredHashes", []))
    allowed = {page["gzipHash"] for page in local["pages"].values()}
    require(required <= allowed, "Hosting requested unrelated payloads")
    by_hash = {page["gzipHash"]: page["compressed"] for page in pages.values()}
    for digest in sorted(required):
        journal(state_path, state, "upload-intent", uploadHash=digest)
        transport.upload(version, digest, by_hash[digest])
    journal(state_path, state, "finalize-intent")
    transport.api("PATCH", version + "?updateMask=status", {"status": "FINALIZED"})
    require(inventory(transport, version) == {"config": plan["config"], "files": plan["afterFiles"]}, "Candidate differs")
    require(current(transport) == plan["beforeRelease"], "Live release changed before publish")
    journal(state_path, state, "release-intent")
    try:
        transport.api("POST", LIVE + "/releases?" + urlencode({"versionName": version}), {"message": "Android launch legal pages: privacy 2026.14, support, account deletion"})
    except Exception:
        journal(state_path, state, "release-response-uncertain")
        raise ValueError("Release response uncertain; use --verify, never repeat apply") from None
    result = verify(transport, plan, state)
    journal(state_path, state, "verified", publishedRelease=result["release"])
    return result


def rollback(transport, plan, state, state_path):
    require(state["phase"] == "verified" and current(transport) == state["publishedRelease"], "Rollback requires exact publication still live")
    journal(state_path, state, "rollback-intent")
    transport.api("POST", LIVE + "/releases?" + urlencode({"versionName": plan["beforeRelease"]["version"]}), {"message": "Rollback Android launch legal pages"})
    result = verify(transport, plan, state, rollback=True)
    journal(state_path, state, "rollback-verified", rollbackRelease=result["release"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    for mode in ("apply", "verify", "rollback", "verify-rollback"):
        modes.add_argument("--" + mode, action="store_true")
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--control", type=Path, default=privacy.CONTROL)
    args = parser.parse_args()
    local, pages = payload()
    transport = Transport(args.control)
    if not any((args.apply, args.verify, args.rollback, args.verify_rollback)):
        plan = prepare(transport, local)
        save_new(args.plan, plan)
        print(json.dumps({"result": "dry-run-no-writes", "plan": str(args.plan), "beforeRelease": plan["beforeRelease"], "changedPaths": plan["changedPaths"], "preservedFiles": len(plan["beforeFiles"]) - len(ROUTES)}, indent=2))
        return
    require(args.state is not None, "--state is required")
    plan = json.loads(args.plan.read_text())
    require(plan["format"] == "uac-android-legal-hosting-2026.14-v1", "Wrong plan")
    if args.apply:
        result = apply(transport, plan, local, pages, args.state)
    else:
        state = json.loads(args.state.read_text())
        require(state["planHash"] == privacy.digest(plan), "State does not belong to plan")
        result = rollback(transport, plan, state, args.state) if args.rollback else verify(transport, plan, state, rollback=args.verify_rollback)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print("Hosting operation unconfirmed. Inspect saved state and verify; do not repeat writes.", file=sys.stderr)
        raise SystemExit(1)
