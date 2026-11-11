#!/usr/bin/env bash
# worktree-setup.sh — make a worktree of the terminal repo runnable. Safe to run again.
#
# A worktree inherits no untracked file, and its submodules stay empty. The script:
#   - copies each env file from the main checkout. A tracked .env.example marks the folder that
#     reads its .env: apps/<app>/, never the worktree root. `next dev` reads the file from its app
#     folder. A root .env does nothing: APP_ENV falls back to development, and FIREBASE_* and
#     REOWN_PROJECT_ID stay missing. An env file that the worktree already has stays as it is.
#   - copies each submodule from the main checkout, minus .git, so git sees nothing to commit.
#     `git submodule update` uses SSH, which pops the YubiKey dialog.
#   - installs node_modules in the worktree. A symlink to the main checkout resolves @tplus/* to
#     the main checkout's packages/. The install runs no lifecycle script, because /exam reads a
#     colleague's PR, and uses a scratch HOME, because Bun sends the tokens in ~/.npmrc.
#
# Usage:
#   worktree-setup.sh <worktree> [--app-env <development|staging|preprod|production>]
#       --app-env writes APP_ENV to apps/terminal/.env. Without it the copied value stays.
#
# Exit codes: 0 ok; 1 usage; 2 no apps/terminal/.env to write APP_ENV to, or the write failed;
#   3 the install failed; 4 the setup changed `git status`, so it can reach a commit or a review.
set -euo pipefail

APP_ENV_FILE="apps/terminal/.env"

usage() { sed -n '2,20p' "$0" >&2; exit 1; }
die() { code="$1"; shift; echo "worktree-setup: $*" >&2; exit "$code"; }
warn() { echo "worktree-setup: warning: $*" >&2; }

TARGET=""; APP_ENV_VALUE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --app-env) [ $# -ge 2 ] || usage; APP_ENV_VALUE="$2"; shift 2 ;;
    -*) echo "unknown arg: $1" >&2; usage ;;
    *) [ -z "$TARGET" ] || usage; TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || usage

# resolveEnvName turns an unknown name into staging without a word, so a typo must stop here.
case "$APP_ENV_VALUE" in
  ""|development|staging|preprod|production) ;;
  *) die 1 "unknown APP_ENV: $APP_ENV_VALUE" ;;
esac

WT="$(git -C "$TARGET" rev-parse --show-toplevel)" || die 1 "not a git worktree: $TARGET"
MAIN="$(git -C "$WT" worktree list --porcelain | sed -n '1s/^worktree //p')"
[ "$WT" != "$MAIN" ] || die 1 "$WT is the main checkout, not a worktree"

if [ -n "$APP_ENV_VALUE" ] && [ ! -f "$WT/$APP_ENV_FILE" ] && [ ! -f "$MAIN/$APP_ENV_FILE" ]; then
  die 2 "the main checkout has no $APP_ENV_FILE to copy"
fi

STATUS_BEFORE="$(git -C "$WT" status --porcelain)"

git -C "$WT" ls-files '*.env.example' | while IFS= read -r example; do
  dir="$(dirname "$example")"
  if [ -e "$WT/$dir/.env" ]; then
    echo "env: $dir/.env kept"
  elif [ -f "$MAIN/$dir/.env" ]; then
    cp -p "$MAIN/$dir/.env" "$WT/$dir/.env"
    echo "env: $dir/.env copied"
  else
    echo "env: $dir/.env not in the main checkout"
  fi
done

if [ -n "$APP_ENV_VALUE" ]; then
  env_file="$WT/$APP_ENV_FILE"
  [ -f "$env_file" ] || die 2 "$APP_ENV_FILE was not copied"
  if grep -q '^APP_ENV=' "$env_file"; then
    sed -i '' "s/^APP_ENV=.*/APP_ENV=$APP_ENV_VALUE/" "$env_file"
  else
    # The leading newline protects a last line that has no newline of its own.
    printf '\nAPP_ENV=%s\n' "$APP_ENV_VALUE" >> "$env_file"
  fi
  grep -qx "APP_ENV=$APP_ENV_VALUE" "$env_file" || die 2 "APP_ENV was not written to $APP_ENV_FILE"
  echo "env: APP_ENV=$APP_ENV_VALUE in $APP_ENV_FILE"
fi

if [ -f "$WT/.gitmodules" ]; then
  git -C "$WT" config -f .gitmodules --get-regexp '\.path$' | while read -r _ sub; do
    if [ -e "$WT/$sub/.git" ]; then
      echo "submodule: $sub already initialized"
    elif [ -z "$(ls -A "$MAIN/$sub" 2>/dev/null)" ]; then
      warn "$sub is empty in the main checkout. Specs that need it will fail."
    else
      rsync -a --exclude .git "$MAIN/$sub/" "$WT/$sub/"
      echo "submodule: $sub copied"
      pinned="$(git -C "$WT" rev-parse -q --verify "HEAD:$sub" || true)"
      copied="$(git -C "$MAIN/$sub" rev-parse HEAD)"
      [ "$pinned" = "$copied" ] || warn "$sub is pinned at ${pinned:-nothing}, but the copy is $copied."
    fi
  done
fi

if [ -f "$WT/bun.lock" ]; then
  REAL_HOME="$HOME"
  SCRATCH_HOME="$(mktemp -d)"
  trap 'rm -rf "$SCRATCH_HOME"' EXIT
  (
    cd "$WT" || exit 1
    export BUN_INSTALL_CACHE_DIR="${BUN_INSTALL_CACHE_DIR:-$REAL_HOME/.bun/install/cache}"
    export PATH="$REAL_HOME/.bun/bin:$PATH"
    export HOME="$SCRATCH_HOME"
    bun install --frozen-lockfile --ignore-scripts
  ) || die 3 "bun install failed in $WT"
else
  warn "$WT has no bun.lock, so nothing was installed."
fi

[ "$(git -C "$WT" status --porcelain)" = "$STATUS_BEFORE" ] \
  || die 4 "the setup changed git status in $WT. Do not commit it. Run: git -C $WT status"

# Node 26 has its own Web Storage global, and the storage specs fail on it with no real defect.
if [ -f "$WT/.nvmrc" ]; then
  NODE_BIN="$HOME/.nvm/versions/node/$(cat "$WT/.nvmrc")/bin"
  if [ -x "$NODE_BIN/node" ]; then
    echo "node: run gates and specs with PATH=\"$NODE_BIN:\$PATH\""
  else
    warn "the .nvmrc Node is not at $NODE_BIN, so specs can fail with no real defect."
  fi
fi

echo "ready: $WT"
