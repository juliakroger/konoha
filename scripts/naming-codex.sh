#!/usr/bin/env bash
# naming-codex.sh — the naming pass, run on the Codex CLI (a different model than the Claude that
# wrote the code, on purpose: an author does not see its own coinages). Codex checks the list of
# new module-level names of a change (new-names.sh) against the names the base already uses and
# against the Names section of docs/ruled-out.md. It only flags; the user or Kakashi picks a name.
#
# Usage: naming-codex.sh --workdir <abs> --base <ref> [--head <ref>]
#   env NAMING_MODEL=<id>        force a model; otherwise the newest `gpt-*-sol` (codex-common.sh)
#   env NAMING_REASONING=<tier>  model_reasoning_effort; otherwise the codex config's, then high
#
# Output: Codex's flags, then one last line `NAMING: CLEAN` or `NAMING: <n> FLAGS`.
# Exit codes: 2 usage; 3 codex not installed; 4 no new name (nothing to check: the caller goes on);
#   5 codex returned no final message; any other non-zero code is codex's own. Exit 3, 5 and
#   codex's own codes HALT the caller, as for Gaara: retry or stop, never a Claude substitute.
#   Every run is appended to ~/.konoha/codex-runs.jsonl.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

WORKDIR="$PWD"; BASE=""; HEAD_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) WORKDIR="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --head) HEAD_ARGS=(--head "$2"); shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BASE" ] || { sed -n '2,17p' "$0" >&2; exit 2; }
command -v codex >/dev/null 2>&1 || { echo "CODEX_UNAVAILABLE"; exit 3; }

NAMES="$("$SCRIPT_DIR/new-names.sh" --workdir "$WORKDIR" --base "$BASE" ${HEAD_ARGS[@]+"${HEAD_ARGS[@]}"})"
[ -n "$NAMES" ] || { echo "NO_NEW_NAMES"; exit 4; }
COUNT="$(printf '%s\n' "$NAMES" | wc -l | tr -d ' ')"
BASE_SHA="$(git -C "$WORKDIR" rev-parse "$BASE")"
RULES="$(sed -n '/^## Names/,/^## Reviews/p' "$SCRIPT_DIR/../docs/ruled-out.md" | sed '$d')"

. "$SCRIPT_DIR/codex-common.sh"
MODEL="$(codex_resolve_model "${NAMING_MODEL:-}")"
REASONING="$(codex_resolve_effort "${NAMING_REASONING:-}" high)"

PROMPT="You review NAMES only, for a change that another model wrote. You are inside the repo
checkout, read-only. The base commit is ${BASE_SHA}: search it with
\`git grep -n -w <word> ${BASE_SHA} -- '*.ts' '*.tsx'\` and read files with
\`git show ${BASE_SHA}:<path>\`. Read the new code in the checkout.

Flag a new name when:
1. it is a second name for a concept the base already names (cite the base name and its path);
2. two or more new names mean the same thing, or one word means different things in the change;
3. it is a vague word on its own (data, info, entry, run, handle, process, manager, util, finish,
   held) or jargon that a reader outside the conversation would not understand;
4. it only forwards to or renames another function (the function itself is the finding);
5. a library of the repo (tMachine, zustand, zod, TanStack) has its own term for it.

Do not flag a name only because you prefer another style. Do not flag test names.

Rules of the repo for names:
${RULES}

Output: at most 15 flags, most important first, one line each:
- \`<name>\` (<path>:<line>): <the problem in one sentence>. Suggest: \`<a better name>\` or 'remove'.
Write in ASD-STE100 Simplified Technical English: short sentences, active voice, simple words.
End with exactly one line: 'NAMING: CLEAN' when you flag nothing, else 'NAMING: <n> FLAGS'.

The ${COUNT} new names (name, kind, path:line):
${NAMES}"

cd "$WORKDIR"
printf '%s' "$PROMPT" | codex_run naming review "$MODEL" "$REASONING"
