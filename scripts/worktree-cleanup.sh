#!/usr/bin/env bash
# worktree-cleanup.sh — remove the worktree and the local branch of a merged PR, or refuse.
#
# A squash merge leaves the branch with no ancestor relation to the base, so git cannot tell that
# the work is merged: `git branch -d` refuses and `-D` deletes anything. This script is the check
# between the two. It removes nothing unless all of these are true:
#   - the tip of the local branch is the merged PR head, or an ancestor of it (no local-only commit);
#   - the worktree has no change to a tracked file and no untracked file;
#   - the worktree is not the main checkout and is not locked;
#   - no process runs from the worktree (a dev server, another agent session). A shell that is
#     open in the folder is a note, not a refusal;
#   - every ignored file is build output, a mission file, or a file the main checkout has too.
#     Other ignored files exist only here, so the user must see them first (--allow-ignored).
# Then it removes the worktree, deletes the local branch and the stale origin/<branch> ref.
# It never contacts the remote, and it never deletes a remote branch.
#
# Usage:
#   worktree-cleanup.sh <repo> <branch> --merged-head <sha> [--dry-run]
#                       [--allow-ignored] [--allow-local-commits]
#       <repo>         a path in the repository (the main checkout, not the worktree to remove)
#       --merged-head  the PR's headRefOid, 40 hex characters. Fetch refs/pull/<n>/head first.
#       --dry-run      run every check, print what a real run removes, change nothing
#       --allow-ignored, --allow-local-commits
#                      pass exit 7 or exit 3. Only after the user saw the list and said yes.
#
# Exit codes: 0 cleaned, or nothing to clean; 1 usage; 2 the merged head is not in the object
#   store; 3 the branch has commits that are not in the merged head; 4 the branch is checked out
#   in the main checkout, or the worktree is locked; 5 uncommitted changes or untracked files;
#   6 a process runs from the worktree; 7 ignored files that only this worktree has.
#   Exits 4, 5 and 6 have no override: the user changes the state, then the script runs again.
set -euo pipefail

usage() { sed -n '2,30p' "$0" >&2; exit 1; }
die() { code="$1"; shift; echo "worktree-cleanup: $*" >&2; exit "$code"; }
note() { echo "worktree-cleanup: note: $*" >&2; }

REPO=""; BRANCH=""; MERGED_HEAD=""; DRY_RUN=0; ALLOW_IGNORED=0; ALLOW_LOCAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --merged-head) [ $# -ge 2 ] || usage; MERGED_HEAD="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --allow-ignored) ALLOW_IGNORED=1; shift ;;
    --allow-local-commits) ALLOW_LOCAL=1; shift ;;
    -*) echo "unknown arg: $1" >&2; usage ;;
    *)
      if [ -z "$REPO" ]; then REPO="$1"
      elif [ -z "$BRANCH" ]; then BRANCH="$1"
      else usage
      fi
      shift ;;
  esac
done
[ -n "$REPO" ] && [ -n "$BRANCH" ] && [ -n "$MERGED_HEAD" ] || usage
# A short or empty sha can name another object, so only a full one is a safe reference.
[[ "$MERGED_HEAD" =~ ^[0-9a-f]{40}$ ]] || die 1 "--merged-head must be a full 40-character sha"

MAIN="$(git -C "$REPO" worktree list --porcelain | sed -n '1s/^worktree //p')" \
  || die 1 "not a git repository: $REPO"
[ -n "$MAIN" ] || die 1 "not a git repository: $REPO"

git -C "$MAIN" cat-file -e "$MERGED_HEAD^{commit}" 2>/dev/null \
  || die 2 "the merged head $MERGED_HEAD is not in the object store. Fetch refs/pull/<n>/head first."

BRANCH_REF="refs/heads/$BRANCH"
REMOTE_REF="refs/remotes/origin/$BRANCH"

WT="$(git -C "$MAIN" worktree list --porcelain | awk -v ref="$BRANCH_REF" '
  /^worktree / { path = substr($0, 10) }
  $0 == "branch " ref { print path }')"
LOCKED="$(git -C "$MAIN" worktree list --porcelain | awk -v ref="$BRANCH_REF" '
  /^worktree / { path = substr($0, 10); hit = 0 }
  $0 == "branch " ref { hit = 1 }
  /^locked/ && hit { print "yes" }')"

HAS_BRANCH=0
git -C "$MAIN" show-ref --verify --quiet "$BRANCH_REF" && HAS_BRANCH=1

if [ "$HAS_BRANCH" -eq 0 ] && [ -z "$WT" ]; then
  echo "nothing to clean: no local branch and no worktree for $BRANCH"
  exit 0
fi

if [ "$HAS_BRANCH" -eq 1 ]; then
  if ! git -C "$MAIN" merge-base --is-ancestor "$BRANCH_REF" "$MERGED_HEAD"; then
    if [ "$ALLOW_LOCAL" -eq 1 ]; then
      echo "commits on $BRANCH that are not in the merged head, deleted with it:"
      git -C "$MAIN" log --oneline "$MERGED_HEAD..$BRANCH_REF" | sed 's/^/  /'
    else
      echo "commits on $BRANCH that are not in the merged head:" >&2
      git -C "$MAIN" log --oneline "$MERGED_HEAD..$BRANCH_REF" >&2
      die 3 "$BRANCH has local commits that the merged PR does not have. Show them to the user, then pass --allow-local-commits."
    fi
  fi
fi

if [ -n "$WT" ]; then
  [ "$WT" != "$MAIN" ] || die 4 "$BRANCH is checked out in the main checkout $MAIN. Switch it to another branch first."
  [ -z "$LOCKED" ] || die 4 "the worktree $WT is locked. Unlock it first: git worktree unlock"

  STATUS="$(git -C "$WT" status --porcelain)"
  if [ -n "$STATUS" ]; then
    echo "$STATUS" >&2
    die 5 "$WT has uncommitted changes or untracked files"
  fi

  # +c 0 prints the full command name. lsof shows only this user's processes, which is the set
  # that can hold a dev server or an agent session.
  PROCS="$(lsof +c 0 -d cwd -Fpcn 2>/dev/null | awk -v wt="$WT" '
    /^p/ { pid = substr($0, 2) }
    /^c/ { cmd = substr($0, 2) }
    /^n/ { path = substr($0, 2); if (path == wt || index(path, wt "/") == 1) print pid "\t" cmd "\t" path }' || true)"
  if [ -n "$PROCS" ]; then
    SHELLS="$(printf '%s\n' "$PROCS" | awk -F'\t' '$2 ~ /^-?(zsh|bash|sh|fish)$/' || true)"
    OTHERS="$(printf '%s\n' "$PROCS" | awk -F'\t' '$2 !~ /^-?(zsh|bash|sh|fish)$/' || true)"
    if [ -n "$OTHERS" ]; then
      printf '%s\n' "$OTHERS" >&2
      die 6 "a process runs from $WT (pid, command, folder above). Stop it first."
    fi
    [ -z "$SHELLS" ] || note "a shell is open in $WT: $(printf '%s\n' "$SHELLS" | awk -F'\t' '{print $1}' | tr '\n' ' ')"
  fi

  # Ignored files: build output and mission files go without a word. A file that the main checkout
  # also has, under the same ignored path, is a copy or is made again by a command. All others
  # exist only in this worktree.
  UNKNOWN=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    trimmed="${path%/}"
    name="$(basename "$trimmed")"
    case "$name" in
      node_modules|.next|.turbo|dist|build|out|coverage|.vercel|.cache|test-results|playwright-report) continue ;;
      .DS_Store|.eslintcache|next-env.d.ts|plan.md|deviations.md) continue ;;
      *.tsbuildinfo|*.log|.env|.env.*) continue ;;
    esac
    [ -e "$MAIN/$trimmed" ] && continue
    UNKNOWN="${UNKNOWN}${path}"$'\n'
  done < <(git -C "$WT" status --porcelain --ignored | sed -n 's/^!! //p')
  if [ -n "$UNKNOWN" ]; then
    if [ "$ALLOW_IGNORED" -eq 1 ]; then
      echo "ignored files that only this worktree has, deleted with it:"
      printf '%s' "$UNKNOWN" | sed 's/^/  /'
    else
      printf '%s' "$UNKNOWN" >&2
      die 7 "$WT has ignored files that only this worktree has (above). Show them to the user, then pass --allow-ignored."
    fi
  fi
fi

BRANCH_SHA=""
[ "$HAS_BRANCH" -eq 0 ] || BRANCH_SHA="$(git -C "$MAIN" rev-parse "$BRANCH_REF")"

# The origin/<branch> ref is a local copy. It goes only when it holds nothing past the merged head.
DROP_REMOTE_REF=0
if git -C "$MAIN" show-ref --verify --quiet "$REMOTE_REF"; then
  if git -C "$MAIN" merge-base --is-ancestor "$REMOTE_REF" "$MERGED_HEAD"; then
    DROP_REMOTE_REF=1
  else
    note "$REMOTE_REF has commits that are not in the merged head, so it stays."
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  [ -z "$WT" ] || echo "would remove worktree: $WT"
  [ "$HAS_BRANCH" -eq 0 ] || echo "would delete branch: $BRANCH (at $BRANCH_SHA)"
  [ "$DROP_REMOTE_REF" -eq 0 ] || echo "would delete ref: $REMOTE_REF"
  echo "dry run: $BRANCH passes every check"
  exit 0
fi

if [ -n "$WT" ]; then
  # --force is needed for the ignored files and the submodule copy. The checks above are the guard.
  git -C "$MAIN" worktree remove --force "$WT"
  echo "removed worktree: $WT"
fi
if [ "$HAS_BRANCH" -eq 1 ]; then
  git -C "$MAIN" branch -D "$BRANCH" >/dev/null
  echo "deleted branch: $BRANCH (was $BRANCH_SHA)"
fi
if [ "$DROP_REMOTE_REF" -eq 1 ]; then
  git -C "$MAIN" update-ref -d "$REMOTE_REF"
  echo "deleted ref: $REMOTE_REF"
fi
git -C "$MAIN" worktree prune
echo "done: $BRANCH"
