# konoha — architecture

A Claude Code plugin: a **squad of Konoha ninja** (reusable subagents) that several dev-workflow skills
summon. Inspired by [`thk`](https://github.com/thiagokroger/thk) (The Hand of the King), but where thk
exposes **one** entrypoint, konoha shares **one cast** across **four** skills.

> You are the **Hokage** — you post the mission and have the final word. The squad does the work.

## The one idea: engine vs. skin

thk bakes its theme into its wiring (skills named `grand-maester`, etc.). konoha splits them:

- **Engine** — a fixed set of neutral **offices** (capture, architect, scholar, enforcer, red-team,
  illusion-dispel, shipwright, counselor) + the flow.
- **Skin** — the Naruto cast is a naming layer on top. The theme could be reskinned without touching
  the flow.

## The second idea (0.3.0): Codex decides, Claude executes

Since 0.3.0 decision authority lives on the other model family. The design is symmetric — each
family authors one layer and audits the other:

- **GPT authors the plan; Claude reviews it.** The architect (Gaara on Codex,
  `scripts/architect-codex.sh plan`, reasoning `high`) writes `plan.md` as a decision record:
  chosen approach, rejected alternatives, files, forbidden anti-patterns, tests. Shikamaru
  (Claude) then runs `review-plan` against the real codebase; blocking findings trigger one
  architect revision round.
- **Claude writes the code; GPT closes the review.** Kakashi executes the plan mechanically and
  logs deviations; the council reviews the diff and the Gaara closer also checks it against
  `plan.md`.
- **Declining is not the executor's call.** Accepting a finding needs no permission. Declining a
  council or review finding — or deviating from the plan on a design level — needs a `GRANTED`
  ruling from `architect-codex.sh arbitrate` (contested items batched, one call per round).
  `/debrief` follows the same rule for review feedback, which matters doubly because the
  frontend-review CI bot runs on Codex: Claude no longer gets to dismiss GPT findings on its own.
- **Fail closed at both Codex points.** A failed plan or arbitration halts the flow: retry or
  stop, never a silent Claude substitute — same policy the Gaara closer always had. Provenance
  stays honest; authority, not identity, settles disputes (the old "present GPT output as if
  Claude wrote it" workaround is retired).
- **Instrumented.** Every mission appends one JSON line to `~/.konoha/metrics.jsonl` (level dials,
  findings per lens, arbitrations, deviations, verify rounds). The outcome metric for the
  architect-vs-baseline A/B is how much the Codex frontend-review bot complains about the shipped
  PR — since 0.5.0 also sliced by level, to verify empirically that lite missions do not regress.

## The third idea (0.5.0): two dials — difficulty × risk

Mission size is not one scalar. Two independent dials size the ceremony, with different judges
because they are knowable at different times:

- **Difficulty** — how hard is the task? Judged up front from the dossier by Shikamaru `assess`
  (never by Kakashi, who must not grade the scrutiny of his own work). `trivial` skips only the
  architect plan + plan review; a design fork discovered mid-execution upgrades the mission back
  to `standard`.
- **Risk** — what does the diff touch? Not judged at all: `_council-review` computes it from the
  final diff against the target repo's `.konoha/critical-paths` (one glob per line; missing file
  = everything critical, fail strict). Any match → `full` council; no match → `lite`, which drops
  ANBU only. No model call may lower the tier, and it can only upgrade mid-flight.

The invariants never scale down: Sakura verify, Kurenai, the Gaara closer, the delta close
(round 2 = Gaara alone on the fix diff via `--base`, so round-1 fixes never ship unreviewed),
the single ship confirmation, and decline-needs-GRANTED run at every level. A copy fix in the
withdraw modal is trivial-difficulty but full-risk; a big refactor of an uncritical view is the
reverse — the dials move independently by design.

## The cast

**Kakashi (Orchestrator)** is not a dispatched subagent — he is the **persona of the skills** that run
in the main loop (`/mission`, `/debrief`), exactly as thk's Hand is the `/thk` skill, not an
`agents/hand.md`. He routes, executes the plan himself, and synthesizes verdicts.

The seven specialists are real subagents in `agents/*.md`, dispatched via the `Agent` tool
(`subagent_type: "konoha:<name>"`):

| Agent | Office | Model | Job |
|---|---|---|---|
| `itachi` | Capture | opus | Sharingan — reads issue + comments (GitHub via `gh`; Linear via the ticket file Kakashi captured over the MCP) + linked PRs + code + backend repos |
| `shikamaru` | Scholar | opus | Plan review (architect's plan vs the real codebase), root-cause, correctness review, PR write-up, difficulty verdict (`assess`) |
| `sakura` | Enforcer | opus | Verification gauntlet (`pnpm check` + tests) + convention rules |
| `anbu` | Red-team | opus | Adversarial security + edge-case + failure-path review (full-tier council only) |
| `kurenai` | Illusion-dispel | opus | Genjutsu release (Kai) — AI-output review: hallucinated symbols, invented compatibility, prompt leakage, narration, fabricated tests; every finding carries its dispel proof |
| `naruto` | Shipwright | sonnet | Commit, push, open PRs, edit PR bodies through the image guard, post comments/replies |
| `gaara` | Architect & Counselor | **Codex CLI** | The decision maker (0.3.0): authors `plan.md`, rules on contested findings (`architect-codex.sh`), and closes reviews (`gaara-codex.sh`) — mandatory, never falls back to Claude |

*(Cut vs thk: no Budget / Master of Coin — Kakashi watches scope himself.)*

## Model & runner assignment

Like thk (which centralizes this in `config/profiles.json`), each office runs on a model matched to its
job — but v1 sets them directly in each agent's frontmatter instead of a profile file:

| Agent | Runner / model | Why |
|---|---|---|
| Kakashi (orchestrator) | your session model (main loop) | runs `/mission` etc. in the main loop — can't be swapped per-agent; set it with `/model` |
| Itachi | Claude Opus | the dossier seeds the whole mission — a misread ticket sends every downstream office the wrong way |
| Shikamaru | Claude Opus | plan review + correctness want the strongest reasoning — and a Claude audit of a GPT plan keeps the design layer cross-model |
| Sakura | Claude Opus | it is a review lens, not just a command runner — `review-rules` was the council's weakest voice on Sonnet |
| ANBU | Claude Opus | adversarial security wants deep reasoning |
| Kurenai | Claude Opus | proving a symbol absent without hallucinating the absence is the hard part — the dispel check wants the strongest reasoning |
| Naruto | Claude Sonnet | git plumbing is destructive and the YubiKey push flow needs retry judgment — not pure mechanical fan-out |
| Gaara | **Codex CLI** — always the newest GPT (currently `gpt-5.6-sol`); review close defaults `GAARA_REASONING=medium`, plan/arbitrate default `ARCHITECT_REASONING=high` | genuine cross-model diversity for the outside read — and, since 0.3.0, for the decisions themselves (plan + arbitrate are one high-leverage call each) |

Frontmatter uses the bare **aliases** (`opus`, `sonnet`, `haiku`, `fable`), never a pinned ID like
`claude-opus-5`. Aliases resolve to the newest model in their tier, so every office stays current
without an edit — the same reason `gaara-codex.sh` resolves its model instead of hard-coding one.
`fable` is available here too; it sits above Opus and is the one genuine step up, but it is priced
roughly double, and these offices run on every mission and every exam.

**Gaara on Codex.** `_council-review` runs `scripts/gaara-codex.sh` for the closer, which shells to
`codex exec --sandbox read-only` (mirrors thk's Counselor Altman, but read-only for review). Since
0.3.0 the same CLI also runs the architect — `scripts/architect-codex.sh` (`plan` + `arbitrate`,
read-only, `ARCHITECT_REASONING` default `high`) — under the same fail-closed policy. Requires
the `codex` CLI on PATH.

The GPT read is the load-bearing part of the review — four Claude lenses grading a Claude change is
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

Because a failed closer now halts the review, the script takes the local diff against `HEAD` (or a
`--base <ref>` snapshot — the delta close) and adds untracked files — a plain `git diff` reported
auto-staged edits and add-only changes as `EMPTY_DIFF`.
A full `profiles.json` (swap any office's model without editing files) is a later phase.

## The four skills

### `/scroll` — draft an issue from a description
`itachi` researches current behavior (code + backend repos) and `shikamaru` structures it; Kakashi
drafts a **lean** issue (Summary / Current / Desired only) and confirms at each gate. AI credit: n/a.

### `/mission <issue>` — take a GitHub or Linear issue to a Draft PR
(Linear: Kakashi reads the ticket, comments, relations and images over the `linear-server` MCP
first — Itachi has no Linear tools — and passes a ticket file; the MCP down = stop and ask) →
`itachi` capture → gate (already-fixed / Linear done, canceled or `BLOCKED` / needs-info / go) →
`shikamaru` **assess** (difficulty dial; `trivial` skips the two plan steps) → **Codex architect
plans** (`architect-codex.sh plan` → `plan.md`; `standard` only) → `shikamaru` reviews the plan
(one revision round) → **Kakashi
executes** (single-agent, per `CLAUDE.md`, deviations logged; design deviations need a `GRANTED`
ruling; a design fork on `trivial` upgrades to `standard`) → `sakura` verify (fix-retry) →
**`_council-review` (fix adapter, plan passed to the closer; risk tier computed vs
`.konoha/critical-paths`)** — declines need an `arbitrate` ruling → **delta close** (Gaara alone
on the fix diff via `--base` snapshot) → `shikamaru` drafts the PR body (links the issue with
`Closes #<n>`, or `Closes <KEY>-<n> — <url>` for Linear; the branch is `issue-<n>` or the lowercased
Linear identifier) → **one confirm** (states both dials) → `naruto` opens the Draft PR (base
`development`; an existing PR is updated through `edit-pr` → `pr-body.sh`, images kept verbatim) →
metrics line appended to `~/.konoha/metrics.jsonl`. AI credit: **No** (your own PR).

### `/debrief <pr-url>` — resolve the reviews on your PR
Two inputs, in order: (1) the **PR URL** → pull comments via `gh` (the AI review bot first, then
teammates); (2) then the skill **asks** if there's a **Slack** review to paste (optional). `shikamaru`
maps the feedback to the task, Kakashi triages (accept / defer / decline-candidate) and fixes —
declines need a `GRANTED` ruling from the Codex architect — `sakura` verifies, `naruto` commits +
resolves fixed threads, and edits a stale body line through `edit-pr` (images kept verbatim).
AI credit: **No** (your own PR).

### `/exam <pr-url>` — review a colleague's PR
Runs **`_council-review` (comment adapter)** on the PR, Kakashi consolidates the findings into **one**
comment, `naruto` posts it in your name with an attributed footer. Plain comment — not a formal
Approve / Request-changes. AI credit: **Yes** — `🍃 Review generated with Julia's Claude Code.`

## The shared module: `_council-review`

Both `/mission` and `/exam` run the same diff review — `anbu` ∥ `shikamaru` (`review-correctness`) ∥
`sakura` (`review-rules`) ∥ `kurenai` in parallel, then `gaara` closes — and return one consolidated, deduped list
of findings. The **caller** applies the output adapter:

| Caller | Target | Adapter | Result |
|---|---|---|---|
| `/mission` | your own diff (pre-PR) | **fix** | Kakashi fixes findings, re-verifies, then ships |
| `/exam` | a colleague's PR | **comment** | consolidate → one attributed comment |

## Language standard: ASD-STE100

Everything the squad writes for humans — dossiers, plans, findings, verify reports, PR bodies,
review comments, issues, and Kakashi's own reports — follows **ASD-STE100 Simplified Technical
English**: short sentences (max 20 words procedural / 25 descriptive), active voice with a named
actor, one topic per sentence, one word per meaning, simple approved words, no idioms or filler.
Code identifiers, paths, commands, and quoted tool output are technical names and stay verbatim. A
required output shape (JSON envelope, PR fragment bullets, commit-message form) wins over STE; STE
governs the prose inside it.

Enforcement follows the plugin's inline-duplication convention (same as the Grep/Glob rule): a
`## Language (ASD-STE100)` block sits in every agent and skill — a dispatched office reads no
shared doc at runtime — plus one rule in the Codex prompt in `gaara-codex.sh` so Gaara follows it
too. Naruto carries a one-line variant: his only self-authored text is `error` / status strings,
and caller-passed text stays verbatim.

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
├── agents/{itachi,shikamaru,sakura,anbu,kurenai,naruto,gaara}.md
├── scripts/gaara-codex.sh      ← Codex adapter for the counselor (review close)
├── scripts/architect-codex.sh  ← Codex adapter for the decision maker (plan + arbitrate)
├── scripts/pr-body.sh          ← image guard: the only way a PR body is edited (check + edit)
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
- **Phase 3 (0.3.0, shipped)** — Codex as decision maker: architect plan + plan review + arbitration
  + deviation log + metrics. Plan-side review arrived here, inverted (GPT authors, Claude reviews).
- **Phase 3.5 (0.4.0, shipped)** — Kurenai joins the council: the AI-output lens — hallucinated
  symbols, invented compatibility, prompt leakage, narration, fabricated tests — under the dispel
  rule (no finding without proof of absence).
- **Phase 3.6 (0.5.0, shipped)** — two dials (difficulty via `assess`, risk computed vs
  `.konoha/critical-paths`; `lite` drops ANBU only), ANBU failure-path lens, delta close
  (`gaara-codex.sh --base` on the fix diff), stale "Shikamaru plans" description fixed.
- **Phase 3.7 (0.6.0 + 0.7.0, shipped)** — `/exam` verifies every finding against the merge base
  and classifies it by provenance; the review opens on the first finding (no preamble, no clean
  list); `/exam` gets its own worktree step; `/mission` is capped at two planned prompts.
- **Phase 3.8 (0.8.0)** — PR images belong to the user: `scripts/pr-body.sh` guards every PR body
  edit (`naruto` `edit-pr`, and `check` before `open-pr`) — the live body is the reference, every
  image reference is carried verbatim in its slot, none is added, a removed one is never restored.
- **Phase 3.9 (0.9.0)** — `/mission` takes a Linear issue link or identifier as well: Kakashi
  reads the ticket, its comments, relations and images over the `linear-server` MCP in the main
  loop (fail closed when it is not connected) and hands Itachi a ticket file; the branch is the
  lowercased identifier; the PR body ends with `Closes <KEY>-<n> — <url>`. The worktree and the
  Draft PR base move from `staging` to `development`.
- **Phase 4 (optional)** — profiles.json, local resume.
