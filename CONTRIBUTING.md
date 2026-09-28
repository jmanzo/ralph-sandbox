# Contributing

Thanks for looking. This is a small project with a specific shape -- a
Dockerfile, a proxy config, and two shell scripts -- and most of the value is
in it staying that way. Before a large change, open an issue and say what you
have in mind; before a change to the security boundary, always.

## What kind of change goes where

| Change | Do this first |
| --- | --- |
| Typo, doc fix, clearer error message | Just send the PR |
| New `RALPH_*` variable or `ralph` subcommand | Open an issue, or comment on an existing one |
| Anything in `proxy/`, `policy/`, the `docker run` line in `ralph`, `entrypoint.sh` | Open an issue; it is the boundary |
| A new provider, a new notification channel | There are issues for these; comment there |
| Reformatting, restructuring, "cleanup" | Please don't, unless an issue asked for it |

The *Known limits* section of `docs/security.md` is deliberate. A PR that quietly closes one
of those gaps is welcome; one that quietly opens a new one is not, however
convenient the feature.

## Setting up

```bash
git clone https://github.com/jmanzo/ralph-sandbox.git
cd ralph-sandbox
./install.sh          # symlinks ralph into ~/.local/bin
ralph build           # builds both images from the pinned versions
```

You need Docker and `bash`. On macOS the system bash 3.2 must be able to run
`ralph` and `install.sh`; `loop.sh` and `entrypoint.sh` run inside the
container on bash 5.

## Checks

CI runs four jobs. Run the first two before every push; the others take a
few minutes and are worth running for anything that touches the images.

```bash
# 1. shellcheck, warning-free
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  ralph install.sh yolo-run.sh entrypoint.sh loop.sh proxy/entrypoint.sh

# 2. ASCII only, in shell and config files
! LC_ALL=C grep -nP '[^\x00-\x7F]' \
    ralph install.sh yolo-run.sh entrypoint.sh loop.sh \
    Dockerfile proxy/Dockerfile proxy/entrypoint.sh proxy/tinyproxy.conf \
    policy/default.allowlist

# 3. the images build and the sandbox tests pass
ralph build
# then run the steps of the `build` job in .github/workflows/ci.yml you touched

# 4. the loop driver, without Docker: each step in the `loop` job is a
#    self-contained scenario driving loop.sh with a fake agent
```

The behavioural tests live as steps in `.github/workflows/ci.yml` for now
(issue #20 tracks moving them into a `tests/` directory). Each step is written
to run on its own: copy it into a shell, or run the job with
[act](https://github.com/nektos/act).

## Rules for the shell

- **Host scripts run on bash 3.2.** `ralph` and `install.sh`: no associative
  arrays, no `${var,,}`, no `mapfile`, no `read -d ''`. Arrays and `[[ ]]` are
  fine. Container scripts (`loop.sh`, `entrypoint.sh`) may use bash 5.
- **ASCII only.** No smart quotes, no em dashes, no box-drawing characters in
  anything that runs. Markdown may use what it likes.
- **shellcheck clean.** A `# shellcheck disable=` needs a comment saying why.
- **`set -euo pipefail`** stays on. Write `cmd || rc=$?` rather than turning
  it off.
- **Every `RALPH_*` variable** is declared at the top of `ralph` with its
  default, passed to the container in `cmd_run` if the loop needs it, listed
  in `ralph status` if it changes what a run does, and documented in
  `docs/configuration.md` and `cmd_help`.
- **Nothing new enters the sandbox** -- no mount, no environment variable, no
  network -- without a sentence in the README saying it does and why.

## Comments

This codebase explains *why*, not *what*. The reader can see what the line
does; the comment is for the decision behind it and the failure that would
happen without it. Look at any function in `loop.sh` before writing one. A
comment that restates the code is removed in review; a comment that records
"found by running it for real" is kept forever.

Prose in the README and the templates has a voice. Match it rather than
adding a section in a different one; if unsure, keep it shorter.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary):

```
feat: hand the loop to codex when anthropic runs out of road
fix: keep quoting in RALPH_DOCKER_ARGS
docs: split the README into a docs directory
ci: scan both images with trivy
build: pin base images by digest
test: make the gitconfig test exercise the mismatch it is named for
chore: add CODEOWNERS
```

One change per commit, in the present tense, describing the behaviour and
not the diff. The body, when there is one, says why. A PR can have several
commits; it should not have one commit that does several things.

## Pull requests

The PR template has the checklist. In short: the checks above pass, the docs
say what the code now does, and a change to the boundary comes with a test
that fails without it. Small PRs get reviewed quickly; large ones get asked
to split.

Everything here is MIT. By contributing you agree your work is too.
