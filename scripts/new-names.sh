#!/usr/bin/env bash
# new-names.sh — list the module-level names that a change adds and the base does not have, for
# the Codex naming pass (naming-codex.sh) and for the count in a review.
#
# Usage: new-names.sh --workdir <abs> --base <ref> [--head <ref>]
#   --base   the commit before the change
#   --head   the commit after the change. Without it, the working tree is compared, new files
#            included, through a temporary index (the real index does not change)
#
# A name is a top-level declaration (no indentation) in a .ts/.tsx/.js/.jsx/.mjs file outside the
# tests: const, let, var, function, class, type, interface, enum, with or without export. A name
# that the base already declares anywhere in those files is not new.
# Output: one tab-separated line per new name: <name> <kind> <path>:<line>
# Exit codes: 0 done (no output = no new name); 2 usage or not a git repository.
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
[ -n "$BASE" ] || { sed -n '2,15p' "$0" >&2; exit 2; }
cd "$WORKDIR"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "new-names: not a git repository: $WORKDIR" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [ -z "$HEAD_REF" ]; then
  GIT_INDEX_FILE="$TMP/index" git read-tree HEAD
  GIT_INDEX_FILE="$TMP/index" git add -A
  HEAD_REF="$(GIT_INDEX_FILE="$TMP/index" git write-tree)"
fi

DECL='^(export[[:space:]]+)?(default[[:space:]]+)?(declare[[:space:]]+)?(abstract[[:space:]]+)?(async[[:space:]]+)?(const|let|var|function\*?|class|type|interface|enum)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*'
PATHS=('*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' ':(exclude)*.spec.*' ':(exclude)*.test.*' ':(exclude)**/tests/**' ':(exclude)**/test/**' ':(exclude)**/__tests__/**')

# The names the base declares.
git grep -h -I -E "$DECL" "$BASE" -- "${PATHS[@]}" 2>/dev/null \
  | sed -E 's/^(export[[:space:]]+)?(default[[:space:]]+)?(declare[[:space:]]+)?(abstract[[:space:]]+)?(async[[:space:]]+)?(const|let|var|function\*?|class|type|interface|enum)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*).*/\7/' \
  | sort -u > "$TMP/base.txt" || true

# The names the change adds, with the new line number of each.
git diff -U0 --no-color "$BASE" "$HEAD_REF" -- "${PATHS[@]}" | awk -v decl="$DECL" '
  /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
  /^@@ / {
    split($3, a, ","); line = substr(a[1], 2) + 0; next
  }
  /^\+/ {
    text = substr($0, 2)
    if (text ~ decl) {
      s = text
      sub(/^(export[ \t]+)?(default[ \t]+)?(declare[ \t]+)?(abstract[ \t]+)?(async[ \t]+)?/, "", s)
      kind = s; sub(/[ \t].*/, "", kind)
      name = s; sub(/^[^ \t]+[ \t]+/, "", name); sub(/[^A-Za-z0-9_$].*/, "", name)
      print name "\t" kind "\t" path ":" line
    }
    line++
    next
  }' | sort -u -t$'\t' -k1,1 > "$TMP/added.tsv"

awk -F'\t' 'NR == FNR { base[$1] = 1; next } !($1 in base)' "$TMP/base.txt" "$TMP/added.tsv" | sort -t$'\t' -k3
