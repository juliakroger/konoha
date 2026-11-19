#!/usr/bin/env bash
# worktree-sweep.sh — sort every worktree and local branch of a repository for /cleanup-worktrees.
#
# It changes no worktree, no local branch and nothing on GitHub. It reads GitHub with `gh` and
# fetches over HTTPS (no YubiKey): the base branches into refs/remotes/origin/<base>, and the
# merged PR heads into the object store only, so worktree-cleanup.sh can check them.
#
# Usage: worktree-sweep.sh <repo>
#
# Output: TSV on stdout, one row for each item, after a header row:
#   kind      branch | detached
#   target    the branch name, or the worktree path of a detached worktree
#   class     merged     a merged PR of the user (branch), or a base branch or a merged PR (detached
#                        HEAD) holds the tip. A base is the default branch or a protected branch. Pass `sha` to worktree-cleanup.sh as --merged-head
#             open-pr    an open PR uses the branch name, or holds the detached HEAD. It stays
#             closed-pr  only closed PRs with no merge. List it and ask
#             no-pr      no PR of the user's uses the branch, and no PR holds the detached HEAD.
#                        List it and ask
#   pr        the PR number, or -
#   sha       for merged: the --merged-head. For the others: the tip of origin/<base>, the
#             reference for the list of commits that only this item has
#   worktree  the worktree path, or -
#   note      a short fact for the list (the base that holds a detached HEAD, the PR state)
# The current branch of the main checkout and the base branches are not listed.
# Exit codes: 0 done; 1 usage or no gh login; 2 a fetch failed.
set -euo pipefail

die() { code="$1"; shift; echo "worktree-sweep: $*" >&2; exit "$code"; }

REPO="${1:-}"
[ -n "$REPO" ] || { sed -n '2,27p' "$0" >&2; exit 1; }
MAIN="$(git -C "$REPO" worktree list --porcelain | sed -n '1s/^worktree //p')" || die 1 "not a git repository: $REPO"
[ -n "$MAIN" ] || die 1 "not a git repository: $REPO"
gh auth status >/dev/null 2>&1 || die 1 "gh is not logged in"

URL="$(git -C "$MAIN" remote get-url origin)"
SLUG="$(printf '%s' "$URL" | sed -E 's#^(git@|ssh://git@|https://)github\.com[:/]##; s#\.git$##')"
CURRENT="$(git -C "$MAIN" symbolic-ref -q --short HEAD || true)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  git -C "$MAIN" -c credential.helper='!gh auth git-credential' fetch -q \
    "https://github.com/$SLUG.git" "$@" || die 2 "the fetch from github.com/$SLUG failed"
}

gh pr list -R "$SLUG" --author @me --state all --limit 2000 \
  --json number,headRefName,headRefOid,state,mergedAt,baseRefName > "$TMP/mine.json"
gh pr list -R "$SLUG" --state open --limit 2000 --json number,headRefName > "$TMP/open.json"
DEFAULT="$(gh repo view "$SLUG" --json defaultBranchRef --jq .defaultBranchRef.name)"

# The bases: the default branch and the protected branches. A stack base or a release branch that
# is not protected is feature work: a PR decides its state.
git -C "$MAIN" -c credential.helper='!gh auth git-credential' ls-remote --heads \
  "https://github.com/$SLUG.git" | sed 's#.*refs/heads/##' | sort > "$TMP/remote-heads.txt"
{ echo "$DEFAULT"; gh api "repos/$SLUG/branches?protected=true&per_page=100" --paginate --jq '.[].name'; } \
  | sort -u | comm -12 - "$TMP/remote-heads.txt" > "$TMP/bases.txt"
REFSPECS=""
while IFS= read -r b; do REFSPECS="$REFSPECS +refs/heads/$b:refs/remotes/origin/$b"; done < "$TMP/bases.txt"
# shellcheck disable=SC2086
fetch $REFSPECS
# The reference base for the list of local commits: the base the user's PRs use most.
MAIN_BASE="$(jq -r '[.[].baseRefName] | group_by(.) | max_by(length) | .[0] // empty' "$TMP/mine.json")"
{ [ -n "$MAIN_BASE" ] && grep -qx "$MAIN_BASE" "$TMP/bases.txt"; } || MAIN_BASE="$DEFAULT"
BASE_SHA="$(git -C "$MAIN" rev-parse "refs/remotes/origin/$MAIN_BASE")"

# head -> class, PR, sha for the user's PRs: merged (the last merge) before closed.
jq -r '
  group_by(.headRefName)[]
  | ([.[] | select(.state == "MERGED")] | sort_by(.mergedAt) | last) as $m
  | if $m then [$m.headRefName, "merged", ($m.number | tostring), $m.headRefOid]
    else ([.[] | select(.state == "CLOSED")] | last) as $c
      | if $c then [$c.headRefName, "closed-pr", ($c.number | tostring), ""] else empty end
    end
  | @tsv' "$TMP/mine.json" > "$TMP/mine.tsv"
jq -r '.[] | [.headRefName, (.number | tostring)] | @tsv' "$TMP/open.json" > "$TMP/open.tsv"

git -C "$MAIN" worktree list --porcelain | awk '
  /^worktree / { path = substr($0, 10); head = "" }
  /^HEAD / { head = substr($0, 6) }
  /^branch / { print "branch\t" substr($0, 19) "\t" path }
  $0 == "detached" { print "detached\t" head "\t" path }' > "$TMP/worktrees.tsv"

git -C "$MAIN" for-each-ref --format='%(refname:short)' refs/heads > "$TMP/branches.txt"

# Branch rows.
awk -F'\t' -v cur="$CURRENT" -v base_sha="$BASE_SHA" '
  FILENAME == ARGV[1] { skip[$1] = 1; next }
  FILENAME == ARGV[2] { open[$1] = $2; next }
  FILENAME == ARGV[3] { cls[$1] = $2; pr[$1] = $3; sha[$1] = $4; next }
  FILENAME == ARGV[4] { if ($1 == "branch") wt[$2] = $3; next }
  {
    b = $0
    if (b == cur || (b in skip)) next
    w = (b in wt) ? wt[b] : "-"
    if (b in open) { print "branch\t" b "\topen-pr\t" open[b] "\t" base_sha "\t" w "\topen PR #" open[b]; next }
    if (b in cls) {
      if (cls[b] == "merged") print "branch\t" b "\tmerged\t" pr[b] "\t" sha[b] "\t" w "\t-"
      else print "branch\t" b "\tclosed-pr\t" pr[b] "\t" base_sha "\t" w "\tPR #" pr[b] " closed with no merge"
      next
    }
    print "branch\t" b "\tno-pr\t-\t" base_sha "\t" w "\tno PR of yours"
  }' "$TMP/bases.txt" "$TMP/open.tsv" "$TMP/mine.tsv" "$TMP/worktrees.tsv" "$TMP/branches.txt" > "$TMP/rows.tsv"

# Detached rows: a base branch that holds the HEAD, else the PRs that GitHub links to the commit.
: > "$TMP/pull-heads.tsv"
while IFS=$'\t' read -r kind head path; do
  [ "$kind" = "detached" ] || continue
  [ "$path" != "$MAIN" ] || continue
  held=""
  while IFS= read -r b; do
    if git -C "$MAIN" merge-base --is-ancestor "$head" "refs/remotes/origin/$b" 2>/dev/null; then
      held="$b"; break
    fi
  done < "$TMP/bases.txt"
  if [ -n "$held" ]; then
    printf 'detached\t%s\tmerged\t-\t%s\t%s\tin origin/%s\n' "$path" \
      "$(git -C "$MAIN" rev-parse "refs/remotes/origin/$held")" "$path" "$held" >> "$TMP/rows.tsv"
    continue
  fi
  # 422 (the commit is not on GitHub) and an empty list both mean: no PR holds it.
  pulls="$(gh api "repos/$SLUG/commits/$head/pulls" \
    --jq '.[] | [(.number | tostring), .state, (.merged_at // ""), .head.sha] | @tsv' 2>/dev/null || true)"
  merged="$(printf '%s\n' "$pulls" | awk -F'\t' '!f && $3 != "" { print; f = 1 }')"
  open="$(printf '%s\n' "$pulls" | awk -F'\t' '!f && $2 == "open" { print; f = 1 }')"
  closed="$(printf '%s\n' "$pulls" | awk -F'\t' '!f && $2 == "closed" { print; f = 1 }')"
  if [ -n "$merged" ]; then
    n="$(printf '%s' "$merged" | cut -f1)"; s="$(printf '%s' "$merged" | cut -f4)"
    printf '%s\t%s\n' "$n" "$s" >> "$TMP/pull-heads.tsv"
    printf 'detached\t%s\tmerged\t%s\t%s\t%s\tin merged PR #%s\n' "$path" "$n" "$s" "$path" "$n" >> "$TMP/rows.tsv"
  elif [ -n "$open" ]; then
    n="$(printf '%s' "$open" | cut -f1)"
    printf 'detached\t%s\topen-pr\t%s\t%s\t%s\tin open PR #%s\n' "$path" "$n" "$BASE_SHA" "$path" "$n" >> "$TMP/rows.tsv"
  elif [ -n "$closed" ]; then
    n="$(printf '%s' "$closed" | cut -f1)"
    printf 'detached\t%s\tclosed-pr\t%s\t%s\t%s\tin PR #%s, closed with no merge\n' "$path" "$n" "$BASE_SHA" "$path" "$n" >> "$TMP/rows.tsv"
  else
    printf 'detached\t%s\tno-pr\t-\t%s\t%s\tno PR holds the HEAD\n' "$path" "$BASE_SHA" "$path" >> "$TMP/rows.tsv"
  fi
done < "$TMP/worktrees.tsv"

# Fetch the merged PR heads that the object store does not have yet, into no ref.
awk -F'\t' '$1 == "branch" && $3 == "merged" { print $4 "\t" $5 }' "$TMP/rows.tsv" >> "$TMP/pull-heads.tsv"
MISSING=""
while IFS=$'\t' read -r n s; do
  [ -n "$n" ] || continue
  git -C "$MAIN" cat-file -e "$s^{commit}" 2>/dev/null || MISSING="$MISSING refs/pull/$n/head"
done < <(sort -u "$TMP/pull-heads.tsv")
# shellcheck disable=SC2086
[ -z "$MISSING" ] || fetch $MISSING

printf 'kind\ttarget\tclass\tpr\tsha\tworktree\tnote\n'
cat "$TMP/rows.tsv"
