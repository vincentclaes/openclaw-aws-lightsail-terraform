#!/usr/bin/env bash
set -euo pipefail

CHANNEL_ID=""
ALLOWED_USER_IDS=""
APPROVER_USER_IDS=""
WORKSPACE="/home/ubuntu/rescope-transformation-platform"
RENDER_ONLY=false

usage() {
  cat <<'EOF'
Usage: configure-instance.sh \
  --channel-id C12345678 \
  --allowed-user-ids U12345678,U87654321 \
  --approver-user-ids U12345678 \
  [--workspace /home/ubuntu/rescope-transformation-platform] \
  [--render-only]

Run this on the Lightsail instance as ubuntu. It signs OpenClaw into ChatGPT,
stores Slack tokens in ~/.openclaw/.env, applies a channel/user allowlist, and
enables approval-gated host execution.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --channel-id) CHANNEL_ID="$2"; shift 2 ;;
    --allowed-user-ids) ALLOWED_USER_IDS="$2"; shift 2 ;;
    --approver-user-ids) APPROVER_USER_IDS="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --render-only) RENDER_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -eq 0 ]; then
  printf 'Run this script as the ubuntu user, not root.\n' >&2
  exit 1
fi
if ! [[ "$CHANNEL_ID" =~ ^[CG][A-Z0-9]+$ ]]; then
  printf 'Invalid Slack channel ID: %s\n' "$CHANNEL_ID" >&2
  exit 2
fi
if [ "$RENDER_ONLY" = false ] && { [ ! -d "$WORKSPACE/.git" ] || [ ! -x "$WORKSPACE/scripts/rescope-admin.sh" ]; }; then
  printf 'Prepare the Rescope checkout first: %s\n' "$WORKSPACE" >&2
  exit 1
fi

normalize_user_ids() {
  local raw="$1"
  local item
  local -a ids
  IFS=',' read -r -a ids <<<"$raw"
  if [ "${#ids[@]}" -eq 0 ]; then
    return 1
  fi
  for item in "${ids[@]}"; do
    item="${item//[[:space:]]/}"
    if ! [[ "$item" =~ ^[UW][A-Z0-9]+$ ]]; then
      printf 'Invalid Slack user ID: %s\n' "$item" >&2
      return 1
    fi
    printf '%s\n' "$item"
  done | jq -R . | jq -s .
}

ALLOWED_USERS_JSON="$(normalize_user_ids "$ALLOWED_USER_IDS")"
APPROVERS_JSON="$(normalize_user_ids "$APPROVER_USER_IDS")"

render_patch() {
  jq -n \
    --arg channel "$CHANNEL_ID" \
    --arg workspace "$WORKSPACE" \
    --argjson users "$ALLOWED_USERS_JSON" \
    --argjson approvers "$APPROVERS_JSON" \
    '{
      agents: {
        defaults: {
          workspace: $workspace
        }
      },
      plugins: {
        entries: {
          codex: { enabled: true }
        }
      },
      channels: {
        slack: {
          enabled: true,
          mode: "socket",
          appToken: { source: "env", provider: "default", id: "SLACK_APP_TOKEN" },
          botToken: { source: "env", provider: "default", id: "SLACK_BOT_TOKEN" },
          dmPolicy: "disabled",
          groupPolicy: "allowlist",
          channels: {
            ($channel): {
              requireMention: true,
              users: $users
            }
          },
          slashCommand: {
            enabled: true,
            name: "openclaw",
            sessionPrefix: "slack:slash",
            ephemeral: true
          },
          execApprovals: {
            enabled: true,
            approvers: $approvers,
            target: "dm"
          }
        }
      },
      commands: {
        ownerAllowFrom: ($approvers | map("slack:" + .)),
        useAccessGroups: true
      },
      tools: {
        elevated: { enabled: false }
      }
    }'
}

if [ "$RENDER_ONLY" = true ]; then
  render_patch
  exit 0
fi

printf 'Starting ChatGPT device-code sign-in. Complete it in your browser.\n'
openclaw models auth login --provider openai --device-code --set-default

read -r -s -p 'Slack app token (xapp-...): ' SLACK_APP_TOKEN
printf '\n'
read -r -s -p 'Slack bot token (xoxb-...): ' SLACK_BOT_TOKEN
printf '\n'
if [[ "$SLACK_APP_TOKEN" != xapp-* ]] || [[ "$SLACK_BOT_TOKEN" != xoxb-* ]]; then
  printf 'Slack tokens do not have the expected xapp-/xoxb- prefixes.\n' >&2
  exit 2
fi

ENV_FILE="$HOME/.openclaw/.env"
mkdir -p "$HOME/.openclaw"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"
ENV_TMP="$(mktemp)"
PATCH_FILE="$(mktemp)"
trap 'rm -f "$ENV_TMP" "$PATCH_FILE"' EXIT
grep -v -E '^(SLACK_APP_TOKEN|SLACK_BOT_TOKEN)=' "$ENV_FILE" >"$ENV_TMP" || true
printf 'SLACK_APP_TOKEN=%s\nSLACK_BOT_TOKEN=%s\n' "$SLACK_APP_TOKEN" "$SLACK_BOT_TOKEN" >>"$ENV_TMP"
mv "$ENV_TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"
unset SLACK_APP_TOKEN SLACK_BOT_TOKEN

openclaw plugins install --force --pin @openclaw/slack@2026.7.1

render_patch >"$PATCH_FILE"

set -a
# The instance-specific OpenClaw env path is intentional.
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
openclaw config patch --file "$PATCH_FILE" --dry-run
openclaw config patch --file "$PATCH_FILE"
openclaw exec-policy preset cautious
openclaw config validate
openclaw gateway restart

printf '\nConfiguration complete. Verification:\n'
openclaw models status
openclaw channels status --probe
openclaw gateway status
