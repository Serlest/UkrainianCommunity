# UkrainianCommunity legal source of truth

This directory contains the release-controlled legal drafts for the app and its
public website. The German text is the canonical legal draft; the Ukrainian text
is the user-facing translation. Neither language may be published independently.

Current draft version: `2026.10`

The operator identity, address and retention choices are filled. Publication is
still blocked by the items in `legal-manifest.json`, especially qualified
Austrian legal review and the public notice-and-action/appeal workflow. Any
future `{{...}}` placeholder also blocks publication.

The documents are engineering drafts based on the product's implemented data
flows. They are not a substitute for review by an Austrian lawyer.

Run before every release:

```sh
python3 scripts/validate_legal_documents.py
python3 scripts/validate_release_configuration.py
python3 scripts/advise_legal_changes.py
```

See `Docs/LegalChangeMatrix.md` for the mandatory update map.
