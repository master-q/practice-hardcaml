#!/usr/bin/env bash
# Shared policy for text that agents publish on GitHub (issues, comments,
# pull requests, reviews): it must be English ASCII (AGENTS.md).
#
# Input: a PreToolUse hook payload (JSON) on stdin.
# Exit codes:
#   0   allowed, or outside this policy's scope
#   10  the tool call would publish non-ASCII text; the reason is on stdout
set -euo pipefail

payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
input="$(printf '%s' "$payload" | jq -r '.tool_input | tostring')"

in_scope=false
case "$tool" in
  Bash|shell|exec_command)
    cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])gh[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit|review)([[:space:]]|$)|(^|[;&|(]|[[:space:]])gh[[:space:]]+api[[:space:]]'; then
      in_scope=true
      input="$cmd"
    fi
    ;;
  mcp__github__issue_write|mcp__github__add_issue_comment|mcp__github__update_issue_comment|\
  mcp__github__sub_issue_write|mcp__github__create_pull_request|mcp__github__update_pull_request|\
  mcp__github__pull_request_review_write|mcp__github__add_comment_to_pending_review|\
  mcp__github__add_reply_to_pull_request_comment|mcp__github__create_or_update_file|\
  mcp__github__push_files)
    in_scope=true
    ;;
esac

if $in_scope && printf '%s' "$input" | LC_ALL=C grep -qP '[^\x00-\x7F]'; then
  printf '%s\n' "Non-ASCII text in a GitHub write ($tool). Issues, comments, pull requests and reviews in this repository must be written in English using ASCII only (AGENTS.md). Rewrite the text in English and retry."
  exit 10
fi
exit 0
