# ralph-sandbox

[![ci](https://github.com/jmanzo/ralph-sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/jmanzo/ralph-sandbox/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Run a coding agent in autonomous ("yolo") mode inside a locked-down container:
deny-by-default network egress, no host filesystem beyond one workspace, and no
access to your Docker daemon.

Agents are most useful when they aren't stopping to ask about every file write and
shell command. But `--dangerously-skip-permissions` means exactly what it says. On
your host, one bad command is your dotfiles, your SSH keys, or your other
repositories -- and an agent with open internet can send anything it reads
anywhere. `ralph` puts the agent somewhere it can only reach what you gave it.

It is a Dockerfile, a proxy config, and two shell scripts. No daemon, no service,
nothing to trust that you can't read in ten minutes.

**Status: early, and used daily.** There is no tagged release yet; `ralph
version` tells you which commit you are on. CI builds and tests the boundary
on Linux amd64 and arm64. macOS on Apple Silicon with Docker Desktop
is where it is developed and run; Windows and WSL are untested. Pinned agent
versions are in the `Dockerfile`; `ralph update` fetches newer ones. Read
[docs/security.md](docs/security.md) before you rely on it.

On top of that boundary it runs [Ralph](https://www.aihero.dev/getting-started-with-ralph):
the same prompt, at the same agent, over and over, one task per iteration, until
a PRD you wrote is satisfied. `ralph loop` is the part you leave running; the
sandbox is what makes leaving it running reasonable.

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
- Optional, for the OpenAI fallback: a ChatGPT plan that includes Codex, or an
  `OPENAI_API_KEY`

Builds natively on **arm64 and amd64**, Apple Silicon included, no emulation.

## Quick start

```bash
git clone https://github.com/jmanzo/ralph-sandbox.git
cd ralph-sandbox
./install.sh            # symlinks `ralph` into ~/.local/bin

cd ~/code/your-project
ralph login anthropic   # builds images on first use, then: type /login
ralph                   # launch the agent
```

`ralph login anthropic` drops you into the agent unauthenticated; type `/login`
and complete the flow. **You only do this once** -- credentials live in a Docker
volume that persists across runs, rebuilds, and projects.

If you want the OpenAI fallback to be able to take over, sign that in too:

```bash
ralph login codex       # device code; open the URL it prints, anywhere
ralph login status      # what the sandbox is currently signed in to
```

The device-code flow is deliberate. The ordinary OAuth flow wants to bind a
localhost callback *inside* the container, which no browser on your machine can
reach. With `OPENAI_API_KEY` set on the host, `ralph login codex` uses that
instead and asks you nothing.

Run `ralph status` at any time to see exactly what is in effect.

## The loop

```bash
cd ~/code/your-project
ralph init            # scaffold the PRD, the prompt, the state files, the subagents
$EDITOR PRD.md        # the only file you have to write by hand
ralph loop            # until the PRD is done, unattended
```

There is no iteration count to pick. The run ends when the PRD is satisfied, or
when one of the guardrails decides it is not going to be. `ralph loop 10`
still caps it, for when you want to sample the behaviour rather than finish.

Every iteration is a *fresh* agent session that remembers nothing. The top-level
session is the orchestrator; it delegates to three subagents, each with its own
context window:

```
                    orchestrator              plans, picks ONE task,
                         |                    commits, writes the log
           +-------------+-------------+
           v             v             v
       architect     developer         qa      separate sessions,
       designs and   writes the        runs the verification,
       orders the    code and the      reports failures
       plan          tests             precisely
```

Between iterations the only things that survive are the git history and
`.ralph/progress.md`. That's the whole discipline: context an agent didn't write
down is context the next iteration doesn't have.

[docs/loop.md](docs/loop.md) has the rest: what `ralph init` lays down, the
`PROPOSALS.md` file for what the loop noticed but did not build, which model
each role runs on and how to change it, the one-way handover to Codex when
Anthropic runs out of road, the three-strikes rule, notifications, the exit
codes, and reviewing a run in `clone` mode before anything lands.

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
ralph policy sync                    # add shipped rules yours is missing
ralph policy reset                   # back to shipped defaults
```

Your allowlist is seeded once and then belongs to you, so shipping a new default
does not reach an existing install. That is usually what you want, and exactly
wrong for a host a new feature needs -- which is what `ralph policy sync` is
for: it appends what is missing and touches nothing already there.

Because the block is at the *route* level rather than DNS, connecting to a raw IP
to bypass name resolution fails too, and UDP and ICMP have nowhere to go at all.

The shipped allowlist covers both agents' APIs and logins, npm, PyPI, GitHub,
and Ubuntu package mirrors. **Trim it to what your work actually needs** -- every entry is a place data
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
ralph login [provider]  Sign the sandbox in to anthropic or codex, or `status`
ralph init [--force]    Scaffold the loop: PRD, prompts, state, subagents
ralph loop [N]          Run until the PRD is done (N caps the iterations)
ralph model [role model]  Show, or change, the model behind each role
ralph shell             Open a shell in the sandbox
ralph status            Provider, logins, mode, network policy, images, volumes
ralph build / update    Build images / rebuild with the latest agents
ralph version           Release number and, from a checkout, the commit
ralph policy   <ls|edit|sync|test HOST|reset>
ralph snapshot <ls|create|restore [ID]>
ralph diff / apply      Clone mode: review and land changes
ralph proxy    <up|down|logs|status>
ralph clean    <image|volume|workspace|proxy|all>
```

## Known limits

Worth reading before you rely on this. The two that matter most:

- **Shared kernel.** A kernel exploit escapes the container. This guards against an
  agent doing something destructive or careless, not against code actively
  attacking you.
- **Credentials live inside the sandbox.** The agent's token is in the home
  volume with it; `ralph` does not intercept TLS to inject it.

The full list, and the threat model they follow from, is in
[docs/security.md](docs/security.md).

## Documentation

| | |
| --- | --- |
| [docs/loop.md](docs/loop.md) | The loop: roles and models, proposals, the Codex handover, guardrails, notifications, exit codes |
| [docs/configuration.md](docs/configuration.md) | Every `RALPH_*` variable, using a different agent, per-project isolation, customizing the image |
| [docs/security.md](docs/security.md) | The threat model, the layers, and the known limits |
| [docs/troubleshooting.md](docs/troubleshooting.md) | What the common failures look like and what fixes them |
| [SECURITY.md](SECURITY.md) | How to report a hole in the boundary |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Checks, shell rules, commit convention |
| [CHANGELOG.md](CHANGELOG.md) | What changed |

## Contributing

Issues are the roadmap; read [CONTRIBUTING.md](CONTRIBUTING.md) before a PR.
CI runs `shellcheck`, an ASCII-only check, the loop scenarios, and builds and
tests the images on amd64 and arm64. Anything that changes what the sandbox
can reach needs an issue first.

## License

MIT. See [LICENSE](LICENSE).
