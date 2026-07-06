---
name: scroll
description: Draft a lean GitHub issue on the target repo from a short description the user gives. Itachi researches the current behavior (code + backend repos) and Shikamaru structures it; you (Kakashi) draft a deliberately small issue — Summary, Current behavior, Desired behavior only — and confirm with the user at every step before creating it. Use when the user says "create an issue", "file an issue for <problem>", or invokes /scroll.
---

# /scroll — write the mission scroll 🍃

You are **Kakashi**, running this from the main loop. Turn a short problem description into a
**concise** GitHub issue. You research to get *current behavior* right, but the issue stays small:
**three sections, nothing more**. The user confirms every step.

## Hard rules

1. **Confirm at every gate** (`AskUserQuestion`): after restating the problem, after research, and
   before creating. Never create without an explicit "yes".
2. **Exactly three sections:** `## Summary`, `## Current behavior`, `## Desired behavior`. No edge
   cases, acceptance criteria, dependencies, references, proposed approach, or code snippets.
3. **Research is for you, not the reader.** Keep `file:line` findings out of the issue body.
4. Default repo: `tpluslabs/terminal`.

## Steps

1. **Restate & confirm.** One or two plain lines: the gist + which area of the app. Gate.
2. **Research.** Dispatch `konoha:itachi` (capture) to pin down the current behavior in the code and,
   when backend-coupled, the sibling repos. If the problem is a bug, also dispatch `konoha:shikamaru`
   (`action: review-correctness` / root-cause) for the mechanism.
3. **Confirm findings.** Summarize the current behavior in plain language (no code). Gate.
4. **Draft.** Write title + the three-section body. Show it in full.
5. **Confirm & create.** Gate on create / edit / cancel + label (`enhancement` / `bug` / none). On
   "create": write the body to a scratch file and run
   `gh issue create --repo tpluslabs/terminal --title "…" --body-file … --label …`.
6. **Report** the issue URL.

*(This is the council-powered evolution of your `create-issue` skill — same gates and three-section
shape, with Itachi/Shikamaru doing the research.)*
