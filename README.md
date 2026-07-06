# konoha 🍃

A Claude Code plugin: a **squad of Konoha ninja** — reusable subagents — that several dev-workflow
skills summon. Inspired by [`thk`](https://github.com/thiagokroger/thk) (The Hand of the King), but
where thk exposes one entrypoint, konoha shares **one cast** across **four skills**.

> You are the **Hokage**: you post the mission, you have the final word. The squad does the work.

## The four skills

| Command | Does | Reviews with you? |
|---|---|---|
| **`/scroll`** | Draft a lean GitHub issue from a description you give (research-backed, confirm each step) | — |
| **`/mission <issue\|notion>`** | Take a ticket end-to-end to a **Draft PR** | yes — council reviews the diff and fixes before shipping |
| **`/debrief <pr-url>`** | Resolve the reviews on **your** PR — the AI review bot + teammates + (optionally) a pasted Slack review | — |
| **`/exam <pr-url>`** | Review a **colleague's** PR and post **one** comment in your name | yes — council inspects, you post the summary |

## The cast (subagents)

| Ninja | Role | Job |
|---|---|---|
| **Kakashi** | Orchestrator | Runs each mission from the main loop; routes, executes, decides *(a persona in the skills, not a dispatched agent — like thk's Hand)* |
| **Itachi** | Capture | Sharingan — reads & remembers everything: issue/Notion + comments + linked PRs + code + backend repos |
| **Shikamaru** | Scholar | Root-cause, git history, drafts the plan + PR write-up, correctness review |
| **Sakura** | Enforcer | Verification gauntlet (`pnpm check` + tests = "vitals green") + convention rules |
| **ANBU** | Red-team | Covert adversarial review — security + edge cases |
| **Naruto** | Shipwright | Kage Bunshin + toad summons — commit, push, open PRs, post comments/replies |
| **Gaara** | Counselor | Kazekage of Suna — the outside read (a different village = a different model) |

See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) for the full design.

## Two rules baked in

1. **The council-review module is shared** between `/mission` (fixes findings before shipping) and
   `/exam` (consolidates findings into one comment). Built once, two output adapters.
2. **AI attribution flips by ownership.** Your own commits/PRs (`/mission`, `/debrief`) carry **no** AI
   attribution. A review comment on a **colleague's** PR (`/exam`) **does** — an explicit footer —
   because there, transparency is the courteous thing.

## Install (local)

```
/plugin marketplace add ~/Projects/konoha
/plugin install konoha@konoha
```

Then restart the Claude Code session so the new skills + agents are discovered.

## Status

v1 scope: single model (except **Gaara** on a different one), diff-side review only, local session
state. Deferred from thk: per-role model profiles, cross-machine resume, context bundling into the
issue, auto-revisit cron.
