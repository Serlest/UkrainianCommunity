#!/usr/bin/env python3
"""Publish the 30-day news retention privacy successor with read-back."""

import publish_legal_documents as publisher


publisher.ACTOR = "privacy-2026-20-news-retention"
publisher.TARGETS = {"privacy": ("2026.19", "2026.20")}
publisher.PLAN_FORMAT = "uac-privacy-2026-20-news-retention-v1"


if __name__ == "__main__":
    publisher.main()
