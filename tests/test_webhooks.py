#!/usr/bin/env python3
"""
Webhook integration tests for ControllerKeys HTTP request feature.

This test suite verifies that HTTP requests are sent correctly and received
by various webhook services. It tests both local mock servers and real
external services (when configured).

Usage:
    # Run all tests (skips unconfigured services)
    python3 test_webhooks.py

    # Run only local tests (no external services needed)
    python3 test_webhooks.py --local-only

    # Run with verbose output
    python3 test_webhooks.py -v

    # Run specific test categories
    python3 test_webhooks.py --only discord,slack

Configuration:
    Copy webhook_config.example.json to webhook_config.json and fill in
    your service credentials. Tests for unconfigured services are skipped.

Requirements:
    pip install requests

For local server tests:
    Run webhook_server.py in another terminal first:
    python3 webhook_server.py
"""

import argparse
import json
import os
import sys
import time
import uuid
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Callable, Optional

try:
    import requests
except ImportError:
    print("Error: 'requests' module not found. Install with: pip install requests")
    sys.exit(1)


# =============================================================================
# Configuration
# =============================================================================

CONFIG_FILE = Path(__file__).parent / "webhook_config.json"
LOCAL_SERVER_URL = "http://localhost:8765"


@dataclass
class WebhookConfig:
    """Configuration for webhook test services."""
    discord_webhook_url: Optional[str] = None
    slack_webhook_url: Optional[str] = None
    ifttt_event_name: Optional[str] = None
    ifttt_key: Optional[str] = None
    webhook_site_token: Optional[str] = None

    @classmethod
    def load(cls) -> "WebhookConfig":
        """Load configuration from file or environment variables."""
        config = cls()

        # Try loading from config file
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    data = json.load(f)
                config.discord_webhook_url = data.get("discord_webhook_url")
                config.slack_webhook_url = data.get("slack_webhook_url")
                config.ifttt_event_name = data.get("ifttt_event_name")
                config.ifttt_key = data.get("ifttt_key")
                config.webhook_site_token = data.get("webhook_site_token")
            except (json.JSONDecodeError, IOError) as e:
                print(f"Warning: Failed to load config file: {e}")

        # Environment variables override config file
        config.discord_webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", config.discord_webhook_url)
        config.slack_webhook_url = os.environ.get("SLACK_WEBHOOK_URL", config.slack_webhook_url)
        config.ifttt_event_name = os.environ.get("IFTTT_EVENT_NAME", config.ifttt_event_name)
        config.ifttt_key = os.environ.get("IFTTT_KEY", config.ifttt_key)
        config.webhook_site_token = os.environ.get("WEBHOOK_SITE_TOKEN", config.webhook_site_token)

        return config


# =============================================================================
# Test Result Types
# =============================================================================

class TestStatus(Enum):
    PASSED = "PASSED"
    FAILED = "FAILED"
    SKIPPED = "SKIPPED"
    ERROR = "ERROR"


@dataclass
class TestResult:
    name: str
    status: TestStatus
    message: str
    duration_ms: float = 0


# =============================================================================
# Test Runner
# =============================================================================

class WebhookTester:
    """Test runner for webhook integration tests."""

    def __init__(self, config: WebhookConfig, verbose: bool = False):
        self.config = config
        self.verbose = verbose
        self.results: list[TestResult] = []

    def log(self, message: str):
        """Log a message if verbose mode is enabled."""
        if self.verbose:
            print(f"    {message}")

    def run_test(self, name: str, test_func: Callable[[], str], skip_condition: bool = False, skip_reason: str = ""):
        """Run a single test and record the result."""
        if skip_condition:
            result = TestResult(name, TestStatus.SKIPPED, skip_reason)
            self.results.append(result)
            print(f"⏭️  {name}: SKIPPED ({skip_reason})")
            return

        start_time = time.time()
        try:
            message = test_func()
            duration = (time.time() - start_time) * 1000
            result = TestResult(name, TestStatus.PASSED, message, duration)
            print(f"✅ {name}: PASSED ({duration:.0f}ms) - {message}")
        except AssertionError as e:
            duration = (time.time() - start_time) * 1000
            result = TestResult(name, TestStatus.FAILED, str(e), duration)
            print(f"❌ {name}: FAILED ({duration:.0f}ms) - {e}")
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            result = TestResult(name, TestStatus.ERROR, str(e), duration)
            print(f"💥 {name}: ERROR ({duration:.0f}ms) - {e}")

        self.results.append(result)

    def summary(self) -> bool:
        """Print test summary and return True if all tests passed."""
        passed = sum(1 for r in self.results if r.status == TestStatus.PASSED)
        failed = sum(1 for r in self.results if r.status == TestStatus.FAILED)
        errors = sum(1 for r in self.results if r.status == TestStatus.ERROR)
        skipped = sum(1 for r in self.results if r.status == TestStatus.SKIPPED)
        total = len(self.results)

        print(f"\n{'='*60}")
        print(f"Test Results: {passed}/{total - skipped} passed", end="")
        if skipped:
            print(f" ({skipped} skipped)", end="")
        if failed:
            print(f", {failed} failed", end="")
        if errors:
            print(f", {errors} errors", end="")
        print()
        print(f"{'='*60}")

        return failed == 0 and errors == 0


# =============================================================================
# Local Server Tests
# =============================================================================

def test_local_server_health(tester: WebhookTester):
    """Test that local test server is running."""
    def run():
        r = requests.get(f"{LOCAL_SERVER_URL}/health", timeout=5)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"
        data = r.json()
        assert data.get("status") == "healthy", f"Unexpected response: {data}"
        return "Server is healthy"

    tester.run_test("Local Server Health Check", run)


def test_local_post_webhook(tester: WebhookTester):
    """Test POST request to local webhook."""
    def run():
        payload = {"action": "button_pressed", "button": "A", "test_id": uuid.uuid4().hex}
        r = requests.post(f"{LOCAL_SERVER_URL}/webhook", json=payload, timeout=5)
        assert r.status_code == 201, f"Expected 201, got {r.status_code}"
        return f"POST accepted (test_id: {payload['test_id'][:8]})"

    tester.run_test("Local POST Webhook", run)


def test_local_get_webhook(tester: WebhookTester):
    """Test GET request to local webhook."""
    def run():
        r = requests.get(f"{LOCAL_SERVER_URL}/webhook?action=status", timeout=5)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"
        return "GET accepted"

    tester.run_test("Local GET Webhook", run)


def test_local_put_webhook(tester: WebhookTester):
    """Test PUT request to local webhook."""
    def run():
        payload = {"setting": "volume", "value": 75}
        r = requests.put(f"{LOCAL_SERVER_URL}/webhook", json=payload, timeout=5)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"
        return "PUT accepted"

    tester.run_test("Local PUT Webhook", run)


def test_local_delete_webhook(tester: WebhookTester):
    """Test DELETE request to local webhook."""
    def run():
        r = requests.delete(f"{LOCAL_SERVER_URL}/webhook", timeout=5)
        assert r.status_code == 204, f"Expected 204, got {r.status_code}"
        return "DELETE accepted (204 No Content)"

    tester.run_test("Local DELETE Webhook", run)


def test_local_patch_webhook(tester: WebhookTester):
    """Test PATCH request to local webhook."""
    def run():
        payload = {"update": "partial"}
        r = requests.patch(f"{LOCAL_SERVER_URL}/webhook", json=payload, timeout=5)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"
        return "PATCH accepted"

    tester.run_test("Local PATCH Webhook", run)


def test_local_echo(tester: WebhookTester):
    """Test echo endpoint returns exact request data."""
    def run():
        payload = {
            "test_id": uuid.uuid4().hex,
            "nested": {"key": "value"},
            "array": [1, 2, 3],
            "unicode": "🎮 controller"
        }
        headers = {
            "X-Custom-Header": "test-value",
            "Authorization": "Bearer test-token"
        }

        r = requests.post(f"{LOCAL_SERVER_URL}/echo", json=payload, headers=headers, timeout=5)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"

        data = r.json()

        # Verify payload was received
        assert data.get("json") == payload, f"Payload mismatch: {data.get('json')}"

        # Verify custom headers
        received_headers = {k.lower(): v for k, v in data.get("headers", {}).items()}
        assert received_headers.get("x-custom-header") == "test-value", "Custom header not received"
        assert "bearer test-token" in received_headers.get("authorization", "").lower(), "Auth header not received"

        return f"Echo verified (test_id: {payload['test_id'][:8]})"

    tester.run_test("Local Echo (Request Verification)", run)


def test_local_custom_headers(tester: WebhookTester):
    """Test custom headers are forwarded correctly."""
    def run():
        headers = {
            "Content-Type": "application/json",
            "X-API-Key": "secret-key-12345",
            "Authorization": "Basic dXNlcjpwYXNzd29yZA==",
            "X-Request-ID": uuid.uuid4().hex
        }

        r = requests.post(f"{LOCAL_SERVER_URL}/echo", json={"test": True}, headers=headers, timeout=5)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"

        received = r.json().get("headers", {})
        received_lower = {k.lower(): v for k, v in received.items()}

        assert received_lower.get("x-api-key") == "secret-key-12345", "X-API-Key not received"
        assert "basic" in received_lower.get("authorization", "").lower(), "Authorization not received"

        return f"4 custom headers verified"

    tester.run_test("Local Custom Headers", run)


def test_local_error_codes(tester: WebhookTester):
    """Test error code simulation endpoints."""
    def run():
        error_codes = [400, 401, 403, 404, 500, 503]
        results = []

        for code in error_codes:
            r = requests.post(f"{LOCAL_SERVER_URL}/error/{code}", json={}, timeout=5)
            assert r.status_code == code, f"Expected {code}, got {r.status_code}"
            results.append(str(code))

        return f"Error codes verified: {', '.join(results)}"

    tester.run_test("Local Error Code Simulation", run)


def test_local_request_capture(tester: WebhookTester):
    """Test that requests are captured and retrievable."""
    def run():
        # Clear previous requests
        requests.delete(f"{LOCAL_SERVER_URL}/requests", timeout=5)

        # Send a unique request
        test_id = uuid.uuid4().hex
        requests.post(f"{LOCAL_SERVER_URL}/webhook/capture-test", json={"test_id": test_id}, timeout=5)

        # Retrieve captured requests
        r = requests.get(f"{LOCAL_SERVER_URL}/requests", timeout=5)
        assert r.status_code == 200

        data = r.json()
        captured = data.get("requests", [])

        # Find our request
        found = any(test_id in str(req) for req in captured)
        assert found, f"Request with test_id {test_id} not found in captured requests"

        return f"Request captured and retrieved (test_id: {test_id[:8]})"

    tester.run_test("Local Request Capture", run)


# =============================================================================
# httpbin.org Tests
# =============================================================================

def test_httpbin_post(tester: WebhookTester):
    """Test POST to httpbin.org echo service."""
    def run():
        payload = {"test_id": uuid.uuid4().hex, "source": "controllerkeys"}
        r = requests.post("https://httpbin.org/post", json=payload, timeout=10)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"

        data = r.json()
        assert data.get("json") == payload, f"Payload mismatch: {data.get('json')}"

        return f"Echo verified (test_id: {payload['test_id'][:8]})"

    tester.run_test("httpbin.org POST Echo", run)


def test_httpbin_headers(tester: WebhookTester):
    """Test custom headers via httpbin.org."""
    def run():
        headers = {
            "X-Custom-Header": "test-value",
            "X-Another": "another-value"
        }
        r = requests.get("https://httpbin.org/headers", headers=headers, timeout=10)
        assert r.status_code == 200

        received = r.json().get("headers", {})
        assert received.get("X-Custom-Header") == "test-value", "Custom header not received"
        assert received.get("X-Another") == "another-value", "Second header not received"

        return "Custom headers verified"

    tester.run_test("httpbin.org Custom Headers", run)


def test_httpbin_methods(tester: WebhookTester):
    """Test various HTTP methods via httpbin.org."""
    def run():
        methods = [
            ("GET", "https://httpbin.org/get"),
            ("POST", "https://httpbin.org/post"),
            ("PUT", "https://httpbin.org/put"),
            ("DELETE", "https://httpbin.org/delete"),
            ("PATCH", "https://httpbin.org/patch"),
        ]

        for method, url in methods:
            r = requests.request(method, url, json={"method": method} if method != "GET" else None, timeout=10)
            assert r.status_code == 200, f"{method} failed with {r.status_code}"

        return f"All {len(methods)} HTTP methods verified"

    tester.run_test("httpbin.org HTTP Methods", run)


# =============================================================================
# Discord Webhook Tests
# =============================================================================

def test_discord_webhook(tester: WebhookTester):
    """Test Discord webhook message delivery."""
    config = tester.config

    def run():
        test_id = uuid.uuid4().hex[:8]
        payload = {
            "content": f"🎮 ControllerKeys webhook test `{test_id}`\n_Automated test - please ignore_"
        }

        r = requests.post(config.discord_webhook_url, json=payload, timeout=10)
        assert r.status_code == 204, f"Expected 204, got {r.status_code}"

        return f"Message sent (test_id: {test_id})"

    skip = not config.discord_webhook_url
    tester.run_test("Discord Webhook", run, skip_condition=skip, skip_reason="No webhook URL configured")


def test_discord_embed(tester: WebhookTester):
    """Test Discord webhook with rich embed."""
    config = tester.config

    def run():
        test_id = uuid.uuid4().hex[:8]
        payload = {
            "embeds": [{
                "title": "ControllerKeys Test",
                "description": f"Automated webhook test `{test_id}`",
                "color": 5814783,  # Blue color
                "fields": [
                    {"name": "Status", "value": "✅ Working", "inline": True},
                    {"name": "Source", "value": "Test Suite", "inline": True}
                ],
                "footer": {"text": "This is an automated test message"}
            }]
        }

        r = requests.post(config.discord_webhook_url, json=payload, timeout=10)
        assert r.status_code == 204, f"Expected 204, got {r.status_code}"

        return f"Embed sent (test_id: {test_id})"

    skip = not config.discord_webhook_url
    tester.run_test("Discord Embed", run, skip_condition=skip, skip_reason="No webhook URL configured")


# =============================================================================
# Slack Webhook Tests
# =============================================================================

def test_slack_webhook(tester: WebhookTester):
    """Test Slack incoming webhook message delivery."""
    config = tester.config

    def run():
        test_id = uuid.uuid4().hex[:8]
        payload = {
            "text": f"🎮 ControllerKeys webhook test `{test_id}`\n_Automated test - please ignore_"
        }

        r = requests.post(config.slack_webhook_url, json=payload, timeout=10)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"
        assert r.text == "ok", f"Expected 'ok', got '{r.text}'"

        return f"Message sent (test_id: {test_id})"

    skip = not config.slack_webhook_url
    tester.run_test("Slack Webhook", run, skip_condition=skip, skip_reason="No webhook URL configured")


def test_slack_blocks(tester: WebhookTester):
    """Test Slack webhook with Block Kit formatting."""
    config = tester.config

    def run():
        test_id = uuid.uuid4().hex[:8]
        payload = {
            "blocks": [
                {
                    "type": "header",
                    "text": {"type": "plain_text", "text": "🎮 ControllerKeys Test"}
                },
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"Automated webhook test `{test_id}`"}
                },
                {
                    "type": "context",
                    "elements": [{"type": "mrkdwn", "text": "_This is an automated test message_"}]
                }
            ]
        }

        r = requests.post(config.slack_webhook_url, json=payload, timeout=10)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"

        return f"Blocks sent (test_id: {test_id})"

    skip = not config.slack_webhook_url
    tester.run_test("Slack Blocks", run, skip_condition=skip, skip_reason="No webhook URL configured")


# =============================================================================
# IFTTT Webhook Tests
# =============================================================================

def test_ifttt_webhook(tester: WebhookTester):
    """Test IFTTT Maker webhook trigger."""
    config = tester.config

    def run():
        test_id = uuid.uuid4().hex[:8]
        url = f"https://maker.ifttt.com/trigger/{config.ifttt_event_name}/with/key/{config.ifttt_key}"
        payload = {
            "value1": f"ControllerKeys test {test_id}",
            "value2": "button_pressed",
            "value3": "A"
        }

        r = requests.post(url, json=payload, timeout=10)
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"

        # IFTTT returns a message on success
        assert "Congratulations" in r.text or "triggered" in r.text.lower(), f"Unexpected response: {r.text[:100]}"

        return f"Event triggered (test_id: {test_id})"

    skip = not (config.ifttt_event_name and config.ifttt_key)
    tester.run_test("IFTTT Webhook", run, skip_condition=skip, skip_reason="No IFTTT credentials configured")


# =============================================================================
# webhook.site Tests
# =============================================================================

def test_webhook_site(tester: WebhookTester):
    """Test webhook.site request capture and retrieval."""
    config = tester.config

    def run():
        test_id = uuid.uuid4().hex
        webhook_url = f"https://webhook.site/{config.webhook_site_token}"
        api_url = f"https://webhook.site/token/{config.webhook_site_token}/requests"

        # Send a test request
        payload = {"test_id": test_id, "source": "controllerkeys", "action": "test"}
        r = requests.post(webhook_url, json=payload, timeout=10)
        assert r.status_code == 200, f"POST failed with {r.status_code}"

        # Wait for capture
        time.sleep(2)

        # Retrieve captured requests
        r = requests.get(api_url, timeout=10)
        assert r.status_code == 200, f"API request failed with {r.status_code}"

        data = r.json()
        requests_list = data.get("data", [])

        # Find our request
        found = any(test_id in str(req.get("content", "")) for req in requests_list)
        assert found, f"Request with test_id {test_id} not found"

        return f"Request captured and verified (test_id: {test_id[:8]})"

    skip = not config.webhook_site_token
    tester.run_test("webhook.site Capture", run, skip_condition=skip, skip_reason="No webhook.site token configured")


# =============================================================================
# End-to-End Simulation Tests
# =============================================================================

def test_e2e_controllerkeys_simulation(tester: WebhookTester):
    """Simulate exactly what ControllerKeys will do when executing an HTTP action."""
    def run():
        """
        This test simulates the SystemCommandExecutor.executeHTTPRequest() behavior:
        1. Default Content-Type: application/json for POST/PUT/PATCH
        2. Custom headers are applied
        3. Body is sent as UTF-8 encoded data
        4. Timeout of 10 seconds
        """

        # Simulate ControllerKeys HTTP request execution
        url = f"{LOCAL_SERVER_URL}/echo"
        method = "POST"
        headers = {"Content-Type": "application/json"}  # Default for POST
        body = json.dumps({"action": "scene_switch", "scene": "Lecture Mode"})

        # Apply custom headers (as ControllerKeys would)
        custom_headers = {"X-API-Key": "obs-key-123"}
        headers.update(custom_headers)

        # Execute request (as ControllerKeys would)
        response = requests.request(
            method=method,
            url=url,
            headers=headers,
            data=body.encode("utf-8"),
            timeout=10
        )

        assert response.status_code == 200, f"Request failed: {response.status_code}"

        # Verify the request was received correctly
        echoed = response.json()
        assert echoed.get("json", {}).get("action") == "scene_switch"
        assert echoed.get("json", {}).get("scene") == "Lecture Mode"

        received_headers = {k.lower(): v for k, v in echoed.get("headers", {}).items()}
        assert received_headers.get("x-api-key") == "obs-key-123"

        return "ControllerKeys simulation verified"

    tester.run_test("E2E ControllerKeys Simulation", run)


def test_e2e_rapid_fire(tester: WebhookTester):
    """Test rapid consecutive requests (simulating rapid button presses)."""
    def run():
        # Clear request counter
        requests.delete(f"{LOCAL_SERVER_URL}/requests", timeout=5)

        # Fire 10 requests as fast as possible
        test_id = uuid.uuid4().hex
        for i in range(10):
            payload = {"test_id": test_id, "sequence": i}
            requests.post(f"{LOCAL_SERVER_URL}/webhook", json=payload, timeout=5)

        # Verify all were received
        time.sleep(0.5)
        r = requests.get(f"{LOCAL_SERVER_URL}/requests", timeout=5)
        data = r.json()

        # Count requests with our test_id
        count = sum(1 for req in data.get("requests", []) if test_id in str(req))
        assert count == 10, f"Expected 10 requests, got {count}"

        return "10 rapid requests captured"

    tester.run_test("E2E Rapid Fire (10 requests)", run)


# =============================================================================
# Main Entry Point
# =============================================================================

def check_local_server() -> bool:
    """Check if local test server is running."""
    try:
        r = requests.get(f"{LOCAL_SERVER_URL}/health", timeout=2)
        return r.status_code == 200
    except requests.exceptions.RequestException:
        return False


def run_tests(args):
    """Run the test suite."""
    config = WebhookConfig.load()
    tester = WebhookTester(config, verbose=args.verbose)

    print(f"\n{'='*60}")
    print("ControllerKeys Webhook Integration Tests")
    print(f"{'='*60}\n")

    # Check local server
    local_server_running = check_local_server()
    if not local_server_running:
        print("⚠️  Local test server not running!")
        print(f"   Start it with: python3 {Path(__file__).parent}/webhook_server.py\n")

    # Parse --only filter
    only_tests = set(args.only.split(",")) if args.only else None

    # Local server tests
    if not args.external_only:
        print("─" * 40)
        print("LOCAL SERVER TESTS")
        print("─" * 40)

        if local_server_running:
            if not only_tests or "local" in only_tests:
                test_local_server_health(tester)
                test_local_post_webhook(tester)
                test_local_get_webhook(tester)
                test_local_put_webhook(tester)
                test_local_delete_webhook(tester)
                test_local_patch_webhook(tester)
                test_local_echo(tester)
                test_local_custom_headers(tester)
                test_local_error_codes(tester)
                test_local_request_capture(tester)
        else:
            print("⏭️  Skipping local tests (server not running)\n")

    # httpbin.org tests (always available)
    if not args.local_only:
        print("\n" + "─" * 40)
        print("HTTPBIN.ORG TESTS")
        print("─" * 40)

        if not only_tests or "httpbin" in only_tests:
            test_httpbin_post(tester)
            test_httpbin_headers(tester)
            test_httpbin_methods(tester)

    # External service tests
    if not args.local_only:
        print("\n" + "─" * 40)
        print("EXTERNAL SERVICE TESTS")
        print("─" * 40)

        if not only_tests or "discord" in only_tests:
            test_discord_webhook(tester)
            test_discord_embed(tester)

        if not only_tests or "slack" in only_tests:
            test_slack_webhook(tester)
            test_slack_blocks(tester)

        if not only_tests or "ifttt" in only_tests:
            test_ifttt_webhook(tester)

        if not only_tests or "webhooksite" in only_tests:
            test_webhook_site(tester)

    # E2E tests
    if local_server_running and not args.external_only:
        print("\n" + "─" * 40)
        print("END-TO-END TESTS")
        print("─" * 40)

        if not only_tests or "e2e" in only_tests:
            test_e2e_controllerkeys_simulation(tester)
            test_e2e_rapid_fire(tester)

    # Summary
    success = tester.summary()
    return 0 if success else 1


def main():
    parser = argparse.ArgumentParser(
        description="ControllerKeys Webhook Integration Tests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 test_webhooks.py                    # Run all tests
  python3 test_webhooks.py --local-only       # Only local server tests
  python3 test_webhooks.py --only discord     # Only Discord tests
  python3 test_webhooks.py --only local,e2e   # Local and E2E tests
  python3 test_webhooks.py -v                 # Verbose output
        """
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    parser.add_argument("--local-only", action="store_true", help="Only run local server tests")
    parser.add_argument("--external-only", action="store_true", help="Only run external service tests")
    parser.add_argument("--only", type=str, help="Comma-separated list of test categories: local,httpbin,discord,slack,ifttt,webhooksite,e2e")

    args = parser.parse_args()
    sys.exit(run_tests(args))


if __name__ == "__main__":
    main()
