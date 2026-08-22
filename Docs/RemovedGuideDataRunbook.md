# Removed Guide Data Runbook

The application no longer exposes Guide functionality. Historical Firebase data must be inventoried and backed up before it is removed from production.

## Read-only inventory

Authenticate with an account that can read the production Firebase project, then run:

```bash
cd functions
npm ci
npm run audit:removed-guide-data -- \
  --project=<firebase-project-id> \
  --storage-bucket=<firebase-storage-bucket>
```

The command only reads data. It reports:

- Guide root collections, bookmarks, and recent views;
- legacy role fields;
- legacy notifications and featured banners, including their document IDs;
- known non-Guide banner aliases (`announcement`, `emergency`, and `partner`) that must be normalized before strict banner validation is deployed;
- Guide markers in current analytics aggregate documents;
- the former Guide banner object and per-banner `featuredBanners/<id>/hero.jpg` objects in Cloud Storage;
- historical system and audit logs, including Guide targets, operations, and actor roles.

Counts for notifications and banners can overlap because one document may match more than one legacy field.
Nested user data is enumerated through user document references, including missing parent
documents, so the audit does not depend on collection-group indexes. The scan still incurs
document reads for recent views and notifications plus aggregate reads for bookmarks.
Historical `activeRegionKeys` are untyped and cannot prove whether a region came only from
Guide traffic. The inventory reports how many daily documents contain those keys; treat their
`activeRegions` value as potentially contaminated until the affected retention window expires
or a reviewed migration resets it from trusted source data.

The inventory command rejects `--execute` and does not contain deletion logic.

## Safe rollout order

1. Run the inventory and export Firestore before changing production data.
2. Confirm that no supported App Store or TestFlight build still sends `canManageGuide: false`
   during registration. The restrictive Rules reject the retired field entirely, so deploy a
   forced client update or a separately reviewed temporary `false`-only compatibility rule if
   an older build must remain usable. Never permit `true`.
3. Deactivate every Guide banner with a reviewed, idempotent migration; do not repurpose unsupported Guide values in the client.
4. Normalize known banner aliases before strict Rules are deployed: map `announcement` and
   `emergency` to `none`, and map `partner` to `externalURL` only when it has a valid URL;
   otherwise deactivate it. Verify that no active banner retains any legacy action value.
5. Deploy the client/backend changes, then the restrictive Firestore and Storage Rules and the reduced index configuration from the same reviewed release.
6. Keep historical logs intact and perform irreversible data deletion only after the cleanup gate below is approved.

The new Rules intentionally let the App Owner inspect and deactivate a legacy featured banner, but deny public reads, reactivation, partial or complete repurposing, deletion, and creation with retired values. Deactivating legacy banners before the Rules deployment prevents an unsupported active document from invalidating a public active-banner query.

## Production cleanup gate

Do not delete data until all of the following are complete:

1. Export Firestore and record the export location.
2. Save the inventory output with the release evidence.
3. Confirm whether any supported App Store or TestFlight build still depends on the removed feature.
4. Review the planned deletion counts and receive explicit approval for the irreversible cleanup.
5. Use an idempotent migration with a dry-run and exact before/after counts.
6. Re-run the inventory and verify that removable counts are zero.

Historical `systemLogs` and `auditLogs` must not be deleted by the feature cleanup.
`systemLogs` follow the scheduled retention matrix. The repository currently has no
automatic retention job for `auditLogs`; define and legally review that separate policy
before any audit-log deletion is implemented.

After the Functions deployment, verify that the removed `assignGuideEditor` and `removeGuideEditor` callables no longer exist in the deployed project; removing exports from source code alone may not remove already deployed functions.
