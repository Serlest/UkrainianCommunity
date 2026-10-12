#!/usr/bin/env python3
"""Publish the mandatory Privacy acknowledgement successor with audit read-back."""

import publish_legal_documents as publisher


publisher.ACTOR = "legal-2026-10-12-consent-recovery"
publisher.TARGETS = {"privacy": ("2026.18", "2026.19")}
publisher.PLAN_FORMAT = "uac-privacy-2026-19-mandatory-acknowledgement-v1"


if __name__ == "__main__":
    publisher.main()
