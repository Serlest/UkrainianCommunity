#!/usr/bin/env python3
"""Read-only release check: deployed analytics consumers must accept released consents.

Requires the existing gcloud session. No credentials, archive environment files,
user profiles or analytics events are printed or changed.
"""
from __future__ import annotations
import concurrent.futures
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
FUNCTIONS = ("trackAnalyticsEvent", "updateAnalyticsConsent", "updateAnalyticsConsentV2")
SOURCE = "src/analytics/analyticsConsent.ts"

def consent_contracts(source: str) -> set[str]:
    match = re.search(r"const compatibleConsentVersions\s*=\s*new Set\(\[(.*?)\]\)", source, re.S)
    if not match:
        raise ValueError("Analytics compatibility contract is missing")
    contracts = set(re.findall(r'"([0-9.]+\|[0-9.-]+)"', match.group(1)))
    if not contracts:
        raise ValueError("Analytics compatibility contract is empty")
    return contracts

def inspect_deployed(name: str, expected: set[str]) -> dict:
    metadata = json.loads(subprocess.check_output([
        "gcloud", "functions", "describe", name, "--gen2", "--region=europe-west3",
        "--project=ukrainiancommunity-dbd5f", "--format=json"], stderr=subprocess.PIPE, text=True))
    source = metadata["buildConfig"]["source"]["storageSource"]
    with tempfile.TemporaryDirectory(prefix="uac-analytics-contract-") as folder:
        archive = Path(folder) / "source.zip"
        subprocess.run(["gcloud", "storage", "cp", f"gs://{source['bucket']}/{source['object']}", str(archive)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with zipfile.ZipFile(archive) as package:
            actual = consent_contracts(package.read(SOURCE).decode())
    return {"function": name, "state": metadata.get("state"),
        "revision": metadata.get("serviceConfig", {}).get("revision"),
        "missingContracts": sorted(expected - actual)}

def main() -> int:
    expected = consent_contracts((ROOT / "functions" / SOURCE).read_text())
    auth = (ROOT / "UkrainianCommunity/Services/Auth/AuthService.swift").read_text()
    current = re.search(r'currentPrivacyVersion = "([0-9.]+)"', auth)
    if not current or not any(c.startswith(current.group(1) + "|") for c in expected):
        print("FAILED: current iOS privacy version is absent from the analytics contract")
        return 1
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            results = list(executor.map(lambda name: inspect_deployed(name, expected), FUNCTIONS))
    except (subprocess.CalledProcessError, KeyError, ValueError, OSError, zipfile.BadZipFile):
        print("FAILED: deployed analytics contract could not be verified; check gcloud access")
        return 1
    print(json.dumps(results, indent=2))
    return int(any(row["state"] != "ACTIVE" or row["missingContracts"] for row in results))

if __name__ == "__main__":
    raise SystemExit(main())
