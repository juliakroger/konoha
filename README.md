# konoha 🍃

A Claude Code plugin: a **squad of Konoha ninja** — reusable subagents — that several dev-workflow
skills summon.

> You are the **Hokage**: you post the mission, you have the final word. The squad does the work.

## The five skills

| Command | Does | Reviews with you? |
|---|---|---|
| **`/scroll`** | Draft a **Linear** issue in team FE from a description you give — the org's issue-creation workflow: interview (≥5 rounds), background research, Summary / Context / Scope / Verification, a fresh-context review, one approval | — |
| **`/mission <issue>`** | Take a GitHub or Linear issue end-to-end to a **Draft PR** (links it with `Closes <owner>/<repo>#<n>` / `Closes <KEY>-<n>`); ends with the **PR creation workflow** — you write the description, Kakashi interviews you and seals it with the fingerprint | yes — council reviews the diff and fixes before shipping |
| **`/debrief <pr-url>`** | Resolve the reviews on **your** PR — the AI review bot + teammates + (optionally) a pasted Slack review | — |
| **`/exam <pr-url>`** | Review a **colleague's** PR and post **one** comment in your name | yes — council inspects, you post the summary |
| **`/seal <pr-url>`** | Run the PR creation workflow on an existing PR of **yours** — the live body is your draft; interview, re-section, fingerprint, edit through the image guard, re-run the check | — |

## The cast (subagents)

Each office runs on a configured AI. In **0.2** Claude decided and GPT only closed the review;
in **0.3** the roles inverted — **Codex decides, Claude executes**. **0.11** gives the plan back
to Claude — **Claude plans and executes**; Codex closes the review and rules on declined findings.

| Ninja | Role | Job | AI in 0.2 | AI in 0.3–0.10 | AI in 0.11+ |
|---|---|---|---|---|---|
| **Kakashi** | Orchestrator | Runs each mission from the main loop; routes and executes *(a persona in the skills, not a dispatched agent — like thk's Hand)* | your session model (Claude) — decided AND executed | your session model (Claude) — executed the architect's plan; contested calls went to Codex | your session model (Claude) — executes Shikamaru's plan; a design change goes back to Shikamaru, a decline to Codex |
| **Itachi** | Capture | Sharingan — reads & remembers everything: issue + comments (GitHub via `gh`; a Linear ticket arrives as the file Kakashi captured over the MCP) + linked PRs + code + backend repos | Claude Opus | Claude Opus *(unchanged)* | Claude Opus *(unchanged)* |
| **Shikamaru** | Scholar | Root-cause, git history, plan, issue-draft review, correctness review | Claude Opus — **authored** the plan | Claude Opus — **reviewed** the architect's plan against the codebase | Claude Opus — **authors** the plan again, and revises it on a design deviation |
| **Sakura** | Enforcer | Verification gauntlet (`pnpm check` + tests = "vitals green") + convention rules | Claude Opus | Claude Opus *(unchanged)* | Claude Opus *(unchanged)* |
| **ANBU** | Red-team | Covert adversarial review — security + edge cases + failure paths (timeouts, retries, rollback, data loss) | Claude Opus | Claude Opus *(unchanged)* | Claude Opus *(unchanged)* |
| **Kurenai** | Illusion-dispel | Genjutsu release (*Kai*) — AI-output review: hallucinated APIs, invented compatibility, prompt leakage, narration, fabricated tests | — | Claude Opus *(joined in 0.4)* | Claude Opus *(unchanged)* |
| **Naruto** | Shipwright | Kage Bunshin + toad summons — commit, push, open PRs, edit PR bodies (image guard), post comments/replies | Claude Sonnet | Claude Sonnet *(unchanged)* | Claude Sonnet *(unchanged)* |
| **Gaara** | Arbiter & Counselor | Kazekage of Suna — a different village = a different model | Codex CLI (newest GPT) — review closer only | Codex CLI (newest `gpt-*-sol`, your config's reasoning effort, every run logged) — **the decision maker**: authored `plan.md`, ruled on contested findings, closed reviews | Codex CLI (same model and effort, every run logged) — closes reviews and **rules on declined findings**; no longer plans |

See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) for the full design.

## Eleven rules baked in

1. **The council-review module is shared** between `/mission` (fixes findings before shipping) and
   `/exam` (consolidates findings into one comment). Built once, two output adapters.
2. **AI attribution flips by ownership.** Your own commits/PRs (`/mission`, `/debrief`) carry **no** AI
   attribution. A review comment on a **colleague's** PR (`/exam`) **does** — an explicit footer —
   because there, transparency is the courteous thing.
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
   `_pr-creation` module: you write the description, Kakashi interviews you about what it leaves
   out (scope drift, new tests, excessive comments, unexplained pieces), keeps every word you
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

## Install (local)

```
/plugin marketplace add ~/Projects/konoha
/plugin install konoha@konoha
```

Then restart the Claude Code session so the new skills + agents are discovered.
