#!/usr/bin/env bash
# Gaara (Counselor) — the outside read, run on the Codex CLI (a different model
# than the Claude squad on purpose). Reviews a change holistically — correctness,
# security, and design together — and looks hardest for what the single-lens
# reviewers missed. Prints Codex's prose verdict to stdout.
#
# Usage:
#   gaara-codex.sh --workdir <abs> [--pr <url>] [--prior <file>]
#     --workdir   repo/worktree to run in (defaults to $PWD)
#     --pr        review a PR's diff (gh pr diff <url>); omit to review the
#                 uncommitted diff in --workdir (the /mission case)
#     --prior     a file of findings the Claude council already produced, so
#                 Gaara targets the gaps instead of repeating them
#
# Exit codes: 3 = codex not installed (caller falls back to the Claude gaara
# agent), 4 = empty diff (nothing to review).
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
  DIFF="$(git diff)"
fi
[ -n "$DIFF" ] || { echo "EMPTY_DIFF"; exit 4; }

PRIOR_TEXT="<none>"
[ -n "$PRIOR" ] && [ -f "$PRIOR" ] && PRIOR_TEXT="$(cat "$PRIOR")"

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

exec codex exec --full-auto \
  --disable enable_request_compression \
  -c model_reasoning_effort="high" \
  "$PROMPT"
