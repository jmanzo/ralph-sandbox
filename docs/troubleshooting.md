# Troubleshooting

`ralph status` first: it shows what is actually in effect, including which
provider is logged in and whether the proxy is up.

**`Not logged in - Please run /login`** -- expected on first run.

**Something in the sandbox can't reach the internet** -- most likely the policy.
`ralph policy test <host>`, then `ralph policy edit` to allow it.

**`egress proxy is not accepting connections`** -- `ralph proxy logs` shows the
tinyproxy error. Note `FilterType` must be `ere`; `fqdn` is not supported by the
tinyproxy 1.11.x that Alpine ships.

**Login doesn't stick** -- the home volume was removed or renamed. `ralph status`.

**`CODEX_HOME points to ... but that path does not exist`** -- a home volume
created before codex support was added. The entrypoint now creates it on every
start, so `ralph update` fixes it; you do not need to lose your logins.

**The codex fallback never takes over** -- `ralph login status` (is it signed
in?), then `ralph policy sync` (can it reach `auth.openai.com`?). `ralph loop`
warns about the second before a run starts, and `.ralph/alert.json` records
whether a handover was attempted.

**`pnpm: command not found` (or yarn, or bun)** -- the image ships npm only.
Put the project's manager in `RALPH_BUILD_ARGS` and rebuild:
`RALPH_BUILD_ARGS="--build-arg EXTRA_NPM_PACKAGES=pnpm" ralph build`. In a
project's own `.ralph/config.env` it survives `ralph update` too, which plain
`--build-arg` on the command line does not. `ralph init --preset` writes that
line for you, with the version from `packageManager`.

**The host's `node_modules` broke after a run** -- the sandbox is Linux and it
installed Linux binaries over your macOS ones (or the reverse). `RALPH_ISOLATE`
is the fix, and it is a setting, not a repair: reinstall on the host once,
then let each side keep its own copy. See
[configuration.md](configuration.md#keeping-host-and-sandbox-dependencies-apart).

**Nothing runs inside the sandbox, but the host is fine** -- the same problem
seen from the other end. The shared `node_modules` holds your machine's
binaries, which the container cannot execute. Same fix.

**`prisma generate` fails to download an engine**, or a browser or toolchain
download times out -- the egress policy. `ralph policy test binaries.prisma.sh`
to confirm, then `ralph policy edit`. The shipped policy lists the common ones,
commented out, with a note on each.

**Something needs a database and there is nothing to connect to** -- there is
no Postgres, MySQL or Redis in the sandbox and no route to one on your host.
Either keep the work offline -- `prisma migrate diff --script` writes migration
SQL without a server -- or run that part outside the loop. The PRD should say
which, or the loop will spend iterations finding out.

**The agent read a file I did not want it to** -- `RALPH_MASK` stops the next
run, not the last one. Rotate the credential. `ralph status` prints what is
masked, and `mask off` when nothing is.

**A setting in `.ralph/config.env` is ignored** -- read the warning: either the
name is not one a project may set (the list is in
[configuration.md](configuration.md#settings-that-live-in-the-project)), or the
value contains shell metacharacters, which are refused rather than quoted. Set
it in `~/.config/ralph/config.env` or on the command line instead.

**Files written by the agent are root-owned (Linux hosts)** --
`ralph build --build-arg SANDBOX_UID=$(id -u) --build-arg SANDBOX_GID=$(id -g)`.
macOS does not have this problem.

**Agent version is behind your host** -- the image installs from npm, which can lag
other channels. `ralph update`.

