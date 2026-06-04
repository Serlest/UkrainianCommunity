# Role Smoke Test Plan

This plan covers the final platform and organization role contract.

## Automated Now

- Swift unit tests cover `PermissionService` platform role gates, usable-account gates, legacy role non-elevation, and organization array boundaries.
- Functions smoke tests cover exported backend permission predicates and organization-role boundary behavior without requiring Firebase services.

Run:

```sh
npm --prefix functions run smoke:roles
```

Run Swift tests from Xcode, or with the active Xcode test action.

## Requires Firebase Emulator Setup

Firestore rules tests should be added with `@firebase/rules-unit-testing` and the Firestore emulator to verify:

- direct writes to `globalRole` and `canManageGuide` are rejected,
- owner/admin/moderator/guide editor reads and writes match `Firebase/firestore.rules`,
- App Admin and App Moderator cannot edit arbitrary organizations,
- Guide Editor can write guide collections only,
- owner-only featured banner and organization override paths remain owner-only.

Cloud Function callable tests should be added with emulator-backed seeded Firestore data to verify:

- `assignAppAdmin`, `removeAppAdmin`, `assignAppModerator`, `removeAppModerator`, `assignGuideEditor`, and `removeGuideEditor` are owner-only,
- App Admin, App Moderator, Guide Editor, and normal users are denied role assignment,
- protected owner targets, self role changes, missing targets, unusable targets, and no-op changes fail cleanly,
- audit logs are written with previous and new role values,
- organization request review callables allow App Owner/App Admin and deny App Moderator/Guide Editor.

## Manual UI Smoke Test

- Owner sees User Management role controls and can trigger confirmation dialogs.
- App Admin sees organization requests, moderation, feedback/reports, and guide only with `canManageGuide`.
- App Moderator sees moderation and feedback/reports without organization request counts.
- Guide Editor sees Guide Management only.
- Platform roles do not appear as organization roles in organization team screens.
