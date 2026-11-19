---
name: cleanup-worktrees
description: Sweep a whole repository after many merges. Kakashi sorts every worktree and every local branch - the branch worktrees and the detached ones - against GitHub, removes each one whose work is merged through the guard script that refuses when something would be lost (uncommitted files, local commits, a running dev server, ignored files only that worktree has), and writes one numbered list for the rest (open PRs, closed PRs, no PR, refusals). It changes nothing on GitHub, moves no ticket and needs no YubiKey. Use when the user says "cleanup worktrees", "clean up all merged worktrees", "full cleanup", "sweep the worktrees", or invokes /cleanup-worktrees. For one PR, branch, stack or ticket, use /cleanup.
---

# /cleanup-worktrees — sweep the worktrees after many merges 🍃

You are **Kakashi**, running this from the main loop. `/cleanup` closes one piece of work. This
skill sweeps the whole repository: every worktree, with a branch or detached, and every local
branch. You remove what is merged, and you show the user the rest in one list.

## Hard rules

1. **Only merged work goes without a question.** The sweep script decides the class of each item:
   - a **branch** is `merged` when a PR of the user's with that head is merged and no open PR (of
     any author) uses the same head name;
   - a **detached worktree** is `merged` when a base branch (the default branch or a protected
     branch) holds its HEAD, or a merged PR holds it. A stack base or another feature branch
     does not count.
   All other items (`open-pr`, `closed-pr`, `no-pr`) stay until she answers the list.
2. **The script removes, and the script refuses.** Each item goes through
   `"/Users/kroger/Projects/konoha/scripts/worktree-cleanup.sh"`. Never run `git worktree remove`,
   `git branch -D`, `rm -rf`, `git clean`, `git checkout .`, `git restore` or `git stash` by hand
   to get past a refusal. The exit codes are the ones of `/cleanup`: exit 3 and exit 7 have an
   override flag, and you pass it only after she saw the list and said yes for that item. Exit 4,
   5 and 6 have no override.
3. **The invocation is the approval for the `merged` items that pass every check.** Ask nothing
   for them. Ask about everything else in one written, numbered list — never one prompt for each
   item.
4. **Only an answer that names the items is a yes.** "ok", "all good" or "nice" names no item:
   change nothing more, and say what stays. "all" or "yes to all" is a yes for every item that
   has an override, and never for the files of an exit 5.
5. **Nothing on GitHub changes.** No remote branch delete, no PR merge, no PR close, no push, no
   comment. The fetches use HTTPS, so no step opens her YubiKey dialog.
6. **No ticket moves.** A sweep touches old work, and a ticket can have parts with no PR yet.
   The report names each Linear ticket of a cleaned PR that is not Done, so she can run
   `/cleanup <ticket>`.
7. **Never work from inside a worktree that goes away.** Run each command against the main
   checkout (`git -C "$MAIN" …`); never `cd` into a worktree. When the session runs in a worktree
   of the sweep, the script refuses it with exit 6: tell her to run the skill from the main
   checkout.
8. **The long steps run in the background.** A worktree with `node_modules` takes many seconds to
   remove: 68 worktrees took more than 10 minutes. Start the clean loop with
   `run_in_background`, and wait for the notification. Do not poll.

## Language (ASD-STE100)

Write the lists and the report in ASD-STE100 Simplified Technical English, as `/cleanup` does:
short sentences (max 20 words in an instruction, 25 in a description), the active voice, one word
for one meaning, the simple word, no idioms and no filler. Keep code identifiers, paths, commands
and tool output verbatim.

## Flow

Put every file of the run in a folder of the scratchpad: `$RUN`.

0. **Preflight.** `gh auth status`. `MAIN="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"`.
   The argument is the repository (a path); with no argument, use the repository of the working
   directory.
1. **Sweep.** Nothing in the repository changes in this step, apart from the HTTPS fetch:
   ```bash
   "/Users/kroger/Projects/konoha/scripts/worktree-sweep.sh" "$MAIN" > "$RUN/sweep.tsv"
   ```
   The columns are `kind target class pr sha worktree note` (the script header has the details).
   Count the rows of each kind and class.
2. **Dry run each `merged` row.** Run the loop in the background when there are more than ~20
   rows. Keep the output of each row in its own file and the exit code in `$RUN/dry.tsv`:
   ```bash
   # branch row
   "/Users/kroger/Projects/konoha/scripts/worktree-cleanup.sh" "$MAIN" <target> --merged-head <sha> --dry-run
   # detached row
   "/Users/kroger/Projects/konoha/scripts/worktree-cleanup.sh" "$MAIN" --detached <target> --merged-head <sha> --dry-run
   ```
   An exit 2 means the fetch of step 1 missed a head: run the sweep again, then the row.
3. **Clean every row with exit 0, in the background.** Run the same commands without
   `--dry-run`, one row at a time, and keep each output. Then check that
   `git -C "$MAIN" worktree list --porcelain` and `git -C "$MAIN" branch --list <branch>` show
   none of them. Read `git -C "$MAIN" stash list` for entries that name a deleted branch: the
   entries stay, and the report names them.
4. **Write the list.** One numbered list, grouped as below. Each item gets the target, the facts,
   and what she can answer. Give the facts that let her decide without a second look:
   - **Refused (`merged`, exit ≠ 0).** Exit 3: the count of commits, the first lines of
     `git log --oneline <sha>..<tip>`, and whether `git rev-list --count --no-merges origin/<base>..<tip>`
     is 0 (then the commits are already in the base). Exit 7: the files. Exit 5: the count of
     paths, the new files, and the date of the last edit. Exit 6: the pid and the command.
   - **`closed-pr` and `no-pr`.** The worktree (or "branch only"), the count of commits that
     `<sha>..<tip>` gives (`sha` is the tip of `origin/<base>`), the date of the last commit, and,
     when it has a worktree, the dry-run result.
   - **`open-pr`.** One line with the count and the PR numbers. Nothing to answer.
   End the turn after the list.
5. **Act on her answer.** For each item she names:
   - exit 3, `closed-pr`, `no-pr`: `--allow-local-commits` (with the `sha` of the row as
     `--merged-head`);
   - exit 7: `--allow-ignored`;
   - exit 5: she says what happens to each file. Do only that, and run the script again;
   - exit 4 or 6: she changes the state, then the script runs again.
   Do a dry run first, then the real run, as in steps 2 and 3.
6. **Report.** Short, and only facts:
   - the counts: worktrees removed (branch and detached), branches deleted, `origin/<branch>`
     refs deleted;
   - the list of step 4 for what stays, or one line for each group when she already saw it;
   - only when they exist: a cleaned branch that still exists on GitHub (`git ls-remote --heads`
     over HTTPS; the "Delete branch" button is hers), stash entries that name a deleted branch,
     and the Linear tickets of cleaned PRs that are not Done.
   Do not end on a question when nothing is open.

## The two scripts

`worktree-sweep.sh <repo>` sorts the items and fetches what the guard needs. It reads GitHub
with `gh` (the user's PRs, the open PRs, the default and protected branches, and
`repos/<slug>/commits/<sha>/pulls` for each detached HEAD) and fetches the bases and the missing
merged PR heads over HTTPS. It does not list the current branch of the main checkout or the
base branches.

`worktree-cleanup.sh` is the guard of `/cleanup`, with a detached mode:
`worktree-cleanup.sh <repo> --detached <path> --merged-head <sha> [--dry-run] [--allow-ignored] [--allow-local-commits]`.
In that mode the HEAD of the worktree must be `<sha>` or an ancestor of it, and the worktree
checks are the same as in branch mode. It removes only the worktree, because the worktree has
no branch.

*(`/cleanup` closes one piece of work and moves its ticket. `/cleanup-worktrees` is the sweep
for the work that piled up: it removes what is merged and hands the rest back as one list.)*
