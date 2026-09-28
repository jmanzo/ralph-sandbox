# The loop

`ralph loop` is the part you leave running; the sandbox is what makes
leaving it running reasonable. This is the reference for what a run does,
what stops it, and what it leaves behind. The [README](../README.md) has the
quick start.

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

