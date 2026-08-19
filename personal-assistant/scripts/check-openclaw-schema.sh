#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.7.1-2}"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf -- "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export OPENCLAW_GATEWAY_TOKEN="schema-test-gateway-token"
export SLACK_APP_TOKEN="xapp-schema-test"
export SLACK_BOT_TOKEN="xoxb-schema-test"

npm exec --yes --package="openclaw@$OPENCLAW_VERSION" -- openclaw onboard \
  --non-interactive \
  --mode local \
  --flow quickstart \
  --auth-choice skip \
  --gateway-auth token \
  --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
  --gateway-port 18789 \
  --gateway-bind loopback \
  --no-install-daemon \
  --skip-bootstrap \
  --skip-skills \
  --skip-health \
  --accept-risk \
  --json >/dev/null

RESULT="$({
  "$ROOT_DIR/scripts/configure-instance.sh" \
    --channel-id C12345678 \
    --allowed-user-ids U12345678,U87654321 \
    --approver-user-ids U12345678 \
    --workspace /home/ubuntu/rescope-transformation-platform \
    --render-only
} | npm exec --yes --package="openclaw@$OPENCLAW_VERSION" -- openclaw config patch \
  --stdin \
  --dry-run \
  --json)"

jq -e '.ok == true and .checks.schema == true and .checks.resolvabilityComplete == true' <<<"$RESULT" >/dev/null
printf 'OpenClaw %s accepted the generated configuration.\n' "$OPENCLAW_VERSION"
