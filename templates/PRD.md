# PRD -- <project name>

<!--
  This is the only file you have to write by hand. The loop reads it every
  iteration and works until everything here is true. Be concrete: the agent
  cannot ask you what you meant.

  Delete these comments once you have filled it in.
-->

## What we are building

One paragraph. What exists at the end, and who it is for.

## Stack and constraints

- Language / runtime:
- Framework:
- Test runner:
- Things the agent must NOT do (rewrite history, add dependencies, touch CI, ...):

## Definition of done

The loop stops when every box below is checked and the verification commands
below pass. Keep them small enough that one iteration can finish one box.

- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

## Verification

Commands that must exit 0 before any task counts as done. QA runs these.

```bash
# e.g.
# npm run typecheck
# npm test
```

## Out of scope

What the agent should leave alone, so it does not wander. Anything it thinks
belongs here anyway gets written to `PROPOSALS.md` for you to read, rather than
built.
