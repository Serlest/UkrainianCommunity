"""Offline publisher safety cases for the coordinator's common verification phase.
Written during implementation; not executed by the content task.
"""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('publish_de', Path(__file__).with_name('publish_de.py'))
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)


class PublicationSafetyTests(unittest.TestCase):
    def setUp(self):
        self.package = subject.load_package()
        self.ids = sorted(subject.IDS - {subject.HELD_ID})
        self.live = {i: copy.deepcopy(v[1]) for i, v in self.package.items()}
        self.calls = []
        self.commit_behavior = 'success'
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.verification = self.directory / 'verification.md'
        self.verification.write_text('Offline test fixture only; not release approval.')

    def request(self, url, body=None, method=None, auth=None):
        self.calls.append((method, url, body))
        if method == 'GET':
            return 200, copy.deepcopy(self.live[url.rsplit('/', 1)[1]])
        self.assertEqual(method, 'POST')
        self.assertTrue(url.endswith('/documents:commit'))
        if self.commit_behavior == 'reject':
            return 409, {'error': {'message': 'conflict'}}
        for write in body['writes']:
            event_id = write['update']['name'].rsplit('/', 1)[1]
            self.assertEqual(write['currentDocument']['updateTime'], self.live[event_id]['updateTime'])
            self.live[event_id]['fields']['localizations']['mapValue']['fields']['de'] = copy.deepcopy(
                write['update']['fields']['localizations']['mapValue']['fields']['de'])
            self.live[event_id]['updateTime'] = '2026-09-05T12:00:00.000001Z'
        if self.commit_behavior == 'timeout_after_write':
            raise TimeoutError('Do not expose transport details')
        if self.commit_behavior == 'other_field_changed':
            self.live[self.ids[0]]['fields']['address'] = {'stringValue': 'concurrent change'}
        return 200, {'commitTime': '2026-09-05T12:00:00.000001Z',
                     'writeResults': [{'updateTime': '2026-09-05T12:00:00.000001Z'} for _ in body['writes']]}

    def run_main(self, mode='publish', ids=None):
        evidence = self.directory / 'attempt'
        argv = ['publish_de.py', mode, '--evidence-dir', str(evidence),
                '--verification-record', str(self.verification), '--confirm-project', subject.PROJECT]
        for event_id in (self.ids if ids is None else ids):
            argv.extend(['--event', event_id])
        control = SimpleNamespace(PROJECT=subject.PROJECT, headers=lambda: {}, request=self.request)
        spec = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda module: None))
        with patch.object(sys, 'argv', argv), \
             patch.object(subject.importlib.util, 'spec_from_file_location', return_value=spec), \
             patch.object(subject.importlib.util, 'module_from_spec', return_value=control), \
             patch('builtins.print'):
            subject.main()
        return evidence

    def post_calls(self):
        return [call for call in self.calls if call[0] == 'POST']

    def test_exact_three_field_mask_and_original_preconditions(self):
        for event, baseline, write in self.package.values():
            self.assertEqual(set(write['updateMask']['fieldPaths']),
                             {'localizations.de.title', 'localizations.de.details', 'localizations.de.summary'})
            self.assertEqual(write['currentDocument'], {'updateTime': baseline['updateTime']})
            self.assertEqual(set(subject.de_fields(write['update'])), {'title', 'details', 'summary'})

    def test_success_is_one_atomic_commit_with_three_writes_and_read_back(self):
        evidence = self.run_main()
        self.assertEqual(len(self.post_calls()), 1)
        self.assertEqual(len(self.post_calls()[0][2]['writes']), 3)
        self.assertTrue(json.loads((evidence / 'after.json').read_text())['passed'])
        self.assertEqual(sum(call[0] == 'GET' for call in self.calls), 6)

    def test_held_candidate_stops_before_auth_or_network(self):
        with self.assertRaisesRegex(ValueError, 'Parish source conflict'):
            self.run_main(ids=[subject.HELD_ID])
        self.assertEqual(self.calls, [])

    def test_stale_baseline_never_writes(self):
        self.live[self.ids[0]]['updateTime'] = '2026-09-05T00:00:00Z'
        with self.assertRaisesRegex(ValueError, 'Stale baseline'):
            self.run_main()
        self.assertEqual(self.post_calls(), [])

    def test_read_only_preflight_never_posts(self):
        self.run_main(mode='preflight')
        self.assertEqual(self.post_calls(), [])

    def test_server_conflict_read_back_once_and_no_retry(self):
        self.commit_behavior = 'reject'
        with self.assertRaisesRegex(ValueError, 'coordinator review'):
            self.run_main()
        self.assertEqual(len(self.post_calls()), 1)
        self.assertEqual(sum(call[0] == 'GET' for call in self.calls), 6)

    def test_timeout_after_commit_does_not_resend_successful_writes(self):
        self.commit_behavior = 'timeout_after_write'
        with self.assertRaisesRegex(ValueError, 'coordinator review'):
            self.run_main()
        self.assertEqual(len(self.post_calls()), 1)
        self.assertTrue(json.loads((self.directory / 'attempt' / 'after.json').read_text())['passed'])

    def test_other_fields_changed_is_not_claimed_as_success(self):
        self.commit_behavior = 'other_field_changed'
        with self.assertRaisesRegex(ValueError, 'coordinator review'):
            self.run_main()
        self.assertEqual(len(self.post_calls()), 1)
        self.assertFalse(json.loads((self.directory / 'attempt' / 'after.json').read_text())['passed'])


if __name__ == '__main__':
    unittest.main()
