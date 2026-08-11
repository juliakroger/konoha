# konoha — architecture

A Claude Code plugin: a **squad of Konoha ninja** (reusable subagents) that several dev-workflow skills
summon. Inspired by [`thk`](https://github.com/thiagokroger/thk) (The Hand of the King), but where thk
exposes **one** entrypoint, konoha shares **one cast** across **four** skills.

> You are the **Hokage** — you post the mission and have the final word. The squad does the work.

## The one idea: engine vs. skin

thk bakes its theme into its wiring (skills named `grand-maester`, etc.). konoha splits them:

- **Engine** — a fixed set of neutral **offices** (capture, scholar, enforcer, red-team, shipwright,
  counselor) + the flow.
- **Skin** — the Naruto cast is a naming layer on top. The theme could be reskinned without touching
  the flow.

## The cast

**Kakashi (Orchestrator)** is not a dispatched subagent — he is the **persona of the skills** that run
in the main loop (`/mission`, `/debrief`), exactly as thk's Hand is the `/thk` skill, not an
`agents/hand.md`. He routes, executes the plan himself, and synthesizes verdicts.

The six specialists are real subagents in `agents/*.md`, dispatched via the `Agent` tool
(`subagent_type: "konoha:<name>"`):

| Agent | Office | Model | Job |
|---|---|---|---|
| `itachi` | Capture | opus | Sharingan — reads issue + comments + linked PRs + code + backend repos |
| `shikamaru` | Scholar | opus | Root-cause, plan, correctness review, PR write-up, "convene?" verdict |
| `sakura` | Enforcer | opus | Verification gauntlet (`pnpm check` + tests) + convention rules |
| `anbu` | Red-team | opus | Adversarial security + edge-case review |
| `naruto` | Shipwright | sonnet | Commit, push, open PRs, post comments/replies |
| `gaara` | Counselor | **Codex CLI** | Outside read on a different model on purpose; the review closer — mandatory, never falls back to Claude |

*(Cut vs thk: no Budget / Master of Coin — Kakashi watches scope himself.)*

## Model & runner assignment

Like thk (which centralizes this in `config/profiles.json`), each office runs on a model matched to its
job — but v1 sets them directly in each agent's frontmatter instead of a profile file:

| Agent | Runner / model | Why |
|---|---|---|
| Kakashi (orchestrator) | your session model (main loop) | runs `/mission` etc. in the main loop — can't be swapped per-agent; set it with `/model` |
| Itachi | Claude Opus | the dossier seeds the whole mission — a misread ticket sends every downstream office the wrong way |
| Shikamaru | Claude Opus | planning + correctness want the strongest reasoning |
| Sakura | Claude Opus | it is a review lens, not just a command runner — `review-rules` was the council's weakest voice on Sonnet |
| ANBU | Claude Opus | adversarial security wants deep reasoning |
| Naruto | Claude Sonnet | git plumbing is destructive and the YubiKey push flow needs retry judgment — not pure mechanical fan-out |
| Gaara | **Codex CLI** — always the newest GPT (currently `gpt-5.6-sol`, `model_reasoning_effort=high`) | genuine cross-model diversity for the outside read |

Frontmatter uses the bare **aliases** (`opus`, `sonnet`, `haiku`, `fable`), never a pinned ID like
`claude-opus-5`. Aliases resolve to the newest model in their tier, so every office stays current
without an edit — the same reason `gaara-codex.sh` resolves its model instead of hard-coding one.
`fable` is available here too; it sits above Opus and is the one genuine step up, but it is priced
roughly double, and these offices run on every mission and every exam.

**Gaara on Codex.** `_council-review` runs `scripts/gaara-codex.sh` for the closer, which shells to
`codex exec --sandbox read-only` (mirrors thk's Counselor Altman, but read-only for review). Requires
the `codex` CLI on PATH.

The GPT read is the load-bearing part of the review — three Claude lenses grading a Claude change is
exactly the blind spot it exists to break — so it is **mandatory and never substituted**. If the
script fails for any reason (`CODEX_UNAVAILABLE` exit 3, `EMPTY_DIFF` exit 4, auth / network /
rate-limit / timeout, empty output), the module stops and asks the user to **retry or stop**. It must
never quietly dispatch the Claude `gaara` agent in its place: a same-family opinion filed under
Gaara's name reads as cross-model diversity while delivering none. The Claude `gaara` agent survives
only for an explicitly requested Claude-side second opinion.

**Gaara stays on the newest model.** The script does not hard-code a version — a pin rots silently,
which is how it kept running `gpt-5.5` long after the CLI default had moved on. It resolves the model
as `$GAARA_MODEL` → the `model` key in `~/.codex/config.toml` → a fallback pin, and echoes the
resolved model to stderr so a review always records which GPT closed it. Keeping `codex` current is
therefore all it takes to keep Gaara current.

Because a failed closer now halts the review, the script takes the local diff against `HEAD` and adds
untracked files — a plain `git diff` reported auto-staged edits and add-only changes as `EMPTY_DIFF`.
A full `profiles.json` (swap any office's model without editing files) is a later phase.

## The four skills

### `/scroll` — draft an issue from a description
`itachi` researches current behavior (code + backend repos) and `shikamaru` structures it; Kakashi
drafts a **lean** issue (Summary / Current / Desired only) and confirms at each gate. AI credit: n/a.

### `/mission <issue>` — take a GitHub issue to a Draft PR
`itachi` capture → gate (already-fixed / needs-info / go) → `shikamaru` plan → **Kakashi executes**
(single-agent, per `CLAUDE.md`) → `sakura` verify (fix-retry) → **`_council-review` (fix adapter)** →
`shikamaru` drafts the PR body (links the issue with `Closes #<n>`) → **one confirm** → `naruto` opens
the Draft PR (base `staging`). AI credit: **No** (your own PR).

### `/debrief <pr-url>` — resolve the reviews on your PR
Two inputs, in order: (1) the **PR URL** → pull comments via `gh` (the AI review bot first, then
teammates); (2) then the skill **asks** if there's a **Slack** review to paste (optional). `shikamaru`
maps the feedback to the task, Kakashi triages (accept / defer / decline) and fixes, `sakura` verifies,
`naruto` commits + posts per-thread replies. AI credit: **No** (your own PR).

### `/exam <pr-url>` — review a colleague's PR
Runs **`_council-review` (comment adapter)** on the PR, Kakashi consolidates the findings into **one**
comment, `naruto` posts it in your name with an attributed footer. Plain comment — not a formal
Approve / Request-changes. AI credit: **Yes** — `🍃 Review generated with Julia's Claude Code.`

## The shared module: `_council-review`

Both `/mission` and `/exam` run the same diff review — `anbu` ∥ `shikamaru` (`review-correctness`) ∥
`sakura` (`review-rules`) in parallel, then `gaara` closes — and return one consolidated, deduped list
of findings. The **caller** applies the output adapter:

| Caller | Target | Adapter | Result |
|---|---|---|---|
| `/mission` | your own diff (pre-PR) | **fix** | Kakashi fixes findings, re-verifies, then ships |
| `/exam` | a colleague's PR | **comment** | consolidate → one attributed comment |

## Attribution matrix (flips by ownership)

| Action | Whose work | AI credit? |
|---|---|---|
| `/scroll` issue | yours (internal) | — |
| `/mission` commits + PR | yours | **No** |
| `/debrief` fix commits + replies | yours | **No** |
| `/exam` review comment | colleague's PR | **Yes** — attributed footer |

## Folder layout

```
konoha/
├── .claude-plugin/{plugin.json, marketplace.json}
├── README.md
├── docs/ARCHITECTURE.md
├── agents/{itachi,shikamaru,sakura,anbu,naruto,gaara}.md
├── scripts/gaara-codex.sh   ← Codex adapter for the counselor
└── skills/
    ├── scroll/SKILL.md          ← create issue
    ├── mission/SKILL.md         ← ticket → Draft PR
    ├── debrief/SKILL.md         ← resolve reviews on your PR
    ├── exam/SKILL.md            ← review a colleague's PR
    └── _council-review/SKILL.md ← shared diff review (fan-out + close)
```

## Install (local marketplace)

```
/plugin marketplace add ~/Projects/konoha
/plugin install konoha@konoha
```

Skills are then invoked as `/konoha:scroll`, `/konoha:mission`, `/konoha:debrief`, `/konoha:exam`;
agents dispatch as `subagent_type: "konoha:itachi"` (etc.). Run `/reload-plugins` or restart the
session after changes.

## Reuse of existing skills

The themed skills evolve logic you already have; your current skills stay untouched:

| konoha skill | Built on your |
|---|---|
| `/scroll` | `create-issue` (+ itachi/shikamaru research) |
| `/mission` | `work-on` (+ `_council-review`) |
| `/debrief` | `resolve-comments` (+ Slack-text input) |
| `/exam` | — (new) |

## v1 scope (deferred from thk)

- **profiles.json** (per-office model routing) — v1 sets models directly in agent frontmatter (Itachi/Sakura
  Sonnet, Shikamaru/ANBU Opus, Naruto Haiku) and runs Gaara on the Codex CLI; a profile file comes later.
- **Cross-machine resume + context bundling into the issue** — skipped; optional local session notes only.
- **Plan-side council review** — v1 reviews the diff only (plan-side is a later phase).
- **Auto-revisit cron** — you trigger `/debrief` yourself.

## Phased build

- **Phase 0** — cast + `/mission` spine (no council).
- **Phase 1** — `_council-review` wired into `/mission` (fix) and `/exam` (comment). ← the payoff.
- **Phase 2** — `/scroll` + `/debrief`, and Shikamaru's `assess` gate.
- **Phase 3 (optional)** — profiles, plan-side review, local resume.
