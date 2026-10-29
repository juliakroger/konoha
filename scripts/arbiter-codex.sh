#!/usr/bin/env bash
# Gaara (Kazekage) — the ARBITER, run on the Codex CLI (a different model than
# the Claude squad on purpose). Claude plans and executes; when the executor
# wants to decline review findings, Codex rules on each one. Accepting a finding
# needs no ruling. From 0.3.0 to 0.10.0 this was architect-codex.sh and also
# authored the plan; since 0.11.0 Shikamaru plans.
#
# Usage:
#   arbiter-codex.sh --contested <file> --workdir <abs> [--plan <planfile>]
#
#   env ARBITER_MODEL=<id>       force a model; otherwise the newest `gpt-*-sol`
#                                the codex CLI lists wins, then the codex
#                                config's `model`, then the pin (codex-common.sh)
#   env ARBITER_REASONING=<tier> model_reasoning_effort; otherwise the codex
#                                config's `model_reasoning_effort` wins (the
#                                user's dial), then max — a ruling is one short
#                                call at maximum leverage
#
# Exit codes: 2 = bad usage, 3 = codex not installed, 4 = missing/empty input,
# 5 = codex returned no final message; any other non-zero code is codex's own.
# Any failure HALTS the caller — ask the user to retry or stop. NEVER write a
# ruling with a Claude agent instead: a same-family ruling under Gaara's name
# lets Claude approve its own declines. Every run is appended to
# ~/.konoha/codex-runs.jsonl (model, reasoning, exit, tokens).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

WORKDIR="$PWD"; CONTESTED=""; PLANFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir)   WORKDIR="$2";   shift 2 ;;
    --contested) CONTESTED="$2"; shift 2 ;;
    --plan)      PLANFILE="$2";  shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v codex >/dev/null 2>&1 || { echo "CODEX_UNAVAILABLE"; exit 3; }
cd "$WORKDIR"

[ -n "$CONTESTED" ] && [ -f "$CONTESTED" ] || { echo "MISSING_INPUT: --contested" >&2; exit 4; }
CONTESTED_TEXT="$(cat "$CONTESTED")"
[[ "$CONTESTED_TEXT" == *[![:space:]]* ]] || { echo "EMPTY_INPUT: --contested" >&2; exit 4; }
PLAN_TEXT="<none>"
[ -n "$PLANFILE" ] && [ -f "$PLANFILE" ] && PLAN_TEXT="$(cat "$PLANFILE")"

# Same resolution as gaara-codex.sh (codex-common.sh): never hard-code the newest
# GPT. Order: $ARBITER_MODEL → newest `gpt-*-sol` in the CLI's models cache →
# `model` in codex config → fallback pin. Reasoning: $ARBITER_REASONING → the
# config's `model_reasoning_effort` → max.
. "$SCRIPT_DIR/codex-common.sh"
MODEL="$(codex_resolve_model "${ARBITER_MODEL:-}")"
REASONING="$(codex_resolve_effort "${ARBITER_REASONING:-}" max)"

PROMPT="You are the arbiter — a different model than the team that planned, wrote,
and first reviewed this change. The executor asks to decline review findings.
Rule on each contested item. Your ruling is final.

Rules:
- For each item output exactly one line:
  RULING <id>: DENIED — <one short reason>    (the executor must fix it)
  RULING <id>: GRANTED — <one short reason>   (the decline is approved)
- Default to DENIED when the evidence is thin. Open the repo files (read-only)
  when the evidence needs checking.
- Write in ASD-STE100 Simplified Technical English: short sentences (max
  20-25 words), active voice, one topic per sentence, simple words, no idioms.
  Keep code identifiers, paths, and commands verbatim.
- No text after the last RULING line.

THE PLAN (context):
${PLAN_TEXT}

CONTESTED ITEMS (id, finding, executor objection, evidence):
${CONTESTED_TEXT}"

# stdin so a large contested file can't blow ARG_MAX; read-only sandbox (inside
# codex_run) — the arbiter rules, it never edits. codex_run prints the rulings
# to stdout and logs the run.
printf '%s' "$PROMPT" | codex_run arbiter arbitrate "$MODEL" "$REASONING"
