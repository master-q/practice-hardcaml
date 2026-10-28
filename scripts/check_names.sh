#!/usr/bin/env bash
# Naming discipline for HardCaml-generated Verilog (see AGENTS.md).
#
# Fails if any flip-flop is anonymous: every target of a non-blocking
# assignment inside an `always @(posedge ...)` block must have a real name,
# given with let%hw, let%hw_var or (--), so it can be found in synthesis
# reports, timing paths and waveforms. HardCaml also uses `reg` and `<=` for
# combinational case statements (`always @*`); those are not flip-flops and
# are ignored (BUGS.md B-0003). HardCaml names every intermediate operator
# `_<N>`, so anonymous combinational wires are expected and only reported.
set -euo pipefail

status=0
for v in "$@"; do
  flops=$(awk '
    /always @\(posedge/ { seq = 1; next }
    /always @\*/        { seq = 0; next }
    /^[ \t]*end(module)?[ \t]*$/ && seq == 0 { next }
    seq && /<=/ {
      line = $0
      sub(/^[ \t]*/, "", line)
      sub(/[ \t]*<=.*/, "", line)
      sub(/\[.*/, "", line)
      print line
    }
    /^[ \t]*(assign|wire|reg|module|endmodule)\b/ { seq = 0 }
  ' "$v" | sort -u)
  anon_flops=$(printf '%s\n' "$flops" | grep -E '^_[0-9]+$' || true)
  n_flops=$(printf '%s' "$flops" | grep -c . || true)
  n_anon_flops=$(printf '%s' "$anon_flops" | grep -c . || true)
  wires=$(grep -cE '^\s*wire\b' "$v" || true)
  anon_wires=$(grep -cE '^\s*wire\b.*\b_[0-9]+;' "$v" || true)
  pct=0
  if [ "$wires" -gt 0 ]; then pct=$((100 * anon_wires / wires)); fi
  echo "$v: flops=$n_flops anonymous_flops=$n_anon_flops" \
       "wires=$wires anonymous_wires=$anon_wires (${pct}%)"
  if [ -n "$anon_flops" ]; then
    echo "ERROR: anonymous flip-flops in $v (name them with let%hw or --):" >&2
    printf '  %s\n' $anon_flops >&2
    status=1
  fi
done
exit $status
