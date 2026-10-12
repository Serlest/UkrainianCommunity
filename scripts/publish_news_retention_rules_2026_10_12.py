#!/usr/bin/env python3
"""Publish aligned Terms and organization rules for 30-day news retention."""

import publish_legal_documents as publisher


publisher.ACTOR = "legal-2026-10-12-news-retention"
publisher.TARGETS = {
    "terms": ("2026.13", "2026.14"),
    "organizationRules": ("2026.10", "2026.11"),
}
publisher.PLAN_FORMAT = "uac-news-retention-rules-2026-10-12-v1"


if __name__ == "__main__":
    publisher.main()
