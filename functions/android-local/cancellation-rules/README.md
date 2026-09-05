# Isolated cancellation-field Rules regression

Local-only O09 security remediation. Not a production deployment, Android backend,
or replacement for the existing callable proof. The only SDK loaded is the Rules
test client; Admin SDK, Functions imports, all other service ports and outbound
network mechanisms are blocked before that SDK is imported.

## Parent-owned execution window

This folder's implementation was written source-only. The parent task must first
review and run its port-free boundary tests:

```sh
node --test functions/android-local/cancellation-rules/boundary.test.cjs
```

Then start a **separate** Firestore-only emulator with reviewed clean CLI environment,
project `demo-uac-cancellation-rules`, config `firebase.android-cancellation-rules.json`.
Check ports8098/4418/4518 are free; do not kill another listener. Do not use the
shared Android project's8088 port, default firebase.json, cloud project, Auth,
Storage or Functions. The test runner intentionally does not start/restart any
emulator and cannot load the user's persisted Firebase CLI login.

Once this isolated emulator is available:

```sh
UAC_CANCELLATION_RULES_LOCAL=1 FIRESTORE_EMULATOR_HOST=127.0.0.1:8098 node functions/android-local/cancellation-rules/run.cjs
```

The runner gives the child an allowlisted environment, exact project/host and
four-minute total deadline. No inherited credential/proxy/loader variables, home
directory or Firebase configuration are copied. The suite also rejects direct
execution with anything but its exact clean local environment.

No `clearFirestore`, recursive deletion, collection-wide cleanup, import or
export is used. Every fixture uses one fresh process UUID and is registered
before any write. Cleanup attempts each exact registered path, even if another
cleanup failed; read-back uses `getDocFromServer`. A test timeout is a failure,
not permission to replay a mutation. Boundary checks are an accidental-egress
Node guard, not an OS sandbox for untrusted native code.

## Coverage and interpretation

- Normal canonical create/edit for organization owner/admin/moderator and app owner.
- Individual and combined cancellation-field create rejection, including null/active.
- Add/change/null/remove and merge/full-replacement rejection of four protected fields.
- Legacy cancellation metadata preserved during ordinary editing; no new permission
  to edit documents containing schema-excluded `cancelledBy` is introduced.
- Existing platform moderation-only path, scheduled own drafts, app-content edit
  scope, registered cancelled-event reads, News authoring/deletion prohibition.
- Guest, foreign, unverified, blocked and MFA-required-without-TOTP denials.
- Existing BC01 iOS/Android push registration security gates remain intact.

Negative assertions require exact `permission-denied`, not merely any rejection.
This suite uses local synthetic Rules tokens and server-disabled fixture setup;
it is not real Auth/TOTP, callable, FCM or cloud evidence. After its PASS, root
must reload the reviewed local Rules on the Android runtime and repeat the exact
Android probe as required DENIED plus the real `cancelEvent` Device scenario.

The original snapshot839 ALLOWED observation remains in the audit record. A new
PASS demonstrates the changed **local** Rules only; production remains a separate
review/deployment/read-back decision.
