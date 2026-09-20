# ralph-sandbox

Run a coding agent in autonomous ("yolo") mode inside a locked-down container:
deny-by-default network egress, no host filesystem beyond one workspace, and no
access to your Docker daemon.

Agents are most useful when they aren't stopping to ask about every file write and
shell command. But `--dangerously-skip-permissions` means exactly what it says. On
your host, one bad command is your dotfiles, your SSH keys, or your other
repositories -- and an agent with open internet can send anything it reads
anywhere. `ralph` puts the agent somewhere it can only reach what you gave it.

It is a Dockerfile, a proxy config, and one shell script. No daemon, no service,
nothing to trust that you can't read in ten minutes.

## Relationship to Docker Sandboxes

Docker ships [Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`), which is
excellent and which you should prefer when it runs on your machine. `ralph` exists
for when it doesn't -- an unsupported platform, a restricted host, or wanting a
boundary you can inspect and change yourself.

Docker's model has five isolation layers. Here is honestly how far a plain
container gets:

| Docker Sandboxes | ralph | |
| --- | --- | --- |
| **Hypervisor** -- microVM, separate kernel | Shared kernel, unprivileged user, caps droppable | ⚠️ **Weaker** |
| **Network** -- TCP proxied, deny-by-default, no UDP/ICMP | Internal network + allowlist proxy; UDP/ICMP have no route | ✅ Equivalent |
| **Docker Engine** -- own daemon, isolated from host | Host socket never mounted; no docker CLI in the image | ✅ Equivalent |
| **Workspace** -- mountless / clone / direct | Same three modes, same semantics | ✅ Equivalent |
| **Credentials** -- injected by host proxy, never enter the VM | Live in the sandbox; the proxy does not intercept TLS | ⚠️ **Weaker** |

**The kernel is the real gap and it cannot be closed with containers.** A container
shares the host kernel, so a kernel exploit escapes it; a microVM does not. On
macOS and Windows, Docker Desktop already runs every container inside a Linux VM,
so there is a hypervisor between the sandbox and your laptop -- but it is shared
with your other containers, not per-sandbox.

`ralph` adds one thing Docker's direct mode doesn't have: **host-side snapshots**,
so even a total wipe of your working tree is recoverable (see below).

## Requirements

- Docker (Desktop, Colima, OrbStack, or plain Engine)
- `bash` (the macOS system bash 3.2 is fine)
- A Claude subscription or an `ANTHROPIC_API_KEY`

Builds natively on **arm64 and amd64**, Apple Silicon included, no emulation.

## Quick start

```bash
git clone https://github.com/jmanzo/ralph-sandbox.git
cd ralph-sandbox
./install.sh            # symlinks `ralph` into ~/.local/bin

cd ~/code/your-project
ralph                   # builds images on first use, then launches the agent
```

The first launch drops you into the agent unauthenticated. Type `/login` and
complete the flow. **You only do this once** -- credentials live in a Docker volume
that persists across runs, rebuilds, and projects.

Run `ralph status` at any time to see exactly what is in effect.

## Workspace modes

`RALPH_MODE` controls how much of your filesystem the agent can touch. The names
and semantics match Docker Sandboxes.

| Mode | Host workspace | Use when |
| --- | --- | --- |
| `direct` (default) | Bind-mounted read-write at `/workspace` | You want live edits in your editor |
| `clone` | Read-only at `/run/sandbox/source`; agent works in a private copy | You want to review before anything lands |
| `none` | Not mounted at all | Throwaway experiments, or work the agent creates from scratch |

```bash
RALPH_MODE=clone ralph      # agent can read your code, cannot change it
ralph diff                  # see what it changed in its copy
ralph apply                 # copy those changes onto the host (snapshots first)
```

In `clone` mode the host tree is genuinely read-only -- a write attempt fails with
`Read-only file system`.

## Network policy

Egress is **deny-by-default**. The sandbox sits on a Docker network created with
`--internal`, which has no route off the host. A small proxy container is attached
to both that network and a normal bridge, so it is the only way out, and it refuses
any destination not on the allowlist.

```bash
ralph policy ls                      # show the active allowlist
ralph policy edit                    # edit it, proxy restarts automatically
ralph policy test github.com         # check one host against the policy
ralph policy reset                   # back to shipped defaults
```

Because the block is at the *route* level rather than DNS, connecting to a raw IP
to bypass name resolution fails too, and UDP and ICMP have nowhere to go at all.

The shipped allowlist covers the agent API, npm, PyPI, GitHub, and Ubuntu package
mirrors. **Trim it to what your work actually needs** -- every entry is a place data
could go. Entries are extended regexes matched against the hostname; anchor them
with `^...$` so a rule for `github.com` can't be satisfied by
`github.com.attacker.example`.

To disable the policy entirely (the sandbox then has open internet):

```bash
RALPH_NETWORK_POLICY=off ralph
```

## Snapshots

`direct` mode is a live bind mount, so the agent can destroy your working tree --
including `rm -rf .git`, which takes unpushed history with it. Before every run,
`ralph` takes a host-side snapshot:

- a git commit on a hidden `refs/ralph/snapshots/*` ref capturing tracked **and**
  untracked files (respecting `.gitignore`, so `node_modules` is skipped)
- a `git bundle` written to `~/.local/share/ralph/snapshots/`, **outside the mount**,
  where the sandbox has no reach

It leaves your index and `git status` untouched, and is near-instant because
committed blobs already exist.

```bash
ralph snapshot ls
ralph snapshot restore            # most recent
ralph snapshot restore 20260919-183219
```

Restore rebuilds the repository if `.git` itself was deleted, puts branches back,
and leaves uncommitted work uncommitted. A wiped directory comes back with an
identical `git status`.

## Hardening

```bash
RALPH_HARDEN=on ralph
```

Drops all capabilities and sets `no-new-privileges`. Verified effect: `CapEff` is
all zeros and `sudo` stops working -- which also means the agent can no longer
install packages, so this suits a sandbox whose toolchain is already baked in.

Resource limits apply in every mode (`--pids-limit` defaults to 2048, which
contains fork bombs):

```bash
RALPH_MEMORY=8g RALPH_CPUS=4 ralph
```

## Commands

```
ralph [run] [args...]   Launch the agent over the current directory (default)
ralph shell             Open a shell in the sandbox
ralph status            Mode, network policy, images, volumes
ralph build / update    Build images / rebuild with the latest agent
ralph policy   <ls|edit|test HOST|reset>
ralph snapshot <ls|create|restore [ID]>
ralph diff / apply      Clone mode: review and land changes
ralph proxy    <up|down|logs|status>
ralph clean    <image|volume|workspace|proxy|all>
```

## Configuration

Environment variables, or `~/.config/ralph/config.env`:

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
| `RALPH_IMAGE` | `ralph-sandbox` | Image tag |
| `RALPH_HOME_VOLUME` | `ralph-home` | Volume holding the login |
| `RALPH_WORKSPACE` | `$PWD` | Directory to sandbox |
| `RALPH_MOUNT_GITCONFIG` | `1` | Mount `~/.gitconfig` read-only |
| `RALPH_MOUNT_SSH` | `0` | Mount `~/.ssh` read-only (see below) |
| `RALPH_DOCKER_ARGS` | -- | Extra `docker run` arguments |

### Using a different agent

`RALPH_AGENT_CMD` is just the command the container runs:

```sh
RALPH_AGENT_CMD="my-agent --auto"
```

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
| `UBUNTU_VERSION` | `24.04` |
| `NODE_MAJOR` | `22` |
| `EXTRA_APT_PACKAGES` / `EXTRA_NPM_PACKAGES` | -- |
| `CLAUDE_VERSION` | `latest` (pin for reproducible images) |
| `SANDBOX_UID` / `SANDBOX_GID` | `1000` (match your host user on Linux) |

If you add a package source, remember to allowlist its host.

## Known limits

Worth reading before you rely on this.

- **Shared kernel.** A kernel exploit escapes the container. This guards against an
  agent doing something destructive or careless, not against code actively
  attacking you.
- **Credentials live inside the sandbox.** Docker's proxy injects API keys so they
  never enter the VM. Doing that requires intercepting TLS, which `ralph`
  deliberately does not do, so the agent's token is in the home volume with it.
- **`direct` mode edits your real files.** That is the point of the mode; snapshots
  are the mitigation. Note that live edits can also trigger things outside the
  sandbox -- git hooks, IDE file watchers, `make` targets running on your host.
- **`sudo` is passwordless** unless `RALPH_HARDEN=on`. Container root is not host
  root, but the agent can undo guardrails *inside* the container. The boundary is
  the container, not anything within it.
- **`RALPH_MOUNT_SSH=1` hands the agent your keys.** Off by default. If you enable
  it so the agent can push, use a key scoped to that.
- **The allowlist is only as tight as you make it.** Anything reachable is a
  possible destination for your source code.

## Troubleshooting

**`Not logged in - Please run /login`** -- expected on first run.

**Something in the sandbox can't reach the internet** -- most likely the policy.
`ralph policy test <host>`, then `ralph policy edit` to allow it.

**`egress proxy is not accepting connections`** -- `ralph proxy logs` shows the
tinyproxy error. Note `FilterType` must be `ere`; `fqdn` is not supported by the
tinyproxy 1.11.x that Alpine ships.

**Login doesn't stick** -- the home volume was removed or renamed. `ralph status`.

**Files written by the agent are root-owned (Linux hosts)** --
`ralph build --build-arg SANDBOX_UID=$(id -u) --build-arg SANDBOX_GID=$(id -g)`.
macOS does not have this problem.

**Agent version is behind your host** -- the image installs from npm, which can lag
other channels. `ralph update`.

## Contributing

CI runs `shellcheck` and builds on amd64 and arm64. Keep the shell ASCII-only and
warning-free:

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  ralph install.sh yolo-run.sh entrypoint.sh
```

## License

MIT. See [LICENSE](LICENSE).
