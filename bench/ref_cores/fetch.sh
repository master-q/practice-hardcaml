#!/usr/bin/env bash
# Fetch the reference cores used by the riscv-ice40 survey
# (https://github.com/MrJake222/riscv-ice40 at 5f4633a8), at the exact
# submodule commits that survey pins, into DIR (default: build/src).
# The sources are not committed here; each core has its own license.
set -euo pipefail
dir=${1:-build/src}
mkdir -p "$dir"
fetch() { # name url commit
  local d="$dir/$1"
  if [ -d "$d/.git" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$3" ]; then return; fi
  rm -rf "$d"
  git init -q "$d"
  git -C "$d" fetch -q --depth 1 "$2" "$3"
  git -C "$d" checkout -q FETCH_HEAD
}
fetch riscv-ice40 https://github.com/MrJake222/riscv-ice40.git 5f4633a826974b8bc833acdc799e534bf0e30b5e
fetch picorv32    https://github.com/YosysHQ/picorv32.git       336cfca6e5f1c08788348aadc46b3581b9a5d585
fetch femtorv     https://github.com/MrJake222/learn-fpga.git   e83d7dfd5cc806abe639a8e3542cfa46d5173356
fetch darkriscv   https://github.com/MrJake222/darkriscv.git    dc3a6456ed7abc0db9ac7460f60bcec950ec21fb
fetch hazard3     https://github.com/MrJake222/Hazard3.git      2a45f589e4d5bf47caea7434bd8a161edec81ad9
