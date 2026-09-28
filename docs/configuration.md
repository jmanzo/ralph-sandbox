# Configuration

Every setting is an environment variable, and every one can live in
`~/.config/ralph/config.env` instead, which `ralph` sources first. `ralph
status` shows what is in effect. The loop's own variables are explained in
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

## Customizing the image

```bash
ralph build \
  --build-arg EXTRA_APT_PACKAGES="golang-go postgresql-client" \
  --build-arg EXTRA_NPM_PACKAGES="pnpm typescript"
```

| Build arg | Default |
| --- | --- |
| `NODE_MAJOR` | `22` |
| `EXTRA_APT_PACKAGES` / `EXTRA_NPM_PACKAGES` | -- |
| `CLAUDE_VERSION` / `CODEX_VERSION` | pinned in the `Dockerfile`; `ralph update` builds with `latest` |
| `SANDBOX_UID` / `SANDBOX_GID` | `1000` (match your host user on Linux) |

If you add a package source, remember to allowlist its host.

