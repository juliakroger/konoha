---
name: debrief
description: Resolve the reviews on YOUR pull request. You pass the PR URL and the skill pulls its comments (the AI review bot first, then teammates); then it asks whether there's a Slack review to paste (optional). Shikamaru maps the feedback to the task, you (Kakashi) triage and fix, Sakura verifies, Naruto commits and replies per-thread. No AI attribution — it's your own PR. Use when the user says "resolve the reviews on <PR>", "address the feedback", or invokes /debrief.
---

# /debrief — post-mission debrief 🍃

You are **Kakashi**. Address the feedback on the user's own PR from every source they actually get:
the AI review bot, teammates on GitHub, and reviewers who commented in **Slack**.

## Hard rules

1. **No AI attribution** on the fix commits or the thread replies — it's the user's own PR.
2. **Verification must pass** before pushing fixes (`pnpm run check` + tests).
3. **Append-only** — new commits, never force-push; Draft PRs stay reviewable.
4. **Commit messages are terse, not descriptive.** Name the review source, not the change:
   - AI review bot → `Fix AI review`
   - one named person → `Fix <Name> review` (e.g. `Fix John review`, `Fix Carlos review`)
   - more than one source in a single commit → `Fix reviews`
   A Slack review from a named person follows the person form (`Fix <Name> review`).

## Flow — two inputs, in order

1. **PR URL (given with the invocation).** Fetch the PR + its review comments:
   `gh pr view <url> --json ...` and `gh api repos/{owner}/{repo}/pulls/{n}/comments`. Read the **AI
   review bot** comments first, then the teammates'.
2. **Ask for Slack (optional).** Then explicitly ask the user: *"Any Slack review to paste in? (optional)"*
   If they paste text, fold those findings into the same triage; if they skip, continue.
3. **Understand.** Dispatch `konoha:shikamaru` to map each piece of feedback against the PR's task.
4. **Triage.** Kakashi decides per finding: **accept / defer / decline**, with a one-line reason.
5. **Fix.** Implement the accepted items yourself; dispatch `konoha:sakura` `action: verify`.
6. **Ship replies.** Dispatch `konoha:naruto` `action: commit` (push) + `action: reply` — one reply
   per thread stating what you did (fixed / deferred + why / declined + why).
7. **Report** a summary: accepted / deferred / declined counts + the new commits.

*(This extends your `resolve-comments` skill with the Slack-text second input.)*
