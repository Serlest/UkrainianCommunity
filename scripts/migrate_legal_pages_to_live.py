#!/usr/bin/env python3
"""Move only the three legal Hosting routes to the published-document function.

Default mode writes a reviewable plan. Apply requires that plan and a fresh
state path. Other live Hosting files and the existing DSA rewrite are retained.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import urllib.request
from urllib.parse import urlencode
from uuid import uuid4

import publish_privacy_hosting_2026_13 as hosting

KINDS = {"terms": "2026.13", "privacy": "2026.19", "organization-rules": "2026.10"}
REMOVED = {f"/{kind}/index.html" for kind in KINDS}
PUBLIC = "https://ukrainiancommunity-dbd5f.web.app"
FUNCTION = "https://europe-west3-ukrainiancommunity-dbd5f.cloudfunctions.net/serveLegalDocument"
SERVICE = "servelegaldocument"
FORMAT = "uac-legal-routes-scoped-v1"
require = hosting.require


def sha(value):
    return hashlib.sha256(value).hexdigest()


def save_new(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def journal(path, value, phase, **changes):
    value.update(phase=phase, **changes)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def page(base, kind, expected_version=None):
    request = urllib.request.Request(
        f"{base}/{kind}?uac_legal_probe={uuid4().hex}",
        headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        require(response.status == 200, f"{kind} returned HTTP {response.status}")
        data = response.read()
        if expected_version:
            require(f"Version {expected_version}".encode() in data, f"{kind} German version mismatch")
            require(f"Версія {expected_version}".encode() in data, f"{kind} Ukrainian version mismatch")
        return {"hash": sha(data), "cacheControl": response.headers.get("Cache-Control", "")}


def direct_pages():
    pages = {kind: page(FUNCTION, kind, KINDS[kind]) for kind in KINDS}
    require(all("no-store" in result["cacheControl"] for result in pages.values()),
            "Function must disable caching")
    return pages


def files_for(transport, version):
    metadata = transport.api("GET", version)
    require(metadata["status"] == "FINALIZED", "Hosting version is not finalized")
    files = {}
    token = ""
    while True:
        query = urlencode({"pageSize": 1000, "status": "ACTIVE", **({"pageToken": token} if token else {})})
        batch = transport.api("GET", version + "/files?" + query)
        for item in batch.get("files", []):
            path = item["path"]
            require(path not in files and item["status"] == "ACTIVE", "Duplicate/inactive Hosting file")
            files[path] = item["hash"]
        token = batch.get("nextPageToken", "")
        if not token:
            break
    require(len(files) == int(metadata.get("fileCount", len(files))), "Incomplete Hosting file inventory")
    return {"config": metadata["config"], "files": dict(sorted(files.items()))}


def candidate_config(old):
    config = json.loads(json.dumps(old))
    existing = config.get("rewrites", [])
    require(len(existing) == 1 and existing[0].get("glob") == "/api/dsa",
            "Hosting rewrites changed; review migration before proceeding")
    routes = []
    for kind in KINDS:
        for glob in (f"/{kind}", f"/{kind}/**"):
            routes.append({"glob": glob, "run": {"serviceId": SERVICE, "region": "europe-west3"}})
    config["rewrites"] = routes + existing
    return config


def prepare(transport):
    before = hosting.current(transport)
    baseline = files_for(transport, before["version"])
    require(REMOVED <= baseline["files"].keys(), "Expected three current static legal files")
    old_pages = {kind: page(PUBLIC, kind) for kind in KINDS}
    function_pages = direct_pages()
    require(hosting.current(transport) == before, "Live Hosting release changed during planning")
    after_files = {path: digest for path, digest in baseline["files"].items() if path not in REMOVED}
    return {
        "format": FORMAT, "site": hosting.SITE, "beforeRelease": before,
        "beforeConfig": baseline["config"], "afterConfig": candidate_config(baseline["config"]),
        "beforeFiles": baseline["files"], "afterFiles": after_files,
        "beforePages": old_pages, "functionPages": function_pages,
        "removed": sorted(REMOVED), "preservedCount": len(after_files),
    }


def verify(transport, plan, state, rollback=False):
    live = hosting.current(transport)
    expected = plan["beforeRelease"]["version"] if rollback else state["candidateVersion"]
    require(live["version"] == expected, "Unexpected live Hosting version")
    inventory = files_for(transport, expected)
    require(inventory["config"] == plan["beforeConfig" if rollback else "afterConfig"],
            "Live Hosting config differs")
    require(inventory["files"] == plan["beforeFiles" if rollback else "afterFiles"],
            "Live Hosting files differ")
    expected_pages = plan["beforePages" if rollback else "functionPages"]
    for kind in KINDS:
        result = page(PUBLIC, kind, None if rollback else KINDS[kind])
        require(result["hash"] == expected_pages[kind]["hash"], f"{kind} page differs")
        if not rollback:
            require("no-store" in result["cacheControl"], f"{kind} page still cacheable")
    require(hosting.current(transport) == live, "Live release changed during verification")
    return {"release": live, "legalRoutes": list(KINDS), "preservedFiles": len(inventory["files"]),
            "rollback": rollback}


def apply(transport, plan, state_path):
    require(prepare(transport) == plan, "Plan is stale; regenerate after reviewing changes")
    state = {"planHash": hosting.privacy.digest(plan), "phase": "reserved"}
    save_new(state_path, state)
    journal(state_path, state, "create-intent")
    created = transport.api("POST", hosting.SITE + "/versions", {
        "config": plan["afterConfig"], "labels": {"deployment-tool": "legal-routes-scoped"},
    })
    version = created["name"]
    hosting.validate_version(version)
    journal(state_path, state, "created", candidateVersion=version)
    pairs = sorted(plan["afterFiles"].items())
    for offset in range(0, len(pairs), 1000):
        journal(state_path, state, "populate-intent", populateOffset=offset)
        response = transport.api("POST", version + ":populateFiles", {
            "files": dict(pairs[offset:offset + 1000]),
        })
        require(not response.get("uploadRequiredHashes"), "Preserved Hosting blob unavailable")
    journal(state_path, state, "finalize-intent")
    transport.api("PATCH", version + "?updateMask=status", {"status": "FINALIZED"})
    require(files_for(transport, version) == {"config": plan["afterConfig"], "files": plan["afterFiles"]},
            "Candidate does not match scoped plan")
    require(hosting.current(transport) == plan["beforeRelease"], "Live release changed before activation")
    require(direct_pages() == plan["functionPages"], "Legal function changed before activation")
    journal(state_path, state, "release-intent")
    try:
        transport.api("POST", hosting.LIVE + "/releases?" + urlencode({"versionName": version}),
                      {"message": "Dynamic legal pages; preserve all other live Hosting files"})
    except Exception:
        journal(state_path, state, "release-response-uncertain")
        raise ValueError("Release response uncertain; inspect state and use --verify. Do not repeat --apply.") from None
    result = verify(transport, plan, state)
    journal(state_path, state, "verified", publishedRelease=result["release"])
    return result


def rollback(transport, plan, state, state_path):
    require(state["phase"] == "verified" and hosting.current(transport) == state["publishedRelease"],
            "Rollback requires this exact release still live")
    journal(state_path, state, "rollback-intent")
    try:
        transport.api("POST", hosting.LIVE + "/releases?" + urlencode({"versionName": plan["beforeRelease"]["version"]}),
                      {"message": "Rollback dynamic legal pages"})
    except Exception:
        raise ValueError("Rollback response uncertain; use --verify-rollback.") from None
    result = verify(transport, plan, state, rollback=True)
    journal(state_path, state, "rollback-verified", rollbackRelease=result["release"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    for name in ("apply", "verify", "rollback", "verify-rollback"):
        action.add_argument("--" + name, action="store_true")
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--state", type=Path)
    args = parser.parse_args()
    transport = hosting.Transport(hosting.privacy.CONTROL)
    if not any((args.apply, args.verify, args.rollback, args.verify_rollback)):
        plan = prepare(transport)
        save_new(args.plan, plan)
        print(json.dumps({"result": "dry-run-no-writes", "plan": str(args.plan),
                          "beforeRelease": plan["beforeRelease"], "removed": plan["removed"],
                          "preservedFiles": plan["preservedCount"]}, indent=2))
        return
    require(args.state is not None, "--state required")
    plan = json.loads(args.plan.read_text())
    require(plan.get("format") == FORMAT and plan.get("site") == hosting.SITE, "Wrong plan")
    if args.apply:
        result = apply(transport, plan, args.state)
    else:
        state = json.loads(args.state.read_text())
        require(state["planHash"] == hosting.privacy.digest(plan), "State/plan mismatch")
        if args.rollback:
            result = rollback(transport, plan, state, args.state)
        else:
            require("candidateVersion" in state, "Candidate version not recorded")
            result = verify(transport, plan, state, rollback=args.verify_rollback)
            journal(args.state, state, "rollback-verified" if args.verify_rollback else "verified",
                    **({"rollbackRelease": result["release"]} if args.verify_rollback else {"publishedRelease": result["release"]}))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("Hosting state unconfirmed. Inspect saved phase and use --verify; do not repeat a write.", file=sys.stderr)
        sys.exit(1)
