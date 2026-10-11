#!/usr/bin/env python3
"""Publish only the two legal Hosting pages using the current live file map."""
from __future__ import annotations

import argparse
from datetime import datetime
import gzip
import json
from pathlib import Path
import sys
import urllib.request
from urllib.parse import urlencode
from uuid import uuid4
from zoneinfo import ZoneInfo

import publish_privacy_hosting_2026_13 as hosting
import publish_legal_2026_10_11 as legal

KINDS = ("terms", "privacy")
PATHS = {kind: f"/{kind}/index.html" for kind in KINDS}
SITE_URL = "https://ukrainiancommunity-dbd5f.web.app"
require = legal.require


def public(kind):
    url = f"{SITE_URL}/{kind}"
    request = urllib.request.Request(
        f"{url}?uac_legal_readback={uuid4().hex}",
        headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        require(response.status == 200 and response.url.startswith(url), "Unexpected public legal response")
        body = response.read()
        return gzip.decompress(body) if response.headers.get("Content-Encoding") == "gzip" else body


def local_payload():
    documents = legal.payload()
    pages = {}
    for kind in KINDS:
        html = (legal.ROOT / f"website/{kind}/index.html").read_bytes()
        compressed = gzip.compress(html, compresslevel=9, mtime=0)
        pages[kind] = {
            "htmlHash": hosting.sha(html), "gzipHash": hosting.sha(compressed),
            "inputHashes": documents[kind]["inputHashes"],
            "compressed": compressed,
        }
    return pages


def compact(pages):
    return {kind: {key: value for key, value in pages[kind].items() if key != "compressed"} for kind in KINDS}


def prepare(transport, pages):
    before = hosting.current(transport)
    inventory = hosting.inventory(transport, before["version"])
    require(all(path in inventory["files"] for path in PATHS.values()), "Live site lacks a selected legal page")
    old_pages = {kind: public(kind) for kind in KINDS}
    for kind, (previous, _) in legal.TARGETS.items():
        require(f"Version {previous}".encode() in old_pages[kind]
                and f"Версія {previous}".encode() in old_pages[kind], f"Unexpected live {kind} version")
    require(hosting.current(transport) == before, "Live release changed while planning")
    after = {**inventory["files"], **{PATHS[kind]: pages[kind]["gzipHash"] for kind in KINDS}}
    require(sorted(path for path in after if after[path] != inventory["files"][path]) == sorted(PATHS.values()),
            "Expected exactly two changed files")
    return {
        "format": "uac-legal-hosting-2026-10-11-v1", "site": hosting.SITE,
        "beforeRelease": before, "config": inventory["config"],
        "beforeFiles": inventory["files"], "afterFiles": after,
        "beforeHtmlHashes": {kind: hosting.sha(old_pages[kind]) for kind in KINDS},
        "local": compact(pages), "changedPaths": sorted(PATHS.values()),
    }


def guard(transport, plan):
    require(hosting.current(transport) == plan["beforeRelease"], "Live release changed")
    require(hosting.inventory(transport, plan["beforeRelease"]["version"])
            == {"config": plan["config"], "files": plan["beforeFiles"]}, "Live file map changed")


def verify(transport, plan, state):
    live = hosting.current(transport)
    require(live["version"] == state["candidateVersion"], "Candidate is not live")
    require(hosting.inventory(transport, live["version"])
            == {"config": plan["config"], "files": plan["afterFiles"]}, "Live file map differs")
    hashes = {}
    for kind in KINDS:
        html = public(kind)
        hashes[kind] = hosting.sha(html)
        require(hashes[kind] == plan["local"][kind]["htmlHash"], f"Public {kind} HTML hash differs")
        version = legal.TARGETS[kind][1]
        require(f"Version {version}".encode() in html and f"Версія {version}".encode() in html,
                f"Missing {kind} locale version marker")
    require(hosting.current(transport) == live, "Release changed during read-back")
    return {"release": live, "htmlHashes": hashes,
            "unchangedOtherFiles": len(plan["beforeFiles"]) - len(KINDS)}


def apply(transport, plan, pages, state_path):
    require(plan["format"] == "uac-legal-hosting-2026-10-11-v1"
            and plan["site"] == hosting.SITE and plan["local"] == compact(pages), "Plan/local mismatch")
    require(datetime.now(ZoneInfo("Europe/Vienna")).date().isoformat() == "2026-10-11", "Publication date changed")
    require(prepare(transport, pages) == plan, "Reviewed plan is stale")
    state = {"planHash": legal.digest(plan), "phase": "reserved"}
    hosting.save_new(state_path, state)
    hosting.journal(state_path, state, "create-intent")
    created = transport.api("POST", hosting.SITE + "/versions",
                            {"config": plan["config"], "labels": {"deployment-tool": "legal-scoped-publisher"}})
    version = created["name"]
    hosting.validate_version(version)
    hosting.journal(state_path, state, "created", candidateVersion=version)
    pairs = sorted(plan["afterFiles"].items())
    required = set()
    for offset in range(0, len(pairs), 1000):
        hosting.journal(state_path, state, "populate-intent", populateOffset=offset)
        response = transport.api("POST", version + ":populateFiles", {"files": dict(pairs[offset:offset + 1000])})
        required.update(response.get("uploadRequiredHashes", []))
        if response.get("uploadRequiredHashes"):
            require(response.get("uploadUrl") == f"https://upload-firebasehosting.googleapis.com/upload/{version}/files",
                    "Unexpected upload target")
    uploads = {pages[kind]["gzipHash"]: pages[kind]["compressed"] for kind in KINDS}
    require(required <= set(uploads), "Hosting requested unrelated payloads")
    for file_hash in required:
        hosting.journal(state_path, state, "upload-intent", uploadHash=file_hash)
        transport.upload(version, file_hash, uploads[file_hash])
    hosting.journal(state_path, state, "finalize-intent")
    transport.api("PATCH", version + "?updateMask=status", {"status": "FINALIZED"})
    require(hosting.inventory(transport, version) == {"config": plan["config"], "files": plan["afterFiles"]},
            "Candidate differs from scoped file map")
    guard(transport, plan)
    hosting.journal(state_path, state, "release-intent")
    try:
        transport.api("POST", hosting.LIVE + "/releases?" + urlencode({"versionName": version}),
                      {"message": "Terms 2026.11 and Privacy 2026.15: two legal pages only"})
    except Exception:
        hosting.journal(state_path, state, "release-response-uncertain")
        raise ValueError("Release response uncertain; use --verify, never repeat apply.") from None
    result = verify(transport, plan, state)
    hosting.journal(state_path, state, "verified", publishedRelease=result["release"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--control", type=Path, default=legal.common.CONTROL)
    args = parser.parse_args()
    transport = hosting.Transport(args.control)
    if not args.apply and not args.verify:
        plan = prepare(transport, local_payload())
        hosting.save_new(args.plan, plan)
        print(json.dumps({"result": "dry-run-no-writes", "plan": str(args.plan),
                          "changedPaths": plan["changedPaths"],
                          "unchangedOtherFiles": len(plan["beforeFiles"]) - 2}, indent=2))
        return
    require(args.state is not None, "--state is required")
    plan = json.loads(args.plan.read_text())
    if args.apply:
        result = apply(transport, plan, local_payload(), args.state)
    else:
        state = json.loads(args.state.read_text())
        require(state["planHash"] == legal.digest(plan), "State does not belong to plan")
        result = verify(transport, plan, state)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("Hosting publication unconfirmed; inspect read-only without repeating writes.", file=sys.stderr)
        sys.exit(1)
