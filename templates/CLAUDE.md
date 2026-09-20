# Project conventions

<!-- Replace this with the real conventions for your codebase. The loop reads
     it on every iteration, so keep it short and true. -->

## Ralph loop rules

This repository is worked on by an autonomous loop (`ralph loop`). The rules
below apply to every agent in it, orchestrator and subagents alike.

- **One task per iteration.** Never start a second task because the first was
  small. Finishing early is the correct outcome.
- **The PRD is the contract.** `PRD.md` decides what done means. If a request
  conflicts with the PRD, the PRD wins; note the conflict in
  `.ralph/progress.md`.
- **Leave the tree green.** Every iteration ends with the verification commands
  in `PRD.md` passing, or with the failure written down in
  `.ralph/progress.md`.
- **Commit every iteration.** One focused commit. The loop's memory is the git
  history plus `.ralph/progress.md` -- nothing else survives.
- **Never rewrite history.** No `rebase`, no `commit --amend`, no force pushes.
  A bad iteration is fixed by the next commit, not by erasing the last one.
- **Write down what you learned.** A surprise that is not in
  `.ralph/progress.md` will surprise the next iteration too.
- **Ideas the PRD did not ask for go in `PROPOSALS.md`.** Not into the code,
  not into the plan. A human promotes them into `PRD.md` later, or doesn't.
- **Three attempts at the same failure per provider.** Not three per
  iteration. A handover gives Codex three attempts at a different theory; if
  Codex spends them too, the run stops and a human is alerted.

## Who runs on what

| Role | Model | Why |
| --- | --- | --- |
| Orchestrator | `haiku` | Routing and bookkeeping, not judgement |
| Architect | `sonnet` | Design and sequencing |
| Developer | `opus` | The reasoning is here; this is where the code gets written |
| QA | `sonnet` | Running things and reporting precisely |

Change one with `ralph model <role> <model>`; `ralph model` alone lists them.

If the loop hands over to Codex -- on a usage limit, on repeated failure, or
when three attempts on one failure are spent -- all four roles collapse into one
session on `RALPH_CODEX_MODEL` (default `gpt-5.6-sol`), because Codex has no
per-role subagent definitions. See `AGENTS.md` for what that changes.

**Starting cheap.** For an MVP, run the developer on `sonnet` as well
(`ralph model developer sonnet`) and leave it there while the work is
CRUD-shaped. Escalate to `opus` when the evidence says to -- intricate domain
logic, a third-party integration that keeps failing in new ways, or the same
signature coming back from QA more than once. Escalate the *developer* first;
it is rarely the architect that is underpowered, and never the orchestrator.

## Build and test

```bash
# fill in: install, build, test, lint
```
