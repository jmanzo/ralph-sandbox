# Security model

This page is the spec for the boundary: what it protects, from whom, and
where it stops. `SECURITY.md` at the repository root says how to report a
hole in it.

## What is being protected

- **The rest of your machine.** Dotfiles, SSH keys, other repositories, the
  Docker daemon, anything outside the one workspace you handed over.
- **Your source code and secrets, from leaving.** An agent with open internet
  can send anything it reads anywhere. Egress is the exfiltration channel.
- **Your working tree and git history**, in `direct` mode, from being
  destroyed beyond recovery.
- **Your money.** An unattended loop can spend all night achieving nothing.

## Who it is protecting against

- **A careless or confused agent.** The common case: `rm -rf` in the wrong
  directory, `git reset --hard` over uncommitted work, `curl`ing a file to a
  paste site because a tool result suggested it, installing a package that
  phones home.
- **Code the agent runs that is hostile to you.** A dependency it installed,
  a test fixture in a repo you asked it to work on, a prompt injection in a
  document it read. Whatever that code does, it does inside the container and
  through the proxy.

It is **not** protecting against:

- **A kernel exploit.** A container shares the host kernel. On macOS and
  Windows there is a shared Linux VM in between; on Linux there is nothing.
  If your threat model includes an attacker spending a kernel 0-day on your
  laptop, use a microVM ([Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)).
- **A compromised host.** If the machine running `ralph` is already hostile,
  none of this matters.
- **The agent vendor.** Transcripts go to Anthropic and OpenAI; that is the
  point of using their models.
- **You turning it off.** `RALPH_NETWORK_POLICY=off`, `RALPH_MOUNT_SSH=1`,
  and a widened allowlist are documented, deliberate, and yours.

## The layers

| Layer | Mechanism | Where it is tested |
| --- | --- | --- |
| Filesystem | One bind mount (`direct`), read-only source plus a private volume (`clone`), or nothing (`none`) | CI: "Clone mode keeps the host workspace read-only" |
| Network | `--internal` network with no route out; tinyproxy is the only path, deny-by-default, `CONNECT` to 443 only, and it serves the sandbox subnet only | CI: "Egress is blocked at the route level", "The proxy serves the sandbox network only", "A webhook is never reachable from inside the sandbox" |
| Docker | The socket is never mounted; no docker CLI in the image | CI: "Host Docker socket is never exposed" |
| Privilege | Unprivileged user (yolo mode refuses root); `RALPH_HARDEN=on` drops all capabilities and sets `no-new-privileges` | CI: "Yolo mode must refuse to run as root", "Hardened mode drops all capabilities" |
| Resources | `--pids-limit` (default 2048), optional memory and cpu limits | -- |
| Recovery | Host-side snapshot before every `direct` run: a hidden ref plus a bundle outside the mount | CI: "Snapshots survive deletion of the whole workspace" |
| Credentials | Logins live in a Docker volume; host API keys arrive through a mode-600 file, not `-e`; webhooks and bot tokens never enter at all | CI: "Slack, Discord and Telegram each get the end-of-run message" (posted from the host) |
| Spend | Stall, repeated-failure, three-strikes and spend-ceiling guardrails in `loop.sh` | CI: the `loop` job |
| Supply chain | Base images pinned by digest, agents by version, actions by SHA; no scripts piped into bash at build time; Dependabot moves the pins | -- |

The [README](../README.md) describes each of these from the user's side.

## Known limits

Worth reading before you rely on this. These are the things `ralph` does not
claim; a report that one of them is worse than described is still welcome.

- **Shared kernel.** A kernel exploit escapes the container. This guards against an
  agent doing something destructive or careless, not against code actively
  attacking you.
- **Credentials live inside the sandbox.** Docker's proxy injects API keys so they
  never enter the VM. Doing that requires intercepting TLS, which `ralph`
  deliberately does not do, so the agent's token is in the home volume with it.
  An `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` from the host goes in through a
  file mounted read-only rather than `docker run -e`, so at least it is not
  in the container config for `docker inspect` to print.
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
- **An unattended loop is still an unattended loop.** The budget, the stall
  detector, the three-strikes rule and the sandbox bound what it can cost and
  reach; they cannot make it right. Read the diff before you ship it.
- **The three-strikes rule trusts the orchestrator's signature.** A model that
  rephrases the same failure each time defeats the check, which is why the
  prompt is emphatic about copying it verbatim. The iteration budget is the
  backstop that does not depend on the model behaving.
- **Codex marks its own homework.** The four-role split on the Anthropic side
  gives QA no edit tools, so it cannot fix what it finds. The codex side is one
  session playing every part, because Codex has no per-role subagent
  definitions to hang the split on. The prompt leans on it; nothing enforces it.
  If unattended correctness matters more than finishing, set
  `RALPH_FALLBACK=off` and let a wall halt the run.
- **The usage-limit check is a string match.** It fires only on an iteration
  that also failed, and its patterns are Claude Code's current wording. If that
  wording changes, a limit degrades into the ordinary repeated-failure path --
  slower to hand over, but not wrong. `RALPH_LIMIT_PATTERN` overrides it.
- **Two providers means two bills.** A spend ceiling only counts Anthropic
  spend, because codex on a ChatGPT login reports tokens and no price. An
  uncapped run that hands over is bounded by the guardrails, not by dollars.

## Reporting

Privately, through GitHub's vulnerability reporting form. `SECURITY.md` has
the details and the scope.
