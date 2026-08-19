#!/usr/bin/env bash
set -euo pipefail

PROFILE=""
CONFIRM_ACCOUNT=""
SSH_CIDR=""
REGION="eu-west-1"
STACK_NAME="rescope-personal-assistant"
KEY_PAIR_NAME="rescope-personal-assistant-ssh"
SSH_PUBLIC_KEY="$HOME/.ssh/id_ed25519.pub"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: deploy.sh \
  --profile AWS_PROFILE \
  --confirm-account 123456789012 \
  --ssh-cidr 203.0.113.10/32 \
  [--region eu-west-1] \
  [--ssh-public-key ~/.ssh/id_ed25519.pub]

Imports a dedicated Lightsail key pair when absent, validates the template,
and deploys the rescope-personal-assistant CloudFormation stack.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --confirm-account) CONFIRM_ACCOUNT="$2"; shift 2 ;;
    --ssh-cidr) SSH_CIDR="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --ssh-public-key) SSH_PUBLIC_KEY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$PROFILE" ] || ! [[ "$CONFIRM_ACCOUNT" =~ ^[0-9]{12}$ ]] || ! [[ "$SSH_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; then
  usage >&2
  exit 2
fi
if [ ! -f "$SSH_PUBLIC_KEY" ]; then
  printf 'SSH public key not found: %s\n' "$SSH_PUBLIC_KEY" >&2
  exit 1
fi

ACTUAL_ACCOUNT="$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)"
if [ "$ACTUAL_ACCOUNT" != "$CONFIRM_ACCOUNT" ]; then
  printf 'Refusing account %s; expected confirmed account %s.\n' "$ACTUAL_ACCOUNT" "$CONFIRM_ACCOUNT" >&2
  exit 1
fi

printf 'Deploy target: AWS account %s, Region %s, stack %s\n' "$ACTUAL_ACCOUNT" "$REGION" "$STACK_NAME"
aws cloudformation validate-template \
  --profile "$PROFILE" \
  --region "$REGION" \
  --template-body "file://$ROOT_DIR/template.yaml" \
  --output json >/dev/null

if ! aws lightsail get-key-pair \
  --profile "$PROFILE" \
  --region "$REGION" \
  --key-pair-name "$KEY_PAIR_NAME" \
  --output json >/dev/null 2>&1; then
  aws lightsail import-key-pair \
    --profile "$PROFILE" \
    --region "$REGION" \
    --key-pair-name "$KEY_PAIR_NAME" \
    --public-key-base64 "file://$SSH_PUBLIC_KEY" \
    --output json >/dev/null
  printf 'Imported Lightsail key pair %s.\n' "$KEY_PAIR_NAME"
fi

aws cloudformation deploy \
  --profile "$PROFILE" \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$ROOT_DIR/template.yaml" \
  --parameter-overrides \
    KeyPairName="$KEY_PAIR_NAME" \
    SshAllowedCidr="$SSH_CIDR"

aws cloudformation describe-stacks \
  --profile "$PROFILE" \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs' \
  --output table
