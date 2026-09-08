#!/usr/bin/env bash
# pr-body.sh — the only sanctioned way to change a PR body.
#
# Images belong to the user. She drags screenshots into the PR description in the
# browser (gh cannot upload an attachment). So an AI edit of a PR body must:
#   - carry every image / attachment reference the LIVE body has — verbatim, in the
#     same order, on its own line when it was on its own line;
#   - never add one (an AI cannot have uploaded it — the reference is stale or invented);
#   - never restore one she removed, never undo one she changed: the live body fetched
#     right before the edit is the reference, not a scratch draft and not memory.
#
# A "reference" is any of: an <img>/<video>/<source>/<picture> tag, a markdown image
# ![…](…), or a bare attachment URL (github.com/user-attachments/assets/…,
# github.com/<owner>/<repo>/assets/…, *.githubusercontent.com/…).
#
# Usage:
#   pr-body.sh check --body-file <file> [--pr <url>]
#       Compare <file> against the live body of <url>. Without --pr the live body is
#       empty, so <file> must carry no reference at all (the create-time check).
#   pr-body.sh edit --pr <url> --body-file <file> [--title <title>]
#       Run the check, then `gh pr edit <url> --body-file <file>` (+ --title), then
#       fetch the body again and confirm the references survived.
#   env PR_BODY_DRY_RUN=1   print the gh edit command instead of running it
#
# Exit codes: 0 ok; 1 usage or gh failure; 2 <file> breaks the image contract;
#   3 the references did not survive the edit.
# On 2 the caller puts the live references back into <file> — same text, same slot,
# own line — and re-runs. Never fall back to a direct `gh pr edit --body`.
set -euo pipefail

usage() { sed -n '2,29p' "$0" >&2; exit 1; }

ACTION="${1:-}"; [ -n "$ACTION" ] || usage; shift
PR=""; FILE=""; TITLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)        PR="$2";    shift 2 ;;
    --body-file) FILE="$2";  shift 2 ;;
    --title)     TITLE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done
case "$ACTION" in
  check) [ -n "$FILE" ] || usage ;;
  edit)  [ -n "$FILE" ] && [ -n "$PR" ] || usage ;;
  *) echo "unknown action: $ACTION" >&2; usage ;;
esac
[ -f "$FILE" ] || { echo "body file not found: $FILE" >&2; exit 1; }

TAG='<(img|video|source|picture)[^>]*>'
MD='!\[[^]]*\]\([^)]*\)'
URLCHARS="[^[:space:])>\"']+"
URL="https?://(github\.com/user-attachments/assets/${URLCHARS}|github\.com/[^/[:space:]]+/[^/[:space:]]+/assets/${URLCHARS}|(private-user-images|user-images|camo)\.githubusercontent\.com/${URLCHARS})"
PATTERN="${TAG}|${MD}|${URL}"

TMP="$(mktemp -d -t prbody)"; trap 'rm -rf "$TMP"' EXIT
LIVE="$TMP/live"; NEW="$TMP/new"

fetch_live() { gh pr view "$PR" --json body -q .body > "$1"; }
refs_of()    { tr -d '\r' < "$1" | grep -oiE "$PATTERN" || true; }
lines_of()   { tr -d '\r' < "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

# compare <live> <new> <label> → 0 ok, 1 contract broken (reasons on stderr)
compare() {
  local live="$1" new="$2" label="$3" bad=0 missing added ref
  refs_of "$live" > "$TMP/live.refs"; refs_of "$new" > "$TMP/new.refs"
  missing="$(comm -23 <(sort "$TMP/live.refs") <(sort "$TMP/new.refs"))"
  added="$(comm -13 <(sort "$TMP/live.refs") <(sort "$TMP/new.refs"))"
  if [ -n "$missing" ]; then
    bad=1; printf '%s: DROPPED image reference(s) the live body has:\n%s\n' "$label" "$missing" >&2
  fi
  if [ -n "$added" ]; then
    bad=1; printf '%s: ADDED image reference(s) the live body does not have:\n%s\n' "$label" "$added" >&2
  fi
  if [ "$bad" -eq 0 ] && ! cmp -s "$TMP/live.refs" "$TMP/new.refs"; then
    bad=1; printf '%s: image references are REORDERED — keep the live order.\n' "$label" >&2
  fi
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    grep -qxF -- "$ref" <<<"$missing" && continue
    if lines_of "$live" | grep -qxF -- "$ref" && ! lines_of "$new" | grep -qxF -- "$ref"; then
      bad=1; printf '%s: INLINED — this reference has its own line in the live body:\n%s\n' "$label" "$ref" >&2
    fi
  done < "$TMP/live.refs"
  if [ "$bad" -ne 0 ]; then
    printf '\nLive body references, with the line before each (put each one back in that slot, verbatim, on its own line):\n' >&2
    tr -d '\r' < "$live" | awk -v pat="$PATTERN" '
      { if (tolower($0) ~ tolower(pat)) { printf "  line %d: %s\n    after: %s\n", NR, $0, prev }
        if ($0 !~ /^[[:space:]]*$/) prev = $0 }' >&2
    return 1
  fi
  return 0
}

if [ -n "$PR" ]; then fetch_live "$LIVE"; else : > "$LIVE"; fi
cp "$FILE" "$NEW"

if ! compare "$LIVE" "$NEW" "check"; then
  echo "image contract broken — not editing. Images belong to the user; fix the body file and re-run." >&2
  exit 2
fi
echo "image contract ok: $(refs_of "$LIVE" | grep -c . || true) reference(s) carried"
[ "$ACTION" = "check" ] && exit 0

args=(--body-file "$FILE"); [ -n "$TITLE" ] && args+=(--title "$TITLE")
if [ "${PR_BODY_DRY_RUN:-}" = "1" ]; then
  printf 'dry run: gh pr edit %q' "$PR"; printf ' %q' "${args[@]}"; printf '\n'
  exit 0
fi
gh pr edit "$PR" "${args[@]}"

fetch_live "$TMP/after"
if ! compare "$LIVE" "$TMP/after" "post-edit"; then
  echo "the edit did not keep the image references — check the PR in the browser." >&2
  exit 3
fi
echo "edited: $PR"
