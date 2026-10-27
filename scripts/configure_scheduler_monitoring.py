#!/usr/bin/env python3
"""Add missing-success coverage for enabled UAC maintenance jobs.

Dry run by default. Only the existing policy's conditions are patched: channels,
notification preferences and all prior conditions remain intact. No job is run,
rescheduled or enabled by this script.
"""
from __future__ import annotations
import argparse
import copy
import json
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

PROJECT = "ukrainiancommunity-dbd5f"
POLICY = f"projects/{PROJECT}/alertPolicies/10611206044681368285"
ADDITIONAL_GROUPS = [
    ("Every-five-minute jobs: no success for 20 minutes", ["rollupBannerMeasurementReports"], "1200s", "120s"),
    ("Daily maintenance: no success for 25 hours", ["migrateLegacyContentMedia", "cleanupStaleFeaturedBannerOrphans", "cleanupExpiredData", "cleanupUnverifiedAccounts", "cleanupStaleContentMediaOrphans", "cleanupAnnouncements"], "90000s", "1800s"),
]

def desired_conditions(policy: dict, jobs: list[dict]) -> list[dict]:
    enabled = {j["name"].split("/")[-1].removeprefix("firebase-schedule-").removesuffix("-europe-west3") for j in jobs if j.get("state") == "ENABLED"}
    conditions = copy.deepcopy(policy.get("conditions", []))
    for title, candidates, window, duration in ADDITIONAL_GROUPS:
        services = sorted(name.lower() for name in candidates if name in enabled)
        # A deliberately paused job must not trigger missing-success warnings.
        existing = next((c for c in conditions if c.get("displayName") == title), None)
        if not services:
            if existing: conditions.remove(existing)
            continue
        condition = {"displayName": title, "conditionThreshold": {
            "filter": 'metric.type="run.googleapis.com/request_count" AND resource.type="cloud_run_revision" AND metric.labels.response_code_class="2xx" AND resource.labels.service_name = one_of(' + ",".join(json.dumps(s) for s in services) + ")",
            "comparison": "COMPARISON_LT", "thresholdValue": 1, "duration": duration,
            "trigger": {"count": 1}, "evaluationMissingData": "EVALUATION_MISSING_DATA_ACTIVE",
            "aggregations": [{"alignmentPeriod": window, "perSeriesAligner": "ALIGN_SUM", "crossSeriesReducer": "REDUCE_SUM", "groupByFields": ["resource.label.service_name"]}],
        }}
        if existing:
            if "name" in existing: condition["name"] = existing["name"]
            conditions[conditions.index(existing)] = condition
        else: conditions.append(condition)
    if len(conditions) > 6:
        raise ValueError("Policy would exceed the six-condition limit; review rather than dropping existing protections.")
    return conditions

def semantic(conditions: list[dict]) -> list[dict]:
    return [{k:v for k,v in c.items() if k != "name"} for c in conditions]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    url = "https://monitoring.googleapis.com/v3/" + POLICY
    def request(uri, body=None):
        req = urllib.request.Request(uri, data=json.dumps(body).encode() if body is not None else None,
            headers=headers, method="PATCH" if body is not None else "GET")
        try:
            with urllib.request.urlopen(req, timeout=45) as response: return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(error.read().decode()) from None
    before = request(url)
    jobs = json.loads(subprocess.check_output(["gcloud", "scheduler", "jobs", "list", "--location=europe-west3", "--project=" + PROJECT, "--format=json"], text=True))
    wanted = desired_conditions(before, jobs)
    (args.output/"monitoring-before.json").write_text(json.dumps(before, indent=2))
    (args.output/"monitoring-desired.json").write_text(json.dumps(wanted, indent=2))
    if args.apply and semantic(wanted) != semantic(before["conditions"]):
        request(url + "?updateMask=conditions", {"name": POLICY, "conditions": wanted})
    after = request(url)
    if args.apply:
        assert semantic(after["conditions"]) == semantic(wanted), "Saved conditions differ"
        for field in ["enabled", "notificationChannels", "alertStrategy", "combiner"]:
            assert after.get(field) == before.get(field), "Unrelated field changed: " + field
    (args.output/"monitoring-readback.json").write_text(json.dumps(after, indent=2))
    print(json.dumps({"applied": args.apply, "conditions": len(wanted), "channelsPreserved": after.get("notificationChannels") == before.get("notificationChannels"), "pausedJobsChanged": False}))

if __name__ == "__main__": main()
