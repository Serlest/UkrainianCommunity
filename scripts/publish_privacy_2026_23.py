#!/usr/bin/env python3
"""Publish the operator-requested 30-day event-retention privacy successor."""
import publish_legal_documents as publisher

publisher.ACTOR = "privacy-2026-23-event-retention"
publisher.TARGETS = {"privacy": ("2026.22", "2026.23")}
publisher.PUBLICATION_DATE = "2026-10-29"
publisher.PLAN_FORMAT = "uac-privacy-2026-23-event-retention-v1"

if __name__ == "__main__":
    publisher.main()
