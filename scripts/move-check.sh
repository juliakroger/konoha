#!/usr/bin/env bash
# move-check.sh — a move changes nothing (docs/ruled-out.md). Lists each file that a change renamed
# AND edited beyond its import lines, so the move and the edit can go in separate commits.
#
# Usage: move-check.sh --workdir <abs> --base <ref> [--head <ref>]
#   --base   the commit before the change (the merge base, or the head before a fix round)
#   --head   the commit after the change. Without it, the working tree is compared, new files
#            included, through a temporary index (the real index does not change)
#
# Output: one tab-separated line per finding: <similarity> <old path> <new path> <edited lines>
#   (edited lines = added + removed lines that are not import/export-from/require lines or blank)
# Exit codes: 0 no finding; 1 findings; 2 usage or not a git repository.
set -euo pipefail

WORKDIR="$PWD"; BASE=""; HEAD_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) WORKDIR="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --head) HEAD_REF="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BASE" ] || { sed -n '2,13p' "$0" >&2; exit 2; }
cd "$WORKDIR"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "move-check: not a git repository: $WORKDIR" >&2; exit 2; }

if [ -z "$HEAD_REF" ]; then
  TMP_INDEX="$(mktemp)"
  trap 'rm -f "$TMP_INDEX"' EXIT
  GIT_INDEX_FILE="$TMP_INDEX" git read-tree HEAD
  GIT_INDEX_FILE="$TMP_INDEX" git add -A
  HEAD_REF="$(GIT_INDEX_FILE="$TMP_INDEX" git write-tree)"
fi

FOUND=0
while IFS=$'\t' read -r status old new; do
  score="${status#R}"
  [ "$score" != "100" ] || continue
  edited="$(git diff -M "$BASE" "$HEAD_REF" -- "$old" "$new" | awk '
    /^(\+\+\+|---) / { next }
    /^[+-]/ {
      line = substr($0, 2)
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^[[:space:]]*import[[:space:](\{*]/) next
      if (line ~ /^[[:space:]]*export[[:space:]].*[[:space:]]from[[:space:]]/) next
      if (line ~ /require\(/) next
      if (line ~ /^[[:space:]]*\}?[[:space:]]*from[[:space:]]+["\047]/) next
      if (line ~ /^[[:space:]]*[A-Za-z0-9_$]+,?[[:space:]]*$/) next
      n++
    }
    END { print n + 0 }')"
  if [ "$edited" -gt 0 ]; then
    printf 'R%s\t%s\t%s\t%s\n' "$score" "$old" "$new" "$edited"
    FOUND=1
  fi
done < <(git diff -M --diff-filter=R --name-status "$BASE" "$HEAD_REF")

exit "$FOUND"
