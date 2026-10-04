# Configuration

Every setting is an environment variable, and every one can live in
`~/.config/ralph/config.env` instead, which `ralph` sources first. A project
can also carry a few of them itself, in `.ralph/config.env` -- see [settings
that live in the project](#settings-that-live-in-the-project). `ralph status`
shows what is in effect. The loop's own variables are explained in
[loop.md](loop.md); the boundary they apply to is in [security.md](security.md).

| Variable | Default | What it does |
| --- | --- | --- |
| `RALPH_MODE` | `direct` | `direct`, `clone`, or `none` |
| `RALPH_NETWORK_POLICY` | `on` | Deny-by-default egress |
| `RALPH_ALLOWLIST` | `~/.config/ralph/allowlist` | Policy file |
| `RALPH_SNAPSHOT` | `on` | Snapshot before each run |
| `RALPH_SNAPSHOT_KEEP` | `10` | Snapshots retained per workspace |
| `RALPH_HARDEN` | `off` | Drop caps, no-new-privileges (breaks `sudo`) |
| `RALPH_MEMORY` / `RALPH_CPUS` | -- | Resource limits |
| `RALPH_PIDS_LIMIT` | `2048` | Process cap |
| `RALPH_AGENT_CMD` | `claude --dangerously-skip-permissions` | Command run inside |
| `RALPH_LOOP_MAX` | `0` | Iteration cap; `0` means run until the PRD is done |
| `RALPH_LOOP_MAX_COST` | -- | Stop once a run has spent this much (USD) |
| `RALPH_LOOP_STALL` | `3` | Stop after this many iterations that change nothing |
| `RALPH_LOOP_FAILS` | `2` | Stop after this many consecutive agent failures |
| `RALPH_LOOP_SLEEP` | `0` | Seconds to pause between iterations |
| `RALPH_LOOP_REPEAT` | `3` | Halt after this many repeats of one failure |
| `RALPH_MODEL_ORCHESTRATOR` | `haiku` | Model behind the orchestrator |
| `RALPH_PROVIDER` | `anthropic` | Who drives the loop: `anthropic` or `codex` |
| `RALPH_FALLBACK` | `codex` | Who catches it, or `off` for single-provider runs |
| `RALPH_CODEX_MODEL` | `gpt-5.6-sol` | One model for all four roles on the codex side |
| `RALPH_CODEX_EFFORT` | `high` | `low`, `medium`, `high`, `xhigh`, `max` |
| `RALPH_LIMIT_PATTERN` | see `loop.sh` | What a spent usage limit looks like in a transcript |
| `RALPH_SLACK_WEBHOOK` | -- | Slack incoming webhook |
| `RALPH_DISCORD_WEBHOOK` | -- | Discord webhook |
| `RALPH_TELEGRAM_TOKEN` / `_CHAT` | -- | Telegram bot token and chat id |
| `RALPH_NOTIFY_ON` | `always` | `always`, or `problem` for bad endings only |
| `RALPH_IMAGE` | `ralph-sandbox` | Image tag |
| `RALPH_HOME_VOLUME` | `ralph-home` | Volume holding both providers' logins |
| `RALPH_WORKSPACE` | `$PWD` | Directory to sandbox |
| `RALPH_MOUNT_GITCONFIG` | `1` | Mount `~/.gitconfig` read-only |
| `RALPH_MOUNT_SSH` | `0` | Mount `~/.ssh` read-only (see below) |
| `RALPH_ISOLATE` | -- | Dependency dirs the sandbox keeps its own copy of |
| `RALPH_MASK` | -- | Workspace files that read empty inside the sandbox |
| `RALPH_BUILD_ARGS` | -- | `docker build` args kept across `build` and `update` |
| `RALPH_DOCKER_ARGS` | -- | Extra `docker run` arguments |

### Using a different agent

`RALPH_AGENT_CMD` is just the command the container runs:

```sh
RALPH_AGENT_CMD="my-agent --auto"
```

Setting it explicitly wins over `--provider`: choosing a provider must not
silently discard a command you asked for by name. `RALPH_CODEX_CMD` (default
`codex exec`) is the same knob for the codex side of the loop, and is what the
test suite substitutes to exercise the handover without spending anything.

### Per-project isolation

Every project shares one login volume by default. To fully quarantine one:

```sh
RALPH_HOME_VOLUME=ralph-home-clientwork ralph
```

### Keeping host and sandbox dependencies apart

In `direct` mode the sandbox edits your live tree, and the sandbox is Linux
whether or not your machine is. A directory of compiled dependencies is then
shared by two platforms that cannot run each other's binaries: install inside
the sandbox and the host's `node_modules` stops working; don't, and nothing
runs inside the sandbox.

`RALPH_ISOLATE` gives each listed directory a Docker volume of its own, so
both sides keep theirs:

```sh
RALPH_ISOLATE="node_modules packages/*/node_modules"
```

Paths are workspace-relative and space-separated; globs are expanded against
the workspace, so one line covers a monorepo. The volumes are named after the
workspace, created on first use and chowned to the sandbox user -- a fresh
Docker volume belongs to root, and without that step the project's first
install fails with "permission denied". `ralph clean workspace` removes them,
which is the fix when a project changes package manager.

Two things worth knowing: the sandbox starts with the directory *empty*, so
the first iteration has to install; and if the directory does not exist on the
host, Docker creates an empty one there. In `clone` and `none` modes the
setting does nothing, because the workspace is already the sandbox's own.

### Hiding files from the agent

A `.env` in a `direct`-mode workspace is readable by the agent, and
`github.com` is on the default allowlist, so there is somewhere it could go.
If the project's tests mock the services those credentials belong to -- and
they usually do -- the agent does not need them:

```sh
RALPH_MASK=".env .env.local"
```

Each listed file is mounted over with an empty, read-only file. It reads as
nothing inside the sandbox, writes to it fail, and the host keeps its own copy
untouched. Globs are expanded against the workspace, so `.env.*` covers a file
you forgot -- though it also covers `.env.example`, which the agent may
legitimately want to read, so listing names is usually better. A name that is
not in the workspace is skipped: there is nothing to hide, and mounting over
it would make Docker create it, leaving an empty `.env.local` in a project
that never had one. In `clone` mode both the read-only source and the private
copy are masked. `ralph status` prints what is masked, which is the list after
globs and missing files, so it is also how you check a pattern matched what
you meant.

This closes one hole rather than drawing a boundary: the same secret may be in
the git history, in the process environment, or reachable with a mounted
`~/.ssh`. See [security.md](security.md).

### Settings that live in the project

Some settings belong to the repository rather than to the machine: which
dependency directories the sandbox keeps its own copy of, which files the
agent must not read, what the image needs installed to build the project at
all. Put those in `.ralph/config.env` in the project and commit it, and every
checkout on every machine runs the same way:

```sh
# myapp/.ralph/config.env
RALPH_ISOLATE="node_modules"
RALPH_MASK=".env"
RALPH_BUILD_ARGS="--build-arg EXTRA_NPM_PACKAGES=pnpm"
```

Precedence is what you would expect: a value typed on the command line beats
the project file, which beats `~/.config/ralph/config.env`, which beats the
built-in default.

**A project may only set these:**

`RALPH_ISOLATE`, `RALPH_MASK`, `RALPH_BUILD_ARGS`, `RALPH_LOOP_MAX`,
`RALPH_LOOP_SLEEP`, `RALPH_LOOP_STALL`, `RALPH_LOOP_FAILS`,
`RALPH_LOOP_REPEAT`, `RALPH_FALLBACK`, `RALPH_MODEL_ORCHESTRATOR`,
`RALPH_CODEX_MODEL`, `RALPH_CODEX_EFFORT`.

Anything else in the file is named in a warning and ignored. The egress
policy, the workspace mode, the image, `RALPH_DOCKER_ARGS`, the spend ceiling
and what of your home directory gets mounted are absent on purpose: cloning a
repository and running `ralph` in it must not be a way to loosen the sandbox,
or to spend your money. For the same reason the file is parsed rather than
sourced, and a value containing shell metacharacters is refused instead of
quoted and hoped about.

In `direct` mode `ralph` mounts the file back over itself read-only, so the
agent cannot change the settings its next run will start with.

## Customizing the image

```bash
ralph build \
  --build-arg EXTRA_APT_PACKAGES="golang-go postgresql-client" \
  --build-arg EXTRA_NPM_PACKAGES="pnpm typescript"
```

`ralph update` rebuilds from scratch and does not remember what you typed last
time, so a toolchain added on the command line disappears at the next update.
Put it in `RALPH_BUILD_ARGS` instead -- in `~/.config/ralph/config.env`, or in
the project's own `.ralph/config.env` -- and both `build` and `update` apply
it:

```sh
RALPH_BUILD_ARGS="--build-arg EXTRA_NPM_PACKAGES=pnpm"
```

A `--build-arg` typed on the command line still wins over a remembered one.
The image is shared by every project, so what one project adds is simply
present for the others.

| Build arg | Default |
| --- | --- |
| `NODE_MAJOR` | `22` |
| `EXTRA_APT_PACKAGES` / `EXTRA_NPM_PACKAGES` | -- |
| `CLAUDE_VERSION` / `CODEX_VERSION` | pinned in the `Dockerfile`; `ralph update` builds with `latest` |
| `SANDBOX_UID` / `SANDBOX_GID` | `1000` (match your host user on Linux) |

If you add a package source, remember to allowlist its host.

