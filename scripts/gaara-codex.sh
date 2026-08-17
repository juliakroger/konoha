#!/usr/bin/env bash
# Gaara (Counselor) — the outside read, run on the Codex CLI (a different model
# than the Claude squad on purpose). Reviews a change holistically — correctness,
# security, and design together — and looks hardest for what the single-lens
# reviewers missed. Prints Codex's prose verdict to stdout.
#
# Usage:
#   gaara-codex.sh --workdir <abs> [--pr <url>] [--prior <file>] [--plan <file>]
#     --workdir   repo/worktree to run in (defaults to $PWD)
#   env GAARA_MODEL=<id>        force a model; otherwise the codex config's `model` wins
#                               (see the resolution block below — keep Gaara on the newest)
#   env GAARA_REASONING=<tier>  model_reasoning_effort (default medium — high roughly
#                               doubled wall time on a mid-size PR for marginal gain)
#   env GAARA_FULL_DIFF=1       embed the whole diff; skip the tests/docs/lockfile trim
#     --pr        review a PR's diff (gh pr diff <url>); omit to review the
#                 uncommitted diff in --workdir (the /mission case)
#     --prior     a file of findings the Claude council already produced, so
#                 Gaara targets the gaps instead of repeating them
#     --plan      the architect's plan.md (/mission only) — the closer also
#                 verifies the diff implements it and flags unapproved
#                 design deviations
#
# Exit codes: 3 = codex not installed, 4 = empty diff (nothing to review).
# Both HALT the review — the caller asks the user to retry or stop, and must
# never substitute the Claude gaara agent for a failed run here.
set -euo pipefail

WORKDIR="$PWD"; PR=""; PRIOR=""; PLAN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) WORKDIR="$2"; shift 2 ;;
    --pr)      PR="$2";      shift 2 ;;
    --prior)   PRIOR="$2";   shift 2 ;;
    --plan)    PLAN="$2";    shift 2 ;;
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
# Single-pass emptiness check; ${DIFF//[[:space:]]/} is quadratic in bash 3.2 and
# spun for CPU-hours on a ~60KB diff.
[[ "$DIFF" == *[![:space:]]* ]] || { echo "EMPTY_DIFF"; exit 4; }

# Tests/docs/lockfiles dominate token cost but rarely move the verdict; strip them
# from the embedded diff. They stay listed in the prompt, and the read-only sandbox
# lets Gaara open them in the checkout when it wants them. GAARA_FULL_DIFF=1 skips.
TRIM_RE='^(tests?/|docs?/)|(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$|\.(snap|lock|svg)$'
OMITTED=""
if [ "${GAARA_FULL_DIFF:-0}" != "1" ]; then
  OMITTED="$(printf '%s\n' "$DIFF" | sed -n 's|^diff --git a/\(.*\) b/.*|\1|p' | grep -E "$TRIM_RE" || true)"
  if [ -n "$OMITTED" ]; then
    TRIMMED="$(printf '%s\n' "$DIFF" | awk -v re="$TRIM_RE" '
      /^diff --git a\// { path = $0; sub(/^diff --git a\//, "", path); sub(/ b\/.*/, "", path); keep = path !~ re }
      keep')"
    # a tests/docs-only change must still get a review — fall back to the full diff
    if [[ "$TRIMMED" == *[![:space:]]* ]]; then DIFF="$TRIMMED"; else OMITTED=""; fi
  fi
fi

PRIOR_TEXT="<none>"
[ -n "$PRIOR" ] && [ -f "$PRIOR" ] && PRIOR_TEXT="$(cat "$PRIOR")"
PLAN_TEXT="<none>"
[ -n "$PLAN" ] && [ -f "$PLAN" ] && PLAN_TEXT="$(cat "$PLAN")"

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
REASONING="${GAARA_REASONING:-medium}"
echo "gaara: codex model=${MODEL} reasoning=${REASONING}" >&2

PROMPT="You are the outside reviewer — a different model than the team that wrote and
first reviewed this change. One pass, holistic: correctness, security, and design
together. Hunt specifically for what single-lens reviewers MISS — lifecycle and
state interactions, API misuse, wrong assumptions the tests share with the code,
and designs that will bite the next change.

Rules:
- Do NOT repeat or re-litigate the council findings below; spend your budget on
  gaps. If you believe a council finding is wrong, refute it in one line instead.
- At most 6 findings, severity-ordered (HIGH/MED/LOW), one tight paragraph each,
  every finding citing file:line. No style nits.
- You are inside the repo checkout, read-only: open surrounding files when the
  diff alone is ambiguous — including any omitted files listed below.
- Write in ASD-STE100 Simplified Technical English: short sentences (max 20-25
  words), active voice, one topic per sentence, simple words, no idioms. Keep
  code identifiers and quoted output verbatim.
- End with exactly one line: 'VERDICT: APPROVE' or 'VERDICT: REQUEST-CHANGES'.

Council findings (do not repeat):
${PRIOR_TEXT}

Approved plan (when present, also verify the diff implements it; flag any
design deviation that carries no GRANTED ruling in the deviation log):
${PLAN_TEXT}

Changed files omitted from the diff for brevity (tests/docs/lockfiles — read them
in the checkout if relevant):
${OMITTED:-<none>}

DIFF UNDER REVIEW:
${DIFF}"

# --sandbox read-only: Gaara reviews; it must never modify files during a review.
# The prompt (which embeds the full diff) goes via stdin ('-') so a large diff
# can't blow the ARG_MAX limit — PR diffs run to thousands of lines.
printf '%s' "$PROMPT" | codex exec --sandbox read-only \
  -m "$MODEL" \
  -c model_reasoning_effort="$REASONING" \
  -
