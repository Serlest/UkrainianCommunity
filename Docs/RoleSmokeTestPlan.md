# Role Smoke Test Plan

## Platform roles

- App Owner has full platform access and organization override.
- App Owner alone assigns or removes App Admin.
- App Admin manages users, organization requests, moderation, feedback, and reports without organization override.
- User has no platform management access.
- Persisted `topAdmin`, `appModerator`, removed `moderator`, and retired `canManageGuide` values grant no elevated access.

## Organization roles

- Organization Owner manages information, team roles, News, Events, and organization moderation.
- Organization Admin edits information and manages organization content, but not team roles.
- Organization Moderator manages organization content only.
- Platform administrators receive no implicit organization access.

## Restricted accounts

- Suspended, permanently banned, and deactivated accounts receive no elevated access.
- Verified email is required for user-generated writes.

## Required automated coverage

- Swift unit tests verify client presentation gates.
- Role contract smoke tests verify Cloud Functions permission helpers.
- Firestore emulator tests verify server-side Rules.
- Storage emulator tests cover privileged, organization, self-service, public-read, unknown, and retired paths.
