# Shopify app rules

Written by `ralph init --preset shopify`. Every agent in the loop reads this,
orchestrator and subagents alike, on every iteration. `CLAUDE.md` imports it;
`AGENTS.md` points at it. The project's build and test commands are in
`CLAUDE.md`.

Edit it. It describes the usual shape of a Shopify app, and yours will differ
somewhere; where it does, this file is wrong and should be corrected rather
than worked around.

## What the sandbox cannot do

These are not preferences. The sandbox has no Postgres, no Partner login, no
tunnel, and no network beyond an allowlist a human maintains.

- **No database.** `prisma migrate dev`, `prisma db push`, `prisma studio` and
  anything that opens a connection will fail. Write migrations offline:

  ```bash
  git show HEAD:prisma/schema.prisma > /tmp/schema.prev.prisma
  prisma migrate diff \
    --from-schema-datamodel /tmp/schema.prev.prisma \
    --to-schema-datamodel prisma/schema.prisma \
    --script > prisma/migrations/<timestamp>_<name>/migration.sql
  ```

  Read the SQL before committing it. A human applies it.
- **Never edit a migration that already exists.** It has run somewhere. A
  mistake in it is fixed by a new migration.
- **No `shopify app dev`, `deploy`, `config push` or `function run`.** They
  need a Partner login and a tunnel. Change the files, say so in
  `.ralph/progress.md`, and leave the deploy to a human.
- **No new host.** If something cannot reach the network, that is the egress
  policy and the fix is a human running `ralph policy edit`. Do not work
  around it by vendoring a download.
- **No `git commit --no-verify`.** The pre-commit hook runs the project's
  checks and is the gate that keeps the loop honest.
- **No new dependency without a `PROPOSALS.md` entry** saying what it is for
  and what it replaces. Then wait for a human to promote it.

## One database, many shops

This is the rule that matters most, because breaking it leaks one merchant's
data to another and no test failure tells you.

- **Every query that touches shop data filters on the shop.** Reads, updates
  and deletes alike. A `findUnique` by id with no shop in the `where` is a
  cross-shop read waiting for a guessed id.
- **Never trust an id from a request.** Look it up scoped to the authenticated
  shop and treat "not found" and "belongs to someone else" as the same answer.
- **The shop comes from the session**, via `authenticate.admin(request)` or
  the matching `authenticate.*` helper -- never from a query parameter, a
  header, a form field or a hidden input.
- **An id a customer can see in a URL is unguessable.** Random, not sequential
  and not a database key. Anything reachable without a session needs this.
- **A test that proves the shop filter is applied is worth more than one that
  proves the happy path works.** Write the first one.

## Webhooks

- Verify first: `authenticate.webhook(request)` checks the HMAC. Nothing
  happens before it returns.
- Respond quickly and do the work after. A handler that waits on a slow call
  gets the delivery retried.
- **Make every handler idempotent.** The same event will arrive twice. Key the
  work on something stable from the payload and make a repeat a no-op.
- Take the shop from what the authenticated helper returns, not from the body.
- `app/uninstalled` deletes or deactivates that shop's sessions and stops its
  scheduled work. A reinstall must not resurrect stale state.
- A handler's tests cover: a bad HMAC refused, an unknown shop refused, a
  duplicate delivery harmless.

## Admin API

- **GraphQL, not REST,** for anything new.
- **One API version for the whole app.** The server config and
  `shopify.app.toml` agree, and bumping it is its own task with its own PRD
  line -- never a side effect of another change.
- **Ask for the fields you use.** Nothing else.
- **Check `userErrors` on every mutation.** A 200 with `userErrors` is a
  failure, and treating it as success is how bad data gets written.
- **Handle throttling.** Read the cost extensions on the response and back
  off. Never retry in a tight loop; never retry a mutation without knowing it
  is safe to repeat.
- Bulk work goes through the bulk operation APIs rather than a loop over
  pages.

## Billing

- **Check entitlement on the server, on every request that needs it**, through
  the billing API. A flag in the session, in the database or in the client is
  not a check.
- Development and test shops use test charges. Never a live charge from a
  test.
- **Prices, plan names and limits are product decisions.** Change them only
  when a PRD line says to, and never as part of another task.

## Routes and the admin UI

- `loader` reads, `action` writes. No mutation in a loader.
- Validate form data at the boundary and pass validated values into Prisma,
  never request values.
- Server-only modules (`*.server.ts`) are never imported from a component.
- Polaris for UI and App Bridge for navigation, toasts and modals; do not
  hand-roll what they provide.
- An error in a loader or action returns something the UI can show. An
  unhandled throw in an embedded app is a blank iframe for the merchant.

## Extensions

`extensions/*/` are separate builds, each with its own `package.json` and its
own dependencies. Install inside the extension's directory, not at the root.

- **Theme app extensions:** Liquid in `blocks/`, settings declared in the
  block schema, assets in `assets/`. The storefront is public -- no secrets,
  no admin data, no API keys in Liquid or in anything it serves.
- **Checkout UI extensions:** they run in a worker with no DOM and restricted
  network access. Only what the extension declares is reachable. Keep logic
  small and put anything substantial behind the app's own endpoint.
- **Extension configuration (`shopify.extension.toml`) does nothing until it
  is deployed**, and deploying is not possible here. Change it, note it, stop.
- Extensions cannot be validated against a real shop in the sandbox. Unit
  tests against fixtures are the whole verification available.

## Functions

- A Function (discount, cart transform, delivery or payment customization)
  compiles to WASM and has its own build and test commands. Unit-test the run
  function against input fixtures and assert on the operations it returns.
- The input is a GraphQL query in the function's directory. Keep it minimal:
  the runtime has an instruction budget, and every field costs.
- A Function cannot run against a real cart here. Fixtures are the test.
- Discount and cart logic is money. A fixture for the boundary case -- zero,
  empty cart, already-discounted line, quantity of one -- is not optional.

## Tests

- Every external service is mocked: Shopify, the database, email, payments.
  No test reaches the network.
- A test that needs a real database usually means the logic belongs outside
  the query layer. Move it and test it there.
- When a bug is fixed, the test that would have caught it lands in the same
  commit.
