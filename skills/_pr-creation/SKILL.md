---
name: _pr-creation
description: Internal shared module — the PR creation workflow of tplus-services (docs/process/pr-creation.md) run as a konoha step. Given a branch (uncommitted or committed) or an existing PR, it links the issue, checks for a split, checks the ticket's requirements, BUILDS the description from what already exists (the human's words verbatim, the diff, plan.md, deviations.md, the verify report) with no draft request and no interview, lists what it proposes to cut for the caller's one gate, and ends it with the fingerprint the auditor's test-requirements check reads. Returns a title + body file; the CALLER ships it (/mission via Naruto open-pr, /seal via Naruto edit-pr + rerun-check). Invoked by /mission and /seal, not by the user directly.
---

# _pr-creation — seal the scroll 🍃

You are **Kakashi**, running the PR creation workflow from the main loop. The source of truth is
`tplus-services/docs/process/pr-creation.md`. Read it when a step below is not enough:
`gh api repos/tpluslabs/tplus-services/contents/docs/process/pr-creation.md --jq .content | base64 -d`
(the sibling checkout `../tplus-services` can be stale). This module only **produces the
description**; the caller ships it.

## Input

```
{ workdir, base, repo,                       // base = the PR's base branch; repo = <owner>/<repo>
  ticket: { kind: 'github' | 'linear' | 'none', url?, identifier?, file? },  // file = the ticket text
  verifyFile,                                // Sakura's final verify report: commands, results, counts
  planFile?,                                 // plan.md on a standard mission
  pr?: { url, liveBodyFile, title } }        // edit mode: an existing PR, its body fetched right now
```

## Output

```
{ title, bodyFile, housekeeping: boolean,
  fingerprint: { start, end, split, scopeDrift, tests, docs, implementation },
  proposals: [ { kind: 'remove-test' | 'trim-comment' | 'scope-drift', where, why } ] }
```

`proposals` are the cuts of step 7 that need her yes. The caller shows them at its one gate.

## Hard rules

1. **Adapt, never interview (0.18.0).** Never send a draft request and never run interview
   rounds. Build the body from what exists: her words, the ticket, the diff, `plan.md`,
   `deviations.md`, the debrief and `verifyFile`. Julia, 2026-10-21 on terminal #1251: "I dont
   want the description to be with my own words, addapt what we had to make sure its following
   the new standard". The decisions she makes are Draft or ready, one PR or a split, the
   requirements items, and the step-7 proposals.
1a. **Her words are verbatim.** Every line she wrote (the live body, bullets she gave in this
   session, an answer in this session) goes into the description as she wrote it, spelling and
   grammar included. Reformat freely (sections, bullets, identifiers as code); never reword.
   Everything else is your text, and it never claims to be hers.
2. **Never guess an issue.** Every `Closes` / `Part of` line names an issue the human confirmed.
3. **Don't re-ask what she already said this session.** The mission's ticket is the confirmed
   issue. Her answers to earlier questions count; your own explanations do not. In edit mode the
   live body is her text.
4. **Ask only at the points below** (steps 1, 3, 4 and 5). No researcher, no review subagent, no
   rounds. A question that cannot wait starts with one short context block: why you ask, where
   the answer goes, what happens after. Then ask in her terms (behaviour, not identifiers). When a
   question offers choices, use `AskUserQuestion` and keep a free-form answer possible. A question that needs free text is a plain message that ends your turn.
5. **No AI attribution** — her own PR (konoha rule). The footer is not attribution: it is the
   process record the auditor reads, and it is the last thing in the body. Write it only at the
   end of this module, never to get past the check.
6. **Change code only for a requirements item she chose to address now (step 5).** A test
   removal or a comment trim is a proposal (step 7): the caller applies it only after her yes.
   Never change production code to make a test possible.
7. **Images belong to Julia (0.8.0).** In edit mode every image reference of the live body stays
   verbatim, on its own line, in its slot relative to her text. The caller's `pr-body.sh` guard
   refuses anything else.
8. **A Linear ticket is read over the `linear-server` MCP** — MCP down = stop and ask; never
   `WebFetch` it, never rebuild it from memory (mission hard rule 13).

## Language (ASD-STE100)

Write all prose — your questions, your notes, the Testing facts — in ASD-STE100 Simplified
Technical English:

- Keep sentences short: max 20 words in an instruction, max 25 in a description. Give each
  sentence one topic. Keep paragraphs to max 6 sentences.
- Use the active voice and name the actor. Use the imperative for instructions. Stay in the
  simple present or simple past tense.
- Use one word for one meaning, and the same word every time — never a synonym for variety.
- Use the simple word: use / start / do / show / before / about — not utilize / initiate /
  perform / demonstrate / prior to / approximately.
- Do not use idioms, metaphors, hedging, or filler. Keep noun clusters to max 3 words — break
  longer chains with of / for / in.
- Keep code identifiers, paths, commands, and quoted tool output verbatim — they are technical
  names, exempt from these rules.
- The human's words are hers, never STE-edited. The footer's exact form wins over STE.

## Flow

0. **Start.** Record `START=$(date -u +%Y-%m-%dT%H:%M:%SZ)` now — the footer uses it, and every
   part of a split uses this same start. `git fetch origin`. List the changed files: an
   uncommitted branch → `git diff --name-only HEAD` plus `git ls-files --others --exclude-standard`;
   a committed branch → `git diff --name-only origin/<base>...HEAD`; an existing PR →
   `gh pr diff <url> --name-only`.

   **Reviewed files.** In the repo root run
   `grep -ho 'claude-auditor/.github/workflows/[a-z-]*' .github/workflows/*.yml`, leave out
   `test-requirements-review`, and read off the files each review audits: `frontend-review` →
   `.ts .tsx .js .jsx .mjs .cjs .vue .svelte` (not `.d.ts`); `ts-sdk-review` → the same without
   `.vue` / `.svelte`; `security-audit` → `.rs`, `Cargo.toml`, `.py`, `pyproject.toml`;
   `python-review` → `.py`; `msg-rs-review` → `.rs`; `smart-contracts-solidity-review` → `.sol`.
   terminal runs `frontend-review`.

   A PR that changes no reviewed file is **housekeeping** (docs, CI, a lockfile bump): skip step
   4 and the step-7 checks. Link its issue if it has one (1–2), check the requirements (5), then go to 8.
1. **Find the issue.** Mission: the ticket is the confirmed issue — go to 2. Seal: collect
   candidates from the branch name (`fe-147`, `issue-625`), the commits
   (`git log origin/<base>..HEAD`), the live body's `Closes` / `Part of` lines and the
   conversation (`#123`, `tpluslabs/<repo>#123`, `FE-123`, issue URLs). Read a candidate before
   you offer it (`gh issue view <n> -R <owner>/<repo>`; a Linear one with `get_issue`). With no
   explicit reference, search open issues:
   ```bash
   gh issue list -R tpluslabs/tplus-services --state open --search "<keywords>" --limit 10
   gh issue list -R tpluslabs/project-management --state open --search "<keywords>" --limit 10
   gh issue list -R <owner>/<repo> --state open --search "<keywords>" --limit 10
   gh search issues "<keywords>" --owner tpluslabs --state open --limit 10   # only if the three find nothing
   ```
   Present at most 3 candidates (explicit references first), each with its id, title and a
   one-line reason — `AskUserQuestion`. She confirms one or more, or none.
2. **Link it.** One line per issue in the body, each on its own line:
   - GitHub issue: `Closes <owner>/<repo>#<n>` — the full cross-repo form, even for the PR's own
     repo. GitHub records a closing link only on a PR into the default branch; the check reads
     this line on a PR into any branch.
   - Linear issue: `Closes <KEY>-<n> — <issue url>` — identifier verbatim; never `Closes #<n>`
     (GitHub would close its own issue n). Linear's GitHub integration reads the magic word and
     the identifier. The check cannot read a Linear issue, so step 5 works from the ticket file.
   - A part of a split says `Part of` instead (step 4).
3. **No issue.** If she confirms none, `AskUserQuestion`: run `/scroll` first (a Linear issue in
   team FE), then link it and continue at 4 — or open the PR without an issue, and skip 5.
4. **Split.** Count the production lines the PR changes: added plus removed from
   `git diff --numstat origin/<base>...HEAD` (`HEAD` for an uncommitted branch; `gh pr diff` for a
   PR), leaving out tests (`tests/`, `*.spec.*`, `*.test.*`), fixtures, docs and Markdown,
   generated files, and lockfiles. An estimate is enough. Over 500 lines **and** more than one
   thing — a refactor plus the behaviour that needs it; changes to parts that don't depend on each
   other; new wire types plus their producers and consumers; an unrelated fix picked up on the
   way — → `AskUserQuestion` with two or three concrete splits, each with its parts in merge order,
   the files or commits in each part, and why each part can be reviewed alone, plus **Keep one
   PR**. Under 500 lines, or one change → go to 5 without asking.
   - **Keep one PR** → ask for a one-line reason; it goes in the description.
   - **Split it** → agree the parts, build them on new branches stacked on each other (a part
     that needs an earlier part bases on that part's branch; GitHub retargets it when the earlier
     part merges). Never force-push, rewrite or delete the original branch without asking. Run
     steps 5–8 once per part, bottom of the stack first. Only the part that completes the issue
     says `Closes`; every other part says `Part of`. Each description names the PR it is stacked
     on and the parts that follow once they exist.
5. **Requirements check.** Read the issue's `## Scope` and `## Verification` against the diff —
   from the Linear ticket file, or `gh issue view <n> -R <owner>/<repo> --json body`. An issue
   with neither section has nothing to check: say so in one line and go on (FE tickets written
   before /scroll 0.10.0 have none). An issue with only `Scope` has only Scope to check.

   First find the other PRs for the issue:
   ```bash
   gh search prs "<owner>/<repo>#<n>" --owner tpluslabs --json repository,number,title,state,url
   gh search prs "#<n>" --repo <owner>/<repo> --json number,title,state,url
   gh search prs "<KEY>-<n>" --owner tpluslabs --json repository,number,title,state,url   # Linear
   ```
   Keep the open and merged ones whose description closes the issue (`Closes`, `Fixes`,
   `Resolves`) or says `Part of` it. Read each one's description and files
   (`gh pr view <n> -R <owner>/<repo> --json title,body,files`). An item belongs to another PR when
   that PR's diff covers it, its description says so, or the item names a path, service or test in
   that PR's repo. For a `Part of` PR, the other parts own their items even before they are
   opened. Don't ask about an item another PR owns — list it under Requirements with its PR
   (step 8). When you can't tell, ask.

   List each remaining item that looks unaddressed: a Scope item with no matching change; a
   Verification item with no test added or extended; an existing test the item asks you to keep
   green that `verifyFile` does not show; a scenario item with no run and result. For each,
   `AskUserQuestion`: **address it now** (make the change or run the test, then move on),
   **explain it in the description** (her words, verbatim, under Requirements), or **proceed**.
   The check never blocks the PR.
6. **Her words.** Collect what she already wrote: the live body (edit mode), bullets she gave in
   this session, her answers in this session. Never ask her to draft. When she wrote nothing,
   write the Summary yourself as one-line fragment bullets, her shape (terminal #619, #591), from
   the ticket and `plan.md`.
7. **Check what her words leave out — yourself.** No interview. Go through the four areas the
   workflow names and answer each from the diff, `plan.md`, `deviations.md` and the debrief:
   - **Scope drift** (skip with no issue). The changes beyond the issue's Scope: behaviour it
     doesn't ask for, an unrelated fix or refactor, a changed default, config value or interface.
     Leave out what the scope needs in order to work. Each one with a reason in `plan.md`,
     `deviations.md` or the debrief goes under `## Differences from the issue` with that reason.
     One with no reason anywhere is a `scope-drift` proposal: move it out (step 4) or drop it.
   - **Tests.** Every new test in the diff: `it(…)` / `test(…)` cases, and each test in a new spec
     file. State under Testing what each one protects, from the Verification item it covers or
     from the code (not from its name). A test that protects nothing another test does not, or
     that the repo's rules forbid (pure sizing, links, copy), is a `remove-test` proposal with
     its `file:line` and the test it overlaps.
   - **Docs and comments.** Added comments and docs that restate the code, narrate the change
     ("now we…", "added for #123"), run much longer than their item, or are commented-out code.
     Leave out a comment that explains why (an invariant, an ordering, a workaround) and docs the
     issue asked for. Each one is a `trim-comment` proposal with the shorter version or "remove".
   - **Implementation.** Break the production diff into the pieces a reviewer would ask about: a
     new type, function, hook, store field, message or config value; a changed code path; an
     error-handling, ordering or concurrency choice; a performance choice (hot path, allocation
     in a loop, new round trip, cache). Explain each under Implementation in data-flow order:
     how it works and why, from `plan.md` / `deviations.md` and the code. Mechanical changes
     (renames, imports, formatting) get one line. Where her words and the code differ, say so in
     a note.
8. **The description.** Build the body file:
   - **Her words** (step 6), verbatim, under `## Summary` — or under the section they belong
     to, moved but never reworded.
   - **Your sections** — `## Implementation`, `## Differences from the issue`, `## Testing`,
     the step-5 items under `## Requirements`, the keep-one-PR reason under `## Split` — in plain
     words, fragment bullets where they fit. Leave out a section that does not apply.
   - **Your notes** — `> [!NOTE]` blocks below a line of hers that needs more: the call path,
     the invariant a piece relies on, where her text and the code differ. Never restate or
     rephrase her words.
   - **Links** — the `Closes` / `Part of` lines of step 2, each on its own line. For a stack, a
     `## Stack` section naming the PR this one is stacked on and the parts that follow.
   - **Testing facts**, under Testing, from `verifyFile`: the commands run (`bun run check`,
     `bun run format:check`, `bun run test`) with their results and counts, and the tree they
     ran on (the merged tree of the resync step). What each new test protects comes from step 7.
   - **Mechanical changes** — one line at the end of Implementation.
   - **Items other PRs own** — under Requirements: "covered by tpluslabs/<repo>#<n>".
   - A housekeeping PR gets a short description with no step-7 sections.
   - **Title.** Mission: a short title (3–6 words) in her style; she sees it at the ship
     confirmation. Edit mode: the live title stays unless she changes it.
   - **Footer.** Record `END=$(date -u +%Y-%m-%dT%H:%M:%SZ)` now and end the body with exactly:
     ```
     ---
     <sub>Opened with the PR creation workflow · <YYYY-MM-DD HH:MM–HH:MM UTC> (<N min>) · split: <…> · scope drift: <…> · tests: <…> · docs and comments: <…> · implementation: <…></sub>
     <!-- pr-creation-workflow v1 start=<START> end=<END> -->
     ```
     Fields: **split** `under 500 lines` | `one change` (over 500 but one thing) | `kept as one
     PR` | `part <i> of <n>`; **scope drift** `<N> explained, <M> moved out or dropped` | `none`;
     **tests** `<N> justified, <M> removed` | `none new`; **docs and comments** `<N> kept, <M>
     trimmed or removed` | `none flagged`; **implementation** `<N> pieces, 0 asked about`.
     The counts stay true: write the proposals as not yet cut, and the caller rebuilds the footer
     when she accepts one. A test counts as justified only when Testing states what it protects.
     Housekeeping: `housekeeping, no interview` in place of all five. The check reads only the
     `<!-- … -->` marker — `start` and `end` as `YYYY-MM-DDTHH:MM:SSZ` — the `<sub>` line is for
     people. Nothing follows the marker.
   - Edit mode: carry every image reference of the live body in its slot, on its own line (hard
     rule 7).

   Return `{ title, bodyFile, housekeeping, fingerprint, proposals }`. The caller shows the full
   body once, with the proposals and one line that says the body is adapted, not interviewed.
   An accepted proposal is a code change the caller makes, verifies and counts (the footer
   changes with it). Then the caller ships in the same step —
   `/mission` through Naruto `open-pr`, `/seal` through Naruto `edit-pr` then `rerun-check`.

## What the check does with it

`.github/workflows/test-requirements-review-caller.yml` runs on `opened`, `reopened` and
`ready_for_review`; it skips drafts and bot PRs. When a reviewed file changed and the marker is
missing it requests changes once per PR, in a review a human may dismiss. A later run that finds
the marker dismisses that review. The run does not start on a body edit, so an edit needs
`gh workflow run test-requirements-review-caller.yml -R <owner>/<repo> -f pr_number=<n>` (Naruto
`rerun-check`). A Draft PR carries the marker from the start and passes the moment she marks it
ready. A Linear-linked PR skips the requirements judgement silently; the fingerprint rule still
applies to it.
