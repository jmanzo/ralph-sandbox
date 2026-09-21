# Working in this repository

This file is the one set of instructions for every coding agent and every
editor assistant that opens this repo: Codex reads it directly, `CLAUDE.md`
imports it for Claude Code, `.cursor/rules/` and
`.github/copilot-instructions.md` point here. Change it here and nowhere else.

It is not the `CLAUDE.md`/`AGENTS.md` that `ralph init` scaffolds into a
user's project; those live in `templates/` and are shipped, not followed.

## What this is

`ralph` runs a coding agent in yolo mode inside a locked-down container and
drives it with the Ralph loop. It is deliberately small: a Dockerfile, a
proxy config, and two shell scripts. Read `README.md` first, then
`docs/security.md`; both are short and they are the spec.

```
ralph                 host CLI: build, run, loop, login, policy, snapshot, ...
loop.sh               the loop driver; runs INSIDE the sandbox as ralph-loop
entrypoint.sh         container entrypoint: seeds clone mode, exports secrets
Dockerfile            the sandbox image (ubuntu + node + both agent CLIs)
proxy/                egress proxy image (alpine + tinyproxy) and its config
policy/               the shipped default allowlist (single source of truth)
templates/            what `ralph init` lays down in a user's project
docs/                 configuration, loop, security, troubleshooting
.github/workflows/    CI: shellcheck, loop tests, image build + boundary tests
```

## Rules

Hard rules; a PR that breaks one is not merged.

1. **The boundary is the product.** Nothing new enters the sandbox -- no
   mount, no environment variable, no network, no host on the default
   allowlist -- without a sentence in the README saying it does and why, and
   a CI test in the `build` job proving the boundary still holds. Never mount
   the Docker socket. Never widen `policy/default.allowlist` for convenience.
2. **Do not weaken a guardrail to make a test pass.** The loop's stall,
   three-strikes, spend-ceiling and limit checks in `loop.sh` exist to stop
   money being spent; each has a CI scenario. Change the scenario when the
   behaviour changes on purpose, never to get green.
3. **Host shell runs on bash 3.2.** `ralph` and `install.sh` must work on the
   macOS system bash: no associative arrays, no `${var,,}`, no `mapfile`.
   `loop.sh` and `entrypoint.sh` run inside the container on bash 5.
4. **ASCII only in anything that runs.** Shell, Dockerfiles, proxy config,
   allowlist. CI greps for it.
5. **shellcheck warning-free.** Any `# shellcheck disable=` carries a comment
   saying why.
6. **`set -euo pipefail` stays.** Use `cmd || rc=$?`, not `set +e`.
7. **A `RALPH_*` variable is declared once**, at the top of `ralph` with its
   default and a comment; passed to the container in `cmd_run` if `loop.sh`
   reads it; shown by `ralph status` if it changes what a run does; listed in
   `docs/configuration.md` and in `cmd_help`.
8. **Never rewrite history.** No `commit --amend`, no rebase of pushed
   commits, no force push. `main` is protected; work on a branch.
9. **Leave `templates/` alone unless the task is about them.** They are what
   every user's project is scaffolded from; a change there reaches every loop
   anyone runs, and the prompts are tuned by running them.

## Style

- Comments explain **why**, and what would go wrong without the line. The
  reader can see what the code does. Read any function in `loop.sh` before
  writing a comment; match that. A comment that restates the code is noise.
- The README and `docs/` have a voice: plain, specific, no hype, honest about
  limits. Add to it in the same voice or keep it shorter.
- Prefer what the file already does over what you would have chosen. Helper
  names, `die`/`warn`/`info`, `cmd_*` functions, `local` everywhere.
- No new dependencies on the host beyond `docker`, `bash`, `git`, `curl`.
  `jq` is optional on the host and present in the image.

## Verifying a change

```bash
# always, before committing
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  ralph install.sh yolo-run.sh entrypoint.sh loop.sh proxy/entrypoint.sh
! LC_ALL=C grep -nP '[^\x00-\x7F]' ralph install.sh yolo-run.sh entrypoint.sh \
    loop.sh Dockerfile proxy/Dockerfile proxy/entrypoint.sh proxy/tinyproxy.conf \
    policy/default.allowlist

# loop.sh changes: the `loop` job in .github/workflows/ci.yml is a set of
# self-contained scenarios that drive loop.sh with a fake agent script and
# need no Docker. Run the ones you touched, and add one for new behaviour.

# image, proxy, entrypoint or docker-run changes: `ralph build`, then the
# relevant steps of the `build` job. They need Docker and a few minutes.
```

Report what you ran and what it printed. "Tests pass" is not a result.

## Commits and PRs

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary),
one change per commit, present tense, describing behaviour rather than the
diff. Types in use: `feat`, `fix`, `docs`, `ci`, `build`, `test`, `chore`,
`refactor`. Fill in the PR template; the checklist is the review.

## Where the plans are

Open issues are the roadmap. Before proposing a feature, check them; many
obvious next steps already have one with a design sketched in. Ideas outside
the current task go in an issue, not in the code.
