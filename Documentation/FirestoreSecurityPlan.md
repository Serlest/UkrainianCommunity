# Firestore Security Plan

## Planned Collections

- `users`
- `news`
- `events`
- `organizations`
- `guideArticles`
- `feedback`
- `comments`
- `registrations`
- `likes`

## Roles

- `user`
- `moderator`
- `admin`
- `owner`

## Security Principle

Firestore Rules are the real security layer. SwiftUI checks are not enough.

Client-side role checks are useful for UI and UX, but they do not protect data by themselves. Every important permission must also be enforced in Firestore Security Rules.

## Planned Access Rules

### Public Content

- Users can read public content from `news`, `events`, `organizations`, and `guideArticles`.
- Public read access for `comments` can be allowed where the related content is public.

### Users

- Users can like content and register for events.
- Users can later edit only their own profile fields in `users/{userId}`.
- Users must not be able to change their own role.
- Users must not be able to unblock themselves if blocked by admins or owner.

### Moderators

- Moderators can create and edit content in:
  - `news`
  - `events`
  - `organizations`
  - `guideArticles`
- Moderators should not manage user roles.
- Moderators should not have full access to all user documents.

### Admins

- Admins have moderator rights.
- Admins can manage moderators.
- Admins can block users.
- Admins should not be allowed to promote themselves or others to `owner`.

### Owner

- Owner has full access to all content.
- Owner can manage all roles.
- Owner can manage all users.
- Owner can block or unblock users.

## Collection Notes

### `users`

- Stores user profile and role data.
- Only the user should later edit safe personal fields.
- Role changes should be restricted to `admin` and `owner`, with final owner-level control over the highest privileges.

### `news`

- Readable by users if public/published.
- Writable by `moderator`, `admin`, and `owner`.

### `events`

- Readable by users if public/published.
- Writable by `moderator`, `admin`, and `owner`.

### `organizations`

- Readable by users if public/published.
- Writable by `moderator`, `admin`, and `owner`.

### `guideArticles`

- Readable by users if public/published.
- Writable by `moderator`, `admin`, and `owner`.

### `feedback`

- Readable by the submitting user and privileged app administrators.
- Writable by authenticated users for their own submissions.
- Status and review lifecycle should be restricted to privileged roles.

### `comments`

- Read rules should follow the visibility of the parent content.
- Write rules can later allow authenticated users, with moderation or ownership checks for edits/deletes.

### `registrations`

- Users can create and manage only their own event registrations.
- Moderators, admins, and owner may later get read access for event management.

### `likes`

- Users can create and remove only their own likes.
- Users must not modify likes that belong to another user.

## Recommended Rule Strategy

- Use `request.auth != null` for authenticated actions.
- Read the caller role from `users/{uid}`.
- Separate public reads from privileged writes.
- Restrict role mutation to trusted roles only.
- Treat blocked users as denied for write actions.
- Keep Firestore Rules aligned with app role logic, but never depend on the app alone for enforcement.
