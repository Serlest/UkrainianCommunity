#!/usr/bin/env python3
"""F02-only coordinator tool. Default is offline inspection; never retries writes."""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent
PROJECT = 'ukrainiancommunity-dbd5f'
DATABASE = f'projects/{PROJECT}/databases/(default)'
API = 'https://firestore.googleapis.com/v1/'
IDS = {
    '09CBA4CE-6066-4DA1-822A-F50A02E25A44',
    '4CCF2D2C-204B-403C-AD3C-162767C7BB65',
    '97E3A6BD-49AF-4EEB-A32C-6A61DCE857E2',
    'FE5637D0-6B8D-483B-869C-C628E3941D92',
}
HELD_ID = 'FE5637D0-6B8D-483B-869C-C628E3941D92'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(',', ':')).encode()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def de_fields(document):
    return document.get('fields', {}).get('localizations', {}).get('mapValue', {}).get(
        'fields', {}).get('de', {}).get('mapValue', {}).get('fields', {})


def without_targets(document, keys):
    fields = copy.deepcopy(document.get('fields', {}))
    locales = fields.get('localizations', {}).get('mapValue', {}).get('fields', {})
    de = locales.get('de', {}).get('mapValue', {}).get('fields', {})
    for key in keys:
        de.pop(key, None)
    # Missing and newly-created empty parent maps are equivalent for this comparison.
    if not de:
        locales.pop('de', None)
    if not locales:
        fields.pop('localizations', None)
    return fields


def load_package():
    translations = read(ROOT / 'translations.json')['events']
    require(len(translations) == 4 and {e['id'] for e in translations} == IDS,
            'Unexpected translation set')
    eligible = read(ROOT / 'eligible.patch.json')['writes']
    held = read(ROOT / 'held.patch.json')['writes']
    require(len(eligible) == 3 and len(held) == 1, 'Expected three eligible and one held candidate')
    patch = eligible + held
    result = {}
    keys = ['title', 'details', 'summary']
    for index, event in enumerate(translations):
        event_id = event['id']
        baseline = read(ROOT / f'{event_id}.baseline.json')
        name = f'{DATABASE}/documents/events/{event_id}'
        require(baseline['name'] == name, 'Unexpected baseline path')
        require((index == 3) == (event_id == HELD_ID), 'Held candidate is in eligible set')
        expected = {
            'update': {'name': name, 'fields': {'localizations': {'mapValue': {
                'fields': {'de': {'mapValue': {'fields': {
                    key: {'stringValue': event[key]} for key in keys
                }}}}
            }}}},
            'updateMask': {'fieldPaths': ['localizations.de.' + key for key in keys]},
            'currentDocument': {'updateTime': baseline['updateTime']},
        }
        require(patch[index] == expected, f'Patch shape/text/precondition mismatch: {event_id}')
        require(all(isinstance(event[k], str) and event[k].strip() for k in keys),
                f'Empty translation: {event_id}')
        result[event_id] = (event, baseline, patch[index])
    return result


def save_new(path, data):
    # No overwrites: retain evidence from an uncertain earlier attempt.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(data, output, ensure_ascii=False, indent=2)
        output.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='inspect',
                        choices=['inspect', 'preflight', 'publish', 'read-back'])
    parser.add_argument('--event', action='append', default=[], help='Exact F02 ID; repeat as needed')
    parser.add_argument('--control', type=Path,
                        default=Path('/Users/serlest/Documents/Codex/2026-09-04/new-chat/production-release/control.py'))
    parser.add_argument('--evidence-dir', type=Path)
    parser.add_argument('--verification-record', type=Path,
                        help='Existing nonempty coordinator record of completed common verification')
    parser.add_argument('--confirm-project', choices=[PROJECT])
    args = parser.parse_args()
    package = load_package()
    require(len(args.event) == len(set(args.event)), 'Duplicate event selection')
    selected = args.event or sorted(IDS - {HELD_ID})
    require(set(selected) <= IDS, 'Unexpected event ID')
    writes = [package[event_id][2] for event_id in selected]
    keys = ['title', 'details', 'summary']
    fingerprint = digest(writes)
    if args.mode == 'inspect':
        print(json.dumps({'mode': 'offline', 'writes': writes, 'sha256': fingerprint,
                          'heldEvent': HELD_ID},
                         ensure_ascii=False, indent=2))
        return
    require(args.evidence_dir is not None, 'An evidence directory is required')
    if args.mode == 'publish':
        require(bool(args.event), 'Publication requires an explicit --event selection')
        require(args.confirm_project == PROJECT, 'Confirm the exact production project')
        require(args.verification_record is not None and args.verification_record.is_file()
                and args.verification_record.stat().st_size > 0,
                'Common verification must be recorded first')
        require(HELD_ID not in selected, 'Parish source conflict is held; no override is provided')
        require(all(package[i][0]['sourceStatus'] == 'verified' for i in selected),
                'Selected sources are not verified')
    # Import the existing credential helper only for deliberate network operations.
    spec = importlib.util.spec_from_file_location('release_control', args.control)
    control = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(control)
    require(control.PROJECT == PROJECT, 'Credential helper project mismatch')
    auth = control.headers()

    def get(event_id):
        status, document = control.request(API + f'{DATABASE}/documents/events/{event_id}',
                                           method='GET', auth=auth)
        require(status == 200, f'Event GET failed: {event_id}; HTTP {status}')
        require(document.get('name') == package[event_id][1]['name'], 'Read path mismatch')
        return document

    def read_back(before):
        require(before['writesSha256'] == fingerprint and before['ids'] == selected,
                'Read-back selection/package differs from saved preflight')
        rows = []
        for event_id in selected:
            live = get(event_id)
            matches = all(de_fields(live).get(k) == {'stringValue': package[event_id][0][k]}
                          for k in keys)
            rows.append({'id': event_id, 'updateTime': live['updateTime'],
                         'targetMatches': matches,
                         'otherFieldsUnchanged': digest(without_targets(live, keys)) ==
                         before['documents'][event_id]['otherFieldsSha256']})
        return {'checkedAt': datetime.now(timezone.utc).isoformat(),
                'writesSha256': fingerprint, 'events': rows,
                'passed': all(r['targetMatches'] and r['otherFieldsUnchanged'] for r in rows)}

    if args.mode == 'read-back':
        before = read(args.evidence_dir / 'before.json')
        result = read_back(before)
        filename = 'read-back-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json'
        save_new(args.evidence_dir / filename, result)
        print(json.dumps(result, indent=2))
        require(result['passed'], 'Read-back mismatch; inspect evidence, do not retry writes')
        return

    before = {'checkedAt': datetime.now(timezone.utc).isoformat(), 'ids': selected,
              'writesSha256': fingerprint, 'documents': {}}
    for event_id in selected:
        live = get(event_id)
        baseline = package[event_id][1]
        require(live['updateTime'] == baseline['updateTime'],
                f'Stale baseline: {event_id}; re-review, do not refresh preconditions automatically')
        require(all(live['fields'].get(k) == v for k, v in baseline['fields'].items()),
                f'Baseline field mismatch: {event_id}')
        require(not any(de_fields(live).get(k) for k in keys), 'German target already exists')
        before['documents'][event_id] = {
            'updateTime': live['updateTime'],
            'otherFieldsSha256': digest(without_targets(live, keys)),
        }
    args.evidence_dir.mkdir(parents=True, exist_ok=False)
    save_new(args.evidence_dir / 'before.json', before)
    if args.mode == 'preflight':
        print('Read-only preflight recorded. No writes were sent.')
        return
    save_new(args.evidence_dir / 'verification.json', {
        'recordPath': str(args.verification_record.resolve()),
        'recordSha256': hashlib.sha256(args.verification_record.read_bytes()).hexdigest(),
    })
    save_new(args.evidence_dir / 'request.json', {'writes': writes})
    # One atomic commit; precise updateTime preconditions close the GET/write race.
    try:
        status, response = control.request(API + DATABASE + '/documents:commit',
                                           body={'writes': writes}, method='POST', auth=auth)
        receipt = {'httpStatus': status, 'commitTime': response.get('commitTime'),
                   'writeResults': response.get('writeResults', [])}
        response_ok = status == 200 and len(receipt['writeResults']) == len(writes)
    except Exception as error:
        # Exception messages/response bodies may contain sensitive data. Retain only type.
        receipt = {'outcome': 'uncertain', 'errorType': type(error).__name__}
        response_ok = False
    save_new(args.evidence_dir / 'receipt.json', receipt)
    # Even an uncertain transport outcome gets exactly one read-back, never a resend.
    result = read_back(before)
    save_new(args.evidence_dir / 'after.json', result)
    print(json.dumps({'receipt': receipt, 'readBack': result}, indent=2))
    require(response_ok and result['passed'],
            'Publication outcome needs coordinator review; do not retry writes blindly')


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print('Stopped (' + type(error).__name__ + '); no automatic write retry.', file=sys.stderr)
        sys.exit(1)
