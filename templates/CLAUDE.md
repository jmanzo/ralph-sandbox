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

## Build and test

```bash
# fill in: install, build, test, lint
```
