#!/usr/bin/env bash
# Negative tests for the S3 checks themselves: each check must reject a
# known-bad input and accept a known-good one (BUGS.md B-0007, B-0008).
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL selftest: $1" >&2; exit 1; }

# An indented anonymous flip-flop must be rejected; an anonymous
# combinational `always @*` target must not count.
cat > "$tmp/anon.v" <<'V'
module m;
    reg [3:0] _12;
    reg [3:0] _13;
    always @(posedge c) begin
        _12 <= x;
    end
    always @* begin
        case (s)
        0:
            _13 <= y;
        endcase
    end
endmodule
V
./check_names.sh "$tmp/anon.v" > /dev/null 2>&1 && fail "check_names accepted an anonymous flip-flop"
sed 's/_12/count/g' "$tmp/anon.v" > "$tmp/named.v"
./check_names.sh "$tmp/named.v" > /dev/null 2>&1 || fail "check_names rejected a combinational case mux"

# The BRAM check must reject a count mismatch.
printf 'Info: \t        ICESTORM_LC:   10/ 1280\nInfo: \t        ICESTORM_RAM:    9/   16\n' > "$tmp/nextpnr.log"
./check_resources.sh "$tmp/nextpnr.log" 10 > /dev/null 2>&1 && fail "check_resources accepted 9 BRAMs for 10"
./check_resources.sh "$tmp/nextpnr.log" 9 > /dev/null 2>&1 || fail "check_resources rejected a match"

# The ASCII check must reject a non-ASCII commit message.
printf 'caf\xc3\xa9\n' > "$tmp/msg"
./check_ascii.sh --message "$tmp/msg" > /dev/null 2>&1 && fail "check_ascii accepted a non-ASCII message"

echo "OK: S3 check self-tests"
