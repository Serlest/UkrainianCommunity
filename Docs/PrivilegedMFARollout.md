# Privileged TOTP MFA rollout

This runbook enables TOTP protection for platform owners and admins without
locking existing accounts or older app builds out of production.

## Safety model

- Firebase Authentication TOTP support is enabled at project level, but it is
  not made globally mandatory.
- Enforcement is per account through the server-owned user field
  `requiresMultiFactorAuth`.
- A missing or false field preserves existing behaviour.
- The field only affects active platform `owner` and `admin` accounts.
- The client cannot create, change or remove the field through Firestore Rules.
- The activation callable accepts only a verified, active owner/admin whose
  current Firebase token contains `firebase.sign_in_second_factor == "totp"`.
- Once activated, Firestore Rules, Storage Rules and Functions require a TOTP
  sign-in session for that account.

## Prerequisites

1. Confirm the project billing account, then upgrade Firebase Authentication to
   Identity Platform and enable TOTP MFA. Treat the product upgrade as a
   permanent production decision: Google publishes an initialization API but
   no matching downgrade operation. On Blaze, email/social authentication has a
   no-cost tier of 50,000 monthly active users before usage charges.
2. Keep the project-level MFA mode optional; never switch directly to a global
   mandatory mode.
3. Confirm at least two recoverable privileged accounts exist and are controlled
   through different trusted identities/devices. The recovery identity must not
   receive Project Owner or Editor. Grant only the checked-in custom role
   `uacMfaRecoveryOperator`, containing Firestore entity read/update, Firebase
   Auth user read/update, and service usage.
4. Deploy `activatePrivilegedMFAProtection` and read back its active revision.
5. Deploy the matching Firestore and Storage Rules and confirm their release
   hashes. With no opted-in users these rules are backward-compatible.
6. Test enrollment, sign-out, password plus TOTP sign-in, callable activation
   and one protected owner action on a disposable privileged account.
7. Only then change `AuthSecurityRollout.allowsTOTPEnrollment` to `true` and
   distribute a compatible TestFlight build.

## Per-account activation

For each owner/admin separately:

1. Open Account Security in a compatible build and enroll an authenticator.
2. Sign out. Enrollment alone is not proof that the current session used TOTP.
3. Sign in again with password and the authenticator code.
4. Activate privileged protection from the blocking security screen.
5. Read back the user document and confirm:
   - `requiresMultiFactorAuth == true`;
   - `multiFactorAuthRequiredMethod == "totp"`;
   - `multiFactorAuthRequiredAt` is present.
6. Confirm a token from a password-only session is rejected by a protected
   Firestore path, Storage path and callable.
7. Confirm a fresh password plus TOTP session succeeds exactly once.
8. Observe Functions and Rules denials before proceeding to the next account.

Do not activate the last recovery owner until another protected owner has
completed the full read-back and recovery test.

## Recovery and rollback

- If an account loses its authenticator, sign Firebase CLI in with the separate
  recovery Google Account and run a dry-run first:

  ```sh
  npm run auth:recover-privileged-mfa -- \
    --project=ukrainiancommunity-dbd5f \
    --target-email=owner@example.com \
    --reason="Lost authenticator; identity verified through the recovery procedure"
  ```

  Apply only with the exact project, email, UID, factor count and requirement
  state printed by that fresh dry-run. The command clears the server-owned
  Firestore requirement first, removes all enrolled Auth factors, revokes
  existing sessions, then performs a full read-back. It records actor, reason
  and server timestamp on the affected user. Output redacts email addresses and
  never prints access tokens or factor secrets.
- The recovery operator must verify its Firebase CLI login and run the dry-run
  before any owner is activated. Client Rules intentionally cannot perform this
  rollback.
- Keep TOTP enabled at project level while any user has an enrolled TOTP factor.
- A client rollout can be paused by returning
  `AuthSecurityRollout.allowsTOTPEnrollment` to false, but already protected
  accounts still require TOTP by design.
- Do not delete the callable or weaken Rules as an account recovery shortcut.
- Record the actor, affected user, reason, timestamp and verification evidence
  for every recovery or rollback.

## Release evidence

Retain the project MFA configuration read-back, callable revision, Rules release
hashes, disposable-account results, per-account activation read-backs and a
24-hour error/denial observation window with the release evidence for the build.
