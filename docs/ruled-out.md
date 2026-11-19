# Ruled-out patterns — check every change and every review against these

Kakashi reads this before he writes code (`/mission` step 5, `/debrief` step 7). The council lenses
and Gaara read it before they review. A violation is a finding, also when the code works.

Source: Carlos's ruled-out list in his tplus harness (2026-11-09, extended 2026-11-18 after the
stack #1500 post-mortem), taken into konoha 0.17.0 at Julia's request. Terminal examples come from
that stack: one sign-in step tracked in four layers, 99 tAuth source files created and deleted in
three weeks, the command layer rebuilt five times.

## Code

- **Try deleting first.** For a fix, a bug, a review finding or a new requirement, first ask what
  you can remove or simplify to solve it. Add code only when deleting does not solve it.
- **An addition needs a yes.** A review fix that adds a file, a type, an enum, a guard, a state or
  a layer needs the user's OK before you write it. Say what it adds and why deleting does not
  solve it. Everything else is fixed without asking.
- **A state machine models a flow, not data.** A machine owns steps and transitions. Data lives in
  a store, a query, form state or the render. Do not bend a flow so it acts as a store.
- **No layer that holds state its source already has.** When a machine, a store or a stored record
  holds a state (busy, the current step, the session), nothing else holds it again, renames it or
  derives a second status, snapshot or route from it. Read it from the source.
- **No step that guards nothing.** An admission or "may this run" step, a status check or a
  transition table stays only when it stops something real: a wrong value signed or sent, funds
  that move twice, a broken screen. Name what it stops, or leave it out.
- **A new concept has to earn its place.** Before you add a concept with its own name (a "command",
  a "coordinator", a "region", a "run"), say what it gives that a plain function, the existing
  machine or the existing store does not. The word is not banned; the unearned layer is.
- **A move changes nothing.** A commit that moves a file changes nothing in it except import
  paths. Edits go in a separate commit. Then use the moved code as it is.
  `scripts/move-check.sh` checks this.
- **No hand-rolled copy of what a library already does.** Before you write a store, a codec, a
  validator, form state, a cache or a fetch layer, check the libraries of the repo (zod, zustand,
  TanStack Query and Form, Orval, tMachine) and use them.
- **Use the source value when you have it.** Do not parse your own output back into a value you
  already had. Do not add a field to objects that do not need it only to carry a value.
- **No code for cases nobody asked for.** No handling for states the backend cannot send, inputs
  no caller passes, or scenarios outside the ticket. Drop a late or stale case (an answer after the
  user moved on, a remount mid-action); do not track it with tokens, maps or re-checks. This does
  not cover a guard against a wrong signature or a double payment — raise that with the user.
- **A small public surface.** A package exports what its consumers call, from one index file.
  Internal layers stay internal, so a rebuild inside the package does not touch the consumers or
  the tests.
- **Settled rulings bind.** A ruling in the PR's decision comments, the ticket or the user's memory
  holds until the user reopens it. Do not propose again what she ruled out.

## Names

- **One concept, one name.** Use the base branch's name for a concept that already exists, and the
  library's term where the library has one (tMachine, zustand). Never a second name for the same
  thing (`heldKey` and `sessionKeyOf`).
- **One name, one meaning.** A word that means four things in one package (`finish`, `held`) is a
  finding.
- **A reader outside the thread understands it.** No vague words alone (`data`, `info`, `entry`,
  `run`, `handle`, `process`, `manager`, `util`), no jargon of the conversation that made the code.
- **No function that only forwards.** A function that calls another one with the same arguments,
  or only renames it, is not a new concept. Call the original.
- `scripts/naming-codex.sh` asks Codex to check the new names of a change against these rules.

## Reviews (what a reviewer writes, in `/exam` and in the council)

- **State the problem, not a mechanism.** A fix line says what must stop being true ("the step is
  tracked in two places") and prefers deleting. Do not prescribe a store, a machine, a graph or a
  new file unless the plan or a ruling already says so. When a mechanism choice is needed, write it
  as a question for the user.
- **Do not reverse an earlier round.** When an earlier review of the same PR gave a direction,
  check each fix against it. A fix that undoes it is a conflict for the user, not a finding for
  the author.
- **Rank, and keep the first list short.** At most five items are marked "do first". A structural
  finding (layers, state kept twice, a design that changed) goes first and alone.
- **Stop rule.** In a repeat review, when more than about a third of the new findings cite lines
  written since the previous review, the review opens with `STOP: re-plan`, with the count. Another
  long list makes it worse.
