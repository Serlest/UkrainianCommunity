# Permission Matrix

This document describes the active authorization contract. UI checks are presentation only; Firestore Rules, Storage Rules, and callable Cloud Functions remain authoritative.

## Platform roles

### App Owner

- Full platform administration.
- Assigns and removes App Admin.
- Manages users, organization requests, moderation, feedback, reports, featured banners, legal documents, analytics, and system logs.
- May use the explicit organization override without becoming an organization team member.

### App Admin

- Manages users, account status, organization requests, moderation, feedback, and reports.
- Cannot assign App Admin, manage featured banners, or use the organization override.
- Has no implicit authority over organization-owned content.

### User

- Reads public content and uses verified-user interactions permitted by Rules.
- Receives no platform management authority.

Persisted legacy values (`topAdmin`, `appModerator`, the removed `moderator` value, and the retired `canManageGuide` flag) must never grant elevated authorization.

## Organization roles

Organization roles are independent from platform roles and are stored on the organization document.

### Organization Owner

- Edits organization information.
- Manages the organization team.
- Creates and edits organization News and Events.
- Moderates organization content.

### Organization Admin

- Edits organization information.
- Creates and edits organization News and Events.
- Does not manage organization roles.

### Organization Moderator

- Creates and edits organization News and Events.
- Moderates organization content.
- Cannot edit organization information or manage roles.

## Account restrictions

Only accounts whose `accountStatus` and `blockState` are `active` or `warned` may receive elevated authorization. Email verification is required for user-generated writes.

## Enforcement rule

Every permission change must be updated together in Swift, Firestore Rules, Storage Rules, Cloud Functions, and automated tests. A role exposed in only one layer is a defect.
