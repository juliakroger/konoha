# konoha 🍃

A Claude Code plugin: a **squad of Konoha ninja** — reusable subagents — that several dev-workflow
skills summon.

> You are the **Hokage**: you post the mission, you have the final word. The squad does the work.

## The four skills

| Command | Does | Reviews with you? |
|---|---|---|
| **`/scroll`** | Draft a lean GitHub issue from a description you give (research-backed, confirm each step) | — |
| **`/mission <issue>`** | Take a GitHub issue end-to-end to a **Draft PR** (links it with `Closes #<n>`) | yes — council reviews the diff and fixes before shipping |
| **`/debrief <pr-url>`** | Resolve the reviews on **your** PR — the AI review bot + teammates + (optionally) a pasted Slack review | — |
| **`/exam <pr-url>`** | Review a **colleague's** PR and post **one** comment in your name | yes — council inspects, you post the summary |

## The cast (subagents)

Each office runs on a configured AI. In **0.2** Claude decided and GPT only closed the review;
in **0.3** the roles inverted — **Codex decides, Claude executes**.

| Ninja | Role | Job | AI in 0.2 | AI in 0.3 |
|---|---|---|---|---|
| **Kakashi** | Orchestrator | Runs each mission from the main loop; routes and executes *(a persona in the skills, not a dispatched agent — like thk's Hand)* | your session model (Claude) — decided AND executed | your session model (Claude) — executes the architect's plan; contested calls go to Codex |
| **Itachi** | Capture | Sharingan — reads & remembers everything: issue + comments + linked PRs + code + backend repos | Claude Opus | Claude Opus *(unchanged)* |
| **Shikamaru** | Scholar | Root-cause, git history, plan work, PR write-up, correctness review | Claude Opus — **authored** the plan | Claude Opus — **reviews** the architect's plan against the codebase; no longer authors it |
| **Sakura** | Enforcer | Verification gauntlet (`pnpm check` + tests = "vitals green") + convention rules | Claude Opus | Claude Opus *(unchanged)* |
| **ANBU** | Red-team | Covert adversarial review — security + edge cases | Claude Opus | Claude Opus *(unchanged)* |
| **Naruto** | Shipwright | Kage Bunshin + toad summons — commit, push, open PRs, post comments/replies | Claude Sonnet | Claude Sonnet *(unchanged)* |
| **Gaara** | Architect & Counselor | Kazekage of Suna — a different village = a different model | Codex CLI (newest GPT) — review closer only | Codex CLI (newest GPT) — **the decision maker**: authors `plan.md`, rules on contested findings, closes reviews |

See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) for the full design.

## Five rules baked in

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
5. **Codex decides, Claude executes.** The Kazekage (newest GPT, via the Codex CLI) authors the
   mission plan and rules on every contested item; Claude implements the plan and may not decline
   a review finding on its own — a decline needs a `GRANTED` ruling. If Codex is down, konoha
   stops and asks — it never quietly substitutes a Claude opinion under Gaara's name.

## Install (local)

```
/plugin marketplace add ~/Projects/konoha
/plugin install konoha@konoha
```

Then restart the Claude Code session so the new skills + agents are discovered.
