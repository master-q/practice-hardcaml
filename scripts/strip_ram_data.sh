#!/usr/bin/env bash
# Print an iCE40 .asc bitstream without its .ram_data sections (the BRAM
# initial contents), so two bitstreams can be compared for logic changes.
set -euo pipefail
awk '/^\./ { skip = ($1 == ".ram_data") } !skip' "$1"
