#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_FILE="$(mktemp)"
trap 'rm -f "$PATCH_FILE"' EXIT

bash -n "$ROOT_DIR/scripts/prepare-rescope.sh"
bash -n "$ROOT_DIR/scripts/configure-instance.sh"
bash -n "$ROOT_DIR/scripts/deploy.sh"
bash -n "$ROOT_DIR/scripts/check-openclaw-schema.sh"
jq -e . "$ROOT_DIR/slack-app-manifest.json" >/dev/null
"$ROOT_DIR/scripts/configure-instance.sh" \
  --channel-id C12345678 \
  --allowed-user-ids U12345678,U87654321 \
  --approver-user-ids U12345678 \
  --workspace /home/ubuntu/rescope-transformation-platform \
  --render-only >"$PATCH_FILE"
jq -e '
  .channels.slack.dmPolicy == "disabled" and
  .channels.slack.groupPolicy == "allowlist" and
  .channels.slack.channels.C12345678.requireMention == true and
  .channels.slack.execApprovals.approvers == ["U12345678"] and
  .tools.elevated.enabled == false
' "$PATCH_FILE" >/dev/null

if command -v cfn-lint >/dev/null 2>&1; then
  cfn-lint "$ROOT_DIR/template.yaml"
elif command -v uvx >/dev/null 2>&1; then
  uvx --quiet cfn-lint "$ROOT_DIR/template.yaml"
else
  aws cloudformation validate-template \
    --template-body "file://$ROOT_DIR/template.yaml" \
    --output json >/dev/null
fi

"$ROOT_DIR/scripts/check-openclaw-schema.sh"

printf 'CloudFormation, shell, OpenClaw patch, and Slack manifest checks passed.\n'
