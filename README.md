# ralph-sandbox

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
when one of the guardrails below decides it is not going to be. `ralph loop 10`
still caps it, for when you want to sample the behaviour rather than finish.

### What `ralph init` lays down

```
PRD.md                       what you're building, and how a machine can tell it's done
PROPOSALS.md                 ideas the loop found but didn't build -- yours to promote
CLAUDE.md                    conventions, plus the rules every agent in the loop follows
AGENTS.md                    points Codex at CLAUDE.md, and says what differs when it drives
.ralph/PROMPT.md             the orchestrator's prompt, run fresh every iteration
.ralph/PROMPT.codex.md       the same iteration, for one agent playing all four roles
.ralph/plan.md               the architect's ordered task list
.ralph/progress.md           append-only log -- the loop's memory between iterations
.claude/agents/architect.md
.claude/agents/developer.md
.claude/agents/qa.md
```

It never overwrites a file you already have. `ralph init --force` does.

### The shape of an iteration

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

The division of labour is enforced by tooling, not just by prompt. The architect
may write only `.ralph/plan.md`, so design pressure can't be resolved by quietly
patching something. QA has no edit tools at all, so it can't fix what it was
supposed to report -- finding and fixing in one pass is how a loop convinces
itself it succeeded. And Claude Code subagents can't spawn subagents, so the tree
is exactly this deep: no runaway fan-out while you're asleep.

Between iterations the only things that survive are the git history and
`.ralph/progress.md`. That's the whole discipline: context an agent didn't write
down is context the next iteration doesn't have.

That shape is Anthropic's. When codex takes the loop it collapses into one
session walking the same four roles in sequence -- see
[When OpenAI takes over](#when-openai-takes-over).

### What it noticed but didn't build

An agent held to one task will keep seeing things it was not asked to do. Left
unmanaged those become scope creep; suppressed entirely, they are simply lost.
They go to `PROPOSALS.md` instead.

The developer and QA report what they saw; the orchestrator files it with the
observation that prompted it, its rough size, and what it costs to keep
ignoring it. Nothing there is implemented, and the loop never promotes anything
into `PRD.md` -- that move is yours:

```bash
ralph loop                      # ... runs, finishes, or stops
$EDITOR PROPOSALS.md            # read the shortlist
# move what you want into PRD.md, delete it from PROPOSALS.md, run again
```

Two details that matter for an uncapped run. A proposal has to cite something
that actually happened, not a best practice -- otherwise the file fills with
boilerplate every night. And there is an *Already considered* section: ideas you
declined go there, and the loop stops raising them.

When a run finishes the PRD, the orchestrator's last act is to tidy the file --
merge duplicates, drop what the finished work made moot, order by value. It is
the one artefact of the run a human reads end to end, so it should read like a
shortlist rather than a log.

### Who runs on what

Spending is concentrated where the reasoning happens, not where the routing
does:

| Role | Model | Set in |
| --- | --- | --- |
| Orchestrator | `haiku` | `RALPH_MODEL_ORCHESTRATOR` |
| Architect | `sonnet` | `.claude/agents/architect.md` |
| Developer | `opus` | `.claude/agents/developer.md` |
| QA | `sonnet` | `.claude/agents/qa.md` |

```bash
ralph model                      # what each role is running on right now
ralph model developer sonnet     # start an MVP cheap
ralph model developer opus       # escalate when the logic gets intricate
```

**Degrading deliberately.** For an MVP, run the developer on `sonnet` too and
leave it there while the work is CRUD-shaped. Escalate to `opus` on evidence --
intricate domain logic, a third-party integration failing in new ways each time,
or the same signature coming back from QA more than once. Escalate the
*developer* first: it is rarely the architect that is underpowered.

One caveat worth knowing before you leave it running: the orchestrator is the
role that decides the PRD is done and emits the completion sigil. On `haiku`
that is the cheapest seat in the tree and also the one whose misjudgement is
least recoverable. If a run ends suspiciously early, raise that one first.

### When OpenAI takes over

Anthropic drives the loop by default. Codex catches it when Anthropic runs out
of road, and the handover is **one-way** -- nothing hands it back.

| Trigger | What happens |
| --- | --- |
| Anthropic reports a usage limit | Hand over on the **first** failed iteration, not after `RALPH_LOOP_FAILS` |
| The agent process fails `RALPH_LOOP_FAILS` times running | Hand over instead of exiting `1` |
| The same failure survives `RALPH_LOOP_REPEAT` iterations | Hand the bug to codex for a fresh theory instead of exiting `4` |
| `ralph loop --provider codex` | Start there; nothing catches it |

The incoming provider gets **its own three attempts, and no more**. Once codex
holds the loop, a limit, repeated failure or three strikes stops the run for
real. Without that the budget would be meaningless, because each side would
keep granting the other a fresh three.

The limit check only fires on an iteration that *also* failed. An agent merely
writing the words "usage limit reached" into its transcript does not hand your
run to another provider.

```bash
ralph loop                        # anthropic, falling back to codex
ralph loop --provider codex       # codex from the start
RALPH_FALLBACK=off ralph loop     # no handover; a wall halts the run
```

**Codex runs one session, not four.** Codex has no per-role subagent
definitions -- the subagents it spawns all share a single
`default_subagent_model` -- so there is no per-role dial to set. Instead
`.ralph/PROMPT.codex.md` walks one agent through all four roles in sequence,
and `ralph model` shows codex as a single row:

```
orchestrator   haiku       (RALPH_MODEL_ORCHESTRATOR)
architect      sonnet      .claude/agents/architect.md
developer      opus        .claude/agents/developer.md
qa             sonnet      .claude/agents/qa.md
codex          gpt-5.6-sol (RALPH_CODEX_MODEL, high effort -- all four roles)
```

One model has to cover the architect's and the developer's work, so the default
is the seat those demand rather than the cheap routing seat:

| `RALPH_CODEX_MODEL` | When |
| --- | --- |
| `gpt-6-astra` | The developer work is genuinely hard and you want the ceiling |
| `gpt-5.6-sol` | **Default.** The seat the architect and developer work demands |
| `gpt-5.6-terra` | A cheaper fallback, for CRUD-shaped work |
| `gpt-5.6-luna` | Cheapest; expect to babysit it |

`RALPH_CODEX_EFFORT` is the second dial (`low`, `medium`, `high`, `xhigh`,
`max`) and matters as much as the model. It defaults to `high`; escalate to
`xhigh` before reaching for a bigger model.

Because one agent both writes the code and verifies it, the codex prompt leans
hard on the QA step -- run the PRD's commands, read the diff as if someone else
wrote it. It is the weakest point of the single-session shape, and it is where
`.ralph/PROMPT.codex.md` spends its words.

**Two things do not carry over.** Codex on a ChatGPT login reports tokens, not
dollars, so `RALPH_LOOP_MAX_COST` can only police the Anthropic half of a run
-- the loop says so when it hands over. And the shipped egress policy gained
OpenAI hosts, which an allowlist seeded before this feature will not have:

```bash
ralph policy sync      # adds what is missing, keeps your own rules
```

`ralph loop` warns when the fallback is enabled and the policy cannot reach
OpenAI, rather than letting you find out during a 3am handover.

### Three strikes on the same failure

Two agents trading one bug back and forth is the most expensive way for an
unattended loop to achieve nothing. So the same failure gets **three attempts
per provider** -- not three per iteration. A handover gives Codex three tries
at a different theory; once those are spent, the run stops:

- The **developer** is told how many attempts are left, and that attempt 3 is
  the last that provider pays for.
- **QA** reports whether a failure is the same one as last time, and whether the
  last attempt changed the output at all.
- The **orchestrator**, on giving up, ends its turn with a failure signature:
  `<blocked>npm test -- auth.spec.ts: expected 401, received 500</blocked>`.

The loop compares those signatures literally. Three identical ones running
hands Anthropic's wall to Codex, or halts with exit `4` when Codex owns the
loop. A genuinely different failure resets the count.

### Notifications

Set any of these -- each one that is set gets a copy:

```bash
export RALPH_SLACK_WEBHOOK=https://hooks.slack.com/services/...
export RALPH_DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
export RALPH_TELEGRAM_TOKEN=123456:ABC...   # and the chat to send to
export RALPH_TELEGRAM_CHAT=-1001234567890

ralph loop
```

One message per run, not per iteration: how it ended, how many iterations it
took, what it cost, and what it was stuck on. `RALPH_NOTIFY_ON=problem` sends
only when a run ends badly; the default `always` also tells you when the PRD is
finished, which is the message you actually want overnight.

**They are posted by the host, after the container exits.** The sandbox writes
`.ralph/alert.txt` and nothing more. So no webhook URL and no bot token ever
enters the sandbox, and none of these services go on the egress allowlist -- an
allowlisted webhook is an exfiltration channel, and this buys the alerting
without opening one.

### When the loop stops

| Exit | Why |
| --- | --- |
| `0` | The agent emitted `<promise>COMPLETE</promise>` -- the PRD is done |
| `1` | The agent process itself failed twice running (`RALPH_LOOP_FAILS`) |
| `2` | Three iterations running changed nothing (`RALPH_LOOP_STALL`) |
| `3` | An explicit iteration cap ran out (only if you passed one) |
| `4` | The same failure came back three iterations running (`RALPH_LOOP_REPEAT`) |
| `5` | Spending passed `RALPH_LOOP_MAX_COST` |

`1` and `4` hand the loop to codex first, if a fallback is available and has not
already been used. They stop the run only once no provider is left.

Uncapped does not mean unbounded: `2`, `4` and `5` are what actually stop a run
that is not going to finish. If you want a hard ceiling in dollars rather than
iterations, that is `RALPH_LOOP_MAX_COST=25`.

The stall detector is the one that saves money. Each round it fingerprints
`HEAD`, the working-tree diff and `progress.md`; a loop that is narrating rather
than working gets stopped instead of billing you for another seven turns of it.
The completion sigil is only honoured in the agent's *final* message, so an
iteration that merely quotes its own instructions doesn't end the run.

Full JSONL transcripts land in `.ralph/logs/`, one per iteration, with the cost
of each, plus a `.last.txt` holding the final message the guardrails actually
read. `.ralph/alert.json` records which provider finished the run, which one
started it, and what caused any handover. The whole run is one container and **one** snapshot, not one per
iteration.

### Reviewing before anything lands

```bash
RALPH_MODE=clone ralph loop      # the loop works on a private copy
ralph diff                       # read everything it did
ralph apply                      # land it, snapshotting first
```

Run `ralph init` before the first clone-mode launch. The private copy is seeded
from your workspace once and then left alone, so files added afterwards don't
appear in it -- `ralph clean workspace` reseeds if you get the order wrong.

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
ralph policy   <ls|edit|sync|test HOST|reset>
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

## Known limits

Worth reading before you rely on this.

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

## Troubleshooting

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
  ralph install.sh yolo-run.sh entrypoint.sh loop.sh
```

## License

MIT. See [LICENSE](LICENSE).
