#!/usr/bin/env bash
# S3 resource check on a nextpnr log: the design must use exactly the
# expected number of block RAMs. A memory that Yosys fails to map to BRAM
# turns into hundreds of flip-flops, and the 1280-LC iCE40HX1K runs out of
# logic long before anything fails functionally (BUGS.md B-0004).
#
#   check_resources.sh build/nextpnr.log EXPECTED_BRAM
set -euo pipefail

log=$1
expected=$2
ram=$(grep -m1 'ICESTORM_RAM:' "$log" | sed -E 's/.*ICESTORM_RAM:\s*([0-9]+)\/.*/\1/')
lc=$(grep -m1 'ICESTORM_LC:' "$log" | sed -E 's/.*ICESTORM_LC:\s*([0-9]+)\/.*/\1/')
echo "$log: LCs=$lc BRAMs=$ram (expected $expected)"
if [ "$ram" != "$expected" ]; then
  echo "ERROR: expected $expected SB_RAM40_4K blocks, nextpnr placed $ram" >&2
  exit 1
fi
