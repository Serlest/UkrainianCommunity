# UAC News scope coordination (prepared, inactive)

The news automation currently running in Codex continues to use its existing v2 progress and schedule. This package prepares a separate search state for the nine federal states and Austria-wide news without importing the old candidate backlog.

## State layout

- `source-registry.json`: one entry per canonical source URL with its assigned scopes. A source shared by several scopes is fetched once.
- `shared-source-state.json`: fetch observations for those unique sources.
- `scopes/<scope>.json`: separate source cursors and final candidate decisions for each of the ten scopes. All cursors begin as unverified (`null`).
- `snapshots/<runId>.json`: immutable results of one shared source scan. `newsScopeBatch.mjs` selects the observations assigned to one scope without making another network request.

`prepareNewsScopes.mjs` previews the layout by default and writes it only with `--write`. It never edits the v2 file. Two historical RIS query URLs with no assigned scope are retained in the registry as inactive review items.

`newsSharedScan.mjs` also previews by default. `--run` performs a real network scan and creates a snapshot; it is not part of any active automation yet. A second scan with the same run ID is refused. Its result is source discovery, not a publication decision or proof of complete source coverage. Article relevance, date, official evidence, and territory still require editorial checks.

The existing `contentPublishingLocalBridge.mjs` remains the only publisher. It already uses deterministic IDs and Firestore identity locks with atomic create-only writes. News publication must still hold the shared `content-work.lock` while invoking the bridge, then verify the separate production read-back before recording success. Search does not hold that lock.

No new scope chat or schedule is active until the later coordination steps are completed and verified.
