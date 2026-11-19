# konoha — architecture

A Claude Code plugin: a **squad of Konoha ninja** (reusable subagents) that several dev-workflow skills
summon. Inspired by [`thk`](https://github.com/thiagokroger/thk) (The Hand of the King), but where thk
exposes **one** entrypoint, konoha shares **one cast** across **seven** skills.

> You are the **Hokage** — you post the mission and have the final word. The squad does the work.

## The one idea: engine vs. skin

thk bakes its theme into its wiring (skills named `grand-maester`, etc.). konoha splits them:

- **Engine** — a fixed set of neutral **offices** (capture, scholar, enforcer, red-team,
  illusion-dispel, shipwright, counselor, arbiter) + the flow.
- **Skin** — the Naruto cast is a naming layer on top. The theme could be reskinned without touching
  the flow.

## The second idea (0.11.0): Claude plans and executes, Codex audits

From 0.3.0 to 0.10.0 Codex was the decision maker: the architect (Gaara on Codex,
`architect-codex.sh plan`) wrote `plan.md`, Shikamaru reviewed it, and Claude executed it. The
Codex plans then dropped in quality and grew slow — the six logged plan runs (2026-10-22 to
2026-10-28, `~/.konoha/codex-runs.jsonl`) took 9 to 129 minutes each. 0.11.0 gives the plan back
to Claude, as in 0.2, and keeps both Codex audit points:

- **Claude authors the plan.** Shikamaru (`action: plan`) writes `plan.md` as a decision record:
  chosen approach, rejected alternatives, files, forbidden anti-patterns, tests, open questions.
  He opens the real code while he plans, so no separate plan review runs. A blocking open
  question goes to the user, and her answer comes back to Shikamaru as a revision.
- **Claude writes the code; GPT closes the review.** Kakashi executes the plan mechanically and
  logs deviations. A design-level deviation goes back to Shikamaru, who revises the plan and
  records the change under `## Revisions` — the executor never redesigns on his own. The council
  reviews the diff, and the Gaara closer also checks it against `plan.md`.
- **Declining is not the executor's call.** Accepting a finding needs no permission. Declining a
  council or review finding needs a `GRANTED` ruling from `arbiter-codex.sh` (contested items
  batched, one call per round). `/debrief` follows the same rule for review feedback, which
  matters doubly because the frontend-review CI bot runs on Codex: Claude does not get to dismiss
  GPT findings on its own.
- **Fail closed at both Codex points.** A failed closer or ruling halts the flow: retry or stop,
  never a silent Claude substitute. Provenance stays honest; authority, not identity, settles
  disputes (the old "present GPT output as if Claude wrote it" workaround stays retired).
- **Instrumented.** Every mission appends one JSON line to `~/.konoha/metrics.jsonl` (level dials,
  findings per lens, arbitrations, deviations, verify rounds). The outcome metric is how much the
  Codex frontend-review bot complains about the shipped PR, sliced by level (since 0.5.0) and by
  planner: lines before 2026-10-28 carry Codex architect plans, later lines Shikamaru plans.

## The third idea (0.5.0): two dials — difficulty × risk

Mission size is not one scalar. Two independent dials size the ceremony, with different judges
because they are knowable at different times:

- **Difficulty** — how hard is the task? Judged up front from the dossier by Shikamaru `assess`
  (never by Kakashi, who must not grade the scrutiny of his own work). `trivial` skips only the
  plan; a design fork discovered mid-execution upgrades the mission back to `standard`.
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
| `shikamaru` | Scholar | opus | Plan (`plan.md`, revised on a design deviation), root-cause, correctness review, issue-draft review (`/scroll`), difficulty verdict (`assess`) |
| `sakura` | Enforcer | opus | Verification gauntlet (`bun run check` + tests) + convention rules |
| `anbu` | Red-team | opus | Adversarial security + edge-case + failure-path review (full-tier council only) |
| `kurenai` | Illusion-dispel | opus | Genjutsu release (Kai) — AI-output review: hallucinated symbols, invented compatibility, prompt leakage, narration, fabricated tests; every finding carries its dispel proof |
| `naruto` | Shipwright | sonnet | Commit, conclude merge commits, push, open PRs, edit PR bodies through the image guard, post comments/replies |
| `gaara` | Arbiter & Counselor | **Codex CLI** | Closes reviews (`gaara-codex.sh`) and rules on declined findings (`arbiter-codex.sh`) — newest `gpt-*-sol`, the user's config effort, every run logged (0.10.0); mandatory, never falls back to Claude. From 0.3.0 to 0.10.0 also the decision maker that authored `plan.md` |

*(Cut vs thk: no Budget / Master of Coin — Kakashi watches scope himself.)*

## Model & runner assignment

Like thk (which centralizes this in `config/profiles.json`), each office runs on a model matched to its
job — but v1 sets them directly in each agent's frontmatter instead of a profile file:

| Agent | Runner / model | Why |
|---|---|---|
| Kakashi (orchestrator) | your session model (main loop) | runs `/mission` etc. in the main loop — can't be swapped per-agent; set it with `/model` |
| Itachi | Claude Opus | the dossier seeds the whole mission — a misread ticket sends every downstream office the wrong way |
| Shikamaru | Claude Opus | planning + correctness want the strongest reasoning, and the planner must read the real code before it commits to an approach |
| Sakura | Claude Opus | it is a review lens, not just a command runner — `review-rules` was the council's weakest voice on Sonnet |
| ANBU | Claude Opus | adversarial security wants deep reasoning |
| Kurenai | Claude Opus | proving a symbol absent without hallucinating the absence is the hard part — the dispel check wants the strongest reasoning |
| Naruto | Claude Sonnet | git plumbing is destructive and the YubiKey push flow needs retry judgment — not pure mechanical fan-out |
| Gaara | **Codex CLI** — always the newest `gpt-*-sol` the CLI lists (`gpt-6.1-sol` on 2026-10-20), at the user's config `model_reasoning_effort` (`max`); `GAARA_REASONING` / `ARBITER_REASONING` override, fallbacks `xhigh` / `max` | genuine cross-model diversity for the outside read and for the rulings on declined findings (one short, high-leverage call each); since 0.10.0 at full strength, with every run on the record |

Frontmatter uses the bare **aliases** (`opus`, `sonnet`, `haiku`, `fable`), never a pinned ID like
`claude-opus-5`. Aliases resolve to the newest model in their tier, so every office stays current
without an edit — the same reason `gaara-codex.sh` resolves its model instead of hard-coding one.
`fable` is available here too; it sits above Opus and is the one genuine step up, but it is priced
roughly double, and these offices run on every mission and every exam.

**Gaara on Codex.** `_council-review` runs `scripts/gaara-codex.sh` for the closer, which shells to
`codex exec --sandbox read-only` (mirrors thk's Counselor Altman, but read-only for review). The
same CLI also runs the arbiter — `scripts/arbiter-codex.sh` (rulings on declined findings,
read-only) — under the same fail-closed policy; from 0.3.0 to 0.10.0 it was
`architect-codex.sh` and also wrote the plan. Requires the `codex` CLI on PATH.

The GPT read is the load-bearing part of the review — four Claude lenses grading a Claude change is
exactly the blind spot it exists to break — so it is **mandatory and never substituted**. If the
script fails for any reason (`CODEX_UNAVAILABLE` exit 3, `EMPTY_DIFF` exit 4, auth / network /
rate-limit / timeout, empty output), the module stops and asks the user to **retry or stop**. It must
never quietly dispatch the Claude `gaara` agent in its place: a same-family opinion filed under
Gaara's name reads as cross-model diversity while delivering none. The Claude `gaara` agent survives
only for an explicitly requested Claude-side second opinion.

**Gaara stays on the newest model, at full strength (0.10.0).** Neither script hard-codes a version
— a pin rots silently, which is how Gaara kept running `gpt-5.5`, and then the config's `gpt-5.6-sol`,
after the CLI had moved on. `scripts/codex-common.sh` (sourced by both) resolves the model as
`$GAARA_MODEL` / `$ARBITER_MODEL` → the newest visible `gpt-<version>-sol` in the CLI's own
`~/.codex/models_cache.json` → the `model` key in `~/.codex/config.toml` → a fallback pin, and the
reasoning effort as the env override → the config's `model_reasoning_effort` → `xhigh` (review) /
`max` (arbitrate). Before 0.10.0 the scripts carried their own lower defaults (`medium`,
`high`) and ignored the user's `max`. `codex_run` drives `codex exec --sandbox read-only --json`,
prints the final message, surfaces codex's own error event on failure, exits 5 on an empty final
message, and appends one record per call to `~/.konoha/codex-runs.jsonl` (model, effort, exit,
seconds, token usage) — so whether Codex is being used, and how hard, is a file, not a guess.

Because a failed closer now halts the review, the script takes the local diff against `HEAD` (or a
`--base <ref>` snapshot — the delta close) and adds untracked files — a plain `git diff` reported
auto-staged edits and add-only changes as `EMPTY_DIFF`.
A full `profiles.json` (swap any office's model without editing files) is a later phase.

## The seven skills

### `/scroll` — draft a Linear issue from a description
The org's issue-creation workflow (`tplus-services docs/process/issue-creation.md`) with terminal's
overrides: Kakashi orients, dispatches `itachi` once in the background with a frozen research seed,
interviews the user for at least five rounds (the last ones on Verification), drafts Summary /
Context and evidence / Scope / Verification (vitest projects named, `- None: <reason>` otherwise),
has `shikamaru` review the draft fresh (`review-issue-draft`), and creates the issue in Linear team
FE over the `linear-server` MCP after one approval gate. Labels, project and parent only when the
user names them. AI credit: n/a.

### `/mission <issue>` — take a GitHub or Linear issue to a Draft PR
(Linear: Kakashi reads the ticket, comments, relations and images over the `linear-server` MCP
first — Itachi has no Linear tools — and passes a ticket file; the MCP down = stop and ask) →
`itachi` capture → gate (already-fixed / Linear done, canceled or `BLOCKED` / needs-info / go) →
`shikamaru` **assess** (difficulty dial; `trivial` skips the plan) → **`shikamaru` plans**
(`plan.md`; `standard` only; a blocking open question goes to the user) → **Kakashi executes**
(single-agent, per `CLAUDE.md`, deviations logged; a design deviation goes back to Shikamaru for a
plan revision; a design fork on `trivial` upgrades to `standard`) → `sakura` verify (fix-retry;
the final report is kept for the PR's Testing facts) → **`_council-review` (fix adapter, plan
passed to the closer; risk tier computed vs `.konoha/critical-paths`)** — declines need a
`GRANTED` ruling from the Codex arbiter →
**delta close** (Gaara alone on the fix diff via `--base` snapshot) → resync → **`_pr-creation`**
(the PR creation workflow: issue link in the form the check reads — `Closes <owner>/<repo>#<n>`, or
`Closes <KEY>-<n> — <url>` for Linear — split check, requirements check against the ticket's Scope /
Verification, Kakashi builds the description from what exists — her words verbatim, his own sections
for scope drift, tests, comments and implementation, no interview — with notes, testing facts and
the fingerprint footer) → **one confirm**
(states both dials) → `naruto` opens the Draft PR (base `development`; an existing PR is updated
through `edit-pr` → `pr-body.sh`, images kept verbatim) → metrics line appended to
`~/.konoha/metrics.jsonl`. AI credit: **No** (your own PR).

### `/debrief <pr-url>` — resolve the reviews on your PR
Two inputs, in order: (1) the **PR URL** → pull comments via `gh` (the AI review bot first, then
teammates); (2) then the skill **asks** if there's a **Slack** review to paste (optional). `shikamaru`
maps the feedback to the task, Kakashi triages (fix / won't do / another task / question) and
writes one list: the fixes he makes, and the items he proposes not to do. A won't-do proposal needs
a `GRANTED` ruling from the Codex arbiter; the user's own decision needs none. `sakura` verifies.
Since 0.17.0 the round starts with a history check: the resolved threads, earlier Slack and
decision comments and the user's rulings are compared with the new items, and each conflict or
repeat is written up as an explanation (both quotes, why they cannot both hold, the cost of each
option, a recommendation) that waits for her ruling. `git blame` against the head of the previous
round counts the findings on lines the last round wrote; more than a third stops the round. A
round fixes every must-fix and at most 8 others, deletes first, asks before a fix that adds code,
and leaves proposed mechanisms for after the review. The fixes are reviewed before the gate:
`move-check.sh`, Gaara on the delta and `naming-codex.sh` (the full council when they add files or
names or pass 300 lines). A pasted Slack review is posted on the PR verbatim.
After one gate `naruto` commits with a message that names the fix (never `Fix review`; several
fixes → a subject that sums them up and one body line for each), pushes, and each fixed thread
gets a `Fixed in <sha>: <what>` reply and is resolved. Each decision not to do an item gets one short comment with the reason —
a reply in its thread, or one PR comment for the items with no thread. An item that moves to
another task gets a Linear ticket in team FE first (`save_issue` over the `linear-server` MCP, the
`/scroll` sections, no interview), and the comment carries its link. A stale body line is edited
through `edit-pr` (images kept verbatim). AI credit: **No** (your own PR).

### `/exam <pr-url or stack-url>` — review a colleague's PR or stack
Runs **`_council-review` (comment adapter)** on the PR, Kakashi consolidates the findings into **one**
comment, `naruto` posts it in your name with an attributed footer. Plain comment — not a formal
Approve / Request-changes. AI credit: **Yes** — `🍃 Review generated with Julia's Claude Code.`

A stack URL (`github.com/<owner>/<repo>/stack/<n>`) reviews every open PR of the chain. Kakashi reads
it over `gh api repos/<owner>/<repo>/stacks/<n>`, gives each open PR its own worktree, base and
council, one at a time from the bottom, and runs Gaara once on the whole diff. Each finding goes to
the lowest PR that introduces it. The result is one review per open PR, posted after one gate, plus
one Slack block for the whole stack. AI credit: **No** — the user chose no footer (2026-11-10).

Every review body, single-PR or stack, uses the same Markdown: `###` section headings, a bold lead
phrase per finding, identifiers and `file:line` in backticks, and code in fenced blocks.

### `/seal <pr-url>` — seal an existing PR with the workflow fingerprint
For a PR of the user's own that predates the workflow, or was opened outside `/mission`: the live
body is her text, so **`_pr-creation`** runs in edit mode — no draft request and no interview: it
fills what the body leaves out itself, runs the requirements check, and the formatting with her words verbatim
and every image in its slot. `sakura` verifies the checkout for the Testing facts; `naruto` edits
the body through `pr-body.sh` and re-runs the test-requirements check (`rerun-check`), whose
passing run dismisses the bot's "fingerprint missing" review. AI credit: **No** (your own PR).

### `/merge <pr-url, branch or stack-url>` — bring the base into your branch
For a branch of the user's own that fell behind its base or shows conflicts on GitHub. Kakashi
fetches `origin/<base>` over HTTPS (`development`, or the branch below in a stack), previews the
conflicts with `git merge-tree`, runs `git merge --no-ff --no-commit`, and resolves each conflict
from both sides of the history. The skill names the cases that lose work in silence: a
modify/delete that drops tests the base added, a file the base moved, `bun.lock`, generated files,
the `tradingview` gitlink. Then he repairs what the merged tree breaks (removed names, new call
sites, file-name case), `sakura` verifies, and after one gate `naruto` concludes the merge commit
(`merge-commit`: `Merge origin/<base> into <branch>`, one body line for each manual resolution)
and pushes the branch (`push`). A stack URL cascades from the bottom up: each branch takes the
branch below it, commits as the cascade goes, and all pushes wait for one gate. The direction is
fixed: the base comes into the branch. `/merge` never merges the PR and never pushes to the base.
AI credit: **No** (your own branch).

### `/cleanup [pr-url, branch, stack-url or ticket]` — close the work after the merge
For a PR of the user's own that she merged. Kakashi runs it from the main loop, with no subagent:
the work is a few `gh`, `git` and Linear calls. He builds the set from the ticket — every PR whose
body says `Closes` or `Part of` it — checks that each PR is merged and hers, and fetches each
merged head over HTTPS. `scripts/worktree-cleanup.sh` then removes the worktree, the local branch
and the stale `origin/<branch>` ref, or refuses. A squash merge leaves the branch with no ancestor
relation to the base, so the script's test is its own: the tip of the local branch must be the
merged PR head or an ancestor of it. It also refuses uncommitted or untracked files, a process
that runs from the worktree, and ignored files that only the worktree has. The invocation is the
approval: a clean target gets no prompt, and a refusal becomes one written list. The Linear
ticket moves to Done over the MCP only when all of its PRs are merged. Nothing on GitHub changes,
and no step needs the YubiKey. With no argument and no work in the session, the skill lists the
merged PRs that still have a worktree, and she chooses. AI credit: — (no commit, no comment).

### `/cleanup-worktrees [repo]` — sweep the worktrees after many merges
For the work that piled up over many merges. Kakashi runs it from the main loop, with no subagent.
`scripts/worktree-sweep.sh` sorts every worktree and every local branch into `merged`, `open-pr`,
`closed-pr` and `no-pr`. A branch is merged when a PR of the user's with that head is merged and
no open PR uses the name. A detached worktree is merged when a base (the default branch or a
protected branch) or a merged PR holds its HEAD — GitHub's `commits/<sha>/pulls` names the PRs.
A stack base is not a base: a PR decides its state. The sweep fetches the bases and the missing
merged heads over HTTPS. Each merged item goes through `scripts/worktree-cleanup.sh`, which has a
`--detached <path>` mode with the same checks. The clean loop runs in the background. The other
items and the refusals become one numbered list, and only an answer that names the items is a
yes. No ticket moves; the report names the Linear tickets of cleaned PRs that are not Done.
AI credit: — (no commit, no comment).

## The shared module: `_pr-creation`

`/mission` (step 10) and `/seal` run the same PR creation workflow —
`tplus-services docs/process/pr-creation.md` adapted to konoha: Kakashi drives it in the main loop,
it adapts what exists instead of interviewing (0.18.0), and every word she wrote stays verbatim.
The module produces `{ title, bodyFile, housekeeping, fingerprint, proposals }` (`proposals` =
tests to remove, comments to trim, unexplained scope drift, shown at the caller's one gate); the caller ships it
(`naruto` `open-pr` or `edit-pr`). The footer's hidden marker
(`<!-- pr-creation-workflow v1 start=… end=… -->`) is what the auditor's test-requirements check
reads on `opened` / `reopened` / `ready_for_review`; a Draft is not checked until it is marked ready,
which is why `/mission` seals the body before the PR opens. No attribution line precedes the footer
on her PRs.

## The shared module: `_council-review`

Both `/mission` and `/exam` run the same diff review — `anbu` ∥ `shikamaru` (`review-correctness`) ∥
`sakura` (`review-rules`) ∥ `kurenai` in parallel, then `gaara` closes — and return one consolidated, deduped list
of findings. The **caller** applies the output adapter:

| Caller | Target | Adapter | Result |
|---|---|---|---|
| `/mission` | your own diff (pre-PR) | **fix** | Kakashi fixes findings, re-verifies, then ships |
| `/exam` | a colleague's PR | **comment** | consolidate → one attributed comment |
| `/exam` | a colleague's stack | **comment**, per PR | verify, place on the lowest PR → one review per open PR, one gate |

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
| `/debrief` fix commits, decision comments + Linear tickets | yours | **No** |
| `/merge` merge commit | yours | **No** |
| `/cleanup` | yours | — (writes no commit and no comment; it changes only the ticket status) |
| `/cleanup-worktrees` | yours | — (writes no commit, no comment and no ticket status) |
| `/exam` review comment | colleague's PR | **Yes** — attributed footer |
| `/exam` stack reviews | colleague's stack, one per PR | **No** — no footer, names no AI |

## Folder layout

```
konoha/
├── .claude-plugin/{plugin.json, marketplace.json}
├── README.md
├── docs/ARCHITECTURE.md
├── docs/ruled-out.md           ← the ruled-out patterns (code, names, reviews), read before code and by every reviewer
├── agents/{itachi,shikamaru,sakura,anbu,kurenai,naruto,gaara}.md
├── scripts/codex-common.sh     ← shared: newest-sol model + config effort resolution, codex_run (JSON events, run log)
├── scripts/gaara-codex.sh      ← Codex adapter for the counselor (review close)
├── scripts/arbiter-codex.sh    ← Codex adapter for the arbiter (rulings on declined findings)
├── scripts/pr-body.sh          ← image guard: the only way a PR body is edited (check + edit)
├── scripts/worktree-setup.sh   ← makes a worktree runnable: env files in their app folders, submodules, bun install
├── scripts/worktree-cleanup.sh ← removes the worktree and local branch of a merged PR (or a detached worktree), or refuses when something would be lost
├── scripts/worktree-sweep.sh   ← sorts every worktree and local branch: merged / open-pr / closed-pr / no-pr
├── scripts/move-check.sh       ← a move changes nothing: lists files renamed AND edited beyond imports
├── scripts/new-names.sh        ← lists the module-level names a change adds that the base does not have
├── scripts/naming-codex.sh     ← the naming pass on Codex: new names vs the base's names and docs/ruled-out.md
└── skills/
    ├── scroll/SKILL.md          ← create a Linear issue (issue-creation workflow)
    ├── mission/SKILL.md         ← ticket → Draft PR
    ├── debrief/SKILL.md         ← resolve reviews on your PR
    ├── exam/SKILL.md            ← review a colleague's PR
    ├── seal/SKILL.md            ← seal an existing PR with the PR workflow fingerprint
    ├── merge/SKILL.md           ← bring the base into your branch, fix the conflicts
    ├── cleanup/SKILL.md         ← after the merge: remove the worktree and branch, move the ticket to Done
    ├── cleanup-worktrees/SKILL.md ← sweep the repository: remove every merged worktree, list the rest
    ├── _pr-creation/SKILL.md    ← shared PR creation workflow (link, split, requirements, adapt, footer)
    └── _council-review/SKILL.md ← shared diff review (fan-out + close)
```

## Install (local marketplace)

```
/plugin marketplace add ~/Projects/konoha
/plugin install konoha@konoha
```

Skills are then invoked as `/konoha:scroll`, `/konoha:mission`, `/konoha:debrief`, `/konoha:exam`, `/konoha:seal`, `/konoha:merge`, `/konoha:cleanup`, `/konoha:cleanup-worktrees`;
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
| `/seal` | — (new) |
| `/merge` | — (new; the `/mission` resync step, for a branch that is already out) |
| `/cleanup` | — (new; what you did by hand after a merge: move the ticket, remove the worktree) |
| `/cleanup-worktrees` | `/cleanup` (the same guard, for every worktree at once) |

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
- **Phase 3.10 (0.10.0)** — the org's workflows and Codex at full strength: `_pr-creation` runs the
  tplus-services PR creation workflow inside `/mission` (the human writes the description, Kakashi
  interviews and seals it with the fingerprint the auditor's test-requirements check reads) and in
  the new `/seal` for existing PRs; `/scroll` follows the issue-creation workflow and creates Linear
  FE issues over the MCP (Shikamaru `review-issue-draft`, Itachi as the bounded researcher, Naruto
  `rerun-check`); `scripts/codex-common.sh` puts Gaara and the architect on the newest `gpt-*-sol`
  at the user's config reasoning effort, exits 5 on an empty final message, and logs every run to
  `~/.konoha/codex-runs.jsonl`.
- **Phase 3.11 (0.11.0)** — the plan comes back to Claude: Shikamaru `plan` writes `plan.md` in
  the 0.3 decision-record shape and revises it for a design deviation or an answered open
  question (`## Revisions`). The Codex architect's plan mode and Shikamaru's `review-plan` are
  retired; `architect-codex.sh` becomes `arbiter-codex.sh` (`ARBITER_*` env), which keeps only
  the rulings on declined findings. `/mission` loses its plan-review step, so the PR description
  is now step 10 and the ship confirmation step 11.
- **Phase 3.12 (0.12.0)** — `/exam` takes a stack URL and writes `~/Desktop/stack-<n>-review.md`
  instead of commenting: one section per PR, one whole-stack Codex read, no attribution. And
  worktree setup for the Bun workspace: `scripts/worktree-setup.sh`
  replaces the setup blocks of `/mission`, `/exam` and `/seal`, and `/debrief` runs it too. It
  copies each env file beside its tracked `.env.example` (`apps/terminal/.env`, never the worktree
  root), copies the TradingView submodule from `apps/terminal/tradingview`, installs `node_modules`
  in the worktree instead of a symlink to the main checkout's, and fails when the setup changes
  `git status`. `/mission` stops when the main checkout has no env file; it no longer skips the
  step in silence. Sakura stops installing and runs on the `.nvmrc` Node, and `pnpm` commands
  become `bun run`.
- **Phase 3.13 (0.13.0)** — `/exam` on a stack URL posts one review per open PR again, through one
  gate, with no footer, instead of the Desktop file. Every review body takes the file's Markdown
  style: `###` section headings, a bold lead phrase per finding, backticked identifiers and
  `file:line`, fenced code blocks.
- **Phase 3.14 (0.14.0)** — three changes from how the commit tree and the reviews read. Commit
  messages name the change: `/debrief` stops writing `Fix review` / `Fix <Name> review`, and
  `/mission`, `/debrief` and `/seal` share one shape — a subject that says what was wrong, and
  for several fixes a subject that sums them up plus one body line for each. `/debrief` records
  each decision not to do an item as one short comment (this ends the "never post replies" rule
  for that one case) and creates the Linear ticket when the item moves to another task. The new
  `/merge` brings the base into a branch or a stack and fixes the conflicts; Naruto gains
  `merge-commit` and `push`.
- **Phase 3.15 (0.15.0)** — `/cleanup` closes the work after the user merges a PR: the guard
  script `worktree-cleanup.sh` removes the worktree and the local branch of each merged PR or
  refuses, and the Linear ticket moves to Done when all of its PRs are merged. No subagent, no
  GitHub write, no YubiKey step.
- **Phase 3.16 (0.16.0)** — `/cleanup-worktrees` sweeps the whole repository: `worktree-sweep.sh`
  sorts every worktree and local branch, the guard gains a `--detached <path>` mode, the merged
  items go with no prompt, and the rest is one numbered list. No ticket moves.
- **Phase 3.17 (0.17.0)** — after the stack #1500 post-mortem: `/debrief` posts Slack reviews on
  the PR, explains conflicts and repeats before fixing, caps a round and stops when the fixes
  feed the next round, deletes first, asks before additions, defers mechanisms, reviews its fixes
  (move check, Gaara delta, Codex naming pass) and replies `Fixed in <sha>`. `docs/ruled-out.md`
  (Carlos's list) is read by Kakashi and every reviewer; the council runs the move check and the
  naming pass; `/exam` reads the PR history, states problems not mechanisms, reports reversals to
  the user, marks at most five "do first" and applies the stop rule.
- **Phase 3.18 (0.18.0)** — the rules cleanup: `_pr-creation` adapts instead of interviewing
  (no draft request; Kakashi checks scope drift, tests, comments and pieces himself and lists the
  cuts as proposals at the one gate), so `/mission` has two planned prompts; Sakura `verify` runs
  `format:check`; a reviewer's same-shape version that adds code is a "needs your yes" item in
  `/debrief`; Shikamaru plans with tMachine, not XState.
- **Phase 4 (optional)** — profiles.json, local resume.
