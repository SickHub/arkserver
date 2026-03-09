#!/usr/bin/env python3
"""Lightweight HTTP health server that validates ARK RCON connectivity via arkmanager."""
import os
import subprocess
import json
import sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

LISTEN_PORT = int(os.environ.get("HEALTH_SERVER_PORT", "8080"))

def check_rcon():
    """Run arkmanager rconcmd ListPlayers — returns True only on success."""
    try:
        result = subprocess.run(
            ["arkmanager", "rconcmd", "ListPlayers"],
            capture_output=True, timeout=15,
        )
        if result.returncode != 0:
            print(
                f"RCON check failed rc={result.returncode} "
                f"stderr={result.stderr.decode(errors='ignore').strip()} "
                f"stdout={result.stdout.decode(errors='ignore').strip()}",
                file=sys.stderr,
            )
            return False
        return True
    except Exception as e:
        print(f"RCON check failed: {e}", file=sys.stderr)
        return False

class Handler(BaseHTTPRequestHandler):
    def log_request(self, *args, **kwargs):
        pass  # suppress request logs

    def do_GET(self):
        if self.path == "/healthz":
            healthy = check_rcon()
            status = 200 if healthy else 503
            body = json.dumps({
                "status": "healthy" if healthy else "unhealthy",
            })
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/livez":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"alive"}')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    print(f"Health server listening on :{LISTEN_PORT}")
    server.serve_forever()
