"""Offline-only publisher tests: in-memory Firestore REST responses, no credentials."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("publish_privacy_2026_13.py"))
pub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pub)


def document(path, fields):
    return {"name": f"{pub.DATABASE}/documents/{path}", "fields": {k: pub.wire(v) for k, v in fields.items()}, "createTime": "2026-09-02T00:00:00Z", "updateTime": "2026-09-02T00:00:00Z"}


def initial():
    documents = {}
    for kind in pub.KINDS:
        version = "2026.12" if kind == "privacy" else "2026.10"
        path = f"legalDocuments/{kind}"
        documents[path] = document(path, {"activeVersion": version, "untouchedField": "preserve"})
        for old in (["2026.11", version] if kind == "privacy" else [version]):
            version_path = f"{path}/versions/{old}"
            documents[version_path] = document(version_path, {"version": old, "contentHash": "historical-fixture"})
    return documents


class FakeTransport:
    def __init__(self):
        self.documents = initial()
        self.commits = []
        self.lose_response = False
        self.conflict = False

    def request(self, url, body=None):
        if body is None:
            path = urlsplit(url).path.split("/documents/", 1)[1]
            if path.endswith("/versions"):
                return 200, {"documents": [copy.deepcopy(v) for k, v in self.documents.items() if k.startswith(path + "/")]}
            return 200, copy.deepcopy(self.documents[path])
        assert url == pub.BASE + ":commit"
        self.commits.append(copy.deepcopy(body))
        if self.conflict:
            return 409, {}
        for write in body["writes"]:
            path = write["update"]["name"].split("/documents/", 1)[1]
            if "exists" in write["currentDocument"]:
                assert write["currentDocument"] == {"exists": False}
                assert path not in self.documents
            else:
                assert self.documents[path]["updateTime"] == write["currentDocument"]["updateTime"]
            target = self.documents.setdefault(path, {"name": write["update"]["name"], "fields": {}})
            target["fields"].update(write["update"]["fields"])
            for transform in write["updateTransforms"]:
                target["fields"][transform["fieldPath"]] = {"timestampValue": "2026-09-05T20:00:00Z"}
            target["updateTime"] = "2026-09-05T20:00:00Z"
        if self.lose_response:
            raise TimeoutError("simulated lost response")
        return 200, {}


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.payload = pub.local_payload()
        self.transport = FakeTransport()
        self.plan = pub.plan_for(self.payload, pub.snapshot(self.transport))
        self.clock = patch.object(pub, "datetime")
        self.clock.start().now.return_value.date.return_value.isoformat.return_value = self.payload["effectiveDate"]
        self.addCleanup(self.clock.stop)

    def test_default_cli_only_reads_and_creates_review_plan(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "plan.json"
            with patch.object(pub, "Transport", return_value=self.transport), patch("sys.argv", ["publisher", "--plan", str(path)]), patch("sys.stdout", new_callable=io.StringIO):
                pub.main()
                self.assertEqual(json.loads(path.read_text()), self.plan)
                with self.assertRaises(FileExistsError):
                    pub.main()
            self.assertEqual(self.transport.commits, [])

    def test_exact_two_writes_use_create_and_cas(self):
        writes = pub.writes_for(self.payload, self.plan)["writes"]
        self.assertEqual(len(writes), 2)
        self.assertEqual(writes[0]["currentDocument"], {"exists": False})
        self.assertEqual(writes[1]["currentDocument"], {"updateTime": self.plan["pointerUpdateTime"]})
        self.assertIn("updateMask", writes[1])
        self.assertNotIn("updateMask", writes[0])

    def test_apply_preserves_history_and_hashes_both_locales(self):
        result = pub.apply(self.transport, self.payload, self.plan)
        self.assertEqual(result["result"], "published-and-verified")
        self.assertEqual(result["localeHashes"], self.plan["localeHashes"])
        self.assertEqual(len(self.transport.commits), 1)
        self.assertEqual(self.transport.documents[pub.POINTER]["fields"]["untouchedField"], pub.wire("preserve"))

    def test_stale_pointer_or_history_refuses_before_write(self):
        for path in (pub.POINTER, "legalDocuments/terms/versions/2026.10"):
            transport = FakeTransport()
            transport.documents[path]["updateTime"] = "changed"
            with self.assertRaises(ValueError):
                pub.apply(transport, self.payload, self.plan)
            self.assertEqual(transport.commits, [])

    def test_existing_target_is_never_overwritten(self):
        self.transport.documents[pub.TARGET] = document(pub.TARGET, {"version": "2026.13"})
        with self.assertRaises(ValueError):
            pub.apply(self.transport, self.payload, self.plan)
        self.assertEqual(self.transport.commits, [])

    def test_changed_local_payload_or_project_refuses(self):
        for key, value in (("project", "other-project"), ("contentHash", "changed"), ("inputHashes", {})):
            plan = {**self.plan, key: value}
            with self.assertRaises(ValueError):
                pub.apply(self.transport, self.payload, plan)
        self.assertEqual(self.transport.commits, [])

    def test_wrong_effective_date_refuses(self):
        with self.assertRaises(ValueError):
            pub.apply(self.transport, {**self.payload, "effectiveDate": "2000-01-01"}, self.plan)
        self.assertEqual(self.transport.commits, [])

    def test_uncertain_commit_verifies_without_retry(self):
        self.transport.lose_response = True
        result = pub.apply(self.transport, self.payload, self.plan)
        self.assertEqual(result["result"], "verified-after-uncertain-response")
        self.assertEqual(len(self.transport.commits), 1)

    def test_cas_conflict_does_not_retry_or_claim_success(self):
        self.transport.conflict = True
        with self.assertRaisesRegex(ValueError, "Do not retry"):
            pub.apply(self.transport, self.payload, self.plan)
        self.assertEqual(len(self.transport.commits), 1)

    def test_readback_rejects_changed_historical_document_and_locale(self):
        pub.apply(self.transport, self.payload, self.plan)
        after = copy.deepcopy(self.transport.documents)
        after["legalDocuments/privacy/versions/2026.12"]["updateTime"] = "changed"
        with self.assertRaises(ValueError):
            pub.verify(self.payload, self.plan, after)
        after = copy.deepcopy(self.transport.documents)
        after[pub.TARGET]["fields"]["locales"]["mapValue"]["fields"]["de"]["mapValue"]["fields"]["contentMarkdown"] = pub.wire("tampered")
        with self.assertRaises(ValueError):
            pub.verify(self.payload, self.plan, after)


if __name__ == "__main__":
    unittest.main()
