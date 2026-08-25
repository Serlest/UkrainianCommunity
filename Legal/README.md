# UkrainianCommunity legal source of truth

This directory contains the release-controlled legal documents for the app and
its public website. The German text is the canonical legal text; the Ukrainian
text is the user-facing translation. Neither language may be published
independently.

Current published version: `2026.10`, effective 25 August 2026.

The operator identity, address and retention choices are filled. The public
notice-and-action and appeal workflow is implemented. Any future `{{...}}`
placeholder or item in `unresolvedReleaseBlocks` blocks publication.

The documents are operator-approved texts based on the product's implemented
data flows. Qualified review by an Austrian lawyer remains recommended and is
not represented as completed.

Run before every release:

```sh
python3 scripts/validate_legal_documents.py
python3 scripts/validate_release_configuration.py
python3 scripts/advise_legal_changes.py
```

See `Docs/LegalChangeMatrix.md` for the mandatory update map.
