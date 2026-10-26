#!/usr/bin/env bash
# One-time clone setup: enable the repository git hooks (ASCII policy).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if [ "$(git config --get core.hooksPath || true)" != ".githooks" ]; then
  git config core.hooksPath .githooks
  echo "git hooks enabled (core.hooksPath=.githooks)"
fi
