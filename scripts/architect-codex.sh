#!/usr/bin/env bash
# Gaara (Kazekage) — the DECISION MAKER, run on the Codex CLI (a different
# model than the Claude squad on purpose). Since 0.3.0 Codex decides the
# solution and Claude executes it. Two modes:
#
#   plan       Author plan.md — the decision record the mission executes.
#   arbitrate  Rule on contested items (declined findings, plan deviations).
#
# Usage:
#   architect-codex.sh plan      --dossier <file> --workdir <abs>
#                                [--revise <planfile> --findings <file>]
#   architect-codex.sh arbitrate --contested <file> --workdir <abs> [--plan <planfile>]
#
#   env ARCHITECT_MODEL=<id>       force a model; otherwise the codex config's
#                                  `model` wins, then the fallback pin
#   env ARCHITECT_REASONING=<tier> model_reasoning_effort (default high — the
#                                  plan is one call at maximum leverage)
#
# Exit codes: 2 = bad usage, 3 = codex not installed, 4 = missing/empty input.
# Any failure HALTS the caller — ask the user to retry or stop. NEVER author a
# plan or a ruling with a Claude agent instead: a same-family decision under
# the architect's name inverts the whole 0.3 design.
set -euo pipefail

MODE="${1:-}"; shift || true
case "$MODE" in
  plan|arbitrate) ;;
  *) echo "usage: architect-codex.sh plan|arbitrate [--flags]" >&2; exit 2 ;;
esac

WORKDIR="$PWD"; DOSSIER=""; REVISE=""; FINDINGS=""; CONTESTED=""; PLANFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir)   WORKDIR="$2";   shift 2 ;;
    --dossier)   DOSSIER="$2";   shift 2 ;;
    --revise)    REVISE="$2";    shift 2 ;;
    --findings)  FINDINGS="$2";  shift 2 ;;
    --contested) CONTESTED="$2"; shift 2 ;;
    --plan)      PLANFILE="$2";  shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v codex >/dev/null 2>&1 || { echo "CODEX_UNAVAILABLE"; exit 3; }
cd "$WORKDIR"

# $1 = path, $2 = label. Prints file content; halts on missing/blank input.
require_file() {
  [ -n "$1" ] && [ -f "$1" ] || { echo "MISSING_INPUT: $2" >&2; exit 4; }
  CONTENT="$(cat "$1")"
  [[ "$CONTENT" == *[![:space:]]* ]] || { echo "EMPTY_INPUT: $2" >&2; exit 4; }
  printf '%s' "$CONTENT"
}

# Same resolution as gaara-codex.sh: never hard-code the newest GPT.
# Order: $ARCHITECT_MODEL → `model` in codex config → fallback pin.
CODEX_CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
MODEL="${ARCHITECT_MODEL:-}"
if [ -z "$MODEL" ] && [ -f "$CODEX_CFG" ]; then
  MODEL="$(grep -m1 -E '^[[:space:]]*model[[:space:]]*=' "$CODEX_CFG" \
    | sed -E 's/.*=[[:space:]]*"?([^"#]*[^"# ])"?.*/\1/' || true)"
fi
[ -n "$MODEL" ] || MODEL="gpt-5.6-sol"
REASONING="${ARCHITECT_REASONING:-high}"
echo "architect: codex mode=${MODE} model=${MODEL} reasoning=${REASONING}" >&2

STE_RULE="Write in ASD-STE100 Simplified Technical English: short sentences (max
20-25 words), active voice, one topic per sentence, simple words, no idioms.
Keep code identifiers, paths, and commands verbatim."

if [ "$MODE" = "plan" ]; then
  DOSSIER_TEXT="$(require_file "$DOSSIER" "--dossier")"

  REVISION_BLOCK=""
  if [ -n "$REVISE" ] || [ -n "$FINDINGS" ]; then
    PRIOR_PLAN="$(require_file "$REVISE" "--revise")"
    REVIEW_FINDINGS="$(require_file "$FINDINGS" "--findings")"
    REVISION_BLOCK="This is a REVISION round. A reviewer checked your prior plan
against the real codebase. Revise the plan: change it for each valid finding,
or refute the finding in one line under a final '## Findings addressed'
section. Do not drop decisions the findings do not touch.

PRIOR PLAN:
${PRIOR_PLAN}

REVIEWER FINDINGS:
${REVIEW_FINDINGS}
"
  fi

  PROMPT="You are the architect and the decision maker for this change — a
different model than the team that will write and first review the code. You
decide the solution. The executor implements your plan and must not redesign
it, so make the plan prescriptive enough for mechanical execution: name files,
functions, signatures, and patterns.

Rules:
- You are inside the repo checkout, read-only. Read CLAUDE.md first and honor
  its conventions. Open the files you plan to change before you commit to an
  approach.
- ${STE_RULE}
- Output EXACTLY this markdown skeleton, nothing before or after:

# Plan: <short title>
## Decision
<the chosen approach and why>
## Rejected alternatives
- <alternative> — <why not>
## Changes
- <file path> — <exact change: functions to add/edit/delete, signatures, state>
## Forbidden
- <anti-patterns for THIS change — always include: no defensive latches, no
  workaround state, no new abstraction where an existing primitive fits;
  add the change-specific ones>
## Tests
- <test file — behaviors to cover, positive and negative>
## Open questions
- <only what genuinely blocks execution; else 'none'>

${REVISION_BLOCK}TASK DOSSIER:
${DOSSIER_TEXT}"

else
  CONTESTED_TEXT="$(require_file "$CONTESTED" "--contested")"
  PLAN_TEXT="<none>"
  [ -n "$PLANFILE" ] && [ -f "$PLANFILE" ] && PLAN_TEXT="$(cat "$PLANFILE")"

  PROMPT="You are the decision maker. The executor asks to decline review
findings or to deviate from the plan. Rule on each contested item. Your ruling
is final.

Rules:
- For each item output exactly one line:
  RULING <id>: DENIED — <one short reason>    (the executor must comply)
  RULING <id>: GRANTED — <one short reason>   (the decline/deviation is approved)
- Default to DENIED when the evidence is thin. Open the repo files (read-only)
  when the evidence needs checking.
- ${STE_RULE}
- No text after the last RULING line.

THE PLAN (context):
${PLAN_TEXT}

CONTESTED ITEMS (id, item, executor objection, evidence):
${CONTESTED_TEXT}"
fi

# stdin ('-') so a large dossier/diff can't blow ARG_MAX; read-only sandbox —
# the architect decides, it never edits.
printf '%s' "$PROMPT" | codex exec --sandbox read-only \
  -m "$MODEL" \
  -c model_reasoning_effort="$REASONING" \
  -
