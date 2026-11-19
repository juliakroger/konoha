# konoha 🍃

A Claude Code plugin: a **squad of Konoha ninja** — reusable subagents — that several dev-workflow
skills summon.

> You are the **Hokage**: you post the mission, you have the final word. The squad does the work.

## The eight skills

| Command | Does | Reviews with you? |
|---|---|---|
| **`/scroll`** | Draft a **Linear** issue in team FE from a description you give — the org's issue-creation workflow: interview (≥5 rounds), background research, Summary / Context / Scope / Verification, a fresh-context review, one approval | — |
| **`/mission <issue>`** | Take a GitHub or Linear issue end-to-end to a **Draft PR** (links it with `Closes <owner>/<repo>#<n>` / `Closes <KEY>-<n>`); ends with the **PR creation workflow** — Kakashi adapts the description from what exists (your words verbatim, no interview) and seals it with the fingerprint | yes — council reviews the diff and fixes before shipping |
| **`/debrief <pr-url>`** | Resolve the reviews on **your** PR — the AI review bot + teammates + (optionally) a pasted Slack review, which goes on the PR verbatim. Conflicts and repeats across reviewers and rounds are explained before anything is fixed; a round has a cap and a stop rule; fixes delete first and are reviewed (Gaara + the Codex naming pass) before they ship. Each fixed thread gets `Fixed in <sha>`; an item you decide not to do gets a short comment with the reason, and a Linear ticket when it moves to another task | yes — the fixes get Gaara + naming before the push |
| **`/exam <pr-url or stack-url>`** | Review a **colleague's** PR and post **one** comment in your name. A **stack** URL reviews each PR plus the whole stack and posts one review per open PR, with no footer | yes — council inspects, you approve what gets posted |
| **`/seal <pr-url>`** | Run the PR creation workflow on an existing PR of **yours** — the live body is your text; adapt (no interview), re-section, fingerprint, edit through the image guard, re-run the check | — |
| **`/merge <pr-url, branch or stack-url>`** | Bring the base (`development`, or the branch below in a stack) into **your** branch as a merge commit and fix the conflicts, so the PR merges clean again. Never merges the PR, never pushes to the base | — |
| **`/cleanup [pr-url, branch, stack-url or ticket]`** | Close the work after **your** PR is merged: remove the worktree and the local branch of each merged PR through a guard script, and move the Linear ticket to Done when all of its PRs are merged. Changes nothing on GitHub, needs no YubiKey | — |
| **`/cleanup-worktrees [repo]`** | Sweep the whole repository: sort every worktree (with a branch or detached) and every local branch against GitHub, remove each one whose work is merged through the same guard script, and hand the rest back as one numbered list. Moves no ticket, changes nothing on GitHub | — |

## The cast (subagents)

Each office runs on a configured AI. In **0.2** Claude decided and GPT only closed the review;
in **0.3** the roles inverted — **Codex decides, Claude executes**. **0.11** gives the plan back
to Claude — **Claude plans and executes**; Codex closes the review and rules on declined findings.

| Ninja | Role | Job | AI in 0.2 | AI in 0.3–0.10 | AI in 0.11+ |
|---|---|---|---|---|---|
| **Kakashi** | Orchestrator | Runs each mission from the main loop; routes and executes *(a persona in the skills, not a dispatched agent — like thk's Hand)* | your session model (Claude) — decided AND executed | your session model (Claude) — executed the architect's plan; contested calls went to Codex | your session model (Claude) — executes Shikamaru's plan; a design change goes back to Shikamaru, a decline to Codex |
| **Itachi** | Capture | Sharingan — reads & remembers everything: issue + comments (GitHub via `gh`; a Linear ticket arrives as the file Kakashi captured over the MCP) + linked PRs + code + backend repos | Claude Opus | Claude Opus *(unchanged)* | Claude Opus *(unchanged)* |
| **Shikamaru** | Scholar | Root-cause, git history, plan, issue-draft review, correctness review | Claude Opus — **authored** the plan | Claude Opus — **reviewed** the architect's plan against the codebase | Claude Opus — **authors** the plan again, and revises it on a design deviation |
| **Sakura** | Enforcer | Verification gauntlet (`bun run check` + tests = "vitals green") + convention rules | Claude Opus | Claude Opus *(unchanged)* | Claude Opus *(unchanged)* |
| **ANBU** | Red-team | Covert adversarial review — security + edge cases + failure paths (timeouts, retries, rollback, data loss) | Claude Opus | Claude Opus *(unchanged)* | Claude Opus *(unchanged)* |
| **Kurenai** | Illusion-dispel | Genjutsu release (*Kai*) — AI-output review: hallucinated APIs, invented compatibility, prompt leakage, narration, fabricated tests | — | Claude Opus *(joined in 0.4)* | Claude Opus *(unchanged)* |
| **Naruto** | Shipwright | Kage Bunshin + toad summons — commit, conclude merge commits, push, open PRs, edit PR bodies (image guard), post comments/replies | Claude Sonnet | Claude Sonnet *(unchanged)* | Claude Sonnet *(unchanged)* |
| **Gaara** | Arbiter & Counselor | Kazekage of Suna — a different village = a different model | Codex CLI (newest GPT) — review closer only | Codex CLI (newest `gpt-*-sol`, your config's reasoning effort, every run logged) — **the decision maker**: authored `plan.md`, ruled on contested findings, closed reviews | Codex CLI (same model and effort, every run logged) — closes reviews and **rules on declined findings**; no longer plans |

See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) for the full design.

## Fifteen rules baked in

1. **The council-review module is shared** between `/mission` (fixes findings before shipping) and
   `/exam` (consolidates findings into one comment). Built once, two output adapters.
2. **AI attribution flips by ownership.** Your own commits/PRs (`/mission`, `/debrief`) carry **no** AI
   attribution. A review comment on a **colleague's** PR (`/exam`) **does** — an explicit footer —
   because there, transparency is the courteous thing. Stack reviews have none: you chose that.
3. **Claude NEVER merges a PR.** Across every skill and agent: no `gh pr merge`, under any phrasing —
   "push it" means `git push` only. The Hokage always merges manually, herself.
4. **The squad talks ASD-STE100.** Every dossier, plan, finding, PR body, review, and issue is
   Simplified Technical English — short sentences, active voice, one word per meaning, no idioms.
   Code identifiers stay verbatim; a required output shape wins over STE.
5. **Claude plans and executes; Codex rules on declines.** Shikamaru (Claude Opus) authors the
   mission plan, as in 0.2 — from 0.3 to 0.10 the Codex architect did. Kakashi implements it, and
   a design change goes back to Shikamaru. Claude may not decline a review finding on its own — a
   decline needs a `GRANTED` ruling from the Kazekage (newest GPT, via the Codex CLI). If Codex is
   down, konoha stops and asks — it never quietly substitutes a Claude opinion under Gaara's name.
6. **Ceremony scales; invariants don't.** Two dials size each mission — difficulty (Shikamaru
   `assess`) scales the planning ceremony, risk (computed from the diff against the repo's
   `.konoha/critical-paths`, never judged) scales the council. Verify, Kurenai, the Gaara closer,
   the delta close, the single ship confirm, and decline-needs-GRANTED never scale down.
7. **PR images belong to you.** You drag screenshots into a PR body in the browser; `gh` cannot
   upload one. Every AI edit of a PR body (`/mission` re-gate, `/debrief`) runs through
   `scripts/pr-body.sh`, which keeps every image reference the live body has — verbatim, in its
   slot — never adds one, and never restores one you removed or undoes one you changed.
8. **A Linear ticket is read over the MCP, in the main loop.** `/mission` takes a GitHub issue or
   a Linear issue. Kakashi fetches a Linear ticket (description, comments, relations, images)
   through the `linear-server` MCP and hands Itachi a ticket file; when the MCP is down, konoha
   stops and asks. The branch is the lowercased identifier (`fe-148`) and the PR body ends with
   `Closes <KEY>-<n> — <url>`, the line Linear's GitHub integration links.
9. **The PR description is yours, sealed by the workflow.** `/mission` and `/seal` run the
   tplus-services PR creation workflow (`docs/process/pr-creation.md`) as the shared
   `_pr-creation` module: Kakashi adapts the description from what exists — no draft request, no
   interview (0.18.0). He checks what your words leave out himself (scope drift, new tests,
   excessive comments, unexplained pieces), proposes the cuts at the one gate, keeps every word you
   wrote verbatim, adds notes and the testing facts, and ends the body with the fingerprint the
   auditor's test-requirements check reads. Without it the check requests changes the moment a
   PR is marked ready.
10. **Issues live in Linear.** `/scroll` follows the org's issue-creation workflow — at least five
    interview rounds, one background research pass, Summary / Context and evidence / Scope /
    Verification, a fresh-context review, one approval — and creates the issue in team FE over the
    `linear-server` MCP. Its `## Scope` and `## Verification` are what the PR workflow later checks
    a PR against.
11. **Codex runs at full strength, and every run is on the record.** Gaara's closer and the
    arbiter run the newest `gpt-*-sol` the Codex CLI lists (not a pin, not the config's older
    model) at the reasoning effort of your codex config (`max`); `GAARA_REASONING` /
    `ARBITER_REASONING` override it. Every call appends a line to `~/.konoha/codex-runs.jsonl` with model, effort,
    exit, duration and token usage, and a run that returns nothing exits 5 instead of passing.
12. **A commit message names the change, never the review.** `Fix review`, `Fix reviews` and
    `Fix <Name> review` say nothing in the commit tree, so no skill writes them. The subject says
    what was wrong or what changed (`Fix EVM providers not being called properly`). A commit with
    several fixes has a subject that sums them up and a body with one line for each fix. Naruto
    refuses a message that names only the review.
13. **A decision not to do a review item is written on the PR.** `/debrief` resolves the threads it
    fixed, with no reply. For each item you and Kakashi decide not to do, it posts one short
    comment with the reason in simple words, after you approve the text. When the item moves to
    another task, it creates the Linear ticket first and the comment carries the link.
14. **`/merge` brings the base into your branch, and nothing the other way.** One merge commit,
    from `origin/<base>`, with each manual resolution named in the commit body; conflicts are
    resolved from both sides of the history, and the merged tree passes the full gates before
    the push. It never merges the PR, never pushes to `development`, never rebases, never
    force-pushes. A stack URL cascades from the bottom up.
15. **`/cleanup` removes only what is merged, and only when nothing is lost.** After you merge a
    PR, it removes the worktree and the local branch through `scripts/worktree-cleanup.sh`. The
    script refuses a worktree with uncommitted or untracked files, a branch with commits that the
    merged PR does not have, a worktree that a process runs from, and ignored files that exist
    only there. The invocation is the approval, so a clean target gets no extra prompt. The
    Linear ticket moves to Done only when all of its PRs are merged. Nothing on GitHub changes:
    no remote branch delete, no push, no comment.
16. **`/cleanup-worktrees` sweeps, and asks only once.** `scripts/worktree-sweep.sh` sorts each
    item: a branch is merged when a PR of yours with that head is merged and no open PR uses the
    name; a detached worktree is merged when the default branch, a protected branch or a merged
    PR holds its HEAD. The merged items that pass the guard go with no prompt. Everything else is
    one numbered list, and only an answer that names the items is a yes. No ticket moves.
17. **`/debrief` explains conflicts before it fixes, and reviews its fixes (0.17.0).** A pasted
    Slack review goes on the PR verbatim. Items that conflict (reviewers, or a reviewer and you)
    or repeat an earlier round are written up as an explanation with both quotes and a
    recommendation, and wait for your ruling. A round fixes every must-fix and at most 8 others;
    when more than a third of the new findings sit on lines the last round wrote, it stops and
    asks to re-plan. A fix deletes first; one that adds a file, type, enum, guard, state or layer
    needs your yes, and a proposed mechanism waits until the review closes. Gaara, the move check
    and the Codex naming pass review the fixes before the push. Each fixed thread gets
    `Fixed in <sha>: <what>`, then it is resolved.
18. **One list of ruled-out patterns (0.17.0).** `docs/ruled-out.md` (from Carlos's tplus harness)
    is read before code is written and by every reviewer: delete first, no layer that holds state
    its source already has, a new concept earns its place, a move changes nothing, one name per
    concept, state the problem not a mechanism. `scripts/move-check.sh` and
    `scripts/naming-codex.sh` (Codex checks the new names against the base) make two of them
    mechanical.
19. **The PR description is adapted, not interviewed (0.18.0).** `_pr-creation` never asks you to
    draft and runs no interview rounds. Kakashi builds the body from your words and what exists,
    and shows it once at the ship gate with the cuts he proposes (tests, comments, unexplained
    scope drift). Sakura's verify runs `format:check` too, like CI.

## Install (local)

```
/plugin marketplace add ~/Projects/konoha
/plugin install konoha@konoha
```

Then restart the Claude Code session so the new skills + agents are discovered.
