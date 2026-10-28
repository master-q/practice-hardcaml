#!/usr/bin/env bash
# Print a placed-and-routed configuration without its block RAM contents,
# so two configurations can be compared for logic changes:
#   iCE40 .asc: drops .ram_data sections
#   ECP5 textual .config: drops .bram_init sections and the .tile_group
#   headers (ecpbram rewrites them with repeated tile names; the packed
#   bitstream is unaffected)
set -euo pipefail
awk '
  /^\./ { skip = ($1 == ".ram_data" || $1 == ".bram_init") }
  /^\.tile_group/ { next }
  !skip
' "$1"
