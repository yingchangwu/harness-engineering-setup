#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true
chmod +x scripts/hooks/*.sh 2>/dev/null || true

echo "Installed git hooks:"
echo "  core.hooksPath = .githooks"
echo "  bypass log = .harness-engineering/plan-bypass.log"
