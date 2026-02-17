#!/usr/bin/env python3
"""
Local webhook test server for ControllerKeys HTTP request feature testing.

This server simulates various webhook endpoints and logs all incoming requests
for verification. It can also simulate error conditions for testing error handling.

Usage:
    python3 webhook_server.py [--port PORT]

Endpoints:
    POST /webhook          - Standard webhook (201 response)
    GET  /webhook          - GET webhook (200 response)
    PUT  /webhook          - PUT webhook (200 response)
    DELETE /webhook        - DELETE webhook (204 response)
    PATCH /webhook         - PATCH webhook (200 response)

    POST /echo             - Echoes back the request as JSON (like httpbin)
    POST /slow             - Responds after 5 second delay (timeout testing)
    POST /error/:code      - Returns specified HTTP error code

    GET  /requests         - Returns list of all captured requests
    DELETE /requests       - Clears captured requests
    GET  /health           - Health check endpoint
"""

import argparse
import json
import threading
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional
from urllib.parse import urlparse, parse_qs


@dataclass
class CapturedRequest:
    """Represents a captured HTTP request for later verification."""
    timestamp: str
    method: str
    path: str
    query_params: dict
    headers: dict
    body: Optional[str]
    content_type: Optional[str]


class RequestStore:
    """Thread-safe storage for captured requests."""

    def __init__(self):
        self._requests: list[CapturedRequest] = []
        self._lock = threading.Lock()

    def add(self, request: CapturedRequest):
        with self._lock:
            self._requests.append(request)
            # Keep only last 100 requests
            if len(self._requests) > 100:
                self._requests = self._requests[-100:]

    def get_all(self) -> list[dict]:
        with self._lock:
            return [asdict(r) for r in self._requests]

    def clear(self):
        with self._lock:
            self._requests.clear()

    def find_by_path(self, path: str) -> list[dict]:
        with self._lock:
            return [asdict(r) for r in self._requests if r.path == path]


# Global request store
request_store = RequestStore()


class WebhookHandler(BaseHTTPRequestHandler):
    """HTTP request handler for webhook testing."""

    # Suppress default logging
    def log_message(self, format, *args):
        pass

    def _get_body(self) -> Optional[str]:
        """Read request body if present."""
        content_length = self.headers.get('Content-Length')
        if content_length:
            return self.rfile.read(int(content_length)).decode('utf-8')
        return None

    def _capture_request(self) -> CapturedRequest:
        """Capture and store the incoming request."""
        parsed = urlparse(self.path)
        body = self._get_body()

        request = CapturedRequest(
            timestamp=datetime.now().isoformat(),
            method=self.command,
            path=parsed.path,
            query_params=parse_qs(parsed.query),
            headers=dict(self.headers),
            body=body,
            content_type=self.headers.get('Content-Type')
        )

        request_store.add(request)
        self._log_request(request)
        return request

    def _log_request(self, request: CapturedRequest):
        """Pretty print the request to console."""
        print(f"\n{'='*60}")
        print(f"[{request.timestamp}] {request.method} {request.path}")
        print(f"{'='*60}")

        if request.query_params:
            print(f"Query: {json.dumps(request.query_params, indent=2)}")

        print("Headers:")
        for key, value in request.headers.items():
            # Truncate long header values
            display_value = value[:80] + "..." if len(value) > 80 else value
            print(f"  {key}: {display_value}")

        if request.body:
            print(f"Body ({len(request.body)} bytes):")
            try:
                # Try to pretty-print JSON
                parsed = json.loads(request.body)
                print(f"  {json.dumps(parsed, indent=2)}")
            except json.JSONDecodeError:
                # Print raw body (truncated)
                display_body = request.body[:500] + "..." if len(request.body) > 500 else request.body
                print(f"  {display_body}")

        print()

    def _send_json(self, status: int, data: dict):
        """Send a JSON response."""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _send_empty(self, status: int):
        """Send an empty response."""
        self.send_response(status)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

    def _handle_webhook(self, default_status: int = 200):
        """Handle standard webhook requests."""
        request = self._capture_request()
        self._send_json(default_status, {
            "status": "received",
            "method": request.method,
            "path": request.path,
            "timestamp": request.timestamp
        })

    def _handle_echo(self):
        """Echo back the request details (like httpbin)."""
        request = self._capture_request()

        # Parse body as JSON if possible
        json_body = None
        if request.body:
            try:
                json_body = json.loads(request.body)
            except json.JSONDecodeError:
                pass

        self._send_json(200, {
            "method": request.method,
            "url": request.path,
            "args": request.query_params,
            "headers": request.headers,
            "data": request.body,
            "json": json_body,
            "origin": self.client_address[0]
        })

    def _handle_slow(self):
        """Simulate a slow response for timeout testing."""
        request = self._capture_request()
        print("  [Delaying response for 5 seconds...]")
        time.sleep(5)
        self._send_json(200, {
            "status": "delayed_response",
            "delay_seconds": 5
        })

    def _handle_error(self, code: int):
        """Return a specific error code."""
        request = self._capture_request()

        error_messages = {
            400: "Bad Request",
            401: "Unauthorized",
            403: "Forbidden",
            404: "Not Found",
            500: "Internal Server Error",
            502: "Bad Gateway",
            503: "Service Unavailable"
        }

        self._send_json(code, {
            "error": error_messages.get(code, "Error"),
            "code": code
        })

    def _handle_requests_list(self):
        """Return list of captured requests."""
        self._send_json(200, {
            "requests": request_store.get_all(),
            "count": len(request_store.get_all())
        })

    def _handle_requests_clear(self):
        """Clear captured requests."""
        request_store.clear()
        self._send_json(200, {"status": "cleared"})

    def _handle_health(self):
        """Health check endpoint."""
        self._send_json(200, {
            "status": "healthy",
            "server": "ControllerKeys Webhook Test Server",
            "captured_requests": len(request_store.get_all())
        })

    def _route_request(self):
        """Route the request to the appropriate handler."""
        parsed = urlparse(self.path)
        path = parsed.path

        # Health check
        if path == "/health":
            return self._handle_health()

        # Request inspection endpoints
        if path == "/requests":
            if self.command == "GET":
                return self._handle_requests_list()
            elif self.command == "DELETE":
                return self._handle_requests_clear()

        # Echo endpoint (like httpbin)
        if path == "/echo":
            return self._handle_echo()

        # Slow endpoint for timeout testing
        if path == "/slow":
            return self._handle_slow()

        # Error simulation
        if path.startswith("/error/"):
            try:
                code = int(path.split("/")[-1])
                return self._handle_error(code)
            except ValueError:
                return self._handle_error(400)

        # Standard webhook endpoints
        if path == "/webhook" or path.startswith("/webhook/"):
            if self.command == "POST":
                return self._handle_webhook(201)
            elif self.command == "DELETE":
                self._capture_request()
                return self._send_empty(204)
            else:
                return self._handle_webhook(200)

        # Default: capture and respond OK
        return self._handle_webhook(200)

    def do_GET(self):
        self._route_request()

    def do_POST(self):
        self._route_request()

    def do_PUT(self):
        self._route_request()

    def do_DELETE(self):
        self._route_request()

    def do_PATCH(self):
        self._route_request()

    def do_OPTIONS(self):
        """Handle CORS preflight requests."""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-Key')
        self.end_headers()


def run_server(port: int = 8765):
    """Start the webhook test server."""
    server = HTTPServer(('localhost', port), WebhookHandler)

    print(f"""
╔══════════════════════════════════════════════════════════════╗
║         ControllerKeys Webhook Test Server                   ║
╠══════════════════════════════════════════════════════════════╣
║  Server running on: http://localhost:{port:<5}                  ║
╠══════════════════════════════════════════════════════════════╣
║  Endpoints:                                                  ║
║    POST   /webhook       Standard webhook (201)              ║
║    GET    /webhook       GET webhook (200)                   ║
║    PUT    /webhook       PUT webhook (200)                   ║
║    DELETE /webhook       DELETE webhook (204)                ║
║    PATCH  /webhook       PATCH webhook (200)                 ║
║                                                              ║
║    POST   /echo          Echo request back (like httpbin)    ║
║    POST   /slow          5-second delay (timeout testing)    ║
║    POST   /error/:code   Return specific HTTP error          ║
║                                                              ║
║    GET    /requests      List captured requests              ║
║    DELETE /requests      Clear captured requests             ║
║    GET    /health        Health check                        ║
╠══════════════════════════════════════════════════════════════╣
║  Press Ctrl+C to stop                                        ║
╚══════════════════════════════════════════════════════════════╝
""")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.shutdown()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ControllerKeys Webhook Test Server")
    parser.add_argument("--port", "-p", type=int, default=8765, help="Port to listen on (default: 8765)")
    args = parser.parse_args()

    run_server(args.port)
