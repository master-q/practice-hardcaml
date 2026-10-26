#!/bin/bash
# Set up the HardCaml + Yosys/nextpnr/icestorm toolchain in Claude Code
# cloud sessions (mirrors .devcontainer/devcontainer.json).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SWITCH=hardcaml-5.3.0
export OPAMYES=1

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; fi

pkgs="build-essential m4 pkg-config libffi-dev libgmp-dev libssl-dev zlib1g-dev opam bubblewrap yosys nextpnr-ice40 fpga-icestorm fpga-icestorm-chipdb"
if ! command -v yosys >/dev/null || ! command -v nextpnr-ice40 >/dev/null \
   || ! command -v icepack >/dev/null || ! command -v opam >/dev/null; then
  $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq $pkgs
fi

if [ ! -d "$HOME/.opam" ]; then
  opam init --disable-sandboxing --bare -y
fi
if ! opam switch list --short | grep -Fxq "$SWITCH"; then
  opam switch create "$SWITCH" ocaml-base-compiler.5.3.0 -y
fi
opam install --switch="$SWITCH" -y dune hardcaml ppx_hardcaml hardcaml_waveterm

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  opam env --switch="$SWITCH" --set-switch >> "$CLAUDE_ENV_FILE"
fi
