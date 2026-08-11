#!/usr/bin/env bash
# Gaara (Counselor) — the outside read, run on the Codex CLI (a different model
# than the Claude squad on purpose). Reviews a change holistically — correctness,
# security, and design together — and looks hardest for what the single-lens
# reviewers missed. Prints Codex's prose verdict to stdout.
#
# Usage:
#   gaara-codex.sh --workdir <abs> [--pr <url>] [--prior <file>]
#     --workdir   repo/worktree to run in (defaults to $PWD)
#   env GAARA_MODEL=<id>  force a model; otherwise the codex config's `model` wins
#                         (see the resolution block below — keep Gaara on the newest)
#     --pr        review a PR's diff (gh pr diff <url>); omit to review the
#                 uncommitted diff in --workdir (the /mission case)
#     --prior     a file of findings the Claude council already produced, so
#                 Gaara targets the gaps instead of repeating them
#
# Exit codes: 3 = codex not installed, 4 = empty diff (nothing to review).
# Both HALT the review — the caller asks the user to retry or stop, and must
# never substitute the Claude gaara agent for a failed run here.
set -euo pipefail

WORKDIR="$PWD"; PR=""; PRIOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) WORKDIR="$2"; shift 2 ;;
    --pr)      PR="$2";      shift 2 ;;
    --prior)   PRIOR="$2";   shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v codex >/dev/null 2>&1 || { echo "CODEX_UNAVAILABLE"; exit 3; }
cd "$WORKDIR"

if [ -n "$PR" ]; then
  DIFF="$(gh pr diff "$PR")"
else
  # Against HEAD, plus untracked files: some setups auto-stage every edit, and a
  # plain `git diff` reports those (and any add-only change) as an empty diff.
  DIFF="$(git diff HEAD)"
  UNTRACKED="$(git ls-files --others --exclude-standard)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    DIFF="${DIFF}"$'\n'"$(git diff --no-index -- /dev/null "$f" || true)"
  done <<< "$UNTRACKED"
fi
[ -n "${DIFF//[[:space:]]/}" ] || { echo "EMPTY_DIFF"; exit 4; }

PRIOR_TEXT="<none>"
[ -n "$PRIOR" ] && [ -f "$PRIOR" ] && PRIOR_TEXT="$(cat "$PRIOR")"

# Gaara must always run the NEWEST Codex model. A hard-coded pin rots silently —
# this sat on gpt-5.5 long after the CLI default moved on — so read the model from
# the codex config (kept current) and treat the pin only as a last resort.
# Order: $GAARA_MODEL → `model` in codex config → fallback pin.
CODEX_CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
MODEL="${GAARA_MODEL:-}"
if [ -z "$MODEL" ] && [ -f "$CODEX_CFG" ]; then
  MODEL="$(grep -m1 -E '^[[:space:]]*model[[:space:]]*=' "$CODEX_CFG" \
    | sed -E 's/.*=[[:space:]]*"?([^"#]*[^"# ])"?.*/\1/' || true)"
fi
[ -n "$MODEL" ] || MODEL="gpt-5.6-sol"
echo "gaara: codex model=${MODEL} reasoning=high" >&2

PROMPT="You are the outside reviewer — a different model than the team that wrote and
first reviewed this change. Review the diff below HOLISTICALLY: correctness,
security, and design together. Look hardest for what a single-lens reviewer would
MISS across lenses. Be concise and cite file:line for every finding. End with one
line: 'VERDICT: APPROVE' or 'VERDICT: REQUEST-CHANGES'.

The Claude council already flagged the following — do NOT just repeat these; find
what they missed:
${PRIOR_TEXT}

DIFF UNDER REVIEW:
${DIFF}"

# --sandbox read-only: Gaara reviews; it must never modify files during a review.
# The prompt (which embeds the full diff) goes via stdin ('-') so a large diff
# can't blow the ARG_MAX limit — PR diffs run to thousands of lines.
printf '%s' "$PROMPT" | codex exec --sandbox read-only \
  -m "$MODEL" \
  -c model_reasoning_effort="high" \
  -
