# Owner Role Setup

## Current Firebase User UID

`m69BEe5byKUFRG1qpuIi0QB4iEq2`

## Manual Promotion to Owner in Firebase Console

1. Open Firebase Console.
2. Open your project.
3. Go to **Firestore Database**.
4. Open the `users` collection.
5. Find and open the document with this ID:

   `m69BEe5byKUFRG1qpuIi0QB4iEq2`

6. Change the field `role` from:

   `user`

   to:

   `owner`

7. Make sure the field `isBlocked` stays:

   `false`

8. Save the document.
9. Restart the app.

## Expected Result in the App

After restart:

- Profile should show the `owner` role.
- `Admin tools` should become visible in the Profile screen.
- `Moderation tools` should become visible in the Profile screen.

## Important Warning

- The `owner` role must never be assignable by normal app users.
- Final production Firestore Rules must protect all role changes.
- Only trusted admin/owner-level backend rules should allow promotion to `owner`.
