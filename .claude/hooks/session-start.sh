#!/bin/bash
# Set up the pinned toolchain in Claude Code cloud sessions (mirrors
# .devcontainer/devcontainer.json and CI; see scripts/toolchain.sh).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

export OPAMYES=1

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; fi

# EDA tools, the RISC-V GCC and the opam packages are pinned (toolchain/,
# scripts/toolchain.sh); apt only provides what does not affect results.
pkgs="build-essential m4 pkg-config libffi-dev libgmp-dev libssl-dev zlib1g-dev opam curl jq flex bison bc cpio"
if ! command -v opam >/dev/null || ! command -v curl >/dev/null; then
  $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq $pkgs
fi
"$CLAUDE_PROJECT_DIR"/scripts/toolchain.sh install

# Enable the repository git hooks (English/ASCII-only policy).
"$CLAUDE_PROJECT_DIR"/scripts/setup_clone.sh

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  "$CLAUDE_PROJECT_DIR"/scripts/toolchain.sh env >> "$CLAUDE_ENV_FILE"
fi
