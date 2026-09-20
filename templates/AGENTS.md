# Repository guide

**Read `CLAUDE.md` in the repository root first.** It holds this project's
conventions and the rules of the Ralph loop, and it is the same contract for
every agent working here whichever provider is driving. This file exists
because Codex looks for `AGENTS.md`; it deliberately does not restate those
rules, so the two cannot drift.

## What is different when Codex is driving

Codex runs this loop as **one session playing all four roles** -- orchestrator,
architect, developer and QA -- because Codex has no per-role subagent
definitions, only a single default subagent model. Claude runs the same loop as
four separate agents with four different models.

That means nothing enforces the separation for you. In particular:

- **You wrote the code you are about to verify.** Run the PRD's verification
  commands and read the diff as if someone else wrote it. A PASS you gave
  yourself without running anything is the most expensive kind of wrong,
  because every iteration after it trusts the green.
- **Each provider gets three attempts at a failure**, not three per iteration.
  A handover gives Codex a fresh budget so it can try a different theory;
  `.ralph/progress.md` shows which provider made each attempt.
- **You are the last provider in the loop.** Nothing catches what you drop.

`.ralph/PROMPT.codex.md` is the full iteration protocol. The loop feeds it to
you on every iteration; you do not need to open it yourself.
