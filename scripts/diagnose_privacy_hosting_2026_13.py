#!/usr/bin/env python3
"""GET-only diagnosis of an existing candidate; never updates remote or journal state."""
import argparse
import json
from pathlib import Path
import traceback
import urllib.error

import publish_privacy_hosting_2026_13 as hosting


class SafeHTTPError(Exception):
    def __init__(self, status):
        self.status = status


class ReadOnlyTransport(hosting.Transport):
    def api(self, method, path, body=None):
        if method != "GET" or body is not None:
            raise ValueError("Diagnostic transport forbids mutations")
        hosting.require(path.startswith(hosting.SITE + "/"), "Wrong Hosting site")
        status, result = self.control.request(hosting.API + path, method="GET")
        if not 200 <= status < 300:
            raise SafeHTTPError(status)
        return result

    def upload(self, *args):
        raise ValueError("Diagnostic transport forbids upload")


def safe_error(error):
    result = {"exceptionType": type(error).__name__}
    if isinstance(error, KeyError):
        key = error.args[0] if error.args else None
        result["missingKey"] = key if key in {"fileCount", "status", "config", "files", "name", "release", "version", "releaseTime", "path", "hash", "candidateVersion"} else "redacted"
    if isinstance(error, json.JSONDecodeError):
        result.update(jsonLine=error.lineno, jsonColumn=error.colno)
    if isinstance(error, SafeHTTPError):
        result["httpStatus"] = error.status
    if isinstance(error, urllib.error.HTTPError):
        result["httpStatus"] = error.code
    if isinstance(error, OSError) and error.errno is not None:
        result["errno"] = error.errno
    # Frame locations only: no values, raw messages, response bodies or auth headers.
    result["frames"] = [{"file": Path(frame.filename).name, "line": frame.lineno, "function": frame.name}
                        for frame in traceback.extract_tb(error.__traceback__)]
    return result


def diagnose(transport, plan, state):
    hosting.require(state["planHash"] == hosting.privacy.digest(plan), "State/plan mismatch")
    hosting.require(plan["site"] == hosting.SITE, "Wrong site")
    candidate = state["candidateVersion"]
    hosting.validate_version(candidate)
    report = {"mode": "GET-only", "savedPhase": state["phase"], "candidateVersion": candidate, "steps": []}

    def step(name, operation):
        try:
            result = operation()
            report["steps"].append({"step": name, "result": result})
        except Exception as error:
            report["steps"].append({"step": name, "error": safe_error(error)})

    def metadata():
        value = transport.api("GET", candidate)
        return {"status": value.get("status"), "fileCountPresent": "fileCount" in value,
                "fileCount": value.get("fileCount"), "finalizeTime": value.get("finalizeTime"),
                "configMatchesPlan": value.get("config") == plan["config"]}

    def candidate_inventory():
        value = hosting.inventory(transport, candidate)
        expected = plan["afterFiles"]
        differing = sorted(path for path in set(value["files"]) | set(expected) if value["files"].get(path) != expected.get(path))
        return {"fileCount": len(value["files"]), "configMatchesPlan": value["config"] == plan["config"], "differingPaths": differing}

    def baseline():
        value = hosting.inventory(transport, plan["beforeRelease"]["version"])
        return {"unchanged": value == {"config": plan["config"], "files": plan["beforeFiles"]}}

    def live():
        value = hosting.current(transport)
        return {"release": value, "stillBaseline": value == plan["beforeRelease"], "candidateIsLive": value["version"] == candidate}

    step("candidate-metadata", metadata)
    step("candidate-inventory", candidate_inventory)
    step("baseline-inventory", baseline)
    step("live-release", live)
    step("public-privacy", lambda: {"htmlHash": hosting.sha(transport.public())})
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--control", type=Path, default=hosting.privacy.CONTROL)
    args = parser.parse_args()
    plan, state = json.loads(args.plan.read_text()), json.loads(args.state.read_text())
    print(json.dumps(diagnose(ReadOnlyTransport(args.control), plan, state), indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"mode": "GET-only", "error": safe_error(error)}, indent=2))
        raise SystemExit(1)
