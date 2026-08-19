#!/usr/bin/env bash
set -euo pipefail

REPO_URL="git@github.com:drift-ai/rescope-transformation-platform.git"
BRANCH="main"
WORKSPACE="/home/ubuntu/rescope-transformation-platform"

usage() {
  cat <<'EOF'
Usage: prepare-rescope.sh [--repo-url URL] [--branch BRANCH] [--workspace PATH]

Clone a read-only Rescope checkout and install the dependencies required by
scripts/rescope-admin.sh. Run this on the Lightsail instance as ubuntu.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -eq 0 ]; then
  printf 'Run this script as the ubuntu user, not root.\n' >&2
  exit 1
fi

if [ -e "$WORKSPACE/.git" ]; then
  printf 'Using existing checkout at %s; no pull was performed.\n' "$WORKSPACE"
elif [ -e "$WORKSPACE" ]; then
  printf 'Workspace exists but is not a Git checkout: %s\n' "$WORKSPACE" >&2
  exit 1
else
  git clone --filter=blob:none --branch "$BRANCH" "$REPO_URL" "$WORKSPACE"
fi

if [ ! -x "$WORKSPACE/scripts/rescope-admin.sh" ] || [ ! -f "$WORKSPACE/.agents/skills/rescope-admin-cli/SKILL.md" ]; then
  printf 'Checkout does not contain the guarded Rescope Admin CLI and skill.\n' >&2
  exit 1
fi

cd "$WORKSPACE"
npm ci

printf 'Rescope workspace ready at %s\n' "$WORKSPACE"
printf 'No Supabase or production credentials were installed.\n'
