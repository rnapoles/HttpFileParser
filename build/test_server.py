#!/usr/bin/env python3
"""Tiny HTTP server for the end-to-end check of RunHttpFile (Python standard library only).

POST /login        -> 200, header X-AuthToken: tok-123, body {"id":7}
GET  /users/<id>   -> 200, body {"user":<id>,"auth":"<Authorization header>"}
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status, payload, headers=None):
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        if self.path == "/login":
            self._send(200, {"id": 7}, {"X-AuthToken": "tok-123"})
        else:
            self._send(404, {"error": "not found"})

    def do_GET(self):
        if self.path.startswith("/users/"):
            self._send(200, {"user": int(self.path.rsplit("/", 1)[1]),
                             "auth": self.headers.get("Authorization", "")})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        sys.stderr.write("[server] " + fmt % args + "\n")


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8099), Handler).serve_forever()
