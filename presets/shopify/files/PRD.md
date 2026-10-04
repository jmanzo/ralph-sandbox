# PRD -- <feature name>

<!--
  The only file you have to write by hand. The loop reads it every iteration
  and works until everything here is true, so be concrete: the agent cannot
  ask what you meant.

  Keep the first one SMALL. One slice that can be finished and verified beats
  a phase that cannot, and the loop only stops when every box is checked.
  Leave out anything that depends on a decision nobody has made yet -- the
  loop cannot make it for you, and it will either stall or guess.

  Delete these comments once you have filled it in.
-->

## What we are building

One paragraph. What a merchant can do at the end that they cannot do now.

## Stack and constraints

- Shopify app: embedded admin app on Remix / React Router
- Data: Prisma + Postgres
- Tests: <runner>, every external service mocked
- Extensions in scope: <none | theme app extension | checkout UI | function>
- `.ralph/rules.md` holds the rules for this stack. They apply to every task
  here and are not repeated below.

## Definition of done

The loop stops when every box is checked and the verification commands pass.
Keep each box small enough for one iteration.

- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

For anything that touches shop data, say the multi-tenancy requirement out
loud as its own box -- "every query in <module> filters on shop, with a test
that fails if the filter is removed" -- rather than trusting it to be implied.

## Schema changes

<!--
  There is no database in the sandbox. If this feature changes
  prisma/schema.prisma, say so here and the loop will generate the migration
  SQL offline, per .ralph/rules.md. A human applies it.
-->

- [ ] None, or: <model> gains <fields>, migration generated but not applied

## Verification

Commands that must exit 0 before any task counts as done. QA runs these. They
should match the ones in `CLAUDE.md`.

```bash
# e.g.
# pnpm run typecheck
# pnpm run test:run
# pnpm run lint
```

## Out of scope

What to leave alone, so the loop does not wander. Anything it thinks belongs
here anyway goes to `PROPOSALS.md` instead of into the code.

- Deploys of any kind: `shopify app deploy`, `config push`, theme publishing
- Pricing, plan names and billing limits
- API version bumps
- <the decisions you have not made yet>
