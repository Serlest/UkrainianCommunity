#!/usr/bin/env python3
"""Publish only the Privacy 2026.19 web page; preserve every other live file."""

import publish_legal_hosting as publisher


publisher.KINDS = ("privacy",)
publisher.PATHS = {"privacy": "/privacy/index.html"}
publisher.PLAN_FORMAT = "uac-privacy-hosting-2026-19-v1"
publisher.legal.TARGETS = {"privacy": ("2026.18", "2026.19")}


if __name__ == "__main__":
    publisher.main()
