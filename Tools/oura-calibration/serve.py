#!/usr/bin/env python3
import argparse
import json
import mimetypes
import os
import threading
import time
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent
DEFAULT_CAPTURE_ROOT = ROOT / "captures"


class CaptureStore:
	def __init__(self, capture_root: Path):
		self.capture_root = capture_root
		self.capture_root.mkdir(parents=True, exist_ok=True)
		stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
		self.capture_dir = self.capture_root / stamp
		self.capture_dir.mkdir(parents=True, exist_ok=False)
		self.events_path = self.capture_dir / "targets.ndjson"
		self.metadata_path = self.capture_dir / "metadata.json"
		self.lock = threading.Lock()
		self.write_metadata({
			"capture_dir": str(self.capture_dir),
			"created_at": datetime.now(timezone.utc).isoformat(),
		})

	def write_metadata(self, metadata):
		self.metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

	def append_event(self, event):
		server_event = dict(event)
		server_event["serverReceivedIso"] = datetime.now(timezone.utc).isoformat()
		server_event["serverReceivedUnix"] = time.time()
		with self.lock:
			with self.events_path.open("a", encoding="utf-8") as handle:
				handle.write(json.dumps(server_event, separators=(",", ":")) + "\n")
		return server_event


class CalibrationHandler(BaseHTTPRequestHandler):
	store = None

	def log_message(self, fmt, *args):
		return

	def do_GET(self):
		parsed = urlparse(self.path)
		if parsed.path == "/api/status":
			self.send_json({
				"captureDir": str(self.store.capture_dir),
				"eventsPath": str(self.store.events_path),
			})
			return

		path = parsed.path
		if path in ("", "/"):
			path = "/index.html"
		requested = (ROOT / path.lstrip("/")).resolve()
		if ROOT not in requested.parents and requested != ROOT:
			self.send_error(403)
			return
		if not requested.exists() or not requested.is_file():
			self.send_error(404)
			return

		body = requested.read_bytes()
		content_type = mimetypes.guess_type(str(requested))[0] or "application/octet-stream"
		self.send_response(200)
		self.send_header("Content-Type", content_type)
		self.send_header("Cache-Control", "no-store")
		self.send_header("Content-Length", str(len(body)))
		self.end_headers()
		self.wfile.write(body)

	def do_POST(self):
		parsed = urlparse(self.path)
		if parsed.path != "/api/event":
			self.send_error(404)
			return
		length = int(self.headers.get("Content-Length", "0"))
		try:
			event = json.loads(self.rfile.read(length).decode("utf-8"))
		except json.JSONDecodeError:
			self.send_error(400)
			return

		written = self.store.append_event(event)
		if written.get("type") == "session:start":
			self.store.write_metadata({
				"capture_dir": str(self.store.capture_dir),
				"created_at": datetime.now(timezone.utc).isoformat(),
				"session_id": written.get("sessionId"),
				"config": written.get("config"),
				"targets": written.get("targets"),
			})
		self.send_json({"ok": True})

	def send_json(self, payload, status=200):
		body = json.dumps(payload, indent=2).encode("utf-8")
		self.send_response(status)
		self.send_header("Content-Type", "application/json")
		self.send_header("Cache-Control", "no-store")
		self.send_header("Content-Length", str(len(body)))
		self.end_headers()
		self.wfile.write(body)


def bind_server(port, store):
	CalibrationHandler.store = store
	for candidate in range(port, port + 20):
		try:
			server = ThreadingHTTPServer(("127.0.0.1", candidate), CalibrationHandler)
			return candidate, server
		except OSError:
			continue
	raise SystemExit(f"Could not bind a port from {port} to {port + 19}")


def main():
	parser = argparse.ArgumentParser(description="Serve the Oura Ring fullscreen calibration target app.")
	parser.add_argument("--port", type=int, default=8765)
	parser.add_argument("--capture-root", type=Path, default=DEFAULT_CAPTURE_ROOT)
	parser.add_argument("--open", action="store_true", help="Open the calibration page in the default browser.")
	args = parser.parse_args()

	store = CaptureStore(args.capture_root.expanduser())
	port, server = bind_server(args.port, store)
	url = f"http://127.0.0.1:{port}/"
	print(f"Calibration URL: {url}")
	print(f"Capture dir: {store.capture_dir}")
	print(f"Events file: {store.events_path}")
	print("Analyze after a run with:")
	print(f"  python3 {ROOT / 'analyze.py'} {store.capture_dir}")
	if args.open:
		webbrowser.open(url)
	try:
		server.serve_forever()
	except KeyboardInterrupt:
		print("\nStopped.")


if __name__ == "__main__":
	main()
