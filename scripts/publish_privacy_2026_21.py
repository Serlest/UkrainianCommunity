#!/usr/bin/env python3
"""Publish the banner-measurement privacy successor with guarded read-back."""

import publish_legal_documents as publisher


publisher.ACTOR = "privacy-2026-21-banner-measurement"
publisher.TARGETS = {"privacy": ("2026.20", "2026.21")}
publisher.PLAN_FORMAT = "uac-privacy-2026-21-banner-measurement-v1"


if __name__ == "__main__":
    publisher.main()
