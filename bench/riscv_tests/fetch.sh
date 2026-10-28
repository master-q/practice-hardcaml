#!/usr/bin/env bash
# Fetch riscv-tests (riscv-software-src/riscv-tests) at a pinned commit, with
# its env submodule, into build/src. Self-checking tests: each one writes
# its result to `tohost` (1 = pass). Not committed; BSD licence.
set -euo pipefail
d=build/src
commit=3df703cd52d5f0d8224e3c50bf03c6cb70efff98
env_commit=6de71edb142be36319e380ce782c3d1830c65d68
marker="$d/.fetched-$commit"
if [ -f "$marker" ]; then exit 0; fi
rm -rf "$d"
git init -q "$d"
git -C "$d" remote add origin https://github.com/riscv-software-src/riscv-tests.git
git -C "$d" fetch -q --depth 1 origin "$commit"
git -C "$d" checkout -q FETCH_HEAD
git init -q "$d/env"
git -C "$d/env" remote add origin https://github.com/riscv/riscv-test-env.git
git -C "$d/env" fetch -q --depth 1 origin "$env_commit"
git -C "$d/env" checkout -q FETCH_HEAD
touch "$marker"
