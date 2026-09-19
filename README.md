# ralph-sandbox

Run a coding agent in autonomous ("yolo") mode inside a disposable container, so
that skipping permission prompts can't reach your machine.

Agents are most useful when they aren't stopping to ask about every file write and
shell command. But `--dangerously-skip-permissions` means exactly what it says: on
your host, one bad command is your dotfiles, your SSH keys, or your other
repositories. `ralph` puts the agent in a container that holds nothing but a
toolchain and the one project you pointed it at.

It is deliberately small and unopinionated: a Dockerfile you can read in a minute,
and one shell script. No daemon, no config format to learn, nothing to trust
beyond Docker.

## Requirements

- Docker (Desktop, Colima, OrbStack, or plain Engine)
- `bash` (the macOS system bash 3.2 is fine)
- An agent account: a Claude subscription or an `ANTHROPIC_API_KEY`

Builds natively on **arm64 and amd64** -- Apple Silicon included, no emulation.
CI builds and smoke-tests both.

## Quick start

```bash
git clone https://github.com/jmanzo/ralph-sandbox.git
cd ralph-sandbox
./install.sh            # symlinks `ralph` into ~/.local/bin

cd ~/code/your-project
ralph                   # builds the image on first use, then launches the agent
```

The first launch drops you into the agent unauthenticated. Type `/login` and
complete the flow. **You only do this once** -- the credentials live in a Docker
volume that persists across runs, rebuilds, and projects.

The directory you run `ralph` from is mounted at `/workspace`. Nothing else on
your machine is visible to the agent.

## Usage

```bash
ralph                          # agent over the current directory
ralph -p "fix the failing test"   # arguments pass straight through to the agent
ralph shell                    # a shell in the sandbox instead
ralph status                   # image, volume, and config state
ralph build                    # build the image
ralph update                   # rebuild from scratch with the latest agent
ralph clean volume             # forget the login
ralph clean all                # remove image and volume
ralph help
```

`yolo-run.sh` is kept as a thin alias for `ralph run`.

## Why not the built-in sandbox?

Most agents ship their own sandboxing -- `sandbox-exec` on macOS, `bubblewrap` or
seccomp on Linux. When those work, use them; they're lighter than a container.

This exists for when they don't: an unsupported architecture or kernel, a host
where the required syscalls are unavailable, a corporate machine where the profile
won't load, or simply wanting an isolation boundary you can inspect and modify
yourself. A container is a blunter tool, but it's the same boundary everywhere.

## Configuration

Set these as environment variables, or put them in `~/.config/ralph/config.env`:

| Variable | Default | What it does |
| --- | --- | --- |
| `RALPH_IMAGE` | `ralph-sandbox` | Image tag to build and run |
| `RALPH_HOME_VOLUME` | `ralph-home` | Volume holding the sandbox's login and caches |
| `RALPH_WORKSPACE` | `$PWD` | Directory mounted at `/workspace` |
| `RALPH_AGENT_CMD` | `claude --dangerously-skip-permissions` | Command run inside the container |
| `RALPH_NETWORK` | `bridge` | Docker network |
| `RALPH_MOUNT_GITCONFIG` | `1` | Mount `~/.gitconfig` read-only, so sandbox commits are attributed to you |
| `RALPH_MOUNT_SSH` | `0` | Mount `~/.ssh` read-only (read the security notes first) |
| `RALPH_DOCKER_ARGS` | -- | Extra arguments for `docker run` |

Example `~/.config/ralph/config.env`:

```sh
RALPH_MOUNT_SSH=1
RALPH_DOCKER_ARGS="--memory=8g --cpus=4"
```

### Using a different agent

`RALPH_AGENT_CMD` is just the command the container runs, so any CLI agent you add
to the image works:

```sh
RALPH_AGENT_CMD="my-agent --auto"
```

### Per-project isolation

By default every project shares one login volume. To give a project its own
throwaway home -- useful for a different account, or for a repo you want fully
quarantined:

```sh
RALPH_HOME_VOLUME=ralph-home-clientwork ralph
```

## Customizing the image

The Dockerfile takes build arguments, so you can add your stack without forking it:

```bash
ralph build \
  --build-arg EXTRA_APT_PACKAGES="golang-go postgresql-client" \
  --build-arg EXTRA_NPM_PACKAGES="pnpm typescript" \
  --build-arg NODE_MAJOR=22
```

| Build arg | Default | Purpose |
| --- | --- | --- |
| `UBUNTU_VERSION` | `24.04` | Base image tag |
| `NODE_MAJOR` | `22` | Node.js major version |
| `EXTRA_APT_PACKAGES` | -- | Additional apt packages |
| `EXTRA_NPM_PACKAGES` | -- | Additional global npm packages |
| `CLAUDE_VERSION` | `latest` | Pin the agent for reproducible images |
| `SANDBOX_UID` / `SANDBOX_GID` | `1000` | Match your host user on Linux |

For anything larger, use this image as a base:

```dockerfile
FROM ralph-sandbox
USER root
RUN apt-get update && apt-get install -y your-toolchain
USER sandboxuser
```

Then `RALPH_IMAGE=my-sandbox ralph`.

## What this protects, and what it doesn't

Being precise about the boundary matters more than the feature list.

**Protected.** Your home directory, SSH keys, credentials, other repositories, and
the host OS. The agent runs as an unprivileged user in a container that can see
one directory.

**Not protected -- your working tree.** `/workspace` is a live bind mount, so the
agent edits your real files. That is the point. Commit before long autonomous runs;
git is your undo.

**Not protected -- the network.** The agent needs to reach the API, so egress is
open by default. Anything it can read in `/workspace` it can send somewhere. Set
`RALPH_NETWORK` if you have a locked-down network to attach to.

**`sudo` inside the container is passwordless.** The agent will want to install
packages, and container root is not host root. But it does mean the agent can undo
any guardrail you set *inside* the container. The boundary you're relying on is the
container itself, not anything within it.

**`RALPH_MOUNT_SSH=1` hands the agent your keys.** It is off by default for that
reason. If you turn it on so the agent can push, use a key scoped to that purpose.

**A container is not a VM.** A kernel exploit escapes it. This is a guard against
an agent doing something destructive, not against hostile code that is actively
targeting you.

Two things are worth knowing about how the pieces fit:

- **Agents refuse yolo mode as root.** `--dangerously-skip-permissions` exits
  immediately with root privileges, which is why the image creates `sandboxuser`.
  Running the container as root will not work, by design.
- **The login lives in the container, not on your host.** On macOS the agent stores
  subscription credentials in the Keychain, which cannot be mounted into a Linux
  container. That's why you log in once *inside* the sandbox and the home volume
  keeps it.

## Troubleshooting

**`Not logged in - Please run /login`** -- expected on first run. Type `/login`.

**Login doesn't stick between runs** -- the home volume was removed or renamed.
Check `ralph status`.

**Files written by the agent are root-owned (Linux hosts)** -- rebuild with your
own ids: `ralph build --build-arg SANDBOX_UID=$(id -u) --build-arg SANDBOX_GID=$(id -g)`.
macOS does not have this problem; Docker Desktop virtualizes ownership.

**Agent version is behind your host** -- the image installs from npm, which can lag
other release channels. `ralph update` rebuilds against the latest.

**`docker: command not found`** -- start Docker Desktop, or whichever runtime you use.

## Contributing

Issues and pull requests welcome. CI runs `shellcheck` on the scripts and builds
the image on amd64 and arm64, so please keep the shell ASCII-only and warning-free:

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable ralph install.sh yolo-run.sh
```

## License

MIT. See [LICENSE](LICENSE).
