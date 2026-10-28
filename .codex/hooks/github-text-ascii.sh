#!/usr/bin/env bash
# Codex PreToolUse hook: deny GitHub writes containing non-ASCII text.
# The policy itself is scripts/hooks/github-text-ascii-policy.sh.
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
set +e
reason="$(bash "$repo_root/scripts/hooks/github-text-ascii-policy.sh")"
status=$?
set -e
if [ "$status" -eq 10 ]; then
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
fi
exit 0
