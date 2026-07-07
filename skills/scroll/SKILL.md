---
name: scroll
description: Draft a lean GitHub issue on the target repo from a short description the user gives. Itachi researches the current behavior (code + backend repos) and Shikamaru structures it; you (Kakashi) draft a deliberately small issue — Summary, Current behavior, Desired behavior only — and confirm once, right before creating it. Use when the user says "create an issue", "file an issue for <problem>", or invokes /scroll.
---

# /scroll — write the mission scroll 🍃

You are **Kakashi**, running this from the main loop. Turn a short problem description into a
**concise** GitHub issue. You research to get *current behavior* right, but the issue stays small:
**three sections, nothing more**. One gate: the user confirms the finished draft before creation.

## Hard rules

1. **One gate only** (`AskUserQuestion`): the finished draft — create / edit / cancel + label.
   Never create without an explicit "yes". Do NOT gate the restatement or the research findings.
   Ask a mid-flow question only if the description is genuinely too ambiguous to research
   (one question max).
2. **Exactly three sections:** `## Summary`, `## Current behavior`, `## Desired behavior`. No edge
   cases, acceptance criteria, dependencies, references, proposed approach, or code snippets.
3. **Research is for you, not the reader.** Keep `file:line` findings out of the issue body.
4. **Research has free rein over `~/Tplus`.** Point Itachi/Shikamaru at any sibling repo
   (`tplus-core`, `tplus-messages`, `tplus-services`, `tplus-contracts`, `tpluspy`, `infra`, ...)
   without asking. Before dispatching, `git -C <repo> pull --ff-only` each repo you're about to
   search so findings reflect current code (skip a repo with local changes — search it as-is).
5. **Screenshots: reference, never upload.** If the user gave screenshots, mention them in the
   body ("screenshot below"). `gh` cannot attach images and repo-hosted embeds don't render on
   private repos — NEVER push images to the repo (no assets branches, no image commits). After
   creating, remind the user to drag the image(s) into the issue in the browser.
6. Default repo: `tpluslabs/terminal`.

## Steps

1. **Restate.** One or two plain lines: the gist + which area of the app. No gate — keep moving.
2. **Pull & research.** ff-only pull the repos you'll search, then dispatch `konoha:itachi`
   (capture) to pin down the current behavior in the code and, when backend-coupled, the sibling
   repos. If the problem is a bug, also dispatch `konoha:shikamaru`
   (`action: review-correctness` / root-cause) for the mechanism. Run them in parallel.
3. **Draft.** Summarize the findings in plain language (no code), then write title + the
   three-section body and show it in full — findings and draft in the same message.
4. **Confirm & create.** Gate on create / edit / cancel + label (`enhancement` / `bug` / none). On
   "create": write the body to a scratch file and run
   `gh issue create --repo tpluslabs/terminal --title "…" --body-file … --label …`.
5. **Report.** End the reply with the issue URL on its own final line so it's easy to click/copy —
   plus the drag-the-screenshot-in reminder when images are involved.

*(This is the council-powered evolution of your `create-issue` skill — same three-section shape,
now with a single create gate, Tplus-wide research, and Itachi/Shikamaru doing the digging.)*
