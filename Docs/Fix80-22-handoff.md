# Fix80-22 organization request review handoff

## Shared contract

The three review callables now accept two optional, backward-compatible fields:

- `operationId`: opaque client-generated identifier, at most 200 characters and without `/`.
- `expectedRevision`: the exact Firestore `updatedAt` revision encoded as `seconds:nanoseconds`.

Current iOS sends both fields. Older clients remain accepted, but they only receive the transaction state guard; they cannot reconcile an uncertain response as a successful retry.

The backend stores completed review receipts in the existing `organizationMutationReceipts` collection with the existing 30-day `expiresAt` retention path. No Firestore client rules or index changes are required.

## Release dependency

Deploy `approveOrganization`, `requestOrganizationRevision`, and `rejectOrganization` before distributing the iOS build. The current deployed callables may ignore the new optional fields, so the iOS retry journal only becomes end-to-end idempotent after that deployment.

No localization keys were added. No common repository protocol change is required.

## Validation still required by the coordinator

- Functions unit and emulator integration tests, including simultaneous revision/reject and same-operation retry.
- iOS build and runtime verification for offline/timeout retry, a queue larger than 100 requests, the dedicated search/sort controls, and organization action rows at default and accessibility text sizes.
- Deployment and production read-back remain separate release steps.
