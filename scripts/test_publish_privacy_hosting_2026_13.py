"""Offline Hosting fake: no network, credentials, versions or releases created."""
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs

import publish_privacy_hosting_2026_13 as pub


class Fake:
    def __init__(self, local, new_html):
        self.old = pub.SITE + "/versions/old"
        self.new = pub.SITE + "/versions/new"
        self.live = {"id": "1", "version": self.old, "time": "old-time"}
        self.files = {pub.SELECTED: "a" * 64, "/index.html": "b" * 64, "/__/firebase/init.js": "c" * 64}
        self.config = {"cleanUrls": True, "headers": [{"glob": "**", "headers": {"X-Test": "keep"}}]}
        self.versions = {self.old: {"config": self.config, "files": self.files}}
        self.old_html = 'Version 2026.12 / Версія 2026.12'.encode()
        self.new_html = new_html
        self.local = local
        self.writes = []
        self.uploads = []
        self.extra_required = False
        self.race = False
        self.lose_release = False

    def api(self, method, path, body=None):
        if method == "GET":
            if path == pub.LIVE:
                return {"release": {"name": pub.LIVE + "/releases/" + self.live["id"], "version": {"name": self.live["version"]}, "releaseTime": self.live["time"]}}
            if "/files?" in path:
                version = path.split("/files?")[0]
                return {"files": [{"path": p, "hash": h, "status": "ACTIVE"} for p, h in self.versions[version]["files"].items()]}
            version = self.versions[path]
            return {"status": "FINALIZED", "fileCount": str(len(version["files"])), "config": version["config"]}
        self.writes.append((method, path, copy.deepcopy(body)))
        if path == pub.SITE + "/versions":
            self.versions[self.new] = {"config": body["config"], "files": {}}
            return {"name": self.new}
        if path.endswith(":populateFiles"):
            self.versions[self.new]["files"].update(body["files"])
            return {"uploadRequiredHashes": ["d" * 64] if self.extra_required else [self.local["gzipHash"]], "uploadUrl": f"https://upload-firebasehosting.googleapis.com/upload/{self.new}/files"}
        if method == "PATCH":
            if self.race:
                self.live = {**self.live, "id": "concurrent"}
            return {}
        if "/releases?" in path:
            version = parse_qs(path.split("?", 1)[1])["versionName"][0]
            self.live = {"id": "2" if version == self.new else "3", "version": version, "time": "new-time"}
            if self.lose_release:
                raise TimeoutError()
            return {}
        raise AssertionError("Unexpected mutation")

    def public(self):
        return self.new_html if self.live["version"] == self.new else self.old_html

    def upload(self, version, digest, data):
        assert version == self.new and pub.sha(data) == digest == self.local["gzipHash"]
        self.uploads.append(digest)


class HostingTests(unittest.TestCase):
    def setUp(self):
        self.html, self.compressed, self.local = pub.payload()
        self.transport = Fake(self.local, self.html)
        self.plan = pub.prepare(self.transport, self.local)
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / "state.json"
        clock = patch.object(pub, "datetime")
        clock.start().now.return_value.date.return_value.isoformat.return_value = self.local["effectiveDate"]
        self.addCleanup(clock.stop)

    def run_apply(self):
        return pub.apply(self.transport, self.plan, self.local, self.compressed, self.path)

    def test_default_cli_no_mutations_and_full_map(self):
        path = Path(self.folder.name) / "plan.json"
        with patch.object(pub, "Transport", return_value=self.transport), patch("sys.argv", ["publisher", "--plan", str(path)]), patch("sys.stdout", new_callable=io.StringIO):
            pub.main()
        self.assertEqual(self.transport.writes, [])
        self.assertEqual(self.transport.uploads, [])
        self.assertEqual(json.loads(path.read_text())["beforeFiles"], self.transport.files)

    def test_one_file_upload_preserves_config_and_all_other_hashes(self):
        result = self.run_apply()
        self.assertEqual(result["unchangedOtherFiles"], 2)
        self.assertEqual(self.transport.uploads, [self.local["gzipHash"]])
        for path, value in self.transport.files.items():
            if path != pub.SELECTED:
                self.assertEqual(self.transport.versions[self.transport.new]["files"][path], value)
        self.assertEqual(self.transport.versions[self.transport.new]["config"], self.transport.config)

    def test_old_release_guard_before_creating_anything(self):
        self.transport.live["id"] = "changed"
        with self.assertRaises(ValueError):
            self.run_apply()
        self.assertEqual(self.transport.writes, [])

    def test_guard_again_before_releasing_candidate(self):
        self.transport.race = True
        with self.assertRaises(ValueError):
            self.run_apply()
        self.assertFalse(any("/releases?" in path for _, path, _ in self.transport.writes))

    def test_no_unrelated_upload_even_if_requested_by_hosting(self):
        self.transport.extra_required = True
        with self.assertRaises(ValueError):
            self.run_apply()
        self.assertEqual(self.transport.uploads, [])
        self.assertFalse(any("/releases?" in path for _, path, _ in self.transport.writes))

    def test_state_blocks_repeated_apply(self):
        self.path.write_text('{}')
        with self.assertRaises(FileExistsError):
            self.run_apply()
        self.assertEqual(self.transport.writes, [])

    def test_uncertain_release_has_readonly_recovery_not_retry(self):
        self.transport.lose_release = True
        with self.assertRaisesRegex(ValueError, "Never repeat"):
            self.run_apply()
        state = json.loads(self.path.read_text())
        self.assertEqual(state["phase"], "release-response-uncertain")
        before = len(self.transport.writes)
        self.assertEqual(pub.verify(self.transport, self.plan, state)["release"]["version"], self.transport.new)
        self.assertEqual(len(self.transport.writes), before)

    def test_html_readback_rejects_wrong_content(self):
        self.run_apply()
        state = json.loads(self.path.read_text())
        self.transport.new_html = b"wrong"
        with self.assertRaises(ValueError):
            pub.verify(self.transport, self.plan, state)

    def test_rollback_releases_exact_old_version_and_checks_html(self):
        self.run_apply()
        state = json.loads(self.path.read_text())
        result = pub.rollback(self.transport, self.plan, state, self.path)
        self.assertTrue(result["rollback"])
        self.assertEqual(result["htmlHash"], self.plan["beforeHtmlHash"])
        self.assertEqual(self.transport.live["version"], self.transport.old)
        self.assertEqual(len(self.transport.uploads), 1)

    def test_rollback_wont_override_a_later_release(self):
        self.run_apply()
        state = json.loads(self.path.read_text())
        self.transport.live["id"] = "later-release"
        before = len(self.transport.writes)
        with self.assertRaises(ValueError):
            pub.rollback(self.transport, self.plan, state, self.path)
        self.assertEqual(len(self.transport.writes), before)


if __name__ == "__main__":
    unittest.main()
