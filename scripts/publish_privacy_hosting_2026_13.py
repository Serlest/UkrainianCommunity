#!/usr/bin/env python3
"""Replace one Hosting file using the live filemap. Default is read-only planning."""
from __future__ import annotations

import argparse
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.request
from urllib.parse import urlencode
from uuid import uuid4
from zoneinfo import ZoneInfo

import publish_privacy_2026_13 as privacy

SITE = "sites/ukrainiancommunity-dbd5f"
API = "https://firebasehosting.googleapis.com/v1beta1/"
LIVE = SITE + "/channels/live"
SELECTED = "/privacy/index.html"
PUBLIC = "https://ukrainiancommunity-dbd5f.web.app/privacy"
require = privacy.require


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save_new(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as out:
        json.dump(value, out, indent=2)
        out.write("\n")


def journal(path, state, phase, **extra):
    state.update(phase=phase, **extra)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(path)


class Transport:
    def __init__(self, control):
        self.control = privacy.load_module(control, "hosting_control")
        require(self.control.PROJECT == privacy.PROJECT, "Wrong helper project")

    def api(self, method, path, body=None):
        require(path.startswith(SITE + "/"), "Unexpected Hosting API target")
        status, result = self.control.request(API + path, body=body, method=method)
        require(200 <= status < 300, f"Hosting request failed: {method} HTTP {status}; no retry")
        return result

    def upload(self, version, digest, payload):
        validate_version(version)
        require(sha(payload) == digest, "Upload hash differs")
        url = f"https://upload-firebasehosting.googleapis.com/upload/{version}/files/{digest}"
        headers = self.control.headers()
        headers["Content-Type"] = "application/octet-stream"
        request = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(request, timeout=60) as response:
            require(response.status == 200, "Upload not confirmed")

    def public(self):
        # No auth headers go to the public site. Cache-busting is scoped to /privacy.
        request = urllib.request.Request(PUBLIC + "?uac_privacy_readback=" + uuid4().hex,
                                         headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"})
        with urllib.request.urlopen(request, timeout=60) as response:
            require(response.status == 200 and response.url.startswith(PUBLIC), "Unexpected privacy response")
            body = response.read()
            if response.headers.get("Content-Encoding") == "gzip":
                body = gzip.decompress(body)
            return body


def validate_version(name):
    require(re.fullmatch(re.escape(SITE) + r"/versions/[A-Za-z0-9_-]+", name or ""), "Unexpected Hosting version name")


def release_info(release):
    version = release["version"]["name"]
    validate_version(version)
    return {"id": release["name"].rsplit("/", 1)[1], "version": version, "time": release["releaseTime"]}


def current(transport):
    return release_info(transport.api("GET", LIVE)["release"])


def inventory(transport, version):
    validate_version(version)
    metadata = transport.api("GET", version)
    require(metadata["status"] == "FINALIZED", "Version must be finalized")
    files = {}
    token = ""
    seen = set()
    while True:
        query = urlencode({"pageSize": 1000, "status": "ACTIVE", **({"pageToken": token} if token else {})})
        page = transport.api("GET", version + "/files?" + query)
        for item in page.get("files", []):
            require(item["status"] == "ACTIVE" and item["path"] not in files, "Unexpected/duplicate Hosting file")
            require(re.fullmatch(r"[0-9a-f]{64}", item["hash"]), "Unexpected Hosting file hash")
            files[item["path"]] = item["hash"]
        token = page.get("nextPageToken", "")
        if not token:
            break
        require(token not in seen and len(seen) < 100, "Unexpected file pagination")
        seen.add(token)
    require(len(files) == int(metadata["fileCount"]) and SELECTED in files, "Incomplete Hosting filemap")
    return {"config": metadata["config"], "files": dict(sorted(files.items()))}


def payload():
    legal = privacy.local_payload()  # Checks generated website + both canonical locales.
    html = (privacy.ROOT / "website/privacy/index.html").read_bytes()
    # The exact compressed bytes are reused for hashing and upload.
    compressed = gzip.compress(html, compresslevel=9, mtime=0)
    return html, compressed, {"htmlHash": sha(html), "gzipHash": sha(compressed),
                              "effectiveDate": legal["effectiveDate"], "legalInputs": legal["inputHashes"]}


def prepare(transport, local):
    before = current(transport)
    old = inventory(transport, before["version"])
    old_html = transport.public()
    require(b'Version 2026.12' in old_html and 'Версія 2026.12'.encode() in old_html, "Live privacy is not bilingual 2026.12")
    require(current(transport) == before, "Live release changed while reading inventory")
    after = {**old["files"], SELECTED: local["gzipHash"]}
    require([path for path in after if after[path] != old["files"][path]] == [SELECTED], "Expected exactly one changed path")
    return {"format": "uac-privacy-hosting-2026.13-v1", "site": SITE, "beforeRelease": before,
            "config": old["config"], "beforeFiles": old["files"], "afterFiles": after,
            "beforeHtmlHash": sha(old_html), "local": local, "changedPaths": [SELECTED]}


def guard(transport, plan):
    require(current(transport) == plan["beforeRelease"], "Current release changed; stop without releasing")
    require(inventory(transport, plan["beforeRelease"]["version"]) == {"config": plan["config"], "files": plan["beforeFiles"]}, "Baseline config/files changed")


def verify(transport, plan, state, rollback=False):
    live = current(transport)
    expected_version = plan["beforeRelease"]["version"] if rollback else state["candidateVersion"]
    require(live["version"] == expected_version, "Expected version is not live; no publication proof")
    expected_files = plan["beforeFiles"] if rollback else plan["afterFiles"]
    require(inventory(transport, expected_version) == {"config": plan["config"], "files": expected_files}, "Live config/filemap differs")
    html = transport.public()
    require(sha(html) == (plan["beforeHtmlHash"] if rollback else plan["local"]["htmlHash"]), "Live privacy HTML hash differs; use read-only verify later")
    version = "2026.12" if rollback else "2026.13"
    require(f"Version {version}".encode() in html and f"Версія {version}".encode() in html, "Missing locale version markers")
    require(current(transport) == live, "Release changed during read-back")
    return {"release": live, "htmlHash": sha(html), "fileCount": len(expected_files),
            "unchangedOtherFiles": len(expected_files) - 1, "locales": ["de", "uk"], "rollback": rollback}


def apply(transport, plan, local, compressed, state_path):
    require(plan["site"] == SITE and plan["local"] == local, "Plan/local mismatch")
    require(datetime.now(ZoneInfo("Europe/Vienna")).date().isoformat() == local["effectiveDate"], "Reconcile effective date before publication")
    require(prepare(transport, local) == plan, "Reviewed plan is stale")
    state = {"planHash": privacy.digest(plan), "phase": "reserved"}
    save_new(state_path, state)  # Existing attempts cannot be silently repeated.
    journal(state_path, state, "create-intent")
    created = transport.api("POST", SITE + "/versions", {"config": plan["config"], "labels": {"deployment-tool": "privacy-scoped-publisher"}})
    version = created["name"]
    validate_version(version)
    require(version != plan["beforeRelease"]["version"], "Unexpected reused version")
    journal(state_path, state, "created", candidateVersion=version)
    pairs = sorted(plan["afterFiles"].items())
    required = set()
    for offset in range(0, len(pairs), 1000):
        journal(state_path, state, "populate-intent", populateOffset=offset)
        response = transport.api("POST", version + ":populateFiles", {"files": dict(pairs[offset:offset + 1000])})
        required.update(response.get("uploadRequiredHashes", []))
        if response.get("uploadRequiredHashes"):
            require(response.get("uploadUrl") == f"https://upload-firebasehosting.googleapis.com/upload/{version}/files", "Unexpected upload target")
    require(required <= {local["gzipHash"]}, "Hosting requested unrelated payloads; stop before release")
    if required:
        journal(state_path, state, "upload-intent")
        transport.upload(version, local["gzipHash"], compressed)
    journal(state_path, state, "finalize-intent")
    transport.api("PATCH", version + "?updateMask=status", {"status": "FINALIZED"})
    require(inventory(transport, version) == {"config": plan["config"], "files": plan["afterFiles"]}, "Candidate is not the exact scoped replacement")
    guard(transport, plan)
    # Hosting releases.create has no CAS/etag parameter. This last read narrows,
    # but cannot eliminate, a race. Coordinator must hold an exclusive deploy window.
    require(current(transport) == plan["beforeRelease"], "Live release changed before publish")
    journal(state_path, state, "release-intent")
    try:
        transport.api("POST", LIVE + "/releases?" + urlencode({"versionName": version}), {"message": "Privacy 2026.13: only /privacy/index.html"})
    except Exception:
        journal(state_path, state, "release-response-uncertain")
        raise ValueError("Release response uncertain; use --verify with the same plan/state. Never repeat apply.") from None
    result = verify(transport, plan, state)
    journal(state_path, state, "verified", publishedRelease=result["release"])
    return result


def rollback(transport, plan, state, state_path):
    require(state["phase"] == "verified" and current(transport) == state["publishedRelease"], "Rollback requires the exact verified publication still live")
    require(inventory(transport, plan["beforeRelease"]["version"]) == {"config": plan["config"], "files": plan["beforeFiles"]}, "Original rollback version changed/unavailable")
    require(current(transport) == state["publishedRelease"], "Release changed before rollback")
    journal(state_path, state, "rollback-intent")
    try:
        transport.api("POST", LIVE + "/releases?" + urlencode({"versionName": plan["beforeRelease"]["version"]}), {"message": "Rollback scoped privacy 2026.13 Hosting release"})
    except Exception:
        raise ValueError("Rollback response uncertain; use --verify-rollback, never repeat rollback blindly") from None
    result = verify(transport, plan, state, rollback=True)
    journal(state_path, state, "rollback-verified", rollbackRelease=result["release"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    for mode in ("apply", "verify", "rollback", "verify-rollback"):
        modes.add_argument("--" + mode, action="store_true")
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--state", type=Path, help="Required for apply/verify/rollback; never reuse for another attempt")
    parser.add_argument("--control", type=Path, default=privacy.CONTROL)
    args = parser.parse_args()
    transport = Transport(args.control)
    if not any((args.apply, args.verify, args.rollback, args.verify_rollback)):
        _, _, local = payload()
        plan = prepare(transport, local)
        save_new(args.plan, plan)
        print(json.dumps({"result": "dry-run-no-writes", "plan": str(args.plan), "beforeRelease": plan["beforeRelease"], "changedPaths": [SELECTED], "preservedFiles": len(plan["beforeFiles"]) - 1, "local": local}, indent=2))
        return
    require(args.state is not None, "--state is required")
    plan = json.loads(args.plan.read_text())
    require(plan["format"] == "uac-privacy-hosting-2026.13-v1" and plan["site"] == SITE, "Wrong plan")
    if args.apply:
        _, compressed, local = payload()
        result = apply(transport, plan, local, compressed, args.state)
    else:
        state = json.loads(args.state.read_text())
        require(state["planHash"] == privacy.digest(plan), "State does not belong to plan")
        if args.rollback:
            result = rollback(transport, plan, state, args.state)
        else:
            require(not args.verify_rollback or state["phase"] in ("rollback-intent", "rollback-verified"), "No rollback attempt in this state")
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
        print("Hosting operation unconfirmed. Inspect saved phase and use read-only verification; do not repeat writes. Error details suppressed.", file=sys.stderr)
        sys.exit(1)
