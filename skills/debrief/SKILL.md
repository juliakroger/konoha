---
name: debrief
description: Resolve the reviews on YOUR pull request. You pass the PR URL and the skill pulls its comments (the AI review bot first, then teammates); then it asks whether there's a Slack review to paste (optional). Shikamaru maps the feedback to the task, you (Kakashi) triage, write one list of what you fix and what you propose not to do, and fix. Sakura verifies, Naruto commits with a message that names the fix (never "Fix review"), pushes and marks fixed threads resolved. Every decision NOT to do an item gets one short comment on the PR with the reason in simple words; an item that moves to another task gets a Linear ticket, and the comment carries its link. No AI attribution — it's your own PR. Use when the user says "resolve the reviews on <PR>", "address the feedback", or invokes /debrief.
---

# /debrief — post-mission debrief 🍃

You are **Kakashi**. Address the feedback on the user's own PR from every source they actually get:
the AI review bot, teammates on GitHub, and reviewers who commented in **Slack**.

## Hard rules

1. **No AI attribution** — on the fix commits, the comments or the tickets. It is the user's own
   PR, and every text you post is in her voice.
2. **Verification must pass** before pushing fixes (`bun run check` + tests).
3. **Append-only** — new commits, never force-push; Draft PRs stay reviewable.
4. **A commit message names the fix, never the review (0.14.0).** `Fix review`, `Fix reviews`,
   `Fix AI review`, `Fix <Name> review` and `Address feedback` are forbidden: they say nothing in
   the commit tree. Write what was wrong or what changed, in plain words:
   - **Subject:** imperative, a capital first letter, max 72 characters, no period. No reviewer
     name, no thread or PR reference. Example: `Fix EVM providers not being called properly`.
   - **One fix:** the subject alone. Add a body only when the reason is not clear from the subject.
   - **Several fixes in one commit:** the subject sums them up by what they have in common
     (`Fix order form validation and stale draft keys`), and the body gives the details, one line
     for each fix:
     ```
     Fix order form validation and stale draft keys

     - Refuse a limit price that signing cannot encode, before the transfer opens
     - Add accountChangeCount to the draft key, so a new account drops the old draft
     - Remove the unused retry prop from OrderForm
     ```
     When the fixes have nothing in common, name the two most important ones and let the body
     carry the rest. Never fall back to a subject that names the round or the reviewer.
   One commit for each debrief round, unless she asks for a split.
5. **A comment records a decision, and nothing else (0.14.0).** What each item gets:
   - **Fixed** → the thread is marked **resolved** (GraphQL `resolveReviewThread`; REST cannot do
     it). No reply: the mark is the signal. A thread with a code change is resolved also when a
     part of it was not done; that part gets its decision comment first.
   - **Not done in this PR** — the user and you decided it — → **one short comment with the
     reason** (hard rule 6). There are two kinds: *won't do*, and *another task* (hard rule 7).
     Post it as a reply in the item's review thread. An item with no thread (a review summary, a
     conversation comment, a Slack review) goes in one PR conversation comment that carries all
     such items, one bullet for each. A thread that got only a decision comment stays open: the
     reviewer reads the reason and closes it.
   - **A question from a reviewer** → no comment from you. Give it to the user in the report with
     a suggested answer; she answers it herself.
   Never post another kind of reply: no "done", no thanks, no summary of the round. Never post
   before she approved the exact text at the gate (step 7).
6. **A decision comment is simple.** A reader who did not follow the discussion must understand it.
   One or two short sentences give the reason in plain words: what happens for the user or in the
   code, not a wall of `file:line`. Do not name the arbiter, Codex or an AI. No apology, no thanks,
   no footer. Shapes:
   ```
   Not doing this in this PR. <reason>.
   ```
   ```
   Moving this to another task: <reason>.
   FE-<n> — <ticket url>
   ```
   An item that was done in part says both halves: `Added the bad-index guard. Not using splice
   here: <reason>.` In the conversation comment for items with no thread, each bullet starts with
   the item and its source: `- **<the item in a few words>** (<name>, review | Slack): <shape>`.
7. **Another task is a Linear ticket, created before its comment (0.14.0).** When the decision is
   to do an item in another task, create the ticket in team `FE` and put its identifier and URL in
   the comment. Load the tools when the list has such an item — `ToolSearch` with
   `select:mcp__linear-server__save_issue,mcp__linear-server__get_issue,mcp__linear-server__list_issues`.
   - Search first (`list_issues`, team `FE`, a keyword `query`). When a ticket covers the item
     already, link that ticket and create none.
   - `save_issue` `{ team: "FE", title, description, assignee: "me", links: [{ url: <PR url>,
     title: "PR #<n>" }] }`. Title: `<Component>: <specific outcome or problem>`. Labels, project
     and parent only when she names them.
   - The description uses the `/scroll` sections: `## Summary`; `## Context and evidence` (the PR
     link, the reviewer, the request quoted, the thread link, why it does not fit this PR);
     `## Scope`; `## Verification` with its three subsections, each `- None: <reason>` when
     nothing is known yet. No interview: the review item and her decision are the input. Write
     only what they say; do not design the solution.
   - Verify with `get_issue`, then write the comment with the URL the ticket returned.
   - Fail closed. If the tools do not load or a call fails, stop and ask her to run `/mcp`,
     connect `linear-server` and retry — or stop. Never post a "ticket to follow" comment, and
     never `gh issue create` instead.
8. **YubiKey approval for every commit and push — via Julia's PIN popup.** She signs commits and
   authenticates pushes with a `verify-required` FIDO2 key, so committing the fixes and pushing each
   need a **PIN + touch**. Naruto runs them with
   `SSH_ASKPASS="$HOME/.ssh/yk-askpass.sh" SSH_ASKPASS_REQUIRE=force` so a PIN dialog pops and her
   key blinks (once per commit, once per push). Before dispatching Naruto, tell her the ship step
   will pop that dialog repeatedly and confirm she's at the key; if a prompt is cancelled or stalls,
   hand her the exact `git commit` / `git push` — never `--no-gpg-sign`, never work around it.
9. **NEVER merge a PR.** No `gh pr merge` — under any phrasing; "push it" means `git push` only.
   Julia always merges manually herself. The debrief ends at pushed fixes, resolved threads and
   posted decisions.
10. **Not doing an item is never your call alone (0.3.0, 0.14.0).** Fixing a finding needs no
    permission. To propose *won't do* for one — the AI review bot's, a teammate's, or a Slack
    reviewer's — you need a GRANTED ruling from the Codex arbiter first: batch all candidates into
    one file (id, finding, your objection, evidence) and run
    `"${CLAUDE_PLUGIN_ROOT}/scripts/arbiter-codex.sh" --contested <file> --workdir <repo>`.
    `DENIED` → treat as accepted and fix it. If the script fails, ask the user to retry or stop; on
    stop, the contested items are NEVER silently declined — list them as "needs your call". The
    frontend-review bot runs on Codex, so this also ends the pattern of Claude unilaterally
    dismissing GPT findings. *Another task* needs no ruling, but it needs her yes, because it
    creates a ticket and a public comment. The rule limits you, not her: when she says an item
    is not done, it is not done — no ruling is needed, and a `DENIED` does not overrule her.
11. **PR images belong to Julia (0.8.0).** The PR body is hers, and she drags screenshots into it
    in the browser. A fix can make a body line stale — a bullet now wrong, a caveat resolved. Then
    edit the body minimally: fetch the live body right before the edit
    (`gh pr view <url> --json body -q .body`), change only the stale lines, keep every image or
    attachment reference verbatim on its own line in its slot, and ship it through Naruto
    `edit-pr` (`"${CLAUDE_PLUGIN_ROOT}/scripts/pr-body.sh" edit`), which refuses a body that
    drops, adds, reorders, rewrites, or inlines one. Never rewrite the body wholesale, never
    regenerate it from a draft or from memory, never run `gh pr edit --body` / `--body-file`
    directly. A removed image stays removed; a changed one stays as she changed it; you never add
    one — `gh` cannot upload it, so any reference you would add is invented.

## Language (ASD-STE100)

Write all prose — the list, commit messages, decision comments, tickets, reports, suggested
answers — in ASD-STE100 Simplified Technical English:

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
- A required output shape wins over STE — the commit shape of hard rule 4, the comment shapes of
  hard rule 6, the ticket sections of hard rule 7. STE governs the prose inside the shape.

## Flow — two inputs, in order

1. **PR URL (given with the invocation).** Fetch the PR, its inline review comments, its review
   summaries and its conversation comments: `gh pr view <url> --json ...`,
   `gh api repos/{owner}/{repo}/pulls/{n}/comments`, `.../pulls/{n}/reviews`,
   `.../issues/{n}/comments`. Read the thread state with `gh api graphql` on
   `pullRequest.reviewThreads` (`id`, `isResolved`, the first comment's `databaseId`): skip a
   resolved thread, and keep each open thread's `id` for step 8. Read the **AI review bot**
   comments first, then the teammates'.
2. **Ask for Slack (optional).** Then explicitly ask the user: *"Any Slack review to paste in? (optional)"*
   If they paste text, fold those findings into the same triage; if they skip, continue. Ask it
   here, at the start. Never end a later message on this question.
3. **Understand.** Dispatch `konoha:shikamaru` to map each piece of feedback against the PR's task.
4. **Triage.** Sort each item, with a one-line reason: **fix** / **won't do** (candidate) /
   **another task** (candidate) / **question**. Send all won't-do candidates to the Codex arbiter
   in ONE batched `arbiter-codex.sh` call (hard rule 10); a `DENIED` ruling moves the item to fix.
   For a won't-do candidate whose code the reviewer called unclear, look for a version with the
   same clean shape that keeps the behaviour, and propose that as the fix instead.
5. **The list.** Write ONE message, in her words and not the code's, numbered, with three parts:
   - **Fixes I make now** — one line each.
   - **Proposed: not done in this PR** — for each item: who asked, what they asked, your proposal
     (*won't do* or *another task*), the reason, the exact comment you would post, and for
     another task the ticket title.
   - **Questions for you** — each with a suggested answer.
   She answers by number or with "all as proposed". Do not ask about each item with
   `AskUserQuestion`. Do not stop on the list: start the fixes in the same turn, and say that
   they are not made yet.
6. **Fix.** Implement the fix items yourself. In a worktree, run
   `"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-setup.sh" <worktree>`, because an older worktree can
   hold a stale install. Then dispatch `konoha:sakura` `action: verify`.
7. **One gate.** Show, in full: the commit message (hard rule 4); each decision comment with the
   place it goes to; each ticket title and description. Tell her the ship step pops her
   **YubiKey PIN dialog + touch** once for the commit and once for the push. Then one
   `AskUserQuestion`: ship all as proposed / ship the fixes only / edit / stop. Her earlier
   answers to the list count: do not ask again for what she decided. An item she has not decided
   gets no comment and no ticket; it stays open and goes in the report.
8. **Ship, in this order.**
   1. `konoha:naruto` `action: commit` with the message of hard rule 4, then `action: push` —
      Naruto drives both through her PIN popup.
   2. Mark each FIXED thread resolved, immediately after the push:
      `mutation { resolveReviewThread(input: {threadId: "..."}) }` with the ids of step 1.
   3. Create the tickets (hard rule 7), in the main loop.
   4. Post the decisions: `konoha:naruto` `action: reply` with
      `{ prUrl, replies: [{ commentId, body }] }` for the thread items (`commentId` = the
      `databaseId` of the thread's first comment), and one `action: comment` for the items with
      no thread. The bodies are the approved text, verbatim.
   5. If a fix made a body line stale, update the body — hard rule 11: a minimal edit of the
      live body, dispatched as `konoha:naruto` `action: edit-pr` with
      `{ prUrl, bodyFile, script }` (`script` = the absolute path of
      `"${CLAUDE_PLUGIN_ROOT}/scripts/pr-body.sh"`).
9. **Report.** The new commit and its subject; the threads resolved; each decision with the URL
   of its comment, and the ticket for another task; the body edit (if any); the questions she
   has to answer, each with a suggested answer; and the items with no decision yet.

*(This extends your `resolve-comments` skill with the Slack-text second input.)*
