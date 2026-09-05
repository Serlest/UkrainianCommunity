#!/usr/bin/env python3
"""Read-only metadata/source snapshot. NO deployment/apply mode; cloud requests are GET only."""
import argparse
import datetime
import hashlib
import io
import json
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile

PROJECT = "ukrainiancommunity-dbd5f"
NUMBER = "919042658790"
REGION = "europe-west3"
# Fixed; no user-supplied function selectors.
ALLOWLIST = ("trackAnalyticsEvent", "updateAnalyticsConsent", "updateAnalyticsConsentV2")
API = "https://cloudfunctions.googleapis.com/v2/"

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-dir", required=True)
    parser.add_argument("--account")
    args = parser.parse_args()
    private = Path(args.private_dir).resolve()
    if "Secrets" not in private.parts:
        raise SystemExit("Private snapshot must be inside the git-ignored Secrets directory.")
    private.mkdir(parents=True, mode=0o700, exist_ok=False)
    command = ["gcloud", "auth", "print-access-token"]
    if args.account:
        command.extend(["--account", args.account])
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode:
        raise SystemExit("Could not obtain an access token; no token or CLI output was saved.")
    token = result.stdout.strip()
    headers = {"Authorization": "Bearer " + token, "x-goog-user-project": PROJECT}

    def get(url, binary=False):
        request = urllib.request.Request(url, method="GET", headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                data = response.read()
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Read-only API request failed with HTTP {error.code}") from None
        return data if binary else json.loads(data)

    def save(name, data, binary=False):
        path = private / name
        with path.open("xb") as output:
            path.chmod(0o600)
            output.write(data if binary else json.dumps(data, indent=2).encode())

    functions = []
    page = ""
    while True:
        url = API + f"projects/{PROJECT}/locations/-/functions?pageSize=1000"
        if page:
            url += "&pageToken=" + urllib.parse.quote(page, safe="")
        data = get(url)
        functions.extend(data.get("functions", []))
        page = data.get("nextPageToken")
        if not page:
            break
    save("all-functions-before.json", functions)
    appcheck = get(f"https://firebaseappcheck.googleapis.com/v1/projects/{NUMBER}/services?pageSize=100")
    if appcheck.get("nextPageToken"):
        raise RuntimeError("Unexpected additional App Check services page; stop and review.")
    save("appcheck-before.json", appcheck)
    summaries = []
    for name in ALLOWLIST:
        resource = f"projects/{PROJECT}/locations/{REGION}/functions/{name}"
        function = get(API + resource)
        if function["state"] != "ACTIVE" or function["environment"] != "GEN_2" or function.get("eventTrigger"):
            raise RuntimeError("Allowlisted function is not an ACTIVE GEN_2 HTTP function.")
        if function["buildConfig"]["entryPoint"] != name:
            raise RuntimeError("Entry point mismatch; do not deploy.")
        save(name + "-function.json", function)
        iam = get(API + resource + ":getIamPolicy")
        save(name + "-function-iam.json", iam)
        service = function["serviceConfig"]["service"]
        run = get("https://run.googleapis.com/v2/" + service)
        save(name + "-run.json", run)
        run_iam = get("https://run.googleapis.com/v2/" + service + ":getIamPolicy")
        save(name + "-run-iam.json", run_iam)
        source = function["buildConfig"]["sourceProvenance"]["resolvedStorageSource"]
        url = "https://storage.googleapis.com/storage/v1/b/" + urllib.parse.quote(source["bucket"], safe="")
        url += "/o/" + urllib.parse.quote(source["object"], safe="")
        url += "?alt=media&generation=" + str(source["generation"])
        archive_bytes = get(url, binary=True)
        save(name + "-source-before.zip", archive_bytes, binary=True)
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            lock = json.loads(archive.read("package-lock.json"))
            uuid_versions = sorted({value.get("version") for key, value in lock.get("packages", {}).items()
                                    if key.endswith("node_modules/uuid")})
            selected_hashes = {path: hashlib.sha256(archive.read(path)).hexdigest() for path in
                ["package.json", "package-lock.json", "lib/analytics/analyticsConsent.js", "lib/analytics/trackAnalyticsEvent.js"]}
        build = function["buildConfig"]
        config = function["serviceConfig"]
        summaries.append({"function": name, "state": function["state"], "runtime": build["runtime"],
            "entryPoint": build["entryPoint"], "settingsSHA256": digest(function),
            "serviceConfigSHA256": digest(config), "buildConfigSHA256": digest(build),
            "serviceAccountSHA256": digest(config.get("serviceAccountEmail")),
            "buildServiceAccountSHA256": digest(build.get("serviceAccount")),
            "environmentSHA256": digest(config.get("environmentVariables", {})),
            "buildEnvironmentSHA256": digest(build.get("environmentVariables", {})),
            "secretEnvironmentCount": len(config.get("secretEnvironmentVariables", [])),
            "secretVolumeCount": len(config.get("secretVolumes", [])),
            "vpcConnectorPresent": bool(config.get("vpcConnector")),
            "runTemplateSHA256": digest(run.get("template")), "runIAMSHA256": digest(run_iam),
            "functionIAMSHA256": digest(iam), "sourceFilesSHA256": selected_hashes,
            "sourceZipSHA256": hashlib.sha256(archive_bytes).hexdigest(), "uuidVersions": uuid_versions,
            "analyticsAppCheckEnv": config.get("environmentVariables", {}).get("ENFORCE_ANALYTICS_APP_CHECK", "absent")})
    summary = {"capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "mode": "read-only", "project": PROJECT, "region": REGION, "allowlist": list(ALLOWLIST),
        "functionCount": len(functions), "functions": summaries, "appCheckSHA256": digest(appcheck),
        "deploymentPerformed": False}
    save("sanitized-summary.json", summary)
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
