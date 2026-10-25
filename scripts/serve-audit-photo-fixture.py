#!/usr/bin/env python3
"""Disposable loopback image transport: fail, enable, retry, independently read counts.

Only synthetic pixels. No Firebase credentials or production network access.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import struct
import zlib

state = {"enabled": False, "failed": 0, "succeeded": 0}

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

row = b"\0" + bytes([25, 75, 145]) * 256 + bytes([255, 220, 40]) * 256
image = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 512, 512, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(row * 512)) + chunk(b"IEND", b"")

class Handler(BaseHTTPRequestHandler):
    def respond(self, code, body, mime="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path == "/reset":
            state.update(enabled=False, failed=0, succeeded=0)
        elif self.path == "/enable":
            state["enabled"] = True
        else:
            self.respond(404, b"{}"); return
        self.respond(200, json.dumps(state).encode())

    def do_GET(self):
        if self.path == "/status":
            self.respond(200, json.dumps(state).encode())
        elif self.path == "/audit-organization-photo.png":
            key = "succeeded" if state["enabled"] else "failed"
            state[key] += 1
            self.respond(200 if state["enabled"] else 503, image if state["enabled"] else b"{}", "image/png" if state["enabled"] else "application/json")
        else:
            self.respond(404, b"{}")

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 29555), Handler).serve_forever()
