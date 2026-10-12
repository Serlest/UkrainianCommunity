# UAC News scope coordination (prepared, inactive)

The news automation currently running in Codex continues to use its existing v2 progress and schedule. This package prepares a separate search state for the nine federal states and Austria-wide news without importing the old candidate backlog.

## State layout

- `source-registry.json`: one entry per canonical source URL with its assigned scopes. A source shared by several scopes is fetched once.
- `shared-source-state.json`: fetch observations for those unique sources.
- `scopes/<scope>.json`: separate source cursors and final candidate decisions for each of the ten scopes. All cursors begin as unverified (`null`). No pending editorial candidates are imported or stored here.
- `snapshots/<runId>.json`: immutable results of one shared source scan. `newsScopeBatch.mjs` selects the observations assigned to one scope without making another network request.

`prepareNewsScopes.mjs` previews the layout by default and writes it only with `--write`. It never edits the v2 file. Two historical RIS query URLs with no assigned scope are retained in the registry as inactive review items.

`newsSharedScan.mjs` also previews by default. `--run` performs a real network scan and creates a snapshot; it is not part of any active automation yet. A second scan with the same run ID is refused. Its result is source discovery, not a publication decision or proof of complete source coverage. Article relevance, date, official evidence, and territory still require editorial checks.

The existing `contentPublishingLocalBridge.mjs` remains the only publisher. It already uses deterministic IDs and Firestore identity locks with atomic create-only writes. News publication must still hold the shared `content-work.lock` while invoking the bridge, then verify the separate production read-back before recording success. Search does not hold that lock.

## One-pass candidate decisions

`newsScopeDecisions.mjs <root> <candidate-batch.json>` previews a scope's decision batch. Once the new system is activated, `--apply` atomically records its technical trace. The input lists every article candidate taken from the current discovery pass and one decision per canonical URL. Only `published` and `rejected` are terminal. A rejected candidate needs a concrete reason. A published candidate needs a matching verified production read-back receipt; the recorder checks its ID, approved status, territory, and `allVerified` result. Missing, duplicate, or pending decisions fail the batch; no editorial queue or draft is created.

Discovery must distinguish article candidates from menus, images, and other non-content links before handing the batch to the recorder. A partial source fetch or uncertain publication is a **partial/failed run**, not a successful empty pass. Keep the affected source cursor unchanged and reconcile any uncertain production write before the next attempt. The scope state contains only final URL decisions and a small run summary; full article text and images are not copied into it. Old v2 pending records remain historical and are never imported into v3. The active nationwide chat has separately been instructed not to process that old backlog.

The nine regional chats exist but have no search or publication schedule yet. The v3 layout remains `prepared_not_active` until the later switch and verification steps.
