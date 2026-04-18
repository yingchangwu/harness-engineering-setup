#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

if ! command -v node >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Commit blocked: node is not available on PATH.
EOF
  exit 1
fi

export PLAN_REPO_ROOT="${REPO_ROOT}"
export PLAN_GIT_USER_NAME="$(git config --get user.name || true)"
export PLAN_GIT_USER_EMAIL="$(git config --get user.email || true)"
export PLAN_GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
export PLAN_STAGED_FILES="$(git diff --cached --name-only)"

exec node "${REPO_ROOT}/scripts/plan.mjs" hook "$@"
