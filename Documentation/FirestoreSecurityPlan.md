# Firestore Security Plan

## Active security contract

`Firebase/firestore.rules` is the authoritative access layer. Swift and SwiftUI permission checks only shape the interface and must never be treated as data protection.

The active platform roles are `user`, `admin`, and `owner`:

- App Owner controls platform administration, App Admin assignment, featured banners, legal documents, analytics, and the explicit organization override.
- App Admin manages the limited platform workflows allowed by Rules, without owner assignment, featured-banner management, or organization override.
- User receives no platform-management authority.

Organization Owner, Admin, and Moderator permissions are independent and derive from membership arrays on each organization document. Legacy role values and retired capability fields are migration data only and must never authorize a request.

## Access boundaries

### Public content

- Approved News, Events, and Organizations are publicly readable under their collection-specific visibility rules.
- Comment reads follow the parent content and deletion state.
- Archived cancelled Events are readable only by the affected registrant or an authorized manager.

### Authenticated user activity

- A verified active user may create only their own permitted likes, bookmarks, follows, registrations, comments, feedback, recent views, and activity records.
- Document identifiers and embedded user/content identifiers must match the authenticated user and request path.
- Self-service profile updates are limited to explicitly allowlisted personal fields.
- Users cannot change their own platform role, organization membership, block state, or warning state.

### Platform and organization management

- Platform management checks require a verified, active account and the exact current platform role.
- Organization management checks require current membership in the relevant organization, except for the owner's explicit override.
- Content create/update rules validate source ownership, organization linkage, immutable identity fields, moderation state, and allowed field sets.
- Role mutations and account deletion run through trusted callable Cloud Functions where server-side authority is required.

### Sensitive and operational data

- System logs are readable only within the owner/admin category boundaries and accept only constrained client-created payloads.
- Notification outbox/inbox documents, analytics aggregates, moderation queues, and audit records have collection-specific deny-by-default write rules.
- App configuration accepts only the active Home, Events, and Organizations banner documents plus the donation configuration.
- Collections without an explicit match fall through to `allow read, write: if false`.

## Account state requirements

- Elevated access requires verified email and an account whose `accountStatus` and `blockState` are `active` or `warned`.
- Suspended, banned, deactivated, or otherwise restricted accounts receive no elevated authorization even if stale role data remains.
- Profile bootstrap remains possible before email verification, but interaction and management writes require verification.

## Change and deployment discipline

Every authorization change must update Firestore Rules, Storage Rules, trusted Functions, client presentation gates, and emulator/unit tests together. Before deployment:

1. Run all Firestore and Storage emulator regression tests.
2. Review the exact rule and index diff against the intended Firebase project.
3. Export or back up production data where the rollout can affect availability or deletion.
4. Deploy Rules and indexes from the reviewed release commit.
5. Verify representative guest, user, owner/admin, and organization-role requests in production logs without using production user data destructively.
