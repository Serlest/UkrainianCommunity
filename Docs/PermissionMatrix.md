# Permission Matrix

This document is the source of truth for the current permission policy. It must be updated before changing Firestore rules, Storage rules, `PermissionService`, Cloud Functions, repositories, or UI access gates.

## Active Roles

- Public / Guest: unauthenticated users or users without an active authenticated session.
- Registered active user: authenticated users whose account is usable. Active and warned states are considered usable; suspended, banned, blocked, and deactivated states are restricted.
- Owner: platform-level owner with `globalRole == owner`. Owner is the only active app-wide privileged role.
- Guide manager: active user with guide management access through Owner role or `canManageGuide == true`.
- Organization owner: user listed as `ownerId` on an organization document.
- Organization admin: user listed in `adminIds` on an organization document.
- Organization moderator: user listed in `moderatorIds` on an organization document.

## Planned Platform Roles

Planned platform roles are documented here for future implementation only. They must not grant authorization until their implementation phase is explicitly started, tested, and completed.

### App Admin

Status: Planned. Not implemented.

Relationship to Owner: App Admin is below Owner. Owner can perform every App Admin action. App Admin cannot create, change, replace, transfer, downgrade, or become Owner. App Admin cannot change this permission matrix or define new platform permissions.

Responsibilities:

- Manage operational admin queues that do not require Owner-only authority.
- Manage Guide content workflows within the limits defined by the future implementation.
- Manage Featured Banners.
- Manage Feedback and report handling.
- Manage Organization Requests.
- Manage Users except Owner accounts.

Allowed actions:

- Manage Guide articles and workflow actions assigned to App Admin.
- Create, update, archive, and delete Featured Banners if future rules permit it.
- Read and respond to Feedback.
- Review and resolve Reports.
- Review, approve, reject, or request revision for Organization Requests if future Cloud Functions permit it.
- Manage user enforcement for non-Owner users, including warnings, suspensions, and account status changes if future rules permit it.

Forbidden actions:

- Cannot transfer Owner.
- Cannot change Owner.
- Cannot assign Owner.
- Cannot remove Owner.
- Cannot become Owner through any client action.
- Cannot manage the Permission Matrix.
- Cannot define, grant, or change platform permissions outside the implemented App Admin scope.
- Cannot bypass Cloud Functions for sensitive role or workflow changes.

### App Moderator

Status: Planned. Not implemented.

Relationship to Owner: App Moderator is below Owner and below App Admin. Owner can perform every App Moderator action. App Moderator has moderation-only authority and must not receive administrative or role-management powers.

Responsibilities:

- Moderate community safety queues.
- Moderate comments.
- Moderate reports.
- Moderate feedback.
- Moderate pending content assigned to moderation queues.

Allowed actions:

- Review and moderate comments.
- Review and moderate reports.
- Review and moderate feedback where future policy allows moderator handling.
- Review pending content and apply limited moderation outcomes if future rules permit it.

Forbidden actions:

- Cannot manage users.
- Cannot manage Featured Banners.
- Cannot manage organization roles.
- Cannot manage platform roles.
- Cannot manage permissions.
- Cannot manage organizations globally.
- Cannot transfer, change, assign, remove, or become Owner.
- Cannot bypass Cloud Functions for sensitive workflow changes.

## Deferred Roles

- App Admin: not implemented yet. Persisted or legacy values must not grant authorization.
- App Moderator: not implemented yet. Persisted or legacy values must not grant authorization.

Do not implement App Admin or App Moderator until Owner access is stable and verified across Firestore, Storage, Swift UI gates, repositories, and Cloud Functions.

## Core Rule

Owner must have full access to every owner/admin function.

If Firestore or Storage rules allow an Owner action but the UI hides it, that is a bug. If the UI shows an Owner action but Firestore, Storage, or Cloud Functions deny it, that is a bug. `PermissionService` should express the UI policy, while Firebase rules and Cloud Functions remain the final security layer.

## Permission Design Principles

- Owner always has full access.
- If rules allow Owner but UI blocks it, that is a bug.
- If UI allows Owner but rules deny it, that is a bug.
- `PermissionService` is the UI authority.
- Firestore Rules are the final security authority for document access.
- Storage Rules are the final security authority for file access.
- Cloud Functions own sensitive role changes and workflow transitions.
- Views should not directly check roles when `PermissionService` can answer.
- App Admin and App Moderator are documented but not implemented.
- Planned roles must remain non-authorizing until their implementation phase is explicitly started.

## Matrix

| Area | Public / Guest | Registered active user | Owner | Guide manager | Organization owner | Organization admin | Organization moderator |
|---|---|---|---|---|---|---|---|
| Users | No private user access. | Read and update own allowed profile fields; deactivate own non-owner account. | Read users, update account status/block fields, delete other users, manage user enforcement. | No special access. | No special access. | No special access. | No special access. |
| Public profiles | Read all public profiles. | Create/update/delete own public profile. | Create/update/delete public profiles. | No special access. | No special access. | No special access. | No special access. |
| Organizations | Read approved organizations. | Submit organization requests; read and revise own pending, needs-revision, or rejected requests. | Create, read, edit, approve/reject through functions where applicable, and delete organizations; manage organization media. | No special access. | Read and manage assigned organization, organization content, photos, and team roles allowed to org owner. | Read and edit organization info/content/photos where allowed. | Read and manage organization content/photos where allowed; no info edit if policy restricts info to owner/admin. |
| Organization roles | No access. | No access. | Manage organization role changes through Cloud Functions; transfer organization ownership. | No special access. | Manage admin/moderator membership through Cloud Functions where supported. | No role management. | No role management. |
| News | Read approved news. | Comment, like, bookmark, and view allowed content. | Read moderation queues, moderate/delete news, and manage permitted news actions. | No special access. | Create/edit organization news; delete organization news where org-owner delete policy applies. | Create/edit organization news. | Create/edit organization news. |
| Events | Read approved events. | Comment, like, bookmark, view, and register for eligible approved events. | Create/edit/delete events and read managed registrations where rules allow. | No special access. | Create/edit organization events; delete organization events where org-owner delete policy applies; read managed registrations. | Create/edit organization events; read managed registrations. | Create/edit organization events; read managed registrations. |
| Guide | Read approved and published articles. | No management access. | Manage guide articles and approve/publish/archive through the owner workflow. | Create/edit/read/delete managed guide articles; cannot approve, publish, or archive unless also Owner and permitted by workflow. | No special access. | No special access. | No special access. |
| Featured banners | Read active banners. | No management access. | Create, update, archive/deactivate, delete, and upload featured banner images. | No special access. | No special access. | No special access. | No special access. |
| Feedback / reports | No access. | Create feedback and report items; read and reply to own open feedback. | Read, reply to, update status, notify users about, and delete feedback/report items. | No special access. | No special access. | No special access. | No special access. |
| Comments | Read comments for readable approved parent content. | Create/edit own comments; delete own comments. | Moderate/delete comments across app-level content. | No special access. | Moderate comments on assigned organization content. | Moderate comments on assigned organization content. | Moderate comments on assigned organization content. |
| Audit logs | No access. | No access. | Read and create allowed audit log records; no update/delete. | No special access. | No special access. | No special access. | No special access. |
| Storage | Public reads for public content paths only. | Upload/update/delete own profile image; upload organization-request media where rules allow. | Manage app content images, featured banner images, app config banners, profile images, and organization media allowed to Owner. | No special access. | Manage assigned organization media, photos, and draft uploads. | Manage assigned organization media, photos, and draft uploads. | Manage assigned organization media, photos, and draft uploads. |

## Known Mismatches And Risks

- Owner direct events are allowed in Firestore rules, but hidden in `PermissionService.canCreateEvent(user:)`.
- Platform news creation is not available. Firestore news creation currently requires organization content, and app-side platform news creation is disabled.
- ID-only organization permission overloads return `false`. This prevents false-positive UI access, but can silently hide valid organization-scoped access when a view has not loaded the organization object.
- Guide managers can manage guide articles but cannot approve, publish, or archive unless they are also Owner and the workflow allows it.
- Reports are stored as feedback items with report type, not as a separate reports collection.
- Owner has a broad events update rule. This is useful for recovery but increases risk because structural field restrictions are weaker than in narrower update paths.
- Organization role policy is split: Firestore prevents direct client writes to role arrays, while Cloud Functions own role changes.
- Direct view checks of `globalRole.authorizationRole == .owner` duplicate policy outside `PermissionService`.

## Cleanup Principles

- `PermissionService` should be the only UI access gate.
- Views should not directly check `globalRole` where avoidable.
- Firestore rules are the final security layer for document access.
- Storage rules are the final security layer for file access.
- Cloud Functions own organization role changes and workflow transitions that require server authority.
- ID-only permission methods should be avoided or renamed to prevent misuse. Prefer object-based checks that can evaluate organization role arrays.
- Owner access must be stabilized before App Admin or App Moderator work starts.
- Legacy or deferred role values may remain readable for migration, but must not grant active authorization.

## Implementation Roadmap

### Phase 1: Documentation Only

Create and maintain this permission matrix. No code or rule changes.

### Phase 2: Centralize UI Gates

Replace direct view-level Owner checks with named `PermissionService` methods. Keep behavior unchanged unless a documented mismatch is being fixed.

### Phase 3: Align Owner UI With Rules

Ensure every Owner action allowed by Firestore, Storage, or Cloud Functions is reachable in the UI, and every visible Owner action is accepted by the backend security layer.

### Phase 4: Add Firebase Rules Tests

Add rule tests for Public / Guest, registered active user, restricted user, Owner, Guide manager, organization owner, organization admin, and organization moderator.

### Phase 5: Add PermissionService Tests

Add focused tests for role outcomes, organization-scoped access, guide access, Owner gates, and restricted account handling.

### Phase 6: Consider Deferred Roles

Only after Owner behavior is stable and tested, evaluate App Admin and App Moderator as new product roles. Do not grant partial authorization through legacy fields before this phase.

## Future Implementation Order

### Phase A: Owner Consistency Audit

Audit every Owner access path across `PermissionService`, views, Firestore rules, Storage rules, repositories, and Cloud Functions. Confirm every Owner action is either intentionally supported or explicitly deferred.

### Phase B: Owner Consistency Fixes

Fix mismatches where Owner is allowed by rules but blocked by UI, or allowed by UI but denied by rules. Keep changes tightly scoped to Owner stabilization.

### Phase C: PermissionService Cleanup

Move UI authorization decisions into named `PermissionService` methods. Remove or isolate direct view role checks. Avoid ID-only organization permission methods unless their limitation is explicit in the name.

### Phase D: Rules Tests

Add Firebase rules tests for the documented active roles, restricted account states, Owner access, organization-scoped roles, guide managers, feedback/report handling, comments, audit logs, and storage paths.

### Phase E: PermissionService Tests

Add Swift tests for `PermissionService` outcomes, including Owner, Guide manager, organization owner/admin/moderator, registered active users, restricted users, and planned-role non-authorization.

### Phase F: App Admin Implementation

Implement App Admin only after Owner behavior is stable and tested. Add rules, Cloud Functions, `PermissionService` gates, UI access, and tests in one complete module.

### Phase G: App Moderator Implementation

Implement App Moderator only after App Admin is stable or explicitly deferred. Add moderation-only permissions, UI gates, backend enforcement, and tests in one complete module.
