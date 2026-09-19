#!/usr/bin/env bash
# Applies branch protection on main: no force-push, no deletion, no required
# PR review (pushdot needs direct push). Re-run any time to reassert these
# settings if they ever get changed in the GitHub UI.
#
# Uses the 21-BreakinCode account's token directly, so it works regardless
# of which gh account is currently active.
set -euo pipefail

GH_TOKEN="$(gh auth token -u 21-BreakinCode)" gh api -X PUT \
  repos/21-BreakinCode/dotfiles/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

echo "Branch protection applied to main: no force-push, no deletion."
