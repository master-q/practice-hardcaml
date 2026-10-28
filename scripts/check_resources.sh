#!/usr/bin/env bash
# S3 resource check on a nextpnr log: the design must use exactly the
# expected number of block RAMs. A memory that Yosys fails to map to BRAM
# turns into hundreds of flip-flops, and the 1280-LC iCE40HX1K runs out of
# logic long before anything fails functionally (BUGS.md B-0004).
#
# It also enforces an upper bound on logic cells, so that an area
# regression (e.g. B-0004's collision logic coming back) fails the build
# instead of silently eating the headroom.
#
#   check_resources.sh build/nextpnr.log EXPECTED_BRAM [MAX_LC]
set -euo pipefail

log=$1
expected=$2
max_lc=${3:-}
ram=$(grep -m1 'ICESTORM_RAM:' "$log" | sed -E 's/.*ICESTORM_RAM:\s*([0-9]+)\/.*/\1/')
lc=$(grep -m1 'ICESTORM_LC:' "$log" | sed -E 's/.*ICESTORM_LC:\s*([0-9]+)\/.*/\1/')
echo "$log: LCs=$lc${max_lc:+ (max $max_lc)} BRAMs=$ram (expected $expected)"
status=0
if [ "$ram" != "$expected" ]; then
  echo "ERROR: expected $expected SB_RAM40_4K blocks, nextpnr placed $ram" >&2
  status=1
fi
if [ -n "$max_lc" ] && [ "$lc" -gt "$max_lc" ]; then
  echo "ERROR: $lc logic cells exceed the budget of $max_lc (MAX_LC in the project Makefile)" >&2
  status=1
fi
exit $status
