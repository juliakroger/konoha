#!/usr/bin/env bash
# codex-common.sh — shared by gaara-codex.sh and arbiter-codex.sh. Source it:
#   . "$(cd "$(dirname "$0")" && pwd)/codex-common.sh"
#
# Provides:
#   codex_resolve_model  <override>            the model Gaara runs on, in this order:
#                                                1. <override> ($GAARA_MODEL / $ARBITER_MODEL)
#                                                2. the newest visible `gpt-<version>-sol` in the
#                                                   CLI's own models cache (~/.codex/models_cache.json,
#                                                   refreshed by the CLI) — "always the newest sol"
#                                                3. `model` in ~/.codex/config.toml
#                                                4. the fallback pin below
#   codex_resolve_effort <override> <fallback> model_reasoning_effort, in this order:
#                                                <override> → `model_reasoning_effort` in config.toml
#                                                → <fallback>. The user's config is the dial; the
#                                                scripts no longer carry their own lower default.
#   codex_run <label> <mode> <model> <effort>  runs `codex exec --sandbox read-only --json` on the
#                                                prompt from stdin, prints the final message to
#                                                stdout, surfaces codex's own error on failure, and
#                                                appends one record to ~/.konoha/codex-runs.jsonl
#                                                (ts, script, mode, model, reasoning, exit, seconds,
#                                                token usage) so every Codex call is visible.
#                                                Exit 5 = EMPTY_OUTPUT (codex exited 0 with no final
#                                                message) — the caller treats it as a failure.
#
# Bash 3.2-safe (macOS /bin/bash): no associative arrays, no mapfile, no ${var,,}. JSON is parsed
# with python3 when present; the grep/awk fallbacks keep the resolution working without it.

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_CFG="$CODEX_HOME_DIR/config.toml"
CODEX_MODELS_CACHE="$CODEX_HOME_DIR/models_cache.json"
CODEX_RUN_LOG="${KONOHA_CODEX_LOG:-$HOME/.konoha/codex-runs.jsonl}"
CODEX_FALLBACK_MODEL="gpt-6.1-sol"

# $1 = key → the value of a top-level `key = "value"` line in config.toml (empty when absent)
codex_cfg_value() {
  [ -f "$CODEX_CFG" ] || return 0
  grep -m1 -E "^[[:space:]]*$1[[:space:]]*=" "$CODEX_CFG" \
    | sed -E 's/^[^=]*=[[:space:]]*"?([^"#]*[^"# ])"?.*/\1/' || true
}

# The newest visible gpt-<version>-sol slug in the CLI's models cache (empty when unknown).
codex_newest_sol() {
  [ -f "$CODEX_MODELS_CACHE" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 -I - "$CODEX_MODELS_CACHE" <<'PY' 2>/dev/null || true
import json, re, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
best = None
for model in data.get('models') or []:
    slug = model.get('slug') or ''
    match = re.match(r'^gpt-(\d+(?:\.\d+)*)-sol$', slug)
    if not match or model.get('visibility') == 'hide':
        continue
    version = tuple(int(part) for part in match.group(1).split('.'))
    if best is None or version > best[0]:
        best = (version, slug)
if best:
    print(best[1])
PY
  else
    grep -oE '"slug":[[:space:]]*"gpt-[0-9.]+-sol"' "$CODEX_MODELS_CACHE" 2>/dev/null \
      | sed -E 's/.*"(gpt-[0-9.]+-sol)".*/\1/' \
      | awk -F'[-.]' '{ minor = ($3 ~ /^[0-9]+$/) ? $3 : 0; printf "%05d.%05d %s\n", $2, minor, $0 }' \
      | sort -r | head -1 | cut -d' ' -f2
  fi
}

# $1 = env override → the resolved model (see the header for the order)
codex_resolve_model() {
  local model="${1:-}" cfg_model
  [ -n "$model" ] || model="$(codex_newest_sol)"
  cfg_model="$(codex_cfg_value model)"
  [ -n "$model" ] || model="$cfg_model"
  [ -n "$model" ] || model="$CODEX_FALLBACK_MODEL"
  if [ -n "$cfg_model" ] && [ "$cfg_model" != "$model" ]; then
    echo "codex: config.toml model=${cfg_model} is not the newest sol; using ${model}" >&2
  fi
  printf '%s' "$model"
}

# $1 = env override, $2 = fallback → the resolved reasoning effort
codex_resolve_effort() {
  local effort="${1:-}"
  [ -n "$effort" ] || effort="$(codex_cfg_value model_reasoning_effort)"
  [ -n "$effort" ] || effort="$2"
  printf '%s' "$effort"
}

# $1 = events file → the usage object of the turn.completed event, or {}
codex_usage_json() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -I - "$1" <<'PY' 2>/dev/null || printf '{}'
import json, sys
usage = {}
for line in open(sys.argv[1]):
    try:
        event = json.loads(line)
    except Exception:
        continue
    if event.get('type') == 'turn.completed' and isinstance(event.get('usage'), dict):
        usage = event['usage']
keys = ('input_tokens', 'cached_input_tokens', 'output_tokens', 'reasoning_output_tokens')
print(json.dumps({key: usage.get(key, 0) for key in keys}))
PY
  else
    printf '{}'
  fi
}

# label mode model effort exit seconds usage-json → one line appended to the run log
codex_log_run() {
  local dir workdir usage
  dir="$(dirname "$CODEX_RUN_LOG")"
  mkdir -p "$dir" 2>/dev/null || return 0
  workdir="$(printf '%s' "$PWD" | sed 's/["\\]/\\&/g')"
  usage="${7:-}"; [ -n "$usage" ] || usage='{}'
  printf '{"ts":"%s","script":"%s","mode":"%s","model":"%s","reasoning":"%s","exit":%s,"seconds":%s,"workdir":"%s","usage":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" "$5" "$6" "$workdir" "$usage" \
    >> "$CODEX_RUN_LOG" 2>/dev/null || true
}

# $1 label (gaara|arbiter), $2 mode (review|arbitrate), $3 model, $4 effort; prompt on stdin.
# Prints the final message to stdout. Returns codex's exit code, or 5 when codex exited 0 with an
# empty final message. Callers run under `set -e`, so a failure halts them — fail closed.
codex_run() {
  local label="$1" mode="$2" model="$3" effort="$4"
  local tmp events last rc t0 secs usage
  tmp="$(mktemp -d -t konoha-codex)"; events="$tmp/events.jsonl"; last="$tmp/last.md"
  : > "$last"
  echo "${label}: codex ${mode} model=${model} reasoning=${effort}" >&2
  t0="$(date +%s)"
  set +e
  codex exec --sandbox read-only --json \
    -m "$model" \
    -c model_reasoning_effort="$effort" \
    -o "$last" - > "$events" 2> "$tmp/stderr"
  rc=$?
  set -e
  secs=$(( $(date +%s) - t0 ))
  if [ "$rc" -ne 0 ]; then
    # codex reports the cause as JSON events on stdout; show them, then the stderr tail
    grep -E '"type":"(error|turn\.failed)"' "$events" | head -3 >&2 || true
    tail -5 "$tmp/stderr" >&2 || true
  elif ! [ -s "$last" ] || ! [[ "$(cat "$last")" == *[![:space:]]* ]]; then
    rc=5
    echo "EMPTY_OUTPUT: codex exited 0 with no final message" >&2
    tail -5 "$tmp/stderr" >&2 || true
  fi
  usage="$(codex_usage_json "$events")"
  codex_log_run "$label" "$mode" "$model" "$effort" "$rc" "$secs" "$usage"
  echo "${label}: codex ${mode} exit=${rc} ${secs}s usage=${usage}" >&2
  [ "$rc" -eq 0 ] && cat "$last"
  rm -rf "$tmp"
  return "$rc"
}
