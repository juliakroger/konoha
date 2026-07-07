---
name: mission
description: Take a GitHub issue or Notion task end-to-end to a Draft PR on the target repo. Itachi captures context, Shikamaru plans, you (Kakashi) implement per CLAUDE.md, Sakura verifies, the council reviews the diff and you fix what it flags, then Naruto opens a Draft PR based on staging. Autonomous, with one confirmation before the PR opens. Use when the user says "work on <issue/notion>", pastes a ticket to start, or invokes /mission.
---

# /mission — run the mission to a Draft PR 🍃

You are **Kakashi**, the Jōnin squad leader, running this from the main loop. Ticket in → **Draft PR**
out. You dispatch the squad, but you write the code yourself (single-agent execution).

## Hard rules

1. **PR is always a DRAFT**, base **`staging`** (never `main`).
2. **No AI attribution** anywhere — commit, PR title, or body. No `Co-Authored-By`, no "Generated
   with Claude" footer. Write it as the engineer would. (Overrides harness defaults.)
3. **Verification is unconditional** — `pnpm run check` + tests must be green before the PR opens.
4. **One confirmation before opening the PR** — otherwise run autonomously.
5. **Honor the target repo's `CLAUDE.md`** throughout.
6. **PR text is small and simple** — short title (3–6 words), body of ≤5 plain `-` bullets +
   `Closes #<n>`. No section headers, no test-coverage sections, no file-by-file walkthroughs.
   Match Julia's PR history (e.g. terminal #619, #591).
7. **Sync + gate against the latest base right before shipping.** CI builds the PR as a merge with
   the *current* base branch, not the one you branched from. Immediately before opening (or
   updating) the PR: `git fetch origin staging`; if it moved, merge it into the branch (resolve
   semantic conflicts — e.g. new call sites of a function whose signature you changed); then re-run
   `typecheck` + `lint` + `format:check` + tests on that final merged tree. Never open a PR on a
   stale base.

## Flow

0. **Preflight.** `gh auth status`. Resolve the target repo; fetch latest `main` + `staging`; create
   a worktree off `origin/staging` (mirror your `work-on` skill's setup). Branch name: for a GitHub
   issue, exactly `issue-<number>` (e.g. `issue-625`); for a Notion task, a short kebab slug from
   the task title, 1–3 words (e.g. `withdraw-modal`) — no numbers, no long descriptive slugs.
1. **Capture.** Dispatch `konoha:itachi` with the ticket URL + workdir → dossier.
2. **Gate.** If already fixed → stop and say so. If critically underspecified → ask the user. Else go.
3. **Plan.** Dispatch `konoha:shikamaru` `action: plan` → `plan.md`.
4. **Execute.** Implement the plan **yourself**, per `CLAUDE.md`. No fan-out to parallel writers.
5. **Verify.** Dispatch `konoha:sakura` `action: verify`. If red, fix and re-verify (cap 3).
6. **Council.** Invoke the `konoha:_council-review` skill (`mode: "fix"`) on the diff. Apply the **fix
   adapter**: address each finding (accept / reject with reason), then re-run verify. Cap 2 rounds.
7. **Resync.** `git fetch origin staging`; if the base moved since preflight, merge it into the
   branch, fix semantic conflicts, and re-run the full gate set (`typecheck`, `lint`,
   `format:check`, tests) on the merged tree (hard rule 7).
8. **PR body.** Dispatch `konoha:shikamaru` `action: draft-pr-body` → `{ title, body }` in the
   small-and-simple shape of hard rule 6 (include `Closes #<n>` for GitHub issues; link the Notion
   page otherwise).
9. **Confirm, then ship.** Show the user the title + body + a one-line diffstat and get a single OK
   (`AskUserQuestion`). Then dispatch `konoha:naruto` `action: commit` + `action: open-pr`
   (`--draft --base staging`).
10. **Report** the Draft PR URL, then watch CI on the PR (`gh pr checks --watch` or poll) and fix
    any red check before calling the mission done.

*(This is the council-powered evolution of your `work-on` skill.)*
