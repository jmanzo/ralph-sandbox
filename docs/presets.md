# Presets

A preset is the setup for a stack, laid down in one command:

```bash
ralph init --preset shopify
# edit PRD.md
ralph loop
```

It exists because the second project on a stack should cost nothing to set up.
Everything a preset does, you could do by hand -- the point is not having to
remember it.

## What a preset brings

- **Rules every agent in the loop reads**, in `.ralph/rules.md`: what the
  sandbox cannot do on this stack, and the mistakes that cost the most.
  `CLAUDE.md` imports the file and `AGENTS.md` points at it, so the Anthropic
  and Codex sides cannot drift.
- **The project's build and test commands**, read out of `package.json` and
  written into the `Build and test` section of `CLAUDE.md` -- but only if that
  section is still the placeholder. Your own conventions are never
  overwritten.
- **The settings the sandbox needs**, in `.ralph/config.env`: the dependency
  directories it keeps its own copy of, the files that read empty inside it,
  and the package manager the image has to install. Commit that file.
- **The hosts the stack reaches at build time**, merged into your own egress
  policy. Every host added is printed; `ralph policy ls` shows the result and
  `ralph policy edit` is how you take one back out.
- **A PRD skeleton shaped for the stack**, blank. You still write it.

Nothing is overwritten. Files already in the project are reported as `skip`,
and running `ralph init --preset` a second time changes nothing. `--force`
overwrites, as it always has.

## What a preset cannot do

`.ralph/config.env` may only set what any project may set, which is listed in
[configuration.md](configuration.md#settings-that-live-in-the-project). A
preset cannot turn off the egress policy, change the workspace mode, add
docker arguments or raise a spend ceiling. It can ask for hosts to be
allowlisted, and it tells you each one as it does.

## Available presets

| Preset | For |
| --- | --- |
| `shopify` | Embedded Shopify admin apps: Remix / React Router, Prisma + Postgres, extensions and Functions |

`ralph init --preset` with no name lists them.

## The shopify preset

It assumes an embedded admin app on Remix or React Router with Prisma and
Postgres, and covers four areas that the sandbox or the platform makes easy to
get wrong:

- **No database in the sandbox.** `prisma migrate dev` cannot work, so the
  rules tell the loop to generate migration SQL offline with
  `prisma migrate diff` and leave applying it to you. Existing migrations are
  never edited.
- **One database, many shops.** Every query filtered on the shop, ids from a
  request never trusted, the shop taken from the session, customer-facing ids
  unguessable. This is the part no test failure warns you about.
- **Webhooks, the Admin API and billing.** HMAC first, handlers idempotent
  because the same event arrives twice, `userErrors` checked, one API version,
  entitlement checked server-side on every request that needs it.
- **Extensions and Functions.** Separate builds with their own dependencies,
  nothing secret in Liquid, and no `shopify app deploy` or `function run` --
  they need a Partner login and a tunnel the sandbox does not have.

It also sets `RALPH_ISOLATE` for the root and extension `node_modules`,
`RALPH_MASK` for `.env` and `.env.local`, the project's package manager as a
build arg, and allowlists `binaries.prisma.sh` (the Prisma query engine, which
`generate` downloads on every install) and `shopify.dev` (the API reference
the `shopify-dev-mcp` server reads -- remove it if the loop does not use that
server).

Read `.ralph/rules.md` after it lands. It describes the usual shape of a
Shopify app, and yours differs somewhere; where it does, the file is wrong and
should be corrected rather than worked around.

After `ralph init --preset shopify`:

```bash
ralph build          # installs the project's package manager in the image
ralph status         # what is isolated, what is masked, what is in effect
ralph policy ls      # what the sandbox can now reach
RALPH_LOOP_MAX_COST=10 ralph loop 2   # a short, capped first run
```

That first capped run is worth doing before an uncapped one: it shows whether
the install, the client generation and the tests all work inside the sandbox,
for a couple of dollars rather than overnight.

## Writing one

See [presets/README.md](../presets/README.md). A preset is files plus hosts;
the work is writing `rules.md` honestly and keeping it short enough that an
agent reads it every iteration.
