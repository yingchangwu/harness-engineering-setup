$ErrorActionPreference = "Stop"

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) {
  throw "Could not determine repo root."
}

$env:PLAN_REPO_ROOT = $repoRoot
$env:PLAN_GIT_USER_NAME = ((& git config --get user.name) 2>$null | Out-String).Trim()
$env:PLAN_GIT_USER_EMAIL = ((& git config --get user.email) 2>$null | Out-String).Trim()
$env:PLAN_GIT_BRANCH = (((& git rev-parse --abbrev-ref HEAD) 2>$null) | Out-String).Trim()

& node (Join-Path $repoRoot "scripts/plan.mjs") @args
exit $LASTEXITCODE
