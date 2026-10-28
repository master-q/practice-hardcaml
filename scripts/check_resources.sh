#!/usr/bin/env bash
# S3 resource check on a nextpnr log (iCE40 or ECP5): the design must use
# exactly the expected number of block RAMs, and at most MAX_LC logic
# cells. A memory that synthesis fails to map to block RAM turns into
# hundreds of flip-flops long before anything fails functionally (B-0004),
# and the LC budget makes area regressions fail the build (B-0009).
#
#   check_resources.sh NEXTPNR_LOG EXPECTED_BRAM [MAX_LC]
#
# iCE40 counts ICESTORM_LC and ICESTORM_RAM (SB_RAM40_4K); ECP5 counts
# TRELLIS_COMB (LUT4 slots) and DP16KD.
set -euo pipefail

log=$1
expected=$2
max_lc=${3:-}
count() { grep -m1 -E "^Info:\s+$1:" "$log" | sed -E "s/.*$1:\s*([0-9]+)\/.*/\1/"; }
if grep -q 'ICESTORM_LC:' "$log"; then
  lc_name=ICESTORM_LC ram_name=ICESTORM_RAM
else
  lc_name=TRELLIS_COMB ram_name=DP16KD
fi
lc=$(count $lc_name)
ram=$(count $ram_name)
lc=${lc:-0} ram=${ram:-0}
echo "$log: $lc_name=$lc${max_lc:+ (max $max_lc)} $ram_name=$ram (expected $expected)"
status=0
if [ "$ram" != "$expected" ]; then
  echo "ERROR: expected $expected $ram_name blocks, nextpnr placed $ram" >&2
  status=1
fi
if [ -n "$max_lc" ] && [ "$lc" -gt "$max_lc" ]; then
  echo "ERROR: $lc $lc_name exceed the budget of $max_lc (MAX_LC in the project Makefile)" >&2
  status=1
fi
exit $status
