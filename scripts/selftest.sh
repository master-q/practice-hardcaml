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
./check_resources.sh "$tmp/nextpnr.log" 9 9 > /dev/null 2>&1 && fail "check_resources accepted 10 LCs for a budget of 9"
./check_resources.sh "$tmp/nextpnr.log" 9 10 > /dev/null 2>&1 || fail "check_resources rejected 10 LCs for a budget of 10"

# The ASCII check must reject a non-ASCII commit message.
printf 'caf\xc3\xa9\n' > "$tmp/msg"
./check_ascii.sh --message "$tmp/msg" > /dev/null 2>&1 && fail "check_ascii accepted a non-ASCII message"

# GitHub text policy (agent hooks): non-ASCII issue text is denied,
# English is allowed, unrelated commands are out of scope.
policy=./hooks/github-text-ascii-policy.sh
printf '%s' '{"tool_name":"mcp__github__issue_write","tool_input":{"title":"\u5272\u308a\u8fbc\u307f"}}' \
  | $policy > /dev/null && fail "github policy accepted a non-ASCII issue title"
printf '%s' '{"tool_name":"mcp__github__issue_write","tool_input":{"title":"Interrupts"}}' \
  | $policy > /dev/null || fail "github policy rejected an English issue"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title \u5272"}}' \
  | $policy > /dev/null && fail "github policy accepted gh issue create with non-ASCII"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo \u5272"}}' \
  | $policy > /dev/null || fail "github policy blocked an unrelated command"

# The toolchain check must reject tools that are not the pinned ones.
PATH=/usr/bin:/bin ./toolchain.sh check > /dev/null 2>&1 && fail "toolchain check accepted an unpinned PATH"

echo "OK: check self-tests"
