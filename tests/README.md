# ControllerKeys Webhook Integration Tests

Test suite for the HTTP request/webhook feature. Verifies that HTTP requests are sent correctly and received by various webhook services.

## Quick Start

```bash
# 1. Install dependencies
pip install requests

# 2. Start the local test server (in one terminal)
python3 webhook_server.py

# 3. Run tests (in another terminal)
python3 test_webhooks.py
```

## Test Categories

| Category | Description | Requires |
|----------|-------------|----------|
| `local` | Local mock server tests | `webhook_server.py` running |
| `httpbin` | httpbin.org echo tests | Internet connection |
| `discord` | Discord webhook tests | Webhook URL configured |
| `slack` | Slack webhook tests | Webhook URL configured |
| `ifttt` | IFTTT Maker tests | Event name + key configured |
| `webhooksite` | webhook.site capture tests | Token configured |
| `e2e` | End-to-end simulation | `webhook_server.py` running |

## Configuration

### Option 1: Config File

```bash
cp webhook_config.example.json webhook_config.json
# Edit webhook_config.json with your credentials
```

### Option 2: Environment Variables

```bash
export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export IFTTT_EVENT_NAME="controllerkeys_test"
export IFTTT_KEY="your_ifttt_key"
export WEBHOOK_SITE_TOKEN="your-uuid-token"
```

## Running Tests

```bash
# Run all tests (skips unconfigured services)
python3 test_webhooks.py

# Run only local tests (no external services needed)
python3 test_webhooks.py --local-only

# Run only external service tests
python3 test_webhooks.py --external-only

# Run specific categories
python3 test_webhooks.py --only discord,slack
python3 test_webhooks.py --only local,e2e

# Verbose output
python3 test_webhooks.py -v
```

## Local Test Server

The local test server (`webhook_server.py`) provides a controlled environment for testing HTTP requests without external dependencies.

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/webhook` | POST | Returns 201 Created |
| `/webhook` | GET | Returns 200 OK |
| `/webhook` | PUT | Returns 200 OK |
| `/webhook` | DELETE | Returns 204 No Content |
| `/webhook` | PATCH | Returns 200 OK |
| `/echo` | POST | Echoes back request details (like httpbin) |
| `/slow` | POST | 5-second delay (for timeout testing) |
| `/error/:code` | POST | Returns specified HTTP error code |
| `/requests` | GET | List all captured requests |
| `/requests` | DELETE | Clear captured requests |
| `/health` | GET | Health check |

### Example Usage

```bash
# Start server
python3 webhook_server.py --port 8765

# Test POST
curl -X POST http://localhost:8765/webhook \
  -H "Content-Type: application/json" \
  -d '{"action": "button_pressed"}'

# Test with custom headers
curl -X POST http://localhost:8765/echo \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-API-Key: secret" \
  -d '{"scene": "Lecture"}'

# Test error handling
curl -X POST http://localhost:8765/error/401

# View captured requests
curl http://localhost:8765/requests
```

## Setting Up External Services

### Discord

1. Go to your Discord server settings
2. Navigate to **Integrations > Webhooks**
3. Click **New Webhook**
4. Copy the webhook URL

### Slack

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Create a new app or use existing
3. Enable **Incoming Webhooks**
4. Add a webhook to a channel
5. Copy the webhook URL

### IFTTT

1. Go to [ifttt.com/maker_webhooks](https://ifttt.com/maker_webhooks)
2. Click **Documentation**
3. Copy your key from the URL
4. Create an applet with "Webhooks" as the trigger
5. Set the event name (e.g., `controllerkeys_test`)

### webhook.site

1. Go to [webhook.site](https://webhook.site)
2. Copy the UUID from your unique URL (the part after `webhook.site/`)
3. Use this as your token

## What These Tests Verify

### HTTP Method Tests
- All HTTP methods (GET, POST, PUT, DELETE, PATCH) work correctly
- Correct status codes are returned

### Header Tests
- Custom headers are forwarded correctly
- Authorization headers work
- Content-Type is set appropriately

### Body Tests
- JSON payloads are sent correctly
- Unicode characters are preserved
- Empty bodies work for appropriate methods

### Error Handling Tests
- Network errors don't crash the app
- HTTP error codes are logged
- Timeouts are handled gracefully

### Real-World Integration Tests
- Discord messages are delivered
- Slack messages appear in channels
- IFTTT applets are triggered
- webhook.site captures requests correctly

## CI Integration

For automated testing in CI (without external service credentials):

```bash
# Start local server in background
python3 webhook_server.py &
sleep 2

# Run local tests only
python3 test_webhooks.py --local-only

# Or run local + httpbin tests
python3 test_webhooks.py --only local,httpbin,e2e
```
