#!/usr/bin/env bash
# Repository language policy: every tracked file and path is ASCII-only
# English (see AGENTS.md).
#
#   check_ascii.sh             check all tracked files (CI, make langcheck)
#   check_ascii.sh --staged    check the index (pre-commit hook)
#   check_ascii.sh --message F check a commit message file (commit-msg hook)
set -euo pipefail

bad=0
report() { echo "ERROR: non-ASCII $1" >&2; bad=1; }

case "${1:-}" in
  --message)
    # Ignore comment lines git strips anyway (e.g. the verbose diff).
    if grep -v '^#' "$2" | LC_ALL=C grep -nP '[^\x00-\x7F]' >&2; then
      report "characters in the commit message (write it in English)"
    fi
    ;;
  --staged)
    while IFS= read -r -d '' path; do
      if printf '%s' "$path" | LC_ALL=C grep -qP '[^\x00-\x7F]'; then
        report "file name: $path"
      fi
      # Skip binary blobs (grep -I); check the staged content, not the worktree.
      if git show ":$path" | LC_ALL=C grep -nIP '[^\x00-\x7F]' > /tmp/check_ascii.$$ 2>/dev/null; then
        sed "s|^|$path:|" /tmp/check_ascii.$$ >&2
        report "characters in $path"
      fi
    done < <(git -c core.quotepath=off diff --cached --name-only -z --diff-filter=ACMR)
    rm -f /tmp/check_ascii.$$
    ;;
  "")
    while IFS= read -r -d '' path; do
      if printf '%s' "$path" | LC_ALL=C grep -qP '[^\x00-\x7F]'; then
        report "file name: $path"
      fi
      if [ -f "$path" ] && LC_ALL=C grep -nIP '[^\x00-\x7F]' "$path" > /tmp/check_ascii.$$; then
        sed "s|^|$path:|" /tmp/check_ascii.$$ >&2
        report "characters in $path"
      fi
    done < <(git -c core.quotepath=off ls-files -z)
    rm -f /tmp/check_ascii.$$
    [ "$bad" -eq 0 ] && echo "OK: all tracked files are ASCII-clean"
    ;;
  *) echo "usage: $0 [--staged | --message FILE]" >&2; exit 2 ;;
esac
exit $bad
