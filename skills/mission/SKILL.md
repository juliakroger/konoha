---
name: mission
description: Take a GitHub issue end-to-end to a Draft PR on the target repo. Itachi captures context, Shikamaru plans, you (Kakashi) implement per CLAUDE.md, Sakura verifies, the council reviews the diff and you fix what it flags, then Naruto opens a Draft PR (based on staging) that links the issue with Closes #<n>. Autonomous, with one confirmation before the PR opens. Use when the user says "work on <issue>", pastes a GitHub issue to start, or invokes /mission.
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
   `Closes #<n>`. Each bullet is a **one-line fragment** — imperative or noun phrase, optional
   detail after an em-dash (`Batch trades WS frames — buffered 200ms and single cache write`) —
   **never a full prose sentence or multi-sentence paragraph**; no rationale clauses, no nested
   parentheticals. A short free-text caveat line between the bullets and `Closes` is fine. No
   section headers, no test-coverage sections, no file-by-file walkthroughs. Match Julia's PR
   history (terminal #619, #591 are the canonical shape).
7. **Sync + gate against the latest base right before shipping.** CI builds the PR as a merge with
   the *current* base branch, not the one you branched from. Immediately before opening (or
   updating) the PR: `git fetch origin staging`; if it moved, merge it into the branch (resolve
   semantic conflicts — e.g. new call sites of a function whose signature you changed); then re-run
   `typecheck` + `lint` + `format:check` + tests on that final merged tree. Never open a PR on a
   stale base.
8. **YubiKey approval for every commit and push — via Julia's PIN popup.** She signs commits and
   authenticates pushes with a `verify-required` FIDO2 key, so **every `git commit` and `git push`
   needs a PIN + physical touch**. Naruto runs them with
   `SSH_ASKPASS="$HOME/.ssh/yk-askpass.sh" SSH_ASKPASS_REQUIRE=force` so a macOS PIN dialog pops and
   her key blinks — once per commit, once per push. The step-9 confirmation must warn her the ship
   step will pop that dialog repeatedly and she has to be at the key to approve; only dispatch Naruto
   once she confirms. If a prompt is cancelled or stalls, hand her the exact `git commit` /
   `git push` / `gh pr create` to run herself — never `--no-gpg-sign`, never `--no-verify`, never
   work around it.
9. **NEVER merge a PR.** No `gh pr merge`, no squash/rebase/merge-queue — under any phrasing.
   "Push it" / "lets push it" means `git push` only. Julia always merges manually herself; the
   mission ends at a green-CI PR, never at a merge.
10. **Codex is the decision maker (0.3.0).** The architect — Gaara on Codex, via
    `"${CLAUDE_PLUGIN_ROOT}/scripts/architect-codex.sh"` — authors `plan.md` and rules on every
    contested item. You execute the plan; you do not redesign it. Accepting a finding needs no
    permission — just fix it. DECLINING a finding, or deviating from the plan on a design level,
    requires a GRANTED ruling from `architect-codex.sh arbitrate`. If the script fails (exit 3/4,
    auth, network, timeout, empty output), STOP and ask the user to retry or stop — never author
    the plan or the ruling with a Claude agent, never dispatch `konoha:gaara` as a stand-in, and
    never continue on your own judgment. Fail closed.

## Language (ASD-STE100)

Write all prose — chat updates, reports, drafts — in ASD-STE100 Simplified Technical English:

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
- A required output shape wins over STE — hard rule 6's fragment bullets stay fragments; STE
  governs the prose inside the shape.

## Flow

0. **Preflight.** `gh auth status`. Resolve the target repo; fetch latest `main` + `staging`; create
   a worktree off `origin/staging` (mirror your `work-on` skill's setup). Branch name: exactly
   `issue-<number>` (e.g. `issue-625`).
1. **Capture.** Dispatch `konoha:itachi` with the issue URL + workdir → dossier.
2. **Gate.** If already fixed → stop and say so. If critically underspecified → ask the user. Else go.
3. **Plan (Codex architect).** Write Itachi's dossier to a scratch file, then run
   `"${CLAUDE_PLUGIN_ROOT}/scripts/architect-codex.sh" plan --dossier <file> --workdir <worktree>`
   and save the output as `plan.md` in the worktree root. `plan.md` (and `deviations.md`, step 5)
   stay **untracked — never stage them**. On any script failure: hard rule 10 — AskUserQuestion,
   retry or stop.
4. **Plan review.** Dispatch `konoha:shikamaru` `action: review-plan` with `{ plan, workdir }`. On
   `blocking` findings, run ONE revision round: write the findings to a file and rerun the
   architect with `--revise plan.md --findings <file>`; replace `plan.md`. If blocking findings
   survive the revision, show them to the user and ask how to proceed. `minor` findings ride along
   as execution notes.
5. **Execute.** Implement `plan.md` **yourself**, per `CLAUDE.md`. No fan-out to parallel writers.
   You follow the plan's Decision, Changes, Forbidden, and Tests sections. Log every deviation in
   `deviations.md` (`- <plan item> — <what changed> — mechanical | GRANTED <id>`): a **mechanical**
   deviation (renamed local, moved line, missing import) is logged and you continue; a
   **design-level** deviation (different approach, new file, changed API, skipped test) requires a
   GRANTED ruling first — write the contested item + evidence to a file and run
   `architect-codex.sh arbitrate --contested <file> --plan plan.md --workdir <worktree>`.
6. **Verify.** Dispatch `konoha:sakura` `action: verify`. If red, fix and re-verify (cap 3).
7. **Council.** Invoke the `konoha:_council-review` skill (`mode: "fix"`, `planFile: "plan.md"`) on
   the diff. Apply the **fix adapter**: fix accepted findings freely — accepting needs no
   permission. To decline any finding, batch ALL contested findings of the round into one file
   (id, finding, your objection, evidence) and run ONE `architect-codex.sh arbitrate` call; obey
   every ruling (`DENIED` → fix it; `GRANTED` → declined, record the id). Then re-run verify.
   Cap 2 rounds, max one arbitrate call per round.
8. **Resync.** `git fetch origin staging`; if the base moved since preflight, merge it into the
   branch, fix semantic conflicts, and re-run the full gate set (`typecheck`, `lint`,
   `format:check`, tests) on the merged tree (hard rule 7).
9. **PR body.** Dispatch `konoha:shikamaru` `action: draft-pr-body` (pass the mission's issue URL) →
   `{ title, body }` in the small-and-simple shape of hard rule 6. The body **must** link the issue
   with `Closes #<n>` (`Closes <owner>/<repo>#<n>` if the issue lives in a different repo than the
   PR) — that's the task link, non-negotiable.
10. **Confirm (incl. YubiKey), then ship.** Show the user the title + body + a one-line diffstat and
    get a single OK (`AskUserQuestion`) — in that same prompt, tell her the ship step pops her
    **YubiKey PIN dialog + touch once per commit to sign and again to push**, so she should have the
    key plugged in and be ready to approve each. Then dispatch `konoha:naruto` `action: commit` +
    `action: open-pr` (`--draft --base staging`); Naruto drives both through her PIN popup (hard
    rule 8). If any prompt stalls, give her the exact `git commit` / `git push` / `gh pr create` to
    run herself.
11. **Report & log.** Report the Draft PR URL, then watch CI on the PR (`gh pr checks --watch` or
    poll) and fix any red check before calling the mission done. Finally append one JSON line to
    `~/.konoha/metrics.jsonl` (`mkdir -p ~/.konoha` first):
    `{ ts, issue, pr, findings: { anbu, correctness, rules, gaara }, arbitrations: { asked, granted },
    deviations, verify_rounds, plan_revised }` — this feeds the architect-vs-baseline comparison
    (fewer frontend-review bot findings on the PR is the outcome metric).

*(This is the council-powered evolution of your `work-on` skill.)*
