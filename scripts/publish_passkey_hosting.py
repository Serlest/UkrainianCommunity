#!/usr/bin/env python3
"""Publish only the AASA association and updated privacy page, preserving every live file."""

import argparse
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path
import sys
import urllib.request
from uuid import uuid4
from urllib.parse import urlencode

import publish_privacy_hosting_2026_13 as hosting
import publish_privacy_2026_13 as legal_control

ROOT = Path(__file__).resolve().parent.parent
FILES = {
    "/.well-known/apple-app-site-association": ROOT / "website/.well-known/apple-app-site-association",
    "/privacy/index.html": ROOT / "website/privacy/index.html",
}
FORMAT = "uac-passkey-hosting-v1"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def public(path):
    url = "https://ukrainiancommunity-dbd5f.web.app" + path
    request = urllib.request.Request(url + "?verify=" + uuid4().hex,
                                     headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=60) as response:
        require(response.status == 200, "Public read-back failed")
        data = response.read()
        return gzip.decompress(data) if response.headers.get("Content-Encoding") == "gzip" else data


def inputs():
    result = {}
    for path, local in FILES.items():
        raw = local.read_bytes()
        compressed = gzip.compress(raw, compresslevel=9, mtime=0)
        result[path] = {"raw": raw, "compressed": compressed,
                        "rawHash": sha(raw), "hash": sha(compressed)}
    association = json.loads(FILES[
        "/.well-known/apple-app-site-association"].read_text())
    require("438S639937.at.serlest.UkrainianCommunity" in
            association.get("webcredentials", {}).get("apps", []), "Wrong webcredentials app ID")
    require(b"Version 2026.18" in result["/privacy/index.html"]["raw"], "Wrong privacy version")
    return result


def target_config(previous):
    config = deepcopy(previous)
    headers = config.setdefault("headers", [])
    headers.insert(0, {"glob": "/.well-known/apple-app-site-association",
                       "headers": {"Content-Type": "application/json",
                                   "Cache-Control": "public, max-age=3600"}})
    return config


def prepare(transport, local):
    before = hosting.current(transport)
    inventory = hosting.inventory(transport, before["version"])
    require("/.well-known/apple-app-site-association" not in inventory["files"],
            "AASA is already deployed; inspect live state")
    require("/privacy/index.html" in inventory["files"], "Live privacy page missing")
    old_privacy = public("/privacy")
    require(b"Version 2026.17" in old_privacy, "Unexpected live privacy version")
    after_files = {**inventory["files"], **{path: item["hash"] for path, item in local.items()}}
    require(hosting.current(transport) == before, "Live release changed while planning")
    return {"format": FORMAT, "site": hosting.SITE, "beforeRelease": before,
            "beforeConfig": inventory["config"], "afterConfig": target_config(inventory["config"]),
            "beforeFiles": inventory["files"], "afterFiles": after_files,
            "inputHashes": {path: item["rawHash"] for path, item in local.items()},
            "oldPrivacyHash": sha(old_privacy), "changedPaths": sorted(FILES)}


def verify(transport, plan):
    live = hosting.current(transport)
    inventory = hosting.inventory(transport, live["version"])
    require(inventory == {"config": plan["afterConfig"], "files": plan["afterFiles"]},
            "Live Hosting inventory differs from the scoped plan")
    for path, expected in plan["inputHashes"].items():
        require(sha(public("/privacy" if path == "/privacy/index.html" else path)) == expected,
                f"Public read-back differs: {path}")
    return {"release": live, "changedPaths": plan["changedPaths"],
            "preservedFiles": len(plan["beforeFiles"]) - 1}


def apply(transport, plan, local):
    require(plan["format"] == FORMAT and plan["site"] == hosting.SITE, "Wrong plan")
    require(prepare(transport, local) == plan, "Plan is stale; no write attempted")
    created = transport.api("POST", hosting.SITE + "/versions",
                            {"config": plan["afterConfig"],
                             "labels": {"deployment-tool": "uac-passkey-scoped-publisher"}})
    version = created["name"]
    hosting.validate_version(version)
    pairs = sorted(plan["afterFiles"].items())
    required = set()
    for offset in range(0, len(pairs), 1000):
        page = transport.api("POST", version + ":populateFiles",
                             {"files": dict(pairs[offset:offset + 1000])})
        required.update(page.get("uploadRequiredHashes", []))
    uploads = {item["hash"]: item["compressed"] for item in local.values()}
    require(required <= set(uploads), "Hosting requested an unrelated file")
    for digest in required:
        transport.upload(version, digest, uploads[digest])
    transport.api("PATCH", version + "?updateMask=status", {"status": "FINALIZED"})
    require(hosting.inventory(transport, version)
            == {"config": plan["afterConfig"], "files": plan["afterFiles"]},
            "Candidate differs from the scoped plan")
    require(hosting.current(transport) == plan["beforeRelease"], "Live release changed")
    try:
        transport.api("POST", hosting.LIVE + "/releases?" + urlencode({"versionName": version}),
                      {"message": "Passkey AASA and Privacy 2026.18; preserve other files"})
    except Exception:
        raise ValueError("Release response uncertain; inspect live read-back before retrying") from None
    return verify(transport, plan)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--control", type=Path, default=legal_control.CONTROL)
    args = parser.parse_args()
    transport = hosting.Transport(args.control)
    local = inputs()
    if not args.apply and not args.verify:
        plan = prepare(transport, local)
        hosting.save_new(args.plan, plan)
        print(json.dumps({"result": "dry-run-no-writes", "changedPaths": plan["changedPaths"],
                          "preservedFiles": len(plan["beforeFiles"]) - 1, "plan": str(args.plan)}, indent=2))
        return
    plan = json.loads(args.plan.read_text())
    result = verify(transport, plan) if args.verify else apply(transport, plan, local)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
